import AppKit

@MainActor
enum AppLifecycle {
    static func launchMainWindow(store: AppStore) {
        openMainWindow(store: store)
    }

    static func openMainWindow(store: AppStore) {
        if mainWindowController == nil {
            mainWindowController = FlowControlWindowController(store: store)
        }
        guard let window = mainWindowController?.window else { return }

        // The editor behaves as a normal app while it is visible. It changes
        // to accessory mode only after the user hides or closes the window.
        presentationGeneration += 1
        let generation = presentationGeneration
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            present(window, generation: generation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                present(window, generation: generation)
            }
        }
    }

    static func hideMainWindow() {
        presentationGeneration += 1
        mainWindowController?.window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    static func quit() {
        NSApp.terminate(nil)
    }

    private static var mainWindowController: FlowControlWindowController?
    private static var presentationGeneration = 0

    private static func present(_ window: NSWindow, generation: Int) {
        guard generation == presentationGeneration else { return }
        NSApp.unhide(nil)
        mainWindowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
