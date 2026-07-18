import SwiftUI

struct ConfigurationActionBar: View {
    let store: AppStore
    let scope: ConfigurationChangeSet
    let workspaceName: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                status
                Spacer(minLength: 20)
                actions
            }

            VStack(alignment: .leading, spacing: 10) {
                status
                HStack {
                    Spacer()
                    actions
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
        .accessibilityElement(children: .contain)
    }

    private var status: some View {
        HStack(spacing: 10) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Revert \(workspaceName)") {
                store.discardChanges(scope: scope)
            }
            .disabled(!hasScopedChanges || store.isBusy)
            .help("Restore the last \(workspaceName.lowercased()) settings read from the keyboard")

            Button(applyTitle) {
                Task { await store.applyChanges(scope: scope) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canApply(scope))
            .help("Back up, write, and verify the pending \(workspaceName.lowercased()) changes")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if store.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(statusTitle)
        } else {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
    }

    private var hasScopedChanges: Bool {
        !store.configuration.changes(comparedTo: store.savedConfiguration)
            .intersection(scope)
            .isEmpty
    }

    private var applyTitle: String {
        store.isConnected ? "Apply to Keyboard" : "Connect & Apply"
    }

    private var statusTitle: String {
        switch store.connectionState {
        case .connecting: "Connecting to keyboard…"
        case .reading: "Reading keyboard settings…"
        case .applying: "Applying and verifying…"
        case .failed: "Action needed"
        default:
            if hasScopedChanges { "\(workspaceName) changes are pending" }
            else if store.isConnected { "\(workspaceName) is up to date" }
            else { "Keyboard is not connected" }
        }
    }

    private var statusDetail: String {
        switch store.connectionState {
        case .failed(let message): return message
        case .applying: return "A backup is created first, then every write is checked by device readback."
        default:
            if hasScopedChanges {
                return store.isConnected
                    ? "Preview only until you apply these changes."
                    : "Your edits are safe; connect over USB when you are ready to apply them."
            }
            return store.isConnected
                ? "No unapplied \(workspaceName.lowercased()) changes."
                : "You can review and edit offline, then connect before applying."
        }
    }

    private var statusSymbol: String {
        if case .failed = store.connectionState { return "exclamationmark.triangle.fill" }
        if hasScopedChanges { return "circle.fill" }
        if store.isConnected { return "checkmark.circle.fill" }
        return "cable.connector.slash"
    }

    private var statusColor: Color {
        if case .failed = store.connectionState { return .orange }
        if hasScopedChanges { return .orange }
        if store.isConnected { return .green }
        return .secondary
    }
}
