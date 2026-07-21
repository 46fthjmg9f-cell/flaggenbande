import { createReadStream } from 'node:fs'
import { access, mkdir, open, readFile, rename, stat, unlink, writeFile } from 'node:fs/promises'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { hostname } from 'node:os'
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import {
  assertNonPublishingReceipt,
  assertSafeYouTubeInsert,
  buildStagingPlan,
  publicStagingSnapshot,
  remoteAccountFingerprint,
  resolveExecutionErrors,
  validateStagingApiBaseUrl,
  validateStagingRegistration,
} from './upload-staging-core.mjs'

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const DEFAULT_STATE_DIR = resolve(REPOSITORY_ROOT, '.state/upload-staging')
const RETRYABLE_HTTP = new Set([429, 500, 502, 503, 504])

const errorMessage = error => error instanceof Error ? error.message : String(error)

function argumentsFrom(argv) {
  const value = name => {
    const direct = argv.find(argument => argument.startsWith(`${name}=`))
    if (direct) return direct.slice(name.length + 1)
    const index = argv.indexOf(name)
    return index >= 0 ? argv[index + 1] : null
  }
  const selectedPlatforms = (value('--platforms') ?? 'youtube,meta')
    .split(',').map(item => item.trim()).filter(Boolean)
  if (selectedPlatforms.length === 0) throw new Error('--platforms benötigt mindestens youtube oder meta.')
  if (selectedPlatforms.some(item => !['youtube', 'meta'].includes(item))) {
    throw new Error('--platforms erlaubt nur youtube, meta oder youtube,meta.')
  }
  const execute = argv.includes('--execute')
  const dryRun = argv.includes('--dry-run')
  const registerOnly = argv.includes('--register-only')
  if ([execute, dryRun, registerOnly].filter(Boolean).length > 1) {
    throw new Error('--execute, --register-only und --dry-run dürfen nicht gemeinsam verwendet werden.')
  }
  return {
    input: value('--input'),
    metadata: value('--metadata'),
    qualityReport: value('--quality-report'),
    output: value('--output'),
    publicOutput: value('--public-output'),
    stateDir: value('--state-dir') || process.env.UPLOAD_STAGING_STATE_DIR || DEFAULT_STATE_DIR,
    mediaUrl: value('--media-url'),
    mediaProject: value('--media-project'),
    mediaBranch: value('--media-branch'),
    selectedPlatforms,
    execute,
    registerOnly,
    dryRun,
  }
}

async function hashFile(path) {
  const hash = createHash('sha256')
  for await (const chunk of createReadStream(path)) hash.update(chunk)
  return hash.digest('hex')
}

async function ffprobe(path) {
  const child = spawn('ffprobe', [
    '-v', 'error', '-show_entries',
    'format=duration,format_name:stream=codec_type,codec_name,width,height,r_frame_rate',
    '-of', 'json', path,
  ], { stdio: ['ignore', 'pipe', 'pipe'] })
  let stdout = ''
  let stderr = ''
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', chunk => { stdout += chunk })
  child.stderr.on('data', chunk => { stderr += chunk })
  const code = await new Promise((done, fail) => {
    child.once('error', fail)
    child.once('close', status => done(status ?? 1))
  })
  if (code !== 0) throw new Error(`ffprobe fehlgeschlagen: ${stderr.trim() || `Code ${code}`}`)
  const result = JSON.parse(stdout)
  const video = result.streams?.find(stream => stream.codec_type === 'video')
  const audio = result.streams?.find(stream => stream.codec_type === 'audio')
  if (!result.format?.format_name?.split(',').includes('mp4')) throw new Error('Die Quelldatei ist kein MP4.')
  if (video?.codec_name !== 'h264' || video.width !== 1080 || video.height !== 1920 || video.r_frame_rate !== '30/1') {
    throw new Error('Der Testlauf benötigt H.264 mit 1080×1920 und 30 FPS.')
  }
  if (audio?.codec_name !== 'aac') throw new Error('Der Testlauf benötigt eine AAC-Audiospur.')
  const durationSeconds = Number(result.format.duration)
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0 || durationSeconds > 180) {
    throw new Error('Die Videodauer liegt außerhalb des sicheren Short-Form-Bereichs.')
  }
  return {
    width: video.width,
    height: video.height,
    fps: 30,
    durationSeconds,
    videoCodec: 'h264',
    audioCodec: 'aac',
  }
}

