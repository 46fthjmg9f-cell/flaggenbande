import SocialAnalytics from './SocialAnalytics'
import type { SocialData } from './types'

interface SocialStatsPageProps {
  readonly data: SocialData
  readonly generatedAt: string | null
  readonly refreshing: boolean
  readonly onRefresh: () => void
}

const formatTimestamp = (value: string | null) => value
  ? new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : 'Warte auf den ersten Plattformabgleich'

export default function SocialStatsPage({ data, generatedAt, refreshing, onRefresh }: SocialStatsPageProps) {
  const platformStates = Object.values(data.platforms).map(platform => platform.status)
  const syncStatus = platformStates.includes('error')
    ? 'error'
    : platformStates.every(status => status === 'available')
      ? 'ok'
      : 'partial'

  return <section id="social-stats-view" className="dashboard-view" role="tabpanel" aria-labelledby="social-stats-tab" tabIndex={0}>
    <header className="compact-page-header">
      <div><h1>Stats</h1><span className={`compact-sync ${syncStatus}`}>{formatTimestamp(data.syncedAt ?? generatedAt)}</span></div>
      <button onClick={onRefresh} disabled={refreshing} aria-label="Plattformdaten aktualisieren">↻</button>
    </header>
    <SocialAnalytics data={data} />
  </section>
}
