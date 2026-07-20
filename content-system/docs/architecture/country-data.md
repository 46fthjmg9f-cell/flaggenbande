# Country Data Architecture

Release 0.2.0 uses a fail-closed dataset for the fixed Flaggenbande quiz format.
The standard pool contains exactly the 193 United Nations member states. It does
not silently mix territories, subdivisions, observer states or disputed
entities into ordinary quizzes.

## Frozen source strategy

| Data | Pinned source | License/use |
| --- | --- | --- |
| inclusion and geographic codes | UN M49 snapshot | authoritative reference |
| German and English display names | Unicode CLDR 48.2.0 | Unicode-3.0 |
| capital candidates | dated Wikidata snapshot | CC0 |
| local SVG flags | flag-icons 7.5.0, 4×3 set | MIT |
| legacy aliases | existing iOS `FlagCatalog.swift` | internal product data |

Runtime rendering never downloads country data or flags. Source snapshots are
fetched once, normalized deterministically, reviewed, checksummed and published
as an immutable dataset release.

The UN overview snapshot supplies alpha-2, alpha-3, M49 and the most specific
available M49 geographic region. CLDR supplies German and English display
names. The Wikidata query is constrained to the reviewed 193-code allowlist and
current UN-member entities, with an explicit Denmark data exception; its
result must still contain the exact 193-code set. Missing labels remain visible
review issues and are never silently promoted to approved data.

The generator copies both dated source snapshots into the candidate package.
The release publisher generates the complete dataset twice, compares every
byte, writes a release manifest plus `SHA256SUMS`, copies to a unique incoming
OneDrive directory, re-reads it, atomically renames it and verifies the final
directory again. Existing candidate versions cannot be overwritten.

## Review boundary

Generated candidates are not production records. A country becomes eligible
only after names, capital roles, difficulty and its flag have an approved review
record with no unresolved conflicts. Difficulty is a transparent manual level
from 1 to 5 and is not copied from app mastery tiers.

Targeted manual review is mandatory for countries with multiple capital roles,
recent changes or policy-sensitive geography. The review queue must include at
least South Africa, Bolivia, Sri Lanka, Eswatini, the Netherlands, Benin,
Malaysia, Nauru, Switzerland, Equatorial Guinea, Indonesia, Afghanistan, Syria,
Israel, Yemen and Sudan.

## Blocking rules

- exactly 193 unique ISO alpha-2 records
- unique stable IDs, alpha-3, numeric and M49 codes
- German and English names plus at least one capital
- local, safe SVG for every record
- matching SHA-256, byte size, source and license metadata
- no remote URLs, path traversal, scripts or external SVG resources
- no unreviewed record can enter a quiz manifest
- deterministic ordering and byte-stable generation

The old `NC` Northern-Cyprus collision and custom codes such as `GB-ENG`, `XK`
and `SLD` are regression cases and must never enter the 193-country pool.