async function writeAtomically(path, value) {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}-${Date.now()}`
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 })
  await rename(temporary, path)
}

async function readJson(path, label) {
  try {
    return JSON.parse(await readFile(path, 'utf8'))
  } catch (error) {
    throw new Error(`${label} ist kein gültiges JSON: ${errorMessage(error)}`)
  }
}

const requiredEnv = name => {
  const value = process.env[name]?.trim()
  if (!value) throw new Error(`${name} fehlt.`)
  return value
}

const delay = milliseconds => new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds))

async function fetchWithPolicy(url, options = {}, { timeoutMs = 30_000, safeToRetry = false, attempts = 3 } = {}) {
  let lastError
  const maximum = safeToRetry ? attempts : 1
  for (let attempt = 0; attempt < maximum; attempt += 1) {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), timeoutMs)
    try {
      const response = await fetch(url, { ...options, signal: controller.signal })
      if (!safeToRetry || !RETRYABLE_HTTP.has(response.status) || attempt === maximum - 1) return response
      await response.arrayBuffer().catch(() => undefined)
    } catch (error) {
      lastError = error
      if (!safeToRetry || attempt === maximum - 1) throw error
    } finally {
      clearTimeout(timeout)
    }
    await delay(500 * 2 ** attempt)
  }
  throw lastError ?? new Error('Netzwerkaufruf fehlgeschlagen.')
}

async function googleAccessToken() {
  const response = await fetchWithPolicy('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: requiredEnv('YOUTUBE_CLIENT_ID'),
      client_secret: requiredEnv('YOUTUBE_CLIENT_SECRET'),
      refresh_token: requiredEnv('YOUTUBE_REFRESH_TOKEN'),
      grant_type: 'refresh_token',
    }),
  }, { safeToRetry: true })
  const body = await response.json().catch(() => ({}))
  if (!response.ok || typeof body.access_token !== 'string') {
    throw new Error(`YouTube OAuth fehlgeschlagen (HTTP ${response.status}).`)
  }
  return body.access_token
}

async function preflightYouTube() {
  const expectedChannelId = requiredEnv('YOUTUBE_CHANNEL_ID')
  const accessToken = await googleAccessToken()
  const response = await fetchWithPolicy('https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true', {
    headers: { authorization: `Bearer ${accessToken}` },
  }, { safeToRetry: true })
  const body = await response.json().catch(() => ({}))
  const actualChannelId = body.items?.[0]?.id
  if (!response.ok || typeof actualChannelId !== 'string') {
    throw new Error(`Der YouTube-Kanal konnte nicht gelesen werden (HTTP ${response.status}).`)
  }
  if (actualChannelId !== expectedChannelId) {
    throw new Error('Der verbundene YouTube-Kanal entspricht nicht YOUTUBE_CHANNEL_ID.')
  }
  return { accessToken, channelId: actualChannelId }
}

async function stageYouTubePrivate(inputPath, plan, onState, preflight) {
  const { accessToken, channelId } = preflight
  const headers = { authorization: `Bearer ${accessToken}` }
  const file = await stat(inputPath)
  const body = assertSafeYouTubeInsert({
    snippet: {
      title: plan.metadata.youtubeTitle,
      description: plan.metadata.description,
      categoryId: process.env.YOUTUBE_CATEGORY_ID?.trim() || '27',
      defaultLanguage: 'en',
      tags: plan.metadata.hashtags.map(hashtag => hashtag.slice(1)),
    },
    status: { privacyStatus: 'private', selfDeclaredMadeForKids: false },
  })

  await onState({ operationState: 'session_create_intent', transportState: 'uploading', updatedAt: new Date().toISOString() })
  let session
  try {
    session = await fetchWithPolicy(
      'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers=false',
      {
        method: 'POST',
        headers: {
          ...headers,
          'content-type': 'application/json; charset=UTF-8',
          'x-upload-content-length': String(file.size),
          'x-upload-content-type': 'video/mp4',
        },
        body: JSON.stringify(body),
      },
      { timeoutMs: 30_000, safeToRetry: false },
    )
  } catch (error) {
    await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', error: 'Ergebnis der YouTube-Session-Erstellung ist unklar.' })
    throw new Error(`YouTube-Session endete unklar; kein automatischer Neuversuch: ${errorMessage(error)}`)
  }
  const sessionUrl = session.headers.get('location')
  if (!session.ok || !sessionUrl) {
    await onState({ operationState: 'failed_before_create', transportState: 'failed', error: `HTTP ${session.status}` })
    throw new Error(`YouTube hat keine Upload-Session erstellt (HTTP ${session.status}).`)
  }
  await onState({ operationState: 'session_confirmed', transportState: 'uploading', uploadedBytes: 0 })

  const descriptor = await open(inputPath, 'r')
  const uploadedHash = createHash('sha256')
  let offset = 0
  let uploaded
  try {
    const chunkSize = 8 * 1024 * 1024
    while (offset < file.size) {
      const length = Math.min(chunkSize, file.size - offset)
      const chunk = Buffer.allocUnsafe(length)
      const { bytesRead } = await descriptor.read(chunk, 0, length, offset)
      if (bytesRead !== length) throw new Error('Die MP4 konnte während des Uploads nicht vollständig gelesen werden.')
      const end = offset + length - 1
      let response
      try {
        response = await fetchWithPolicy(sessionUrl, {
          method: 'PUT',
          headers: {
            'content-type': 'video/mp4',
            'content-length': String(length),
            'content-range': `bytes ${offset}-${end}/${file.size}`,
          },
          body: chunk,
        }, { timeoutMs: 120_000, safeToRetry: false })
      } catch (error) {
        await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', uploadedBytes: offset, error: 'Chunk-Ergebnis unklar.' })
        throw new Error(`YouTube-Chunk endete unklar; Session muss abgestimmt werden: ${errorMessage(error)}`)
      }
      if (response.status === 308) {
        const matched = response.headers.get('range')?.match(/bytes=0-(\d+)/i)
        if (!matched) {
          await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', uploadedBytes: offset, error: 'YouTube-Range fehlt.' })
          throw new Error('YouTube bestätigte den Chunk ohne Range-Header; automatische Fortsetzung wurde gesperrt.')
        }
        const acceptedThrough = Number(matched[1])
        if (!Number.isInteger(acceptedThrough) || acceptedThrough < offset || acceptedThrough > end) {
          await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', uploadedBytes: offset, error: 'YouTube-Range ist inkonsistent.' })
          throw new Error('YouTube meldete einen inkonsistenten Upload-Bereich.')
        }
        uploadedHash.update(chunk.subarray(0, acceptedThrough - offset + 1))
        offset = acceptedThrough + 1
        await onState({ operationState: 'uploading', transportState: 'uploading', uploadedBytes: offset })
        continue
      }
      if (!response.ok) {
        await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', uploadedBytes: offset, error: `HTTP ${response.status}` })
        throw new Error(`YouTube-Upload ist unklar fehlgeschlagen (HTTP ${response.status}); manuelle Abstimmung erforderlich.`)
      }
      uploadedHash.update(chunk)
      uploaded = await response.json()
      offset = file.size
    }
  } finally {
    await descriptor.close()
  }

  const videoId = uploaded?.id
  if (typeof videoId !== 'string' || !videoId) {
    await onState({ operationState: 'reconcile_required', transportState: 'reconcile_required', uploadedBytes: file.size, error: 'Video-ID fehlt.' })
    throw new Error('YouTube lieferte keine Video-ID; manuelle Abstimmung erforderlich.')
  }
  if (uploadedHash.digest('hex') !== plan.assetSha256) {
    await onState({ operationState: 'safety_violation', transportState: 'failed', error: 'Upload-Bytes weichen von der Content-ID ab.' })
    throw new Error('Die während des Uploads gelesenen Bytes stimmen nicht mit der geprüften Content-ID überein.')
  }
  const verify = await fetchWithPolicy(
    `https://www.googleapis.com/youtube/v3/videos?part=status,processingDetails&id=${encodeURIComponent(videoId)}`,
    { headers },
    { safeToRetry: true },
  )
  const verified = await verify.json().catch(() => ({}))
  const status = verified.items?.[0]?.status
  if (!verify.ok || status?.privacyStatus !== 'private' || status?.publishAt) {
    await onState({ operationState: 'safety_violation', transportState: 'failed', error: 'Privater Status nicht bestätigt.' })
    throw new Error('YouTube hat den ausschließlich privaten Zustand nicht bestätigt.')
  }
  const receipt = assertNonPublishingReceipt({
    platform: 'youtube',
    workflowState: 'private_uploaded',
    transportState: 'ready',
    visibilityState: 'non_public',
    remoteObjectId: videoId,
    accountFingerprint: remoteAccountFingerprint('youtube', channelId),
    providerStatus: status.privacyStatus,
    confirmedAt: new Date().toISOString(),
    publishedAt: null,
    scheduledFor: null,
    publicUrl: null,
  })
  await onState({ operationState: 'confirmed', transportState: 'ready', uploadedBytes: file.size, error: null })
  return receipt
}

