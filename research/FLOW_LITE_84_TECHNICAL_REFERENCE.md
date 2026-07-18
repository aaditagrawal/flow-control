# LoFree Flow Lite 84 technical reference

Last updated: 2026-07-15. This document consolidates the evidence and live results for the ANSI Flow Lite 84 used by this project. “Verified” means observed on the connected firmware `v1.66`, CID/MID `1/1`, unless stated otherwise. Shared LoFree driver features are not assumed to work on this keyboard.

## Hardware and HID identity

| Field | Observed value |
| --- | --- |
| USB product / manufacturer | `Air84@Lofree` / `Compx` |
| VID:PID | `05AC:024F` |
| Device revision / firmware | USB revision `0x0166`; command response `v1.66` |
| CID / MID | `1 / 1` |
| USB speed / serial | 12 Mbps / no serial exposed |
| Configuration collection | primary consumer usage `0x000C:0x0001`, containing vendor usage `0xFF02:0x0002` |
| Configuration report | report ID `0x08`, 16-byte input and output payloads |
| macOS interface maxima | 21-byte input, 20-byte output (the interface also contains other numbered reports) |

The device exposes three macOS IOHID devices: keyboard (`0x01:0x06`, 8-byte input/1-byte output), consumer/vendor configuration, and pointer (`0x01:0x02`). The pointer descriptor declares relative vertical-wheel (`0x01:0x38`) and horizontal-pan (`0x0C:0x0238`) elements plus five mouse buttons. This provides a possible host path for the physical roller, but a live capture must still distinguish it from Consumer-page volume events because the shared firmware also exposes mouse actions for ordinary remapped keys. The vendor collection declares report `0x13` with a 19-byte payload. Flow Control accepts only the exact VID/PID, primary consumer collection, report sizes, and a report-8 element beneath `0xFF02:0x0002`; matching VID/PID alone is insufficient.

Evidence: `research/wired-device.md`, `mac/Sources/FlowControl/Services/FlowHIDService.swift`, `RECCE.md`.

## Report-8 protocol

Commands are 16-byte payloads. macOS `IOHIDDeviceSetReport` is given a 17-byte buffer consisting of the report ID followed by the payload; the input callback receives the 16-byte payload.

| Byte | Meaning |
| --- | --- |
| 0 | command |
| 1 | response status (`0` is success); zero/reserved in requests |
| 2–3 | big-endian flash address for flash commands |
| 4 | keyboard endpoint flag `0x80` plus payload length |
| 5–14 | up to 10 data bytes |
| 15 | report checksum |

The outgoing checksum makes `(report ID + sum(bytes 0...15)) mod 256 == 0x55`. Data records separately use `0x55 - sum(data)` modulo 256. Two-byte scalar records are `[value, 0x55 - value]`.

Implemented command values are identity `0x01`, online `0x03`, battery `0x04`, flash write `0x07`, flash read `0x08`, current profile `0x0E`, and device version `0x12`. Identity uses an eight-byte nonce; response bytes 9–11 contain CID, MID, and transport. Transport 2 or 3 is accepted as wired. Battery uses bytes 5–8; version uses bytes 5–6.

Flash transfers use at most 10 bytes per report. The native client serializes transactions and complete configuration operations, retries timeouts up to five times, and gives each attempt 200 ms. Reads verify opcode, status, address, and length. Every production write is followed by an exact flash readback; incoming reports are not currently validated with the outgoing-report checksum rule.

Golden vectors and codecs: `mac/Tests/FlowControlTests/FlowProtocolTests.swift`, `mac/Sources/FlowControl/Support/FlowProtocol.swift`, and `packages/protocol/src/`.

## Flash map and write boundary

| Address/range | Size / format | Status |
| --- | --- | --- |
| `0` | Windows base, 128 × 4 bytes | enabled; 84 physical slots used |
| `512` | Windows Fn, 128 × 4 | enabled |
| `1536` | macOS base, 128 × 4 | enabled |
| `2048` | macOS Fn, 128 × 4 | enabled |
| `6176...7455` | 128 custom-light records × 10 | read-verified; writes excluded |
| `8496` | current light mode complement pair | enabled |
| `8498` | lighting enabled complement pair | enabled |
| `8500` | backlight-off time complement pair | enabled |
| `8544 + mode × 32` | 16 effect records × 32 | only four-byte headers written |
| `9408` | polling-rate complement pair | enabled |
| `9416` | current OS system complement pair | enabled |
| `9418` | Fn lock complement pair | enabled |
| `9420` | full-key lock complement pair | enabled |
| `10064 + slot × 384` | 15 macro slots | enabled |

