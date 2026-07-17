import crypto from 'node:crypto'
import { gunzipSync } from 'node:zlib'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const outputPath = new URL('../dashboard/public/data/dashboard.json', import.meta.url)
const appStoreBase = 'https://api.appstoreconnect.apple.com/v1'
const cloudKitContainer = process.env.CLOUDKIT_CONTAINER || 'iCloud.de.phil.SpassmitFlaggen'
const isConfigured = (...names) => names.every(name => Boolean(process.env[name]))
const warnings = []

const now = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
const normalize = value => String(value ?? '').trim().toLowerCase().replace(/[ _-]/g, '')
const asNumber = value => {
  const normalized = String(value ?? '').replace(/[^0-9,.-]/g, '').replace(',', '.')
  const number = Number(normalized)
  return Number.isFinite(number) ? number : 0
}
const isoDate = value => {
  const text = String(value ?? '').trim()
  if (!text) return null
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text
  const german = text.match(/^(\d{2})\.(\d{2})\.(\d{4})$/)
  if (german) return `${german[3]}-${german[2]}-${german[1]}`
  const parsed = new Date(text)
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString().slice(0, 10)
}

function createAscToken({ issuer = process.env.ASC_ISSUER_ID, keyId = process.env.ASC_KEY_ID, privateKey = process.env.ASC_PRIVATE_KEY } = {}) {
  const timestamp = Math.floor(Date.now() / 1000)
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url')
  const unsigned = `${encode({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${encode({ iss: issuer, iat: timestamp, exp: timestamp + 600, aud: 'appstoreconnect-v1' })}`
  const signature = crypto.sign('sha256', Buffer.from(unsigned), { key: privateKey.replace(/\\n/g, '\n'), dsaEncoding: 'ieee-p1363' }).toString('base64url')
  return `${unsigned}.${signature}`
}

async function fetchWithRetry(url, options = {}, retries = 3) {
  let lastError
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      const response = await fetch(url, options)
      if (response.ok) return response
      if (![429, 500, 502, 503, 504].includes(response.status) || attempt === retries) throw new Error(`${response.status}: ${await response.text()}`)
      await new Promise(resolve => setTimeout(resolve, 500 * 2 ** attempt))
    } catch (error) {
      lastError = error
      if (attempt === retries) throw error
    }
  }
  throw lastError
}

function ascUrl(path) { return path.startsWith('http') ? path : `${appStoreBase}${path}` }
async function ascJson(path) {
  const response = await fetchWithRetry(ascUrl(path), { headers: { authorization: `Bearer ${createAscToken()}` } })
  return response.json()
}
async function ascPages(path) {
  const data = []
  let next = path
  while (next) {
    const page = await ascJson(next)
    data.push(...(page.data ?? []))
    next = typeof page.links?.next === 'string' ? page.links.next : page.links?.next?.href
  }
  return data
}

function parseTsv(bytes) {
  const buffer = Buffer.from(bytes)
  const text = (buffer[0] === 0x1f && buffer[1] === 0x8b ? gunzipSync(buffer) : buffer).toString('utf8').replace(/^\uFEFF/, '')
  const [headerLine, ...lines] = text.split(/\r?\n/).filter(Boolean)
  if (!headerLine) return []
  const headers = headerLine.split('\t')
  return lines.map(line => Object.fromEntries(headers.map((header, index) => [header, line.split('\t')[index] ?? ''])))
}
function column(row, aliases) { return Object.entries(row).find(([header]) => aliases.includes(normalize(header)))?.[1] }
function metricFromRow(row, aliases) { return asNumber(column(row, aliases)) }