function stagingApiUrl(pathname) {
  const origin = validateStagingApiBaseUrl(
    requiredEnv('UPLOAD_STAGING_API_URL'),
    process.env.UPLOAD_STAGING_ALLOWED_HOST,
  )
  return new URL(pathname, `${origin}/`).toString()
}

function stagingHeaders() {
  return {
    authorization: `Bearer ${requiredEnv('UPLOAD_STAGING_API_TOKEN')}`,
    'content-type': 'application/json',
  }
}

async function postStagingReceipt(plan, receipt, idempotencyKey, claimId) {
  const response = await fetchWithPolicy(stagingApiUrl('/staging/receipts'), {
    method: 'POST',
    headers: stagingHeaders(),
    body: JSON.stringify({
      schemaVersion: 1,
      lane: 'non-publishing',
      runId: plan.runId,
      platform: receipt.platform,
      idempotencyKey,
      claimId,
      ...receipt,
      publishedAt: null,
      scheduledFor: null,
      publicUrl: null,
    }),
  }, { safeToRetry: true })
  if (!response.ok) throw new Error(`Dashboard-Receipt wurde abgelehnt (HTTP ${response.status}).`)
}

async function claimYouTubeStaging(plan, idempotencyKey) {
  const response = await fetchWithPolicy(stagingApiUrl('/staging/claims'), {
    method: 'POST',
    headers: stagingHeaders(),
    body: JSON.stringify({
      schemaVersion: 1,
      lane: 'non-publishing',
      runId: plan.runId,
      platform: 'youtube',
      idempotencyKey,
    }),
  }, { safeToRetry: false })
  const body = await response.json().catch(() => null)
  if (!response.ok || !body || !['claimed', 'already_completed'].includes(body.status)) {
    throw new Error(`Der globale YouTube-Claim wurde nicht erteilt (HTTP ${response.status}).`)
  }
  return body
}

