import SwiftUI

struct KeyAssignmentView: View {
    let store: AppStore

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "Key Assignment",
                subtitle: "Select a key, then choose its action in the inspector."
            ) {
                Picker("System", selection: $store.selectedSystem) {
                    ForEach(KeyboardSystem.allCases) { system in
                        Text(system.title).tag(system)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: 140, idealWidth: 170, maxWidth: 190)
                .accessibilityLabel("Keyboard system")

                Picker("Layer", selection: $store.selectedLayer) {
                    ForEach(KeyboardLayer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: 150, idealWidth: 190, maxWidth: 210)
                .accessibilityLabel("Keyboard layer")
            }

            Divider()

            KeyboardCanvasView(store: store)
                .padding(.bottom, 64)

        }
        .navigationTitle("Key Assignment")
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Divider()
                ConfigurationActionBar(
                    store: store,
                    scope: assignmentApplyScope,
                    workspaceName: "Key Assignments"
                )
            }
        }
    }

    private var assignmentApplyScope: ConfigurationChangeSet {
        let changes = store.configuration.changes(comparedTo: store.savedConfiguration)
        if changes.contains(.keymaps), changes.contains(.macros) {
            return [.keymaps, .macros]
        }
        return .keymaps
    }
}

private struct KeyboardCanvasView: View {
    let store: AppStore

    @AppStorage(InterfacePreferences.keyboardFitsWindowKey) private var fitsWindow = true
    @AppStorage(InterfacePreferences.keyboardZoomKey) private var preferredZoom = InterfacePreferences.defaultKeyboardZoom

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = CGSize(
                width: proxy.size.width,
                height: max(0, proxy.size.height - 41)
            )
            let scale = fitsWindow
                ? KeyboardCanvasLayout.fittingScale(in: viewportSize)
                : CGFloat(InterfacePreferences.clampedKeyboardZoom(preferredZoom))

