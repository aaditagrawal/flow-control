import Foundation
@preconcurrency import IOKit.hid

@_silgen_name("IOHIDCheckAccess")
private func hidCheckAccess(_ requestType: Int32) -> Int32

@_silgen_name("IOHIDRequestAccess")
private func hidRequestAccess(_ requestType: Int32) -> Bool

final class FlowHIDService: FlowDeviceClient, @unchecked Sendable {
    private let stateLock = NSLock()
    private let transactionLock = NSLock()
    /// Keeps complete configuration reads and writes from interleaving while
    /// individual HID reports are also serialized by `transactionLock`.
    private let configurationLock = NSLock()
    private let responseCondition = NSCondition()

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputThread: Thread?
    private var inputRunLoop: CFRunLoop?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var expectedCommand: UInt8?
    private var pendingResponse: [UInt8]?
    private var cachedIdentity: FlowDeviceIdentity?
    private static let inputBufferSize = 21

    var isConnected: Bool {
        stateLock.withLock { device != nil }
    }

    deinit {
        disconnect()
    }

    func connect() async throws -> FlowDeviceIdentity {
        // macOS protects report access behind Input Monitoring. Ask through the
        // public IOHID access API before attempting to open the vendor channel.
        let listenEventRequest: Int32 = 1
        let grantedAccess: Int32 = 0
        if hidCheckAccess(listenEventRequest) != grantedAccess {
            _ = hidRequestAccess(listenEventRequest)
            guard hidCheckAccess(listenEventRequest) == grantedAccess else {
                throw FlowDeviceError.inputMonitoringPermissionRequired
            }
        }
        return try await Task.detached { [self] in
            if isConnected { return try readIdentityBlocking() }
            return try connectBlocking()
        }.value
    }

