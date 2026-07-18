import Foundation

enum ConfigurationSection: String, CaseIterable, Identifiable {
    case keymap
    case lighting
    case macros
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keymap: "Key Assignment"
        case .lighting: "Lighting"
        case .macros: "Macros"
        case .device: "Device"
        }
    }

    var systemImage: String {
        switch self {
        case .keymap: "keyboard"
        case .lighting: "lightbulb"
        case .macros: "record.circle"
        case .device: "slider.horizontal.3"
        }
    }
}

enum KeyboardSystem: String, CaseIterable, Codable, Identifiable {
    case mac
    case windows

    var id: String { rawValue }
    var title: String { self == .mac ? "macOS" : "Windows" }
}

enum KeyboardLayer: String, CaseIterable, Codable, Identifiable {
    case base
    case function

    var id: String { rawValue }
    var title: String { self == .base ? "Base Layer" : "Fn Layer" }
}

enum ActionCategory: String, CaseIterable, Codable, Identifiable {
    case basic = "Basic Keys"
    case shortcut = "Shortcuts"
    case modifier = "Modifiers"
    case media = "Media"
    case navigation = "Navigation"
    case macro = "Macros"
    case device = "Device"
    case mouse = "Mouse"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .basic: "textformat"
        case .shortcut: "command"
        case .modifier: "option"
        case .media: "play.rectangle"
        case .navigation: "arrow.up.left.and.arrow.down.right"
        case .macro: "record.circle"
        case .device: "keyboard"
        case .mouse: "computermouse"
        }
    }
}

struct KeyAction: Codable, Hashable, Identifiable {
    let family: UInt8
    let value: UInt16
    let label: String
    let category: ActionCategory

    var id: String { "\(family)-\(value)" }
}

/// A simultaneous keyboard chord in the Flow Lite keymap format.
///
/// Family `0x07` stores the USB keyboard usage in the high byte and the
/// standard HID modifier mask in the low byte. For example, the factory
/// macOS screenshot assignment `0x200A` is Shift + Command + 3.
struct FlowShortcut: Hashable {
    static let family: UInt8 = 0x07

    var modifierMask: UInt8
    var keyUsage: UInt8

    var value: UInt16 {
        UInt16(keyUsage) << 8 | UInt16(modifierMask)
    }

    init(modifierMask: UInt8, keyUsage: UInt8) {
        self.modifierMask = modifierMask
        self.keyUsage = keyUsage
    }

    init?(action: KeyAction) {
        guard action.family == Self.family else { return nil }
        modifierMask = UInt8(action.value & 0x00FF)
        keyUsage = UInt8(action.value >> 8)
    }
}

enum FlowShortcutModifier: UInt8, CaseIterable, Identifiable {
    case control = 0x01
    case option = 0x04
    case shift = 0x02
    case command = 0x08

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .control: "Control"
        case .shift: "Shift"
        case .option: "Option"
        case .command: "Command"
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .shift: "⇧"
        case .option: "⌥"
        case .command: "⌘"
        }
    }
}

struct PhysicalKey: Hashable, Identifiable {
    let id: String
    let label: String
    let width: Double
    let spacerBefore: Double

    init(_ id: String, _ label: String, width: Double = 1, spacerBefore: Double = 0) {
        self.id = id
        self.label = label
        self.width = width
        self.spacerBefore = spacerBefore
    }
}

struct MacroEvent: Codable, Hashable, Identifiable {
    enum State: UInt8, Codable {
        case released = 0
        case pressed = 1
    }

    var id = UUID()
    var state: State
    var family: UInt8
    var value: UInt16
    var label: String
    var delayMilliseconds: UInt16
}

struct KeyboardMacro: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var events: [MacroEvent]
}

struct LightingConfiguration: Codable, Hashable {
    var mode: UInt8
    var isEnabled: Bool
    var brightness: UInt8
    var speed: UInt8
    var offTime: UInt8
}

struct DeviceConfiguration: Codable, Hashable {
    var pollingRate: Int
    var currentSystem: KeyboardSystem
    var fnLock: Bool
    var fullKeyboardLock: Bool
}

struct KeyboardConfiguration: Codable, Hashable {
    var keymaps: [KeyboardSystem: [KeyboardLayer: [String: KeyAction]]]
    var lighting: LightingConfiguration
    var macros: [KeyboardMacro]
    var device: DeviceConfiguration

    func changes(comparedTo other: Self) -> ConfigurationChangeSet {
        var changes: ConfigurationChangeSet = []
        if lighting != other.lighting { changes.insert(.lighting) }
        if device != other.device { changes.insert(.device) }

        for system in KeyboardSystem.allCases {
            for layer in KeyboardLayer.allCases {
                guard Self.keymapIsDeviceEquivalent(
                    keymaps[system]?[layer],
                    other.keymaps[system]?[layer]
                ) else {
                    changes.insert(.keymaps)
                    break
                }
            }
        }

        let lhsMacros = macros.sorted { $0.id < $1.id }
        let rhsMacros = other.macros.sorted { $0.id < $1.id }
        if lhsMacros.count != rhsMacros.count || !zip(lhsMacros, rhsMacros).allSatisfy({ lhs, rhs in
            lhs.isDeviceEquivalent(to: rhs)
        }) {
            changes.insert(.macros)
        }
        return changes
    }

    func applyingChanges(from edited: Self, sections: ConfigurationChangeSet) -> Self {
        var result = self
        if sections.contains(.keymaps) { result.keymaps = edited.keymaps }
        if sections.contains(.lighting) { result.lighting = edited.lighting }
        if sections.contains(.macros) { result.macros = edited.macros }
        if sections.contains(.device) { result.device = edited.device }
        return result
    }

