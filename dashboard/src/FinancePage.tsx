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
  const financeAvailable = data.finance !== null && data.finance !== undefined
  const salesAvailable = data.availability['Sales & Trends']?.available === true
  const salesReason = data.availability['Sales & Trends']?.reason ?? 'Noch kein Tagesreport'
  const financeReason = data.availability.Finance?.reason ?? 'Noch kein Monatsbericht'
  const hasFinancialValues = financeAvailable || proceeds !== null || appUnits !== null || inAppPurchaseUnits !== null || refunds !== null
  const classificationStatus = data.sales?.classificationStatus ?? 'unavailable'
  const unknownIdentifiers = data.sales?.unknownProductTypeIdentifiers ?? []

  return <section id="finance-view" className="dashboard-view" role="tabpanel" aria-labelledby="finance-tab" tabIndex={0}>
    <header className="compact-page-header">
      <div><h1>Finanzen</h1><span className={`compact-sync ${hasFinancialValues ? 'ok' : 'partial'}`}>{hasFinancialValues ? 'Daten vorhanden' : 'Noch keine Beträge'}</span></div>
      <button onClick={onRefresh} disabled={refreshing} aria-label="Finanzdaten aktualisieren">↻</button>
    </header>

    <section className="kpis finance-kpis" aria-label="Finanzkennzahlen">
      <article className="kpi-card green"><p>Apple-Erlöse · Monatsbericht</p><strong>{formatMoney(data.finance?.proceeds ?? null)}</strong><span>{data.finance?.period ?? 'Noch nicht verfügbar'}</span></article>
      <article className="kpi-card green"><p>Erlöse · verfügbare Historie</p><strong>{formatMoney(proceeds)}</strong><span>App Store Connect · Verkäufe</span></article>
      <article className="kpi-card purple"><p>App-Einheiten · Tagesbericht</p><strong>{formatNumber(appUnits)}</strong><span>{appUnits === null ? metricAvailability(appUnits, '') : formatReportDate(data.sales?.reportDate)}</span></article>
      <article className="kpi-card purple"><p>In-App-Käufe · Tagesbericht</p><strong>{formatNumber(inAppPurchaseUnits)}</strong><span>{inAppPurchaseUnits === null ? metricAvailability(inAppPurchaseUnits, '') : formatReportDate(data.sales?.reportDate)}</span></article>
      <article className="kpi-card red"><p>Rückerstattungen</p><strong>{formatNumber(refunds)}</strong><span>{metricAvailability(refunds, 'bestätigte Einheiten')}</span></article>
    </section>

    <section className="finance-grid">
      <article className="panel finance-panel">
        <div className="panel-heading"><div><span>QUELLEN</span><h2>Finanzdaten-Abdeckung</h2></div></div>
        <ul className="finance-source-list">
          <li><div><strong>App Store Connect · Tagesreport</strong><small>{salesAvailable ? 'App-Einheiten, In-App-Käufe, Erlöse und Rückerstattungen' : salesReason}</small></div><span className={`status-badge ${salesAvailable ? 'ready' : 'planned'}`}>{salesAvailable ? 'Verfügbar' : 'Noch kein Report'}</span></li>
          <li><div><strong>Apple-Produkttypen</strong><small>{classificationStatus === 'complete' ? 'App- und In-App-Einheiten vollständig getrennt' : classificationStatus === 'partial' ? `Unbekannte Kennungen: ${unknownIdentifiers.join(', ') || 'nicht benannt'}` : 'Noch kein klassifizierbarer Tagesreport'}</small></div><span className={`status-badge ${classificationStatus === 'complete' ? 'ready' : 'planned'}`}>{classificationStatus === 'complete' ? 'Klassifiziert' : classificationStatus === 'partial' ? 'Teilweise' : 'Ausstehend'}</span></li>
          <li><div><strong>Apple-Finanzbericht</strong><small>{financeAvailable ? 'Monatliche bestätigte Auszahlung' : financeReason}</small></div><span className={`status-badge ${financeAvailable ? 'ready' : 'planned'}`}>{financeAvailable ? 'Verfügbar' : 'Noch kein Report'}</span></li>
          <li><div><strong>Umsatz der sozialen Plattformen</strong><small>YouTube, Instagram, Facebook und TikTok</small></div><span className="status-badge not_configured">Nicht angebunden</span></li>
          <li><div><strong>Produktionskosten</strong><small>Spracherzeugung, Videoerstellung und externe Dienste</small></div><span className="status-badge planned">Noch nicht erfasst</span></li>
        </ul>
      </article>
    </section>
  </section>
}
