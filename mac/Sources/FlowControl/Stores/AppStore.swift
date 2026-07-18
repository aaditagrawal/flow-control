import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case reading
        case ready
        case applying
        case failed(String)
    }

    var selection: ConfigurationSection? = .keymap
    var selectedSystem: KeyboardSystem = .mac
    var selectedLayer: KeyboardLayer = .base
    var selectedKeyID = "escape"
    var selectedMacroID = 0
    var searchText = ""
    var connectionState: ConnectionState = .disconnected
    var identity: FlowDeviceIdentity?
    var configuration: KeyboardConfiguration
    var savedConfiguration: KeyboardConfiguration
    var lastBackupURL: URL?

    private let client: FlowDeviceClient
    private let automaticBackupDirectory: URL?
    private var activeOperationID: UUID?

    init(client: FlowDeviceClient = FlowHIDService(), automaticBackupDirectory: URL? = nil) {
        self.client = client
        self.automaticBackupDirectory = automaticBackupDirectory
        let initial = FlowDefaults.configuration
        configuration = initial
        savedConfiguration = initial
    }

    var hasUnsavedChanges: Bool { !configuration.isDeviceEquivalent(to: savedConfiguration) }
    var isConnected: Bool { identity != nil && client.isConnected }
    var isBusy: Bool { activeOperationID != nil }
    /// Apply is also available for offline edits. It connects and reads the
    /// keyboard first, preserving the edits, then continues automatically.
    var canApply: Bool { !isBusy && hasUnsavedChanges }

    func canApply(_ scope: ConfigurationChangeSet) -> Bool {
        !isBusy && !configuration.changes(comparedTo: savedConfiguration).intersection(scope).isEmpty
    }

    func connectAndRead(silentlyWhenUnavailable: Bool = false) async {
        guard let operationID = beginOperation() else { return }
        let editorBaselineAtStart = savedConfiguration
        connectionState = .connecting
        defer { finishOperation(operationID) }
        do {
            let connectedIdentity = try await client.connect()
            guard activeOperationID == operationID else { return }
            identity = connectedIdentity
            connectionState = .reading
            let live = try await client.readConfiguration()
            guard activeOperationID == operationID else { return }

            savedConfiguration = live
            configuration = live.rebasingEdits(
                from: configuration,
                originalBaseline: editorBaselineAtStart
            )
            connectionState = .ready
        } catch {
            guard activeOperationID == operationID else { return }
            client.disconnect()
            identity = nil
            if silentlyWhenUnavailable, case FlowDeviceError.deviceNotFound = error {
                connectionState = .disconnected
            } else {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        activeOperationID = nil
        client.disconnect()
        connectionState = .disconnected
        identity = nil
    }

    func discardChanges() {
        configuration = savedConfiguration
    }

    func discardChanges(scope: ConfigurationChangeSet) {
        configuration = configuration.applyingChanges(from: savedConfiguration, sections: scope)
    }

    func dismissError() {
        guard case .failed = connectionState else { return }
        connectionState = isConnected ? .ready : .disconnected
    }

    func applyChanges(scope: ConfigurationChangeSet = .all) async {
        guard canApply(scope) else { return }
        if !isConnected {
            await connectAndRead()
            guard isConnected else { return }
        }
        let baseline = savedConfiguration
        let requested = baseline.applyingChanges(from: configuration, sections: scope)
        _ = await apply(requested, baseline: baseline)
    }

    /// Installs one physical key assignment without sweeping unrelated staged
    /// keymap edits into the same write. The result is true only after device
    /// readback matches the requested family and value.
    func assignAndApply(
        _ action: KeyAction,
        system: KeyboardSystem,
        layer: KeyboardLayer,
        keyID: String
    ) async -> Bool {
        configuration.keymaps[system]?[layer]?[keyID] = action
        if !isConnected {
            await connectAndRead()
            guard isConnected else { return false }
            configuration.keymaps[system]?[layer]?[keyID] = action
        }

        let baseline = savedConfiguration
        if let saved = baseline.keymaps[system]?[layer]?[keyID],
           saved.family == action.family,
           saved.value == action.value {
            return true
        }

        var requested = baseline
        requested.keymaps[system]?[layer]?[keyID] = action
        return await apply(requested, baseline: baseline)
    }

    private func apply(
        _ requested: KeyboardConfiguration,
        baseline: KeyboardConfiguration
    ) async -> Bool {
        let changes = requested.changes(comparedTo: baseline)
        guard !changes.isEmpty else { return true }
        guard let operationID = beginOperation() else { return false }
        connectionState = .applying
        defer { finishOperation(operationID) }
        do {
            try validateForApply(requested)
            try createAutomaticBackup()
            let verified = try await client.applyConfiguration(
                requested,
                baseline: baseline,
                changes: changes
            )
            guard activeOperationID == operationID else { return false }
            guard verified.isDeviceEquivalent(to: requested) else {
                let differing = verified.changes(comparedTo: requested)
                let detail = differing.description.isEmpty ? "unknown settings" : differing.description
                throw FlowDeviceError.writeVerificationFailed(
                    "the keyboard readback differs in \(detail)"
                )
            }
            savedConfiguration = verified
            if configuration.isDeviceEquivalent(to: requested) {
                configuration = verified
            }
            connectionState = .ready
            return true
        } catch {
            guard activeOperationID == operationID else { return false }
            if !client.isConnected { identity = nil }
            connectionState = .failed(error.localizedDescription)
            return false
        }
    }

    func assign(_ action: KeyAction) {
        configuration.keymaps[selectedSystem]?[selectedLayer]?[selectedKeyID] = action
    }

    func revertSelectedKeyAssignment() {
        guard let saved = savedConfiguration.keymaps[selectedSystem]?[selectedLayer]?[selectedKeyID] else { return }
        configuration.keymaps[selectedSystem]?[selectedLayer]?[selectedKeyID] = saved
    }

    func exportBackup(to url: URL) throws {
        guard let identity else { throw FlowDeviceError.notConnected }
        let backup = ConfigurationBackup(createdAt: .now, identity: identity, configuration: configuration)
        let data = try JSONEncoder.flowControl.encode(backup)
        try data.write(to: url, options: .atomic)
        lastBackupURL = url
    }

    func importBackup(from url: URL) throws {
        let backup = try JSONDecoder.flowControl.decode(ConfigurationBackup.self, from: Data(contentsOf: url))
        guard backup.identity.vendorID == FlowDeviceIdentity.expectedVendorID,
              backup.identity.productID == FlowDeviceIdentity.expectedProductID else {
            throw FlowDeviceError.unsupportedDevice("backup belongs to another device")
        }
        configuration = backup.configuration
    }

    private func createAutomaticBackup() throws {
        guard let identity else { throw FlowDeviceError.notConnected }
        let directory = automaticBackupDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "FlowControl/Backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Flow-Lite84-\(Date.now.formatted(.iso8601))-\(UUID().uuidString).json")
        let backup = ConfigurationBackup(createdAt: .now, identity: identity, configuration: savedConfiguration)
        try JSONEncoder.flowControl.encode(backup).write(to: url, options: .atomic)
        lastBackupURL = url
    }

    private func beginOperation() -> UUID? {
        guard activeOperationID == nil else { return nil }
        let operationID = UUID()
        activeOperationID = operationID
        return operationID
    }

    private func finishOperation(_ operationID: UUID) {
        if activeOperationID == operationID { activeOperationID = nil }
    }

    private func validateForApply(_ candidate: KeyboardConfiguration) throws {
        guard FlowDefaults.supportedLightingModeValues.contains(candidate.lighting.mode) else {
            throw StoreValidationError.invalidConfiguration("Lighting mode \(candidate.lighting.mode) is not supported by Flow Lite 84.")
        }
        guard candidate.lighting.brightness <= 4, candidate.lighting.speed <= 4 else {
            throw StoreValidationError.invalidConfiguration("Lighting brightness and speed must be between 0 and 4.")
        }
        let supportedOffTimes: Set<UInt8> = [0, 1, 3, 6, 12, 30, 60, 90]
        guard supportedOffTimes.contains(candidate.lighting.offTime) else {
            throw StoreValidationError.invalidConfiguration("The selected lighting sleep time is not supported.")
        }
        guard Set(candidate.macros.map(\.id)) == Set(0..<15), candidate.macros.count == 15 else {
            throw StoreValidationError.invalidConfiguration("The configuration must contain exactly 15 unique macro slots.")
        }
        for system in KeyboardSystem.allCases {
            for layer in KeyboardLayer.allCases {
                guard let assignments = candidate.keymaps[system]?[layer],
                      assignments.count == FlowDefaults.physicalKeys.count else {
                    throw StoreValidationError.invalidConfiguration("Every system and layer must contain all 84 physical keys.")
                }
                let allowedModifierMask = FlowShortcutModifier.allCases.reduce(UInt8(0)) { $0 | $1.rawValue }
                let supportedKeyUsages = Set(FlowDefaults.shortcutKeyActions.map { UInt8(truncatingIfNeeded: $0.value) })
                for action in assignments.values where action.family == FlowShortcut.family {
                    guard let shortcut = FlowShortcut(action: action),
                          shortcut.modifierMask != 0,
                          shortcut.modifierMask & ~allowedModifierMask == 0,
                          supportedKeyUsages.contains(shortcut.keyUsage) else {
                        throw StoreValidationError.invalidConfiguration("A shortcut assignment contains an invalid modifier or key.")
                    }
                }
            }
        }
    }
}

private enum StoreValidationError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail): detail
        }
    }
}

extension JSONEncoder {
    static var flowControl: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var flowControl: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
