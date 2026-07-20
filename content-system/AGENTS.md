# Flaggenbande Content-System Agent Rules

## Product boundary

Build one stable, deterministic quiz Production Engine. Do not add research,
experimentation, self-optimization or a second analytics platform.

## Ownership

- Manager: architecture, releases, integration and cost control
- Data: country records, ISO codes, names, capitals, difficulty and flags
- Content: deterministic quiz manifests and platform metadata
- Video Engine: timeline, rendering and batch production
- Design: approved visual system and safe areas
- Audio: cached speech, music, effects and normalization
- App Promo: fixed Flaggenbande end card and approved app assets
- Platform: exports and later guarded upload adapters
- QA: data, timeline, asset, audio and render gates
- Release: versions, changelog, tags, rollback and release notes

Agents must not change another area’s approved contract without Manager review.
No public publishing, credential changes or paid services without explicit human
approval.

## Model and reasoning policy

- Use `gpt-5.6-sol` for specialist agents unless a smaller model is explicitly
  sufficient.
- Small, bounded edits use low or medium reasoning.
- Normal implementation and verification use medium reasoning.
- Architecture, migrations and difficult integration faults may use high
  reasoning.
- Subagents never use ultra reasoning. Ultra is reserved for the Manager Agent
  and only when the task genuinely requires it.
