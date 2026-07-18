import AppKit
import SwiftUI

@MainActor
final class FlowControlWindowController: NSWindowController, NSWindowDelegate {
    private static let frameAutosaveName = "FlowControlMainWindow"

    init(store: AppStore) {
        let rootView = ContentView(store: store)
            .frame(minWidth: 820, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flow Control"
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AppLifecycle.hideMainWindow()
        return false
    }
}
