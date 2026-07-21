import { useEffect, useState } from 'react'
import {
  emptyContentOperations,
  parseContentOperations,
  type ContentOperationsData,
  type PlatformStatus,
  type ProductionRunStatus,
  type PublicationStatus,
  type SystemStatus,
} from './contentOperations'

const statusLabels: Record<SystemStatus | PlatformStatus | PublicationStatus | ProductionRunStatus, string> = {
  ready: 'Bereit',
  planned: 'Geplant',
  not_configured: 'Nicht verbunden',
  error: 'Fehler',
  uploading: 'Upload läuft',
  processing: 'Verarbeitung läuft',
  scheduled: 'Eingeplant',
  published: 'Veröffentlicht',
  failed: 'Fehlgeschlagen',
  private: 'Privat',
  draft: 'Entwurf',
  container_unpublished: 'Container bereit · unveröffentlicht',
  upload_ready: 'Upload-bereit · unveröffentlicht',
  manual_uploaded: 'Manuell hochgeladen',
  expired: 'Abgelaufen',
  reconcile_required: 'Abstimmung erforderlich',
  queued: 'In Warteschlange',
  running: 'Läuft',
  partial: 'Teilweise abgeschlossen',
  qa_failed: 'QA fehlgeschlagen',
  completed: 'Abgeschlossen',
}

const platformAbbreviations = {
  youtube: 'YT',
  instagram: 'IG',
  tiktok: 'TT',
  facebook: 'FB',
} as const

const qualityLabels = {
  not_run: 'Noch nicht geprüft',
  passed: 'Qualität bestanden',
  failed: 'Qualität fehlgeschlagen',
} as const

function formatTimestamp(value: string | null): string {
  if (!value) return 'Noch keine Plattformdaten'
  const timestamp = new Date(value)
  if (Number.isNaN(timestamp.valueOf())) return 'Zeitpunkt unbekannt'
  return new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium', timeStyle: 'short' }).format(timestamp)
}

function humanRunTitle(runId: string, title: string | null): string {
  if (title) return title
  const cleaned = runId
    .replace(/^upload-test-/, '')
    .replace(/^gameshow-/, '')
    .replace(/-v(\d+)$/, ' · V$1')
    .replaceAll('-', ' ')
  return cleaned.replace(/\b\w/g, letter => letter.toUpperCase())
}

function EmptyState({ title, detail }: { title: string; detail: string }) {
  return <div className="content-empty"><span aria-hidden="true">○</span><div><strong>{title}</strong><p>{detail}</p></div></div>
}

export default function ContentSystemDashboard() {
  const [data, setData] = useState<ContentOperationsData>(emptyContentOperations)
  const [error, setError] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const refresh = async () => {
    setRefreshing(true)
    setError(null)
    try {
      const response = await fetch(`./data/content-operations.json?refresh=${Date.now()}`, { cache: 'no-store' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      setData(parseContentOperations(await response.json()))
    } catch (reason) {
      const detail = reason instanceof Error ? reason.message : String(reason)
      setError(`Content-System-Daten konnten nicht sicher geladen werden: ${detail}`)
    } finally {
      setRefreshing(false)
    }
  }

  useEffect(() => {
    void refresh()
  }, [])

  const videoRuns = data.runs.map(run => ({
    ...run,
    displayTitle: humanRunTitle(run.runId, run.title),
    publications: data.publications.filter(publication => publication.runId === run.runId),
  }))

  return <section id="videos-view" className="dashboard-view" role="tabpanel" aria-labelledby="videos-tab" tabIndex={0}>
    <header className="hero content-hero">
      <div>
        <span className="eyebrow">FLAGGENBANDE · VIDEO-STUDIO</span>
        <h1>Von der Idee bis zum Upload.</h1>
        <p>Produktionsstand, Qualitätsprüfung und Plattformstatus jedes Videos in einer gemeinsamen Ansicht. Social Performance und App-Daten befinden sich in ihren eigenen Bereichen.</p>
      </div>
      <div className="sync-controls">
        <div className={`sync-state ${data.status}`}><span className="pulse" />{formatTimestamp(data.generatedAt)}</div>
        <button className="refresh" onClick={() => void refresh()} disabled={refreshing}>{refreshing ? 'Wird aktualisiert …' : 'Video-Status aktualisieren'}</button>
        <small>Öffentlicher Snapshot · Schema {data.schemaVersion}</small>
      </div>
    </header>

    {(error || data.messages.length > 0) && <section className="notices content-notices" aria-live="polite">
      {error && <p className="error">{error}</p>}
      {data.messages.map(message => <p key={message}>{message}</p>)}
    </section>}

    <section className="content-section" aria-labelledby="system-status-title">
      <div className="section-heading"><div><span>SYSTEM</span><h2 id="system-status-title">Produktionsbereitschaft</h2></div><p>Nur freigegebene, öffentliche Zustände</p></div>
      {data.system.length > 0 ? <div className="system-status-grid">{data.system.map(component => <article className="system-status-card" key={component.id}>
        <div className="status-card-heading"><span className={`status-dot ${component.status}`} /><span className={`status-badge ${component.status}`}>{statusLabels[component.status]}</span></div>
        <p>{component.label}</p><strong>{component.value}</strong><small>{component.detail}</small>
      </article>)}</div> : <EmptyState title="Systemstatus noch nicht vorhanden" detail="Der erste sichere Datenexport ergänzt Engine, Release, Datenbank und Quality-Gate." />}
    </section>

    <section className="content-section" aria-labelledby="video-overview-title">
      <div className="section-heading"><div><span>VIDEOS</span><h2 id="video-overview-title">Produktionsübersicht</h2></div><p>Ein Eintrag pro Video · alle Plattformen gemeinsam</p></div>
      {videoRuns.length === 0 ? <EmptyState title="Noch keine Produktionsläufe" detail="Nach dem ersten Video-Lauf erscheinen hier Produktion, Quality-Gate und Uploadstatus gemeinsam." /> : <div className="video-operations-list">{videoRuns.map(run => <article className="video-operation-card" key={run.runId}>
        <div className="video-operation-heading">
          <div><span>VIDEO</span><h3>{run.displayTitle}</h3><small>Gestartet {formatTimestamp(run.startedAt)}</small></div>
          <span className={`status-badge ${run.status}`}>{statusLabels[run.status]}</span>
        </div>
        <dl className="video-operation-meta">
          <div><dt>Produktion</dt><dd>{statusLabels[run.status]}</dd></div>
          <div><dt>Qualitätsprüfung</dt><dd className={run.qualityStatus === 'passed' ? 'quality-passed' : run.qualityStatus === 'failed' ? 'quality-failed' : ''}>{qualityLabels[run.qualityStatus]}</dd></div>
          <div><dt>Abgeschlossen</dt><dd>{run.completedAt ? formatTimestamp(run.completedAt) : 'Noch offen'}</dd></div>
        </dl>
        <div className="video-platform-row" aria-label="Plattformstatus">{run.publications.length > 0 ? run.publications.map(publication => <span className={`video-platform-status ${publication.platform} ${publication.status}`} key={publication.platform}>
          <b>{platformAbbreviations[publication.platform]}</b><span>{statusLabels[publication.status]}</span>
        </span>) : <span className="video-platform-empty">Noch keine Uploadstände</span>}</div>
        <details className="technical-reference"><summary>Interne Referenz</summary><code>{run.runId}</code></details>
      </article>)}</div>}
    </section>

    <footer>Flaggenbande Video-Studio · GitHub Pages zeigt keine Tokens, API-Schlüssel, lokalen Pfade oder unveröffentlichten Videoinhalte.</footer>
  </section>
}
