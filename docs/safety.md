# Threat and safety model

## Assets and failure modes

The protected asset is the keyboard's persistent configuration and ability to recover. Relevant failures include writing a similarly identified device, corrupting a flash range with an incorrect codec, leaving a partial configuration after disconnect, importing an unreviewed personal backup, and distributing a build signed with an untrusted local identity.

## Controls

- Exact VID/PID, collection, report ID/size, CID/MID, and wired-transport checks constrain connection.
- A flash-range allowlist rejects unknown configuration storage.
- Transactions are serialized, bounded, retried only for timeout, and shape-checked.
- Pre-write backups, diffed writes, per-record readback, and restoration-capable live tests limit ordinary-write risk.
- UI capability gating prevents generic driver data from becoming a write claim.
- Local signing material is isolated in ignored `.local-signing/`; it is not distributable trust material.

## Excluded destructive commands

The code and public workflow exclude firmware flashing, bootloader entry, receiver pairing, Bluetooth clearing, factory reset, clear settings, receiver mutation, custom-light writes, and arbitrary animation streaming. Do not add an escape hatch, environment variable, or undocumented command path for these operations.

## Residual risk

Readback proves protocol state, not physical key behavior or long-term flash durability. USB disconnects, firmware differences, vendor changes, and malformed user imports can still produce loss of user configuration. Maintain independent backups and treat new firmware as read-only until revalidated.
