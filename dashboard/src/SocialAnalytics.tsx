import { useMemo, useState } from 'react'
import type { Numeric, SocialData, SocialPlatform, SocialUpload, SocialVideo } from './types'

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

const publishedAsUpload = (entry: SocialVideo): SocialUpload => ({
  platform: entry.platform,
  platformVideoId: entry.platformVideoId,
  contentId: entry.contentId,
  title: entry.title,
  description: entry.description,
  uploadedAt: entry.publishedAt,
  publishedAt: entry.publishedAt,
  scheduledAt: null,
  url: entry.url,
  thumbnailUrl: entry.thumbnailUrl,
  status: entry.status,
  privacyStatus: entry.status,
  uploadStatus: 'processed',
  durationSeconds: entry.durationSeconds,
})

export default function SocialAnalytics({ data }: { readonly data: SocialData }) {
  const [platform, setPlatform] = useState<'all' | SocialPlatform>('all')
  const [view, setView] = useState<'uploads' | 'published'>('uploads')
  const publishedByKey = useMemo(() => new Map(data.videos.map(entry => [
    `${entry.platform}:${entry.platformVideoId}`,
    entry,
  ])), [data.videos])
  const uploads = useMemo(() => {
    const byKey = new Map((data.uploads ?? []).map(entry => [`${entry.platform}:${entry.platformVideoId}`, entry]))
    for (const entry of data.videos) {
      const key = `${entry.platform}:${entry.platformVideoId}`
      if (!byKey.has(key)) byKey.set(key, publishedAsUpload(entry))
    }
    return [...byKey.values()].sort((left, right) => String(right.uploadedAt ?? right.publishedAt ?? '')
      .localeCompare(String(left.uploadedAt ?? left.publishedAt ?? '')))
  }, [data.uploads, data.videos])
  const visibleUploads = useMemo(
    () => uploads.filter(entry => platform === 'all' || entry.platform === platform),
    [uploads, platform],
  )
  const visibleVideos = useMemo(
    () => data.videos.filter(entry => platform === 'all' || entry.platform === platform),
    [data.videos, platform],
  )

  const exportJson = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }))
    const link = document.createElement('a')
    link.href = url
    link.download = 'flaggenbande-platform-data.json'
    link.click()
    URL.revokeObjectURL(url)
  }

  return <section className="social-analytics" aria-label="Plattform-Analytics">
    <div className="social-heading">
      <div><span className="eyebrow">SOCIAL · SERVER-SIDE SYNC</span><h2>Video-Performance auf allen Plattformen</h2><p>Vereinheitlichte Kennzahlen; fehlende API-Felder bleiben transparent leer.</p></div>
      <div className="social-actions">
        <div className="social-view-toggle" role="group" aria-label="Videostatus">
          <button className={view === 'uploads' ? 'active' : ''} onClick={() => setView('uploads')}>Alle Uploads</button>
          <button className={view === 'published' ? 'active' : ''} onClick={() => setView('published')}>Veröffentlicht & analysierbar</button>
        </div>
        <label>Plattform<select value={platform} onChange={event => setPlatform(event.target.value as 'all' | SocialPlatform)}><option value="all">Alle Plattformen</option>{Object.entries(platformLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <button onClick={exportJson}>JSON exportieren</button>
      </div>
    </div>

    <div className="platform-status-grid">
      {(Object.entries(data.platforms) as Array<[SocialPlatform, SocialData['platforms'][SocialPlatform]]>).map(([name, state]) => <article key={name} className={`platform-status ${state.status}`}>
        <div><b>{platformLabels[name]}</b><span className="platform-state-dot" /></div>
        <strong>{state.uploadCount ?? uploads.filter(entry => entry.platform === name).length} Uploads · {state.videoCount} veröffentlicht</strong>
        <small title={state.reason ?? state.accountName ?? undefined}>{state.reason ?? state.accountName ?? 'Verbindung vorbereitet'}</small>
        <em className={isStale(state.completedAt) ? 'stale' : ''}>{state.completedAt ? `${isStale(state.completedAt) ? 'Veraltet · ' : ''}Sync ${formatDate(state.completedAt)}` : 'Noch kein erfolgreicher Sync'}</em>
      </article>)}
    </div>

    <div className="social-kpis">
      <article><span>Views</span><strong>{formatNumber(data.totals.views)}</strong></article>
      <article><span>Likes</span><strong>{formatNumber(data.totals.likes)}</strong></article>
      <article><span>Kommentare</span><strong>{formatNumber(data.totals.comments)}</strong></article>
      <article><span>Shares</span><strong>{formatNumber(data.totals.shares)}</strong></article>
      <article><span>Watchtime</span><strong>{formatNumber(data.totals.watchTimeMinutes)} min</strong></article>
    </div>

    <div className="social-list-heading"><strong>{view === 'uploads' ? 'Upload-Inventar' : 'Veröffentlichte Videos'}</strong><span>{view === 'uploads' ? `${visibleUploads.length} Uploads einschließlich privat, geplant und nicht gelistet` : `${visibleVideos.length} Videos mit auswertbarem Veröffentlichungsstatus`}</span></div>
    <div className="social-table-wrap">
      {view === 'uploads' ? <table className="social-table upload-table">
        <thead><tr><th>Plattform</th><th>Video</th><th>Status</th><th>Hochgeladen</th><th>Geplant</th><th>Veröffentlicht</th><th>Auswertung</th></tr></thead>
        <tbody>{visibleUploads.length ? visibleUploads.map(upload => {
          const published = publishedByKey.get(`${upload.platform}:${upload.platformVideoId}`)
          return <tr key={`${upload.platform}:${upload.platformVideoId}`}>
            <td><span className={`platform-pill ${upload.platform}`}>{platformLabels[upload.platform]}</span></td>
            <td>{upload.url ? <a href={upload.url} target="_blank" rel="noreferrer">{upload.title}</a> : upload.title}<small>{upload.contentId ?? upload.platformVideoId}</small></td>
            <td><span className={`upload-state ${upload.status}`}>{upload.status.replaceAll('_', ' ')}</span></td>
            <td>{formatDate(upload.uploadedAt)}</td>
            <td>{formatDate(upload.scheduledAt)}</td>
            <td>{formatDate(upload.publishedAt)}</td>
            <td>{published ? `${formatNumber(published.metrics.views)} Views` : 'Noch nicht analysierbar'}</td>
          </tr>
        }) : <tr><td colSpan={7} className="empty-social">Noch kein vollständiges Upload-Inventar synchronisiert. Veröffentlichte Videos bleiben unten verfügbar.</td></tr>}</tbody>
      </table> :
      <table className="social-table">
        <thead><tr><th>Plattform</th><th>Video</th><th>Status</th><th>Veröffentlicht</th><th>Views</th><th>Likes</th><th>Kommentare</th><th>Shares</th><th>Ø Wiedergabe</th></tr></thead>
        <tbody>{visibleVideos.length ? visibleVideos.map(video => <tr key={`${video.platform}:${video.platformVideoId}`}>
          <td><span className={`platform-pill ${video.platform}`}>{platformLabels[video.platform]}</span></td>
          <td>{video.url ? <a href={video.url} target="_blank" rel="noreferrer">{video.title}</a> : video.title}<small>{video.contentId ?? video.platformVideoId}</small></td>
          <td>{video.status}</td>
          <td>{formatDate(video.publishedAt)}</td>
          <td>{formatNumber(video.metrics.views)}</td>
          <td>{formatNumber(video.metrics.likes)}</td>
          <td>{formatNumber(video.metrics.comments)}</td>
          <td>{formatNumber(video.metrics.shares)}</td>
          <td>{video.metrics.averageViewDurationSeconds === null ? '—' : `${formatNumber(video.metrics.averageViewDurationSeconds)} s`}</td>
        </tr>) : <tr><td colSpan={9} className="empty-social">Noch keine Plattformdaten synchronisiert.</td></tr>}</tbody>
      </table>}
    </div>
  </section>
}