async function registerStagingPlan(plan) {
  const response = await fetchWithPolicy(stagingApiUrl('/staging/runs'), {
    method: 'POST',
    headers: stagingHeaders(),
    body: JSON.stringify({ ...plan, executeMeta: false }),
  }, { safeToRetry: true })
  if (!response.ok) throw new Error(`Der Dashboard-Testlauf wurde nicht registriert (HTTP ${response.status}).`)
  const body = await response.json().catch(() => null)
  return validateStagingRegistration(plan, body)
}

function assertMetaResponse(value, plan) {
  if (!value || typeof value !== 'object' || value.runId !== plan.runId || !Array.isArray(value.targets)) {
    throw new Error('Meta-Staging lieferte keinen gültigen Laufstatus.')
  }
  const allowedRunStatuses = new Set(['planned', 'running', 'partial', 'completed', 'failed', 'expired', 'reconcile_required'])
  if (!allowedRunStatuses.has(value.status)) throw new Error('Meta-Staging meldete einen unsicheren oder unbekannten Laufstatus.')
  const targets = value.targets.filter(target => ['instagram', 'facebook'].includes(target?.platform))
  if (new Set(targets.map(target => target.platform)).size !== 2) {
    throw new Error('Meta-Staging lieferte nicht beide Plattformstatus.')
  }
  for (const target of targets) {
    if (target.visibilityState === 'public' || target.publishedAt || target.scheduledFor || target.publicUrl) {
      throw new Error(`Sicherheitsverletzung im ${target.platform}-Stagingstatus.`)
    }
    if (String(target.providerStatus ?? '').toUpperCase() === 'PUBLISHED' || target.workflowState === 'safety_violation') {
      throw new Error(`Sicherheitsverletzung im ${target.platform}-Providerstatus.`)
    }
    if (!['planned', 'uploading', 'processing', 'ready', 'failed', 'expired', 'reconcile_required'].includes(target.transportState) ||
        !['ready', 'container_unpublished', 'draft', 'failed', 'expired', 'reconcile_required'].includes(target.workflowState)) {
      throw new Error(`Unbekannter ${target.platform}-Stagingstatus.`)
    }
    if (target.workflowState === 'draft' || target.workflowState === 'container_unpublished') {
      assertNonPublishingReceipt({ ...target, publishedAt: null, scheduledFor: null, publicUrl: null })
    }
  }
  return { runId: value.runId, status: value.status, targets }
}

