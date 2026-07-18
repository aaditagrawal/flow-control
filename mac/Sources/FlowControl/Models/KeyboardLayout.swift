import Foundation

/// A lighting effect exposed by the Flow Lite 84 Windows driver.
///
/// `id` is the stable mode slot used by the app. `rawValue` is retained
/// separately because the Windows data contains three distinct slots whose
/// raw value is `0xff`.
struct LightingMode: Identifiable, Hashable {
    let id: UInt8
    let rawValue: UInt8
    let name: String
    let supportsBrightness: Bool
    let supportsSpeed: Bool
}

/// The exact ANSI Flow Lite 84 physical layout transcribed from the manual.
/// Rows and keys are ordered exactly as they appear in the device's 84-key map.
enum KeyboardLayout {
    static let rows: [[PhysicalKey]] = [
        [
            PhysicalKey("escape", "Esc"),
            PhysicalKey("f1", "F1", spacerBefore: 0.5),
            PhysicalKey("f2", "F2"),
            PhysicalKey("f3", "F3"),
            PhysicalKey("f4", "F4"),
            PhysicalKey("f5", "F5"),
            PhysicalKey("f6", "F6"),
            PhysicalKey("f7", "F7"),
            PhysicalKey("f8", "F8"),
            PhysicalKey("f9", "F9"),
            PhysicalKey("f10", "F10"),
            PhysicalKey("f11", "F11"),
            PhysicalKey("f12", "F12"),
            PhysicalKey("print-screen", "PrtSc", spacerBefore: 0.5),
            PhysicalKey("insert", "Ins"),
            PhysicalKey("delete", "Del"),
        ],
        [
            PhysicalKey("backquote", "`"),
            PhysicalKey("digit-1", "1"),
            PhysicalKey("digit-2", "2"),
            PhysicalKey("digit-3", "3"),
            PhysicalKey("digit-4", "4"),
            PhysicalKey("digit-5", "5"),
            PhysicalKey("digit-6", "6"),
            PhysicalKey("digit-7", "7"),
            PhysicalKey("digit-8", "8"),
            PhysicalKey("digit-9", "9"),
            PhysicalKey("digit-0", "0"),
            PhysicalKey("digit-minus", "-"),
            PhysicalKey("digit-equal", "="),
            PhysicalKey("backspace", "Backspace", width: 2),
            PhysicalKey("home", "Home", spacerBefore: 1),
        ],
        [
            PhysicalKey("tab", "Tab", width: 1.5),
            PhysicalKey("key-q", "Q"),
            PhysicalKey("key-w", "W"),
            PhysicalKey("key-e", "E"),
            PhysicalKey("key-r", "R"),
            PhysicalKey("key-t", "T"),
            PhysicalKey("key-y", "Y"),
            PhysicalKey("key-u", "U"),
            PhysicalKey("key-i", "I"),
            PhysicalKey("key-o", "O"),
            PhysicalKey("key-p", "P"),
            PhysicalKey("bracket-left", "["),
            PhysicalKey("bracket-right", "]"),
            PhysicalKey("backslash", "\\", width: 1.5),
            PhysicalKey("end", "End", spacerBefore: 1),
        ],
        [
            PhysicalKey("caps-lock", "Caps", width: 1.75),
            PhysicalKey("key-a", "A"),
            PhysicalKey("key-s", "S"),
            PhysicalKey("key-d", "D"),
            PhysicalKey("key-f", "F"),
            PhysicalKey("key-g", "G"),
            PhysicalKey("key-h", "H"),
            PhysicalKey("key-j", "J"),
            PhysicalKey("key-k", "K"),
            PhysicalKey("key-l", "L"),
            PhysicalKey("semicolon", ";"),
            PhysicalKey("quote", "'"),
            PhysicalKey("enter", "Enter", width: 2.25),
            PhysicalKey("page-up", "PgUp", spacerBefore: 1),
        ],
        [
            PhysicalKey("shift-left", "Shift", width: 2.25),
            PhysicalKey("key-z", "Z"),
            PhysicalKey("key-x", "X"),
            PhysicalKey("key-c", "C"),
            PhysicalKey("key-v", "V"),
            PhysicalKey("key-b", "B"),
            PhysicalKey("key-n", "N"),
            PhysicalKey("key-m", "M"),
            PhysicalKey("comma", ","),
            PhysicalKey("period", "."),
            PhysicalKey("slash", "/"),
            PhysicalKey("shift-right", "Shift", width: 1.75),
            PhysicalKey("arrow-up", "↑"),
            PhysicalKey("page-down", "PgDn", spacerBefore: 1),
        ],
        [
            PhysicalKey("control-left", "Ctrl", width: 1.25),
            PhysicalKey("meta-left", "Win/⌘", width: 1.25),
            PhysicalKey("alt-left", "Alt/⌥", width: 1.25),
            PhysicalKey("space", "Space", width: 6.25),
            PhysicalKey("alt-right", "Alt/⌘", width: 1.25),
            PhysicalKey("fn", "Fn", width: 1.25),
            PhysicalKey("control-right", "Ctrl", width: 1.25),
            PhysicalKey("arrow-left", "←", spacerBefore: 0.25),
            PhysicalKey("arrow-down", "↓"),
            PhysicalKey("arrow-right", "→"),
        ],
    ]