            VStack(spacing: 0) {
                zoomBar(renderedScale: scale)
                Divider()

                ScrollView([.horizontal, .vertical]) {
                    keyboard(at: scale)
                        .padding(KeyboardCanvasLayout.canvasPadding * scale)
                        .frame(
                            minWidth: viewportSize.width,
                            minHeight: viewportSize.height,
                            alignment: .center
                        )
                }
                .accessibilityLabel("Flow Lite 84 keyboard layout")
            }
        }
    }

    private func keyboard(at scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            KeyboardChassisBackground()
                .frame(
                    width: KeyboardCanvasLayout.chassisSize.width,
                    height: KeyboardCanvasLayout.chassisSize.height
                )

            VStack(alignment: .leading, spacing: KeyboardCanvasLayout.rowSpacing) {
                ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: KeyboardCanvasLayout.keySpacing) {
                        ForEach(row) { key in
                            KeyboardKeyView(
                                key: key,
                                action: currentAction(for: key.id),
                                isSelected: store.selectedKeyID == key.id
                            ) {
                                store.selectedKeyID = key.id
                            }
                            .padding(
                                .leading,
                                CGFloat(key.spacerBefore) * KeyboardCanvasLayout.keyUnit
                            )
                        }
                    }
                }
            }
            .focusSection()
            .frame(
                width: KeyboardCanvasLayout.keyboardSize.width,
                height: KeyboardCanvasLayout.keyboardSize.height,
                alignment: .topLeading
            )
            .padding(KeyboardCanvasLayout.chassisPadding)
        }
        .frame(
            width: KeyboardCanvasLayout.chassisSize.width,
            height: KeyboardCanvasLayout.chassisSize.height,
            alignment: .topLeading
        )
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
            width: KeyboardCanvasLayout.chassisSize.width * scale,
            height: KeyboardCanvasLayout.chassisSize.height * scale,
            alignment: .topLeading
        )
    }

    private func zoomBar(renderedScale: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text("Selected \(selectedKeyLabel) • \(selectedActionLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(fitsWindow ? "The keyboard fits the available space" : "The keyboard uses manual zoom")

            Spacer(minLength: 8)

            Button {
                setManualZoom(Double(renderedScale) - 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .accessibilityLabel("Zoom keyboard out")

            Button {
                setManualZoom(1)
            } label: {
                Text(renderedScale, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(minWidth: 42)
            }
            .help("Show the keyboard at actual size")
            .accessibilityLabel("Keyboard zoom, \(Int((renderedScale * 100).rounded())) percent. Set actual size")

            Button {
                setManualZoom(Double(renderedScale) + 0.1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .accessibilityLabel("Zoom keyboard in")

            Toggle(isOn: $fitsWindow) {
                Label("Fit", systemImage: "arrow.down.left.and.arrow.up.right")
            }
            .toggleStyle(.button)
            .help("Automatically resize the keyboard to fit this window")
            .accessibilityHint("When enabled, the keyboard scales as the window changes size")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.bar)
    }

    private func setManualZoom(_ zoom: Double) {
        preferredZoom = InterfacePreferences.clampedKeyboardZoom(zoom)
        fitsWindow = false
    }

    private func currentAction(for keyID: String) -> KeyAction? {
        store.configuration.keymaps[store.selectedSystem]?[store.selectedLayer]?[keyID]
    }

    private var selectedKeyLabel: String {
        FlowDefaults.physicalKeys.first { $0.id == store.selectedKeyID }?.label
            ?? store.selectedKeyID.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var selectedActionLabel: String {
        currentAction(for: store.selectedKeyID)?.label ?? "Unassigned"
    }
}

private struct KeyboardChassisBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(
            cornerRadius: KeyboardCanvasLayout.chassisCornerRadius,
            style: .continuous
        )
        .fill(chassisGradient)
        .overlay {
            RoundedRectangle(
                cornerRadius: KeyboardCanvasLayout.chassisCornerRadius,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(outerHighlightOpacity), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: KeyboardCanvasLayout.chassisInnerCornerRadius,
                style: .continuous
            )
            .fill(deckColor)
            .overlay {
                RoundedRectangle(
                    cornerRadius: KeyboardCanvasLayout.chassisInnerCornerRadius,
                    style: .continuous
                )
                .strokeBorder(Color.black.opacity(innerEdgeOpacity), lineWidth: 1)
            }
            .padding(KeyboardCanvasLayout.chassisRimWidth)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14),
            radius: 6,
            y: 3
        )
        .accessibilityHidden(true)
    }

    private var chassisGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 0.91, green: 0.83, blue: 0.68)
                        .opacity(colorScheme == .dark ? 0.72 : 0.62),
                    location: 0
                ),
                .init(
                    color: Color(red: 0.70, green: 0.79, blue: 0.88)
                        .opacity(colorScheme == .dark ? 0.68 : 0.58),
                    location: 0.52
                ),
                .init(
                    color: Color(red: 0.86, green: 0.80, blue: 0.68)
                        .opacity(colorScheme == .dark ? 0.70 : 0.60),
                    location: 1
                ),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var deckColor: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.98 : 0.94)
    }

    private var outerHighlightOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.62
    }

    private var innerEdgeOpacity: Double {
        colorScheme == .dark ? 0.48 : 0.18
    }
}

private struct KeyboardKeyView: View {
    let key: PhysicalKey
    let action: KeyAction?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                Text(key.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let action, action.label != key.label {
                    Text(action.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(
                width: max(KeyboardCanvasLayout.minimumKeyWidth, CGFloat(key.width) * KeyboardCanvasLayout.keyUnit),
                height: KeyboardCanvasLayout.keyHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyboardKeyButtonStyle(isSelected: isSelected))
        .accessibilityLabel("\(key.label), assigned to \(action?.label ?? "default")")
        .accessibilityHint("Select this key to change its assignment")
        .help("\(key.label) • \(action?.label ?? "Default assignment")")
    }
}

private struct KeyboardKeyButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(configuration.isPressed ? 0.18 : 0.09))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
