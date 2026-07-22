import { useEffect, useMemo, useState } from 'react'
import type { EChartsOption, EChartsType } from 'echarts'
import ContentSystemDashboard from './ContentSystemDashboard'
import FinancePage from './FinancePage'
import NewProductionPage from './NewProductionPage'
import PublishingCalendar from './PublishingCalendar'
import SocialStatsPage from './SocialStatsPage'
import { DASHBOARD_SECTIONS, dashboardSectionFromHash, type DashboardSectionId } from './dashboardSections'
import type { DashboardData, DailyMetric, Numeric } from './types'
import { emptyDashboard } from './types'

const formatNumber = (value: Numeric) => value === null || value === undefined ? '—' : new Intl.NumberFormat('de-DE', { maximumFractionDigits: 1 }).format(value)
const formatPercent = (value: Numeric) => value === null || value === undefined ? '—' : new Intl.NumberFormat('de-DE', { style: 'percent', maximumFractionDigits: 1 }).format(value)
const numeric = (value: unknown) => typeof value === 'number' ? value : 0
const optionalNumeric = (value: unknown): number | null => typeof value === 'number' ? value : null
const unique = (values: Array<string | undefined>) => [...new Set(values.filter((value): value is string => Boolean(value)))].sort()
const availabilityLabels: Record<string, string> = {
  'App Analytics': 'App-Auswertung',
  'App Store Feedback & Release': 'App-Store-Bewertungen und Freigabe',
  'Sales & Trends': 'Verkäufe und Entwicklungen',
  Finance: 'Finanzen',
}

function Chart({ option, label }: { option: EChartsOption; label: string }) {
  const [element, setElement] = useState<HTMLDivElement | null>(null)
  useEffect(() => {
    if (!element) return
    let disposed = false
    let chart: EChartsType | null = null
    const observer = new ResizeObserver(() => chart?.resize())
    void import('echarts').then(echarts => {
      if (disposed) return
      chart = echarts.init(element, undefined, { renderer: 'canvas' })
      chart.setOption(option)
      observer.observe(element)
    })
    return () => { disposed = true; observer.disconnect(); chart?.dispose() }
  }, [element, option])
  return <div className="chart" ref={setElement} aria-label={label} role="img" />
}

function KpiCard({ label, value, detail, accent = 'blue' }: { label: string; value: string; detail: string; accent?: string }) {
  return <article className={`kpi-card ${accent}`}><p>{label}</p><strong>{value}</strong><span>{detail}</span></article>
}

function Panel({ eyebrow, title, detail, children, wide = false }: { eyebrow: string; title: string; detail?: string; children: React.ReactNode; wide?: boolean }) {
  return <article className={`panel ${wide ? 'wide' : ''}`}><div className="panel-heading"><div><span>{eyebrow}</span><h2>{title}</h2></div>{detail && <small>{detail}</small>}</div>{children}</article>
}

function aggregateByDate(rows: DailyMetric[]) {
  const map = new Map<string, Record<string, number | string>>()
  for (const row of rows) {
    const state = map.get(row.date) ?? { date: row.date }
    for (const [key, value] of Object.entries(row)) if (typeof value === 'number') state[key] = numeric(state[key]) + value
    map.set(row.date, state)
  }
  return [...map.values()].sort((a, b) => String(a.date).localeCompare(String(b.date)))
}

function aggregateBreakdown(rows: DailyMetric[], field: 'country' | 'device' | 'osVersion' | 'appVersion') {
  const map = new Map<string, number>()
  for (const row of rows) {
    const key = row[field]
    if (!key) continue
    map.set(key, (map.get(key) ?? 0) + numeric(row.downloads) + numeric(row.purchases))
  }
  return [...map.entries()].map(([key, value]) => ({ key, value })).sort((a, b) => b.value - a.value)
}

const baseGrid = { left: 44, right: 18, top: 44, bottom: 34 }
const lineStyle = { color: '#8ca1ba' }
const splitLine = { lineStyle: { color: '#22334b' } }

