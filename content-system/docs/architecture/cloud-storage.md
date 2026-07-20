# Cloud Storage Policy

OneDrive is the durable home for project snapshots, source snapshots, reviewed
data, reusable assets, release evidence and generated videos. The active local
checkout is disposable.

## Durable root

The path is configured only through `FLAGGENBANDE_CLOUD_ROOT`. No user-specific
path is compiled into source code. The current machine keeps its value in the
ignored `.env` file and a recovery copy under OneDrive `runtime-config/`.

## Local-only material

The following content is reproducible and must never be synchronized:

- `node_modules`
- `dist` and Xcode DerivedData
- temporary imports and render fragments
- package, TypeScript and renderer caches
- write probes and lock files

## Publication rule

1. Generate into a disposable local staging directory.
2. Run schema, asset, checksum and reproducibility checks.
3. Copy into a new immutable OneDrive release directory.
4. Re-read and checksum every durable file from the mounted OneDrive path.
5. Never overwrite an existing release.
6. Remove local staging only after the durable copy passes.

`npm run storage:doctor` reports `local-copy-verified`. This proves the mounted
copy can be written and read correctly. It does not claim Microsoft has already
completed remote synchronization; that needs either visible OneDrive status or
a future Microsoft cloud API.
