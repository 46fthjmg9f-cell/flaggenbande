import type { DailyMetric, DashboardData, Numeric } from './types'

const formatNumber = (value: Numeric) => value === null || value === undefined
  ? '—'
  : new Intl.NumberFormat('de-DE', { maximumFractionDigits: 1 }).format(value)

const formatMoney = (value: Numeric) => value === null || value === undefined
  ? '—'
  : new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(value)

const sumPresent = (rows: DailyMetric[], key: keyof DailyMetric): number | null => {
  const values = rows.map(row => row[key]).filter((value): value is number => typeof value === 'number')
  return values.length > 0 ? values.reduce((sum, value) => sum + value, 0) : null
}

interface FinancePageProps {
  readonly data: DashboardData
  readonly rows: DailyMetric[]
  readonly refreshing: boolean
  readonly onRefresh: () => void
}

export default function FinancePage({ data, rows, refreshing, onRefresh }: FinancePageProps) {
  const salesUnits = sumPresent(rows, 'purchases')
  const refunds = sumPresent(rows, 'refunds')
  const proceeds = sumPresent(rows, 'proceeds')
  const revenue = sumPresent(rows, 'revenue')
  const financeAvailable = data.finance !== null && data.finance !== undefined

  return <section id="finance-view" className="dashboard-view" role="tabpanel" aria-labelledby="finance-tab" tabIndex={0}>
    <header className="hero section-hero">
      <div>
        <span className="eyebrow">FLAGGENBANDE · FINANZEN</span>
        <h1>Einnahmen und Kosten.</h1>
        <p>App-Store-Umsätze, Verkäufe und Rückerstattungen sind von Produkt- und Social-Kennzahlen getrennt. Fehlende Finanzquellen bleiben ausdrücklich als nicht verfügbar markiert.</p>
      </div>
      <div className="sync-controls">
        <div className={`sync-state ${financeAvailable ? 'ok' : 'partial'}`}><span className="pulse" />{financeAvailable ? `Apple-Finanzreport · ${data.finance?.period}` : 'Monatlicher Finanzreport noch nicht verfügbar'}</div>
        <button className="refresh" onClick={onRefresh} disabled={refreshing}>{refreshing ? 'Wird aktualisiert …' : 'Finanzdaten aktualisieren'}</button>
        <small>Keine Schätzwerte; ausschließlich bestätigte Quellen.</small>
      </div>
    </header>

    <section className="kpis finance-kpis" aria-label="Finanzkennzahlen">
      <article className="kpi-card green"><p>Apple Proceeds · Monatsreport</p><strong>{formatMoney(data.finance?.proceeds ?? null)}</strong><span>{data.finance?.period ?? 'Noch nicht verfügbar'}</span></article>
      <article className="kpi-card green"><p>Proceeds · verfügbare Historie</p><strong>{formatMoney(proceeds)}</strong><span>App Store Connect Sales</span></article>
      <article className="kpi-card blue"><p>Umsatz · verfügbare Historie</p><strong>{formatMoney(revenue)}</strong><span>nur wenn von Apple geliefert</span></article>
      <article className="kpi-card purple"><p>Sales Units</p><strong>{formatNumber(salesUnits)}</strong><span>keine In-App-Käufe</span></article>
      <article className="kpi-card red"><p>Rückerstattungen</p><strong>{formatNumber(refunds)}</strong><span>bestätigte Einheiten</span></article>
    </section>

    <section className="finance-grid">
      <article className="panel finance-panel">
        <div className="panel-heading"><div><span>QUELLEN</span><h2>Finanzdaten-Abdeckung</h2></div></div>
        <ul className="finance-source-list">
          <li><div><strong>App Store Connect Sales</strong><small>Tägliche Verkäufe, Proceeds und Refunds</small></div><span className="status-badge ready">Verbunden</span></li>
          <li><div><strong>Apple Finance Report</strong><small>Monatliche bestätigte Auszahlung</small></div><span className={`status-badge ${financeAvailable ? 'ready' : 'planned'}`}>{financeAvailable ? 'Verfügbar' : 'Ausstehend'}</span></li>
          <li><div><strong>Social-Plattform-Umsatz</strong><small>YouTube, Instagram, Facebook und TikTok</small></div><span className="status-badge planned">Noch nicht verfügbar</span></li>
          <li><div><strong>Produktionskosten</strong><small>Voice, Rendering und externe Dienste</small></div><span className="status-badge planned">Noch nicht erfasst</span></li>
        </ul>
      </article>
      <article className="panel finance-panel">
        <div className="panel-heading"><div><span>GRUNDSATZ</span><h2>Keine irreführenden Nullwerte</h2></div></div>
        <div className="finance-explanation">
          <strong>„—“ bedeutet: Quelle liefert noch keinen belastbaren Wert.</strong>
          <p>Eine echte Null wird erst angezeigt, wenn der Provider für den gewählten Zeitraum tatsächlich den Wert 0 geliefert hat.</p>
        </div>
      </article>
    </section>
    <footer>Flaggenbande Finanzen · Öffentliche Ansicht ohne Kontodaten, Belegdokumente oder Zugangsschlüssel.</footer>
  </section>
}
