# Troubleshooting and known unknowns

## Native app cannot access the configuration interface

Confirm the keyboard is wired, then verify the observed VID:PID, vendor collection, and report-8 shape. Input Monitoring permission is also required. If the app was rebuilt after earlier ad-hoc signing, remove the stale Flow Control permission record and grant access to the current packaged app as described in [macOS](macos.md). Do not run the test harness and GUI app simultaneously; both contend for the HID interface.

## Browser cannot select the keyboard

Use Chrome or Edge on HTTPS/localhost and trigger connection through the application's chooser action. Safari and Firefox do not implement WebHID. Selecting an ordinary keyboard collection does not provide access to the vendor configuration collection.

## A lighting mode reads back but looks inactive

On the tested `v1.66` firmware, mode selection needs the mode and enabled-state complement pairs written atomically after the target effect header. A successful mode-only readback is insufficient. Restore the prior snapshot rather than experimenting with undocumented records.

## Known unknowns

- custom-light record types and safe custom-mode activation;
- music-reactive transport;
- macro repeat/until-release persistence;
- roller event source and persistent remapping;
- generic shared settings such as N-key rollover, WASD swap, scan time, and low latency;
- behavior on other firmware, CID/MID values, layouts, or transports;
- firmware recovery/update protocol, which remains out of scope.

When reporting a problem, include only non-sensitive device/firmware information and a minimal reproduction. Do not attach personal backups or vendor binaries.
