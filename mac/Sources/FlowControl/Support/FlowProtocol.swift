import Foundation

enum FlowProtocol {
    static let vendorID = 0x05AC
    static let productID = 0x024F
    static let usagePage = 0xFF02
    static let usage = 0x0002
    static let reportID: CFIndex = 0x08
    static let reportLength = 16
    static let flashSize = 16_384
    static let flashChunkSize = 10

    enum Command: UInt8 {
        case identity = 0x01
        case online = 0x03
        case battery = 0x04
        case writeFlash = 0x07
        case readFlash = 0x08
        case currentProfile = 0x0E
        case deviceVersion = 0x12
    }

    enum Address {
        static let customLightMaps = 6_176
        static let currentLightMode = 8_496
        static let lightState = 8_498
        static let offLightTime = 8_500
        static let effectParameters = 8_544
        static let reportRate = 9_408
        static let currentSystem = 9_416
        static let fnLock = 9_418
        static let fullKeyLock = 9_420
        static let macros = 10_064
    }

    struct CommandResponse: Equatable {
        let command: UInt8
        let status: UInt8
        let bytes: [UInt8]

        var isSuccess: Bool { status == 0 }
    }

    struct Identity: Equatable {
        let customerID: UInt8
        let modelID: UInt8
        let transportType: UInt8

        var isWired: Bool { transportType == 2 || transportType == 3 }
    }

    struct Battery: Equatable {
        let percent: Int
        let isCharging: Bool
        let voltageMillivolts: Int
    }

    struct KeyAssignment: Equatable {
        let rawFamily: UInt8
        let value: UInt16

        /// The official client uses flag bits in the high nibble for some records.
        var family: UInt8 { rawFamily & 0x0F }
    }

    struct LightingState: Equatable {
        let mode: UInt8
        let isEnabled: Bool
        let offTime: UInt8
    }

    struct LightEffect: Equatable {
        let speed: UInt8
        let brightness: UInt8
    }

    struct MacroRecord: Equatable {
        struct Event: Equatable {
            /// Official client values: 0 is press and 1 is release.
            let status: UInt8
            let family: UInt8
            let value: UInt16
            let delayMilliseconds: UInt16
        }

        let name: String
        let events: [Event]
    }

