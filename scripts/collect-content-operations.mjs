import { readFile, rename, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const outputUrl = new URL('../dashboard/public/data/content-operations.json', import.meta.url)
const platforms = ['youtube', 'instagram', 'tiktok', 'facebook']
const platformSet = new Set(platforms)
const qualityStatuses = new Set(['not_run', 'passed', 'failed'])
const runStatuses = new Set(['queued', 'running', 'partial', 'qa_failed', 'ready', 'completed', 'failed', 'expired', 'reconcile_required'])
const finalPublicationStatuses = new Set(['private', 'draft', 'container_unpublished', 'upload_ready', 'manual_uploaded'])
const passthroughPublicationStatuses = new Set(['planned', 'uploading', 'processing', 'failed', 'expired', 'reconcile_required'])
const expectedMode = {
  youtube: 'private',
  instagram: 'container_unpublished',
  facebook: 'draft',
  tiktok: 'manual_uploaded',
}
const platformForFinalStatus = {
  private: 'youtube',
  draft: 'facebook',
  container_unpublished: 'instagram',
  upload_ready: 'instagram',
  manual_uploaded: 'tiktok',
}
const stagingMessagePrefix = 'Nichtöffentlicher Upload-Testlauf:'
const identifierPattern = /^[a-z0-9][a-z0-9._-]{2,199}$/i

const isRecord = value => typeof value === 'object' && value !== null && !Array.isArray(value)

const requiredRecord = (value, path) => {
  if (!isRecord(value)) throw new Error(`${path} muss ein Objekt sein.`)
  return value
}

const requiredArray = (value, path, maximum) => {
  if (!Array.isArray(value)) throw new Error(`${path} muss eine Liste sein.`)
  if (value.length > maximum) throw new Error(`${path} enthält zu viele Einträge.`)
  return value
}

const requiredString = (value, path, maximum = 240) => {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${path} muss ein nicht-leerer Text sein.`)
  const text = value.trim()
  if (text.length > maximum) throw new Error(`${path} ist zu lang.`)
  return text
}

const requiredIdentifier = (value, path) => {
  const identifier = requiredString(value, path, 200)
  if (!identifierPattern.test(identifier)) throw new Error(`${path} enthält unerlaubte Zeichen.`)
  return identifier
}

const requiredIso = (value, path) => {
  const text = requiredString(value, path, 60)
  const timestamp = new Date(text)
  if (Number.isNaN(timestamp.valueOf())) throw new Error(`${path} muss ein gültiger ISO-Zeitpunkt sein.`)
  return timestamp.toISOString()
}

const nullableIso = (value, path) => value === null ? null : requiredIso(value, path)

const requireNullWhenPresent = (record, key, path) => {
  if (key in record && record[key] !== null) throw new Error(`${path}.${key} muss für den nichtöffentlichen Testlauf null sein.`)
}

const normalizeRunStatus = (value, path) => {
  const raw = requiredString(value, path, 40).toLowerCase()
  const aliases = {
    planned: 'queued',
    safety_violation: 'failed',
  }
  const status = aliases[raw] ?? raw
  if (!runStatuses.has(status)) throw new Error(`${path} enthält einen unbekannten Status.`)
  return status
}

const normalizePublicationStatus = (record, platform, path) => {
  const rawStatus = requiredString(record.status, `${path}.status`, 40).toLowerCase()
  const mode = record.mode === undefined ? null : requiredString(record.mode, `${path}.mode`, 40).toLowerCase()
  if (mode !== null && mode !== expectedMode[platform]) throw new Error(`${path}.mode passt nicht zur Plattform.`)
  if (['published', 'scheduled', 'public'].includes(rawStatus)) {
    throw new Error(`${path}.status darf im nichtöffentlichen Testlauf keine Veröffentlichung melden.`)
  }
  if (rawStatus === 'private_uploaded') {
    if (platform !== 'youtube') throw new Error(`${path}.status passt nicht zur Plattform.`)
    return 'private'
  }
  if (rawStatus === 'safety_violation') return 'failed'
  if (rawStatus === 'ready' && mode !== null) return mode
  if (rawStatus === 'ready') return expectedMode[platform]
  if (finalPublicationStatuses.has(rawStatus)) {
    if (platformForFinalStatus[rawStatus] !== platform) throw new Error(`${path}.status passt nicht zur Plattform.`)
    return rawStatus
  }
  if (passthroughPublicationStatuses.has(rawStatus)) return rawStatus
  throw new Error(`${path}.status enthält einen unbekannten Status.`)
}

const normalizeRun = (value, index) => {
  const path = `runs[${index}]`
  const record = requiredRecord(value, path)
  if ('title' in record && record.title !== null) throw new Error(`${path}.title darf für unveröffentlichte Inhalte nicht ausgegeben werden.`)
  if ('publicationAuthorized' in record && record.publicationAuthorized !== false) {
    throw new Error(`${path}.publicationAuthorized muss false sein.`)
  }
  const startedAt = requiredIso(record.createdAt ?? record.startedAt, `${path}.createdAt`)
  const completedAt = nullableIso(record.completedAt ?? null, `${path}.completedAt`)
  if (completedAt !== null && completedAt < startedAt) throw new Error(`${path}.completedAt liegt vor dem Start.`)
  const qualityStatus = requiredString(record.qualityStatus, `${path}.qualityStatus`, 20).toLowerCase()
  if (!qualityStatuses.has(qualityStatus)) throw new Error(`${path}.qualityStatus enthält einen unbekannten Status.`)
  return {
    runId: requiredIdentifier(record.runId, `${path}.runId`),
    contentId: requiredIdentifier(record.contentId, `${path}.contentId`),
    title: null,
    status: normalizeRunStatus(record.status, `${path}.status`),
    qualityStatus,
    startedAt,
    completedAt,
  }
}

const normalizePublication = (value, index, runs, runsByContentId) => {
  const path = `publications[${index}]`
  const record = requiredRecord(value, path)
  const contentId = requiredIdentifier(record.contentId, `${path}.contentId`)
  const platform = requiredString(record.platform, `${path}.platform`, 20).toLowerCase()
  if (!platformSet.has(platform)) throw new Error(`${path}.platform ist unbekannt.`)
  const mode = record.mode === undefined
    ? expectedMode[platform]
    : requiredString(record.mode, `${path}.mode`, 40).toLowerCase()
  if (mode !== expectedMode[platform]) throw new Error(`${path}.mode passt nicht zur Plattform.`)
  if ('title' in record && record.title !== null) throw new Error(`${path}.title darf für unveröffentlichte Inhalte nicht ausgegeben werden.`)
  if ('visibilityState' in record && record.visibilityState !== 'non_public') {
    throw new Error(`${path}.visibilityState muss non_public sein.`)
  }
  for (const key of ['scheduledAt', 'publishedAt', 'publicUrl']) requireNullWhenPresent(record, key, path)

  const candidates = runsByContentId.get(contentId) ?? []
  const runId = record.runId === undefined
    ? candidates.length === 1 ? candidates[0].runId : null
    : requiredIdentifier(record.runId, `${path}.runId`)
  const run = runId === null ? null : runs.find(entry => entry.runId === runId)
  if (!run || run.contentId !== contentId) throw new Error(`${path} verweist auf keinen passenden Lauf.`)
  const updatedAt = 'updatedAt' in record
    ? requiredIso(record.updatedAt, `${path}.updatedAt`)
    : run.startedAt
  if (updatedAt < run.startedAt) throw new Error(`${path}.updatedAt liegt vor dem Start des Laufs.`)

  return {
    runId,
    publicValue: {
      runId,
      contentId,
      platform,
      mode,
      status: normalizePublicationStatus(record, platform, path),
      updatedAt,
      title: null,
      scheduledAt: null,
      publishedAt: null,
      publicUrl: null,
    },
  }
}

export function normalizeStagingFeed(value) {
  const root = requiredRecord(value, 'staging-feed')
  if (root.schemaVersion !== 1) throw new Error('Unbekannte Staging-Feed-Schemaversion.')
  if ('lane' in root && root.lane !== 'non-publishing') throw new Error('Der Feed gehört nicht zur nichtöffentlichen Staging-Lane.')
  if ('publicationAuthorized' in root && root.publicationAuthorized !== false) {
    throw new Error('Der Staging-Feed darf keine Veröffentlichung autorisieren.')
  }
  const generatedAt = requiredIso(root.generatedAt, 'generatedAt')
  const runs = requiredArray(root.runs, 'runs', 100).map(normalizeRun)
  const runIds = new Set()
  const runsByContentId = new Map()
  for (const run of runs) {
    if (runIds.has(run.runId)) throw new Error(`Lauf ${run.runId} ist doppelt.`)
    runIds.add(run.runId)
    const matchingRuns = runsByContentId.get(run.contentId) ?? []
    matchingRuns.push(run)
    runsByContentId.set(run.contentId, matchingRuns)
  }

  const normalizedPublications = requiredArray(root.publications, 'publications', 400)
    .map((entry, index) => normalizePublication(entry, index, runs, runsByContentId))
  const keys = new Set()
  const platformsByRun = new Map()
  for (const publication of normalizedPublications) {
    const key = `${publication.runId}:${publication.publicValue.platform}`
    if (keys.has(key)) throw new Error(`Plattformstatus ${key} ist doppelt.`)
    keys.add(key)
    const found = platformsByRun.get(publication.runId) ?? new Set()
    found.add(publication.publicValue.platform)
    platformsByRun.set(publication.runId, found)
  }
  for (const run of runs) {
    const found = platformsByRun.get(run.runId) ?? new Set()
    if (platforms.some(platform => !found.has(platform))) {
      throw new Error(`Lauf ${run.runId} enthält nicht alle vier Plattformstatus.`)
    }
  }

  const runOrder = new Map([...runs]
    .sort((left, right) => right.startedAt.localeCompare(left.startedAt))
    .map((run, index) => [run.runId, index]))
  const platformOrder = new Map(platforms.map((platform, index) => [platform, index]))
  const publications = normalizedPublications
    .sort((left, right) => (runOrder.get(left.runId) ?? 0) - (runOrder.get(right.runId) ?? 0)
      || (platformOrder.get(left.publicValue.platform) ?? 0) - (platformOrder.get(right.publicValue.platform) ?? 0))
    .map(entry => entry.publicValue)

  return {
    generatedAt,
    runs: [...runs].sort((left, right) => right.startedAt.localeCompare(left.startedAt)),
    publications,
  }
}

const platformReason = status => ({
  private: 'Privater YouTube-Testupload bestätigt; keine Veröffentlichung autorisiert.',
  draft: 'Facebook-Entwurf bestätigt; keine Veröffentlichung autorisiert.',
  container_unpublished: 'Instagram-Container ist upload-bereit und bleibt unveröffentlicht.',
  upload_ready: 'Instagram-Container ist upload-bereit und bleibt unveröffentlicht.',
  manual_uploaded: 'Manueller TikTok-Upload bestätigt; Veröffentlichung bleibt unbestätigt.',
  expired: 'Das nichtöffentliche Staging-Objekt ist abgelaufen.',
  reconcile_required: 'Das Remote-Ergebnis ist unklar und muss vor einem neuen Versuch abgestimmt werden.',
  uploading: 'Der nichtöffentliche Testupload läuft.',
  processing: 'Die Plattform verarbeitet den nichtöffentlichen Testupload.',
  planned: 'Der nichtöffentliche Testupload ist vorbereitet.',
  failed: 'Der nichtöffentliche Testupload ist fehlgeschlagen.',
  ready: 'Der nichtöffentliche Testupload ist bereit.',
}[status] ?? 'Nichtöffentlicher Plattformstatus wurde aktualisiert.')

const summaryStatus = status => {
  if (['failed', 'expired', 'reconcile_required'].includes(status)) return 'failed'
  if (['uploading', 'processing'].includes(status)) return 'uploading'
  if (status === 'planned') return 'planned'
  return 'ready'
}

const confirmedUploadStatus = status => finalPublicationStatuses.has(status)

const contentDataStatus = runs => {
  if (runs.some(run => ['failed', 'qa_failed', 'reconcile_required'].includes(run.status))) return 'error'
  return runs.length > 0 && runs.every(run => run.status === 'completed') ? 'ok' : 'partial'
}

export function mergeStagingFeed(previous, staging) {
  const base = requiredRecord(previous, 'content-operations')
  if (base.schemaVersion !== 1) throw new Error('Unbekannte Content-Operations-Schemaversion.')
  const previousPlatforms = requiredArray(base.platforms, 'content-operations.platforms', 4)
  const byPlatform = new Map(previousPlatforms.map(entry => [entry.platform, entry]))
  const platformSummaries = platforms.map(platform => {
    const prior = requiredRecord(byPlatform.get(platform), `content-operations.platforms.${platform}`)
    const matching = staging.publications.filter(entry => entry.platform === platform)
    if (matching.length === 0) return prior
    const latest = matching[0]
    return {
      ...prior,
      status: summaryStatus(latest.status),
      uploads: matching.filter(entry => confirmedUploadStatus(entry.status)).length,
      publications: 0,
      reason: platformReason(latest.status),
      updatedAt: latest.updatedAt,
    }
  })
  const messages = requiredArray(base.messages, 'content-operations.messages', 100)
    .filter(message => typeof message === 'string' && !message.startsWith(stagingMessagePrefix))
  if (staging.runs.length > 0) {
    messages.push(`${stagingMessagePrefix} ${staging.runs.length} Lauf/Läufe mit ${staging.publications.length} sicheren Plattformstatus; keine Veröffentlichung autorisiert.`)
  }
  return {
    ...base,
    generatedAt: staging.generatedAt,
    status: staging.runs.length > 0 ? contentDataStatus(staging.runs) : base.status,
    messages,
    platforms: platformSummaries,
    runs: staging.runs,
    publications: staging.publications,
  }
}

export function stagingFeedUrl(env = process.env) {
  const direct = env.UPLOAD_STAGING_FEED_URL?.trim()
  const base = env.UPLOAD_STAGING_API_URL?.trim()
  if (!direct && !base) return null
  const url = new URL(direct || '/staging/feed', direct ? undefined : base)
  if (url.protocol !== 'https:' || url.username || url.password || !url.pathname.endsWith('/staging/feed')) {
    throw new Error('UPLOAD_STAGING_FEED_URL muss auf einen öffentlichen HTTPS-/staging/feed-Endpunkt zeigen.')
  }
  url.hash = ''
  return url.toString()
}

export async function fetchStagingFeed(url, fetchImpl = fetch) {
  const response = await fetchImpl(url, {
    headers: { accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  })
  if (!response.ok) throw new Error(`Staging-Feed antwortet mit HTTP ${response.status}.`)
  const text = await response.text()
  if (text.length > 1_000_000) throw new Error('Staging-Feed ist unerwartet groß.')
  let payload
  try {
    payload = JSON.parse(text)
  } catch {
    throw new Error('Staging-Feed enthält kein gültiges JSON.')
  }
  return normalizeStagingFeed(payload)
}

const loadPrevious = async () => JSON.parse(await readFile(outputUrl, 'utf8'))

const writeAtomically = async payload => {
  const temporaryUrl = new URL(`./content-operations-${process.pid}-${Date.now()}.json`, outputUrl)
  await writeFile(temporaryUrl, `${JSON.stringify(payload, null, 2)}\n`)
  await rename(temporaryUrl, outputUrl)
}

export async function collectContentOperations({ env = process.env, fetchImpl = fetch } = {}) {
  const url = stagingFeedUrl(env)
  if (url === null) return { updated: false, reason: 'not_configured' }
  const previous = await loadPrevious()
  const staging = await fetchStagingFeed(url, fetchImpl)
  const payload = mergeStagingFeed(previous, staging)
  await writeAtomically(payload)
  return { updated: true, payload }
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  collectContentOperations().then(result => {
    if (!result.updated) console.log('Öffentlicher Upload-Staging-Feed ist nicht konfiguriert; sicherer Snapshot bleibt unverändert.')
  }).catch(error => {
    console.error(`Content-Operations-Collector fehlgeschlagen: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}
