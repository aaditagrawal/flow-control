import Foundation

struct DefaultKeyBinding: Hashable {
    let keyID: String
    let actionID: String
    let isWriteSafe: Bool

    init(_ keyID: String, _ actionID: String, isWriteSafe: Bool = true) {
        self.keyID = keyID
        self.actionID = actionID
        self.isWriteSafe = isWriteSafe
    }
}

enum FlowDefaults {
    static let physicalKeys = KeyboardLayout.rows.flatMap { $0 }

    /// Physical keys paired with their actual record in a 128-entry firmware
    /// layer. Sorted by flash index for deterministic reads and writes.
    static let firmwareKeySlots: [(flashIndex: Int, key: PhysicalKey)] = physicalKeys
        .compactMap { key in
            KeyboardLayout.flashIndexByKeyID[key.id].map { (flashIndex: $0, key: key) }
        }
        .sorted { $0.flashIndex < $1.flashIndex }

    static let lightingModes: [LightingMode] = [
        LightingMode(id: 0, rawValue: 0xff, name: "Off", supportsBrightness: false, supportsSpeed: false),
        LightingMode(id: 1, rawValue: 0x08, name: "Ripple", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 2, rawValue: 0x07, name: "Touch Effect", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 3, rawValue: 0xff, name: "Flow", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 4, rawValue: 0x04, name: "Snow Trace", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 5, rawValue: 0x06, name: "Sine Wave", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 6, rawValue: 0x01, name: "Breathing", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 7, rawValue: 0x00, name: "Always On", supportsBrightness: true, supportsSpeed: false),
        LightingMode(id: 8, rawValue: 0x09, name: "Snake", supportsBrightness: true, supportsSpeed: true),
        LightingMode(id: 9, rawValue: 0xff, name: "Season Blossom", supportsBrightness: false, supportsSpeed: false),
        LightingMode(id: 10, rawValue: 0x02, name: "Rainbow Cycle", supportsBrightness: false, supportsSpeed: false),
        LightingMode(id: 11, rawValue: 0x03, name: "Seven-color Change", supportsBrightness: true, supportsSpeed: true),
    ]

    /// Values accepted by the firmware's CurrentLightMode byte. Windows rows
    /// with raw value 0xFF are unavailable placeholders, not distinct modes.
    static let supportedLightingModeValues: [UInt8] = lightingModes
        .map(\.rawValue)
        .filter { $0 != 0xFF }

    static let lightingBrightnessValues: [UInt8] = [0, 30, 60, 90, 120]
    static let lightingSpeedValues: [UInt16] = [1000, 17, 12, 8, 0]
    static let pollingRates: [(label: String, value: Int)] = [
        ("125 Hz", 8), ("250 Hz", 4), ("500 Hz", 2), ("1000 Hz", 1),
    ]

    /// Assignable actions whose type/value encodings are established by the
    /// official driver. Generic HYPACE-only Fn2, sequences, RGB/color and light
    /// strip actions are deliberately not present.
    static let actions: [KeyAction] = {
        var result: [KeyAction] = [
            KeyAction(family: 0x00, value: 0x0000, label: "Disabled", category: .basic),
        ]

        result.append(contentsOf: modifierActions.values)

        for key in physicalKeys {
            guard let usage = KeyboardLayout.hidUsages[key.id],
                  modifierActionID(for: key.id) == nil else { continue }
            result.append(KeyAction(family: 0x02, value: usage, label: key.label, category: keyboardCategory(for: usage)))
        }

        result.append(contentsOf: consumerActions.values)
        result.append(contentsOf: deviceActions.values)
        result.append(KeyAction(family: 0x06, value: 0x0001, label: "Fn", category: .modifier))
        result.append(KeyAction(family: 0x06, value: 0x0002, label: "Mac Fn", category: .modifier))
        result.append(shortcutAction(modifierMask: 0x0a, keyUsage: 0x20, label: "Screenshot (⇧⌘3)"))
        result.append(contentsOf: mouseActions)

        return result.sorted {
            if $0.category.rawValue == $1.category.rawValue { return $0.label < $1.label }
            return $0.category.rawValue < $1.category.rawValue
        }
    }()

