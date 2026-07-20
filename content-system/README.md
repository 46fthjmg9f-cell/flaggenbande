# Flaggenbande Content System

Stabiles Fundament für die spätere Produktion gleichbleibender Flaggen-Quiz-
Shorts. Release `0.2.0` ergänzt eine reproduzierbare Kandidaten-Datenbank für
exakt 193 UN-Mitgliedstaaten. Die Daten bleiben bis zur menschlichen Prüfung
für die Produktion gesperrt; Video-, Audio- und Uploadlogik folgen später.

## Voraussetzungen

- macOS oder Linux
- Node.js 22 oder neuer
- npm

## Installation

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm install
```

## Start

Development:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm start
```

Production-Konfiguration prüfen:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run start:production
```

Vollständige Prüfung:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run check
```

Lokale Voraussetzungen und Schreibpfade prüfen:

```bash
cd /Users/praemer/Projects/flaggenbande-content-r010/content-system
npm run doctor
```

## Konfiguration

Die versionierten Standardwerte liegen unter `config/development` und
`config/production`. Optionale lokale Überschreibungen stehen in
`.env.example`. Zugangsdaten gehören niemals in das Repository.

Ausführlichere Betriebs- und Fehlerhinweise stehen unter
[`docs/operations.md`](docs/operations.md).

## Release-Grenze

`0.2.0` erzeugt und prüft Länder-Datenkandidaten, lokale SVG-Flaggen,
Quellen-Snapshots, Review-Queue und Prüfsummen. Erst eine gesonderte menschliche
Freigabe darf Einträge quizfähig machen. Das erste gerenderte Quizvideo gehört
zu `0.3.0`.
