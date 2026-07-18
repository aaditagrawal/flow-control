# Report-8 protocol and storage

This is an implementation-oriented record of observed behavior, not a vendor specification. Evidence levels are defined in [research policy](evidence-and-research.md).

## Frame and checksum

The configuration channel exchanges 16-byte report-8 payloads. On macOS, IOHID receives a 17-byte write buffer containing report ID `0x08` followed by the payload. Byte layout:

| Bytes | Meaning |
| --- | --- |
| `0` | command |
| `1` | response status; `0` is success |
| `2..3` | big-endian flash address for flash commands |
| `4` | endpoint flag `0x80` OR payload length |
| `5..14` | up to ten data bytes |
| `15` | report checksum |

For outgoing reports, `(report ID + sum(payload bytes)) mod 256 = 0x55`. A two-byte scalar is `[value, 0x55 - value]`; a record checksum follows the same modulo-256 complement rule. Incoming responses are matched by command/status/address/shape; they are not treated as valid merely because they arrive.

## Transactions

Implemented ordinary commands are identity `0x01`, online `0x03`, battery `0x04`, flash write `0x07`, flash read `0x08`, current profile `0x0E`, and version `0x12`. Transfers are capped at ten bytes. The native transport serializes operations, uses a 200 ms attempt window, retries timeouts up to five times, and validates a read response's opcode, status, address, and length. Every ordinary write has exact readback.

## Allowlisted flash map

| Address | Data | Write status |
| ---: | --- | --- |
| `0`, `512`, `1536`, `2048` | Win/Mac base and Fn maps; 128 x 4 bytes each | enabled for known records |
| `6176..7455` | 128 custom-light records x 10 | read-only |
| `8496`, `8498`, `8500` | light mode, enabled state, off time | enabled |
| `8544 + mode x 32` | 32-byte lighting effect records | four-byte header only |
| `9408`, `9416`, `9418`, `9420` | polling, OS system, Fn lock, full-key lock | enabled |
| `10064 + slot x 384` | 15 macro slots | enabled |

Unlisted storage is rejected. The command surface excludes bootloader/update, pairing, factory reset, clear settings, and receiver mutation.

## Codecs and evidence

Key assignments are four bytes: family, little-endian value, checksum. Macro storage has 15 slots of 384 bytes: UTF-8 name at bytes `0..30`, event count at `31`, up to 70 five-byte events from `32`, then checksum. The protocol TypeScript package supplies transport-free codecs and golden-vector tests; the Swift implementation has matching protocol tests. See [configuration behavior](configuration.md).
