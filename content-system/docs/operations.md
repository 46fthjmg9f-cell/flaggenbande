# Operations

## Fresh installation

1. Use Node 22 as declared in `.node-version`.
2. Run `npm ci` inside `content-system`.
3. Run `npm run doctor`.
4. Run `npm run check && npm run build`.

No network, API key, paid service, database or renderer is required after npm
installation in Release 0.1.0.

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

Logs are JSON lines on stdout. Fields that look like keys, tokens, passwords or
secrets are redacted before serialization.
