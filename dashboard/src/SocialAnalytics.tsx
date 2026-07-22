import { useMemo, useRef, useState } from 'react'
import type { Numeric, RetentionPoint, SocialData, SocialMetrics, SocialPlatform, SocialVideo } from './types'

const platformLabels: Record<SocialPlatform, string> = {
  youtube: 'YouTube',
  instagram: 'Instagram',
  facebook: 'Facebook',
  tiktok: 'TikTok',
}

const platformOrder = Object.keys(platformLabels) as SocialPlatform[]

const metricLabels: Array<{ key: keyof SocialMetrics; label: string; unit?: string }> = [
  { key: 'views', label: 'Aufrufe' },
  { key: 'reach', label: 'Reichweite' },
  { key: 'likes', label: 'Gefällt mir' },
  { key: 'comments', label: 'Kommentare' },
  { key: 'shares', label: 'Geteilt' },
  { key: 'saves', label: 'Gespeichert' },
  { key: 'watchTimeMinutes', label: 'Wiedergabezeit', unit: ' min' },
  { key: 'averageViewDurationSeconds', label: 'Ø Wiedergabedauer', unit: ' s' },
  { key: 'averageViewPercentage', label: 'Ø angesehen', unit: ' %' },
  { key: 'followersGained', label: 'Neue Abonnenten' },
]

const publicationStatusLabel = (status: string): string => ({
  published: 'Veröffentlicht',
  scheduled: 'Eingeplant',
  private: 'Privat',
  draft: 'Entwurf',
  failed: 'Fehlgeschlagen',
}[status] ?? status)

const formatNumber = (value: Numeric) => value === null || value === undefined
  ? 'Nicht verfügbar'
  : new Intl.NumberFormat('de-DE', { maximumFractionDigits: 1, notation: value >= 10000 ? 'compact' : 'standard' }).format(value)

const formatMetric = (value: Numeric, unit = '') => value === null || value === undefined
  ? 'Nicht verfügbar'
  : `${formatNumber(value)}${unit}`

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : 'Nicht verfügbar'

const metricValue = (videos: SocialVideo[], key: keyof SocialMetrics): number | null => {
  const values = videos.map(video => video.metrics[key]).filter((value): value is number => typeof value === 'number')
  return values.length > 0 ? values.reduce((sum, value) => sum + value, 0) : null
}

const averageMetric = (videos: SocialVideo[], key: keyof SocialMetrics): number | null => {
  const values = videos.map(video => video.metrics[key]).filter((value): value is number => typeof value === 'number')
  return values.length > 0 ? values.reduce((sum, value) => sum + value, 0) / values.length : null
}

