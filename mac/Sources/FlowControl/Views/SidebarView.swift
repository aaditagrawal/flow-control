import SwiftUI

struct SidebarView: View {
    let store: AppStore

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selection) {
            Section("Configure") {
                ForEach(ConfigurationSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Section("Keyboard") {
                ConnectionSummary(store: store)
            }

            Section {
                Button {
                    AppLifecycle.hideMainWindow()
                } label: {
                    Label("Hide to Menu Bar", systemImage: "menubar.rectangle")
                }
                .buttonStyle(.plain)
                .help("Close this window and keep Flow Control available in the menu bar. Current mappings remain on the keyboard.")
                .accessibilityHint("The app stays running without occupying the Dock")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Flow Control")
    }
}

private struct ConnectionSummary: View {
    let store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.identity?.productName ?? "Flow Lite 84")
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard, \(store.identity?.productName ?? "Flow Lite 84"), \(statusText)")
        .accessibilityHint(store.isConnected ? "Use the toolbar to disconnect" : "Use the toolbar to connect over USB")
    }

    private var statusText: String {
        switch store.connectionState {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .reading: "Reading configuration…"
        case .ready: store.hasUnsavedChanges ? "Connected • Edited" : "Connected"
        case .applying: "Applying and verifying…"
        case .failed: "Needs attention"
        }
    }

    private var statusIcon: String {
        switch store.connectionState {
        case .ready: "checkmark.circle.fill"
        case .connecting, .reading, .applying: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .disconnected: "circle"
        }
    }

    private var statusColor: Color {
        switch store.connectionState {
        case .ready: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
