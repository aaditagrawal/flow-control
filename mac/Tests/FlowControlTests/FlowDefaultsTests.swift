import AppKit
import Testing
@testable import FlowControl

@Suite("Flow Lite 84 verified defaults")
struct FlowDefaultsTests {
    @Test("physical layout is exact and stable")
    func physicalLayout() {
        #expect(KeyboardLayout.rows.map(\.count) == [16, 15, 15, 14, 14, 10])
        #expect(FlowDefaults.physicalKeys.count == 84)
        #expect(Set(FlowDefaults.physicalKeys.map(\.id)).count == 84)
        #expect(FlowDefaults.physicalKeys.first?.id == "escape")
        #expect(FlowDefaults.physicalKeys.last?.id == "arrow-right")
        #expect(KeyboardLayout.hidUsages.count == 83)
        #expect(KeyboardLayout.hidUsages["key-a"] == 0x04)
        #expect(KeyboardLayout.hidUsages["arrow-up"] == 0x52)
        #expect(KeyboardLayout.flashIndexByKeyID.count == 84)
        #expect(Set(KeyboardLayout.flashIndexByKeyID.values).count == 84)
        #expect(FlowDefaults.firmwareKeySlots.count == 84)
    }

    @Test("firmware slots preserve the official 128-entry matrix gaps")
    func firmwareSlots() {
        #expect(KeyboardLayout.flashIndexByKeyID["print-screen"] == 13)
        #expect(KeyboardLayout.flashIndexByKeyID["backquote"] == 16)
        #expect(KeyboardLayout.flashIndexByKeyID["insert"] == 30)
        #expect(KeyboardLayout.flashIndexByKeyID["delete"] == 46)
        #expect(KeyboardLayout.flashIndexByKeyID["page-up"] == 47)
        #expect(KeyboardLayout.flashIndexByKeyID["end"] == 62)
        #expect(KeyboardLayout.flashIndexByKeyID["page-down"] == 63)
        #expect(KeyboardLayout.flashIndexByKeyID["arrow-up"] == 78)
        #expect(KeyboardLayout.flashIndexByKeyID["space"] == 85)
        #expect(KeyboardLayout.flashIndexByKeyID["fn"] == 88)
        #expect(KeyboardLayout.flashIndexByKeyID["arrow-left"] == 93)
        #expect(KeyboardLayout.flashIndexByKeyID["arrow-right"] == 95)

        let used = Set(KeyboardLayout.flashIndexByKeyID.values)
        #expect(!used.contains(14)) // Scroll Lock
        #expect(!used.contains(15)) // Pause
        #expect(!used.contains(89)) // Fn2
        #expect(!used.contains(92)) // Numpad 0
    }

    @Test("defaults contain only supported systems and layers")
    func semanticDefaults() {
        let macFn = FlowDefaults.bindings(system: .mac, layer: .function)
        let windowsFn = FlowDefaults.bindings(system: .windows, layer: .function)
        #expect(macFn.count == 12)
        #expect(windowsFn.count == 16)
        #expect(macFn.first { $0.keyID == "f3" }?.isWriteSafe == false)
        #expect(windowsFn.first { $0.keyID == "print-screen" }?.actionID == "calculator")
        let macBase = FlowDefaults.bindings(system: .mac, layer: .base)
        #expect(macBase.first { $0.keyID == "meta-left" }?.actionID == "modifier-alt-left")
        #expect(macBase.first { $0.keyID == "alt-left" }?.actionID == "modifier-meta-left")
        #expect(macBase.first { $0.keyID == "alt-right" }?.actionID == "modifier-meta-right")
        #expect(macBase.first { $0.keyID == "control-right" }?.actionID == "modifier-alt-right")
        #expect(macBase.first { $0.keyID == "fn" }?.actionID == "mac-fn")
        #expect(macBase.first { $0.keyID == "print-screen" }?.actionID == "mac-screenshot")
        #expect(FlowDefaults.configuration.keymaps.count == 2)
        #expect(FlowDefaults.configuration.keymaps[.mac]?.count == 2)
        #expect(FlowDefaults.configuration.keymaps[.mac]?[.function]?.count == 84)
        #expect(FlowDefaults.configuration.keymaps[.windows]?[.function]?.count == 84)
    }