const cleanTitle = (value: string): string => {
  const firstLine = value.split(/\r?\n/)[0]?.replace(/(?:\s*#[\p{L}\p{N}_-]+)+\s*$/gu, '').trim() ?? ''
  if (!firstLine || firstLine.toLowerCase() === 'ohne titel') return 'Flaggenbande Video'
  return firstLine.length > 82 ? `${firstLine.slice(0, 79).trim()}…` : firstLine
}

const groupTitle = (videos: SocialVideo[]): string => {
  const preferred = videos.find(video => video.platform === 'youtube')
    ?? videos.find(video => video.title && video.title.toLowerCase() !== 'ohne titel')
    ?? videos[0]
  return cleanTitle(preferred?.title ?? 'Flaggenbande Video')
}

const normalizeContentText = (value: string): string => value
  .normalize('NFKC')
  .toLocaleLowerCase('en')
  .replace(/https?:\/\/\S+/gu, ' ')
  .replace(/#/gu, '')
  .replace(/[^\p{L}\p{N}]+/gu, ' ')
  .replace(/\s+/gu, ' ')
  .trim()

const contentSignature = (video: SocialVideo): string | null => {
  const description = normalizeContentText(video.description)
  if (description.length >= 40) return description
  const title = normalizeContentText(video.title)
  return title.length >= 24 ? title : null
}

const buildGroupKeyBySignature = (videos: SocialVideo[]): ReadonlyMap<string, string> => {
  const candidates = new Map<string, { contentIds: Set<string>; platformCounts: Map<SocialPlatform, number> }>()
  for (const video of videos) {
    const signature = contentSignature(video)
    if (!signature) continue
    const candidate = candidates.get(signature) ?? { contentIds: new Set<string>(), platformCounts: new Map<SocialPlatform, number>() }
    if (video.contentId) candidate.contentIds.add(video.contentId)
    candidate.platformCounts.set(video.platform, (candidate.platformCounts.get(video.platform) ?? 0) + 1)
    candidates.set(signature, candidate)
  }
  return new Map([...candidates.entries()]
    .filter(([, candidate]) => candidate.contentIds.size <= 1 && [...candidate.platformCounts.values()].every(count => count === 1) && candidate.platformCounts.size >= 2)
    .map(([signature, candidate]) => [signature, [...candidate.contentIds][0] ?? `exact-copy:${signature}`]))
}

interface SocialVideoGroup {
  readonly key: string
  readonly title: string
  readonly videos: SocialVideo[]
  readonly publishedAt: string | null
}

const buildVideoGroups = (videos: SocialVideo[]): SocialVideoGroup[] => {
  const groupKeysBySignature = buildGroupKeyBySignature(videos)
  const groupsByKey = new Map<string, SocialVideo[]>()

  for (const video of videos) {
    const signature = contentSignature(video)
    // Only deterministic identifiers or exact normalized copy matches may join
    // platform records. Publication time is deliberately never used as a guess.
    const key = video.contentId
      ?? (signature ? groupKeysBySignature.get(signature) : undefined)
      ?? `${video.platform}:${video.platformVideoId}`
    groupsByKey.set(key, [...(groupsByKey.get(key) ?? []), video])
  }

  return [...groupsByKey.entries()].map(([key, groupedVideos]) => ({
    key,
    videos: groupedVideos,
    title: groupTitle(groupedVideos),
    publishedAt: groupedVideos.map(video => video.publishedAt).filter((value): value is string => Boolean(value)).sort().at(-1) ?? null,
  })).sort((left, right) => String(right.publishedAt ?? '').localeCompare(String(left.publishedAt ?? '')))
}

const trustedPlatformUrl = (video: SocialVideo): string | null => {
  if (!video.url) return null
  try {
    const url = new URL(video.url)
    if (url.protocol !== 'https:') return null
    const host = url.hostname.replace(/^www\./u, '')
    const allowedHosts: Record<SocialPlatform, string[]> = {
      youtube: ['youtube.com', 'youtu.be'],
      instagram: ['instagram.com'],
      facebook: ['facebook.com', 'fb.watch'],
      tiktok: ['tiktok.com'],
    }
    return allowedHosts[video.platform].some(domain => host === domain || host.endsWith(`.${domain}`)) ? url.toString() : null
  } catch {
    return null
  }
}

const snapshotTrend = (data: SocialData, video: SocialVideo) => {
  const snapshots = data.snapshots
    .filter(snapshot => snapshot.platform === video.platform && snapshot.platformVideoId === video.platformVideoId)
    .sort((left, right) => left.capturedAt.localeCompare(right.capturedAt))
  return { snapshots, first: snapshots[0], latest: snapshots.at(-1) }
}

const retentionPoints = (video: SocialVideo): RetentionPoint[] => {
  const points = video.retention
  return Array.isArray(points)
    ? points.filter(point => Number.isFinite(point.elapsedVideoTimeRatio) && Number.isFinite(point.audienceWatchRatio))
    : []
}

function RetentionChart({ points, platform }: { readonly points: RetentionPoint[]; readonly platform: SocialPlatform }) {
  const width = 520
  const height = 160
  const padding = 18
  const maxAudience = Math.max(1, ...points.map(point => point.audienceWatchRatio))
  const coordinates = points.map(point => ({
    x: padding + Math.max(0, Math.min(1, point.elapsedVideoTimeRatio)) * (width - padding * 2),
    y: height - padding - Math.max(0, point.audienceWatchRatio) / maxAudience * (height - padding * 2),
  }))
  const path = coordinates.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(' ')

  return <div className="retention-chart">
    <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${platformLabels[platform]} Zuschauerbindung über die Videolänge`}>
      <line x1={padding} x2={width - padding} y1={height - padding} y2={height - padding} className="retention-axis" />
      <line x1={padding} x2={padding} y1={padding} y2={height - padding} className="retention-axis" />
      <path d={path} className={`retention-line ${platform}`} />
    </svg>
    <div className="retention-chart-labels"><span>Start</span><span>Videomitte</span><span>Ende</span></div>
  </div>
}

const trendDelta = (first: Numeric, latest: Numeric): string => {
  if (typeof first !== 'number' || typeof latest !== 'number') return 'Nicht verfügbar'
  const delta = latest - first
  return `${delta >= 0 ? '+' : ''}${formatNumber(delta)}`
}

export default function SocialAnalytics({ data }: { readonly data: SocialData }) {
  const [selectedPlatforms, setSelectedPlatforms] = useState<ReadonlySet<SocialPlatform>>(() => new Set(platformOrder))
  const [selectedGroupKey, setSelectedGroupKey] = useState<string | null>(null)
  const dialogRef = useRef<HTMLDialogElement>(null)
  const lastFocusedElement = useRef<HTMLElement | null>(null)

  const allGroups = useMemo(() => buildVideoGroups(data.videos), [data.videos])
  const visibleVideos = useMemo(
    () => data.videos.filter(entry => selectedPlatforms.has(entry.platform)),
    [data.videos, selectedPlatforms],
  )
  const groups = useMemo<SocialVideoGroup[]>(() => allGroups
    .map(group => ({ ...group, videos: group.videos.filter(video => selectedPlatforms.has(video.platform)) }))
    .filter(group => group.videos.length > 0), [allGroups, selectedPlatforms])
  const selectedGroup = groups.find(group => group.key === selectedGroupKey) ?? null
  const allSelected = selectedPlatforms.size === platformOrder.length

  const selectAllPlatforms = () => setSelectedPlatforms(new Set(platformOrder))
  const togglePlatform = (platform: SocialPlatform) => {
    if (allSelected) {
      setSelectedPlatforms(new Set([platform]))
      return
    }
    const next = new Set(selectedPlatforms)
    if (next.has(platform)) {
      if (next.size === 1) return
      next.delete(platform)
    } else {
      next.add(platform)
    }
    setSelectedPlatforms(next)
  }

  const openDetails = (group: SocialVideoGroup) => {
    lastFocusedElement.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setSelectedGroupKey(group.key)
    window.requestAnimationFrame(() => {
      if (dialogRef.current && !dialogRef.current.open) dialogRef.current.showModal()
    })
  }

  const closeDetails = () => dialogRef.current?.close()
  const handleDialogClose = () => {
    setSelectedGroupKey(null)
    lastFocusedElement.current?.focus()
  }

  const coverage = (key: keyof SocialMetrics) => `${visibleVideos.filter(video => video.metrics[key] !== null).length}/${visibleVideos.length}`

  return <section className="social-analytics" aria-label="Auswertung der sozialen Medien">
    <div className="social-heading"><h2>Veröffentlichte Videos</h2></div>

    <div className="platform-comparison-filter" role="group" aria-label="Plattformen vergleichen">
      <button type="button" className={allSelected ? 'active' : ''} aria-pressed={allSelected} onClick={selectAllPlatforms}>Alle vergleichen</button>
      {platformOrder.map(platform => <button
        type="button"
        key={platform}
        className={`platform-filter-chip ${platform} ${selectedPlatforms.has(platform) ? 'active' : ''}`}
        aria-pressed={selectedPlatforms.has(platform)}
        onClick={() => togglePlatform(platform)}
      >{platformLabels[platform]}</button>)}
    </div>

    <div className="social-kpis social-kpis-focused">
      <article><span>Aufrufe <small>{coverage('views')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'views'))}</strong></article>
      <article><span>Reichweite <small>{coverage('reach')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'reach'))}</strong></article>
      <article><span>Gefällt mir <small>{coverage('likes')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'likes'))}</strong></article>
      <article><span>Kommentare <small>{coverage('comments')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'comments'))}</strong></article>
      <article><span>Geteilt <small>{coverage('shares')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'shares'))}</strong></article>
      <article><span>Wiedergabezeit <small>{coverage('watchTimeMinutes')} Videos</small></span><strong>{formatMetric(metricValue(visibleVideos, 'watchTimeMinutes'), ' min')}</strong></article>
    </div>

    <div className="social-list-heading"><strong>Leistung der Inhalte</strong><span>{groups.length} Inhalte · {visibleVideos.length} Plattformveröffentlichungen</span></div>
    {groups.length > 0 ? <div className="social-video-grid">{groups.map(group => <article
      className="social-video-card"
      key={group.key}
      onClick={event => {
        if (!(event.target instanceof Element) || !event.target.closest('a')) openDetails(group)
      }}
    >
      <div className="social-video-main">
        <button type="button" className="social-video-title-button" onClick={event => { event.stopPropagation(); openDetails(group) }}>
          <span className="video-card-kicker">Veröffentlicht {formatDate(group.publishedAt)}</span>
          <span className="social-video-title">{group.title}</span>
        </button>
        <div className="video-platform-links" aria-label="Externe Videolinks">{group.videos.map(video => {
          const url = trustedPlatformUrl(video)
          return url
            ? <a key={`${video.platform}:${video.platformVideoId}`} className={`platform-pill ${video.platform}`} href={url} target="_blank" rel="noreferrer" onClick={event => event.stopPropagation()}>{platformLabels[video.platform]} ↗</a>
            : <span key={`${video.platform}:${video.platformVideoId}`} className={`platform-pill ${video.platform} unavailable`} title="Kein bestätigter externer Link verfügbar">{platformLabels[video.platform]}</span>
        })}</div>
      </div>
      <dl className="social-video-metrics">
        <div><dt>Aufrufe</dt><dd>{formatNumber(metricValue(group.videos, 'views'))}</dd></div>
        <div><dt>Gefällt mir</dt><dd>{formatNumber(metricValue(group.videos, 'likes'))}</dd></div>
        <div><dt>Kommentare</dt><dd>{formatNumber(metricValue(group.videos, 'comments'))}</dd></div>
        <div><dt>Geteilt</dt><dd>{formatNumber(metricValue(group.videos, 'shares'))}</dd></div>
        <div><dt>Ø Wiedergabe</dt><dd>{formatMetric(averageMetric(group.videos, 'averageViewDurationSeconds'), ' s')}</dd></div>
      </dl>
    </article>)}</div> : <div className="content-empty"><span aria-hidden="true">○</span><div><strong>Noch keine veröffentlichten Videos</strong><p>Nach dem nächsten Plattformabgleich erscheinen hier ausschließlich bestätigte Veröffentlichungen.</p></div></div>}

    <dialog ref={dialogRef} className="social-video-dialog" aria-labelledby="social-video-dialog-title" onClose={handleDialogClose} onClick={event => {
      if (event.target === dialogRef.current) closeDetails()
    }}>
      {selectedGroup ? <div className="social-video-dialog-content">
        <header>
          <div><span className="eyebrow">VIDEOEINZELHEITEN</span><h2 id="social-video-dialog-title">{selectedGroup.title}</h2><p>{selectedGroup.videos.length} ausgewählte Plattformveröffentlichungen im direkten Vergleich.</p></div>
          <button type="button" className="dialog-close" onClick={closeDetails} aria-label="Video-Details schließen">×</button>
        </header>
        <div className="platform-detail-grid">{selectedGroup.videos.map(video => {
          const url = trustedPlatformUrl(video)
          const history = snapshotTrend(data, video)
          const retention = retentionPoints(video)
          return <article className="platform-detail-card" key={`${video.platform}:${video.platformVideoId}`}>
            <div className="platform-detail-heading">
              <span className={`platform-pill ${video.platform}`}>{platformLabels[video.platform]}</span>
              {url ? <a href={url} target="_blank" rel="noreferrer">Auf Plattform öffnen ↗</a> : <span className="external-link-unavailable">Externer Link nicht verfügbar</span>}
            </div>
            <dl className="platform-detail-meta">
              <div><dt>Veröffentlicht</dt><dd>{formatDate(video.publishedAt)}</dd></div>
              <div><dt>Videolänge</dt><dd>{formatMetric(video.durationSeconds, ' s')}</dd></div>
              <div><dt>Status</dt><dd>{publicationStatusLabel(video.status) || 'Nicht verfügbar'}</dd></div>
            </dl>
            <h3>Verfügbare Plattformwerte</h3>
            <dl className="platform-metric-grid">{metricLabels.map(metric => <div key={metric.key}><dt>{metric.label}</dt><dd>{formatMetric(video.metrics[metric.key], metric.unit)}</dd></div>)}</dl>
            <section className="retention-availability" aria-label={`${platformLabels[video.platform]} Nutzerbindung`}>
              <h3>Nutzerbindung</h3>
              {retention.length > 1
                ? <><RetentionChart points={retention} platform={video.platform} /><p>{retention.length} echte Messpunkte aus der Plattform-API. Keine Werte wurden ergänzt oder geschätzt. {video.retentionCheckStatus === 'error' ? `Der letzte Abruf am ${formatDate(video.retentionCheckedAt ?? null)} ist fehlgeschlagen; der letzte bekannte Verlauf bleibt sichtbar.` : `Letzte Prüfung: ${formatDate(video.retentionCheckedAt ?? null)}.`}</p></>
                : typeof video.metrics.averageViewPercentage === 'number'
                ? <p>Die API liefert aktuell nur den Durchschnitt von <strong>{formatMetric(video.metrics.averageViewPercentage, ' %')}</strong>. Eine zeitbasierte Kurve zur Nutzerbindung ist nicht verfügbar.</p>
                : <p><strong>Nicht verfügbar.</strong> Die Plattform-API liefert für dieses Video aktuell weder eine Kurve zur Nutzerbindung noch einen verlässlichen Durchschnitt.</p>}
            </section>
            <section className="snapshot-summary" aria-label={`${platformLabels[video.platform]} Messverlauf`}>
              <h3>Messverlauf</h3>
              {history.snapshots.length > 1 && history.first && history.latest ? <>
                <p>{history.snapshots.length} Messpunkte · {formatDate(history.first.capturedAt)} bis {formatDate(history.latest.capturedAt)}</p>
                <dl><div><dt>Aufrufe</dt><dd>{trendDelta(history.first.metrics.views, history.latest.metrics.views)}</dd></div><div><dt>Gefällt mir</dt><dd>{trendDelta(history.first.metrics.likes, history.latest.metrics.likes)}</dd></div><div><dt>Kommentare</dt><dd>{trendDelta(history.first.metrics.comments, history.latest.metrics.comments)}</dd></div><div><dt>Geteilt</dt><dd>{trendDelta(history.first.metrics.shares, history.latest.metrics.shares)}</dd></div></dl>
              </> : <p>{history.snapshots.length === 1 ? `Bislang ein Messpunkt vom ${formatDate(history.snapshots[0].capturedAt)}; ein Trend ist noch nicht belastbar.` : 'Noch keine historischen Messpunkte verfügbar.'}</p>}
            </section>
          </article>
        })}</div>
      </div> : null}
    </dialog>

  </section>
}
