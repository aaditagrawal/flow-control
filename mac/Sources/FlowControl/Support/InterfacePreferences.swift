import Foundation

enum InterfacePreferences {
    static let keyboardFitsWindowKey = "interface.keyboard.fitsWindow"
    static let keyboardZoomKey = "interface.keyboard.zoom"
    static let showsInspectorKey = "interface.inspector.isVisible"

    static let defaultKeyboardZoom = 1.0
    static let minimumKeyboardZoom = 0.6
    static let maximumKeyboardZoom = 1.5

    static func clampedKeyboardZoom(_ zoom: Double) -> Double {
        min(max(zoom, minimumKeyboardZoom), maximumKeyboardZoom)
    }
}
