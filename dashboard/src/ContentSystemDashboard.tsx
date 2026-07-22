import { useEffect, useMemo, useState } from 'react'
import VideoProductionControl from './VideoProductionControl'
import {
  emptyContentOperations,
  parseContentOperations,
  type ContentOperationsData,
  type PlatformId,
  type PublicationStatus,
  type ProductionRunStatus,
} from './contentOperations'

const runLabels: Record<ProductionRunStatus, string> = {
  queued: 'Wartet',
  running: 'Läuft',
  partial: 'Teilweise',
  qa_failed: 'Qualität fehlgeschlagen',
  ready: 'Bereit',
  completed: 'Fertig',
  failed: 'Fehler',
  expired: 'Abgelaufen',
  reconcile_required: 'Prüfen',
}

const platformLabels: Record<PlatformId, string> = { youtube: 'YT', instagram: 'IG', facebook: 'FB', tiktok: 'TT' }

function platformState(status: PublicationStatus): string {
  if (status === 'published') return 'published'
  if (status === 'scheduled' || status === 'private' || status === 'draft' || status === 'container_unpublished' || status === 'upload_ready' || status === 'manual_uploaded') return 'ready'
  if (status === 'uploading' || status === 'processing') return 'running'
  if (status === 'failed' || status === 'expired' || status === 'reconcile_required') return 'failed'
  return 'missing'
}

function formatTimestamp(value: string | null): string {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? '—' : new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' }).format(date)
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
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setRefreshing(false)
    }
  }

  useEffect(() => { void refresh() }, [])

  const runs = useMemo(() => [...data.runs]
    .sort((a, b) => b.startedAt.localeCompare(a.startedAt))
    .slice(0, 12)
    .map(run => ({
      ...run,
      publications: data.publications.filter(publication => publication.runId === run.runId),
    })), [data.publications, data.runs])

  return <section id="production-view" className="dashboard-view" role="tabpanel" aria-labelledby="production-tab" tabIndex={0}>
    <header className="compact-page-header">
      <h1>Produktion</h1>
      <button type="button" onClick={() => void refresh()} disabled={refreshing} aria-label="Produktionsdaten aktualisieren">↻</button>
    </header>
    {error && <p className="operator-error">{error}</p>}
    <VideoProductionControl />
    <section className="recent-production">
      <div className="compact-heading"><h2>Letzte Videos</h2><span>{formatTimestamp(data.generatedAt)}</span></div>
      <div className="recent-production-list">
        {runs.length > 0 ? runs.map(run => <article className="recent-production-row" key={run.runId}>
          <div className="recent-production-main">
            <strong>{run.title ?? 'Video'}</strong>
            <span>{formatTimestamp(run.completedAt ?? run.startedAt)}</span>
          </div>
          <span className={`status-badge ${run.status}`}>{runLabels[run.status]}</span>
          <div className="recent-platforms" aria-label="Plattformstatus">
            {(['youtube', 'instagram', 'facebook', 'tiktok'] as const).map(platform => {
              const publication = run.publications.find(entry => entry.platform === platform)
              return <span className={`calendar-platform ${publication ? platformState(publication.status) : 'missing'}`} key={platform}>{platformLabels[platform]}</span>
            })}
          </div>
        </article>) : <p className="compact-empty">Keine Videos</p>}
      </div>
    </section>
  </section>
}
