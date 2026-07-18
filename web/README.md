# Flow Control web

The web-first LoFree Flow Lite 84 configurator.

This is a public client application target whose npm package is marked private
to prevent accidental registry publication. It requires Chromium WebHID on
HTTPS or localhost; read the repository [compatibility](../docs/compatibility.md),
[safety](../docs/safety.md), and [WebHID security model](../docs/webhid.md) before use.

The browser companion reads and writes the Flow Lite 84 over WebHID. It supports both keymap layers for macOS and Windows, verified lighting modes and five discrete brightness/speed levels, all 15 macro slots (up to 70 events each), polling rate, active layout, Fn lock, full-key lock, JSON import/export, automatic local backup, and immediate plus final readback verification.

Firmware flashing, receiver pairing, BLE clearing, and factory reset remain intentionally excluded because they are recovery/destructive operations rather than ordinary configuration.

Use Chrome or Edge on `localhost` or HTTPS.

```bash
bun install
bun run dev
```

Production checks:

```bash
bun lint
bunx tsc --noEmit
bun run build
```

## Hosting

`vite.config.ts` uses `base: './'`, so the generated `dist/` folder can be served from a GitHub Pages project site, a custom subpath, or another static HTTPS host without rewriting asset URLs.

### GitHub Pages

The repository CI workflow deploys `web/dist` to GitHub Pages after every
macOS, protocol, and web validation job passes on a push to `main`. Set the
repository's Pages source to **GitHub Actions** before the first deployment.
Pull requests build and test the app but never deploy it.

Pages supplies HTTPS, which satisfies WebHID's secure-context requirement. It
does not interpret `_headers`; the WebHID feature's default same-origin policy
still permits this top-level app. The explicit `Permissions-Policy: hid=(self)`
header remains configured for hosts that support custom response headers.

### Vercel

The app is entirely client-side. `vercel.json` selects Bun, runs the production Vite build, publishes `dist/`, and sends the same-origin WebHID permissions policy.

For Vercel Git integration:

1. Import the repository.
2. Set **Root Directory** to `web`.
3. Leave the detected Vite build settings in place. No environment variables or server functions are required.

For a CLI preview without changing repository settings:

```bash
bunx vercel --cwd web
```

Use `bunx vercel --cwd web --prod` only when you intend to publish production.

### ChatGPT Sites

An optional local `.openai/hosting.json` can identify a Sites project; it is
ignored because it is a maintainer-specific hosting binding.
`public/server/index.js` is the Cloudflare Worker-compatible entry that serves
the static assets and adds the WebHID permissions policy.

```bash
cd web
bun run build:sites
```

That command produces and validates the Sites-ready `dist/` output. A Sites deployment can then package this exact source with the Sites hosting workflow; no alternate app or server implementation is needed.

### Other static hosts

```bash
cd web
bun run build
```

Publish `web/dist/` over HTTPS. `_headers` supplies the WebHID and basic security headers on hosts that support the common static `_headers` format. On other hosts, configure `Permissions-Policy: hid=(self)` directly.

Open the deployed site in current Chrome or Edge, connect the keyboard by cable, and select it in the browser chooser. The site will offer a previously granted matching keyboard for reconnect, but never opens a device without a user action.

The app validates the USB identity, vendor collection (`FF02:0002`), report ID 08, and wired CID/MID transport before configuration reads. Only protocol-defined ordinary configuration ranges are writable. It deliberately does not expose firmware updates, bootloader actions, receiver pairing, reset/clear actions, BLE clear, custom-light writes, or unknown flash ranges.

Imports are schema-validated before staging. Export before a significant change; **Discard** restores staged data from the last on-keyboard baseline, while an Apply automatically stores that baseline locally and verifies every write and the entire final configuration. If a cable is removed mid-operation, treat the result as failed and reconnect/read before making further changes.
