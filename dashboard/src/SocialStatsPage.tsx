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
  : 'Warte auf ersten Social-Sync'

export default function SocialStatsPage({ data, generatedAt, refreshing, onRefresh }: SocialStatsPageProps) {
  return <section id="social-stats-view" className="dashboard-view" role="tabpanel" aria-labelledby="social-stats-tab" tabIndex={0}>
    <header className="hero section-hero">
      <div>
        <span className="eyebrow">FLAGGENBANDE · SOCIAL ANALYTICS</span>
        <h1>Reichweite und Wirkung.</h1>
        <p>Nur veröffentlichte Inhalte und tatsächlich verfügbare Plattformwerte. Produktion, App-Entwicklung und Finanzen bleiben bewusst außerhalb dieser Ansicht.</p>
      </div>
      <div className="sync-controls">
        <div className="sync-state ok"><span className="pulse" />{formatTimestamp(data.syncedAt ?? generatedAt)}</div>
        <button className="refresh" onClick={onRefresh} disabled={refreshing}>{refreshing ? 'Wird aktualisiert …' : 'Social-Daten aktualisieren'}</button>
        <small>Automatischer Datenabruf stündlich zur Minute 17.</small>
      </div>
    </header>
    <SocialAnalytics data={data} />
    <footer>Flaggenbande Social Analytics · Nicht verfügbare Kennzahlen werden nicht als Nullwerte ausgegeben.</footer>
  </section>
}
