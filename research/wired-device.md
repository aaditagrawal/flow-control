# Wired Flow Lite 84 identity

Captured on macOS on 2026-07-15. Descriptor inspection only; no HID reports were sent.

## USB device

- Product string: `Air84@Lofree`
- Manufacturer string: `Compx`
- Vendor ID: `0x05AC`
- Product ID: `0x024F`
- Device revision: `0x0166` (firmware/device version 1.66)
- USB speed: 12 Mbps
- Serial number: none exposed

## HID interfaces

The device exposes three macOS HID devices:

1. Keyboard collection: usage page `0x0001`, usage `0x0006`, 8-byte input, 1-byte output.
2. Consumer/vendor collection: includes usage page `0xFF02`, usage `0x0002`.
3. Pointer collection: usage page `0x0001`, usage `0x0002`.

The pointer collection is a candidate path for the physical roller. Its descriptor
declares a relative vertical wheel (`0x0001:0x0038`) and relative horizontal
pan (`0x000C:0x0238`) in addition to pointer X/Y and five mouse buttons. A live
event capture is still required to distinguish this path from Consumer-page
volume up/down events; the generic firmware can expose the pointer collection
for mouse actions even when the roller itself uses Consumer events.

Raw descriptor for the pointer interface:

```text
05010902a1010901a10005091901290515002501950575018102
95017503810105010930093116008026ff7f751095028106c0
a100050109381581257f750895018106c0
a100050c0a3802950175081581257f8106c0c0
```

`research/tools/DialEventProbe.swift` is a read-only IOHID probe for confirming
which of these elements the roller and any press action emit.

The second interface confirms the configuration channel expected from LoFree's web client:

- Vendor usage page: `0xFF02`
- Vendor usage: `0x0002`
- Configuration report ID: `0x08`
- Input payload: 16 bytes
- Output payload: 16 bytes
- Additional vendor report ID: `0x13`
- Additional report payload: 19 bytes

Raw descriptor for the consumer/vendor interface:

```text
050c0901a1018503150026140519002a1405751095018100c0
05010980a10185021981298315002501950375018102950175058101c0
05010906a10185040507150025011900299f95a075018102c0
0602ff0902a1018513150026ff00750895130902810009029100c0
0602ff0902a1018508150026ff00750895100902810009029100c0
```

This clears the descriptor portion of Phase 0. Browser permission and WebHID enumeration remain to be confirmed through the local probe.
