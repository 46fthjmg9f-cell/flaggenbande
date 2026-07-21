import { useMemo, useState } from 'react'
import type { Numeric, SocialData, SocialMetrics, SocialPlatform, SocialVideo } from './types'

const platformLabels: Record<SocialPlatform, string> = {
  youtube: 'YouTube',
  instagram: 'Instagram',
  facebook: 'Facebook',
  tiktok: 'TikTok',
}

const formatNumber = (value: Numeric) => value === null || value === undefined
  ? '—'
  : new Intl.NumberFormat('de-DE', { maximumFractionDigits: 1, notation: value >= 10000 ? 'compact' : 'standard' }).format(value)

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '—'

const isStale = (value: string | null) => value
  ? Date.now() - new Date(value).valueOf() > 2 * 60 * 60 * 1000
  : true

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
  .replace(/#[\p{L}\p{N}_-]+/gu, ' ')
  .replace(/[^\p{L}\p{N}]+/gu, ' ')
  .replace(/\s+/gu, ' ')
  .trim()

const contentSignature = (video: SocialVideo): string | null => {
  const description = normalizeContentText(video.description)
  if (description.length >= 40) return description
  const title = normalizeContentText(video.title)
  return title.length >= 24 ? title : null
}

const buildContentIdBySignature = (videos: SocialVideo[]): ReadonlyMap<string, string> => {
  const candidates = new Map<string, Set<string>>()
  for (const video of videos) {
    if (!video.contentId) continue
    const signature = contentSignature(video)
    if (!signature) continue
    const ids = candidates.get(signature) ?? new Set<string>()
    ids.add(video.contentId)
    candidates.set(signature, ids)
  }
  return new Map([...candidates.entries()]
    .filter(([, ids]) => ids.size === 1)
    .map(([signature, ids]) => [signature, [...ids][0]]))
}

interface SocialVideoGroup {
  readonly key: string
  readonly title: string
  readonly videos: SocialVideo[]
  readonly publishedAt: string | null
}

export default function SocialAnalytics({ data }: { readonly data: SocialData }) {
  const [platform, setPlatform] = useState<'all' | SocialPlatform>('all')

  const visibleVideos = useMemo(
    () => data.videos.filter(entry => platform === 'all' || entry.platform === platform),
    [data.videos, platform],
  )

  const groups = useMemo<SocialVideoGroup[]>(() => {
    // Direct platform APIs do not always expose our internal content ID. An exact,
    // normalized description match links those records without guessing by time.
    const contentIdBySignature = buildContentIdBySignature(data.videos)
    const grouped = new Map<string, SocialVideo[]>()
    for (const video of visibleVideos) {
      const signature = contentSignature(video)
      const key = video.contentId
        ?? (signature ? contentIdBySignature.get(signature) : undefined)
        ?? `${video.platform}:${video.platformVideoId}`
      grouped.set(key, [...(grouped.get(key) ?? []), video])
    }
    return [...grouped.entries()].map(([key, videos]) => ({
      key,
      videos,
      title: groupTitle(videos),
      publishedAt: videos.map(video => video.publishedAt).filter((value): value is string => Boolean(value)).sort().at(-1) ?? null,
    })).sort((left, right) => String(right.publishedAt ?? '').localeCompare(String(left.publishedAt ?? '')))
  }, [data.videos, visibleVideos])

  const exportJson = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }))
    const link = document.createElement('a')
    link.href = url
    link.download = 'flaggenbande-social-stats.json'
    link.click()
    URL.revokeObjectURL(url)
  }

  const coverage = (key: keyof SocialMetrics) => `${visibleVideos.filter(video => video.metrics[key] !== null).length}/${visibleVideos.length}`

  return <section className="social-analytics" aria-label="Social Analytics">
    <div className="social-heading">
      <div><span className="eyebrow">PERFORMANCE</span><h2>Veröffentlichte Videos</h2><p>Ein Video erscheint nur einmal; seine Plattformen werden gemeinsam dargestellt.</p></div>
      <div className="social-actions">
        <label>Plattform<select value={platform} onChange={event => setPlatform(event.target.value as 'all' | SocialPlatform)}><option value="all">Alle Plattformen</option>{Object.entries(platformLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <button type="button" onClick={exportJson}>JSON exportieren</button>
      </div>
    </div>

    <div className="social-kpis social-kpis-focused">
      <article><span>Views <small>{coverage('views')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'views'))}</strong></article>
      <article><span>Reach <small>{coverage('reach')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'reach'))}</strong></article>
      <article><span>Likes <small>{coverage('likes')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'likes'))}</strong></article>
      <article><span>Kommentare <small>{coverage('comments')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'comments'))}</strong></article>
      <article><span>Shares <small>{coverage('shares')} Videos</small></span><strong>{formatNumber(metricValue(visibleVideos, 'shares'))}</strong></article>
      <article><span>Watchtime <small>{coverage('watchTimeMinutes')} Videos</small></span><strong>{metricValue(visibleVideos, 'watchTimeMinutes') === null ? '—' : `${formatNumber(metricValue(visibleVideos, 'watchTimeMinutes'))} min`}</strong></article>
    </div>

    <div className="social-list-heading"><strong>Content-Performance</strong><span>{groups.length} Inhalte · {visibleVideos.length} Plattformveröffentlichungen</span></div>
    {groups.length > 0 ? <div className="social-video-grid">{groups.map(group => <article className="social-video-card" key={group.key}>
      <div className="social-video-main">
        <div>
          <span className="video-card-kicker">Veröffentlicht {formatDate(group.publishedAt)}</span>
          <h3>{group.title}</h3>
        </div>
        <div className="video-platform-links">{group.videos.map(video => video.url
          ? <a key={`${video.platform}:${video.platformVideoId}`} className={`platform-pill ${video.platform}`} href={video.url} target="_blank" rel="noreferrer">{platformLabels[video.platform]}</a>
          : <span key={`${video.platform}:${video.platformVideoId}`} className={`platform-pill ${video.platform}`}>{platformLabels[video.platform]}</span>)}</div>
      </div>
      <dl className="social-video-metrics">
        <div><dt>Views</dt><dd>{formatNumber(metricValue(group.videos, 'views'))}</dd></div>
        <div><dt>Likes</dt><dd>{formatNumber(metricValue(group.videos, 'likes'))}</dd></div>
        <div><dt>Kommentare</dt><dd>{formatNumber(metricValue(group.videos, 'comments'))}</dd></div>
        <div><dt>Shares</dt><dd>{formatNumber(metricValue(group.videos, 'shares'))}</dd></div>
        <div><dt>Ø Wiedergabe</dt><dd>{averageMetric(group.videos, 'averageViewDurationSeconds') === null ? '—' : `${formatNumber(averageMetric(group.videos, 'averageViewDurationSeconds'))} s`}</dd></div>
      </dl>
    </article>)}</div> : <div className="content-empty"><span aria-hidden="true">○</span><div><strong>Noch keine veröffentlichten Videos</strong><p>Nach dem nächsten Plattform-Sync erscheinen hier ausschließlich bestätigte Veröffentlichungen.</p></div></div>}

    <details className="connection-details">
      <summary>Verbindungen und Datenstand</summary>
      <div className="platform-status-grid">
        {(Object.entries(data.platforms) as Array<[SocialPlatform, SocialData['platforms'][SocialPlatform]]>).map(([name, state]) => <article key={name} className={`platform-status ${state.status}`}>
          <div><b>{platformLabels[name]}</b><span className="platform-state-dot" /></div>
          <strong>{state.videoCount} veröffentlicht</strong>
          <small title={state.reason ?? state.accountName ?? undefined}>{state.reason ?? state.accountName ?? 'Verbindung vorbereitet'}</small>
          <em className={isStale(state.completedAt) ? 'stale' : ''}>{state.completedAt ? `${isStale(state.completedAt) ? 'Veraltet · ' : ''}Sync ${formatDate(state.completedAt)}` : 'Noch kein erfolgreicher Sync'}</em>
        </article>)}
      </div>
    </details>
  </section>
}
