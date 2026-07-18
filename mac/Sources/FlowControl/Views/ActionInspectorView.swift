import SwiftUI

struct ActionInspectorView: View {
    let store: AppStore

    @State private var category: ActionCategory?
    @State private var shortcutModifierMask: UInt8 = FlowShortcutModifier.command.rawValue
    @State private var shortcutKeyUsage: UInt8 = 0x04
    @State private var shortcutInstallState: ShortcutInstallState = .idle

    var body: some View {
        @Bindable var store = store

        List {
            inspectorSummary
                .inspectorControlRow(top: 10, bottom: 6)

            if let factoryDefaultAction {
                factoryResetButton(factoryDefaultAction)
                    .inspectorControlRow(top: 2, bottom: 6)
            }

            shortcutComposer
                .inspectorControlRow(top: 2, bottom: 8)

            shortcutInstallStatus
                .inspectorControlRow(top: 0, bottom: 8)

            if shortcutInstallState == .idle, selectedKeyHasPendingChange, let currentAction {
                pendingChange(currentAction)
                    .inspectorControlRow(top: 0, bottom: 8)
            }

            macroHint
                .inspectorControlRow(top: 0, bottom: 6)

            TextField("Search actions", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search available key actions")
                .inspectorControlRow(top: 2, bottom: 6)

            Picker("Other Actions", selection: $category) {
                Text("All Actions").tag(ActionCategory?.none)
                ForEach(ActionCategory.allCases) { item in
                    Text(item.rawValue).tag(Optional(item))
                }
            }
            .inspectorControlRow(top: 0, bottom: 8)

            ForEach(filteredActions) { action in
                Button {
                    shortcutInstallState = .idle
                    store.assign(action)
                } label: {
                    ActionChoiceRow(action: action, isCurrent: isCurrent(action))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("action-inspector.scroll")
        .onChange(of: shortcutEditorIdentity, initial: true) {
            synchronizeShortcutEditor()
        }
        .onChange(of: selectedKeyContextIdentity) {
            shortcutInstallState = .idle
        }
    }

    private var inspectorSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Action")
                    .font(.headline)
                Text(selectedKeyLabel)
                    .font(.title3.weight(.semibold))
                Text("\(store.selectedSystem.title) • \(store.selectedLayer.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(store.isConnected ? "On keyboard now" : "Last device read", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(savedAction?.label ?? "Unknown")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .padding(9)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("key-assignment.on-keyboard")

            Text(selectedContextDescription)
                .font(.caption)
                .foregroundStyle(selectedContextIsActive ? Color.secondary : Color.orange)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-inspector.summary")
    }

    private func factoryResetButton(_ factoryDefaultAction: KeyAction) -> some View {
        Button {
            installAction(factoryDefaultAction)
        } label: {
            Label(
                "Reset to Factory Default (\(factoryDefaultAction.label))",
                systemImage: "arrow.counterclockwise"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(selectedKeyUsesFactoryDefault || shortcutInstallState.isInstalling || store.isBusy)
        .help(
            selectedKeyUsesFactoryDefault
                ? "\(selectedKeyLabel) already matches its factory default"
                : "Restore only \(selectedKeyLabel) to \(factoryDefaultAction.label), then verify it on the keyboard"
        )
        .accessibilityIdentifier("key-assignment.reset-default")
    }

    private var shortcutComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Shortcut for \(selectedKeyLabel)", systemImage: "command")
                .font(.subheadline.weight(.semibold))

            ShortcutComposerView(
                modifierMask: $shortcutModifierMask,
                keyUsage: $shortcutKeyUsage,
                submitTitle: "Install \(shortcutPreviewLabel) on \(selectedKeyLabel)",
                targetLabel: selectedKeyLabel,
                submitImmediatelyWhenCaptured: true
            ) { shortcut in
                installShortcut(shortcut)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .disabled(shortcutInstallState.isInstalling || store.isBusy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-inspector.shortcut-composer")
    }

    private func pendingChange(_ currentAction: KeyAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(selectedKeyLabel) will send \(currentAction.label)", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))
            Text("Staged only — the keyboard has not changed yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Undo") {
                    store.revertSelectedKeyAssignment()
                }
                Spacer()
                Button(assignmentApplyTitle) {
                    Task { await store.applyChanges(scope: selectedAssignmentApplyScope) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canApply(selectedAssignmentApplyScope))
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("key-assignment.pending")
    }

    private var macroHint: some View {
        HStack {
            Text("For multiple shortcuts, build a macro and assign it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Macros") {
                store.selection = .macros
            }
            .buttonStyle(.link)
        }
    }

    private var currentAction: KeyAction? {
        store.configuration.keymaps[store.selectedSystem]?[store.selectedLayer]?[store.selectedKeyID]
    }

    private var savedAction: KeyAction? {
        store.savedConfiguration.keymaps[store.selectedSystem]?[store.selectedLayer]?[store.selectedKeyID]
    }

    private var factoryDefaultAction: KeyAction? {
        FlowDefaults.configuration.keymaps[store.selectedSystem]?[store.selectedLayer]?[store.selectedKeyID]
    }

    private var selectedKeyUsesFactoryDefault: Bool {
        guard let factoryDefaultAction, let currentAction, let savedAction else { return false }
        return currentAction.family == factoryDefaultAction.family &&
            currentAction.value == factoryDefaultAction.value &&
            savedAction.family == factoryDefaultAction.family &&
            savedAction.value == factoryDefaultAction.value
    }

    private var selectedKeyHasPendingChange: Bool {
        currentAction?.family != savedAction?.family || currentAction?.value != savedAction?.value
    }

    private var selectedKeyLabel: String {
        FlowDefaults.physicalKeys.first { $0.id == store.selectedKeyID }?.label
            ?? store.selectedKeyID.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var selectedContextIsActive: Bool {
        store.selectedSystem == store.configuration.device.currentSystem && store.selectedLayer == .base
    }

    private var selectedContextDescription: String {
        if store.selectedSystem != store.configuration.device.currentSystem {
            return "Not active now: the keyboard is currently in \(store.configuration.device.currentSystem.title) mode."
        }
        if store.selectedLayer == .function {
            return "This assignment runs only while the Fn layer is active."
        }
        return "Active mapping: this is what \(selectedKeyLabel) sends without Fn."
    }

    private var selectedAssignmentApplyScope: ConfigurationChangeSet {
        let changes = store.configuration.changes(comparedTo: store.savedConfiguration)
        if currentAction?.family == 0x08, changes.contains(.macros) {
            return [.keymaps, .macros]
        }
        return .keymaps
    }

    private var assignmentApplyTitle: String {
        selectedAssignmentApplyScope.contains(.macros)
            ? "Apply Key + Macro"
            : "Apply to Keyboard"
    }

    private var shortcutPreviewLabel: String {
        FlowDefaults.shortcutAction(
            modifierMask: shortcutModifierMask,
            keyUsage: shortcutKeyUsage
        ).label
    }

    private var filteredActions: [KeyAction] {
        availableActions.filter { action in
            let matchesCategory = category == nil || action.category == category
            let matchesSearch = store.searchText.isEmpty || action.label.localizedStandardContains(store.searchText)
            return matchesCategory && matchesSearch
        }
    }

    private var availableActions: [KeyAction] {
        let macroActions = store.configuration.macros
            .filter { !$0.events.isEmpty }
            .map { FlowDefaults.macroAction(slot: $0.id, name: $0.name) }
        return (FlowDefaults.actions + macroActions).sorted {
            if $0.category.rawValue == $1.category.rawValue { return $0.label < $1.label }
            return $0.category.rawValue < $1.category.rawValue
        }
    }

    private var shortcutEditorIdentity: String {
        let action = currentAction
        return "\(store.selectedSystem.rawValue)-\(store.selectedLayer.rawValue)-\(store.selectedKeyID)-\(action?.family ?? 0)-\(action?.value ?? 0)"
    }

    private var selectedKeyContextIdentity: String {
        "\(store.selectedSystem.rawValue)-\(store.selectedLayer.rawValue)-\(store.selectedKeyID)"
    }

    @ViewBuilder
    private var shortcutInstallStatus: some View {
        switch shortcutInstallState {
        case .idle:
            EmptyView()
        case .installing(let label):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installing \(label) on \(selectedKeyLabel)…")
                        .font(.subheadline.weight(.semibold))
                    Text("Writing the key and reading it back from the keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("shortcut.installing")
        case .verified(let label):
            VStack(alignment: .leading, spacing: 3) {
                Label("Installed and verified", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text("\(selectedKeyLabel) now sends \(label). The assignment was read back from the keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let savedAction, let expected = FlowShortcut(action: savedAction) {
                    Divider()
                        .padding(.vertical, 4)
                    ShortcutOutputTestView(expected: expected, targetLabel: selectedKeyLabel)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("shortcut.verified")
        case .failed(let label):
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn’t verify \(label)", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(shortcutInstallFailureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let currentAction {
                    Button("Retry Install") {
                        installAction(currentAction)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("shortcut.install.failed")
        }
    }

    private var shortcutInstallFailureMessage: String {
        if case .failed(let message) = store.connectionState {
            return message
        }
        return "The keyboard did not confirm the assignment. It remains staged and has not been presented as installed."
    }

    private func isCurrent(_ action: KeyAction) -> Bool {
        currentAction?.family == action.family && currentAction?.value == action.value
    }

    private func installShortcut(_ shortcut: FlowShortcut) {
        installAction(
            FlowDefaults.shortcutAction(
                modifierMask: shortcut.modifierMask,
                keyUsage: shortcut.keyUsage
            )
        )
    }

    private func installAction(_ action: KeyAction) {
        let system = store.selectedSystem
        let layer = store.selectedLayer
        let keyID = store.selectedKeyID
        let contextIdentity = selectedKeyContextIdentity
        shortcutInstallState = .installing(action.label)
        Task {
            let verified = await store.assignAndApply(
                action,
                system: system,
                layer: layer,
                keyID: keyID
            )
            guard selectedKeyContextIdentity == contextIdentity else { return }
            shortcutInstallState = verified ? .verified(action.label) : .failed(action.label)
        }
    }

    private func synchronizeShortcutEditor() {
        if let currentAction, let shortcut = FlowShortcut(action: currentAction) {
            shortcutModifierMask = shortcut.modifierMask
            shortcutKeyUsage = shortcut.keyUsage
            return
        }
        shortcutModifierMask = FlowShortcutModifier.command.rawValue
        if let usage = KeyboardLayout.hidUsages[store.selectedKeyID], usage < 0xe0 {
            shortcutKeyUsage = UInt8(usage)
        } else {
            shortcutKeyUsage = 0x04
        }
    }
}

private struct ActionChoiceRow: View {
    let action: KeyAction
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.label)
                    .foregroundStyle(.primary)
                Text(action.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private extension View {
    func inspectorControlRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 12, bottom: bottom, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private enum ShortcutInstallState: Equatable {
    case idle
    case installing(String)
    case verified(String)
    case failed(String)

    var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }
}

struct WorkspaceInspectorView: View {
    let store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Configuration")
                    .font(.headline)

                Label(connectionTitle, systemImage: connectionSymbol)
                    .foregroundStyle(connectionColor)

                LabeledContent("Changes", value: store.hasUnsavedChanges ? "Modified" : "Saved")
                LabeledContent("System", value: store.configuration.device.currentSystem.title)
                if let identity = store.identity {
                    LabeledContent("Firmware", value: identity.deviceVersion)
                    if let battery = identity.batteryPercent {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                }

                Divider()

                Text(connectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Changes are backed up automatically before they are written and verified on the keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var connectionTitle: String {
        switch store.connectionState {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .reading: "Reading configuration…"
        case .ready: "Connected"
        case .applying: "Applying and verifying…"
        case .failed: "Needs attention"
        }
    }

    private var connectionDetail: String {
        if case .failed(let message) = store.connectionState { return message }
        if store.isConnected { return "This view reflects the last verified keyboard readback." }
        return "Offline edits stay local until you connect and choose Apply."
    }

    private var connectionSymbol: String {
        switch store.connectionState {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .connecting, .reading, .applying: "arrow.triangle.2.circlepath"
        case .disconnected: "cable.connector.slash"
        }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .ready: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
