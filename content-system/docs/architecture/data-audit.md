# Existing country-data audit

The Swift app catalog is useful import material, not a production database.
The current snapshot contains 244 unique entities: 193 core countries, 41
dependent territories and 10 partially recognized entities. Every entry has a
German and English country name plus one capital string, while only 129 have a
dedicated pronunciation aid.

## Blocking issues before Release 0.2.0

- Flags are remote dependencies: 240 FlagCDN URLs and four Wikimedia URLs.
- No source, license, checksum, reviewer or review date is stored.
- `NC` is used for Northern Cyprus even though ISO assigns it to New Caledonia.
- `GB-ENG`, `GB-SCT`, `GB-WLS`, `GB-NIR` and `SLD` are not ISO alpha-2 codes.
- `XK` is a commonly reserved user code, not an assigned ISO alpha-2 code.
- Capital names are German-only and cannot safely drive English narration.
- One-capital strings cannot model countries with multiple capital roles.
- Senegal’s pronunciation value says “Senegal” instead of “Dakar”.
- User mastery tiers are not global quiz difficulty levels.
- Territories and disputed entities must be excluded from standard quizzes by
  default until a human-approved content policy exists.

## 0.2.0 import rule

Start with a reviewed sovereign-country pool. Keep a stable internal entity ID
separate from optional ISO codes, store localized names and capital arrays,
require difficulty 1–5, and make every standard-quiz entry point to a local,
licensed, checksum-verified flag asset. Validation fails closed.
