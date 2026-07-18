import SwiftUI

struct LightingView: View {
    let store: AppStore

    @State private var showsAppliedConfirmation = false

    var body: some View {
        @Bindable var store = store
        let selectedMode = FlowDefaults.lightingModes.first {
            $0.rawValue == store.configuration.lighting.mode && $0.rawValue != 0xFF
        }

        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "Lighting",
                subtitle: "Tune the keyboard backlight and idle behavior."
            )
            Divider()

            Form {
                Section("Backlight") {
                    Toggle("Enabled", isOn: $store.configuration.lighting.isEnabled)

                    Picker("Effect", selection: $store.configuration.lighting.mode) {
                        ForEach(FlowDefaults.lightingModes.filter { $0.rawValue != 0xFF }) { mode in
                            Text(mode.name).tag(mode.rawValue)
                        }
                    }
                    .frame(maxWidth: 420)

                    LabeledContent("Brightness") {
                        FiveLevelPicker(
                            title: "Backlight brightness",
                            selection: $store.configuration.lighting.brightness,
                            labels: ["0", "1", "2", "3", "4"],
                            valueDescription: brightnessLabel(store.configuration.lighting.brightness),
                            hint: "Choose one of the keyboard's five brightness levels"
                        )
                    }
                    .disabled(selectedMode?.supportsBrightness == false || !store.configuration.lighting.isEnabled)

                    LabeledContent("Effect speed") {
                        FiveLevelPicker(
                            title: "Lighting effect speed",
                            selection: $store.configuration.lighting.speed,
                            labels: ["Slowest", "Slow", "Medium", "Fast", "Fastest"],
                            valueDescription: "\(speedLabel(store.configuration.lighting.speed)), level \(min(store.configuration.lighting.speed, 4)) of 4",
                            hint: "Choose one of the keyboard's five effect speed levels"
                        )
                    }
                    .disabled(selectedMode?.supportsSpeed == false || !store.configuration.lighting.isEnabled)
                }

                Section("Power Saving") {
                    Picker("Turn off after", selection: $store.configuration.lighting.offTime) {
                        Text("Never").tag(UInt8(0))
                        Text("10 seconds").tag(UInt8(1))
                        Text("30 seconds").tag(UInt8(3))
                        Text("1 minute").tag(UInt8(6))
                        Text("2 minutes").tag(UInt8(12))
                        Text("5 minutes").tag(UInt8(30))
                        Text("10 minutes").tag(UInt8(60))
                        Text("15 minutes").tag(UInt8(90))
                    }
                    .frame(maxWidth: 300)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            LightingApplyBar(
                store: store,
                showsAppliedConfirmation: showsAppliedConfirmation,
                apply: applyChanges,
                revert: revertLighting
            )
        }
        .navigationTitle("Lighting")
        .onChange(of: store.configuration.lighting) {
            showsAppliedConfirmation = false
        }
    }

    private func brightnessLabel(_ level: UInt8) -> String {
        "Level \(min(Int(level), 4)) of 4"
    }

    private func speedLabel(_ level: UInt8) -> String {
        ["Slowest", "Slow", "Medium", "Fast", "Fastest"][min(Int(level), 4)]
    }

    private func revertLighting() {
        store.configuration.lighting = store.savedConfiguration.lighting
        showsAppliedConfirmation = false
    }

    private func applyChanges() {
        showsAppliedConfirmation = false
        Task {
            await store.applyChanges(scope: .lighting)
            if store.connectionState == .ready &&
                store.configuration.lighting == store.savedConfiguration.lighting {
                showsAppliedConfirmation = true
            }
        }
    }
}

private struct FiveLevelPicker: View {
    let title: String
    @Binding var selection: UInt8
    let labels: [String]
    let valueDescription: String
    let hint: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(UInt8(0)...UInt8(4), id: \.self) { level in
                Text(labels[Int(level)])
                    .tag(level)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(title)
        .accessibilityValue(valueDescription)
        .accessibilityHint(hint)
        .frame(minWidth: 280, idealWidth: 420, maxWidth: 420, alignment: .leading)
    }
}

private struct LightingApplyBar: View {
    let store: AppStore
    let showsAppliedConfirmation: Bool
    let apply: () -> Void
    let revert: () -> Void

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
            Button("Revert Lighting", action: revert)
                .disabled(!hasLightingChanges || isBusy)
                .help("Restore the last lighting settings read from the keyboard")

            Button(store.isConnected ? "Apply to Keyboard" : "Connect & Apply", action: apply)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canApply(.lighting))
                .help("Back up, write, and verify the pending lighting changes")
                .accessibilityHint(store.isConnected
                    ? "Writes the lighting changes and verifies them by reading the keyboard back"
                    : "Connects to the USB keyboard, writes the lighting changes, and verifies them")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Applying changes")
        } else {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .font(.title3)
                .accessibilityHidden(true)
        }
    }

    private var hasLightingChanges: Bool {
        store.configuration.lighting != store.savedConfiguration.lighting
    }

    private var isBusy: Bool {
        switch store.connectionState {
        case .connecting, .reading, .applying: true
        default: false
        }
    }

    private var statusTitle: String {
        switch store.connectionState {
        case .connecting: return "Connecting to keyboard…"
        case .reading: return "Reading keyboard settings…"
        case .applying: return "Applying and verifying…"
        case .failed: return "Apply needs attention"
        default:
            if showsAppliedConfirmation { return "Changes applied and verified" }
            if hasLightingChanges { return "Lighting changes are pending" }
            if store.hasUnsavedChanges { return "Other changes are pending" }
            if store.isConnected { return "Keyboard is up to date" }
            return "Keyboard is not connected"
        }
    }

    private var statusDetail: String {
        switch store.connectionState {
        case .applying: return "A backup is created before the keyboard is written, then the result is read back."
        case .failed(let message): return message
        default:
            if showsAppliedConfirmation {
                return "The keyboard readback matches this configuration."
            }
            if hasLightingChanges && hasOtherChanges {
                return "Lighting and other workspace changes are pending. This button applies only lighting."
            }
            if hasLightingChanges {
                return "These lighting settings are only a preview until you apply them."
            }
            if store.hasUnsavedChanges {
                return "Other workspace changes remain pending; use the toolbar Apply button for those."
            }
            if store.isConnected {
                return "No unapplied configuration changes."
            }
            return "You can adjust a preview now, but must connect over USB before applying it."
        }
    }

    private var hasOtherChanges: Bool {
        !store.configuration.changes(comparedTo: store.savedConfiguration)
            .subtracting(.lighting)
            .isEmpty
    }

    private var statusSymbol: String {
        if case .failed = store.connectionState { return "exclamationmark.triangle.fill" }
        if showsAppliedConfirmation || (store.isConnected && !store.hasUnsavedChanges) {
            return "checkmark.circle.fill"
        }
        if store.hasUnsavedChanges { return "circle.fill" }
        return "cable.connector.slash"
    }

    private var statusColor: Color {
        if case .failed = store.connectionState { return .orange }
        if showsAppliedConfirmation || (store.isConnected && !store.hasUnsavedChanges) { return .green }
        if store.hasUnsavedChanges { return .orange }
        return .secondary
    }
}
