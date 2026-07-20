# Flaggenbande Content System

Stabiles Fundament für die spätere Produktion gleichbleibender Flaggen-Quiz-
Shorts. Release `0.1.0` enthält bewusst noch keine Video-, Länder-, Audio- oder
Uploadlogik. Diese Funktionen werden in den festgelegten Releases ergänzt.

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

`0.1.0` liefert nur reproduzierbares Projektfundament, Konfiguration, Logging,
Dokumentation und Tests. Die Länderbank beginnt mit `0.2.0`; das erste
gerenderte Quizvideo gehört zu `0.3.0`.
