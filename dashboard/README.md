# Flaggenbande Analytics Dashboard

Das Dashboard ist ein statisches Vite/React-Frontend für GitHub Pages. Es liest **ausschließlich** `public/data/dashboard.json`. Diese Datei enthält nur aggregierte Kennzahlen und wird durch GitHub Actions erzeugt; weder API-Schlüssel noch CloudKit-Rohdaten noch Spieleridentitäten werden publiziert.

## Einmalige GitHub-Konfiguration

1. In **Settings → Pages** als Quelle **GitHub Actions** wählen.
2. Unter **Settings → Actions → General** den Workflow-Berechtigungen `Read and write permissions` erlauben.
3. Diese Secrets im Repository anlegen:

| Secret | Zweck |
| --- | --- |
| `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY` | Team-Schlüssel mit mindestens *Sales and Reports* |
| `ASC_APP_ID` | numerische Apple-ID der App (kein Geheimnis, wird dennoch als Secret gehalten) |
| `ASC_ANALYTICS_REPORT_REQUEST_ID` | bestehende laufende Analytics-Report-Anfrage |
| `ASC_VENDOR_NUMBER` | optional; erforderlich für Sales & Trends |
| `ASC_FINANCE_ISSUER_ID`, `ASC_FINANCE_KEY_ID`, `ASC_FINANCE_PRIVATE_KEY` | optionaler Team-Schlüssel mit Rolle *Finance*; aktiviert den aktuellen Monats-Finanzreport |
| `CLOUDKIT_KEY_ID`, `CLOUDKIT_PRIVATE_KEY` | CloudKit Server-to-Server Key nur für die öffentliche Datenbank |
| `CLOUDKIT_CONTAINER` | optional; Standard ist `iCloud.de.phil.SpassmitFlaggen` |

CloudKit muss dafür im CloudKit Dashboard unter **API Access → Server-to-Server Keys** einen P-256-Schlüssel erhalten. Der private Schlüssel gehört nur in `CLOUDKIT_PRIVATE_KEY`; niemals in App, Pages-Build oder Repository.

## Datenschutz

Der Collector fragt aus CloudKit nur die für Aggregate notwendigen Felder ab. Er veröffentlicht weder Namen, Game-Center-IDs, Record-Namen, Profil-Snapshots noch Antwortverläufe. App Analytics kann aufgrund Apples Datenschutzschwellen und Reporting-Latenzen zunächst leer sein; das Dashboard kennzeichnet das statt Nullwerte zu erfinden.

Der Abruf folgt den paginierten Analytics-Instanzen und CloudKit-Continuation-Markern, nutzt exponentielle Wiederholungsversuche bei temporären API-Fehlern und schreibt die JSON-Datei atomar. Schlägt ein Abruf fehl, bleibt die letzte sichere Aggregation sichtbar.
