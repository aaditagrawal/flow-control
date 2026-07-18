import AppKit

/// Converts macOS virtual key codes and modifier flags into the USB HID values
/// stored by the Flow Lite shortcut record.
enum ShortcutCaptureMap {
    static func hidUsage(forVirtualKeyCode keyCode: UInt16) -> UInt8? {
        usageByVirtualKeyCode[keyCode]
    }

    static func modifierMask(from flags: NSEvent.ModifierFlags) -> UInt8 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt8 = 0
        if flags.contains(.control) { result |= FlowShortcutModifier.control.rawValue }
        if flags.contains(.option) { result |= FlowShortcutModifier.option.rawValue }
        if flags.contains(.shift) { result |= FlowShortcutModifier.shift.rawValue }
        if flags.contains(.command) { result |= FlowShortcutModifier.command.rawValue }
        return result
    }

    // Apple virtual key codes are hardware-position codes. Mapping them here
    // avoids layout-sensitive character parsing and covers every ordinary key
    // offered by the Flow Lite shortcut picker.
    private static let usageByVirtualKeyCode: [UInt16: UInt8] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0b, 5: 0x0a,
        6: 0x1d, 7: 0x1b, 8: 0x06, 9: 0x19, 11: 0x05,
        12: 0x14, 13: 0x1a, 14: 0x08, 15: 0x15, 16: 0x1c, 17: 0x17,
        18: 0x1e, 19: 0x1f, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
        24: 0x2e, 25: 0x26, 26: 0x24, 27: 0x2d, 28: 0x25, 29: 0x27,
        30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2f, 34: 0x0c, 35: 0x13,
        36: 0x28, 37: 0x0f, 38: 0x0d, 39: 0x34, 40: 0x0e, 41: 0x33,
        42: 0x31, 43: 0x36, 44: 0x38, 45: 0x11, 46: 0x10, 47: 0x37,
        48: 0x2b, 49: 0x2c, 50: 0x35, 51: 0x2a, 53: 0x29,
        96: 0x3e, 97: 0x3f, 98: 0x40, 99: 0x3c, 100: 0x41,
        101: 0x42, 103: 0x44, 109: 0x43, 111: 0x45,
        114: 0x49, 115: 0x4a, 116: 0x4b, 117: 0x4c, 118: 0x3d,
        119: 0x4d, 120: 0x3b, 121: 0x4e, 122: 0x3a,
        123: 0x50, 124: 0x4f, 125: 0x51, 126: 0x52,
    ]
}
