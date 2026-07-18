# Web architecture and WebHID security model

The `web/` application is a private React/Vite browser companion. It uses `navigator.hid` and report ID `0x08`; protocol parsing and configuration semantics must remain aligned with the codec evidence in this repository.

WebHID is available in Chromium-derived desktop browsers such as Chrome and Edge. It is unavailable in Safari and Firefox. It requires a secure context (`https:`) or `localhost`, and first-time device selection must come from an explicit user action through the browser chooser. Authorization is scoped to the browser profile and origin; an app cannot silently acquire arbitrary HID access.

Chromium restricts ordinary keyboard collections. This project targets the separate vendor-defined configuration collection, not the keyboard typing interface. The user must select the exact device and the application must still reject an incompatible collection or report shape.

Do not deploy this app on a broad, unreviewed origin, embed it in a hostile frame, or treat a previously authorized device as permission to write. HTTPS protects transport to the page; it does not prove firmware compatibility or eliminate configuration-write risk. WebHID tests in hosted CI are unit/build checks only and must not access physical devices.
