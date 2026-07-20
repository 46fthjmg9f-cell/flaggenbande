# Operations

## Fresh installation

1. Use Node 22 as declared in `.node-version`.
2. Run `npm ci` inside `content-system`.
3. Run `npm run doctor`.
4. Run `npm run check && npm run build`.

No API key, paid service, database or renderer is required. Release 0.2.0 only
uses public source pages during the explicit snapshot commands; validation and
runtime use local immutable files.

## Country-data candidate

Fetch both dated public source snapshots into the disposable local cache:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run data:fetch-un-m49 -- --output .cache/source-snapshots/un-m49-2026-07-20.json
npm run data:fetch-capitals -- --output .cache/source-snapshots/wikidata-capitals-2026-07-20.json
```

Publish an immutable, twice-generated and re-read candidate to OneDrive:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run data:publish-candidate -- --dataset-version 0.2.0-candidate.1 --generated-at 2026-07-20T10:00:00.000Z --un-m49-snapshot .cache/source-snapshots/un-m49-2026-07-20.json --wikidata-snapshot .cache/source-snapshots/wikidata-capitals-2026-07-20.json
```

There is intentionally no `--force`: an existing version is immutable. Failed
publication preserves local staging for diagnosis. Successful publication
removes the duplicate local staging only after the OneDrive-mounted files have
been re-read and their complete file set, byte sizes and SHA-256 values match.

## Durable OneDrive storage

Permanent datasets, reviewed assets, releases and generated output live under
`FLAGGENBANDE_CLOUD_ROOT`. The local `.env` points the output directory into
that root. Dependencies, build output and `.cache` stay local because they are
disposable and unsafe to synchronize while tools are running.

Run:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run storage:doctor
```

The command verifies local write/read integrity inside the OneDrive-mounted
directory. It deliberately reports `remoteSyncVerified: false`: without a
Microsoft cloud API, filesystem access cannot prove that OneDrive has already
uploaded the bytes to its servers.

## Modes

Development is the default and uses debug logs plus one future render worker.
Production is selected explicitly with `npm run start:production` and uses info
logs plus two future workers. The concurrency values are inert until the batch
renderer is introduced.

## Failures

- Invalid mode or log level: correct `.env` using `.env.example` as reference.
- Missing mode config: restore the versioned JSON file from Git.
- Unwritable output: set `FLAGGENBANDE_OUTPUT_DIR` to a writable path.
- Node check failure: activate Node 22 or newer and rerun `npm ci`.
- Existing candidate version: choose a new candidate version; never overwrite.
- `remoteSyncVerified: false`: confirm OneDrive's visible sync status before a
  stable human-approved release.

Logs are JSON lines on stdout. Fields that look like keys, tokens, passwords or
secrets are redacted before serialization.
