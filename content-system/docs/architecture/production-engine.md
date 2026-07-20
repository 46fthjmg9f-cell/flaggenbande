# Production Engine Architecture

## Current repository

The repository already contains the SwiftUI app, an extensive in-app country
catalog and a separate analytics dashboard. Neither is a production engine and
neither should be coupled to rendering. The country catalog is useful source
material for Release 0.2.0, but it mixes German UI names, territories and
disputed entities and therefore requires an explicit content-safe export and
validation before reuse.

The detailed findings and known catalog defects are recorded in
[`data-audit.md`](data-audit.md).
The inspected repository boundaries and reuse decisions are recorded in
[`current-repository.md`](current-repository.md).

## Target modules

The content system will grow inside this isolated directory:

1. `packages/country-data`: reviewed country records and licensed flag assets
2. `packages/quiz-generator`: seeded selection and repetition history
3. `packages/video-template`: one approved Remotion template
4. `packages/audio`: cached, normalized reusable speech and sound
5. `packages/platform-metadata`: platform-specific text and export contracts
6. `packages/qa`: blocking data and technical checks
7. `packages/shared`: versioned schemas and stable identifiers
8. `apps/renderer`: CLI for one video and batches

The existing dashboard remains outside this engine. A small production-history
file is enough until the rendering pipeline is stable.

## Deterministic flow

`country data → seeded quiz manifest → cached audio → fixed timeline → render → QA → platform exports → history`

Every boundary uses versioned JSON. Failed QA prevents release. Upload remains
disabled until Release 0.11.0.

## Release 0.1.0 decisions

- Strict TypeScript and Node 22 establish the future renderer toolchain.
- Configuration is local, versioned and validated without a config dependency.
- Logs are JSON lines with stable event names and no secrets.
- Development and production modes differ only through reviewed configuration.
- Remotion is intentionally not installed before Release 0.3.0.
- No external API or paid service is introduced.
