# Architecture and boundaries

## Repository map

```text
mac/                         native macOS application
  SwiftUI views              editor presentation
  AppStore                   staged state, backups, diff/apply coordination
  FlowHIDService             IOHID discovery, transactions, allowlisted I/O
  FlowProtocol               report and record codecs
web/                         browser companion; WebHID transport and UI
packages/protocol/           transport-independent TypeScript codecs/tests
packages/device-flow-lite84/ capability-gated layout, defaults, and action data
research/                    authored technical evidence and provenance only
script/                      local build/sign/verification entry points
```

The protocol package does not open HID devices. Each application owns permission handling and user interaction; codecs produce or parse report payloads. Device data is deliberately separate from generic protocol storage so a generic feature does not become a UI capability without device evidence.

## Native write path

`AppStore` reads a baseline, keeps edits staged, snapshots the requested change set, creates a backup, and asks `FlowHIDService` to apply only that scope. `FlowHIDService` accepts the exact target collection and report element, serializes transactions, writes allowlisted flash ranges in bounded chunks, and immediately reads each record back. A disconnect or stale asynchronous completion cannot mark an operation successful.

## Browser boundary

The browser companion uses the same report-8 shape through WebHID. Browser device authorization is user-mediated and origin-scoped; browser support and device selection are not substitutes for native identity checks. See [WebHID](webhid.md).

## Non-goals

This is not a cross-platform daemon, a driver, a vendor protocol specification, or a general LoFree configurator. The repository does not include a Windows application. The old Electron prototype is retained locally as research context and is excluded from the public tree.