    @Test("action catalog excludes generic unsupported features")
    func actionCatalog() {
        #expect(FlowDefaults.actions.contains { $0.family == 0x02 && $0.value == 0x04 })
        #expect(FlowDefaults.actions.contains { $0.family == 0x03 && $0.value == 0x00cd })
        #expect(FlowDefaults.actions.contains { $0.family == 0x06 && $0.value == 0x01 })
        #expect(FlowDefaults.actions.contains { $0.family == 0x06 && $0.value == 0x02 })
        #expect(FlowDefaults.actions.contains { $0.family == 0x07 && $0.value == 0x200a })
        #expect(!FlowDefaults.actions.contains { $0.family == 0x06 && $0.value == 0x03 })
        #expect(!FlowDefaults.actions.contains { $0.family == 0x09 })
        #expect(!FlowDefaults.actions.contains { $0.family == 0x05 && (0x0007...0x0009).contains($0.value) })
        #expect(!FlowDefaults.actions.contains { $0.family == 0x05 && (0x0024...0x0030).contains($0.value) })
    }

    @Test("lighting, macros, and polling match the Flow Lite Windows app")
    func features() {
        #expect(FlowDefaults.lightingModes.count == 12)
        #expect(FlowDefaults.lightingModes.map(\.id) == Array(0...11))
        #expect(FlowDefaults.lightingModes.filter { $0.rawValue == 0xff }.count == 3)
        #expect(FlowDefaults.supportedLightingModeValues == [8, 7, 4, 6, 1, 0, 9, 2, 3])
        #expect(FlowDefaults.configuration.lighting.mode == 0)
        #expect(FlowDefaults.lightingBrightnessValues == [0, 30, 60, 90, 120])
        #expect(FlowDefaults.lightingSpeedValues == [1000, 17, 12, 8, 0])
        #expect(FlowDefaults.configuration.lighting.brightness == 3)
        #expect(FlowDefaults.configuration.lighting.speed == 3)
        #expect(FlowDefaults.pollingRates.map(\.value) == [8, 4, 2, 1])
        #expect(FlowDefaults.configuration.macros.count == 15)
    }

    @Test("unknown device action round-trips without pretending it is known")
    func unknownAction() {
        let action = FlowDefaults.action(family: 0x7f, value: 0xabcd)
        #expect(action.family == 0x7f)
        #expect(action.value == 0xabcd)
        #expect(action.label.contains("Unknown"))
    }

    @Test("shortcut chords encode modifier mask and key usage")
    func shortcutEncoding() {
        for modifierMask in UInt8(1)...UInt8(15) {
            let action = FlowDefaults.shortcutAction(modifierMask: modifierMask, keyUsage: 0x0e)
            #expect(action.family == 0x07)
            #expect(action.value == UInt16(0x0e00) | UInt16(modifierMask))
            let decoded = FlowShortcut(action: action)
            #expect(decoded?.modifierMask == modifierMask)
            #expect(decoded?.keyUsage == 0x0e)
        }

        let screenshot = FlowDefaults.shortcutAction(modifierMask: 0x0a, keyUsage: 0x20)
        #expect(screenshot.value == 0x200a)
        #expect(screenshot.label == "⇧⌘3")
    }

    @Test("multiple shortcuts expand into balanced macro events")
    func shortcutMacroEvents() {
        let shortcut = FlowShortcut(modifierMask: 0x0a, keyUsage: 0x06)
        let events = FlowDefaults.macroEvents(for: shortcut)

        #expect(events.map(\.state) == [.pressed, .pressed, .pressed, .released, .released, .released])
        #expect(events.map(\.family) == [0x01, 0x01, 0x02, 0x02, 0x01, 0x01])
        #expect(events.map(\.value) == [0x02, 0x08, 0x06, 0x06, 0x08, 0x02])
        #expect(events.allSatisfy { $0.delayMilliseconds == 20 })
    }

    @Test("macro key assignments encode slot and one-shot repeat count")
    func macroAssignmentEncoding() {
        let first = FlowDefaults.macroAction(slot: 0, name: "Copy and Paste")
        #expect(first.family == 0x08)
        #expect(first.value == 0x0100)
        #expect(first.category == .macro)
        #expect(first.label == "Copy and Paste")

        let repeated = FlowDefaults.macroAction(slot: 14, repeatCount: 3)
        #expect(repeated.value == 0x030e)
        #expect(FlowDefaults.action(family: 0x08, value: repeated.value).value == 0x030e)
    }

    @Test("macOS key events map to Flow Lite shortcut bytes")
    func shortcutCaptureMapping() {
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 0) == 0x04) // A
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 40) == 0x0e) // K
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 122) == 0x3a) // F1
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 111) == 0x45) // F12
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 123) == 0x50) // Left
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 126) == 0x52) // Up
        #expect(ShortcutCaptureMap.hidUsage(forVirtualKeyCode: 255) == nil)

        let flags = NSEvent.ModifierFlags.command
            .union(.shift)
            .union(.capsLock)
        #expect(ShortcutCaptureMap.modifierMask(from: flags) == 0x0a)
    }
}
