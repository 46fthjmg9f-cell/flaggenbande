# Flaggenbande Auswertungsübersicht

Die Übersicht ist ein statisches Vite/React-Frontend für GitHub Pages. Die Navigation trennt **Neue Produktion**, **Videos**, **Kalender**, **Stats**, **App** und **Finanzen**. Die sichtbaren Namen und ihre Reihenfolge liegen zentral in `src/dashboardSections.ts`.

Die App-, Plattform- und Finanzauswertung liest `public/data/dashboard.json`. Diese Datei enthält nur zusammengefasste Kennzahlen und wird durch GitHub Actions erzeugt; weder API-Schlüssel noch CloudKit-Rohdaten noch Spieleridentitäten werden veröffentlicht.

**Neue Produktion** enthält ausschließlich die sichere Produktionssteuerung. Der Bereich **Videos** liest zusätzlich den versionierten öffentlichen Vertrag `public/data/content-operations.json` und zeigt pro Video den Produktions-, Qualitäts- und Plattformstatus. Die Plattformleistung wird ausschließlich in **Stats**, Finanzwerte ausschließlich in **Finanzen** dargestellt. Unveröffentlichte Titel, lokale Pfade, Rohdaten und Zugangsdaten dürfen nicht in die öffentlichen Dateien geschrieben werden. Die serverseitige Datensammlung gleicht bestätigte öffentliche Plattformvideos mit alten Upload-Testläufen ab; unbestätigte Plattformen bleiben sichtbar und werden ausdrücklich als nicht verfügbar markiert.

## Lokale Prüfung

```bash
cd /Users/praemer/Desktop/SpassmitFlaggenapp/dashboard
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

Für den nichtöffentlichen Testlauf zum Hochladen kann zusätzlich die GitHub-Variable `UPLOAD_STAGING_FEED_URL` auf den öffentlichen HTTPS-Endpunkt `/staging/feed` zeigen. Alternativ reicht `UPLOAD_STAGING_API_URL` als Basisadresse; die Datensammlung ergänzt den Pfad selbst. Der Abruf sendet bewusst keine Zugangsdaten und übernimmt ausschließlich freigegebene Lauf- und Plattformstatus in `content-operations.json`. Private Objekt-IDs, Container-IDs, Medienadressen, Metadaten und Fehler externer Dienste werden nicht veröffentlicht.

Der Produktionsstatus wird danach über den ebenfalls öffentlichen, minimalen Endpunkt `/publication/feed` überlagert. `META_PUBLICATION_FEED_URL` kann diesen Endpunkt explizit festlegen; ohne die Variable wird er aus `UPLOAD_STAGING_API_URL` beziehungsweise `UPLOAD_STAGING_FEED_URL` abgeleitet. Der Feed enthält nur Content-ID, Plattform, Zeitpunkte, Status und einen begrenzten Fehlercode. Rohfehler, Metadaten, Medienpfade, Container-, Token- und Plattform-IDs bleiben serverseitig. Bestätigte öffentliche Plattformdaten werden zuletzt abgeglichen und haben Vorrang vor Queue- und Staging-Status.

CloudKit muss dafür im CloudKit Dashboard unter **API Access → Server-to-Server Keys** einen P-256-Schlüssel erhalten. Der private Schlüssel gehört nur in `CLOUDKIT_PRIVATE_KEY`; niemals in App, Pages-Build oder Repository.

## Datenschutz

Die Datensammlung fragt aus CloudKit und den Plattform-APIs nur die für Zusammenfassungen notwendigen Felder ab. Sie veröffentlicht weder Namen, Game-Center-IDs, Datensatznamen, Profil-Zwischenstände, Antwortverläufe noch Zugangsdaten. Eindeutige CloudKit-Nutzer werden ausschließlich gezählt; ihre Kennungen verlassen den Collector nicht. Nicht verfügbare Plattform- und App-Kennzahlen bleiben `null`, statt als Nullleistung interpretiert zu werden. Die App-Auswertung kann aufgrund Apples Datenschutzschwellen und Berichtsverzögerungen zunächst leer sein; die Übersicht kennzeichnet das ausdrücklich.

Der Abruf läuft stündlich zur Minute 17, folgt den paginierten Analytics-Instanzen und CloudKit-Continuation-Markern, nutzt exponentielle Wiederholungsversuche bei temporären API-Fehlern und schreibt die JSON-Datei atomar. Schlägt ein Abruf fehl, bleibt die letzte sichere Aggregation sichtbar. Bei Bedarf kann er in GitHub Actions manuell gestartet werden.