    static let configuration: KeyboardConfiguration = {
        var keymaps: [KeyboardSystem: [KeyboardLayer: [String: KeyAction]]] = [:]
        for system in KeyboardSystem.allCases {
            keymaps[system] = [
                .base: resolvedKeymap(from: baseBindings(for: system)),
                .function: resolvedKeymap(from: baseBindings(for: system) + functionBindings(for: system)),
            ]
        }

        return KeyboardConfiguration(
            keymaps: keymaps,
            lighting: LightingConfiguration(mode: 0, isEnabled: true, brightness: 3, speed: 3, offTime: 60),
            macros: (0..<15).map { KeyboardMacro(id: $0, name: "Macro \($0 + 1)", events: []) },
            device: DeviceConfiguration(pollingRate: 1_000, currentSystem: .mac, fnLock: false, fullKeyboardLock: false)
        )
    }()

    static func action(family: UInt8, value: UInt16) -> KeyAction {
        if family == FlowShortcut.family {
            let shortcut = FlowShortcut(
                modifierMask: UInt8(value & 0x00ff),
                keyUsage: UInt8(value >> 8)
            )
            return shortcutAction(
                modifierMask: shortcut.modifierMask,
                keyUsage: shortcut.keyUsage
            )
        }
        if family == 0x08 {
            return macroAction(
                slot: Int(value & 0x00ff),
                repeatCount: UInt8(value >> 8)
            )
        }
        return actions.first { $0.family == family && $0.value == value }
            ?? KeyAction(
                family: family,
                value: value,
                label: String(format: "Unknown 0x%02X:0x%04X", family, value),
                category: .basic
            )
    }

    /// Ordinary keyboard usages available as the non-modifier part of a
    /// shortcut. Modifier usages themselves are excluded because the chord's
    /// low byte already carries them.
    static let shortcutKeyActions: [KeyAction] = actions.filter {
        $0.family == 0x02 && !(0xe0...0xe7).contains($0.value)
    }

    static func shortcutAction(
        modifierMask: UInt8,
        keyUsage: UInt8,
        label explicitLabel: String? = nil
    ) -> KeyAction {
        let shortcut = FlowShortcut(modifierMask: modifierMask, keyUsage: keyUsage)
        let modifiers = FlowShortcutModifier.allCases
            .filter { modifierMask & $0.rawValue != 0 }
            .map(\.symbol)
            .joined()
        let keyLabel = physicalKeys.first {
            KeyboardLayout.hidUsages[$0.id] == UInt16(keyUsage)
        }?.label ?? String(format: "Key 0x%02X", keyUsage)
        let label = explicitLabel ?? "\(modifiers)\(keyLabel)"
        return KeyAction(family: FlowShortcut.family, value: shortcut.value, label: label, category: .shortcut)
    }

    /// Macro key assignments use `[0x08, slot, repeatCount, checksum]` in the
    /// official Windows implementation. The current editor intentionally
    /// emits a finite one-shot assignment unless the imported value says
    /// otherwise.
    static func macroAction(slot: Int, repeatCount: UInt8 = 1, name: String? = nil) -> KeyAction {
        let value = UInt16(repeatCount) << 8 | UInt16(UInt8(clamping: slot))
        let base = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Macro \(slot + 1)"
        let suffix = switch repeatCount {
        case 0: " (imported repeat mode)"
        case 1: ""
        default: " × \(repeatCount)"
        }
        return KeyAction(family: 0x08, value: value, label: "\(base)\(suffix)", category: .macro)
    }

    static func macroEvents(
        for shortcut: FlowShortcut,
        delayMilliseconds: UInt16 = 20
    ) -> [MacroEvent] {
        let modifiers = FlowShortcutModifier.allCases.filter {
            shortcut.modifierMask & $0.rawValue != 0
        }
        var events = modifiers.map { modifier in
            let action = action(family: 0x01, value: UInt16(modifier.rawValue))
            return MacroEvent(
                state: .pressed,
                family: action.family,
                value: action.value,
                label: action.label,
                delayMilliseconds: delayMilliseconds
            )
        }

        let keyAction = action(family: 0x02, value: UInt16(shortcut.keyUsage))
        events.append(
            MacroEvent(
                state: .pressed,
                family: keyAction.family,
                value: keyAction.value,
                label: keyAction.label,
                delayMilliseconds: delayMilliseconds
            )
        )
        events.append(
            MacroEvent(
                state: .released,
                family: keyAction.family,
                value: keyAction.value,
                label: keyAction.label,
                delayMilliseconds: delayMilliseconds
            )
        )

        events.append(contentsOf: modifiers.reversed().map { modifier in
            let action = action(family: 0x01, value: UInt16(modifier.rawValue))
            return MacroEvent(
                state: .released,
                family: action.family,
                value: action.value,
                label: action.label,
                delayMilliseconds: delayMilliseconds
            )
        })
        return events
    }

