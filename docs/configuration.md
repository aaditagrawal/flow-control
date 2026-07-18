# Configuration behavior

## Keymaps and actions

There are independent Windows/macOS base and Fn maps, each stored as 128 records although only 84 physical slots are rendered for this layout. Established assignment families include disabled, modifier, keyboard, consumer/media, device action, Fn/Mac Fn, combination, macro, profile/queue, and mouse. The UI writes only established values and retains unfamiliar values from the keyboard.

Shortcut combinations use family `0x07` with HID modifier mask and key usage. Macro assignment uses family `0x08`; the safe emitted form is one-shot repeat count `1`, slots `0..14`. Unverified repeat/until-release modes are intentionally unavailable.

## Macros

A macro records balanced press/release events with a value and delay. The editor can compose several shortcuts into a macro, which can then be assigned to one physical key. Macro slots are read back after write. Do not assume that a macro feature advertised by the vendor's shared Windows UI is safe for this device until it fits the encoded limits and has passed restoration testing.

## Lighting and settings

The Flow Lite hardware is white-backlit. Verified built-in mode values include Always On `0x00`, Breathing `0x01`, Rainbow Cycle `0x02`, Seven-color Change `0x03`, Snow Trace `0x04`, Sine Wave `0x06`, Touch Effect `0x07`, Ripple `0x08`, and Snake `0x09`. Brightness and speed are firmware levels `0..4`; the vendor slider labels are one-based.

Lighting selection writes the effect header before atomically setting the mode and enabled complement pairs. This matters because `v1.66` can read back a selected mode while leaving the effect dormant if only the mode pair changes. The app writes only the four-byte header for a level change and preserves the remainder of the record.

Verified settings are 125/250/500/1000 Hz polling, macOS/Windows system, Fn lock, full-key lock, and backlight-off values `0, 1, 3, 6, 12, 30, 60, 90`.

## Backup, diff, write, readback, restore

Before an apply, the native app serializes a pre-write configuration backup under `~/Library/Application Support/FlowControl/Backups`. It computes persisted-field differences, writes only the selected changed section, and verifies records immediately. Lighting-only changes do not rewrite keymaps or macros. Hardware tests save original state and attempt restoration on both success and failure. Imported/exported JSON is configuration data: review it before import and do not submit it to issues because it may expose personal shortcuts or macro content.