The allowlist in `FlowHIDService.isOrdinaryConfigurationRange` excludes unknown storage, iOS/Android/Fn2 maps, custom-light writes, firmware, bootloader, receiver pairing, clear/reset, and update operations. Firmware update, pairing, factory reset, and bootloader entry are deliberately absent from the native command enum.

## Keymaps, actions, macros, and settings

Each assignment is `[family, valueLo, valueHi, checksum]`. The low nibble identifies the family; the firmware uses high-nibble flags in some defaults. Confirmed/catalogued families include disabled `0x00`, modifiers `0x01`, keyboard usages `0x02`, consumer/media `0x03`, device actions `0x05`, Fn/Mac Fn `0x06`, combinations `0x07`, macros `0x08`, profiles/queues `0x09`, and mouse `0x0A`. The native app exposes only actions with established values and preserves unknown read values without pretending to identify them. Multi-Screen, Windows Menu, Voice Assistant, Lock, generic Fn2/sequences, and several shared-driver actions remain excluded from writes.

Combination family `0x07` stores `[0x07, modifierMask, keyUsage, checksum]`, using the standard HID modifier bits. The factory macOS screenshot record `0x200A` therefore means Shift + Command + 3. The official Windows `on_MacroSave_clicked` object code constructs macro assignments as `[0x08, slot, repeatCount, checksum]`; the native app emits repeat count `1` and slots `0...14`. Its macro editor can expand each shortcut into balanced modifier/key press and release events, so multiple shortcuts can be placed in one macro and the macro assigned to any physical key.

The physical layout is 84 keys mapped into each 128-record layer. Windows/macOS base and Fn layers are read and edited independently. iOS, Android, and Fn2 storage exists in the generic protocol but is not advertised for this CID/MID. There is no evidence that roller rotation is remappable in firmware. The official CID/MID 1 Windows configuration does contain an otherwise hidden keymap record at slot `83`, labelled `Mute` and set to Consumer usage `0xE2` on every advertised map. This is a strong candidate for a clickable roller press and may be persistently remappable once a live capture confirms it.

There are 15 macro slots of 384 bytes. Bytes 0–30 hold a UTF-8 name (maximum 30 bytes), byte 31 is the event count (maximum 70), and five-byte events begin at byte 32. An event stores press/release plus a four-bit family, little-endian value, and big-endian 16-bit delay. The checksum follows the last event. Press/release timing and one-shot key assignment are supported; the Windows UI’s until-release modes are not exposed because their persistence encoding has not been verified.

Verified device settings are 125/250/500/1000 Hz polling, Windows/macOS system, Fn lock, full-key lock, and backlight-off values `0,1,3,6,12,30,60,90`. Higher polling rates, N-key rollover, WASD swap, scan time, low latency, boot animation, and music state occur in shared storage/Windows UI but remain capability-gated.

Profiles in the native app are JSON import/export plus automatic pre-write backups in `~/Library/Application Support/FlowControl/Backups`. The Windows driver also has named profile management; the native app does not currently mutate the protocol’s on-device current-profile command.

## Built-in lighting

The Flow Lite is white-backlit, not per-key RGB. Windows row IDs and firmware mode bytes are distinct:

| Windows label | Firmware mode | Native support |
| --- | ---: | --- |
| Ripple | `0x08` | yes |
| Touch Effect | `0x07` | yes |
| Snow Trace | `0x04` | yes |
| Sine Wave | `0x06` | yes |
| Breathing | `0x01` | yes |
| Always On | `0x00` | yes; no speed control |
| Snake | `0x09` | yes |
| Rainbow Cycle | `0x02` | yes, despite monochrome hardware |
| Seven-color Change | `0x03` | yes, despite monochrome hardware |
| Off / Flow / Season Blossom | `0xFF` placeholders | not selectable |