    static func dataChecksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        let sum = bytes.reduce(0) { ($0 + Int($1)) & 0xFF }
        return UInt8((0x55 - sum) & 0xFF)
    }

    static func finalize(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count == reportLength else {
            throw FlowDeviceError.malformedResponse("report payload must contain 16 bytes")
        }
        var result = bytes
        result[15] = UInt8((Int(dataChecksum(result.prefix(15))) - Int(reportID)) & 0xFF)
        return result
    }

    static func isValidReport(_ bytes: [UInt8]) -> Bool {
        bytes.count == reportLength &&
            ((bytes.reduce(0) { $0 + Int($1) } + Int(reportID)) & 0xFF) == 0x55
    }

    static func readCommand(_ command: Command) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = command.rawValue
        bytes[4] = 0x80
        return try finalize(bytes)
    }

    static func writeCommand(_ command: Command, data: [UInt8]) throws -> [UInt8] {
        guard data.count <= flashChunkSize else {
            throw FlowDeviceError.malformedResponse("command data exceeds 10 bytes")
        }
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = command.rawValue
        bytes[4] = 0x80 + UInt8(data.count)
        bytes.replaceSubrange(5..<(5 + data.count), with: data)
        return try finalize(bytes)
    }

    static func identityCommand(nonce: [UInt8]) throws -> [UInt8] {
        guard nonce.count == 8 else {
            throw FlowDeviceError.malformedResponse("identity nonce must contain 8 bytes")
        }
        return try writeCommand(.identity, data: nonce)
    }

    static func readFlashCommand(address: Int, length: Int) throws -> [UInt8] {
        guard address >= 0, length > 0, length <= flashChunkSize,
              address + length <= flashSize else {
            throw FlowDeviceError.malformedResponse("flash read is outside the safe address range")
        }
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = Command.readFlash.rawValue
        bytes[2] = UInt8((address >> 8) & 0xFF)
        bytes[3] = UInt8(address & 0xFF)
        bytes[4] = 0x80 + UInt8(length)
        return try finalize(bytes)
    }

    static func writeFlashCommands(address: Int, data: [UInt8]) throws -> [[UInt8]] {
        guard !data.isEmpty, address >= 0, address + data.count <= flashSize else {
            throw FlowDeviceError.protectedOperation
        }
        return try stride(from: 0, to: data.count, by: flashChunkSize).map { offset in
            let count = min(flashChunkSize, data.count - offset)
            let chunkAddress = address + offset
            var bytes = [UInt8](repeating: 0, count: reportLength)
            bytes[0] = Command.writeFlash.rawValue
            bytes[2] = UInt8((chunkAddress >> 8) & 0xFF)
            bytes[3] = UInt8(chunkAddress & 0xFF)
            bytes[4] = 0x80 + UInt8(count)
            bytes.replaceSubrange(5..<(5 + count), with: data[offset..<(offset + count)])
            return try finalize(bytes)
        }
    }

    static func parseResponse(_ bytes: [UInt8], expecting command: Command) throws -> CommandResponse {
        guard bytes.count == reportLength else {
            throw FlowDeviceError.malformedResponse("command response must contain 16 bytes")
        }
        guard bytes[0] == command.rawValue else {
            throw FlowDeviceError.malformedResponse(
                "expected command \(command.rawValue), received \(bytes[0])"
            )
        }
        let response = CommandResponse(command: bytes[0], status: bytes[1], bytes: bytes)
        guard response.isSuccess else {
            throw FlowDeviceError.malformedResponse(
                "command \(response.command) failed with status \(response.status)"
            )
        }
        return response
    }

    static func parseIdentity(_ bytes: [UInt8]) throws -> Identity {
        let response = try parseResponse(bytes, expecting: .identity).bytes
        return Identity(customerID: response[9], modelID: response[10], transportType: response[11])
    }

    static func parseBattery(_ bytes: [UInt8]) throws -> Battery {
        let response = try parseResponse(bytes, expecting: .battery).bytes
        return Battery(
            percent: Int(response[5]),
            isCharging: response[6] == 1,
            voltageMillivolts: Int(response[7]) << 8 | Int(response[8])
        )
    }

    static func parseVersion(_ bytes: [UInt8]) throws -> String {
        let response = try parseResponse(bytes, expecting: .deviceVersion).bytes
        return "v\(response[5]).\(String(format: "%02x", response[6]))"
    }

    static func parseFlashRead(_ bytes: [UInt8], expectedAddress: Int) throws -> [UInt8] {
        let response = try parseResponse(bytes, expecting: .readFlash).bytes
        let address = Int(response[2]) << 8 | Int(response[3])
        guard address == expectedAddress else {
            throw FlowDeviceError.malformedResponse(
                "expected flash address \(expectedAddress), received \(address)"
            )
        }
        // Bit 7 identifies the keyboard endpoint in the official protocol;
        // the low seven bits carry the actual payload length.
        let length = Int(response[4] & 0x7F)
        guard length <= flashChunkSize else {
            throw FlowDeviceError.malformedResponse("invalid flash response length \(length)")
        }
        return Array(response[5..<(5 + length)])
    }

    static func keymapLayerAddress(system: KeyboardSystem, layer: KeyboardLayer) -> Int {
        let systemOffset = system == .windows ? 0 : 1_536
        let layerOffset = layer == .base ? 0 : 512
        return systemOffset + layerOffset
    }

    static func decodeKeyAssignment(_ bytes: [UInt8]) throws -> KeyAssignment {
        guard bytes.count == 4 else {
            throw FlowDeviceError.malformedResponse("key assignment must contain 4 bytes")
        }
        guard bytes[3] == dataChecksum(bytes.prefix(3)) else {
            throw FlowDeviceError.malformedResponse("invalid key assignment checksum")
        }
        return KeyAssignment(rawFamily: bytes[0], value: UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
    }

    static func encodeKeyAssignment(family: UInt8, value: UInt16) -> [UInt8] {
        var bytes = [family, UInt8(value & 0xFF), UInt8(value >> 8), 0]
        bytes[3] = dataChecksum(bytes.prefix(3))
        return bytes
    }

    static func decodeLightingState(_ bytes: [UInt8]) throws -> LightingState {
        guard bytes.count == 6 else {
            throw FlowDeviceError.malformedResponse("lighting state must contain 6 bytes")
        }
        for offset in stride(from: 0, through: 4, by: 2)
        where (Int(bytes[offset]) + Int(bytes[offset + 1])) & 0xFF != 0x55 {
            throw FlowDeviceError.malformedResponse("invalid lighting complement at byte \(offset)")
        }
        return LightingState(mode: bytes[0], isEnabled: bytes[2] == 1, offTime: bytes[4])
    }

    static func encodeLightingState(_ state: LightingState) throws -> [UInt8] {
        try encodeLightingSelection(mode: state.mode, isEnabled: state.isEnabled) + complementPair(state.offTime)
    }

    /// Matches the official mode-selection write: firmware expects the mode
    /// and enabled-state complement pairs together, even when state is already
    /// on. Sending only the two mode bytes can leave an effect engine dormant.
    static func encodeLightingSelection(mode: UInt8, isEnabled: Bool) throws -> [UInt8] {
        let enabled: UInt8 = isEnabled ? 1 : 0
        return try complementPair(mode) + complementPair(enabled)
    }

    static func decodeLightEffect(_ bytes: [UInt8]) throws -> LightEffect {
        guard bytes.count >= 4, bytes[3] == dataChecksum(bytes.prefix(3)) else {
            throw FlowDeviceError.malformedResponse("invalid light effect record")
        }
        return LightEffect(speed: bytes[1], brightness: bytes[2])
    }

    /// Encodes the four-byte effect header used by LoFree's individual
    /// brightness and speed setters. The remaining 28 bytes contain color
    /// records and must not be rewritten for a level-only adjustment.
    static func lightEffectHeader(_ original: [UInt8], speed: UInt8, brightness: UInt8) throws -> [UInt8] {
        guard original.count >= 4, speed <= 4, brightness <= 4 else {
            throw FlowDeviceError.malformedResponse("light effect levels must be between 0 and 4")
        }
        var result = Array(original.prefix(4))
        result[1] = speed
        result[2] = brightness
        result[3] = dataChecksum(result.prefix(3))
        return result
    }

    static func decodeMacro(_ bytes: [UInt8]) throws -> MacroRecord? {
        guard bytes.count == 384 else {
            throw FlowDeviceError.malformedResponse("macro slot must contain 384 bytes")
        }
        let nameLength = Int(bytes[0])
        let eventCount = Int(bytes[31])
        // Erased/unused slots are commonly filled with 0xFF rather than zero.
        if nameLength == 0 || nameLength > 30 || eventCount > 70 { return nil }
        let checksumOffset = 32 + eventCount * 5
        let expectedChecksum = UInt8(
            (Int(dataChecksum(bytes[32..<checksumOffset])) - eventCount) & 0xFF
        )
        guard bytes[checksumOffset] == expectedChecksum else {
            throw FlowDeviceError.malformedResponse("invalid macro checksum")
        }
        guard let name = String(bytes: bytes[1..<(1 + nameLength)], encoding: .utf8) else {
            throw FlowDeviceError.malformedResponse("macro name is not valid UTF-8")
        }
        let events = (0..<eventCount).map { index in
            let offset = 32 + index * 5
            let flags = bytes[offset]
            return MacroRecord.Event(
                status: flags >> 6 == 2 ? 0 : 1,
                family: flags & 0x0F,
                value: UInt16(bytes[offset + 1]) | UInt16(bytes[offset + 2]) << 8,
                delayMilliseconds: UInt16(bytes[offset + 3]) << 8 | UInt16(bytes[offset + 4])
            )
        }
        return MacroRecord(name: name, events: events)
    }

    static func encodeMacro(_ macro: MacroRecord) throws -> [UInt8] {
        let name = Array(macro.name.utf8)
        guard !name.isEmpty, name.count <= 30, macro.events.count <= 70 else {
            throw FlowDeviceError.malformedResponse("macro name or event count exceeds the supported limit")
        }
        var bytes = [UInt8](repeating: 0xFF, count: 33 + macro.events.count * 5)
        bytes[0] = UInt8(name.count)
        bytes.replaceSubrange(1..<(1 + name.count), with: name)
        bytes[31] = UInt8(macro.events.count)
        for (index, event) in macro.events.enumerated() {
            let offset = 32 + index * 5
            bytes[offset] = (event.status == 0 ? 2 : 1) << 6 | (event.family & 0x0F)
            bytes[offset + 1] = UInt8(event.value & 0xFF)
            bytes[offset + 2] = UInt8(event.value >> 8)
            bytes[offset + 3] = UInt8(event.delayMilliseconds >> 8)
            bytes[offset + 4] = UInt8(event.delayMilliseconds & 0xFF)
        }
        let checksumOffset = 32 + macro.events.count * 5
        bytes[checksumOffset] = UInt8(
            (Int(dataChecksum(bytes[32..<checksumOffset])) - macro.events.count) & 0xFF
        )
        return bytes
    }

    static func pollingRate(from encoded: UInt8) throws -> Int {
        guard encoded != 0 else {
            throw FlowDeviceError.malformedResponse("polling-rate divisor cannot be zero")
        }
        return encoded >= 16 ? Int(encoded) / 16 * 2_000 : 1_000 / Int(encoded)
    }

    static func pollingRateEncoding(for rate: Int) throws -> UInt8 {
        let encoded = rate > 1_000 ? rate / 1_000 * 16 : 1_000 / rate
        guard [1, 2, 4, 8].contains(encoded), rate <= 1_000 else {
            // Flow Lite's wired identity advertises 1000 Hz. Higher rates are not safe here.
            throw FlowDeviceError.protectedOperation
        }
        return UInt8(encoded)
    }

    static func complementPair(_ value: UInt8) throws -> [UInt8] {
        [value, UInt8(truncatingIfNeeded: 0x55 - Int(value))]
    }

    static func decodeComplementPair(_ bytes: [UInt8]) throws -> UInt8 {
        guard bytes.count == 2, (Int(bytes[0]) + Int(bytes[1])) & 0xFF == 0x55 else {
            throw FlowDeviceError.malformedResponse("invalid setting complement pair")
        }
        return bytes[0]
    }
}
