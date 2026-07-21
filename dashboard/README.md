# Flaggenbande Analytics Dashboard

Das Dashboard ist ein statisches Vite/React-Frontend für GitHub Pages. Es trennt die öffentlichen Daten in vier unabhängig benannte Hauptbereiche: **App & Entwicklung**, **Videos**, **Social Stats** und **Finanzen**. Die sichtbaren Namen und ihre Reihenfolge liegen zentral in `src/dashboardSections.ts` und können ohne Änderung der Seitenlogik angepasst werden.

Die App-, Social- und Finanzauswertung liest `public/data/dashboard.json`. Diese Datei enthält nur aggregierte Kennzahlen und wird durch GitHub Actions erzeugt; weder API-Schlüssel noch CloudKit-Rohdaten noch Spieleridentitäten werden publiziert.

Der Bereich **Videos** liest zusätzlich den versionierten öffentlichen Vertrag `public/data/content-operations.json`. Er zeigt pro Video den freigegebenen Produktions-, Quality- und Plattformstatus. Social-Performance wird ausschließlich in **Social Stats**, Finanzwerte ausschließlich in **Finanzen** dargestellt. Unveröffentlichte Titel, lokale Pfade, Rohdaten und Zugangsdaten dürfen nicht in die öffentlichen Dateien geschrieben werden. Der serverseitige Social-Collector erkennt veröffentlichte Plattformvideos über die autorisierten Konten automatisch; manuelle Videolinks sind nicht erforderlich.

## Lokale Prüfung

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/dashboard
npm ci
npm run check
npm run build
```

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
| `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET`, `YOUTUBE_REFRESH_TOKEN` | YouTube Data und Analytics API für veröffentlichte Videos |
| `META_ACCESS_TOKEN`, `INSTAGRAM_ACCOUNT_ID`, `FACEBOOK_PAGE_ID` | Instagram- und Facebook-Medien sowie verfügbare Insights |
| `TIKTOK_ACCESS_TOKEN` | TikTok-Videoliste und verfügbare Basiskennzahlen |

Optional kann `META_GRAPH_API_VERSION` als GitHub-Variable gesetzt werden; ohne Angabe verwendet der Collector `v24.0`.

Für den nichtöffentlichen Upload-Testlauf kann zusätzlich die GitHub-Variable `UPLOAD_STAGING_FEED_URL` auf den öffentlichen HTTPS-Endpunkt `/staging/feed` zeigen. Alternativ reicht `UPLOAD_STAGING_API_URL` als Basisadresse; der Collector ergänzt den Pfad selbst. Der Abruf sendet bewusst keinen Token und übernimmt ausschließlich freigegebene Lauf- und Plattformstatus in `content-operations.json`. Private Objekt-IDs, Container-IDs, Medienadressen, Metadaten und Providerfehler werden nicht veröffentlicht.

CloudKit muss dafür im CloudKit Dashboard unter **API Access → Server-to-Server Keys** einen P-256-Schlüssel erhalten. Der private Schlüssel gehört nur in `CLOUDKIT_PRIVATE_KEY`; niemals in App, Pages-Build oder Repository.

## Datenschutz

Der Collector fragt aus CloudKit und den Plattform-APIs nur die für Aggregate notwendigen Felder ab. Er veröffentlicht weder Namen, Game-Center-IDs, Record-Namen, Profil-Snapshots, Antwortverläufe noch Zugangsdaten. Nicht verfügbare Plattformmetriken bleiben `null`, statt als Nullleistung interpretiert zu werden. App Analytics kann aufgrund Apples Datenschutzschwellen und Reporting-Latenzen zunächst leer sein; das Dashboard kennzeichnet das statt Nullwerte zu erfinden.

Der Abruf läuft stündlich zur Minute 17, folgt den paginierten Analytics-Instanzen und CloudKit-Continuation-Markern, nutzt exponentielle Wiederholungsversuche bei temporären API-Fehlern und schreibt die JSON-Datei atomar. Schlägt ein Abruf fehl, bleibt die letzte sichere Aggregation sichtbar. Bei Bedarf kann er in GitHub Actions manuell gestartet werden.
