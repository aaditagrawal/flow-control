# Development, testing, and release process

## Local checks

```sh
swift test --package-path mac
(cd packages/protocol && bun install --frozen-lockfile && bun run typecheck && bun test)
(cd web && bun install --frozen-lockfile && bun lint && bun run build && bun test)
```

Run `./script/build_and_run.sh --verify` on a macOS development machine to build and verify the local native app package. The native application source is intentionally outside routine documentation changes.

## Live hardware gates

Hosted CI must not run these. Disconnect non-target devices and close Flow Control before running them:

```sh
./script/verify_mac.sh --live-read
./script/verify_mac.sh --live-write --repeat 3
```

The lower-level `FLOW_HID_*_INTEGRATION` tests are opt-in. Their write gates save the existing state, verify readback, and attempt restoration on failure, but they are still physical-device operations. Use only the documented target identity and record the firmware, transport, test revision, before/after state, and restoration result in release evidence.

## Release checklist

1. Review `git status --ignored` and confirm no local identities, vendor acquisitions, build outputs, backups, or `node_modules` are staged.
2. Run the local checks above. Record tool versions and lockfile state.
3. For a protocol/write-scope change, complete the relevant live gate and exact restore on each supported firmware identity.
4. Review documentation, compatibility matrix, known unknowns, and changelog for claims matching the evidence.
5. Confirm the MIT License and notices are present, and verify that no tracked third-party or vendor-owned material is incorrectly covered by it.
6. For macOS distribution, complete Developer ID signing, hardened runtime, notarization, stapling, and independent signature verification.
7. Create a signed/tagged release only after the artifact hash and release notes are ready. Release notes must distinguish hosted checks from live hardware verification.

## CI scope

CI checks deterministic source properties only: Swift unit tests on macOS, TypeScript codec typecheck/tests, and web lint/build/test. It does not have a physical keyboard, TCC authorization, a Developer ID certificate, or authority to claim hardware compatibility.

## Continuous deployment

On a push to `main`, the `deploy-web` job runs only after the macOS, protocol,
and web CI jobs all pass. It performs a fresh frozen Bun install, rebuilds the
static site, uploads `web/dist` as a Pages artifact, and deploys that artifact
to the `github-pages` environment. Pull requests never deploy.

The repository must be configured once under **Settings > Pages > Build and
deployment > Source: GitHub Actions**. No repository secret is required. The
workflow uses job-scoped `pages: write` and `id-token: write`; all validation
jobs retain read-only repository permissions.

GitHub Pages does not apply the repository's `_headers` file as HTTP response
headers. WebHID remains available because the application is same-origin and
Pages supplies HTTPS; hosts that support custom headers should additionally
send `Permissions-Policy: hid=(self)`, `X-Content-Type-Options: nosniff`, and
`Referrer-Policy: strict-origin-when-cross-origin`.
