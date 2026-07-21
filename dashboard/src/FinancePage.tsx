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

const metricAvailability = (value: Numeric, availableLabel: string) => value === null || value === undefined
  ? 'Daten nicht verfügbar'
  : availableLabel

const formatReportDate = (value: string | null | undefined) => value
  ? new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium' }).format(new Date(`${value}T00:00:00Z`))
  : 'Datum nicht verfügbar'

interface FinancePageProps {
  readonly data: DashboardData
  readonly rows: DailyMetric[]
  readonly refreshing: boolean
  readonly onRefresh: () => void
}

export default function FinancePage({ data, rows, refreshing, onRefresh }: FinancePageProps) {
  const classifiedDailyRowsAvailable = rows.some(row => row.appUnits !== undefined || row.inAppPurchaseUnits !== undefined)
  const appUnits = data.sales?.appUnits ?? (classifiedDailyRowsAvailable ? sumPresent(rows, 'appUnits') : null)
  const inAppPurchaseUnits = data.sales?.inAppPurchaseUnits ?? (classifiedDailyRowsAvailable ? sumPresent(rows, 'inAppPurchaseUnits') : null)
  const refunds = data.sales?.refunds ?? (data.schemaVersion >= 3 ? sumPresent(rows, 'refunds') : null)
  const proceeds = data.schemaVersion >= 3 ? sumPresent(rows, 'proceeds') : null
  const revenue = sumPresent(rows, 'revenue')
  const financeAvailable = data.finance !== null && data.finance !== undefined
  const salesAvailable = data.availability['Sales & Trends']?.available === true
  const classificationStatus = data.sales?.classificationStatus ?? 'unavailable'
  const unknownIdentifiers = data.sales?.unknownProductTypeIdentifiers ?? []

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
      <article className="kpi-card purple"><p>App-Einheiten · Tagesreport</p><strong>{formatNumber(appUnits)}</strong><span>{appUnits === null ? metricAvailability(appUnits, '') : formatReportDate(data.sales?.reportDate)}</span></article>
      <article className="kpi-card purple"><p>In-App-Käufe · Tagesreport</p><strong>{formatNumber(inAppPurchaseUnits)}</strong><span>{inAppPurchaseUnits === null ? metricAvailability(inAppPurchaseUnits, '') : formatReportDate(data.sales?.reportDate)}</span></article>
      <article className="kpi-card red"><p>Rückerstattungen</p><strong>{formatNumber(refunds)}</strong><span>{metricAvailability(refunds, 'bestätigte Einheiten')}</span></article>
    </section>

    <section className="finance-grid">
      <article className="panel finance-panel">
        <div className="panel-heading"><div><span>QUELLEN</span><h2>Finanzdaten-Abdeckung</h2></div></div>
        <ul className="finance-source-list">
          <li><div><strong>App Store Connect Sales</strong><small>Tägliche App-Einheiten, In-App-Käufe, Proceeds und Refunds</small></div><span className={`status-badge ${salesAvailable ? 'ready' : 'planned'}`}>{salesAvailable ? 'Verfügbar' : 'Ausstehend'}</span></li>
          <li><div><strong>Apple-Produkttypen</strong><small>{classificationStatus === 'complete' ? 'App- und In-App-Einheiten vollständig getrennt' : classificationStatus === 'partial' ? `Unbekannte Kennungen: ${unknownIdentifiers.join(', ') || 'nicht benannt'}` : 'Noch kein klassifizierbarer Tagesreport'}</small></div><span className={`status-badge ${classificationStatus === 'complete' ? 'ready' : 'planned'}`}>{classificationStatus === 'complete' ? 'Klassifiziert' : classificationStatus === 'partial' ? 'Teilweise' : 'Ausstehend'}</span></li>
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
          <p>App-Einheiten und In-App-Käufe werden anhand von Apples „Product Type Identifier“ getrennt. Updates, erneute Downloads und wiederhergestellte Käufe zählen nicht als neue Käufe.</p>
        </div>
      </article>
    </section>
    <footer>Flaggenbande Finanzen · Öffentliche Ansicht ohne Kontodaten, Belegdokumente oder Zugangsschlüssel.</footer>
  </section>
}