    func disconnect() {
        let resources = stateLock.withLock { () -> (IOHIDManager?, IOHIDDevice?, CFRunLoop?, UnsafeMutablePointer<UInt8>?, Thread?) in
            let resources = (manager, device, inputRunLoop, inputBuffer, inputThread)
            manager = nil
            device = nil
            inputRunLoop = nil
            inputThread = nil
            inputBuffer = nil
            cachedIdentity = nil
            return resources
        }
        responseCondition.withLock {
            expectedCommand = nil
            pendingResponse = nil
            responseCondition.broadcast()
        }
        if let runLoop = resources.2 { CFRunLoopStop(runLoop) }
        let threadDeadline = Date().addingTimeInterval(0.5)
        while resources.4?.isExecuting == true, Date() < threadDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if let device = resources.1 {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager = resources.0 {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        resources.3?.deallocate()
    }

    func readIdentity() async throws -> FlowDeviceIdentity {
        try await Task.detached { [self] in try readIdentityBlocking() }.value
    }

    func readConfiguration() async throws -> KeyboardConfiguration {
        try await Task.detached { [self] in
            try configurationLock.withLock { try readConfigurationBlocking() }
        }.value
    }

    func writeConfiguration(_ configuration: KeyboardConfiguration) async throws {
        try await Task.detached { [self, configuration] in
            try configurationLock.withLock { try writeConfigurationBlocking(configuration) }
        }.value
    }

    func applyConfiguration(
        _ configuration: KeyboardConfiguration,
        baseline: KeyboardConfiguration,
        changes: ConfigurationChangeSet
    ) async throws -> KeyboardConfiguration {
        try await Task.detached { [self, configuration, baseline, changes] in
            try configurationLock.withLock {
                try applyConfigurationBlocking(
                    configuration,
                    baseline: baseline,
                    changes: changes
                )
            }
        }.value
    }

    /// Reads one mode's verified four-byte effect header without changing the
    /// active mode. Used by diagnostics and by reversible hardware tests.
    func readLightingEffect(mode: UInt8) async throws -> FlowProtocol.LightEffect {
        guard mode < 16 else {
            throw FlowDeviceError.protectedOperation
        }
        return try await Task.detached { [self] in
            try configurationLock.withLock {
                guard isConnected else { throw FlowDeviceError.notConnected }
                let address = FlowProtocol.Address.effectParameters + Int(mode) * 32
                return try FlowProtocol.decodeLightEffect(readFlash(address: address, length: 4))
            }
        }.value
    }

    /// Returns one complete ordinary effect record for read-only diagnostics.
    /// Keeping this separate from writes lets tests inspect firmware slots that
    /// a particular Windows configuration does not expose in its picker.
    func readLightingEffectRecord(mode: UInt8) async throws -> [UInt8] {
        guard mode < 16 else {
            throw FlowDeviceError.protectedOperation
        }
        return try await Task.detached { [self] in
            try configurationLock.withLock {
                guard isConnected else { throw FlowDeviceError.notConnected }
                let address = FlowProtocol.Address.effectParameters + Int(mode) * 32
                return try readFlash(address: address, length: 32)
            }
        }.value
    }

    /// Reads the 128 ten-byte per-slot custom-light records without writing
    /// them. The format is shared by the official web and Windows clients.
    func readCustomLightingRecords() async throws -> [[UInt8]] {
        try await Task.detached { [self] in
            try configurationLock.withLock {
                guard isConnected else { throw FlowDeviceError.notConnected }
                let bytes = try readFlash(
                    address: FlowProtocol.Address.customLightMaps,
                    length: 128 * 10
                )
                return stride(from: 0, to: bytes.count, by: 10).map {
                    Array(bytes[$0..<($0 + 10)])
                }
            }
        }.value
    }

    /// Selects an ordinary firmware effect slot for a short-lived integration
    /// probe. Production writes remain constrained to the verified picker.
    func selectLightingModeForDiagnostics(_ mode: UInt8) async throws {
        guard mode < 16 else {
            throw FlowDeviceError.protectedOperation
        }
        try await Task.detached { [self] in
            try configurationLock.withLock {
                guard isConnected else { throw FlowDeviceError.notConnected }
                try writeFlash(
                    address: FlowProtocol.Address.currentLightMode,
                    data: FlowProtocol.complementPair(mode)
                )
            }
        }.value
    }

    // MARK: - Connection

    private func connectBlocking() throws -> FlowDeviceIdentity {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: FlowProtocol.vendorID,
            kIOHIDProductIDKey: FlowProtocol.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw FlowDeviceError.configurationInterfaceMissing
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: Self.isExactConfigurationDevice) else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw FlowDeviceError.deviceNotFound
        }
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw FlowDeviceError.configurationInterfaceMissing
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        buffer.initialize(repeating: 0, count: Self.inputBufferSize)
        stateLock.withLock {
            self.manager = manager
            self.device = device
            self.inputBuffer = buffer
        }
        startInputLoop()

        do {
            // Give the dedicated run loop a bounded window to install the callback.
            let deadline = Date().addingTimeInterval(0.25)
            while stateLock.withLock({ inputRunLoop == nil }), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            let identity = try readIdentityBlocking()
            guard identity.transportType.map({ $0 == 2 || $0 == 3 }) == true else {
                throw FlowDeviceError.unsupportedDevice("the configuration channel is not wired")
            }
            stateLock.withLock { cachedIdentity = identity }
            return identity
        } catch {
            disconnect()
            throw error
        }
    }

    private static func isExactConfigurationDevice(_ device: IOHIDDevice) -> Bool {
        integerProperty(kIOHIDVendorIDKey, on: device) == FlowProtocol.vendorID &&
            integerProperty(kIOHIDProductIDKey, on: device) == FlowProtocol.productID &&
            integerProperty(kIOHIDPrimaryUsagePageKey, on: device) == 0x0C &&
            integerProperty(kIOHIDMaxInputReportSizeKey, on: device) == 21 &&
            integerProperty(kIOHIDMaxOutputReportSizeKey, on: device) == 20 &&
            hasConfigurationReportElement(device)
    }

