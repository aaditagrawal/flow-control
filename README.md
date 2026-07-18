# Flow Control

Flow Control is a safety-bounded configurator for one observed LoFree Flow Lite 84 wired HID variant. It contains a native macOS 14+ application using IOHID and a browser companion using WebHID, plus protocol codecs and device data used by both implementations.

It is not an official LoFree product, is not a firmware updater, and does not claim compatibility with every keyboard that shares a LoFree driver or USB identifier.

The product is experimental - built with GPT 5.6 Sol (High) using the [ChatGPT Desktop App in Codex Mode](https://chat.com/desktop) with Computer Use for verification.

## Why?

I got a LoFree Flow Lite 84 recently, and it does not ship with native VIA support. Customization is one of the strongest reasons to use a custom keyboard, so this project provides an alternative.

## Installation

### Native macOS app

Requirements: macOS 14 or later, a Swift 6 toolchain, and the keyboard connected in wired mode. Clone the private repository, then build and launch the app from its root:

```sh
git clone https://github.com/aaditagrawal/flow-control.git
cd flow-control
./script/build_and_run.sh --verify
```

The script builds, locally signs, and launches `mac/dist/Flow Control.app`. On first use, allow **Flow Control** in **System Settings → Privacy & Security → Input Monitoring**, quit the app, and reopen it. The local signing identity is for stable development permissions only; it is not a notarized Developer ID release.

### Web app

No installation is required. Open [aaditagrawal.github.io/flow-control](https://aaditagrawal.github.io/flow-control/) in a current Chrome or Edge browser, connect the keyboard by USB, and select **Connect keyboard**. Choose the `Air84@Lofree` device in the browser prompt. Safari and Firefox do not support WebHID.

## Using Flow Control

1. Connect the Flow Lite 84 in wired mode and select **Connect**. The app reads the current keyboard configuration before enabling writes.
2. Choose the relevant macOS/Windows and Base/Fn context, then edit **Key Assignment**, **Lighting**, **Macros**, or **Device** settings.
3. Review the pending changes. Edits remain local until you select **Apply to Keyboard** or **Apply All**.
4. Apply the changes without disconnecting the keyboard. Flow Control creates a backup, writes only the changed records, and verifies the keyboard's readback.
5. Use **Revert** or **Discard** to remove unapplied edits. Use **Export** before substantial changes if you want a portable configuration backup; use **Import** to load one later.

The app supports only the device and firmware boundary documented below. Do not use it for firmware updates, receiver pairing, factory resets, or unsupported keyboards.

## Disclaimer

Try it. This is very much a tech demo that works. 

## Status and tested boundary

The approved native macOS app has been exercised against one ANSI unit identified as `Air84@Lofree` / `Compx` - my keyboard, VID:PID `05AC:024F`, CID/MID `1/1`, firmware `v1.66`, in wired mode. The matching vendor collection is `0xFF02:0x0002`; configuration uses report ID `0x08` with 16-byte payloads. See [compatibility](docs/compatibility.md) and [evidence](docs/evidence-and-research.md).

On that unit the native app reads four keymap contexts, 15 macro slots, built-in white-backlight settings, and selected device settings. Reversible polling-rate and lighting write/readback/restore tests have passed. Other firmware versions, layouts, transport modes, CID/MID values, and LoFree models are not supported merely by resemblance.

## Safety boundary

Ordinary writes are limited to allowlisted configuration ranges. Before a write, the app snapshots state; it writes only the changed records and reads them back. It deliberately does **not** implement firmware flashing, bootloader entry, receiver pairing, factory reset, clear/reset commands, or custom-light writes. Those operations are outside this repository's ordinary-configuration model because vendor recovery material documents a bricking history.

Read [safety and threat model](docs/safety.md) before connecting a device.

## Components

| Path | Role | Publication status |
| --- | --- | --- |
| `mac/` | Native SwiftUI/AppKit + IOHID macOS app | application, not a package |
| `web/` | WebHID browser companion | client application; private npm package |
| `packages/protocol/` | Transport-free TypeScript framing/codecs | internal reusable component; `private` |
| `packages/device-flow-lite84/` | Capability-gated Flow Lite 84 layout/data | internal reusable component; `private` |
| `research/` | Authored evidence, provenance, and summaries | source documentation only |

The browser app requires Chrome or Edge over `https:` or `localhost`; Safari and Firefox do not provide WebHID. The native app requires macOS 14+ and Input Monitoring permission for the final signed app identity. Details: [macOS](docs/macos.md), [WebHID](docs/webhid.md).

## Build and verification

Native macOS (macOS host):

```sh
swift test --package-path mac
./script/build_and_run.sh --verify
```

Protocol package:

```sh
cd packages/protocol
bun install --frozen-lockfile
bun run typecheck
bun test
```

Web app:

```sh
cd web
bun install --frozen-lockfile
bun lint
bun run build
bun test
```

Hardware tests are explicitly opt-in and must never run in hosted CI. Close Flow Control before using them; see [live hardware gates](docs/development-and-release.md#live-hardware-gates).

## License

Flow Control's original code and documentation are available under the [MIT License](LICENSE). Third-party and vendor-owned material is not relicensed.

## Issues and contributions

Issues and pull requests should include the exact hardware identity, firmware, transport, and a non-sensitive diagnostic summary. Do not attach vendor installers, firmware images, signing material, or full personal backups. Report security-sensitive defects privately through GitHub's **Security → Report a vulnerability** flow rather than a public issue.
