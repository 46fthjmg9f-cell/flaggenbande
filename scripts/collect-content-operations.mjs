import { readFile, rename, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const outputUrl = new URL('../dashboard/public/data/content-operations.json', import.meta.url)
const dashboardDataUrl = new URL('../dashboard/public/data/dashboard.json', import.meta.url)
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
const stagingMessagePrefix = 'Nichtöffentlicher Testlauf zum Hochladen:'
const legacyStagingMessagePrefix = 'Nichtöffentlicher Upload-Testlauf:'
const identifierPattern = /^[a-z0-9][a-z0-9._-]{2,199}$/i
const publishedSocialStatuses = new Set(['public', 'published'])
const corePlatforms = ['youtube', 'instagram', 'facebook']
const productionPlatforms = new Set(['instagram', 'facebook'])
const productionPublicationStatuses = new Set(['scheduled', 'processing', 'waiting_for_meta', 'published', 'failed'])
const publicationFailureCodes = new Set([
  'api_access_blocked',
  'authentication_failed',
  'permission_denied',
  'rate_limited',
  'media_unavailable',
  'processing_timeout',
  'platform_rejected',
  'unknown',
])
const productionMessagePrefix = 'Produktions-Queue:'

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

const normalizeProductionPublication = (value, index) => {
  const path = `production-publications[${index}]`
  const record = requiredRecord(value, path)
  const platform = requiredString(record.platform, `${path}.platform`, 20).toLowerCase()
  if (!productionPlatforms.has(platform)) throw new Error(`${path}.platform ist unbekannt.`)
  const status = requiredString(record.status, `${path}.status`, 40).toLowerCase()
  if (!productionPublicationStatuses.has(status)) throw new Error(`${path}.status ist unbekannt.`)
  const failureCode = record.failureCode === null
    ? null
    : requiredString(record.failureCode, `${path}.failureCode`, 60).toLowerCase()
  if (failureCode !== null && !publicationFailureCodes.has(failureCode)) {
    throw new Error(`${path}.failureCode ist unbekannt.`)
  }
  if (status === 'failed' && failureCode === null) throw new Error(`${path}.failureCode fehlt.`)
  if (status !== 'failed' && failureCode !== null) throw new Error(`${path}.failureCode ist nur bei Fehlern zulässig.`)
  const publishedAt = nullableIso(record.publishedAt, `${path}.publishedAt`)
  if (status === 'published' && publishedAt === null) throw new Error(`${path}.publishedAt fehlt.`)
  if (status !== 'published' && publishedAt !== null) throw new Error(`${path}.publishedAt ist nur nach Veröffentlichung zulässig.`)
  const rawPublicUrl = record.publicUrl ?? null
  const publicUrl = rawPublicUrl === null ? null : validPublicUrl(rawPublicUrl, platform)
  if (rawPublicUrl !== null && publicUrl === null) throw new Error(`${path}.publicUrl ist keine gültige öffentliche Plattform-URL.`)
  if (status === 'published' && publicUrl === null) throw new Error(`${path}.publicUrl fehlt.`)
  if (status !== 'published' && publicUrl !== null) throw new Error(`${path}.publicUrl ist nur nach Veröffentlichung zulässig.`)
  return {
    contentId: requiredIdentifier(record.contentId, `${path}.contentId`),
    platform,
    status,
    scheduledAt: requiredIso(record.scheduledAt, `${path}.scheduledAt`),
    updatedAt: requiredIso(record.updatedAt, `${path}.updatedAt`),
    publishedAt,
    publicUrl,
    failureCode,
  }
}

export function normalizePublicationFeed(value) {
  const root = requiredRecord(value, 'publication-feed')
  if (root.schemaVersion !== 1) throw new Error('Unbekannte Publication-Feed-Schemaversion.')
  if (root.lane !== 'production-publication') throw new Error('Der Feed gehört nicht zur Produktions-Veröffentlichung.')
  const generatedAt = requiredIso(root.generatedAt, 'publication-feed.generatedAt')
  const publications = requiredArray(root.publications, 'publication-feed.publications', 400)
    .map(normalizeProductionPublication)
  return { generatedAt, publications }
}

const platformReason = status => ({
  private: 'Privates YouTube-Testvideo wurde hochgeladen; keine Veröffentlichung autorisiert.',
  draft: 'Facebook-Entwurf bestätigt; keine Veröffentlichung autorisiert.',
  container_unpublished: 'Der Instagram-Container ist zum Hochladen bereit und bleibt unveröffentlicht.',
  upload_ready: 'Der Instagram-Container ist zum Hochladen bereit und bleibt unveröffentlicht.',
  manual_uploaded: 'Das TikTok-Video wurde manuell hochgeladen; die Veröffentlichung bleibt unbestätigt.',
  expired: 'Das nichtöffentliche Testobjekt ist abgelaufen.',
  reconcile_required: 'Das Plattformergebnis ist unklar und muss vor einem neuen Versuch abgestimmt werden.',
  uploading: 'Das nichtöffentliche Testvideo wird hochgeladen.',
  processing: 'Die Plattform verarbeitet das nichtöffentliche Testvideo.',
  planned: 'Das nichtöffentliche Hochladen ist vorbereitet.',
  failed: 'Das nichtöffentliche Hochladen ist fehlgeschlagen.',
  ready: 'Das nichtöffentliche Hochladen ist bereit.',
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

const normalizeDescription = value => typeof value === 'string'
  ? value.normalize('NFKC').replace(/\s+/gu, ' ').trim()
  : ''

const validPublicUrl = (value, platform) => {
  if (typeof value !== 'string' || !value.trim()) return null
  let url
  try {
    url = new URL(value)
  } catch {
    return null
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) return null
  const hostname = url.hostname.toLowerCase()
  const pathname = url.pathname.toLowerCase()
  const pathSegments = url.pathname.split('/').filter(Boolean)
  const instagramPermalinkIndex = pathSegments.findIndex(segment => ['reel', 'p'].includes(segment.toLowerCase()))
  const validInstagramPath = (instagramPermalinkIndex === 0 || instagramPermalinkIndex === 1)
    && pathSegments.length === instagramPermalinkIndex + 2
    && (instagramPermalinkIndex === 0 || /^[a-z0-9._]+$/i.test(pathSegments[0]))
    && /^[a-z0-9_-]+$/i.test(pathSegments[instagramPermalinkIndex + 1])
  const facebookVideoId = url.searchParams.get('v')
  const validFacebookReelPath = /^\/reel\/[a-z0-9._-]+\/?$/i.test(url.pathname)
  const validFacebookVideoPath = /^\/(?:[a-z0-9._-]+\/)?videos\/[a-z0-9._-]+\/?$/i.test(url.pathname)
  const validFacebookWatchPath = /^\/watch\/?$/i.test(url.pathname)
    && typeof facebookVideoId === 'string' && /^[a-z0-9._-]+$/i.test(facebookVideoId)
  const valid = platform === 'youtube'
    ? ['youtube.com', 'www.youtube.com', 'm.youtube.com'].includes(hostname)
      && (pathname === '/watch' || pathname.startsWith('/shorts/'))
    : platform === 'instagram'
      ? ['instagram.com', 'www.instagram.com'].includes(hostname)
        && validInstagramPath
      : platform === 'facebook'
        ? (hostname === 'facebook.com' || hostname.endsWith('.facebook.com'))
          && (validFacebookReelPath || validFacebookVideoPath || validFacebookWatchPath)
        : platform === 'tiktok'
          ? (hostname === 'tiktok.com' || hostname.endsWith('.tiktok.com')) && pathname.includes('/video/')
          : false
  if (!valid) return null
  if (platform === 'instagram' || (platform === 'facebook' && !validFacebookWatchPath)) url.search = ''
  if (platform === 'facebook' && validFacebookWatchPath) url.search = `?v=${encodeURIComponent(facebookVideoId)}`
  url.hash = ''
  return url.toString()
}

const publishedSocialProof = value => {
  if (!isRecord(value)) return null
  const platform = typeof value.platform === 'string' ? value.platform.trim().toLowerCase() : ''
  if (!platformSet.has(platform)) return null
  const status = typeof value.status === 'string' ? value.status.trim().toLowerCase() : ''
  if (!publishedSocialStatuses.has(status)) return null
  const publicUrl = validPublicUrl(value.url, platform)
  if (publicUrl === null || typeof value.publishedAt !== 'string') return null
  const timestamp = new Date(value.publishedAt)
  if (Number.isNaN(timestamp.valueOf())) return null
  const title = typeof value.title === 'string' && value.title.trim()
    ? value.title.trim().slice(0, 240)
    : null
  const description = normalizeDescription(value.description)
  const contentId = typeof value.contentId === 'string' && identifierPattern.test(value.contentId.trim())
    ? value.contentId.trim()
    : null
  return {
    platform,
    status: 'published',
    contentId,
    title,
    description,
    publishedAt: timestamp.toISOString(),
    publicUrl,
  }
}

const uniqueEntries = values => values.length === 1 ? values[0] : null

/**
 * Reconciles stale, non-public upload receipts with authoritative public platform
 * inventory. Every promotion is fail-closed: a valid platform URL, publication
 * time and unambiguous content association are all required.
 */
export function reconcilePublishedSocial(contentOperations, socialVideos) {
  const base = requiredRecord(contentOperations, 'content-operations')
  if (base.schemaVersion !== 1 || !Array.isArray(socialVideos)) return base
  const runs = requiredArray(base.runs, 'content-operations.runs', 100)
  const publications = requiredArray(base.publications, 'content-operations.publications', 400)
  const runIdsByContentId = new Map()
  for (const run of runs) {
    const runIds = runIdsByContentId.get(run.contentId) ?? new Set()
    runIds.add(run.runId)
    runIdsByContentId.set(run.contentId, runIds)
  }
  // A platform proof identifies content, not one specific production attempt.
  // If several runs share the content ID, applying the proof would be a guess.
  const unambiguousContentIds = new Set([...runIdsByContentId.entries()]
    .filter(([, runIds]) => runIds.size === 1)
    .map(([contentId]) => contentId))
  const proofs = socialVideos.map(publishedSocialProof).filter(Boolean)

  const metaIdsByDescription = new Map()
  for (const proof of proofs) {
    if (!['instagram', 'facebook'].includes(proof.platform) || proof.contentId === null || !unambiguousContentIds.has(proof.contentId) || !proof.description) continue
    const ids = metaIdsByDescription.get(proof.description) ?? new Set()
    ids.add(proof.contentId)
    metaIdsByDescription.set(proof.description, ids)
  }

  const associatedProofs = proofs.flatMap(proof => {
    if (proof.contentId !== null && unambiguousContentIds.has(proof.contentId)) return [{ ...proof, associatedContentId: proof.contentId }]
    if (proof.platform !== 'youtube' || !proof.description) return []
    const matchingIds = metaIdsByDescription.get(proof.description)
    if (!matchingIds || matchingIds.size !== 1) return []
    return [{ ...proof, associatedContentId: [...matchingIds][0] }]
  })
  if (associatedProofs.length === 0) return base

  const proofsByContentAndPlatform = new Map()
  for (const proof of associatedProofs) {
    const key = `${proof.associatedContentId}:${proof.platform}`
    const matching = proofsByContentAndPlatform.get(key) ?? []
    matching.push(proof)
    proofsByContentAndPlatform.set(key, matching)
  }
  const proofFor = (contentId, platform) => uniqueEntries(proofsByContentAndPlatform.get(`${contentId}:${platform}`) ?? [])

  const reconciledPublications = publications.map(publication => {
    const proof = proofFor(publication.contentId, publication.platform)
    if (proof === null) return publication
    return {
      ...publication,
      status: 'published',
      updatedAt: proof.publishedAt,
      title: proof.title,
      scheduledAt: null,
      publishedAt: proof.publishedAt,
      publicUrl: proof.publicUrl,
      failureCode: null,
    }
  })

  const publicationsByRun = new Map()
  for (const publication of reconciledPublications) {
    const entries = publicationsByRun.get(publication.runId) ?? []
    entries.push(publication)
    publicationsByRun.set(publication.runId, entries)
  }

  const reconciledRuns = runs.map(run => {
    const entries = publicationsByRun.get(run.runId) ?? []
    const core = corePlatforms.map(platform => entries.find(entry => entry.platform === platform))
    const corePublished = core.every(entry => entry?.status === 'published')
    if (!corePublished || run.qualityStatus !== 'passed') return run
    const completedAt = core.map(entry => entry.publishedAt).filter(Boolean).sort().at(-1)
    const preferredTitle = ['youtube', 'instagram', 'facebook']
      .map(platform => entries.find(entry => entry.platform === platform)?.title)
      .find(Boolean) ?? run.title
    return {
      ...run,
      title: preferredTitle,
      status: 'completed',
      completedAt: completedAt ?? run.completedAt,
    }
  })

  const completedRunIds = new Set(reconciledRuns.filter(run => run.status === 'completed').map(run => run.runId))
  const finalPublications = reconciledPublications.map(publication => publication.platform === 'tiktok'
    && publication.status === 'planned'
    && completedRunIds.has(publication.runId)
    ? {
        ...publication,
        status: 'not_configured',
        scheduledAt: null,
        publishedAt: null,
        publicUrl: null,
      }
    : publication)

  const platformSummaries = platforms.map(platform => {
    const prior = base.platforms.find(entry => entry.platform === platform)
    if (!prior) return null
    const matching = finalPublications.filter(entry => entry.platform === platform)
    const published = matching.filter(entry => entry.status === 'published')
    const latest = [...matching].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))[0]
    if (published.length > 0) {
      const latestPublished = [...published].sort((left, right) => right.publishedAt.localeCompare(left.publishedAt))[0]
      return {
        ...prior,
        status: 'published',
        uploads: matching.filter(entry => confirmedUploadStatus(entry.status) || entry.status === 'published').length,
        publications: published.length,
        reason: `${published.length} öffentliche ${published.length === 1 ? 'Veröffentlichung' : 'Veröffentlichungen'} bestätigt.`,
        updatedAt: latestPublished.publishedAt,
      }
    }
    if (platform === 'tiktok' && matching.some(entry => entry.status === 'not_configured')) {
      return {
        ...prior,
        status: 'not_configured',
        uploads: matching.filter(entry => confirmedUploadStatus(entry.status)).length,
        publications: 0,
        reason: 'Keine öffentliche TikTok-Veröffentlichung nachgewiesen.',
        updatedAt: latest?.updatedAt ?? prior.updatedAt,
      }
    }
    return prior
  }).filter(Boolean)

  const confirmedCount = finalPublications.filter(entry => entry.status === 'published').length
  const messages = requiredArray(base.messages, 'content-operations.messages', 100)
    .filter(message => typeof message === 'string' && !message.startsWith(stagingMessagePrefix) && !message.startsWith(legacyStagingMessagePrefix))
  if (confirmedCount > 0) messages.push(`${confirmedCount} öffentliche Plattformveröffentlichungen wurden eindeutig bestätigt.`)

  return {
    ...base,
    status: contentDataStatus(reconciledRuns),
    messages,
    platforms: platformSummaries,
    runs: reconciledRuns,
    publications: finalPublications,
  }
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
    .filter(message => typeof message === 'string' && !message.startsWith(stagingMessagePrefix) && !message.startsWith(legacyStagingMessagePrefix))
    .filter(message => staging.runs.length === 0 || !message.includes('Noch sind keine Upload-Adapter verbunden.'))
  if (staging.runs.length > 0) {
    const runCount = `${staging.runs.length} ${staging.runs.length === 1 ? 'Lauf' : 'Läufe'}`
    messages.push(`${stagingMessagePrefix} ${runCount} mit ${staging.publications.length} sicheren Plattformzuständen; keine Veröffentlichung autorisiert.`)
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

const productionPublicStatus = status => ({
  scheduled: 'planned',
  processing: 'processing',
  waiting_for_meta: 'processing',
  published: 'published',
  failed: 'failed',
}[status])

const productionPlatformStatus = status => ({
  scheduled: 'scheduled',
  processing: 'uploading',
  waiting_for_meta: 'uploading',
  published: 'published',
  failed: 'failed',
}[status])

const productionReason = publication => {
  if (publication.status === 'scheduled') return 'Cloud-Veröffentlichung ist eingeplant.'
  if (publication.status === 'processing') return 'Cloud-Veröffentlichung wird verarbeitet.'
  if (publication.status === 'waiting_for_meta') return 'Meta verarbeitet das Video.'
  if (publication.status === 'published') return 'Cloud-Veröffentlichung wurde bestätigt.'
  return `Cloud-Veröffentlichung ist fehlgeschlagen (${publication.failureCode}).`
}

/**
 * Overlays the non-publishing staging view with the live production queue.
 * Associations are deliberately fail-closed: exactly one run, one dashboard
 * target and one queue row must exist for a content/platform pair.
 */
export function mergePublicationFeed(contentOperations, production) {
  const base = requiredRecord(contentOperations, 'content-operations')
  if (base.schemaVersion !== 1) throw new Error('Unbekannte Content-Operations-Schemaversion.')
  const runs = requiredArray(base.runs, 'content-operations.runs', 100)
  const publications = requiredArray(base.publications, 'content-operations.publications', 400)

  const runsByContentId = new Map()
  for (const run of runs) {
    const entries = runsByContentId.get(run.contentId) ?? []
    entries.push(run)
    runsByContentId.set(run.contentId, entries)
  }
  const queueByContentAndPlatform = new Map()
  for (const publication of production.publications) {
    const key = `${publication.contentId}:${publication.platform}`
    const entries = queueByContentAndPlatform.get(key) ?? []
    entries.push(publication)
    queueByContentAndPlatform.set(key, entries)
  }
  const targetsByRunAndPlatform = new Map()
  for (const publication of publications) {
    const key = `${publication.runId}:${publication.platform}`
    const entries = targetsByRunAndPlatform.get(key) ?? []
    entries.push(publication)
    targetsByRunAndPlatform.set(key, entries)
  }

  const acceptedByRunAndPlatform = new Map()
  for (const [key, queueEntries] of queueByContentAndPlatform) {
    if (queueEntries.length !== 1) continue
    const queue = queueEntries[0]
    const matchingRuns = runsByContentId.get(queue.contentId) ?? []
    if (matchingRuns.length !== 1) continue
    const run = matchingRuns[0]
    const targetKey = `${run.runId}:${queue.platform}`
    if ((targetsByRunAndPlatform.get(targetKey) ?? []).length !== 1) continue
    acceptedByRunAndPlatform.set(targetKey, queue)
  }

  const overlaidPublications = publications.map(publication => {
    const queue = acceptedByRunAndPlatform.get(`${publication.runId}:${publication.platform}`)
    if (!queue) return publication
    const publicProof = publication.status === 'published'
      && publication.publishedAt
      && validPublicUrl(publication.publicUrl, publication.platform)
    if (publicProof) return publication
    return {
      ...publication,
      status: productionPublicStatus(queue.status),
      updatedAt: queue.updatedAt,
      scheduledAt: queue.scheduledAt,
      publishedAt: queue.publishedAt,
      publicUrl: queue.publicUrl,
      failureCode: queue.failureCode,
    }
  })

  const acceptedByRun = new Map()
  for (const [key, queue] of acceptedByRunAndPlatform) {
    const runId = key.slice(0, key.lastIndexOf(':'))
    const entries = acceptedByRun.get(runId) ?? []
    entries.push(queue)
    acceptedByRun.set(runId, entries)
  }
  const overlaidRuns = runs.map(run => {
    const entries = acceptedByRun.get(run.runId) ?? []
    if (entries.length === 0 || run.status === 'completed') return run
    if (entries.some(entry => entry.status === 'failed')) return { ...run, status: 'failed', completedAt: null }
    return { ...run, status: 'partial', completedAt: null }
  })

  const priorPlatforms = requiredArray(base.platforms, 'content-operations.platforms', 4)
  const platformSummaries = priorPlatforms.map(prior => {
    if (!productionPlatforms.has(prior.platform)) return prior
    const accepted = [...acceptedByRunAndPlatform.values()].filter(entry => entry.platform === prior.platform)
    if (accepted.length === 0) return prior
    const latest = [...accepted].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))[0]
    const matching = overlaidPublications.filter(entry => entry.platform === prior.platform)
    return {
      ...prior,
      status: productionPlatformStatus(latest.status),
      uploads: matching.filter(entry => entry.status === 'published').length,
      publications: matching.filter(entry => entry.status === 'published').length,
      reason: productionReason(latest),
      updatedAt: latest.updatedAt,
    }
  })

  const messages = requiredArray(base.messages, 'content-operations.messages', 100)
    .filter(message => typeof message === 'string' && !message.startsWith(productionMessagePrefix))
  if (acceptedByRunAndPlatform.size > 0) {
    const failed = [...acceptedByRunAndPlatform.values()].filter(entry => entry.status === 'failed').length
    messages.push(`${productionMessagePrefix} ${acceptedByRunAndPlatform.size} eindeutige Meta-Status${acceptedByRunAndPlatform.size === 1 ? '' : 'se'} übernommen; ${failed} fehlgeschlagen.`)
  }

  return {
    ...base,
    generatedAt: [base.generatedAt, production.generatedAt].filter(Boolean).sort().at(-1) ?? base.generatedAt,
    status: contentDataStatus(overlaidRuns),
    messages,
    platforms: platformSummaries,
    runs: overlaidRuns,
    publications: overlaidPublications,
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

export function publicationFeedUrl(env = process.env) {
  const direct = env.META_PUBLICATION_FEED_URL?.trim()
  const base = env.UPLOAD_STAGING_API_URL?.trim()
  const staging = env.UPLOAD_STAGING_FEED_URL?.trim()
  if (!direct && !base && !staging) return null
  let url
  if (direct) {
    url = new URL(direct)
  } else if (base) {
    url = new URL('/publication/feed', base)
  } else {
    url = new URL(staging)
    url.pathname = url.pathname.replace(/\/staging\/feed$/, '/publication/feed')
  }
  if (url.protocol !== 'https:' || url.username || url.password || !url.pathname.endsWith('/publication/feed')) {
    throw new Error('META_PUBLICATION_FEED_URL muss auf einen öffentlichen HTTPS-/publication/feed-Endpunkt zeigen.')
  }
  url.hash = ''
  return url.toString()
}

export async function fetchPublicationFeed(url, fetchImpl = fetch) {
  const response = await fetchImpl(url, {
    headers: { accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  })
  if (!response.ok) throw new Error(`Publication-Feed antwortet mit HTTP ${response.status}.`)
  const text = await response.text()
  if (text.length > 1_000_000) throw new Error('Publication-Feed ist unerwartet groß.')
  let payload
  try {
    payload = JSON.parse(text)
  } catch {
    throw new Error('Publication-Feed enthält kein gültiges JSON.')
  }
  return normalizePublicationFeed(payload)
}

const loadPrevious = async () => JSON.parse(await readFile(outputUrl, 'utf8'))

const loadSocialVideos = async () => {
  try {
    const text = await readFile(dashboardDataUrl, 'utf8')
    if (text.length > 10_000_000) return []
    const dashboard = JSON.parse(text)
    return isRecord(dashboard) && isRecord(dashboard.social) && Array.isArray(dashboard.social.videos)
      ? dashboard.social.videos.slice(0, 2_000)
      : []
  } catch {
    return []
  }
}

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
  const productionUrl = publicationFeedUrl(env)
  const production = productionUrl === null
    ? { generatedAt: staging.generatedAt, publications: [] }
    : await fetchPublicationFeed(productionUrl, fetchImpl)
  const staged = mergeStagingFeed(previous, staging)
  const queued = mergePublicationFeed(staged, production)
  const payload = reconcilePublishedSocial(queued, await loadSocialVideos())
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
