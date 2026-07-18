import SwiftUI

struct ShortcutComposerView: View {
    @Binding var modifierMask: UInt8
    @Binding var keyUsage: UInt8

    var submitTitle = "Assign Shortcut"
    var cancel: (() -> Void)?
    var targetLabel: String?
    var submitImmediatelyWhenCaptured = false
    let submit: (FlowShortcut) -> Void

    @State private var showsManualEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortcutCaptureView(
                modifierMask: $modifierMask,
                keyUsage: $keyUsage,
                targetLabel: targetLabel,
                installsOnCapture: submitImmediatelyWhenCaptured
            ) { shortcut in
                if submitImmediatelyWhenCaptured {
                    submit(shortcut)
                }
            }

            if submitImmediatelyWhenCaptured {
                Text("One step: press the shortcut and Flow Control installs it on the keyboard, then verifies it by reading it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showsManualEditor.toggle()
            } label: {
                HStack {
                    Text("Fine-tune manually")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsManualEditor ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Fine-tune shortcut manually")
            .accessibilityValue(showsManualEditor ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("shortcut.manual.toggle")

            if showsManualEditor {
                manualEditor
                    .padding(.top, 8)
            }

            if !submitImmediatelyWhenCaptured {
                submitRow
            }
        }
    }

    private var manualEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifiers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FlowShortcutModifier.allCases) { modifier in
                    Toggle(isOn: modifierBinding(modifier)) {
                        Text("\(modifier.symbol)  \(modifier.title)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("shortcut.modifier.\(modifier.title.lowercased())")
                }
            }

            Picker("Key", selection: keyUsageBinding) {
                ForEach(FlowDefaults.shortcutKeyActions) { action in
                    Text(action.label).tag(UInt8(action.value))
                }
            }
            .accessibilityIdentifier("shortcut.key")

            if submitImmediatelyWhenCaptured {
                HStack {
                    Text("Staged shortcut")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preview.label)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }

                Text("Manual controls are a preview until you use the install button below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                submitRow
            }
        }
    }

    private var submitRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcut")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(preview.label)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .accessibilityIdentifier("shortcut.preview")
            }

            HStack {
                if let cancel {
                    Button("Cancel", action: cancel)
                }
                Spacer()
                Button(submitTitle) {
                    submit(preview)
                }
                .buttonStyle(.borderedProminent)
                .disabled(modifierMask == 0)
                .accessibilityIdentifier("shortcut.submit")
            }

            if modifierMask == 0 {
                Text("Choose at least one modifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preview: FlowShortcut {
        FlowShortcut(modifierMask: modifierMask, keyUsage: keyUsage)
    }

    private func modifierBinding(_ modifier: FlowShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { modifierMask & modifier.rawValue != 0 },
            set: { enabled in
                var updatedMask = modifierMask
                if enabled {
                    updatedMask |= modifier.rawValue
                } else {
                    updatedMask &= ~modifier.rawValue
                }
                guard !submitImmediatelyWhenCaptured || updatedMask != 0 else {
                    return
                }
                modifierMask = updatedMask
            }
        )
    }

    private var keyUsageBinding: Binding<UInt8> {
        Binding(
            get: { keyUsage },
            set: { updatedUsage in
                keyUsage = updatedUsage
            }
        )
    }
}

private extension FlowShortcut {
    var label: String {
        FlowDefaults.shortcutAction(modifierMask: modifierMask, keyUsage: keyUsage).label
    }
}
