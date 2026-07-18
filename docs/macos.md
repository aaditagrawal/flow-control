# Native macOS architecture and distribution

Flow Control is a macOS 14+ SwiftPM application using SwiftUI for the editor, AppKit for window/menu-bar lifecycle, and IOKit/IOHID for transport. It does not use a browser runtime, Electron, or a kernel extension.

## Discovery and access

`FlowHIDService` opens only the observed configuration collection and requires report-8 metadata in addition to VID:PID. macOS protects event/report access with Input Monitoring. The app checks `IOHIDCheckAccess` for ListenEvent access, requests it where possible, and asks the user to reopen after granting permission.

Input Monitoring permission is attached to the application's code requirement. If an older local build was ad-hoc signed, its changing identity can leave a stale TCC entry. Remove the stale Flow Control entry, reset the `ListenEvent` record for `dev.flowcontrol.mac` if appropriate, add the current packaged app in **System Settings > Privacy & Security > Input Monitoring**, authorize, then reopen. Do not repeatedly grant permissions to a different executable path.

## Local signing versus public distribution

`script/build_and_run.sh` stages `mac/dist/Flow Control.app`. The local signing script creates an ignored, isolated self-signed identity in `.local-signing/` to keep local TCC identity stable. It is not trusted by macOS, not a Developer ID, and must never be committed, exported, or shipped.

A public build requires a separate release procedure:

1. use an Apple Developer ID Application certificate owned by the release maintainer;
2. enable hardened runtime and use only required entitlements;
3. archive an immutable release artifact and record its SHA-256;
4. submit it to Apple's notarization service, wait for acceptance, and staple the result;
5. verify signature, notarization, and a fresh-machine launch before publishing.

The repository does not currently claim a notarized build exists.
