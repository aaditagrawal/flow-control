import SwiftUI

struct ActionInspectorView: View {
    let store: AppStore

    @State private var category: ActionCategory?
    @State private var shortcutModifierMask: UInt8 = FlowShortcutModifier.command.rawValue
    @State private var shortcutKeyUsage: UInt8 = 0x04
    @State private var shortcutInstallState: ShortcutInstallState = .idle
    @State private var showsActionBrowser = false
    @State private var showsSpecialMappings = true
    @State private var showsAllSpecialMappings = false

    var body: some View {
        @Bindable var store = store

        List {
            inspectorSummary
                .inspectorControlRow(top: 14, bottom: 8)

            if let factoryDefaultAction {
                factoryResetButton(factoryDefaultAction)
                    .inspectorControlRow(top: 2, bottom: 10)
            }

            shortcutComposer
                .inspectorControlRow(top: 0, bottom: 12)

            shortcutInstallStatus
                .inspectorControlRow(top: 0, bottom: 12)

            if shortcutInstallState == .idle, selectedKeyHasPendingChange, let currentAction {
                pendingChange(currentAction)
                    .inspectorControlRow(top: 0, bottom: 12)
            }

            macroHint
                .inspectorControlRow(top: 0, bottom: 12)

            specialMappingsCard
                .inspectorControlRow(top: 0, bottom: 10)

            actionBrowserToggle
                .inspectorControlRow(top: 0, bottom: showsActionBrowser ? 8 : 14)

            if showsActionBrowser {
                actionBrowserControls
                    .inspectorControlRow(top: 0, bottom: 12)

                ForEach(groupedActions) { group in
                    Section {
                        ForEach(group.actions) { action in
                            Button {
                                shortcutInstallState = .idle
                                store.assign(action)
                            } label: {
                                ActionChoiceRow(action: action, isCurrent: isCurrent(action))
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack(spacing: 7) {
                            Label(group.category.rawValue, systemImage: group.category.systemImage)
                            Spacer()
                            Text(group.actions.count, format: .number)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.top, 4)
                    }
                }
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
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
        Button {
            store.selection = .macros
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .frame(width: 20, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multiple shortcuts")
                        .font(.subheadline.weight(.semibold))
                    Text("Build a macro, then assign it to this key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionBrowserControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: $category) {
                Text("All Categories").tag(ActionCategory?.none)
                ForEach(ActionCategory.allCases) { item in
                    Text(item.rawValue).tag(Optional(item))
                }
            }
            .pickerStyle(.menu)

            TextField("Search actions", text: searchTextBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search available key actions")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    private var actionBrowserToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsActionBrowser.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .frame(width: 20, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse all actions")
                        .font(.subheadline.weight(.semibold))
                    Text("Basic keys and every available assignment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
                    .rotationEffect(.degrees(showsActionBrowser ? 90 : 0))
            }
            .foregroundStyle(.primary)
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsActionBrowser ? "Expanded" : "Collapsed")
    }

    private var specialMappingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsSpecialMappings.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 20, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Special mappings")
                            .font(.subheadline.weight(.semibold))
                        Text("\(store.selectedSystem.title) • \(store.selectedLayer.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(specialMappings.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                        .rotationEffect(.degrees(showsSpecialMappings ? 90 : 0))
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsSpecialMappings ? "Expanded" : "Collapsed")

            if showsSpecialMappings {
                Divider()

                if specialMappings.isEmpty {
                    Text("No shortcut, media, macro, modifier, or device actions are assigned on this layer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSpecialMappings) { mapping in
                        Button {
                            shortcutInstallState = .idle
                            store.selectedKeyID = mapping.key.id
                        } label: {
                            HStack(spacing: 9) {
                                Text(mapping.key.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 54)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 12)
                                Text(mapping.action.label)
                                    .lineLimit(1)
                                Spacer()
                                if store.selectedKeyID == mapping.key.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 0)
                            .padding(.vertical, 6)
                            .background(
                                store.selectedKeyID == mapping.key.id
                                    ? Color.accentColor.opacity(0.11)
                                    : Color.secondary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if specialMappings.count > specialMappingPreviewLimit {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsAllSpecialMappings.toggle()
                            }
                        } label: {
                            HStack {
                                Text(
                                    showsAllSpecialMappings
                                        ? "Show fewer"
                                        : "Show \(specialMappings.count - specialMappingPreviewLimit) more"
                                )
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(showsAllSpecialMappings ? 180 : 0))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { store.searchText = $0 }
        )
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

    private var groupedActions: [ActionGroup] {
        let actionsByCategory = Dictionary(grouping: filteredActions, by: \.category)
        return ActionCategory.allCases.compactMap { category in
            guard let actions = actionsByCategory[category], !actions.isEmpty else { return nil }
            return ActionGroup(category: category, actions: actions)
        }
    }

    private var specialMappings: [DisplayedMapping] {
        guard let keymap = store.configuration.keymaps[store.selectedSystem]?[store.selectedLayer] else {
            return []
        }
        return FlowDefaults.physicalKeys.compactMap { key in
            guard let action = keymap[key.id], action.category != .basic else { return nil }
            return DisplayedMapping(key: key, action: action)
        }
    }

    private var visibleSpecialMappings: [DisplayedMapping] {
        showsAllSpecialMappings
            ? specialMappings
            : Array(specialMappings.prefix(specialMappingPreviewLimit))
    }

    private var specialMappingPreviewLimit: Int { 6 }

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
        HStack(spacing: 8) {
            Text(action.label)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isCurrent {
                Label("Current", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isCurrent ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

private struct ActionGroup: Identifiable {
    let category: ActionCategory
    let actions: [KeyAction]

    var id: ActionCategory { category }
}

private struct DisplayedMapping: Identifiable {
    let key: PhysicalKey
    let action: KeyAction

    var id: String { key.id }
}

private extension View {
    func inspectorControlRow(top: CGFloat, bottom: CGFloat) -> some View {
        padding(.horizontal, 14)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .listRowInsets(EdgeInsets())
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
