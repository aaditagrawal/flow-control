# Evidence, clean-room boundaries, and third-party artifact policy

## Evidence levels

Use these labels precisely:

1. **Live verified**: observed on the documented target identity and exercised with readback/restoration where relevant.
2. **Official-client corroborated**: behavior represented by an official public web client or manual, not necessarily executed on this keyboard.
3. **Static-analysis inference**: inferred from vendor binary metadata, strings, generated code, or configuration files; never sufficient alone for a write.
4. **Unknown**: plausible but untested; keep read-only or omit.

The technical reference and package READMEs identify which level supports a claim. Preserve uncertainty rather than converting generic LoFree behavior into Flow Lite support.

## Clean-room implementation boundary

Repository code is authored independently. Vendor artifacts may be inspected as data to formulate hypotheses, but they are not source dependencies, build inputs, or redistributable project assets. Implementations should rely on documented observable behavior, small independently written codecs, and tests; do not copy vendor source, resources, or UI assets into the application.

## Artifact policy

The working directory may contain vendor installers, archives, manuals, downloaded web bundles, extracted PE/DLL/OBJ/PDB files, Electron bundles, and generated app products. They are intentionally ignored. Public Git contains only authored research summaries and acquisition manifests.

`research/lofree-windows-driver/PROVENANCE.md` records URLs, acquisition date, and SHA-256 values for the observed vendor material. Re-fetch from the upstream source, validate hashes, and inspect locally if reproduction is needed. Never upload such acquisitions to a fork, issue, release, or package registry unless their redistribution terms have been reviewed separately.

## Safe research workflow

Acquire into ignored paths, hash before analysis, do not execute an installer just to inspect it, keep a command/log summary without personal data, and state the boundary between observation and inference. Firmware images and recovery flows are specifically excluded from normal development.