    static func bindings(system: KeyboardSystem, layer: KeyboardLayer) -> [DefaultKeyBinding] {
        switch layer {
        case .base: baseBindings(for: system)
        case .function: functionBindings(for: system)
        }
    }

    private static let modifierActions: [String: KeyAction] = [
        "modifier-control-left": KeyAction(family: 0x01, value: 0x01, label: "Left Control", category: .modifier),
        "modifier-shift-left": KeyAction(family: 0x01, value: 0x02, label: "Left Shift", category: .modifier),
        "modifier-alt-left": KeyAction(family: 0x01, value: 0x04, label: "Left Alt / Option", category: .modifier),
        "modifier-meta-left": KeyAction(family: 0x01, value: 0x08, label: "Left Windows / Command", category: .modifier),
        "modifier-control-right": KeyAction(family: 0x01, value: 0x10, label: "Right Control", category: .modifier),
        "modifier-shift-right": KeyAction(family: 0x01, value: 0x20, label: "Right Shift", category: .modifier),
        "modifier-alt-right": KeyAction(family: 0x01, value: 0x40, label: "Right Alt / Option", category: .modifier),
        "modifier-meta-right": KeyAction(family: 0x01, value: 0x80, label: "Right Windows / Command", category: .modifier),
    ]

    private static let consumerActions: [String: KeyAction] = {
        let values: [(String, String, UInt16)] = [
            ("player", "Player", 0x0183), ("play-pause", "Play / Pause", 0x00cd),
            ("next-track", "Next Track", 0x00b5), ("previous-track", "Previous Track", 0x00b6),
            ("stop", "Stop", 0x00b7), ("mute", "Mute", 0x00e2),
            ("volume-up", "Volume Up", 0x00e9), ("volume-down", "Volume Down", 0x00ea),
            ("mail", "Mail", 0x018a), ("calculator", "Calculator", 0x0192),
            ("computer", "My Computer", 0x0194), ("home-page", "Home Page", 0x0223),
            ("search", "Search", 0x0221), ("browser-forward", "Browser Forward", 0x0225),
            ("browser-back", "Browser Back", 0x0224), ("browser-stop", "Stop Web Page", 0x0226),
            ("refresh", "Refresh", 0x0227), ("favorites", "Favorites", 0x022a),
            ("screen-brightness-down", "Screen Brightness Down", 0x0070),
            ("screen-brightness-up", "Screen Brightness Up", 0x006f),
        ]
        return Dictionary(uniqueKeysWithValues: values.map {
            ($0.0, KeyAction(family: 0x03, value: $0.2, label: $0.1, category: .media))
        })
    }()

    private static let deviceActions: [String: KeyAction] = {
        let values: [(String, String, UInt16)] = [
            ("bt-1", "Bluetooth 1", 0x0000), ("bt-2", "Bluetooth 2", 0x0001),
            ("bt-3", "Bluetooth 3", 0x0002), ("receiver-24g", "2.4 GHz", 0x0003),
            ("light-mode-cycle-forward", "Light Mode Cycle +", 0x0004),
            ("light-mode-next", "Light Mode +", 0x0005), ("light-mode-previous", "Light Mode -", 0x0006),
            ("light-speed-cycle", "Light Speed Cycle", 0x000b), ("light-speed-up", "Light Speed +", 0x000c),
            ("light-speed-down", "Light Speed -", 0x000d),
            ("light-brightness-cycle", "Light Brightness Cycle", 0x000e),
            ("light-brightness-up", "Light Brightness +", 0x000f),
            ("light-brightness-down", "Light Brightness -", 0x0010),
            ("battery-check", "Check Battery", 0x0011), ("light-toggle", "Light Switch", 0x0012),
            ("fn-lock", "Fn Lock", 0x0013), ("wired", "Wired", 0x0015),
            ("restore", "Restore", 0x0017), ("system-windows", "Windows Mode", 0x0018),
            ("system-mac", "macOS Mode", 0x0019), ("keyboard-lock", "Full Keyboard Lock", 0x0022),
            ("light-mode-cycle-backward", "Light Mode Cycle -", 0x0031),
        ]
        return Dictionary(uniqueKeysWithValues: values.map {
            ($0.0, KeyAction(family: 0x05, value: $0.2, label: $0.1, category: .device))
        })
    }()

