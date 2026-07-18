import Foundation
import XCTest
@testable import FlowControl

@MainActor
final class AppStoreTests: XCTestCase {
    func testDirtyStateIgnoresReadbackOnlyMetadata() {
        let store = makeStore(client: FakeFlowDeviceClient())
        var event = MacroEvent(
            state: .pressed,
            family: 0x02,
            value: 0x04,
            label: "A",
            delayMilliseconds: 20
        )
        store.savedConfiguration.macros[0].name = "Typing"
        store.savedConfiguration.macros[0].events = [event]

        event.id = UUID()
        event.label = "A key"
        store.configuration = store.savedConfiguration
        store.configuration.macros[0].events = [event]

        XCTAssertFalse(store.hasUnsavedChanges)

        store.configuration.macros[0].events[0].delayMilliseconds = 21
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testApplyUsesSnapshotAndKeepsEditsMadeWhileWriting() async throws {
        let client = FakeFlowDeviceClient(writeDelayNanoseconds: 150_000_000)
        let store = makeStore(client: client)
        await store.connectAndRead()

        store.configuration.device.pollingRate = 500
        let apply = Task { await store.applyChanges() }
        await waitUntil { client.writeCount == 1 }
        store.configuration.device.fnLock.toggle()
        await apply.value

        XCTAssertEqual(store.savedConfiguration.device.pollingRate, 500)
        XCTAssertFalse(store.savedConfiguration.device.fnLock)
        XCTAssertTrue(store.configuration.device.fnLock)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.connectionState, .ready)
    }

    func testOverlappingApplyIsCoalesced() async throws {
        let client = FakeFlowDeviceClient(writeDelayNanoseconds: 150_000_000)
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.device.pollingRate = 500

        async let first: Void = store.applyChanges()
        async let second: Void = store.applyChanges()
        _ = await (first, second)

        XCTAssertEqual(client.writeCount, 1)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testDisconnectPreventsStaleConnectCompletion() async throws {
        let client = FakeFlowDeviceClient(readDelayNanoseconds: 150_000_000)
        let store = makeStore(client: client)

        let connect = Task { await store.connectAndRead() }
        await waitUntil { store.connectionState == .reading }
        store.disconnect()
        await connect.value

        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertNil(store.identity)
        XCTAssertFalse(store.isConnected)
    }

    func testInvalidLightingImportFailsBeforeWrite() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.lighting.mode = 0xff

        await store.applyChanges()

        XCTAssertEqual(client.writeCount, 0)
        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.contains("not supported"))
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testInvalidShortcutImportFailsBeforeWrite() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.keymaps[.mac]?[.base]?["f12"] = KeyAction(
            family: FlowShortcut.family,
            value: 0x0400,
            label: "Invalid shortcut",
            category: .shortcut
        )

        await store.applyChanges()