function canonicalAnalytics(rows) {
  return rows.map(row => ({
    date: isoDate(column(row, ['date', 'eventdate', 'appdownloaddate'])),
    country: column(row, ['territory', 'countryorregion', 'country']) || undefined,
    device: column(row, ['device', 'platform']) || undefined,
    osVersion: column(row, ['platformversion', 'osversion']) || undefined,
    appVersion: column(row, ['appversion']) || undefined,
    downloads: metricFromRow(row, ['totaldownloads', 'downloads']),
    firstTimeDownloads: metricFromRow(row, ['firsttimedownloads']),
    redownloads: metricFromRow(row, ['redownloads']),
    impressions: metricFromRow(row, ['impressions']),
    productPageViews: metricFromRow(row, ['productpageviews']),
    sessions: metricFromRow(row, ['sessions']),
    activeDevices: metricFromRow(row, ['activedevices']),
    activeUsers: metricFromRow(row, ['activeusers']),
    installations: metricFromRow(row, ['installations']),
    deletions: metricFromRow(row, ['deletions']),
    crashes: metricFromRow(row, ['crashes']),
    retention: metricFromRow(row, ['retention', 'averageretention']),
  })).filter(row => row.date)
}

async function collectAnalytics() {
  if (!isConfigured('ASC_ISSUER_ID', 'ASC_KEY_ID', 'ASC_PRIVATE_KEY', 'ASC_ANALYTICS_REPORT_REQUEST_ID')) return { rows: [], available: false, reason: 'App-Store-Analytics-Secrets fehlen.' }
  const reports = await ascPages(`/analyticsReportRequests/${process.env.ASC_ANALYTICS_REPORT_REQUEST_ID}/reports`)
  const candidates = reports.filter(report => /standard/i.test(report.attributes?.name ?? ''))
  const selected = candidates.length ? candidates : reports
  const collected = []
  for (const report of selected) {
    const instances = await ascPages(`/analyticsReports/${report.id}/instances`)
    for (const instance of instances) {
      const segments = await ascPages(`/analyticsReportInstances/${instance.id}/segments`)
      for (const segment of segments) {
        const signedUrl = segment.attributes?.url
        if (!signedUrl) continue
        const response = await fetchWithRetry(signedUrl)
        collected.push(...parseTsv(await response.arrayBuffer()))
      }
    }
  }
  return { rows: canonicalAnalytics(collected), available: true }
}

async function collectReviewsAndRelease() {
  if (!isConfigured('ASC_ISSUER_ID', 'ASC_KEY_ID', 'ASC_PRIVATE_KEY', 'ASC_APP_ID')) return { available: false, reason: 'ASC_APP_ID oder App-Store-Connect-Secrets fehlen.', reviews: null, release: {} }
  try {
    const [reviews, versions, builds] = await Promise.all([
      ascPages(`/apps/${process.env.ASC_APP_ID}/customerReviews?limit=200`),
      ascPages(`/apps/${process.env.ASC_APP_ID}/appStoreVersions?limit=200`),
      ascPages(`/apps/${process.env.ASC_APP_ID}/builds?limit=200`),
    ])
    const ratings = reviews.map(review => asNumber(review.attributes?.rating)).filter(Boolean)
    const newestVersion = versions.sort((a, b) => String(b.attributes?.createdDate ?? '').localeCompare(String(a.attributes?.createdDate ?? '')))[0]
    const newestBuild = builds.sort((a, b) => String(b.attributes?.uploadedDate ?? '').localeCompare(String(a.attributes?.uploadedDate ?? '')))[0]
    return {
      available: true,
      reviews: ratings.length ? { count: ratings.length, average: ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length } : { count: 0, average: null },
      release: {
        appStoreVersion: newestVersion?.attributes?.versionString,
        appStoreState: newestVersion?.attributes?.appStoreState,
        build: newestBuild?.attributes?.version,
        buildProcessingState: newestBuild?.attributes?.processingState,
      },
    }
  } catch (error) { return { available: false, reason: `App-Store-Metadaten noch nicht abrufbar: ${error.message}`, reviews: null, release: {} } }
}

