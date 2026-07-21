import { createHash } from 'node:crypto'

export const STAGING_SCHEMA_VERSION = 1
export const STAGING_PLATFORMS = ['youtube', 'instagram', 'facebook', 'tiktok']

export const STAGING_MODES = Object.freeze({
  youtube: 'private',
  instagram: 'container_unpublished',
  facebook: 'draft',
  tiktok: 'manual_uploaded',
})

const APP_STORE_URL = 'https://apps.apple.com/us/app/flaggenbande/id6778848528'
const COMPLETED_WORKFLOWS = new Set(['private_uploaded', 'container_unpublished', 'draft', 'manual_uploaded'])

const isRecord = value => typeof value === 'object' && value !== null && !Array.isArray(value)
const normalizedString = (value, name) => {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name} muss ein nicht-leerer Text sein.`)
  return value.trim()
}

const uniqueHashtags = value => {
  const seen = new Set()
  const result = []
  for (const hashtag of String(value).match(/#[\p{L}\p{N}_]+/gu) ?? []) {
    const canonical = hashtag.toLocaleLowerCase('en')
    if (seen.has(canonical)) continue
    seen.add(canonical)
    result.push(hashtag)
  }
  return result
}

const answerAppears = (copy, answer) => {
  const escaped = answer.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return new RegExp(`(?:^|[^\\p{L}\\p{N}])${escaped}(?:$|[^\\p{L}\\p{N}])`, 'iu').test(copy)
}

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

export function sha256(value) {
  return createHash('sha256').update(value).digest('hex')
}

export function remoteAccountFingerprint(platform, accountId) {
  return sha256(canonicalJson({
    platform: normalizedString(platform, 'platform'),
    accountId: normalizedString(accountId, 'accountId'),
  }))
}

export function validatePlatformMetadata(value) {
  if (!isRecord(value)) throw new Error('Die Plattformmetadaten müssen ein Objekt sein.')
  const youtubeTitle = normalizedString(value.youtubeTitle, 'youtubeTitle')
  const description = normalizedString(value.description, 'description')
  const language = normalizedString(value.language, 'language')
  if (youtubeTitle.length > 100) throw new Error('Der YouTube-Titel darf höchstens 100 Zeichen enthalten.')
  if (description.length > 2_200) throw new Error('Die gemeinsame Plattformbeschreibung darf höchstens 2.200 Zeichen enthalten.')
  if (language.toLowerCase() !== 'en') throw new Error('Der Testlauf benötigt englische Metadaten.')
  const titleHashtags = uniqueHashtags(youtubeTitle)
  const descriptionHashtags = uniqueHashtags(description)
  if (titleHashtags.length !== 5) throw new Error('Der YouTube-Titel muss exakt fünf eindeutige Hashtags enthalten.')
  if (descriptionHashtags.length !== 5) throw new Error('Die Beschreibung muss exakt fünf eindeutige Hashtags enthalten.')
  const lastLine = description.split(/\r?\n/).map(line => line.trim()).filter(Boolean).at(-1)
  if (lastLine !== APP_STORE_URL) throw new Error('Der App-Store-Link muss die letzte nicht-leere Zeile der Beschreibung sein.')
  const forbiddenAnswers = Array.isArray(value.forbiddenAnswerTerms)
    ? value.forbiddenAnswerTerms.map(term => normalizedString(term, 'forbiddenAnswerTerms[]'))
    : []
  const searchableCopy = `${youtubeTitle}\n${description}`
  const leaked = forbiddenAnswers.filter(term => answerAppears(searchableCopy, term))
  if (leaked.length > 0) throw new Error('Die Plattformtexte verraten mindestens eine Quizantwort.')

  // Answer terms are private QA input. They must never enter plans, receipts,
  // dashboard files or idempotency hashes.
  return {
    youtubeTitle,
    description,
    language: 'en',
    hashtags: descriptionHashtags,
  }
}

export function createContentId(assetSha256) {
  if (!/^[a-f0-9]{64}$/i.test(assetSha256)) throw new Error('assetSha256 ist ungültig.')
  return `flaggenbande-${assetSha256.toLowerCase()}`
}

export function createIdempotencyKey({ platform, accountFingerprint, assetSha256, mode }) {
  if (!STAGING_PLATFORMS.includes(platform)) throw new Error(`Unbekannte Plattform: ${platform}`)
  const account = normalizedString(accountFingerprint, 'accountFingerprint')
  if (!/^[a-f0-9]{64}$/i.test(assetSha256)) throw new Error('assetSha256 ist ungültig.')
  if (STAGING_MODES[platform] !== mode) throw new Error(`Unerlaubter Stagingmodus für ${platform}.`)
  // Visible copy may be corrected without creating another remote video. The
  // content bytes, destination account and non-publishing mode define identity.
  return sha256(canonicalJson({
    schemaVersion: STAGING_SCHEMA_VERSION,
    lane: 'non-publishing',
    platform,
    accountFingerprint: account,
    assetSha256: assetSha256.toLowerCase(),
    mode,
  }))
}

export function assertSafeYouTubeInsert(body) {
  if (!isRecord(body) || !isRecord(body.status)) throw new Error('YouTube-Insert ist unvollständig.')
  if (body.status.privacyStatus !== 'private') throw new Error('YouTube-Staging darf ausschließlich privat hochladen.')
  if ('publishAt' in body.status) throw new Error('YouTube-Staging darf keinen Veröffentlichungszeitpunkt setzen.')
  return body
}

export function facebookDraftFinishPayload({ videoId, title, description }) {
  return {
    video_id: normalizedString(videoId, 'videoId'),
    upload_phase: 'finish',
    video_state: 'DRAFT',
    title: normalizedString(title, 'title'),
    description: normalizedString(description, 'description'),
  }
}

export function instagramContainerPayload({ mediaUrl, description }) {
  const parsed = new URL(normalizedString(mediaUrl, 'mediaUrl'))
  if (parsed.protocol !== 'https:') throw new Error('Instagram benötigt eine HTTPS-Medienadresse.')
  return {
    media_type: 'REELS',
    video_url: parsed.toString(),
    caption: normalizedString(description, 'description'),
  }
}

export function validateManualTikTokReceipt(value) {
  if (!isRecord(value) || value.confirmedManualUpload !== true) return null
  const accountFingerprint = normalizedString(value.accountFingerprint, 'tiktok.accountFingerprint')
  const confirmedAt = normalizedString(value.confirmedAt, 'tiktok.confirmedAt')
  if (!Number.isFinite(Date.parse(confirmedAt))) throw new Error('tiktok.confirmedAt ist kein gültiger Zeitpunkt.')
  return {
    platform: 'tiktok',
    workflowState: 'manual_uploaded',
    transportState: 'ready',
    visibilityState: 'unknown',
    evidence: 'user_confirmed',
    accountFingerprint,
    confirmedAt: new Date(confirmedAt).toISOString(),
    remoteObjectId: typeof value.platformVideoId === 'string' && value.platformVideoId.trim()
      ? value.platformVideoId.trim()
      : null,
    publishedAt: null,
    scheduledFor: null,
    publicUrl: null,
  }
}

export function assertNonPublishingReceipt(receipt) {
  if (!isRecord(receipt)) throw new Error('Upload-Receipt muss ein Objekt sein.')
  if (!STAGING_PLATFORMS.includes(receipt.platform)) throw new Error('Upload-Receipt enthält eine unbekannte Plattform.')
  if (receipt.visibilityState !== 'non_public') throw new Error('Nichtöffentlicher Testlauf meldet eine unerlaubte Sichtbarkeit.')
  if (receipt.publishedAt !== null || receipt.scheduledFor !== null || receipt.publicUrl !== null) {
    throw new Error('Nichtöffentlicher Testlauf darf keine Veröffentlichung melden.')
  }
  if (receipt.transportState !== 'ready') throw new Error('Ein bestätigter Staging-Beleg muss transportState=ready melden.')
  if (typeof receipt.remoteObjectId !== 'string' || !receipt.remoteObjectId.trim()) {
    throw new Error('Ein bestätigter Staging-Beleg benötigt eine Remote-Objekt-ID.')
  }
  if (typeof receipt.confirmedAt !== 'string' || !Number.isFinite(Date.parse(receipt.confirmedAt))) {
    throw new Error('Ein bestätigter Staging-Beleg benötigt einen gültigen Bestätigungszeitpunkt.')
  }
  const allowed = {
    youtube: ['private_uploaded'],
    instagram: ['container_unpublished'],
    facebook: ['draft'],
    tiktok: [],
  }
  if (!allowed[receipt.platform].includes(receipt.workflowState)) {
    throw new Error(`Unerlaubter Stagingstatus für ${receipt.platform}.`)
  }
  const expectedProviderStatus = { youtube: 'PRIVATE', instagram: 'FINISHED', facebook: 'DRAFT' }
  if (String(receipt.providerStatus ?? '').toUpperCase() !== expectedProviderStatus[receipt.platform]) {
    throw new Error(`Der Providerstatus bestätigt ${receipt.platform} nicht sicher.`)
  }
  return receipt
}

export function buildStagingPlan({ runId, assetSha256, metadata, accountFingerprints, createdAt, manualTikTokReceipt }) {
  const checkedMetadata = validatePlatformMetadata(metadata)
  const metadataSha256 = sha256(canonicalJson(checkedMetadata))
  const contentId = createContentId(assetSha256)
  const manualTikTok = validateManualTikTokReceipt(manualTikTokReceipt)
  const expectedTikTokAccount = normalizedString(accountFingerprints.tiktok, 'accountFingerprints.tiktok')
  if (manualTikTok && manualTikTok.accountFingerprint !== expectedTikTokAccount) {
    throw new Error('Die manuelle TikTok-Bestätigung gehört nicht zum geplanten Zielkonto.')
  }
  const targets = STAGING_PLATFORMS.map(platform => {
    const accountFingerprint = normalizedString(accountFingerprints[platform], `accountFingerprints.${platform}`)
    const mode = STAGING_MODES[platform]
    return {
      platform,
      mode,
      accountFingerprint,
      idempotencyKey: createIdempotencyKey({ platform, accountFingerprint, assetSha256, mode }),
      transportState: platform === 'tiktok' && manualTikTok ? 'ready' : 'planned',
      visibilityState: platform === 'tiktok' && manualTikTok ? 'unknown' : 'not_created',
      workflowState: platform === 'tiktok' && manualTikTok ? 'manual_uploaded' : 'ready',
      publishedAt: null,
      scheduledFor: null,
      publicUrl: null,
    }
  })
  return {
    schemaVersion: STAGING_SCHEMA_VERSION,
    lane: 'non-publishing',
    runId: normalizedString(runId, 'runId'),
    contentId,
    assetSha256: assetSha256.toLowerCase(),
    metadataSha256,
    createdAt: normalizedString(createdAt, 'createdAt'),
    qualityStatus: 'passed',
    publicationAuthorized: false,
    metadata: checkedMetadata,
    targets,
    manualReceipts: manualTikTok ? [manualTikTok] : [],
  }
}

export function validateStagingApiBaseUrl(value, allowedHost = null) {
  let url
  try {
    url = new URL(normalizedString(value, 'UPLOAD_STAGING_API_URL'))
  } catch {
    throw new Error('UPLOAD_STAGING_API_URL ist keine gültige URL.')
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
    throw new Error('UPLOAD_STAGING_API_URL muss eine reine HTTPS-Adresse ohne Zugangsdaten, Query oder Fragment sein.')
  }
  const expectedHost = typeof allowedHost === 'string' && allowedHost.trim() ? allowedHost.trim().toLowerCase() : null
  if (expectedHost ? url.hostname.toLowerCase() !== expectedHost : !url.hostname.toLowerCase().endsWith('.workers.dev')) {
    throw new Error('UPLOAD_STAGING_API_URL gehört nicht zum freigegebenen Cloudflare-Worker-Host.')
  }
  return url.origin
}

export function validateStagingRegistration(plan, value) {
  if (!isRecord(value) || value.schemaVersion !== STAGING_SCHEMA_VERSION || value.lane !== 'non-publishing') {
    throw new Error('Der Dashboard-Testlauf lieferte kein gültiges Staging-Schema.')
  }
  if (value.runId !== plan.runId || value.contentId !== plan.contentId || value.qualityStatus !== 'passed') {
    throw new Error('Der Dashboard-Testlauf bestätigt nicht exakt den geprüften Lauf.')
  }
  if (!['planned', 'partial'].includes(value.status) || !Array.isArray(value.targets) || value.targets.length !== STAGING_PLATFORMS.length) {
    throw new Error('Der Dashboard-Testlauf meldet keinen sicheren, unveränderten Planstatus.')
  }
  const expectedByPlatform = new Map(plan.targets.map(target => [target.platform, target]))
  const seenPlatforms = new Set()
  const seenKeys = new Set()
  for (const target of value.targets) {
    if (!isRecord(target) || !STAGING_PLATFORMS.includes(target.platform) || seenPlatforms.has(target.platform)) {
      throw new Error('Der Dashboard-Testlauf enthält unbekannte oder doppelte Plattformziele.')
    }
    const expected = expectedByPlatform.get(target.platform)
    if (!expected || target.mode !== expected.mode || target.transportState !== expected.transportState ||
        target.visibilityState !== expected.visibilityState || target.workflowState !== expected.workflowState) {
      throw new Error(`Der Dashboard-Testlauf meldet für ${target.platform} keinen unveränderten Planstatus.`)
    }
    if (typeof target.idempotencyKey !== 'string' || !/^[a-f0-9]{64}$/i.test(target.idempotencyKey) || seenKeys.has(target.idempotencyKey)) {
      throw new Error('Der Dashboard-Testlauf enthält keinen eindeutigen Server-Idempotenzschlüssel.')
    }
    if (target.remoteObjectId != null || target.providerStatus != null || target.publishedAt != null ||
        target.scheduledFor != null || target.publicUrl != null) {
      throw new Error('Die reine Dashboard-Registrierung meldet unerwartet ein Plattformobjekt oder eine Veröffentlichung.')
    }
    seenPlatforms.add(target.platform)
    seenKeys.add(target.idempotencyKey)
  }
  return value
}

function targetPublicStatus(target, receipt) {
  const workflow = receipt?.workflowState ?? target.workflowState
  const transport = receipt?.transportState ?? target.transportState
  if (workflow === 'private_uploaded') return 'private'
  if (workflow === 'draft') return 'draft'
  if (workflow === 'container_unpublished') return 'container_unpublished'
  if (workflow === 'manual_uploaded') return 'manual_uploaded'
  if (workflow === 'reconcile_required' || transport === 'reconcile_required') return 'reconcile_required'
  if (workflow === 'expired' || transport === 'expired') return 'expired'
  if (workflow === 'failed' || workflow === 'safety_violation' || transport === 'failed') return 'failed'
  if (transport === 'uploading' || transport === 'processing') return 'uploading'
  if (transport === 'planned') return 'planned'
  return 'ready'
}

export function publicStagingSnapshot(record) {
  const plan = record.plan ?? record
  const receipts = [...(plan.manualReceipts ?? []), ...(record.execution?.receipts ?? [])]
  const byPlatform = new Map(receipts.map(receipt => [receipt.platform, receipt]))
  const statuses = plan.targets.map(target => targetPublicStatus(target, byPlatform.get(target.platform)))
  const failed = statuses.some(status => ['failed', 'expired', 'reconcile_required'].includes(status))
  const completed = plan.targets.every(target => COMPLETED_WORKFLOWS.has(byPlatform.get(target.platform)?.workflowState))
  const active = statuses.some(status => status === 'uploading')
  return {
    schemaVersion: STAGING_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    runs: [{
      runId: plan.runId,
      contentId: plan.contentId,
      title: null,
      status: failed ? 'failed' : completed ? 'completed' : active ? 'running' : 'ready',
      qualityStatus: plan.qualityStatus,
      startedAt: plan.createdAt,
      completedAt: completed ? record.execution?.completedAt ?? null : null,
    }],
    publications: plan.targets.map(target => ({
      contentId: plan.contentId,
      platform: target.platform,
      status: targetPublicStatus(target, byPlatform.get(target.platform)),
      title: null,
      scheduledAt: null,
      publishedAt: null,
      publicUrl: null,
    })),
  }
}

export const FLAGGENBANDE_APP_STORE_URL = APP_STORE_URL