        XCTAssertEqual(client.writeCount, 0)
        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.contains("invalid modifier or key"))
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testAssignAndApplyInstallsOnlyTheRequestedKeyAndLeavesOtherEditsPending() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.lighting.brightness = 4
        let shortcut = FlowDefaults.shortcutAction(
            modifierMask: FlowShortcutModifier.control.rawValue | FlowShortcutModifier.shift.rawValue,
            keyUsage: 0x07
        )

        let verified = await store.assignAndApply(
            shortcut,
            system: .mac,
            layer: .base,
            keyID: "print-screen"
        )

        XCTAssertTrue(verified)
        XCTAssertEqual(client.lastChanges, .keymaps)
        XCTAssertEqual(store.savedConfiguration.keymaps[.mac]?[.base]?["print-screen"]?.value, shortcut.value)
        XCTAssertEqual(store.configuration.keymaps[.mac]?[.base]?["print-screen"]?.value, shortcut.value)
        XCTAssertNotEqual(store.savedConfiguration.lighting.brightness, 4)
        XCTAssertEqual(store.configuration.lighting.brightness, 4)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.connectionState, .ready)
    }

    func testAssignAndApplyDoesNotClaimSuccessWhenReadbackDiffers() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        client.corruptNextReadback()
        let shortcut = FlowDefaults.shortcutAction(
            modifierMask: FlowShortcutModifier.control.rawValue | FlowShortcutModifier.shift.rawValue,
            keyUsage: 0x07
        )

        let verified = await store.assignAndApply(
            shortcut,
            system: .mac,
            layer: .base,
            keyID: "print-screen"
        )

        XCTAssertFalse(verified)
        XCTAssertNotEqual(store.savedConfiguration.keymaps[.mac]?[.base]?["print-screen"]?.value, shortcut.value)
        XCTAssertEqual(store.configuration.keymaps[.mac]?[.base]?["print-screen"]?.value, shortcut.value)
        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.contains("readback differs"))
    }

    func testFactoryDefaultCanBeReinstalledForOnlyOneKey() async {
        var customized = FlowDefaults.configuration
        customized.keymaps[.mac]?[.base]?["print-screen"] = FlowDefaults.shortcutAction(
            modifierMask: FlowShortcutModifier.control.rawValue | FlowShortcutModifier.shift.rawValue,
            keyUsage: 0x07
        )
        let client = FakeFlowDeviceClient(configuration: customized)
        let store = makeStore(client: client)
        await store.connectAndRead()
        guard let factoryDefault = FlowDefaults.configuration.keymaps[.mac]?[.base]?["print-screen"] else {
            return XCTFail("Expected factory PrtSc assignment")
        }

        let verified = await store.assignAndApply(
            factoryDefault,
            system: .mac,
            layer: .base,
            keyID: "print-screen"
        )

        XCTAssertTrue(verified)
        XCTAssertEqual(client.lastChanges, .keymaps)
        XCTAssertEqual(
            store.savedConfiguration.keymaps[.mac]?[.base]?["print-screen"]?.value,
            factoryDefault.value
        )
        XCTAssertEqual(store.savedConfiguration.keymaps[.mac]?[.base]?["f12"], customized.keymaps[.mac]?[.base]?["f12"])
    }

    func testConnectPreservesOfflineImportedChanges() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        store.configuration.device.pollingRate = 500

        await store.connectAndRead()

        XCTAssertEqual(store.savedConfiguration.device.pollingRate, 1_000)
        XCTAssertEqual(store.configuration.device.pollingRate, 500)
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testOfflineLightingEditRebasesOntoLiveDeviceWithoutInventingOtherChanges() async {
        var live = FlowDefaults.configuration
        live.device.pollingRate = 125
        live.device.fnLock = true
        live.keymaps[.mac]?[.base]?["escape"] = FlowDefaults.actions[1]
        let client = FakeFlowDeviceClient(configuration: live)
        let store = makeStore(client: client)
        store.configuration.lighting.brightness = 4

        await store.connectAndRead()

        XCTAssertEqual(store.configuration.device, live.device)
        XCTAssertEqual(
            store.configuration.keymaps[.mac]?[.base]?["escape"],
            live.keymaps[.mac]?[.base]?["escape"]
        )
        XCTAssertEqual(store.configuration.lighting.brightness, 4)
        XCTAssertEqual(store.configuration.changes(comparedTo: store.savedConfiguration), .lighting)
    }

    func testReadbackMismatchPreservesBaselineAndAutomaticBackup() async throws {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        let baseline = store.savedConfiguration
        store.configuration.device.pollingRate = 500
        client.corruptNextReadback()

        await store.applyChanges()

        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected failed verification")
        }
        XCTAssertTrue(message.contains("readback differs"))
        XCTAssertTrue(store.savedConfiguration.isDeviceEquivalent(to: baseline))
        XCTAssertTrue(store.hasUnsavedChanges)
        let backupURL = try XCTUnwrap(store.lastBackupURL)
        let backup = try JSONDecoder.flowControl.decode(
            ConfigurationBackup.self,
            from: Data(contentsOf: backupURL)
        )
        XCTAssertTrue(backup.configuration.isDeviceEquivalent(to: baseline))
    }

    func testOfflineApplyConnectsReadsAndContinuesWithoutASecondClick() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        store.configuration.lighting.brightness = 4

        await store.applyChanges()

        XCTAssertEqual(client.connectCount, 1)
        XCTAssertEqual(client.applyCount, 1)
        XCTAssertEqual(client.lastChanges, .lighting)
        XCTAssertEqual(store.savedConfiguration.lighting.brightness, 4)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testSilentDetectionTreatsAbsentKeyboardAsDisconnectedInsteadOfAnError() async {
        let client = FakeFlowDeviceClient(failure: .deviceNotFoundOnConnect)
        let store = makeStore(client: client)

        await store.connectAndRead(silentlyWhenUnavailable: true)

        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertNil(store.identity)
        XCTAssertFalse(store.isConnected)
    }

    func testExplicitApplyReportsAbsentKeyboardAndKeepsOfflineEdit() async {
        let client = FakeFlowDeviceClient(failure: .deviceNotFoundOnConnect)
        let store = makeStore(client: client)
        store.configuration.lighting.speed = 4

        await store.applyChanges()

        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected a visible connection failure")
        }
        XCTAssertTrue(message.contains("No wired Flow Lite 84"))
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(client.applyCount, 0)
    }

    func testDisconnectDuringApplyClearsStaleIdentityAndKeepsBaseline() async {
        let client = FakeFlowDeviceClient(failure: .disconnectDuringWrite)
        let store = makeStore(client: client)
        await store.connectAndRead()
        let baseline = store.savedConfiguration
        store.configuration.device.pollingRate = 500

        await store.applyChanges()

        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected a failed apply")
        }
        XCTAssertTrue(message.contains("not connected"))
        XCTAssertNil(store.identity)
        XCTAssertFalse(store.isConnected)
        XCTAssertTrue(store.savedConfiguration.isDeviceEquivalent(to: baseline))
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testVerificationFailureNamesTheDifferingSection() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.device.pollingRate = 500
        client.corruptNextReadback()

        await store.applyChanges()

        guard case .failed(let message) = store.connectionState else {
            return XCTFail("Expected failed verification")
        }
        XCTAssertTrue(message.contains("device settings"), message)
    }

    func testChangeSetSeparatesEveryPersistedConfigurationArea() {
        let baseline = FlowDefaults.configuration

        var lighting = baseline
        lighting.lighting.speed = lighting.lighting.speed == 4 ? 3 : 4
        XCTAssertEqual(lighting.changes(comparedTo: baseline), .lighting)

        var keymap = baseline
        keymap.keymaps[.mac]?[.base]?["escape"] = FlowDefaults.actions[1]
        XCTAssertEqual(keymap.changes(comparedTo: baseline), .keymaps)

        var macros = baseline
        macros.macros[0].events.append(MacroEvent(
            state: .pressed,
            family: 0x02,
            value: 0x04,
            label: "A",
            delayMilliseconds: 10
        ))
        XCTAssertEqual(macros.changes(comparedTo: baseline), .macros)

        var device = baseline
        device.device.fnLock.toggle()
        XCTAssertEqual(device.changes(comparedTo: baseline), .device)
    }

    func testLightingScopedApplyLeavesOtherEditsPending() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()
        store.configuration.lighting.speed = 4
        store.configuration.device.fnLock.toggle()

        await store.applyChanges(scope: .lighting)

        XCTAssertEqual(client.lastChanges, .lighting)
        XCTAssertEqual(store.savedConfiguration.lighting.speed, 4)
        XCTAssertFalse(store.savedConfiguration.device.fnLock)
        XCTAssertTrue(store.configuration.device.fnLock)
        XCTAssertEqual(store.configuration.changes(comparedTo: store.savedConfiguration), .device)
        XCTAssertEqual(store.connectionState, .ready)
    }

    func testShortcutAndMultiShortcutMacroCanBeAssignedAndAppliedTogether() async {
        let client = FakeFlowDeviceClient()
        let store = makeStore(client: client)
        await store.connectAndRead()

        store.selectedSystem = .mac
        store.selectedLayer = .base
        store.selectedKeyID = "f12"
        let first = FlowShortcut(modifierMask: 0x08, keyUsage: 0x06)
        let second = FlowShortcut(modifierMask: 0x08, keyUsage: 0x19)
        store.configuration.macros[0].name = "Copy then Paste"
        store.configuration.macros[0].events =
            FlowDefaults.macroEvents(for: first) + FlowDefaults.macroEvents(for: second)
        store.assign(FlowDefaults.macroAction(slot: 0, name: "Copy then Paste"))

        await store.applyChanges()

        XCTAssertEqual(client.lastChanges, [.keymaps, .macros])
        XCTAssertEqual(store.savedConfiguration.keymaps[.mac]?[.base]?["f12"]?.family, 0x08)
        XCTAssertEqual(store.savedConfiguration.keymaps[.mac]?[.base]?["f12"]?.value, 0x0100)
        XCTAssertEqual(store.savedConfiguration.macros[0].events.count, 8)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testRevertSelectedKeyAssignmentOnlyUndoesThatKey() async {
        let store = makeStore(client: FakeFlowDeviceClient())
        await store.connectAndRead()
        store.selectedKeyID = "f12"
        store.assign(FlowDefaults.shortcutAction(modifierMask: 0x0a, keyUsage: 0x07))
        store.configuration.lighting.brightness = 4

        store.revertSelectedKeyAssignment()

        XCTAssertEqual(
            store.configuration.keymaps[.mac]?[.base]?["f12"],
            store.savedConfiguration.keymaps[.mac]?[.base]?["f12"]
        )
        XCTAssertEqual(store.configuration.changes(comparedTo: store.savedConfiguration), .lighting)
    }

    func testScopedRevertLeavesOtherWorkspaceEditsPending() async {
        let store = makeStore(client: FakeFlowDeviceClient())
        await store.connectAndRead()
        store.configuration.lighting.speed = 4
        store.configuration.device.fnLock.toggle()

        store.discardChanges(scope: .lighting)

        XCTAssertEqual(store.configuration.lighting, store.savedConfiguration.lighting)
        XCTAssertNotEqual(store.configuration.device, store.savedConfiguration.device)
        XCTAssertEqual(store.configuration.changes(comparedTo: store.savedConfiguration), .device)
    }

    private func makeStore(client: FakeFlowDeviceClient) -> AppStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FlowControlTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppStore(client: client, automaticBackupDirectory: directory)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class FakeFlowDeviceClient: FlowDeviceClient, @unchecked Sendable {
    enum Failure {
        case deviceNotFoundOnConnect
        case disconnectDuringWrite
    }

    private let lock = NSLock()
    private var connected = false
    private var storedConfiguration: KeyboardConfiguration
    private var writes = 0
    private var connects = 0
    private var applies = 0
    private var capturedChanges: ConfigurationChangeSet = []
    private var shouldCorruptNextReadback = false
    private let readDelayNanoseconds: UInt64
    private let writeDelayNanoseconds: UInt64
    private let failure: Failure?

    init(
        readDelayNanoseconds: UInt64 = 0,
        writeDelayNanoseconds: UInt64 = 0,
        configuration: KeyboardConfiguration = FlowDefaults.configuration,
        failure: Failure? = nil
    ) {
        self.readDelayNanoseconds = readDelayNanoseconds
        self.writeDelayNanoseconds = writeDelayNanoseconds
        storedConfiguration = configuration
        self.failure = failure
    }

    var isConnected: Bool { withLock { connected } }
    var writeCount: Int { withLock { writes } }
    var connectCount: Int { withLock { connects } }
    var applyCount: Int { withLock { applies } }
    var lastChanges: ConfigurationChangeSet { withLock { capturedChanges } }

    func corruptNextReadback() {
        withLock { shouldCorruptNextReadback = true }
    }

    func connect() async throws -> FlowDeviceIdentity {
        withLock { connects += 1 }
        if failure == .deviceNotFoundOnConnect { throw FlowDeviceError.deviceNotFound }
        withLock { connected = true }
        return FlowDeviceIdentity(
            productName: "Flow Lite 84 Test",
            vendorID: FlowDeviceIdentity.expectedVendorID,
            productID: FlowDeviceIdentity.expectedProductID,
            deviceVersion: "test"
        )
    }

    func disconnect() {
        withLock { connected = false }
    }

    func readIdentity() async throws -> FlowDeviceIdentity {
        try await connect()
    }

    func readConfiguration() async throws -> KeyboardConfiguration {
        if readDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: readDelayNanoseconds) }
        guard isConnected else { throw FlowDeviceError.notConnected }
        return withLock {
            var result = storedConfiguration
            if shouldCorruptNextReadback {
                shouldCorruptNextReadback = false
                result.device.pollingRate = result.device.pollingRate == 250 ? 125 : 250
            }
            return result
        }
    }

    func writeConfiguration(_ configuration: KeyboardConfiguration) async throws {
        withLock { writes += 1 }
        if writeDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: writeDelayNanoseconds) }
        if failure == .disconnectDuringWrite {
            withLock { connected = false }
            throw FlowDeviceError.notConnected
        }
        guard isConnected else { throw FlowDeviceError.notConnected }
        withLock { storedConfiguration = configuration }
    }

    func applyConfiguration(
        _ configuration: KeyboardConfiguration,
        baseline: KeyboardConfiguration,
        changes: ConfigurationChangeSet
    ) async throws -> KeyboardConfiguration {
        _ = baseline
        withLock {
            applies += 1
            capturedChanges = changes
        }
        try await writeConfiguration(configuration)
        return try await readConfiguration()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