async function stageMeta(plan, args, recoverOnly = false) {
  if (recoverOnly) {
    const response = await fetchWithPolicy(stagingApiUrl(`/staging/runs/${encodeURIComponent(plan.runId)}`), {
      headers: stagingHeaders(),
    }, { safeToRetry: true })
    if (!response.ok) throw new Error(`Meta-Stagingstatus konnte nicht gelesen werden (HTTP ${response.status}).`)
    return assertMetaResponse(await response.json(), plan)
  }
  if (!args.mediaUrl || !args.mediaProject || !args.mediaBranch) {
    throw new Error('Meta-Staging benötigt --media-url, --media-project und --media-branch.')
  }
  const response = await fetchWithPolicy(stagingApiUrl('/staging/runs'), {
    method: 'POST',
    headers: stagingHeaders(),
    body: JSON.stringify({
      ...plan,
      executeMeta: true,
      mediaUrl: new URL(args.mediaUrl).toString(),
      mediaProject: args.mediaProject,
      mediaBranch: args.mediaBranch,
    }),
  }, { timeoutMs: 30_000, safeToRetry: false })
  if (!response.ok) throw new Error(`Meta-Staging wurde abgelehnt (HTTP ${response.status}).`)
  return assertMetaResponse(await response.json(), plan)
}

function normalizedMetaReceipts(result) {
  return result.targets
    .filter(target => ['draft', 'container_unpublished'].includes(target.workflowState))
    .map(target => assertNonPublishingReceipt({
      platform: target.platform,
      workflowState: target.workflowState,
      transportState: target.transportState,
      visibilityState: target.visibilityState,
      remoteObjectId: target.remoteObjectId ?? null,
      providerStatus: target.providerStatus ?? null,
      confirmedAt: target.confirmedAt ?? new Date().toISOString(),
      publishedAt: null,
      scheduledFor: null,
      publicUrl: null,
    }))
}

function samePlan(prior, plan) {
  if (prior.plan.contentId !== plan.contentId || prior.plan.runId !== plan.runId) return false
  if (prior.plan.metadataSha256 !== plan.metadataSha256) return false
  return prior.plan.targets.every((target, index) => target.idempotencyKey === plan.targets[index]?.idempotencyKey)
}

async function validateQualityReport(path, assetSha256, media) {
  const report = await readJson(path, 'Der Quality-Report')
  if (report.status !== 'passed') throw new Error('Der Quality-Report ist nicht bestanden.')
  if (report.video?.sha256 !== assetSha256) throw new Error('Der Quality-Report gehört nicht zu dieser MP4.')
  if (report.video?.width !== media.width || report.video?.height !== media.height || report.video?.fps !== media.fps) {
    throw new Error('Die technischen Videodaten stimmen nicht mit dem Quality-Report überein.')
  }
  return { id: String(report.id ?? ''), status: 'passed', warningCount: Array.isArray(report.warnings) ? report.warnings.length : 0 }
}

const isWithin = (root, candidate) => {
  const path = relative(root, candidate)
  return path === '' || (!path.startsWith('..') && !path.startsWith('/'))
}

function ensureSeparatePaths(inputPath, privateOutputPath, publicOutputPath, stateDir) {
  if (inputPath === privateOutputPath || inputPath === publicOutputPath) {
    throw new Error('Ein JSON-Ausgabepfad darf niemals die MP4 überschreiben.')
  }
  if (privateOutputPath.startsWith(resolve(REPOSITORY_ROOT, 'dashboard/public'))) {
    throw new Error('Private Receipts dürfen nicht im öffentlichen Dashboard-Ordner gespeichert werden.')
  }
  if (isWithin(REPOSITORY_ROOT, privateOutputPath) && !isWithin(stateDir, privateOutputPath)) {
    throw new Error('Private Receipts innerhalb des Repositorys müssen im gitignorierten State-Verzeichnis liegen.')
  }
  if (publicOutputPath) {
    const allowedRoot = resolve(REPOSITORY_ROOT, 'dashboard/public/data')
    const relativePath = relative(allowedRoot, publicOutputPath)
    if (relativePath.startsWith('..') || relativePath === '') {
      throw new Error('--public-output muss eine Datei innerhalb dashboard/public/data sein.')
    }
  }
}