Brightness and speed are firmware levels `0...4` (the Windows UI displays 1...5). A 32-byte effect record contains `[colorIndex, speed, brightness, checksum]` plus seven four-byte color records. For level changes, Flow Control preserves the record and writes only the four-byte header.

### Atomic mode activation

Changing only the mode pair can produce a successful readback while leaving the effect engine dormant. Firmware `v1.66` requires the mode and enabled-state pairs together. Selecting Sine Wave while enabled therefore writes `[06, 4F, 01, 54]` at address 8496. Flow Control writes the target effect header first, then this four-byte selection. The regression test switches away, switches back to Sine Wave, verifies readback, and restores the original state.

## Custom lighting and arbitrary animations

There is meaningful evidence that custom lighting is possible, but arbitrary animations are not yet safe to expose.

The official generic web protocol defines 128 ten-byte records at address 6176. Each record contains:

```text
[type, streamIndex, streamListIndex, runningIndex, runningListIndex,
 packed(speed << 4 | brightness), red, green, blue, checksum]
```

A read-only dump from the physical `v1.66` board decoded all 128 records with 128/128 valid checksums. Its type distribution was `{0: 107, 1: 13, 3: 8}`. Type-1 records had populated ordered stream pairs (beginning `1/1`, etc.), and type-3 records were also populated. This confirms real custom-map data on this board, rather than merely generic dead code.

The CID/MID 1 Windows configuration has `CusVisible=1` and enables three custom choices corresponding to Off, Breathing, and Always On; Marquee and Light Trail rows are commented out. The generic web client exposes setters for stream type `1` and running type `4`, while the live board also contains type `3`. One official single-record web setter appears to place its checksum at byte 3, whereas the full-profile encoder and the 128 valid live records use byte 9. The latter is internally consistent, but this discrepancy is another reason writes remain disabled.

Windows object code treats raw lighting mode `0x0B` as the single custom-mode
activation value. That is strong static evidence, but it has not yet been
selected on the physical keyboard by this project.

What this supports is a firmware-defined per-key pattern editor assembled from type/index parameters. No arbitrary frame-buffer upload or safe high-rate live-frame transport has been identified. Continually writing flash to simulate frames would be slow and risks storage wear. The Windows music UI captures system audio, but its runtime HID stream is not yet reverse-engineered and Whisky cannot pass this keyboard through.

Safe next gates are: preserve the full custom-map snapshot; decode the type-1/type-3 sequences against visible behavior; reversibly verify custom-mode `0x0B`; capture one official custom edit on real Windows/WebHID; then perform one bounded record write, readback, visual check, and exact restore. Until all gates pass, the native write allowlist must continue excluding `6176...7455`.

## macOS Input Monitoring and signing

IOHID report access is protected by Input Monitoring. Flow Control checks `IOHIDCheckAccess` for ListenEvent request type 1, calls `IOHIDRequestAccess` when needed, and fails with an actionable message until permission is granted and the app is reopened.

The observed permissions failure was not USB detection: System Settings showed Flow Control enabled, but `tccd` logged `Failed to match existing code requirement`. The saved TCC entry referred to an older ad-hoc build’s changing `cdhash`, while the installed app had a certificate-based designated requirement. Toggling the stale row did not replace its requirement. The successful recovery was to quit the app, run `tccutil reset ListenEvent dev.flowcontrol.mac`, remove/re-add the installed `/Applications/Flow Control.app`, enable it, authorize with Touch ID, and reopen it.

Local builds now use `script/sign_local_app.sh`, which creates one persistent, self-signed `CA:FALSE` code-signing identity in an isolated `.local-signing/` keychain and signs with:

```text
identifier "dev.flowcontrol.mac" and certificate leaf = H"<persistent certificate SHA-1>"
```

The keychain is never added to the user search list, the certificate is never trusted or installed system-wide, and the keychain is locked after signing. Deleting `.local-signing/` rotates the identity and requires one new permission grant. This solves local TCC identity stability only; distribution still requires Developer ID signing, hardened runtime, notarization, and stapling.

## Windows application and Whisky

The official `Lofree Key Mapper_v1.1.1.3_2025.09.15_setup.exe` is native Qt 5.9.3/C++, not Electron, and uses standard user-space Windows HID/SetupAPI helpers rather than a custom kernel driver. Static assets and accidentally bundled build artifacts expose its feature catalog and corroborate the report/address protocol.

