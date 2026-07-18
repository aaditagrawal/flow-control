# Flow Lite 84 device data

Machine-readable UI data for the ANSI Flow Lite 84. Import `@flow-control/device-flow-lite84` for the physical 84-key layout, Win/Mac normal and Fn defaults, assignable-action catalog, lighting labels, and settings options.

## Evidence boundary

- **Flow Lite 84 confirmed:** ANSI 84-key physical layout and printed Fn legends from `Flow_Lite84_User_Manual.png`; USB identity/channel/report metadata from `research/wired-device.md`.
- **Shared official web driver:** action type/value catalog, the four systems/two layers advertised by the generic driver, polling-rate option encodings, and light-sleep option encodings from `research/official-web/en.json` and `cfg.json`.
- **Windows static analysis:** profiles, macro editor semantics and limits, 12 effect names and flags, five brightness values, five speed values, polling through 1000 Hz, rollover and ancillary settings from `research/lofree-windows-driver/RESEARCH.md` and the bundled `usersetting/Config.ini`.

`cfg.json` is titled **Lofree HYPACE** and its keyboard records describe 107-key layouts. `ref.json` is the same generic 128-slot/107-key reference layout. Neither is a Flow Lite 84 physical map, so their 128 raw default arrays and lighting mode numbers are intentionally not presented as Flow Lite defaults. In particular, do not send a `cfg.json` default array to this keyboard.

## Known gaps / do not enable yet

- Exact raw command values for Multi-Screen, Windows Menu, Voice Assistant, and Lock are not established. Their semantic default bindings are useful for UI but are not write-safe. Shortcut chords and one-shot macro assignment are established by the official Windows object code and reversible device tests.
- The shared catalog contains Android/iOS switching, light-strip controls, 16 sequences, 2/4/8 kHz polling, Fn2, mouse buttons, and several lockout functions. These may be generic shared-driver features. They are not confirmed for Flow Lite 84.
- The Windows package exposes music-reactive lighting, custom lighting, receiver pairing, WASD/arrow swap, Smart Speed/low latency and firmware update. Device support remains unconfirmed.
- The Flow Lite has monochrome backlighting. RGB/custom-color controls from the shared driver must stay hidden unless device reads prove support.
- The volume roller is not represented as remappable.
- Firmware update is deliberately disabled. It needs a separate, model/version-gated implementation and recovery path.

The UI should surface evidence level and disable writes for unconfirmed features until a reversible capture/read-back test establishes the protocol.
