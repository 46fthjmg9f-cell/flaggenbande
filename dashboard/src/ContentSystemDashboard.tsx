import { useEffect, useState } from 'react'
import {
  emptyContentOperations,
  parseContentOperations,
  type ContentOperationsData,
  type PlatformStatus,
  type SystemStatus,
} from './contentOperations'

const statusLabels: Record<SystemStatus | PlatformStatus, string> = {
  ready: 'Bereit',
  planned: 'Geplant',
  not_configured: 'Nicht verbunden',
  error: 'Fehler',
  uploading: 'Upload läuft',
  scheduled: 'Eingeplant',
  published: 'Veröffentlicht',
  failed: 'Fehlgeschlagen',
}

const platformAbbreviations = {
  youtube: 'YT',
  instagram: 'IG',
  tiktok: 'TT',
  facebook: 'FB',
} as const

function formatTimestamp(value: string | null): string {
  if (!value) return 'Noch keine Plattformdaten'
  const timestamp = new Date(value)
  if (Number.isNaN(timestamp.valueOf())) return 'Zeitpunkt unbekannt'
  return new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium', timeStyle: 'short' }).format(timestamp)
}

function formatNumber(value: number | null): string {
  return value === null ? '—' : new Intl.NumberFormat('de-DE', { maximumFractionDigits: 1 }).format(value)
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

  return <section id="content-system-view" className="dashboard-view" role="tabpanel" aria-labelledby="content-system-tab" tabIndex={0}>
    <header className="hero content-hero">
      <div>
        <span className="eyebrow">FLAGGENBANDE · CONTENT-SYSTEM</span>
        <h1>Produktion und Plattformen.</h1>
        <p>Diese öffentliche Ansicht zeigt ausschließlich bereinigte Betriebs- und Leistungsdaten. Zugangsdaten, lokale Pfade und unveröffentlichte Inhalte bleiben außerhalb des Browsers.</p>
      </div>
      <div className="sync-controls">
        <div className={`sync-state ${data.status}`}><span className="pulse" />{formatTimestamp(data.generatedAt)}</div>
        <button className="refresh" onClick={() => void refresh()} disabled={refreshing}>{refreshing ? 'Wird aktualisiert …' : 'Content-Status aktualisieren'}</button>
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

    <section className="content-section" aria-labelledby="platform-status-title">
      <div className="section-heading"><div><span>PLATTFORMEN</span><h2 id="platform-status-title">Upload-Verbindungen</h2></div><p>Keine Zugangsdaten im Dashboard</p></div>
      {data.platforms.length > 0 ? <div className="platform-grid">{data.platforms.map(platform => <article className="platform-card" key={platform.platform}>
        <div className="platform-card-heading"><span className={`platform-mark ${platform.platform}`} aria-hidden="true">{platformAbbreviations[platform.platform]}</span><div><strong>{platform.label}</strong><span className={`status-badge ${platform.status}`}>{statusLabels[platform.status]}</span></div></div>
        <dl><div><dt>Uploads</dt><dd>{platform.uploads}</dd></div><div><dt>Veröffentlicht</dt><dd>{platform.publications}</dd></div><div><dt>Performance</dt><dd>{platform.performanceAvailable ? 'Verfügbar' : 'Noch nicht'}</dd></div></dl>
        <p>{platform.reason}</p><small>{platform.updatedAt ? `Stand ${formatTimestamp(platform.updatedAt)}` : 'Noch kein Plattform-Sync'}</small>
      </article>)}</div> : <EmptyState title="Plattformstatus nicht verfügbar" detail="Der öffentliche Datenexport enthält aktuell keine Plattformverbindungen." />}
    </section>

    <section className="content-activity-grid" aria-label="Produktion, Uploads und Performance">
      <article className="content-activity-card">
        <div className="activity-heading"><span>PRODUKTION</span><h2>Letzte Läufe</h2></div>
        {data.runs.length === 0 ? <EmptyState title="Noch keine Produktionsläufe" detail="Produktionsdaten erscheinen nach dem ersten stabilen Renderer-Lauf." /> : <ul className="activity-list">{data.runs.map(run => <li key={run.runId}><div><strong>{run.title ?? run.contentId}</strong><small>{run.runId}</small></div><span className={`status-badge ${run.status}`}>{run.status}</span></li>)}</ul>}
      </article>
      <article className="content-activity-card">
        <div className="activity-heading"><span>UPLOADS</span><h2>Veröffentlichungen</h2></div>
        {data.publications.length === 0 ? <EmptyState title="Noch keine Uploads" detail="Upload-Daten bleiben leer, bis ein geprüfter Plattformadapter verbunden ist." /> : <ul className="activity-list">{data.publications.map((publication, index) => <li key={`${publication.contentId}-${publication.platform}-${index}`}><div><strong>{publication.title ?? publication.contentId}</strong><small>{publication.platform}</small></div><span className={`status-badge ${publication.status}`}>{statusLabels[publication.status]}</span></li>)}</ul>}
      </article>
      <article className="content-activity-card">
        <div className="activity-heading"><span>PERFORMANCE</span><h2>Plattformvergleich</h2></div>
        {data.performance.length === 0 ? <EmptyState title="Noch keine Performancewerte" detail="Nicht verfügbare Plattformmetriken werden nicht als Nullwerte dargestellt." /> : <ul className="activity-list">{data.performance.map((snapshot, index) => <li key={`${snapshot.contentId}-${snapshot.platform}-${index}`}><div><strong>{snapshot.contentId}</strong><small>{snapshot.platform}</small></div><span>{formatNumber(snapshot.views)} Views</span></li>)}</ul>}
      </article>
    </section>

    <footer>Flaggenbande Content-System · GitHub Pages zeigt keine Tokens, API-Schlüssel, lokalen Pfade oder unveröffentlichten Videoinhalte.</footer>
  </section>
}
