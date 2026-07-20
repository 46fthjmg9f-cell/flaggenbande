# Current Repository Map

This document records the read-only repository inspection performed for Release
0.1.0. No existing product code was moved or rewritten.

## Existing areas

### iOS application

- `SpassmitFlaggen/`: SwiftUI application marketed as **Flaggenbande**
- `SpassmitFlaggen.xcodeproj`: Debug and Release schemes for the app
- `SpassmitFlaggen/FlagCatalog.swift`: in-app country catalog
- `SpassmitFlaggen/Assets.xcassets`: app icon and approved brand assets

The app remains the product being promoted. CloudKit, StoreKit, Game Center and
other app services are not dependencies of video production.

### Analytics dashboard

- `dashboard/`: independent React, Vite and TypeScript dashboard
- `.github/workflows/`: existing repository automation

The dashboard remains independent. Release 0.1.0 does not add a second
dashboard or couple the renderer foundation to analytics.

### Existing operational material

- repository scripts and documentation remain available to their current users
- the app catalog provides a reviewed import seed, not authoritative production
  data
- the app icon and existing brand colors can be reused later by the App Promo
  and Design agents after approval

## Production-engine ownership

The new `content-system/` directory owns only deterministic quiz-video
production. Its future boundaries are:

| Area | Planned owner | First release |
| --- | --- | --- |
| reviewed country records and local flags | Data Agent | 0.2.0 |
| deterministic quiz manifests | Content Agent | 0.7.0 |
| Remotion timeline and renderer | Video Engine Agent | 0.3.0 |
| fixed visual system | Design Agent | 0.4.0 |
| cached narration and sound | Audio Agent | 0.5.0 |
| fixed app end card | App Promo Agent | 0.6.0 |
| platform-specific exports | Platform Agent | 0.9.0 |
| blocking production checks | QA Agent | 0.10.0 |
| versions, tags and rollback | Release Agent | every release |

## Reuse decision

Reuse app branding and a human-reviewed subset of the country catalog. Do not
reuse remote flag URLs, gameplay mastery tiers as quiz difficulty, or app-only
service code. The concrete country-data risks are listed in
[`data-audit.md`](data-audit.md).