    private static let mouseActions: [KeyAction] = [
        KeyAction(family: 0x0a, value: 0x01, label: "Mouse Left", category: .mouse),
        KeyAction(family: 0x0a, value: 0x02, label: "Mouse Right", category: .mouse),
        KeyAction(family: 0x0a, value: 0x04, label: "Mouse Middle", category: .mouse),
        KeyAction(family: 0x0a, value: 0x10, label: "Mouse Forward", category: .mouse),
        KeyAction(family: 0x0a, value: 0x08, label: "Mouse Back", category: .mouse),
    ]

    private static func baseBindings(for system: KeyboardSystem) -> [DefaultKeyBinding] {
        physicalKeys.map { key in
            if system == .mac {
                switch key.id {
                case "print-screen": return DefaultKeyBinding(key.id, "mac-screenshot")
                case "meta-left": return DefaultKeyBinding(key.id, "modifier-alt-left")
                case "alt-left": return DefaultKeyBinding(key.id, "modifier-meta-left")
                case "alt-right": return DefaultKeyBinding(key.id, "modifier-meta-right")
                case "fn": return DefaultKeyBinding(key.id, "mac-fn")
                case "control-right": return DefaultKeyBinding(key.id, "modifier-alt-right")
                default: break
                }
            }
            if key.id == "fn" { return DefaultKeyBinding(key.id, "fn") }
            if let modifier = modifierActionID(for: key.id) { return DefaultKeyBinding(key.id, modifier) }
            return DefaultKeyBinding(key.id, "keyboard-\(String(format: "%02x", KeyboardLayout.hidUsages[key.id] ?? 0))")
        }
    }

    private static let commonFunctionBindings: [DefaultKeyBinding] = [
        DefaultKeyBinding("f1", "screen-brightness-down"),
        DefaultKeyBinding("f2", "screen-brightness-up"),
        DefaultKeyBinding("f3", "multi-screen", isWriteSafe: false),
        DefaultKeyBinding("f4", "search"),
        DefaultKeyBinding("f5", "light-brightness-down"),
        DefaultKeyBinding("f6", "light-brightness-up"),
        DefaultKeyBinding("f7", "previous-track"),
        DefaultKeyBinding("f8", "play-pause"),
        DefaultKeyBinding("f9", "next-track"),
        DefaultKeyBinding("f10", "mute"),
        DefaultKeyBinding("f11", "volume-down"),
        DefaultKeyBinding("f12", "volume-up"),
    ]

    private static func functionBindings(for system: KeyboardSystem) -> [DefaultKeyBinding] {
        guard system == .windows else { return commonFunctionBindings }
        return commonFunctionBindings + [
            DefaultKeyBinding("alt-right", "menu", isWriteSafe: false),
            DefaultKeyBinding("print-screen", "calculator"),
            DefaultKeyBinding("insert", "voice-assistant", isWriteSafe: false),
            DefaultKeyBinding("delete", "lock", isWriteSafe: false),
        ]
    }

    private static func resolvedKeymap(from bindings: [DefaultKeyBinding]) -> [String: KeyAction] {
        var result: [String: KeyAction] = [:]
        for binding in bindings {
            guard binding.isWriteSafe, let action = catalogAction(id: binding.actionID) else { continue }
            result[binding.keyID] = action
        }
        return result
    }

    private static func catalogAction(id: String) -> KeyAction? {
        if id == "fn" { return KeyAction(family: 0x06, value: 0x0001, label: "Fn", category: .modifier) }
        if id == "mac-fn" { return KeyAction(family: 0x06, value: 0x0002, label: "Mac Fn", category: .modifier) }
        if id == "mac-screenshot" { return shortcutAction(modifierMask: 0x0a, keyUsage: 0x20, label: "Screenshot (⇧⌘3)") }
        if let action = modifierActions[id] ?? consumerActions[id] ?? deviceActions[id] { return action }
        if id.hasPrefix("keyboard-"), let value = UInt16(id.dropFirst("keyboard-".count), radix: 16) {
            return actions.first { $0.family == 0x02 && $0.value == value }
        }
        return nil
    }

    private static func modifierActionID(for keyID: String) -> String? {
        switch keyID {
        case "control-left", "shift-left", "alt-left", "meta-left",
             "control-right", "shift-right", "alt-right", "meta-right":
            return "modifier-\(keyID)"
        default: return nil
        }
    }

    private static func keyboardCategory(for usage: UInt16) -> ActionCategory {
        switch usage {
        case 0x46...0x52: .navigation
        default: .basic
        }
    }
}
