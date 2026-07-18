# Hardware identity and compatibility policy

## Supported evidence envelope

| Field | Required observed value |
| --- | --- |
| Product / manufacturer | `Air84@Lofree` / `Compx` |
| USB VID:PID | `05AC:024F` |
| CID/MID | `1/1` |
| Firmware evidence | `v1.66` |
| Transport for live validation | wired |
| Vendor collection | `0xFF02:0x0002` beneath the consumer/vendor interface |
| Configuration report | ID `0x08`, 16-byte input/output payloads |

The native discovery logic intentionally requires more than VID:PID: it checks the expected collection and report element. A match is necessary for connection, not a declaration that every firmware behavior is safe.

## Policy

- A new firmware, CID/MID, physical layout, or transport begins read-only.
- Static evidence from a shared LoFree client never enables a write by itself.
- A capability becomes eligible only after a scoped, reversible test with readback and restoration on the exact identity.
- Unknown key records are preserved on read and are not relabeled or overwritten as known actions.
- The Flow Lite is white-backlit. Generic RGB, custom-light, iOS/Android, Fn2, 2/4/8 kHz, receiver, and reset features remain hidden or write-disabled unless their exact scope is established.

## Explicitly unsupported

Bluetooth and receiver configuration, firmware/update/recovery flows, factory reset, other Flow Lite layouts/models, and other LoFree keyboards are outside support. The roller is not declared remappable; its pointer/consumer event path needs a live capture.