    /// USB HID keyboard usages for every ordinary key. Fn is intentionally
    /// absent because it is a firmware layer action, not a USB keyboard usage.
    static let hidUsages: [String: UInt16] = [
        "escape": 0x29,
        "f1": 0x3a, "f2": 0x3b, "f3": 0x3c, "f4": 0x3d,
        "f5": 0x3e, "f6": 0x3f, "f7": 0x40, "f8": 0x41,
        "f9": 0x42, "f10": 0x43, "f11": 0x44, "f12": 0x45,
        "print-screen": 0x46, "insert": 0x49, "delete": 0x4c,
        "backquote": 0x35,
        "digit-1": 0x1e, "digit-2": 0x1f, "digit-3": 0x20,
        "digit-4": 0x21, "digit-5": 0x22, "digit-6": 0x23,
        "digit-7": 0x24, "digit-8": 0x25, "digit-9": 0x26,
        "digit-0": 0x27, "digit-minus": 0x2d, "digit-equal": 0x2e,
        "backspace": 0x2a, "home": 0x4a, "tab": 0x2b,
        "key-q": 0x14, "key-w": 0x1a, "key-e": 0x08, "key-r": 0x15,
        "key-t": 0x17, "key-y": 0x1c, "key-u": 0x18, "key-i": 0x0c,
        "key-o": 0x12, "key-p": 0x13,
        "bracket-left": 0x2f, "bracket-right": 0x30, "backslash": 0x31,
        "end": 0x4d, "caps-lock": 0x39,
        "key-a": 0x04, "key-s": 0x16, "key-d": 0x07, "key-f": 0x09,
        "key-g": 0x0a, "key-h": 0x0b, "key-j": 0x0d, "key-k": 0x0e,
        "key-l": 0x0f, "semicolon": 0x33, "quote": 0x34, "enter": 0x28,
        "page-up": 0x4b, "shift-left": 0xe1,
        "key-z": 0x1d, "key-x": 0x1b, "key-c": 0x06, "key-v": 0x19,
        "key-b": 0x05, "key-n": 0x11, "key-m": 0x10,
        "comma": 0x36, "period": 0x37, "slash": 0x38,
        "shift-right": 0xe5, "arrow-up": 0x52, "page-down": 0x4e,
        "control-left": 0xe0, "meta-left": 0xe3, "alt-left": 0xe2,
        "space": 0x2c, "alt-right": 0xe6, "control-right": 0xe4,
        "arrow-left": 0x50, "arrow-down": 0x51, "arrow-right": 0x4f,
    ]

    /// Keymap record index in each 128-entry firmware layer.
    ///
    /// The firmware uses a fixed full-size matrix address space even on the
    /// 84-key board. Consequently, visual row order is *not* flash order. The
    /// gaps below are reserved positions such as Scroll Lock, Pause, Fn2 and
    /// numpad keys. This mapping is taken from the official CID 1 / MID 1
    /// configuration's indexed rectangles and default records, then narrowed
    /// to keys physically present in the Flow Lite 84 manual.
    static let flashIndexByKeyID: [String: Int] = [
        "escape": 0,
        "f1": 1, "f2": 2, "f3": 3, "f4": 4,
        "f5": 5, "f6": 6, "f7": 7, "f8": 8,
        "f9": 9, "f10": 10, "f11": 11, "f12": 12,
        "print-screen": 13,

        "backquote": 16,
        "digit-1": 17, "digit-2": 18, "digit-3": 19,
        "digit-4": 20, "digit-5": 21, "digit-6": 22,
        "digit-7": 23, "digit-8": 24, "digit-9": 25,
        "digit-0": 26, "digit-minus": 27, "digit-equal": 28,
        "backspace": 29, "insert": 30, "home": 31,

        "tab": 32,
        "key-q": 33, "key-w": 34, "key-e": 35, "key-r": 36,
        "key-t": 37, "key-y": 38, "key-u": 39, "key-i": 40,
        "key-o": 41, "key-p": 42,
        "bracket-left": 43, "bracket-right": 44, "backslash": 45,
        "delete": 46, "page-up": 47,

        "caps-lock": 48,
        "key-a": 49, "key-s": 50, "key-d": 51, "key-f": 52,
        "key-g": 53, "key-h": 54, "key-j": 55, "key-k": 56,
        "key-l": 57, "semicolon": 58, "quote": 59, "enter": 60,
        "end": 62, "page-down": 63,

        "shift-left": 64,
        "key-z": 65, "key-x": 66, "key-c": 67, "key-v": 68,
        "key-b": 69, "key-n": 70, "key-m": 71,
        "comma": 72, "period": 73, "slash": 74, "shift-right": 75,
        "arrow-up": 78,

        "control-left": 80, "meta-left": 81, "alt-left": 82,
        "space": 85, "alt-right": 87, "fn": 88, "control-right": 90,
        "arrow-left": 93, "arrow-down": 94, "arrow-right": 95,
    ]
}
