import SwiftUI

struct FlowControlMenuBarView: View {
    let store: AppStore

    var body: some View {
        Button("Open Flow Control") {
            AppLifecycle.openMainWindow(store: store)
        }

        Divider()

        Text(deviceStatusLine)
        Text(configurationStatusLine)

        Divider()

        if store.isConnected {
            Button("Refresh Configuration") {
                Task { await store.connectAndRead() }
            }
            .disabled(store.isBusy)

            Button("Disconnect") {
                store.disconnect()
            }
            .disabled(store.isBusy)
        } else {
            Button("Connect / Refresh") {
                Task { await store.connectAndRead() }
            }
            .disabled(store.isBusy)
        }

        Divider()

        Button("Quit Flow Control") {
            AppLifecycle.quit()
        }
        .keyboardShortcut("q")
    }

    private var deviceStatusLine: String {
        let deviceName = shortMenuTitle(store.identity?.productName ?? "Flow Lite 84", limit: 18)
        return "\(deviceName) • \(connectionStatus)"
    }

    private var configurationStatusLine: String {
        if store.hasUnsavedChanges { return "Unapplied edits in window" }
        if store.isConnected { return "On-device settings are active" }
        return "Mappings remain on keyboard"
    }

    private var connectionStatus: String {
        switch store.connectionState {
        case .disconnected: "Offline"
        case .connecting: "Connecting"
        case .reading: "Refreshing"
        case .ready: "Connected"
        case .applying: "Applying"
        case .failed: "Needs attention"
        }
    }

    private func shortMenuTitle(_ title: String, limit: Int) -> String {
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)) + "…"
    }
}
