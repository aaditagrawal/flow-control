import SwiftUI

struct MacrosView: View {
    let store: AppStore

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "Macros",
                subtitle: "Build key sequences with explicit press, release, and delay events."
            ) {
                Picker("Macro", selection: $store.selectedMacroID) {
                    ForEach(store.configuration.macros) { macro in
                        Text("\(macro.id + 1). \(macro.name)").tag(macro.id)
                    }
                }
                .frame(minWidth: 170, idealWidth: 230, maxWidth: 280)
                .accessibilityLabel("Macro slot")
            }
            Divider()

            if let index = selectedMacroIndex {
                MacroEditor(macro: $store.configuration.macros[index])
                    .padding(.bottom, 64)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 0) {
                            Divider()
                            ConfigurationActionBar(store: store, scope: .macros, workspaceName: "Macros")
                        }
                    }
            } else {
                ContentUnavailableView("No Macro Selected", systemImage: "record.circle", description: Text("Select a macro slot to edit it."))
            }
        }
        .navigationTitle("Macros")
    }

    private var selectedMacroIndex: Int? {
        store.configuration.macros.firstIndex { $0.id == store.selectedMacroID }
    }
}

private struct MacroEditor: View {
    @Binding var macro: KeyboardMacro
    @State private var showShortcutComposer = false
    @State private var shortcutModifierMask: UInt8 = FlowShortcutModifier.command.rawValue
    @State private var shortcutKeyUsage: UInt8 = 0x04

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $macro.name)
                    .textFieldStyle(.roundedBorder)

                Text("Macros assigned from Key Assignment run once. Advanced repeat and until-release modes are not enabled.")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(maxHeight: 120)

            Divider()

            Table($macro.events) {
                TableColumn("Event") { $event in
                    Picker("Event", selection: $event.state) {
                        Text("Key Down").tag(MacroEvent.State.pressed)
                        Text("Key Up").tag(MacroEvent.State.released)
                    }
                    .labelsHidden()
                }
                .width(min: 90, ideal: 110)

                TableColumn("Action") { $event in
                    Picker("Action", selection: actionBinding(for: $event)) {
                        ForEach(FlowDefaults.actions) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .labelsHidden()
                }
                .width(min: 160, ideal: 240)

                TableColumn("Delay") { $event in
                    HStack(spacing: 4) {
                        TextField("Delay", value: $event.delayMilliseconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Text("ms")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 100, ideal: 120)

                TableColumn("") { $event in
                    Button(role: .destructive) {
                        macro.events.removeAll { $0.id == event.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete event")
                }
                .width(36)
            }
            .overlay {
                if macro.events.isEmpty {
                    ContentUnavailableView(
                        "No Events Yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add a key event or a complete shortcut to begin this macro.")
                    )
                    .allowsHitTesting(false)
                }
            }

            HStack {
                Button {
                    appendEvent(state: .pressed)
                } label: {
                    Label("Add Key Down", systemImage: "plus")
                }

                Button {
                    appendEvent(state: .released)
                } label: {
                    Label("Add Key Up", systemImage: "plus")
                }

                Button {
                    showShortcutComposer = true
                } label: {
                    Label("Add Shortcut…", systemImage: "command")
                }

                Spacer()
                Text("\(macro.events.count) event\(macro.events.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)
        }
        .sheet(isPresented: $showShortcutComposer) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Shortcut to \(macro.name)")
                    .font(.title3.weight(.semibold))
                Text("Each shortcut is expanded into key-down and key-up events. Add this more than once to build a sequence of shortcuts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ShortcutComposerView(
                    modifierMask: $shortcutModifierMask,
                    keyUsage: $shortcutKeyUsage,
                    submitTitle: "Add to Macro",
                    cancel: { showShortcutComposer = false }
                ) { shortcut in
                    append(shortcut)
                    showShortcutComposer = false
                }
            }
            .padding(24)
            .frame(width: 390)
        }
    }

    private func appendEvent(state: MacroEvent.State) {
        guard let action = FlowDefaults.actions.first else { return }
        macro.events.append(
            MacroEvent(
                state: state,
                family: action.family,
                value: action.value,
                label: action.label,
                delayMilliseconds: 20
            )
        )
    }

    private func append(_ shortcut: FlowShortcut) {
        macro.events.append(contentsOf: FlowDefaults.macroEvents(for: shortcut))
    }

    private func actionBinding(for event: Binding<MacroEvent>) -> Binding<KeyAction> {
        Binding(
            get: {
                FlowDefaults.actions.first {
                    $0.family == event.wrappedValue.family && $0.value == event.wrappedValue.value
                } ?? FlowDefaults.actions[0]
            },
            set: { action in
                event.wrappedValue.family = action.family
                event.wrappedValue.value = action.value
                event.wrappedValue.label = action.label
            }
        )
    }
}