export default function Dashboard() {
  const [activeView, setActiveView] = useState<DashboardSectionId>(() => dashboardSectionFromHash(window.location.hash))
  const [data, setData] = useState<DashboardData>(emptyDashboard)
  const [days, setDays] = useState('30')
  const [country, setCountry] = useState('all')
  const [device, setDevice] = useState('all')
  const [osVersion, setOsVersion] = useState('all')
  const [appVersion, setAppVersion] = useState('all')
  const [error, setError] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const refreshDashboard = async () => {
    setRefreshing(true)
    setError(null)
    try {
      const response = await fetch(`./data/dashboard.json?refresh=${Date.now()}`, { cache: 'no-store' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const payload: DashboardData = await response.json()
      setData({
        ...emptyDashboard,
        ...payload,
        cloudKit: { ...emptyDashboard.cloudKit, ...payload.cloudKit },
        social: {
          ...emptyDashboard.social,
          ...payload.social,
          platforms: { ...emptyDashboard.social.platforms, ...payload.social?.platforms },
          totals: { ...emptyDashboard.social.totals, ...payload.social?.totals },
        },
      })
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : String(reason)
      setError(`Übersichtsdaten konnten nicht geladen werden: ${message}`)
    } finally {
      setRefreshing(false)
    }
  }

  useEffect(() => {
    void refreshDashboard()
  }, [])

  useEffect(() => {
    const syncSection = () => setActiveView(dashboardSectionFromHash(window.location.hash))
    window.addEventListener('hashchange', syncSection)
    return () => window.removeEventListener('hashchange', syncSection)
  }, [])

  const openSection = (section: DashboardSectionId) => {
    setActiveView(section)
    window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#/${section}`)
  }

  const moveSectionFocus = (event: React.KeyboardEvent<HTMLButtonElement>, currentIndex: number) => {
    let nextIndex: number | null = null
    if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % DASHBOARD_SECTIONS.length
    if (event.key === 'ArrowLeft') nextIndex = (currentIndex - 1 + DASHBOARD_SECTIONS.length) % DASHBOARD_SECTIONS.length
    if (event.key === 'Home') nextIndex = 0
    if (event.key === 'End') nextIndex = DASHBOARD_SECTIONS.length - 1
    if (nextIndex === null) return
    event.preventDefault()
    const nextSection = DASHBOARD_SECTIONS[nextIndex]
    openSection(nextSection.id)
    requestAnimationFrame(() => document.getElementById(`${nextSection.id}-tab`)?.focus())
  }

  const countries = useMemo(() => unique(data.daily.map(row => row.country)), [data.daily])
  const devices = useMemo(() => unique(data.daily.map(row => row.device)), [data.daily])
  const osVersions = useMemo(() => unique(data.daily.map(row => row.osVersion)), [data.daily])
  const appVersions = useMemo(() => unique(data.daily.map(row => row.appVersion)), [data.daily])
  const filtered = useMemo(() => {
    let visible = data.daily.filter(row => (country === 'all' || row.country === country) && (device === 'all' || row.device === device) && (osVersion === 'all' || row.osVersion === osVersion) && (appVersion === 'all' || row.appVersion === appVersion))
    if (days === 'all') return visible
    const allowed = new Set([...new Set(visible.map(row => row.date))].sort().slice(-Number(days)))
    return visible.filter(row => allowed.has(row.date))
  }, [data.daily, days, country, device, osVersion, appVersion])
  const series = useMemo(() => aggregateByDate(filtered), [filtered])
  const latest = series.at(-1)
  const last7 = series.slice(-7)
  const last7Downloads = last7.some(row => typeof row.downloads === 'number')
    ? last7.reduce((sum, row) => sum + numeric(row.downloads), 0)
    : null
  const filteredCountries = useMemo(() => aggregateBreakdown(filtered, 'country'), [filtered])
  const hasTrend = series.some(row => Object.values(row).some(value => typeof value === 'number' && value > 0))
  const labels = series.map(row => String(row.date).slice(5))

  const downloadsOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, grid: baseGrid,
    xAxis: { type: 'category', data: labels, axisLabel: lineStyle }, yAxis: { type: 'value', axisLabel: lineStyle, splitLine },
    series: [{ name: 'Downloads', type: 'line', smooth: true, showSymbol: false, data: series.map(row => numeric(row.downloads)), lineStyle: { color: '#59b7ff', width: 3 }, areaStyle: { color: 'rgba(89,183,255,.12)' } }],
  }), [labels, series])
  const discoveryOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, legend: { textStyle: { color: '#b7c7d9' } }, grid: baseGrid,
    xAxis: { type: 'category', data: labels, axisLabel: lineStyle }, yAxis: { type: 'value', axisLabel: lineStyle, splitLine },
    series: [
      { name: 'Einblendungen', type: 'line', smooth: true, showSymbol: false, data: series.map(row => numeric(row.impressions)), lineStyle: { color: '#a78bfa', width: 2 } },
      { name: 'Produktseiten-Aufrufe', type: 'line', smooth: true, showSymbol: false, data: series.map(row => numeric(row.productPageViews)), lineStyle: { color: '#41d6a2', width: 2 } },
    ],
  }), [labels, series])
  const engagementOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, legend: { textStyle: { color: '#b7c7d9' } }, grid: baseGrid,
    xAxis: { type: 'category', data: labels, axisLabel: lineStyle }, yAxis: { type: 'value', axisLabel: lineStyle, splitLine },
    series: [
      { name: 'Sitzungen', type: 'line', smooth: true, showSymbol: false, data: series.map(row => numeric(row.sessions)), lineStyle: { color: '#59b7ff', width: 2 } },
      { name: 'Aktive Geräte', type: 'line', smooth: true, showSymbol: false, data: series.map(row => numeric(row.activeDevices)), lineStyle: { color: '#f7b955', width: 2 } },
    ],
  }), [labels, series])
  const qualityOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, legend: { textStyle: { color: '#b7c7d9' } }, grid: baseGrid,
    xAxis: { type: 'category', data: labels, axisLabel: lineStyle }, yAxis: [{ type: 'value', axisLabel: lineStyle, splitLine }, { type: 'value', min: 0, max: 1, axisLabel: { ...lineStyle, formatter: (value: number) => `${Math.round(value * 100)}%` }, splitLine: { show: false } }],
    series: [
      { name: 'Abstürze', type: 'bar', data: series.map(row => numeric(row.crashes)), itemStyle: { color: '#ff7e8a', borderRadius: [4, 4, 0, 0] } },
      { name: 'Nutzerbindung', type: 'line', yAxisIndex: 1, smooth: true, showSymbol: false, data: series.map(row => numeric(row.retention)), lineStyle: { color: '#41d6a2', width: 2 } },
    ],
  }), [labels, series])
  const countryOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, grid: { left: 80, right: 18, top: 18, bottom: 20 },
    xAxis: { type: 'value', axisLabel: lineStyle, splitLine }, yAxis: { type: 'category', data: filteredCountries.slice(0, 8).map(row => row.key).reverse(), axisLabel: { color: '#b7c7d9' } },
    series: [{ type: 'bar', data: filteredCountries.slice(0, 8).map(row => row.value).reverse(), itemStyle: { color: '#59b7ff', borderRadius: 4 } }],
  }), [filteredCountries])
  const modeOption = useMemo<EChartsOption>(() => ({
    backgroundColor: 'transparent', tooltip: { trigger: 'axis' }, grid: { left: 80, right: 18, top: 18, bottom: 20 },
    xAxis: { type: 'value', axisLabel: lineStyle, splitLine }, yAxis: { type: 'category', data: data.cloudKit.modes.slice(0, 8).map(row => row.key).reverse(), axisLabel: { color: '#b7c7d9' } },
    series: [{ type: 'bar', data: data.cloudKit.modes.slice(0, 8).map(row => row.value).reverse(), itemStyle: { color: '#41d6a2', borderRadius: 4 } }],
  }), [data.cloudKit.modes])

  const exportCsv = () => {
    const header = ['date', 'downloads', 'impressions', 'productPageViews', 'sessions', 'activeDevices', 'crashes', 'proceeds']
    const escape = (value: unknown) => `"${String(value ?? '').replaceAll('"', '""')}"`
    const body = series.map(row => header.map(key => escape(row[key])).join(','))
    const url = URL.createObjectURL(new Blob([[header.join(','), ...body].join('\n')], { type: 'text/csv;charset=utf-8' }))
    const link = document.createElement('a'); link.href = url; link.download = 'flaggenbande-analytics.csv'; link.click(); URL.revokeObjectURL(url)
  }
  const select = (label: string, value: string, setValue: (value: string) => void, entries: string[], allLabel: string) => <label>{label}<select aria-label={label} value={value} onChange={event => setValue(event.target.value)}><option value="all">{allLabel}</option>{entries.map(entry => <option key={entry} value={entry}>{entry}</option>)}</select></label>

  return <main>
    <nav className="dashboard-tabs" role="tablist" aria-label="Bereiche der Übersicht">
      {DASHBOARD_SECTIONS.map((section, index) => <button
        id={`${section.id}-tab`}
        key={section.id}
        type="button"
        role="tab"
        aria-selected={activeView === section.id}
        aria-controls={`${section.id}-view`}
        tabIndex={activeView === section.id ? 0 : -1}
        className={activeView === section.id ? 'active' : ''}
        onClick={() => openSection(section.id)}
        onKeyDown={event => moveSectionFocus(event, index)}
      >{section.label}</button>)}
    </nav>
    {activeView === 'new-production' && <NewProductionPage />}
    {activeView === 'production' && <ContentSystemDashboard />}
    {activeView === 'calendar' && <PublishingCalendar socialVideos={data.social.videos} />}
    {activeView === 'social-stats' && <SocialStatsPage data={data.social} generatedAt={data.generatedAt} refreshing={refreshing} onRefresh={() => void refreshDashboard()} />}
    {activeView === 'finance' && <FinancePage data={data} rows={data.daily} refreshing={refreshing} onRefresh={() => void refreshDashboard()} />}
    {activeView === 'app-development' && <section id="app-development-view" className="dashboard-view" role="tabpanel" aria-labelledby="app-development-tab" tabIndex={0}>
    <header className="compact-page-header">
      <div><h1>App</h1><span className={`compact-sync ${data.status}`}>{data.generatedAt ? new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(data.generatedAt)) : '—'}</span></div>
      <button onClick={() => void refreshDashboard()} disabled={refreshing} aria-label="App-Daten aktualisieren">↻</button>
    </header>
    <section className="filters" aria-label="Filter der Übersicht">
      <label>Zeitraum<select aria-label="Zeitraum" value={days} onChange={event => setDays(event.target.value)}><option value="7">7 Tage</option><option value="30">30 Tage</option><option value="90">90 Tage</option><option value="all">Gesamt</option></select></label>
      {select('Land', country, setCountry, countries, 'Alle Länder')}{select('Gerät', device, setDevice, devices, 'Alle Geräte')}{select('iOS', osVersion, setOsVersion, osVersions, 'Alle iOS-Versionen')}{select('App-Version', appVersion, setAppVersion, appVersions, 'Alle App-Versionen')}
      <button className="export" onClick={exportCsv} disabled={!series.length}>CSV exportieren</button>
    </section>
    {(error || data.messages.length > 0) && <section className="notices">{error && <p className="error">{error}</p>}{data.messages.map(message => <p key={message}>{message}</p>)}</section>}
    <section className="kpis" aria-label="Kernkennzahlen">
      <KpiCard label="Downloads heute" value={formatNumber(optionalNumeric(latest?.downloads))} detail="App Store Connect" />
      <KpiCard label="Downloads · 7 Tage" value={formatNumber(last7Downloads)} detail="rollierend" />
      <KpiCard label="Produktseiten-Aufrufe" value={formatNumber(optionalNumeric(latest?.productPageViews))} detail="heute" accent="purple" />
      <KpiCard label="Umwandlungsrate" value={formatPercent(numeric(latest?.impressions) > 0 ? numeric(latest?.downloads) / numeric(latest?.impressions) : null)} detail="Downloads / Einblendungen" accent="green" />
      <KpiCard label="Aktive Geräte" value={formatNumber(optionalNumeric(latest?.activeDevices))} detail="Apple · Geräte mit mindestens einer Sitzung" accent="gold" />
      <KpiCard label="Abstürze" value={formatNumber(optionalNumeric(latest?.crashes))} detail="heute" accent="red" />
      <KpiCard label="App-Store-Bewertung" value={data.kpis.reviewAverage ? `${formatNumber(data.kpis.reviewAverage)} / 5` : '—'} detail={`${formatNumber(data.kpis.reviewCount)} Bewertungen`} accent="purple" />
      <KpiCard label="Eindeutige CloudKit-Nutzer" value={formatNumber(data.cloudKit.uniqueUsers ?? null)} detail={typeof data.cloudKit.identifiedUserCoverage === 'number' ? `${formatPercent(data.cloudKit.identifiedUserCoverage)} der Versuche zuordenbar` : 'pseudonyme Geräte oder Game-Center-Konten'} accent="purple" />
      <KpiCard label="CloudKit-Nutzer · letzter Tag" value={formatNumber(data.cloudKit.uniqueUsersLatestDay ?? null)} detail="eindeutige DailyAttempt-Nutzer" accent="gold" />
      <KpiCard label="CloudKit-Abschlussquote" value={formatPercent(typeof data.cloudKit.totalAttempts === 'number' && data.cloudKit.totalAttempts > 0 ? numeric(data.cloudKit.completedAttempts) / data.cloudKit.totalAttempts : null)} detail={`${formatNumber(data.cloudKit.completedAttempts ?? null)} von ${formatNumber(data.cloudKit.totalAttempts ?? null)} Versuchen`} />
      <KpiCard label="Aktuelle Version" value={data.release?.build ?? '—'} detail={data.release?.buildProcessingState ?? data.release?.appStoreState ?? 'App Store Connect'} accent="green" />
    </section>
    <section className="chart-grid">
      <Panel eyebrow="GEWINNUNG" title="Downloads im Zeitverlauf" detail={hasTrend ? 'Interaktiv filterbar' : 'Daten folgen nach Apples Mindestschwelle'} wide><Chart option={downloadsOption} label="Downloads im Zeitverlauf" /></Panel>
      <Panel eyebrow="SICHTBARKEIT" title="Sichtbarkeit und Produktseite" detail="Einblendungen · Produktseiten-Aufrufe" wide><Chart option={discoveryOption} label="App-Store-Sichtbarkeit" /></Panel>
      <Panel eyebrow="NUTZUNG" title="Sitzungen und aktive Geräte" detail="App-Auswertung" wide><Chart option={engagementOption} label="Nutzung im Zeitverlauf" /></Panel>
      <Panel eyebrow="QUALITÄT" title="Abstürze und Nutzerbindung" detail="nur bei Apple-Schwelle" wide><Chart option={qualityOption} label="Abstürze und Nutzerbindung" /></Panel>
      <Panel eyebrow="LÄNDER" title="Downloads nach Land" detail="aktiver Filter berücksichtigt"><Chart option={countryOption} label="Downloads nach Land" /></Panel>
      <Panel eyebrow="SPIELMODI" title="Versuche nach Modus" detail="CloudKit DailyAttempt"><Chart option={modeOption} label="Versuche nach Spielmodus" /></Panel>
      <Panel eyebrow="DATENABDECKUNG" title="Verfügbare Quellen" detail="Sicherer, stündlicher Abruf">
        <div className="metric-list">{Object.entries(data.availability).length ? <ul>{Object.entries(data.availability).map(([name, entry]) => <li key={name}><span className={entry.available ? 'available-dot' : 'unavailable-dot'} /><b>{availabilityLabels[name] ?? name}</b><small>{entry.available ? 'Verfügbar' : entry.reason ?? 'Noch nicht verfügbar'}</small></li>)}</ul> : <p>Der erste Abruf füllt hier transparent die verfügbaren Apple- und CloudKit-Quellen ein.</p>}</div>
      </Panel>
    </section>
    </section>}
  </main>
}
