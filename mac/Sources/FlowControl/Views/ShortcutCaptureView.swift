import AppKit
import SwiftUI

struct ShortcutCaptureView: View {
    @Binding var modifierMask: UInt8
    @Binding var keyUsage: UInt8
    var targetLabel: String?
    var installsOnCapture = false
    var captured: ((FlowShortcut) -> Void)?
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            captureSurface

            Text("Use at least one modifier plus a key. Escape cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var captureSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(isRecording ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 9)
                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.28), lineWidth: isRecording ? 2 : 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    captureIcon
                    Text(captureTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if !isRecording {
                        Text("Click, then press shortcut")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    captureIcon
                    Text(compactCaptureTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !isRecording {
                        Text("Click to record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)

            ShortcutCaptureBridge(
                modifierMask: $modifierMask,
                keyUsage: $keyUsage,
                isRecording: $isRecording,
                captured: captured
            )
        }
        .frame(height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(isRecording ? "Press a shortcut now" : "Click to start recording")
    }

    private var captureIcon: some View {
        Image(systemName: isRecording ? "record.circle.fill" : "keyboard.badge.ellipsis")
            .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
    }

    private var captureTitle: String {
        if isRecording {
            return targetLabel.map { "Press keys for \($0)…" } ?? "Press shortcut now…"
        }
        if installsOnCapture {
            return targetLabel.map { "Record & Install for \($0)" } ?? "Record & Install Shortcut"
        }
        return targetLabel.map { "Record shortcut for \($0)" } ?? "Record Shortcut"
    }

    private var compactCaptureTitle: String {
        if isRecording { return "Press shortcut…" }
        return installsOnCapture ? "Record & Install" : "Record Shortcut"
    }

    private var accessibilityTitle: String {
        if isRecording {
            return targetLabel.map { "Recording shortcut for \($0)" } ?? "Recording keyboard shortcut"
        }
        if installsOnCapture {
            return targetLabel.map { "Record and install shortcut for \($0)" } ?? "Record and install keyboard shortcut"
        }
        return targetLabel.map { "Record shortcut for \($0)" } ?? "Record keyboard shortcut"
    }
}

struct ShortcutOutputTestView: View {
    let expected: FlowShortcut
    let targetLabel: String

    @State private var observedModifierMask: UInt8 = 0
    @State private var observedKeyUsage: UInt8 = 0
    @State private var isRecording = false
    @State private var observed: FlowShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isRecording ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.28), lineWidth: isRecording ? 2 : 1)

                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "keyboard.fill" : "checkmark.circle")
                        .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                    Text(isRecording ? "Press physical \(targetLabel) now…" : testButtonTitle)
                        .fontWeight(.medium)
                    Spacer()
                    if !isRecording {
                        Text("Expecting \(expectedLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)

                ShortcutCaptureBridge(
                    modifierMask: $observedModifierMask,
                    keyUsage: $observedKeyUsage,
                    isRecording: $isRecording
                ) { shortcut in
                    observed = shortcut
                }
            }
            .frame(height: 38)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isRecording ? "Waiting for physical \(targetLabel)" : testButtonTitle)
            .accessibilityValue(isRecording ? "Press the physical key now" : "Expected output \(expectedLabel)")

            if let observed {
                if observed == expected {
                    Label("Physical key confirmed — received \(expectedLabel)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("shortcut.physical.verified")
                } else {
                    Label("Mismatch — received \(label(for: observed)), expected \(expectedLabel)", systemImage: "xmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("shortcut.physical.mismatch")
                }
            } else {
                Text("Click Test, then press the physical key—not the shortcut itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var testButtonTitle: String {
        observed == nil ? "Test physical \(targetLabel)" : "Test \(targetLabel) again"
    }

    private var expectedLabel: String {
        label(for: expected)
    }

    private func label(for shortcut: FlowShortcut) -> String {
        FlowDefaults.shortcutAction(
            modifierMask: shortcut.modifierMask,
            keyUsage: shortcut.keyUsage
        ).label
    }
}

private struct ShortcutCaptureBridge: NSViewRepresentable {
    @Binding var modifierMask: UInt8
    @Binding var keyUsage: UInt8
    @Binding var isRecording: Bool
    var captured: ((FlowShortcut) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onCapture = { mask, usage in
            modifierMask = mask
            keyUsage = usage
            captured?(FlowShortcut(modifierMask: mask, keyUsage: usage))
        }
        view.onRecordingChanged = { recording in
            isRecording = recording
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderNSView, context: Context) {
        view.onCapture = { mask, usage in
            modifierMask = mask
            keyUsage = usage
            captured?(FlowShortcut(modifierMask: mask, keyUsage: usage))
        }
        view.onRecordingChanged = { recording in
            isRecording = recording
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Record keyboard shortcut")
        view.setAccessibilityValue(isRecording ? "Recording" : "Idle")
    }
}

private final class ShortcutRecorderNSView: NSView {
    var onCapture: ((UInt8, UInt8) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var eventMonitor: Any?
    private var isArmedByClick = false

    // Prevent the window's initial/key-loop focus machinery from silently
    // starting a capture session. The view opts in only for the duration of a
    // direct mouse click.
    override var acceptsFirstResponder: Bool { isArmedByClick }

    override func mouseDown(with event: NSEvent) {
        isArmedByClick = true
        window?.makeFirstResponder(self)
        isArmedByClick = false
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, isArmedByClick {
            startMonitoring()
            onRecordingChanged?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        stopMonitoring()
        onRecordingChanged?(false)
        return super.resignFirstResponder()
    }

    override func removeFromSuperview() {
        stopMonitoring()
        super.removeFromSuperview()
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window === event.window, self.window?.firstResponder === self else {
                return event
            }
            self.capture(event)
            return nil
        }
    }

    private func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func capture(_ event: NSEvent) {
        let modifierMask = ShortcutCaptureMap.modifierMask(from: event.modifierFlags)
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        guard modifierMask != 0,
              let keyUsage = ShortcutCaptureMap.hidUsage(forVirtualKeyCode: event.keyCode) else {
            NSSound.beep()
            return
        }

        onCapture?(modifierMask, keyUsage)
        window?.makeFirstResponder(nil)
    }
}
