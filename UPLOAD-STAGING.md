# Nichtöffentlicher Upload-Testlauf

Diese Strecke bereitet den späteren automatischen Upload vor, ohne ein Video zu veröffentlichen oder einzuplanen:

- YouTube: `private`
- Facebook: Reel-Entwurf (`DRAFT`)
- Instagram: unveröffentlichter Mediencontainer; kein Aufruf von `media_publish`
- TikTok: ausschließlich dokumentierte manuelle Nutzerbestätigung; kein API-Aufruf

Der Testlauf ist von der bestehenden Veröffentlichungsstrecke getrennt. Er verwendet die bewährten FactVerse-Muster für SHA-256-Content-IDs, persistente Statusdateien, atomare Schreibvorgänge, Zielkonto-Prüfung und Duplikatschutz. Er übernimmt ausdrücklich weder FactVerses automatische Publish-Entscheidung noch dessen Mock-Erfolgsstatus.

## Statusmodell

Ein Dashboard-Status ist erst nach einer Plattformbestätigung gesetzt:

- `private`: YouTube bestätigte `privacyStatus=private` und keinen Veröffentlichungszeitpunkt.
- `draft`: Facebook bestätigte einen nichtöffentlichen Entwurf.
- `container_unpublished`: Instagram verarbeitete den Container; er wurde nicht veröffentlicht und läuft nach ungefähr 24 Stunden ab.
- `manual_uploaded`: TikTok wurde vom Nutzer als manuell hochgeladen bestätigt; die öffentliche Sichtbarkeit wird daraus nicht abgeleitet.
- `reconcile_required`: Eine Remote-Antwort blieb unklar. Der Runner startet dann keinen zweiten Upload.

Private Receipts und Plattform-IDs liegen nur in OneDrive beziehungsweise im konfigurierten privaten State-Verzeichnis. Das öffentliche Dashboard erhält ausschließlich bereinigte Statusfelder. Veröffentlichte Plattformanalysen bleiben davon getrennt.

Das Dashboard zählt nur von der Plattform bestätigte Testuploads. Ein lediglich `planned`-Ziel erhöht den Upload-Zähler nicht. `runId`, nichtöffentlicher Modus und tatsächlicher Aktualisierungszeitpunkt bleiben im bereinigten Snapshot erhalten, damit spätere automatisierte Läufe eindeutig zugeordnet werden können.

Temporäre Cloudflare-Pages-Medien werden erst entfernt, wenn Instagram den unveröffentlichten Container und Facebook den Entwurf sicher bestätigt haben. Der Cleanup prüft Projekt, eindeutige Medien-URL und Branch, verarbeitet alle Ergebnisseiten und validiert die Löschung. Unklare Plattformzustände blockieren den Cleanup fail-closed.

## Lokaler Sicherheitstest

Dieser vollständige Befehl prüft MP4, Quality-Report, Metadaten und Dashboard-Vertrag, verändert aber keine Plattform:

```bash
cd "/Users/praemer/Projects/.flaggenbande-worktrees/upload-staging" && npm run upload:test -- \
  --input "/vollstaendiger/pfad/video.mp4" \
  --metadata "/vollstaendiger/pfad/upload-metadata.json" \
  --quality-report "/vollstaendiger/pfad/quality-report.json" \
  --state-dir "/vollstaendiger/privater/pfad/upload-staging/state" \
  --output "/vollstaendiger/privater/pfad/upload-staging-plan.json" \
  --public-output "/Users/praemer/Projects/.flaggenbande-worktrees/upload-staging/dashboard/public/data/upload-staging.json" \
  --dry-run
```

## Dashboard-Anbindung ohne Plattform-Upload

`--register-only` registriert den validierten Lauf beim Cloud-Statusdienst. YouTube, Facebook und Instagram werden dabei nicht aufgerufen. TikTok bleibt ausschließlich die bereits dokumentierte manuelle Bestätigung. Damit lässt sich die komplette Dashboard-Anbindung risikofrei testen:

```bash
cd "/Users/praemer/Projects/.flaggenbande-worktrees/upload-staging" && \
  node --env-file-if-exists=.env.platforms scripts/upload-staging.mjs \
  --input "/vollstaendiger/pfad/video.mp4" \
  --metadata "/vollstaendiger/pfad/upload-metadata.json" \
  --quality-report "/vollstaendiger/pfad/quality-report.json" \
  --state-dir "/vollstaendiger/privater/pfad/upload-staging/state" \
  --output "/vollstaendiger/privater/pfad/upload-staging-status.json" \
  --register-only
```

## Kontrollierter Remote-Test

`--execute` ist die einzige Freigabe für Remote-Schreibvorgänge. Die `.env.platforms` bleibt serverseitig und wird nie ins Repository eingecheckt. Erforderlich sind:

- `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET`, `YOUTUBE_REFRESH_TOKEN`, `YOUTUBE_CHANNEL_ID`
- `UPLOAD_STAGING_API_URL`, `UPLOAD_STAGING_API_TOKEN`
- für Meta zusätzlich eine kontrollierte temporäre HTTPS-MP4 samt `--media-url`, `--media-project` und `--media-branch`

```bash
cd "/Users/praemer/Projects/.flaggenbande-worktrees/upload-staging" && \
  node --env-file-if-exists=.env.platforms scripts/upload-staging.mjs \
  --input "/vollstaendiger/pfad/video.mp4" \
  --metadata "/vollstaendiger/pfad/upload-metadata.json" \
  --quality-report "/vollstaendiger/pfad/quality-report.json" \
  --state-dir "/vollstaendiger/privater/pfad/upload-staging/state" \
  --output "/vollstaendiger/privater/pfad/upload-staging-status.json" \
  --media-url "https://kontrolliertes-pages-projekt.pages.dev/video.mp4" \
  --media-project "kontrolliertes-pages-projekt" \
  --media-branch "eindeutiger-test-branch" \
  --execute
```

Bei einem unklaren Create-/Finish-Ergebnis wird nur der Remote-Status abgefragt. Es gibt keinen blinden zweiten Upload und keinen `--force`-Schalter.