function canonicalSales(rows) {
  return rows.map(row => {
    const units = metricFromRow(row, ['units'])
    const proceeds = metricFromRow(row, ['developerproceeds', 'proceeds'])
    const country = column(row, ['countryofsale', 'customercountry', 'territory'])
    const currency = column(row, ['proceedscurrency', 'currencyofproceeds', 'currency'])
    return {
      date: isoDate(column(row, ['enddate', 'begindate', 'date'])), country: country || undefined,
      purchases: units > 0 ? units : 0, refunds: units < 0 ? Math.abs(units) : 0,
      proceeds: currency === 'EUR' || !currency ? proceeds : 0,
    }
  }).filter(row => row.date)
}

async function collectSales() {
  if (!isConfigured('ASC_ISSUER_ID', 'ASC_KEY_ID', 'ASC_PRIVATE_KEY', 'ASC_VENDOR_NUMBER')) return { rows: [], available: false, reason: 'ASC_VENDOR_NUMBER fehlt.' }
  const reportDate = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
  const query = new URLSearchParams({ 'filter[frequency]': 'DAILY', 'filter[reportDate]': reportDate, 'filter[reportSubType]': 'SUMMARY', 'filter[reportType]': 'SALES', 'filter[vendorNumber]': process.env.ASC_VENDOR_NUMBER, 'filter[version]': '1_0' })
  try {
    const response = await fetchWithRetry(`${appStoreBase}/salesReports?${query}`, { headers: { authorization: `Bearer ${createAscToken()}` } })
    return { rows: canonicalSales(parseTsv(await response.arrayBuffer())), available: true }
  } catch (error) {
    const detail = String(error.message)
    const reason = detail.includes('NOT_FOUND') || detail.includes('no sales for the date specified')
      ? 'Apple meldet für den abgefragten Tag noch keine Verkäufe.'
      : 'Der Tagesreport ist noch nicht verfügbar; der nächste tägliche Abruf versucht es erneut.'
    return { rows: [], available: false, reason }
  }
}

async function collectFinance() {
  if (!isConfigured('ASC_FINANCE_ISSUER_ID', 'ASC_FINANCE_KEY_ID', 'ASC_FINANCE_PRIVATE_KEY', 'ASC_VENDOR_NUMBER')) return { available: false, reason: 'Separater Finance-Key oder ASC_VENDOR_NUMBER fehlt.', latest: null }
  const month = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth() - 1, 1)).toISOString().slice(0, 7)
  const query = new URLSearchParams({ 'filter[regionCode]': 'ZZ', 'filter[reportDate]': month, 'filter[reportType]': 'FINANCIAL', 'filter[vendorNumber]': process.env.ASC_VENDOR_NUMBER })
  try {
    const token = createAscToken({ issuer: process.env.ASC_FINANCE_ISSUER_ID, keyId: process.env.ASC_FINANCE_KEY_ID, privateKey: process.env.ASC_FINANCE_PRIVATE_KEY })
    const response = await fetchWithRetry(`${appStoreBase}/financeReports?${query}`, { headers: { authorization: `Bearer ${token}` } })
    const rows = parseTsv(await response.arrayBuffer())
    const proceeds = rows.reduce((sum, row) => sum + metricFromRow(row, ['developerproceeds', 'proceeds']), 0)
    return { available: true, latest: { period: month, proceeds, currency: 'EUR' } }
  } catch (error) { return { available: false, reason: 'Der monatliche Finanzreport ist noch nicht verfügbar.', latest: null } }
}

function cloudKitHeaders(path, body) {
  const date = now()
  const bodyHash = crypto.createHash('sha256').update(body).digest('base64')
  const message = `${date}:${bodyHash}:${path}`
  const signature = crypto.sign('sha256', Buffer.from(message), { key: process.env.CLOUDKIT_PRIVATE_KEY.replace(/\\n/g, '\n') }).toString('base64')
  return { 'content-type': 'application/json', 'X-Apple-CloudKit-Request-KeyID': process.env.CLOUDKIT_KEY_ID, 'X-Apple-CloudKit-Request-ISO8601Date': date, 'X-Apple-CloudKit-Request-SignatureV1': signature }
}
function field(record, key) { const value = record.fields?.[key]?.value; return typeof value === 'object' && value?.timestamp ? value.timestamp : value }
async function cloudKitQuery(recordType, desiredKeys) {
  const path = `/database/1/${cloudKitContainer}/production/public/records/query`
  const all = []
  let continuationMarker
  do {
    const payload = JSON.stringify({ query: { recordType, filterBy: [], sortBy: [] }, desiredKeys, resultsLimit: 200, continuationMarker })
    const response = await fetchWithRetry(`https://api.apple-cloudkit.com${path}`, { method: 'POST', headers: cloudKitHeaders(path, payload), body: payload })
    const page = await response.json()
    all.push(...(page.records ?? []))
    continuationMarker = page.continuationMarker
  } while (continuationMarker)
  return all
}