The extracted x64 app launches under Whisky, but Wine exposes only synthetic HID devices `845E:0001` and `845E:0002`; it does not pass through physical `05AC:024F`. Consequently the official app cannot detect or configure this keyboard in Whisky. This was a pass-through limitation, not evidence of a missing physical interface, and no risky command was sent.

Artifact hashes, package details, and recovery URLs are recorded in `research/lofree-windows-driver/RESEARCH.md`. The vendor’s package title explicitly warns not to use it with other devices.

## Native app architecture and safety behavior

`mac/` is a macOS 14+ SwiftPM SwiftUI executable linked to AppKit and IOKit. `FlowHIDService` owns exact discovery, the input callback/run loop, serialized transactions, codecs, diffed writes, and readback. `AppStore` owns connection/editor state, offline-edit rebase, operation coalescing, scoped Apply, validation, backup, and import/export. Models compare only persisted fields, avoiding false dirty state from regenerated UUIDs or display labels.

Apply snapshots the requested state, creates a backup, writes only changed records, verifies each write immediately, and preserves edits made while a write is running. Lighting-only Apply does not reread or rewrite four keymaps and fifteen macros. Disconnects and stale async completions cannot silently mark an operation successful.

## Verification and live `v1.66` results

Current unit command:

```bash
swift test --package-path mac
```

On 2026-07-15 it executed 32 XCTest cases with 8 explicitly gated hardware tests skipped and no failures, plus 6 Swift Testing cases with no failures. The hardware gates have separately passed against the connected `v1.66`, CID/MID `1/1` board:

- full identity and complete configuration read (four 84-key maps, 15 macros, lighting, settings);
- reversible polling-rate change and restoration;
- scoped brightness/speed change, independent full readback, and restoration;
- combined mode/state/off-time change, minimum/maximum and rapid concurrent writes, and restoration;
- Sine Wave switch-away/switch-back with atomic activation and restoration;
- read-only custom-map dump with 128/128 valid records.

The repeatable harness requires the GUI app to be closed while tests own the HID interface:

```bash
./script/verify_mac.sh
./script/verify_mac.sh --live-read
./script/verify_mac.sh --live-write --repeat 3
```

Individual environment gates are documented in `mac/README.md` and implemented in `mac/Tests/FlowControlTests/FlowHIDIntegrationTests.swift`. All write tests save original state and attempt restoration on both success and failure.

## Remaining unknowns

- semantics and activation values for live custom-light types `1` and `3`, and whether type `4` works on this firmware;
- whether custom lighting can express more than the three enabled Windows choices on CID/MID 1;
- music-reactive transport and whether it is host-streamed or merely toggles firmware state;
- macro repeat/until-release encoding and safe macro-assignment family values;
- whether the volume roller's live directions and any press action exactly match the pointer descriptor, and whether firmware exposes any separate persistent mapping storage for them;
- shared settings such as N-key rollover, WASD swap, scan time, and low latency;
- behavior on Flow Lite variants, other CID/MID combinations, and firmware other than `v1.66`;
- firmware/update/recovery protocol, intentionally outside normal customization scope.

## Evidence index

- `RECCE.md` — project scope, safety history, and high-level findings.
- `research/wired-device.md` — macOS descriptor capture.
- `research/official-web/` — preserved official WebHID assets and manual.
- `research/lofree-windows-driver/RESEARCH.md` — Windows package/static/Whisky analysis and hashes.
- `packages/protocol/src/` and `packages/protocol/test/` — TypeScript protocol extraction and golden vectors.
- `packages/device-flow-lite84/` — capability-gated layout/actions/defaults.
- `mac/Sources/FlowControl/Support/FlowProtocol.swift` — native framing and record codecs.
- `mac/Sources/FlowControl/Services/FlowHIDService.swift` — discovery, transport, allowlist, and verified writes.
- `mac/Sources/FlowControl/Stores/AppStore.swift` — Apply/backup/state behavior.
- `mac/Tests/FlowControlTests/` and `script/verify_mac.sh` — unit, adversarial, and live verification loops.
- `script/build_and_run.sh` and `script/sign_local_app.sh` — app staging and stable local signing.
