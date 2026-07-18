import AppKit
import SwiftUI

final class FlowControlAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            AppLifecycle.launchMainWindow(store: FlowControlRuntime.store)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLifecycle.launchMainWindow(store: FlowControlRuntime.store)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.isEmpty {
            AppLifecycle.launchMainWindow(store: FlowControlRuntime.store)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private enum FlowControlRuntime {
    static let store = AppStore()
}

@main
@MainActor
struct FlowControlApp: App {
    @NSApplicationDelegateAdaptor(FlowControlAppDelegate.self) private var appDelegate
    @State private var store = FlowControlRuntime.store
    @AppStorage(InterfacePreferences.keyboardFitsWindowKey) private var keyboardFitsWindow = true
    @AppStorage(InterfacePreferences.keyboardZoomKey) private var keyboardZoom = InterfacePreferences.defaultKeyboardZoom

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AppLifecycle.launchMainWindow(store: FlowControlRuntime.store)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            FlowControlMenuBarView(store: store)
        } label: {
            Label(menuBarLabel, systemImage: "keyboard")
                .accessibilityLabel(menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Keyboard") {
                Button(store.isConnected ? "Disconnect" : "Connect Keyboard") {
                    if store.isConnected {
                        store.disconnect()
                    } else {
                        Task { await store.connectAndRead() }
                    }
                }

                Divider()

                Button("Apply Changes") {
                    Task { await store.applyChanges() }
                }
                .disabled(!store.canApply)
                .keyboardShortcut(.return, modifiers: .command)

                Button("Revert Changes") {
                    store.discardChanges()
                }
                .disabled(!store.hasUnsavedChanges)
                .keyboardShortcut("r", modifiers: [.command, .option])
            }

            CommandGroup(after: .importExport) {
                Button("Import Configuration…") {
                    BackupPanels.importConfiguration(into: store)
                }

                Button("Export Configuration…") {
                    BackupPanels.exportConfiguration(from: store)
                }
                .disabled(store.identity == nil)
            }

            CommandMenu("Keyboard View") {
                Toggle("Fit Keyboard to Window", isOn: $keyboardFitsWindow)
                    .keyboardShortcut("0", modifiers: [.command, .option])

                Divider()

                Button("Zoom In") {
                    keyboardFitsWindow = false
                    keyboardZoom = InterfacePreferences.clampedKeyboardZoom(keyboardZoom + 0.1)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    keyboardFitsWindow = false
                    keyboardZoom = InterfacePreferences.clampedKeyboardZoom(keyboardZoom - 0.1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    keyboardFitsWindow = false
                    keyboardZoom = 1
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private var menuBarLabel: String {
        if store.hasUnsavedChanges { return "Flow •" }
        return store.isConnected ? "Flow" : "Flow —"
    }

    private var menuBarAccessibilityLabel: String {
        if store.hasUnsavedChanges { return "Flow Control, unapplied changes" }
        return store.isConnected ? "Flow Control, keyboard connected" : "Flow Control, keyboard disconnected"
    }
}