function aggregateBy(items, mapper) {
  const map = new Map()
  for (const item of items) {
    const { key, value } = mapper(item)
    if (!key || !Number.isFinite(value)) continue
    map.set(key, (map.get(key) ?? 0) + value)
  }
  return [...map.entries()].map(([key, value]) => ({ key, value })).sort((a, b) => b.value - a.value)
}

async function collectCloudKit() {
  if (!isConfigured('CLOUDKIT_KEY_ID', 'CLOUDKIT_PRIVATE_KEY')) return { cloudKit: {}, available: false, reason: 'CloudKit-Server-to-Server-Secrets fehlen.' }
  try {
    const [players, attempts, userStats] = await Promise.all([
      cloudKitQuery('PlayerStats', ['updatedAt']),
      cloudKitQuery('DailyAttempt', ['dateKey', 'mode', 'score', 'duration', 'completed']),
      cloudKitQuery('UserStats', ['dailyFlaggenrunTrophies', 'dailyStaedterunTrophies', 'totalTrophies', 'updatedAt']),
    ])
    const dailyMap = new Map()
    for (const record of attempts) {
      const date = isoDate(field(record, 'dateKey'))
      if (!date) continue
      const mode = String(field(record, 'mode') ?? 'Unbekannt')
      const key = `${date}|${mode}`
      const state = dailyMap.get(key) ?? { date, mode, attempts: 0, completed: 0, scoreTotal: 0, durationTotal: 0, players: new Set() }
      state.attempts += 1
      state.completed += field(record, 'completed') ? 1 : 0
      state.scoreTotal += asNumber(field(record, 'score'))
      state.durationTotal += asNumber(field(record, 'duration'))
      state.players.add(record.recordName ?? crypto.createHash('sha256').update(JSON.stringify(record)).digest('hex'))
      dailyMap.set(key, state)
    }
    const daily = [...dailyMap.values()].sort((a, b) => a.date.localeCompare(b.date) || a.mode.localeCompare(b.mode)).map(state => ({ date: state.date, mode: state.mode, players: state.players.size, attempts: state.attempts, completed: state.completed, averageScore: state.attempts ? state.scoreTotal / state.attempts : null, averageDuration: state.attempts ? state.durationTotal / state.attempts : null, abortRate: state.attempts ? 1 - state.completed / state.attempts : null }))
    const scores = aggregateBy(attempts, record => ({ key: String(Math.floor(asNumber(field(record, 'score')) / 10) * 10), value: 1 }))
    const modes = aggregateBy(attempts, record => ({ key: String(field(record, 'mode') ?? 'Unbekannt'), value: 1 }))
    const trophies = [{ key: 'Flaggenrun', value: userStats.reduce((sum, record) => sum + asNumber(field(record, 'dailyFlaggenrunTrophies')), 0) }, { key: 'Städterun', value: userStats.reduce((sum, record) => sum + asNumber(field(record, 'dailyStaedterunTrophies')), 0) }]
    const today = new Date().toISOString().slice(0, 10)
    const averageScore = attempts.length ? attempts.reduce((sum, record) => sum + asNumber(field(record, 'score')), 0) / attempts.length : null
    return { cloudKit: { daily, scoreDistribution: scores, modes, trophies, players: players.length, profilesUpdatedToday: players.filter(record => String(field(record, 'updatedAt') ?? '').startsWith(today)).length, totalAttempts: attempts.length, averageScore }, available: true }
  } catch (error) { return { cloudKit: {}, available: false, reason: `CloudKit-Query fehlgeschlagen: ${error.message}` } }
}

