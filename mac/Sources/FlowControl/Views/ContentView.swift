import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let store: AppStore

    @AppStorage(InterfacePreferences.showsInspectorKey) private var showInspector = true
    @State private var showCompactInspector = false

    private let compactInspectorThreshold: CGFloat = 1_180

    var body: some View {
        GeometryReader { proxy in
            let usesCompactInspector = proxy.size.width < compactInspectorThreshold

            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 250)
            } detail: {
                Group {
                    switch store.selection ?? .keymap {
                    case .keymap:
                        KeyAssignmentView(store: store)
                    case .lighting:
                        LightingView(store: store)
                    case .macros:
                        MacrosView(store: store)
                    case .device:
                        DeviceView(store: store)
                    }
                }
            }
            .inspector(isPresented: persistentInspectorBinding(isCompact: usesCompactInspector)) {
                inspectorContent
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        if store.isConnected {
                            store.disconnect()
                        } else {
                            Task { await store.connectAndRead() }
                        }
                    } label: {
                        Label(store.isConnected ? "Disconnect" : "Connect", systemImage: store.isConnected ? "cable.connector.slash" : "cable.connector")
                    }
                    .help(store.isConnected ? "Disconnect the keyboard" : "Connect and read the wired keyboard")
                    .accessibilityHint(store.isConnected ? "Leaves offline edits in place" : "Reads the current configuration without writing")
                }

                ToolbarItemGroup {
                    Button {
                        BackupPanels.importConfiguration(into: store)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import a Flow Control configuration")

                    Button {
                        BackupPanels.exportConfiguration(from: store)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export the current configuration")
                    .disabled(store.identity == nil)

                    Button {
                        store.discardChanges()
                    } label: {
                        Label("Revert All", systemImage: "arrow.uturn.backward")
                    }
                    .help("Discard every unapplied change")
                    .disabled(!store.hasUnsavedChanges || store.isBusy)

                    Button {
                        Task { await store.applyChanges() }
                    } label: {
                        Label("Apply All", systemImage: "checkmark.circle.fill")
                    }
                    .help("Back up, apply, and verify every staged change")
                    .disabled(!store.canApply)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if usesCompactInspector {
                            showCompactInspector.toggle()
                        } else {
                            showInspector.toggle()
                        }
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                    .help(usesCompactInspector ? "Show the inspector in a popover" : "Show or hide the inspector")
                    .accessibilityValue((usesCompactInspector ? showCompactInspector : showInspector) ? "Shown" : "Hidden")
                    .popover(isPresented: $showCompactInspector, arrowEdge: .top) {
                        inspectorContent
                            .frame(
                                width: min(360, max(300, proxy.size.width - 80)),
                                height: min(640, max(360, proxy.size.height - 100))
                            )
                    }
                }
            }
            .task {
                guard case .disconnected = store.connectionState else { return }
                await store.connectAndRead(silentlyWhenUnavailable: true)
            }
            .alert("Keyboard Error", isPresented: errorPresented) {
                if !store.isConnected {
                    Button("Try Again") {
                        Task { await store.connectAndRead() }
                    }
                }
                if errorMayNeedInputMonitoring {
                    Button("Open Input Monitoring") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button("Dismiss", role: .cancel) {
                    store.dismissError()
                }
            } message: {
                if case .failed(let message) = store.connectionState {
                    Text(message)
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if store.selection == .keymap {
            ActionInspectorView(store: store)
                .inspectorColumnWidth(min: 300, ideal: 350, max: 420)
        } else {
            WorkspaceInspectorView(store: store)
                .inspectorColumnWidth(min: 220, ideal: 250, max: 320)
        }
    }

    private func persistentInspectorBinding(isCompact: Bool) -> Binding<Bool> {
        Binding(
            get: { showInspector && !isCompact },
            set: { isPresented in
                guard !isCompact else { return }
                showInspector = isPresented
            }
        )
    }

    private var errorMayNeedInputMonitoring: Bool {
        guard case .failed(let message) = store.connectionState else { return false }
        let normalized = message.lowercased()
        return normalized.contains("input monitoring") ||
            normalized.contains("permission") ||
            normalized.contains("vendor configuration interface")
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: {
                if case .failed = store.connectionState { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { store.dismissError() }
            }
        )
    }
}

@MainActor
enum BackupPanels {
    static func importConfiguration(into store: AppStore) {
        let panel = NSOpenPanel()
        panel.title = "Import Flow Control Configuration"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.importBackup(from: url)
        } catch {
            store.connectionState = .failed(error.localizedDescription)
        }
    }

    static func exportConfiguration(from store: AppStore) {
        let panel = NSSavePanel()
        panel.title = "Export Flow Control Configuration"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Flow-Lite84-Configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportBackup(to: url)
        } catch {
            store.connectionState = .failed(error.localizedDescription)
        }
    }
}
