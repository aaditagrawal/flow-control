# LoFree protocol core

Pure TypeScript codecs for the LoFree report-8 keyboard configuration protocol. This package performs no HID I/O; web and desktop transports send the returned 16-byte payload with WebHID report ID `0x08`.

The public API covers:

- identity/CID/MID/transport, online state, battery, firmware version, and current-profile reads;
- bounded flash reads and writes, split into the protocol's 10-byte chunks;
- 128-entry Win/Mac/iOS/Android keymap layers;
- 15 macro slots;
- lighting state, effect, and custom-light records;
- polling rate and keyboard setting records.

Intentionally excluded: firmware/bootloader, pairing, factory reset/clear-setting, and receiver mutation commands.

## Safety and known uncertainties

- The byte framing, checksum, addresses, and codecs reproduce LoFree's official web client. Golden vectors lock these down.
- The Flow Lite 84 configuration advertises only Win/Mac and normal/Fn maps. The generic firmware reserves iOS/Android and Fn2 storage, but UI consumers should not expose those without a CID/MID capability match.
- Generic lighting storage supports RGB and custom maps. Flow Lite hardware is white-backlight only, so consumers must capability-gate RGB/custom-light controls.
- The official client's single-custom-light setter appears to overwrite byte 3 with a checksum; its full-profile encoder correctly writes the checksum to byte 9. This package uses the internally consistent full-profile layout (checksum at byte 9).
- The official full-profile polling-rate helper does not round-trip rates above 1000 Hz, while its one-setting writer uses a different formula. Flow Lite's wired identity advertises 1000 Hz, so higher rates should remain capability-gated until verified on another model.
- Command responses from the official client are not report-checksum validated, so parsers validate opcode/status/shape only.