async function withContentLock(stateDir, contentId, action) {
  await mkdir(stateDir, { recursive: true })
  const lockPath = resolve(stateDir, `${contentId}.lock`)
  let handle
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      handle = await open(lockPath, 'wx', 0o600)
      await handle.writeFile(`${JSON.stringify({ pid: process.pid, host: hostname(), startedAt: new Date().toISOString() })}\n`)
      break
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error
      let stale = false
      try {
        const lock = JSON.parse(await readFile(lockPath, 'utf8'))
        if (lock.host === hostname() && Number.isInteger(lock.pid)) {
          try { process.kill(lock.pid, 0) } catch (probeError) { stale = probeError?.code === 'ESRCH' }
        }
      } catch {
        // An unreadable or foreign-host lock is never removed automatically.
      }
      if (!stale || attempt > 0) {
        throw new Error('Für dieses Video läuft bereits ein Upload-Test. Es wird kein zweiter Upload gestartet.')
      }
      await unlink(lockPath)
    }
  }
  try {
    return await action()
  } finally {
    await handle.close().catch(() => undefined)
    await unlink(lockPath).catch(() => undefined)
  }
}

async function main() {
  const args = argumentsFrom(process.argv.slice(2))
  if (!args.input || !args.metadata || !args.qualityReport || !args.output) {
    throw new Error('Erforderlich: --input <mp4> --metadata <json> --quality-report <json> --output <private-json>. Standard ist Plan-only; Dashboard-Registrierung mit --register-only, Remote-Uploads nur mit --execute.')
  }
  const inputPath = resolve(args.input)
  const metadataPath = resolve(args.metadata)
  const qualityReportPath = resolve(args.qualityReport)
  const outputPath = resolve(args.output)
  const publicOutputPath = args.publicOutput ? resolve(args.publicOutput) : null
  const stateDir = resolve(args.stateDir)
  ensureSeparatePaths(inputPath, outputPath, publicOutputPath, stateDir)
  await Promise.all([access(inputPath), access(metadataPath), access(qualityReportPath)])

  const before = await stat(inputPath)
  let metadataFile
  let media
  let assetSha256
  try {
    [metadataFile, media, assetSha256] = await Promise.all([
      readJson(metadataPath, 'Die Upload-Metadaten'),
      ffprobe(inputPath),
      hashFile(inputPath),
    ])
  } catch (error) {
    if (error?.code === 'ETIMEDOUT' || /operation timed out|connection timed out/i.test(errorMessage(error))) {
      throw new Error('Mindestens eine OneDrive-Datei ist nur als Cloud-Platzhalter vorhanden. OneDrive kurz starten und MP4 sowie Quality-Report zuerst vollständig herunterladen.')
    }
    throw error
  }
  const after = await stat(inputPath)
  if (before.size !== after.size || before.mtimeMs !== after.mtimeMs) {
    throw new Error('Die MP4 wurde während der Prüfung verändert oder noch synchronisiert.')
  }
  let quality
  try {
    quality = await validateQualityReport(qualityReportPath, assetSha256, media)
  } catch (error) {
    if (/ETIMEDOUT|operation timed out|connection timed out/i.test(errorMessage(error))) {
      throw new Error('Der Quality-Report ist nur als OneDrive-Cloud-Platzhalter vorhanden und muss zuerst vollständig heruntergeladen werden.')
    }
    throw error
  }
  const plan = buildStagingPlan({
    runId: metadataFile.runId,
    assetSha256,
    metadata: metadataFile.platformMetadata,
    accountFingerprints: metadataFile.accountFingerprints,
    createdAt: metadataFile.createdAt ?? new Date().toISOString(),
    manualTikTokReceipt: metadataFile.tiktok,
  })

  await withContentLock(stateDir, plan.contentId, async () => {
    const statePath = resolve(stateDir, `${plan.contentId}.json`)
    let prior = null
    try {
      prior = JSON.parse(await readFile(statePath, 'utf8'))
    } catch (error) {
      if (error?.code !== 'ENOENT') throw new Error(`Der persistente Upload-Status ist beschädigt: ${errorMessage(error)}`)
    }
    if (prior && !samePlan(prior, plan)) {
      throw new Error('Für dieselbe MP4 existiert ein abweichender Lauf oder Metadatenstand. Es wird kein doppelter Upload erzeugt.')
    }
    const record = prior ?? {
      schemaVersion: 1,
      plan,
      source: { fileName: inputPath.split('/').at(-1), sizeBytes: after.size, media, quality },
      execution: {
        requested: false,
        status: 'plan_validated',
        targets: {},
        receipts: [...plan.manualReceipts],
        errors: [],
        completedAt: null,
      },
    }
    const hadExecuteState = record.execution.requested === true || record.execution.mode === 'execute'
    if (args.execute) {
      record.execution.requested = true
      record.execution.mode = 'execute'
    } else if (!hadExecuteState) {
      record.execution.requested = false
      record.execution.mode = args.registerOnly ? 'register_only' : 'plan_only'
    }

    const persist = async () => {
      record.updatedAt = new Date().toISOString()
      await writeAtomically(statePath, record)
      await writeAtomically(outputPath, record)
      if (publicOutputPath) await writeAtomically(publicOutputPath, publicStagingSnapshot(record))
    }
    await persist()

    if (args.execute || args.registerOnly) {
      if (args.registerOnly || record.execution.targets.registry?.operationState !== 'confirmed') {
        try {
          const registration = await registerStagingPlan(plan)
          record.execution.targets.registry = {
            operationState: 'confirmed',
            transportState: 'ready',
            serverTargets: registration.targets.map(target => ({
              platform: target.platform,
              idempotencyKey: target.idempotencyKey,
            })),
          }
          resolveExecutionErrors(record.execution, 'dashboard')
          await persist()
        } catch (error) {
          record.execution.targets.registry = { operationState: 'failed', transportState: 'failed' }
          record.execution.errors.push({ platform: 'dashboard', at: new Date().toISOString(), message: errorMessage(error) })
          await persist()
          throw new Error(`Kein Remote-Upload wurde gestartet: ${errorMessage(error)}`)
        }
      }

      if (args.registerOnly && !hadExecuteState) {
        record.execution.status = 'registered_plan_only'
        record.execution.completedAt = new Date().toISOString()
        await persist()
      }
    }

    if (args.execute) {

      if (args.selectedPlatforms.includes('youtube')) {
        const youtubeReceipt = record.execution.receipts.find(receipt => receipt.platform === 'youtube')
        if (!youtubeReceipt) {
          const targetState = record.execution.targets.youtube
          if (targetState && targetState.operationState !== 'failed_before_create') {
            record.execution.errors.push({ platform: 'youtube', at: new Date().toISOString(), message: 'Vorheriger YouTube-Aufruf muss manuell abgestimmt werden.' })
          } else {
            try {
              const preflight = await preflightYouTube()
              const serverTarget = record.execution.targets.registry.serverTargets
                .find(target => target.platform === 'youtube')
              if (!serverTarget?.idempotencyKey) throw new Error('Der Server lieferte keinen verifizierten YouTube-Idempotenzschlüssel.')
              record.execution.targets.youtube = { operationState: 'preflight_confirmed', transportState: 'planned' }
              await persist()
              const claim = await claimYouTubeStaging(plan, serverTarget.idempotencyKey)
              if (claim.status === 'already_completed') {
                const target = claim.target
                const receipt = assertNonPublishingReceipt({
                  platform: 'youtube', workflowState: target.workflowState, transportState: target.transportState,
                  visibilityState: target.visibilityState, remoteObjectId: target.remoteObjectId,
                  providerStatus: target.providerStatus, confirmedAt: new Date().toISOString(),
                  publishedAt: null, scheduledFor: null, publicUrl: null,
                })
                record.execution.receipts.push(receipt)
                record.execution.targets.youtube = { operationState: 'confirmed', transportState: 'ready', dashboardSync: 'confirmed' }
                resolveExecutionErrors(record.execution, 'youtube')
                await persist()
              } else {
                record.execution.targets.youtube = {
                  operationState: 'global_claim_confirmed',
                  transportState: 'uploading',
                  claimId: claim.claimId,
                }
                await persist()
                const receipt = await stageYouTubePrivate(inputPath, plan, async patch => {
                  record.execution.targets.youtube = { ...record.execution.targets.youtube, ...patch }
                  await persist()
                }, preflight)
                record.execution.receipts.push(receipt)
                record.execution.targets.youtube = { ...record.execution.targets.youtube, operationState: 'confirmed', transportState: 'ready' }
                resolveExecutionErrors(record.execution, 'youtube')
                try {
                  await postStagingReceipt(plan, receipt, serverTarget.idempotencyKey, claim.claimId)
                  record.execution.targets.youtube.dashboardSync = 'confirmed'
                } catch (error) {
                  record.execution.targets.youtube.dashboardSync = 'pending'
                  record.execution.errors.push({ platform: 'dashboard', at: new Date().toISOString(), message: errorMessage(error) })
                }
              }
            } catch (error) {
              record.execution.errors.push({ platform: 'youtube', at: new Date().toISOString(), message: errorMessage(error) })
            }
            await persist()
          }
        }
      }

      if (args.selectedPlatforms.includes('meta')) {
        const confirmedMeta = record.execution.receipts.filter(receipt => ['instagram', 'facebook'].includes(receipt.platform))
        if (confirmedMeta.length < 2) {
          try {
            const recoverOnly = Boolean(record.execution.targets.meta)
            record.execution.targets.meta = {
              ...record.execution.targets.meta,
              operationState: recoverOnly ? 'reconciling' : 'remote_create_started',
              transportState: 'uploading',
            }
            await persist()
            const result = await stageMeta(plan, args, recoverOnly)
            resolveExecutionErrors(record.execution, 'meta')
            for (const receipt of normalizedMetaReceipts(result)) {
              const index = record.execution.receipts.findIndex(existing => existing.platform === receipt.platform)
              if (index >= 0) record.execution.receipts[index] = receipt
              else record.execution.receipts.push(receipt)
            }
            record.execution.targets.meta = {
              operationState: result.status,
              transportState: result.status === 'completed' ? 'ready'
                : ['failed', 'expired', 'reconcile_required'].includes(result.status) ? 'failed' : 'processing',
              workerStatus: result.status,
            }
            if (['failed', 'expired', 'reconcile_required'].includes(result.status)) {
              record.execution.errors.push({ platform: 'meta', at: new Date().toISOString(), message: `Meta-Stagingstatus: ${result.status}` })
            }
          } catch (error) {
            record.execution.targets.meta = {
              ...record.execution.targets.meta,
              operationState: 'reconcile_required',
              transportState: 'reconcile_required',
            }
            record.execution.errors.push({ platform: 'meta', at: new Date().toISOString(), message: errorMessage(error) })
          }
          await persist()
        }
      }

      const completedPlatforms = new Set(record.execution.receipts.map(receipt => receipt.platform))
      record.execution.status = ['youtube', 'instagram', 'facebook', 'tiktok'].every(platform => completedPlatforms.has(platform))
        ? 'staged_non_public'
        : record.execution.errors.length > 0 ? 'partial_or_reconcile_required' : 'processing'
      record.execution.completedAt = record.execution.status === 'staged_non_public' ? new Date().toISOString() : null
      const requestedTargets = [
        ...(args.selectedPlatforms.includes('youtube') ? ['youtube'] : []),
        ...(args.selectedPlatforms.includes('meta') ? ['instagram', 'facebook'] : []),
      ]
      const requestedErrors = new Set(record.execution.errors.map(error => error.platform))
      const requestedSucceeded = requestedTargets.every(platform => completedPlatforms.has(platform)) &&
        !requestedTargets.some(platform => requestedErrors.has(platform))
      record.execution.lastAttempt = {
        platforms: [...args.selectedPlatforms],
        status: requestedSucceeded ? 'succeeded' : 'incomplete_or_failed',
        completedAt: new Date().toISOString(),
      }
      await persist()
      if (!requestedSucceeded) process.exitCode = 1
    }

    const outcome = args.execute
      ? `Status: ${record.execution.status}.`
      : args.registerOnly
        ? 'Dashboard-Registrierung erfolgreich; keine Plattform wurde verändert.'
        : 'Plan-only erfolgreich; keine Plattform wurde verändert.'
    console.log(`[upload-staging] ${outcome}`)
    console.log(`[upload-staging] Content-ID: ${plan.contentId}`)
    console.log(`[upload-staging] Private Statusdatei: ${outputPath}`)
  })
}

main().catch(error => {
  console.error(`[upload-staging] Fehlgeschlagen: ${errorMessage(error)}`)
  process.exitCode = 1
})