    /// Replays only genuine editor changes onto a freshly read device snapshot.
    /// This prevents one offline lighting edit from replacing unrelated live
    /// keymaps, macros, or device settings with bundled defaults.
    func rebasingEdits(from edited: Self, originalBaseline: Self) -> Self {
        var result = self

        if edited.lighting.mode != originalBaseline.lighting.mode {
            result.lighting.mode = edited.lighting.mode
        }
        if edited.lighting.isEnabled != originalBaseline.lighting.isEnabled {
            result.lighting.isEnabled = edited.lighting.isEnabled
        }
        if edited.lighting.brightness != originalBaseline.lighting.brightness {
            result.lighting.brightness = edited.lighting.brightness
        }
        if edited.lighting.speed != originalBaseline.lighting.speed {
            result.lighting.speed = edited.lighting.speed
        }
        if edited.lighting.offTime != originalBaseline.lighting.offTime {
            result.lighting.offTime = edited.lighting.offTime
        }

        if edited.device.pollingRate != originalBaseline.device.pollingRate {
            result.device.pollingRate = edited.device.pollingRate
        }
        if edited.device.currentSystem != originalBaseline.device.currentSystem {
            result.device.currentSystem = edited.device.currentSystem
        }
        if edited.device.fnLock != originalBaseline.device.fnLock {
            result.device.fnLock = edited.device.fnLock
        }
        if edited.device.fullKeyboardLock != originalBaseline.device.fullKeyboardLock {
            result.device.fullKeyboardLock = edited.device.fullKeyboardLock
        }

        for system in KeyboardSystem.allCases {
            for layer in KeyboardLayer.allCases {
                guard let editedLayer = edited.keymaps[system]?[layer],
                      let originalLayer = originalBaseline.keymaps[system]?[layer] else { continue }
                for (keyID, editedAction) in editedLayer {
                    guard let originalAction = originalLayer[keyID],
                          editedAction.family != originalAction.family ||
                            editedAction.value != originalAction.value else { continue }
                    result.keymaps[system]?[layer]?[keyID] = editedAction
                }
            }
        }

        for editedMacro in edited.macros {
            guard let originalMacro = originalBaseline.macros.first(where: { $0.id == editedMacro.id }),
                  !editedMacro.isDeviceEquivalent(to: originalMacro),
                  let destination = result.macros.firstIndex(where: { $0.id == editedMacro.id }) else { continue }
            result.macros[destination] = editedMacro
        }
        return result
    }

    /// Equality of fields that can actually be persisted to the keyboard.
    /// UI identity and display labels are intentionally excluded: HID reads
    /// recreate macro UUIDs and canonical action labels on every readback.
    func isDeviceEquivalent(to other: Self) -> Bool {
        guard lighting == other.lighting, device == other.device else { return false }

        for system in KeyboardSystem.allCases {
            for layer in KeyboardLayer.allCases {
                guard let lhs = keymaps[system]?[layer],
                      let rhs = other.keymaps[system]?[layer],
                      lhs.count == rhs.count else { return false }
                for (keyID, action) in lhs {
                    guard let otherAction = rhs[keyID],
                          action.family == otherAction.family,
                          action.value == otherAction.value else { return false }
                }
            }
        }

        let lhsMacros = macros.sorted { $0.id < $1.id }
        let rhsMacros = other.macros.sorted { $0.id < $1.id }
        guard lhsMacros.count == rhsMacros.count else { return false }
        return zip(lhsMacros, rhsMacros).allSatisfy { lhs, rhs in
            lhs.isDeviceEquivalent(to: rhs)
        }
    }

    private static func keymapIsDeviceEquivalent(
        _ lhs: [String: KeyAction]?,
        _ rhs: [String: KeyAction]?
    ) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count else { return false }
        return lhs.allSatisfy { keyID, action in
            guard let otherAction = rhs[keyID] else { return false }
            return action.family == otherAction.family && action.value == otherAction.value
        }
    }
}

struct ConfigurationChangeSet: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let keymaps = Self(rawValue: 1 << 0)
    static let lighting = Self(rawValue: 1 << 1)
    static let macros = Self(rawValue: 1 << 2)
    static let device = Self(rawValue: 1 << 3)
    static let all: Self = [.keymaps, .lighting, .macros, .device]

    var description: String {
        var names: [String] = []
        if contains(.keymaps) { names.append("key assignments") }
        if contains(.lighting) { names.append("lighting") }
        if contains(.macros) { names.append("macros") }
        if contains(.device) { names.append("device settings") }
        return names.joined(separator: ", ")
    }
}

private extension KeyboardMacro {
    func isDeviceEquivalent(to other: Self) -> Bool {
        guard id == other.id, events.count == other.events.count else { return false }
        // Empty records do not persist their display name.
        if !events.isEmpty, name != other.name { return false }
        return zip(events, other.events).allSatisfy { lhs, rhs in
            lhs.state == rhs.state &&
                lhs.family == rhs.family &&
                lhs.value == rhs.value &&
                lhs.delayMilliseconds == rhs.delayMilliseconds
        }
    }
}

struct FlowDeviceIdentity: Codable, Hashable {
    var productName: String
    var vendorID: Int
    var productID: Int
    var deviceVersion: String
    var customerID: UInt8?
    var modelID: UInt8?
    var transportType: UInt8?
    var batteryPercent: Int?

    static let expectedVendorID = 0x05AC
    static let expectedProductID = 0x024F
}

struct ConfigurationBackup: Codable {
    var createdAt: Date
    var identity: FlowDeviceIdentity
    var configuration: KeyboardConfiguration
}