    private static func hasConfigurationReportElement(_ device: IOHIDDevice) -> Bool {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return false }
        return elements.contains { element in
            guard IOHIDElementGetReportID(element) == FlowProtocol.reportID else { return false }
            var cursor: IOHIDElement? = element
            while let current = cursor {
                if IOHIDElementGetUsagePage(current) == FlowProtocol.usagePage,
                   IOHIDElementGetUsage(current) == FlowProtocol.usage {
                    return true
                }
                cursor = IOHIDElementGetParent(current)
            }
            return false
        }
    }

    private static func integerProperty(_ key: String, on device: IOHIDDevice) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func stringProperty(_ key: String, on device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func startInputLoop() {
        let thread = Thread { [weak self] in
            guard let self,
                  let device = stateLock.withLock({ self.device }),
                  let buffer = stateLock.withLock({ self.inputBuffer }) else { return }
            guard let runLoop = CFRunLoopGetCurrent() else { return }
            stateLock.withLock { inputRunLoop = runLoop }
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buffer,
                Self.inputBufferSize,
                Self.inputReportCallback,
                context
            )
            IOHIDDeviceRegisterRemovalCallback(device, Self.removalCallback, context)
            IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopRun()
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }
        thread.name = "FlowControl.HIDInput"
        stateLock.withLock { inputThread = thread }
        thread.start()
    }

    private static let inputReportCallback: IOHIDReportCallback = {
        context, result, _, _, reportID, report, reportLength in
        guard result == kIOReturnSuccess,
              reportID == FlowProtocol.reportID,
              let context else { return }
        let service = Unmanaged<FlowHIDService>.fromOpaque(context).takeUnretainedValue()
        let received = Array(UnsafeBufferPointer(start: report, count: reportLength))
        if received.count == FlowProtocol.reportLength {
            service.receive(received)
        } else if received.count == FlowProtocol.reportLength + 1,
                  received.first == UInt8(FlowProtocol.reportID) {
            service.receive(Array(received.dropFirst()))
        }
    }

    private static let removalCallback: IOHIDCallback = { context, _, _ in
        guard let context else { return }
        let service = Unmanaged<FlowHIDService>.fromOpaque(context).takeUnretainedValue()
        service.stateLock.withLock {
            service.device = nil
            service.cachedIdentity = nil
        }
        service.responseCondition.withLock { service.responseCondition.broadcast() }
    }

    private func receive(_ bytes: [UInt8]) {
        responseCondition.withLock {
            guard bytes.count == FlowProtocol.reportLength,
                  bytes.first == expectedCommand else { return }
            pendingResponse = bytes
            responseCondition.signal()
        }
    }

    // MARK: - Report transport

    private func transact(_ report: [UInt8]) throws -> [UInt8] {
        var lastTimeout: Error = FlowDeviceError.timedOut("HID report")
        for _ in 0..<5 {
            do {
                return try transactOnce(report, timeout: 0.2)
            } catch {
                guard case FlowDeviceError.timedOut = error else { throw error }
                lastTimeout = error
            }
        }
        throw lastTimeout
    }

    private func transactOnce(_ report: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        guard report.count == FlowProtocol.reportLength, let command = report.first else {
            throw FlowDeviceError.malformedResponse("outgoing report must contain 16 bytes")
        }
        guard FlowProtocol.isValidReport(report) else {
            throw FlowDeviceError.malformedResponse("outgoing report checksum is invalid")
        }
        guard let device = stateLock.withLock({ self.device }) else {
            throw FlowDeviceError.notConnected
        }

        transactionLock.lock()
        defer { transactionLock.unlock() }
        responseCondition.lock()
        expectedCommand = command
        pendingResponse = nil
        // IOHIDDeviceSetReport requires the report ID in both the argument and
        // the first byte when a descriptor contains multiple numbered reports.
        let hidReport = [UInt8(FlowProtocol.reportID)] + report
        let result = hidReport.withUnsafeBytes { pointer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                FlowProtocol.reportID,
                pointer.bindMemory(to: UInt8.self).baseAddress!,
                hidReport.count
            )
        }
        guard result == kIOReturnSuccess else {
            expectedCommand = nil
            responseCondition.unlock()
            throw FlowDeviceError.malformedResponse("IOHIDDeviceSetReport failed with code \(result)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while pendingResponse == nil, isConnected {
            guard responseCondition.wait(until: deadline) else { break }
        }
        let response = pendingResponse
        expectedCommand = nil
        pendingResponse = nil
        responseCondition.unlock()
        guard let response else {
            if !isConnected { throw FlowDeviceError.notConnected }
            throw FlowDeviceError.timedOut("command 0x\(String(command, radix: 16))")
        }
        return response
    }

    private func readFlash(address: Int, length: Int) throws -> [UInt8] {
        guard length > 0, address >= 0, address + length <= FlowProtocol.flashSize else {
            throw FlowDeviceError.malformedResponse("flash read is outside the device storage")
        }
        var result: [UInt8] = []
        result.reserveCapacity(length)
        for offset in stride(from: 0, to: length, by: FlowProtocol.flashChunkSize) {
            let count = min(FlowProtocol.flashChunkSize, length - offset)
            let chunkAddress = address + offset
            let command = try FlowProtocol.readFlashCommand(address: chunkAddress, length: count)
            let response = try transact(command)
            let chunk = try FlowProtocol.parseFlashRead(response, expectedAddress: chunkAddress)
            guard chunk.count == count else {
                throw FlowDeviceError.malformedResponse("short flash read at address \(chunkAddress)")
            }
            result.append(contentsOf: chunk)
        }
        return result
    }

    private func writeFlash(address: Int, data: [UInt8], verify: Bool = true) throws {
        guard Self.isOrdinaryConfigurationRange(address: address, length: data.count) else {
            throw FlowDeviceError.protectedOperation
        }
        for report in try FlowProtocol.writeFlashCommands(address: address, data: data) {
            _ = try FlowProtocol.parseResponse(try transact(report), expecting: .writeFlash)
        }
        if verify {
            let readback = try readFlash(address: address, length: data.count)
            guard readback == data else {
                throw FlowDeviceError.writeVerificationFailed("flash readback failed at address \(address)")
            }
        }
    }

    static func isOrdinaryConfigurationRange(address: Int, length: Int) -> Bool {
        guard length > 0 else { return false }
        let requested = address..<(address + length)
        let allowed = [
            0..<1_024,            // Windows normal + Fn keymaps
            1_536..<2_560,        // macOS normal + Fn keymaps
            8_496..<8_502,        // lighting mode, state and off time
            8_544..<9_056,        // 16 ordinary lighting-effect records
            9_408..<9_430,        // polling/system/locks and ordinary settings
            10_064..<15_824,      // 15 macro slots
        ]
        return allowed.contains { requested.lowerBound >= $0.lowerBound && requested.upperBound <= $0.upperBound }
    }

    // MARK: - Identity and configuration

    private func readIdentityBlocking() throws -> FlowDeviceIdentity {
        guard let device = stateLock.withLock({ self.device }) else {
            throw FlowDeviceError.notConnected
        }
        var nonce = [UInt8](repeating: 0, count: 8)
        for index in 0..<4 { nonce[index] = UInt8.random(in: .min ... .max) }
        let rawIdentity = try FlowProtocol.parseIdentity(
            try transact(FlowProtocol.identityCommand(nonce: nonce))
        )
        let version = try FlowProtocol.parseVersion(
            try transact(FlowProtocol.readCommand(.deviceVersion))
        )
        let battery = try? FlowProtocol.parseBattery(
            try transact(FlowProtocol.readCommand(.battery))
        )
        return FlowDeviceIdentity(
            productName: Self.stringProperty(kIOHIDProductKey, on: device) ?? "Flow Lite 84",
            vendorID: Self.integerProperty(kIOHIDVendorIDKey, on: device) ?? FlowProtocol.vendorID,
            productID: Self.integerProperty(kIOHIDProductIDKey, on: device) ?? FlowProtocol.productID,
            deviceVersion: version,
            customerID: rawIdentity.customerID,
            modelID: rawIdentity.modelID,
            transportType: rawIdentity.transportType,
            batteryPercent: battery?.percent
        )
    }

    private func readConfigurationBlocking() throws -> KeyboardConfiguration {
        guard isConnected else { throw FlowDeviceError.notConnected }
        let slots = FlowDefaults.firmwareKeySlots
        guard slots.count == FlowDefaults.physicalKeys.count,
              slots.allSatisfy({ (0..<128).contains($0.flashIndex) }) else {
            throw FlowDeviceError.malformedResponse("physical key map has missing or invalid firmware slots")
        }

        var keymaps: [KeyboardSystem: [KeyboardLayer: [String: KeyAction]]] = [:]
        for system in KeyboardSystem.allCases {
            var layers: [KeyboardLayer: [String: KeyAction]] = [:]
            for layer in KeyboardLayer.allCases {
                let bytes = try readFlash(
                    address: FlowProtocol.keymapLayerAddress(system: system, layer: layer),
                    length: 512
                )
                var assignments: [String: KeyAction] = [:]
                for slot in slots {
                    let offset = slot.flashIndex * 4
                    let raw = try FlowProtocol.decodeKeyAssignment(Array(bytes[offset..<(offset + 4)]))
                    assignments[slot.key.id] = FlowDefaults.action(family: raw.family, value: raw.value)
                }
                layers[layer] = assignments
            }
            keymaps[system] = layers
        }

        let lightingBytes = try readFlash(address: FlowProtocol.Address.currentLightMode, length: 6)
        let lightingState = try FlowProtocol.decodeLightingState(lightingBytes)
        let effectIndex = min(Int(lightingState.mode), 15)
        let effectBytes = try readFlash(
            address: FlowProtocol.Address.effectParameters + effectIndex * 32,
            length: 4
        )
        let effect = try FlowProtocol.decodeLightEffect(effectBytes)

        var macros: [KeyboardMacro] = []
        for slot in 0..<15 {
            let bytes = try readFlash(address: FlowProtocol.Address.macros + slot * 384, length: 384)
            if let record = try FlowProtocol.decodeMacro(bytes) {
                macros.append(KeyboardMacro(
                    id: slot,
                    name: record.name,
                    events: record.events.map { event in
                        let action = FlowDefaults.action(family: event.family, value: event.value)
                        return MacroEvent(
                            state: event.status == 0 ? .pressed : .released,
                            family: event.family,
                            value: event.value,
                            label: action.label,
                            delayMilliseconds: event.delayMilliseconds
                        )
                    }
                ))
            } else {
                macros.append(KeyboardMacro(id: slot, name: "Macro \(slot + 1)", events: []))
            }
        }

        // Keymaps are read before macro records. Once names are available,
        // replace only their display metadata so assigned keys show the
        // user's macro name while preserving the exact device bytes.
        for system in KeyboardSystem.allCases {
            for layer in KeyboardLayer.allCases {
                guard let assignments = keymaps[system]?[layer] else { continue }
                for (keyID, assignment) in assignments where assignment.family == 0x08 {
                    let slot = Int(assignment.value & 0x00ff)
                    guard let macro = macros.first(where: { $0.id == slot }) else { continue }
                    keymaps[system]?[layer]?[keyID] = FlowDefaults.macroAction(
                        slot: slot,
                        repeatCount: UInt8(assignment.value >> 8),
                        name: macro.name
                    )
                }
            }
        }

        let settings = try readFlash(address: FlowProtocol.Address.reportRate, length: 22)
        let polling = try FlowProtocol.pollingRate(from: FlowProtocol.decodeComplementPair(Array(settings[0..<2])))
        let currentSystemRaw = try FlowProtocol.decodeComplementPair(Array(settings[8..<10]))
        let fnLock = try FlowProtocol.decodeComplementPair(Array(settings[10..<12]))
        let fullLock = try FlowProtocol.decodeComplementPair(Array(settings[12..<14]))

        return KeyboardConfiguration(
            keymaps: keymaps,
            lighting: LightingConfiguration(
                mode: lightingState.mode,
                isEnabled: lightingState.isEnabled,
                brightness: effect.brightness,
                speed: effect.speed,
                offTime: lightingState.offTime
            ),
            macros: macros,
            device: DeviceConfiguration(
                pollingRate: polling,
                currentSystem: currentSystemRaw == 1 ? .mac : .windows,
                fnLock: fnLock == 1,
                fullKeyboardLock: fullLock == 1
            )
        )
    }

    private func writeConfigurationBlocking(_ configuration: KeyboardConfiguration) throws {
        guard isConnected else { throw FlowDeviceError.notConnected }
        let current = try readConfigurationBlocking()
        _ = try applyConfigurationBlocking(configuration, baseline: current, changes: .all)
    }

    /// Applies only the sections the store compared with its last live device
    /// snapshot. Every changed record is verified by `writeFlash`; unchanged
    /// keymaps and macros are not reread merely to discover that they match.
    private func applyConfigurationBlocking(
        _ configuration: KeyboardConfiguration,
        baseline: KeyboardConfiguration,
        changes: ConfigurationChangeSet
    ) throws -> KeyboardConfiguration {
        guard isConnected else { throw FlowDeviceError.notConnected }
        try validateForOrdinaryWrite(configuration)
        let actualChanges = configuration.changes(comparedTo: baseline)
        guard actualChanges.isSubset(of: changes) else {
            throw FlowDeviceError.malformedResponse("apply scope omits edited configuration sections")
        }

        var verified = baseline
        let slots = FlowDefaults.firmwareKeySlots

        if changes.contains(.keymaps) {
            var wroteActiveKeymap = false
            for system in KeyboardSystem.allCases {
                for layer in KeyboardLayer.allCases {
                    for slot in slots {
                        guard let requested = configuration.keymaps[system]?[layer]?[slot.key.id],
                              let existing = baseline.keymaps[system]?[layer]?[slot.key.id],
                              requested.family != existing.family || requested.value != existing.value else { continue }
                        let bytes = FlowProtocol.encodeKeyAssignment(family: requested.family, value: requested.value)
                        let address = FlowProtocol.keymapLayerAddress(system: system, layer: layer) + slot.flashIndex * 4
                        try writeFlash(address: address, data: bytes)
                        if system == configuration.device.currentSystem {
                            wroteActiveKeymap = true
                        }
                    }
                }
            }
            // Key assignments live in flash, while the firmware scans from its
            // active runtime map. Reasserting the already-selected system makes
            // the firmware reload that map without switching the user's mode.
            if wroteActiveKeymap {
                let activeSystemValue: UInt8 = configuration.device.currentSystem == .mac ? 1 : 0
                let encodedSystem = try FlowProtocol.complementPair(activeSystemValue)
                try writeFlash(address: FlowProtocol.Address.currentSystem, data: encodedSystem)
                let confirmedSystem = try readFlash(address: FlowProtocol.Address.currentSystem, length: 2)
                guard confirmedSystem == encodedSystem else {
                    throw FlowDeviceError.writeVerificationFailed("the active keyboard system did not reload")
                }
            }
            verified.keymaps = configuration.keymaps
        }

        // Effect levels belong to the selected mode. Write the target mode's
        // four-byte header before switching modes so final readback matches
        // the configuration the user requested.
        if changes.contains(.lighting) {
            if configuration.lighting.mode != baseline.lighting.mode ||
                configuration.lighting.speed != baseline.lighting.speed ||
                configuration.lighting.brightness != baseline.lighting.brightness {
                let address = FlowProtocol.Address.effectParameters + Int(configuration.lighting.mode) * 32
                let original = try readFlash(address: address, length: 4)
                let changed = try FlowProtocol.lightEffectHeader(
                    original,
                    speed: configuration.lighting.speed,
                    brightness: configuration.lighting.brightness
                )
                try writeFlash(address: address, data: changed)
            }
            if configuration.lighting.mode != baseline.lighting.mode {
                try writeFlash(
                    address: FlowProtocol.Address.currentLightMode,
                    data: FlowProtocol.encodeLightingSelection(
                        mode: configuration.lighting.mode,
                        isEnabled: configuration.lighting.isEnabled
                    )
                )
            }
            if configuration.lighting.mode == baseline.lighting.mode,
               configuration.lighting.isEnabled != baseline.lighting.isEnabled {
                try writeFlash(
                    address: FlowProtocol.Address.lightState,
                    data: FlowProtocol.complementPair(configuration.lighting.isEnabled ? 1 : 0)
                )
            }
            if configuration.lighting.offTime != baseline.lighting.offTime {
                try writeFlash(
                    address: FlowProtocol.Address.offLightTime,
                    data: FlowProtocol.complementPair(configuration.lighting.offTime)
                )
            }
            verified.lighting = configuration.lighting
        }

        if changes.contains(.macros) {
            for slot in 0..<15 {
                guard let requested = configuration.macros.first(where: { $0.id == slot }),
                      let existing = baseline.macros.first(where: { $0.id == slot }),
                      !macroRecordEquivalent(requested, existing) else { continue }
                if requested.events.isEmpty {
                    try writeFlash(
                        address: FlowProtocol.Address.macros + slot * 384,
                        data: [UInt8](repeating: 0, count: 384)
                    )
                    continue
                }
                let record = FlowProtocol.MacroRecord(
                    name: requested.name,
                    events: requested.events.map {
                        FlowProtocol.MacroRecord.Event(
                            status: $0.state == .pressed ? 0 : 1,
                            family: $0.family,
                            value: $0.value,
                            delayMilliseconds: $0.delayMilliseconds
                        )
                    }
                )
                try writeFlash(
                    address: FlowProtocol.Address.macros + slot * 384,
                    data: FlowProtocol.encodeMacro(record)
                )
            }
            verified.macros = configuration.macros
        }

        if changes.contains(.device) {
            if configuration.device.pollingRate != baseline.device.pollingRate {
                let encoded = try FlowProtocol.pollingRateEncoding(for: configuration.device.pollingRate)
                try writeFlash(address: FlowProtocol.Address.reportRate, data: FlowProtocol.complementPair(encoded))
            }
            if configuration.device.currentSystem != baseline.device.currentSystem {
                let value: UInt8 = configuration.device.currentSystem == .mac ? 1 : 0
                try writeFlash(address: FlowProtocol.Address.currentSystem, data: FlowProtocol.complementPair(value))
            }
            if configuration.device.fnLock != baseline.device.fnLock {
                try writeFlash(
                    address: FlowProtocol.Address.fnLock,
                    data: FlowProtocol.complementPair(configuration.device.fnLock ? 1 : 0)
                )
            }
            if configuration.device.fullKeyboardLock != baseline.device.fullKeyboardLock {
                try writeFlash(
                    address: FlowProtocol.Address.fullKeyLock,
                    data: FlowProtocol.complementPair(configuration.device.fullKeyboardLock ? 1 : 0)
                )
            }
            verified.device = configuration.device
        }

        return verified
    }

    private func validateForOrdinaryWrite(_ configuration: KeyboardConfiguration) throws {
        guard FlowDefaults.supportedLightingModeValues.contains(configuration.lighting.mode),
              configuration.lighting.brightness <= 4,
              configuration.lighting.speed <= 4 else {
            throw FlowDeviceError.protectedOperation
        }
        _ = try FlowProtocol.pollingRateEncoding(for: configuration.device.pollingRate)
        for macro in configuration.macros {
            if !macro.events.isEmpty {
                let record = FlowProtocol.MacroRecord(
                    name: macro.name,
                    events: macro.events.map {
                        .init(
                            status: $0.state == .pressed ? 0 : 1,
                            family: $0.family,
                            value: $0.value,
                            delayMilliseconds: $0.delayMilliseconds
                        )
                    }
                )
                _ = try FlowProtocol.encodeMacro(record)
            }
        }
    }

    private func macroRecordEquivalent(_ lhs: KeyboardMacro, _ rhs: KeyboardMacro) -> Bool {
        guard lhs.events.count == rhs.events.count else { return false }
        if !lhs.events.isEmpty, lhs.name != rhs.name { return false }
        return zip(lhs.events, rhs.events).allSatisfy { lhsEvent, rhsEvent in
            lhsEvent.state == rhsEvent.state &&
                lhsEvent.family == rhsEvent.family &&
                lhsEvent.value == rhsEvent.value &&
                lhsEvent.delayMilliseconds == rhsEvent.delayMilliseconds
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
