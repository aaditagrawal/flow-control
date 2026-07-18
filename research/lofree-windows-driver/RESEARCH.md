# LoFree Flow Lite Windows app reconnaissance

Captured 2026-07-15. All executables were treated as data and were not run.

## Provenance

- Official download-centre page: https://www.lofree.co/pages/download-center
- The official `Download App` link currently resolves to: https://www.dropbox.com/scl/fo/2581avtxvitvftsd7312f/AC-XHGb5oZKm3mPypP0pR10?dl=0&e=1&rlkey=putg9j9gw9lou8mtwariog2xg&st=bds48004
- Folder download used for preservation: https://www.dropbox.com/scl/fo/2581avtxvitvftsd7312f/AC-XHGb5oZKm3mPypP0pR10?rlkey=putg9j9gw9lou8mtwariog2xg&dl=1
- Dropbox folder title: `Lofree Flowlite Key Mapper – DO NOT USE on other devices (May cause bricking)`.
- The outer archive contains a RAR dated `2025.09.15`, an installer named `Lofree Key Mapper_v1.1.1.3_2025.09.15_setup.exe`, and an upgrade-recovery DOCX.

## Hashes

| Artifact | SHA-256 |
| --- | --- |
| `official-dropbox-download.zip` | `a7c0ad9a680086f946d0897ca0025f151eb3331163125b01c37cb08a5153ebc9` |
| Official RAR | `88b688dcd7c3a539cbe001a2ae03a212552b590d90852801501c834bc810f3ab` |
| Installer EXE | `2cd74f316945535823036784bf54fc92e4ebde5258860959d647c13001379580` |
| Upgrade-recovery DOCX | `03a3ed64cafdbdc0a60693cb5203f64390d66c8f0379ff0dcfdf0875053edbf4` |
| Extracted x64 `Lofree Key Mapper.exe` | `646df4364165670e30e5fd5e82c23bd7f7a6a37ed9c5ed2b405fb5f789574d17` |
| Extracted x64 `HIDUsb.dll` | `0cb20c33f490cbedbc3c78b018c85955322c40d494632c7bebcf86f10aef5ba8` |

## Package metadata and architecture

- Installer: Inno Setup 6.1.0, PE32, product version `1.1.1.3`, company field `Lofree Key Mapper, Inc.`
- Installed app: native C++/Qt, not Electron. It bundles Qt 5.9.3 and separate `Sys32` and `Sys64` trees.
- x64 app timestamp: 2025-09-12; original name `Lofree.exe`.
- HID library: `HIDUsb.dll` version `1.0.0.28`, timestamp 2024-05-17. Its metadata identifies a Shenzhen gaming-driver vendor; it is a user-space HID helper, not a kernel driver.
- The installer accidentally/purposefully contains `.obj`, generated `moc_*.cpp`, `.pdb`, `.lib`, and resource files. These expose class/signal names and make protocol reverse engineering materially easier.
- Eight firmware images are bundled, covering VIDs/PIDs `3554:F811`, `388D:0008`, `388D:0009`, and `05AC:024F`, with firmware versions 1.57–1.68 and layout/model suffixes `0101`–`0108`.

## UI and feature inventory

High confidence, based on `Language/en.xml`, Qt generated metadata, configuration files, and UI image assets:

- Per-key remapping on Default, Fn, and Fn2 layers, with system modes for Windows, macOS, iOS, and Android.
- Assignment types: standard keyboard usages, modifier/combo keys, multimedia/consumer controls, mouse buttons, macros, Fn/Fn2/MacFn, profile slots (`Queue1`–`Queue16`), lighting controls, and disable.
- Profiles: create, rename, delete, import, and export.
- Macros: record/edit key-down, key-up, delays, and mouse-button events; automatic or fixed delay; repeat 1–250 times or until key/key-release conditions; maximum 15 macros.
- Lighting: 12 built-in modes and at least 3 enabled custom modes; brightness, speed, direction, color/preset color, preview, and per-mode capability flags. Japanese resources name the effects as Off, Ripple, Touch Effect, Flow, Snow Trace, Sine Wave, Breathing, Always On, Snake, Season Blossom, Rainbow Cycle, and Seven-color Change.
- Music-reactive lighting with Normal/Rock/Passion modes, smoothness and amplitude controls.
- Device settings: receiver/keyboard firmware versions, firmware update, receiver pairing, factory restore, backlight sleep timeout (10 seconds through 40 minutes), polling rate (125/250/500/1000 Hz), 6-key rollover, WASD/arrow swap, and `Smart Speed X Low Latency`.
- App settings: English, Simplified Chinese, Traditional Chinese, Japanese; launch at boot; close-to-exit or remain in tray.
- No evidence that the volume roller is remappable. This should be considered unsupported until device testing disproves it.

## Device/protocol evidence

High confidence:

- Communication is USB HID using Windows `HID.DLL`, `HidD_SetFeature`, `ReadFile`, and `WriteFile`. The app enumerates interfaces through SetupAPI and targets configurable interface/port values (`Interface=1`, `Port=5`).
- The bundled config decodes candidate USB IDs from Base64 as VIDs `05AC`, `3554`, `3434`, `388D` and PIDs `024F`, `FA0A`, `F811`, `0E41`, `0009`, `0008`. Firmware filenames confirm several VID/PID pairs, but the exact Flow Lite 84 runtime pair must be read from the user's keyboard.
- `HIDUsb.dll` exports explicit operations for enumerating/opening HID devices, generic read/write, reading all flash/config/version/battery/polling rate, writing current config, clearing settings, receiver pairing, entering USB update mode, locating bootloader devices, and starting firmware upgrades.
- Key assignments are encoded around HID usage values. Configuration rows show an assignment family byte plus usage data (for example `0x02,0x29` for Escape, `0x01` modifier family, `0x03` consumer/media family, `0x06` Fn-family, `0x09` profile slots, and `0x0A` mouse buttons). Some device layouts add a fourth physical-key/index byte.
- Combination records use family `0x07`, a HID modifier mask, and a keyboard usage. In `keyboardset.obj`, `on_MacroSave_clicked` explicitly builds `[0x08, macroSlot, repeatCount, checksum]` before updating the selected key, establishing family `0x08` macro assignment and one-shot repeat count `1` for the native implementation.

Medium confidence / still requires capture:

- The web/mac implementation should be able to use WebHID/IOHID directly without privileged drivers because the official app uses standard user-space HID calls.
- Configuration appears persisted in keyboard flash, but exact report IDs, packet length, framing, checksum, command opcodes, read/write sequencing, and acknowledgement rules are not yet established from static inspection.
- The fastest safe next step is to capture WebHID traffic from the official web configurator while performing one reversible change at a time, then compare against the exported DLL/app disassembly. Firmware update should be isolated as a later phase because the official bundle warns about bricking.

## Whisky runtime reconnaissance

The extracted x64 `Lofree Key Mapper.exe` was launched successfully in the existing Whisky/Wine bottle on macOS. Wine's HID and SetupAPI traces showed that the Windows process could enumerate only Wine's synthetic HID devices (`VID_845E`, `PID_0001` and `PID_0002`). The physical Flow Lite interface (`VID_05AC`, `PID_024F`) was not passed through to the Windows process, so the official application could not detect or communicate with the keyboard under Whisky. No device write, firmware, reset, or pairing operation was performed.

The same connected keyboard is exposed directly to macOS as three IOHID devices. The configuration channel is the consumer-control collection with primary usage page `0x0C`, primary usage `0x01`, maximum input report size 21, and maximum output report size 20. This confirms that Whisky's limitation is USB HID pass-through rather than an absent keyboard interface.

## Confirmed lighting protocol

The official web client, Windows configuration data, and Windows object-code disassembly agree on the lighting write semantics:

- HID report ID: `0x08`; report payload: 16 bytes.
- Flash write command: `0x07`; flash read command: `0x08`.
- Byte 4 contains the payload length with the keyboard endpoint flag `0x80` set.
- Current mode: address 8496; enabled state: 8498; idle timeout: 8500.
- Ordinary effect records begin at 8544 and are 32 bytes apart (`8544 + mode * 32`).
- An individual brightness or speed adjustment rewrites only the four-byte effect header: `[colorIndex, speed, brightness, checksum]`.
- The header checksum is `0x55 - sum(first three bytes)`, truncated to one byte.
- The Windows sliders display levels 1 through 5 and store the raw value minus one, so firmware brightness and speed levels are exactly 0 through 4.
- Mode, enabled state, and idle timeout are individual two-byte writes `[value, 0x55 - value]`.
- The official client retries a transaction up to five times with an approximately 200 ms response window. It matches a write acknowledgement by command/status/address prefix and a read acknowledgement by the first five header bytes.

The native macOS implementation uses the same report ID, command bytes, address map, endpoint flag, checksums, 0-through-4 level encoding, four-byte effect-header write, complement-pair setters, and bounded retry behavior. The Whisky run therefore found no lighting-protocol mismatch in the native implementation; failures in the packaged macOS app should be investigated in native device discovery, IOHID access/permissions, or application state flow rather than by changing these packet semantics.

## Firmware recovery evidence

The included DOCX says failed-upgrade bootloader recovery works in Chrome on Windows and macOS and provides model-specific pages:

- Flow Lite 84 ANSI: https://www.lofree.tech/OE921/
- Flow Lite 100 ANSI: https://www.lofree.tech/OE922/
- Flow Lite 84 ISO Nordic: https://www.lofree.tech/OE921E/
- Flow Lite 100 ISO Nordic: https://www.lofree.tech/OE922E/
- Flow Lite 84 ISO-DE: https://www.lofree.tech/OE921GE/
- Flow Lite 100 ISO-DE: https://www.lofree.tech/OE922GE/
- Flow Lite 84 JIS: https://www.lofree.tech/OE921J/
- Flow Lite 100 JIS: https://www.lofree.tech/OE922J/

It explicitly says those pages only support devices already in BOOT after an upgrade failure, and require a factory reset with `Fn+Esc+Backspace` after recovery.
