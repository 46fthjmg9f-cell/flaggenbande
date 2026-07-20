import { useMemo, useState } from 'react'
import type { Numeric, SocialData, SocialPlatform } from './types'

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

export default function SocialAnalytics({ data }: { readonly data: SocialData }) {
  const [platform, setPlatform] = useState<'all' | SocialPlatform>('all')
  const visibleVideos = useMemo(
    () => data.videos.filter(video => platform === 'all' || video.platform === platform),
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
        <label>Plattform<select value={platform} onChange={event => setPlatform(event.target.value as 'all' | SocialPlatform)}><option value="all">Alle Plattformen</option>{Object.entries(platformLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <button onClick={exportJson}>JSON exportieren</button>
      </div>
    </div>

    <div className="platform-status-grid">
      {(Object.entries(data.platforms) as Array<[SocialPlatform, SocialData['platforms'][SocialPlatform]]>).map(([name, state]) => <article key={name} className={`platform-status ${state.status}`}>
        <div><b>{platformLabels[name]}</b><span className="platform-state-dot" /></div>
        <strong>{state.videoCount} Videos</strong>
        <small>{state.accountName ?? state.reason ?? 'Verbindung vorbereitet'}</small>
        <em>{state.completedAt ? `Sync ${formatDate(state.completedAt)}` : state.status.replaceAll('_', ' ')}</em>
      </article>)}
    </div>

    <div className="social-kpis">
      <article><span>Views</span><strong>{formatNumber(data.totals.views)}</strong></article>
      <article><span>Likes</span><strong>{formatNumber(data.totals.likes)}</strong></article>
      <article><span>Kommentare</span><strong>{formatNumber(data.totals.comments)}</strong></article>
      <article><span>Shares</span><strong>{formatNumber(data.totals.shares)}</strong></article>
      <article><span>Watchtime</span><strong>{formatNumber(data.totals.watchTimeMinutes)} min</strong></article>
    </div>

    <div className="social-table-wrap">
      <table className="social-table">
        <thead><tr><th>Plattform</th><th>Video</th><th>Status</th><th>Veröffentlicht</th><th>Views</th><th>Likes</th><th>Kommentare</th><th>Shares</th><th>Ø Wiedergabe</th></tr></thead>
        <tbody>{visibleVideos.length ? visibleVideos.map(video => <tr key={`${video.platform}:${video.platformVideoId}`}>
          <td><span className={`platform-pill ${video.platform}`}>{platformLabels[video.platform]}</span></td>
          <td>{video.url ? <a href={video.url} target="_blank" rel="noreferrer">{video.title}</a> : video.title}<small>{video.platformVideoId}</small></td>
          <td>{video.status}</td>
          <td>{formatDate(video.publishedAt)}</td>
          <td>{formatNumber(video.metrics.views)}</td>
          <td>{formatNumber(video.metrics.likes)}</td>
          <td>{formatNumber(video.metrics.comments)}</td>
          <td>{formatNumber(video.metrics.shares)}</td>
          <td>{video.metrics.averageViewDurationSeconds === null ? '—' : `${formatNumber(video.metrics.averageViewDurationSeconds)} s`}</td>
        </tr>) : <tr><td colSpan={9} className="empty-social">Noch keine Plattformdaten synchronisiert.</td></tr>}</tbody>
      </table>
    </div>
  </section>
}