function mergeDaily(rows) {
  const byDimension = new Map()
  for (const row of rows) {
    const key = [row.date, row.country, row.device, row.osVersion, row.appVersion].join('|')
    const state = byDimension.get(key) ?? { date: row.date, country: row.country, device: row.device, osVersion: row.osVersion, appVersion: row.appVersion }
    for (const [name, value] of Object.entries(row)) if (typeof value === 'number') state[name] = (state[name] ?? 0) + value
    byDimension.set(key, state)
  }
  return [...byDimension.values()].sort((a, b) => a.date.localeCompare(b.date))
}

async function loadPrevious() { try { return JSON.parse(await readFile(outputPath, 'utf8')) } catch { return null } }
async function writeAtomically(payload) {
  await mkdir(dirname(fileURLToPath(outputPath)), { recursive: true })
  const temporary = new URL(`../dashboard/public/data/dashboard-${Date.now()}.json`, import.meta.url)
  await writeFile(temporary, JSON.stringify(payload, null, 2) + '\n')
  await rename(temporary, outputPath)
}

const previous = await loadPrevious()
try {
  const [analytics, reviewsAndRelease, sales, finance, cloud] = await Promise.all([collectAnalytics(), collectReviewsAndRelease(), collectSales(), collectFinance(), collectCloudKit()])
  if (![analytics.available, reviewsAndRelease.available, sales.available, finance.available, cloud.available].some(Boolean) && previous?.status === 'waiting_for_first_sync') process.exit(0)
  const allRows = [...analytics.rows, ...sales.rows]
  const daily = mergeDaily(allRows)
  const availability = {
    'App Analytics': { available: analytics.available && analytics.rows.length > 0, reason: analytics.reason ?? (analytics.rows.length ? undefined : 'Apple hat noch keine Analytics-Instanzen bereitgestellt.'), updatedAt: now() },
    'App Store Feedback & Release': { available: reviewsAndRelease.available, reason: reviewsAndRelease.reason, updatedAt: now() },
    'Sales & Trends': { available: sales.available && sales.rows.length > 0, reason: sales.reason ?? (sales.rows.length ? undefined : 'Der erste Tagesreport ist noch nicht verfügbar.'), updatedAt: now() },
    'CloudKit Public DB': { available: cloud.available, reason: cloud.reason, updatedAt: now() },
    'Finance': { available: finance.available, reason: finance.reason, updatedAt: now() },
  }
  const payload = {
    schemaVersion: 1, generatedAt: now(), status: 'ok', messages: warnings, availability,
    kpis: { reviewAverage: reviewsAndRelease.reviews?.average ?? null, reviewCount: reviewsAndRelease.reviews?.count ?? null },
    daily, countries: aggregateBy(allRows, row => ({ key: row.country ?? '', value: row.downloads || row.purchases || 0 })),
    devices: aggregateBy(analytics.rows, row => ({ key: row.device ?? '', value: row.activeDevices || 0 })),
    versions: aggregateBy(analytics.rows, row => ({ key: row.appVersion ?? '', value: row.activeDevices || 0 })),
    release: reviewsAndRelease.release, finance: finance.latest, cloudKit: cloud.cloudKit ?? {},
  }
  await writeAtomically(payload)
} catch (error) {
  if (previous) {
    previous.status = 'error'
    previous.messages = [`Letzter Abruf fehlgeschlagen; sichere vorherige Daten bleiben sichtbar. ${error.message}`]
    await writeAtomically(previous)
  } else {
    await writeAtomically({ schemaVersion: 1, generatedAt: now(), status: 'error', messages: [`Erster Abruf fehlgeschlagen: ${error.message}`], availability: {}, kpis: {}, daily: [], countries: [], devices: [], versions: [], cloudKit: {} })
  }
  process.exitCode = 1
}
