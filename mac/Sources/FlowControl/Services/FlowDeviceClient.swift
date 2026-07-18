import Foundation

protocol FlowDeviceClient: AnyObject, Sendable {
    var isConnected: Bool { get }

    func connect() async throws -> FlowDeviceIdentity
    func disconnect()
    func readIdentity() async throws -> FlowDeviceIdentity
    func readConfiguration() async throws -> KeyboardConfiguration
    func writeConfiguration(_ configuration: KeyboardConfiguration) async throws
    func applyConfiguration(
        _ configuration: KeyboardConfiguration,
        baseline: KeyboardConfiguration,
        changes: ConfigurationChangeSet
    ) async throws -> KeyboardConfiguration
}

extension FlowDeviceClient {
    /// Applies and verifies a known set of changes. Hardware clients can
    /// override this to read only the affected records; the fallback preserves
    /// compatibility by using a complete write and readback.
    func applyConfiguration(
        _ configuration: KeyboardConfiguration,
        baseline: KeyboardConfiguration,
        changes: ConfigurationChangeSet
    ) async throws -> KeyboardConfiguration {
        _ = baseline
        _ = changes
        try await writeConfiguration(configuration)
        return try await readConfiguration()
    }
}

enum FlowDeviceError: LocalizedError {
    case notConnected
    case deviceNotFound
    case unsupportedDevice(String)
    case configurationInterfaceMissing
    case inputMonitoringPermissionRequired
    case timedOut(String)
    case malformedResponse(String)
    case writeVerificationFailed(String)
    case protectedOperation

    var errorDescription: String? {
        switch self {
        case .notConnected: "The Flow Lite 84 is not connected."
        case .deviceNotFound: "No wired Flow Lite 84 was found."
        case .unsupportedDevice(let detail): "Unsupported keyboard: \(detail)"
        case .configurationInterfaceMissing: "The vendor configuration interface is unavailable."
        case .inputMonitoringPermissionRequired:
            "Allow Flow Control in System Settings > Privacy & Security > Input Monitoring, then reconnect."
        case .timedOut(let operation): "The keyboard timed out during \(operation)."
        case .malformedResponse(let detail): "The keyboard returned malformed data: \(detail)"
        case .writeVerificationFailed(let detail): "The change could not be verified: \(detail)"
        case .protectedOperation: "This protected operation is not available in this build."
        }
    }
}
