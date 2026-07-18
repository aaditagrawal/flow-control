# Flow Control for macOS

A native SwiftUI configurator for the LoFree Flow Lite 84.

This is an application target, not a published Swift package. Its tested hardware
envelope, destructive-operation exclusions, and public distribution requirements
are documented at the repository root: [compatibility](../docs/compatibility.md),
[safety](../docs/safety.md), and [macOS distribution](../docs/macos.md).

Flow Control runs as a menu-bar utility and intentionally stays out of the Dock.
Closing or hiding the main window leaves the menu-bar item alive; choose **Open
Flow Control** there to restore and focus the window. Current key assignments,
macros, lighting, and device settings are stored on the keyboard and continue to
work when Flow Control is hidden or quit. The persistent host process is reserved
for future host-side features such as dial remapping.

The app uses macOS IOHID directly to communicate with the wired keyboard at USB identity `05AC:024F`, vendor usage page `FF02`, report ID `08`. It does not require a browser, web view, Electron runtime, or kernel driver.

## Build and run

From the repository root:

```bash
./script/build_and_run.sh
```

The script builds with SwiftPM, stages `mac/dist/Flow Control.app`, signs it with a persistent project-local development identity, and launches it as a foreground macOS application. Optional modes are `--verify`, `--debug`, `--logs`, and `--telemetry`.

On first connection, allow Flow Control in **System Settings > Privacy & Security > Input Monitoring**, then quit and reopen it. Builds made before the persistent identity was introduced used changing ad-hoc `cdhash` requirements. Remove that stale Flow Control row, add the newly built app, and grant it once. Later local rebuilds retain the same designated requirement.

The first build creates `.local-signing/`, an ignored directory with mode `0700`, containing an isolated keychain and password files with mode `0600`. The keychain is addressed explicitly: it is not added to the user's keychain search list, and its self-signed certificate is not installed in or trusted by macOS. Never import or trust this certificate. The script locks the keychain after each signing operation. Deleting `.local-signing/` rotates the identity and requires one new Input Monitoring grant.

This identity is only for stable local TCC permission. It is not an Apple Developer ID, does not satisfy Gatekeeper distribution policy, and must not be used to distribute the app. A public build requires a Developer ID Application certificate, hardened runtime, and notarization.

## Safety boundary

Normal configuration writes are preceded by a local backup and followed by device readback. The complete configuration read and a reversible 1000 Hz -> 500 Hz -> 1000 Hz write/readback/restore cycle have been validated on the connected firmware 1.66 board.

Lighting brightness and animation speed are the firmware's five discrete levels (`0...4`). Supported effects use the Windows driver's raw firmware values; unavailable `0xFF` placeholder rows are not offered. The app uses the vendor's individual two-byte state setters and checksumed four-byte effect-header write. Reversible live level and adversarial mode/state/timeout/concurrent-write matrices have been validated with full restoration on firmware 1.66.

The Lighting workspace has a persistent status bar beside **Revert Lighting** and **Apply to Keyboard**. Apply snapshots the pending configuration, creates a baseline backup, writes only changed lighting records, and verifies each record immediately. It does not reread all four keymaps and fifteen macro slots for a lighting-only adjustment. Edits made while a write is running remain pending for the next Apply.

Effect selection writes the mode and enabled-state pairs atomically, matching the
official Windows driver. Some firmware effects, including Sine Wave on v1.66,
can remain dormant when only the two mode bytes are changed even though mode
readback succeeds.

Firmware update, bootloader entry, receiver pairing, and factory reset remain intentionally excluded: they are recovery/destructive operations, not keyboard customization, and the vendor's earlier web updater has a documented bricking history. Advanced macro repeat/until-release modes remain omitted; one-shot assignment uses a verified repeat count of one and event press/release timing is supported.

Key Assignment includes a native shortcut composer for Control, Option, Shift,
and Command chords. To map multiple shortcuts to one key, add each shortcut to
a macro, return to Key Assignment, and choose that named macro. Macro key
assignments are emitted as one-shot records and are read back after writing.
Select the key you want to change, click **Record & Install for _key_**, and press
the desired modifier chord. Flow Control writes only that physical key, reads it
back from the keyboard, and shows **Installed and verified** only after the bytes
match. The inspector always separates **On keyboard now** from any staged value
and explains whether the selected macOS/Windows and Base/Fn context is active.
Use **Fine-tune manually** to preview a chord with individual modifier controls,
then choose its explicit install button. The recorder intercepts Command-key menu
equivalents only while focused; press Escape to cancel without changing it.

## Verification

Run the repeatable verifier from the repository root. The live-write mode changes
only lighting settings, verifies every write by reading the keyboard, and restores
the original state even when a test fails:

```bash
./script/verify_mac.sh
./script/verify_mac.sh --live-read
./script/verify_mac.sh --live-write --repeat 3
```

The individual test gates remain available for targeted diagnosis:

```bash
swift test --package-path mac
FLOW_HID_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testConnectedFlowLiteCanReadItsCompleteConfiguration
FLOW_HID_WRITE_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testAppStoreCanApplyVerifyAndRestoreOneSafeSetting
FLOW_HID_LIGHTING_WRITE_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testLightingLevelsCanRoundTripAndRestore
FLOW_HID_LIGHTING_MATRIX_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testLightingModeStateTimeoutAndRapidWritesCanRestore
FLOW_HID_SINE_WRITE_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testSineWaveModeSelectionCanRoundTripAndRestore
FLOW_HID_SHORTCUT_WRITE_INTEGRATION=1 swift test --package-path mac --filter FlowHIDIntegrationTests/testShortcutAndMacroAssignmentsCanRoundTripAndRestore
```
