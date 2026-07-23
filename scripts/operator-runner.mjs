import { createHash } from 'node:crypto'
import { lstat, readFile, realpath } from 'node:fs/promises'
import { homedir, hostname } from 'node:os'
import { isAbsolute, relative, resolve, sep } from 'node:path'
import { pathToFileURL } from 'node:url'
import { buildOperatorAnalysisManifest } from './operator-analysis-manifest.mjs'

const RUN_ID_PATTERN = /^video-[a-f0-9]{24}$/u
const LOCAL_STATUSES = new Set(['queued', 'running', 'waiting', 'completed', 'failed'])
const LOCAL_STEP_IDS = [
  'script_validation',
  'flag_selection',
  'voice_preparation',
  'timeline_build',
  'audio_design',
  'render',
  'quality_check',
  'preview_ready',
]
const LOCAL_STEP_ID_SET = new Set(LOCAL_STEP_IDS)
const LOCALLY_RETRYABLE_PREVIEW_STEPS = new Set(['flag_selection', 'timeline_build'])
const LOCAL_STEP_STATUSES = new Set(['pending', 'running', 'waiting', 'completed', 'failed'])
const MAX_PREVIEW_BYTES = 512 * 1024 * 1024
const MAX_GATE_JSON_BYTES = 5 * 1024 * 1024

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds))

const required = (env, name) => {
  const value = env[name]?.trim()
  if (!value) throw new Error(`${name} fehlt.`)
  return value
}

const integerSetting = (env, name, fallback, minimum, maximum) => {
  const raw = env[name]?.trim()
  const value = raw ? Number(raw) : fallback
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} muss zwischen ${minimum} und ${maximum} liegen.`)
  }
  return value
}

const normalizedUrl = (value, mode) => {
  const parsed = new URL(value)
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname)
  if (parsed.username || parsed.password || parsed.search || parsed.hash) {
    throw new Error(`${mode} enthält unzulässige URL-Bestandteile.`)
  }
  if (mode === 'VIDEO_CONTROL_API_URL' && !local) {
    throw new Error('VIDEO_CONTROL_API_URL muss eine lokale Loopback-Adresse sein.')
  }
  if (parsed.protocol !== 'https:' && !(local && parsed.protocol === 'http:')) {
    throw new Error(`${mode} muss HTTPS verwenden.`)
  }
  return parsed.href.replace(/\/$/u, '')
}

const safeRunnerId = value => {
  const normalized = value.trim().replace(/[^A-Za-z0-9._:-]+/gu, '-').slice(0, 100)
  if (!/^[A-Za-z0-9._:-]{3,100}$/u.test(normalized)) throw new Error('OPERATOR_RUNNER_ID ist ungültig.')
  return normalized
}

const absoluteDirectory = (value, name) => {
  const expanded = value === '~'
    ? homedir()
    : value.startsWith('~/')
      ? resolve(homedir(), value.slice(2))
      : value
  if (!isAbsolute(expanded)) throw new Error(`${name} muss ein absoluter Pfad sein.`)
  const normalized = resolve(expanded)
  if (normalized === sep) throw new Error(`${name} darf nicht auf das Dateisystem-Stammverzeichnis zeigen.`)
  return normalized
}

export const loadRunnerConfig = (env = process.env) => ({
  operatorApiUrl: normalizedUrl(required(env, 'OPERATOR_API_URL'), 'OPERATOR_API_URL'),
  runnerToken: required(env, 'OPERATOR_RUNNER_TOKEN'),
  runnerId: safeRunnerId(env.OPERATOR_RUNNER_ID?.trim() || `mac-${hostname()}`),
  controlApiUrl: normalizedUrl(env.VIDEO_CONTROL_API_URL?.trim() || 'http://127.0.0.1:4317', 'VIDEO_CONTROL_API_URL'),
  localRunsRoot: absoluteDirectory(required(env, 'OPERATOR_LOCAL_RUNS_ROOT'), 'OPERATOR_LOCAL_RUNS_ROOT'),
  pollIntervalMs: integerSetting(env, 'OPERATOR_POLL_INTERVAL_MS', 5_000, 1_000, 60_000),
  requestTimeoutMs: integerSetting(env, 'OPERATOR_REQUEST_TIMEOUT_MS', 15_000, 1_000, 120_000),
  previewTimeoutMs: integerSetting(env, 'OPERATOR_PREVIEW_TIMEOUT_MS', 120_000, 30_000, 600_000),
  localPollIntervalMs: integerSetting(env, 'OPERATOR_LOCAL_POLL_INTERVAL_MS', 1_500, 500, 30_000),
  leaseSeconds: integerSetting(env, 'OPERATOR_LEASE_SECONDS', 60, 30, 300),
})

const request = async (url, init, timeoutMs) => {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    return await fetch(url, { ...init, signal: controller.signal, cache: 'no-store' })
  } finally {
    clearTimeout(timeout)
  }
}

const readJson = async response => {
  try {
    return await response.json()
  } catch {
    throw new Error(`Ungültige JSON-Antwort (HTTP ${response.status}).`)
  }
}

const operatorHeaders = config => ({
  Authorization: `Bearer ${config.runnerToken}`,
  'Content-Type': 'application/json',
})

const safeNullableText = (value, maxLength = 500) => {
  if (value === null || value === undefined) return null
  if (typeof value !== 'string' || value.trim() === '' || value.length > maxLength) return null
  return value.trim()
}

const safeLocalPreviewUrl = value => {
  if (typeof value !== 'string' || value.length > 2_048) return null
  try {
    const parsed = new URL(value)
    if (
      parsed.protocol !== 'http:' ||
      !['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname) ||
      parsed.username || parsed.password
    ) return null
    return parsed.href
  } catch {
    return null
  }
}

const parseLocalSteps = value => {
  if (!Array.isArray(value) || value.length !== LOCAL_STEP_IDS.length) {
    throw new Error('Produktionsstatus enthält keine vollständigen Prüfschritte.')
  }
  const seen = new Set()
  const steps = value.map(candidate => {
    if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
      throw new Error('Produktionsstatus enthält einen ungültigen Prüfschritt.')
    }
    if (
      typeof candidate.id !== 'string' || !LOCAL_STEP_ID_SET.has(candidate.id) || seen.has(candidate.id) ||
      typeof candidate.status !== 'string' || !LOCAL_STEP_STATUSES.has(candidate.status) ||
      typeof candidate.progress !== 'number' || !Number.isFinite(candidate.progress) ||
      candidate.progress < 0 || candidate.progress > 100
    ) throw new Error('Produktionsstatus enthält einen ungültigen Prüfschritt.')
    seen.add(candidate.id)
    return {
      id: candidate.id,
      status: candidate.status,
      progress: candidate.progress,
    }
  })
  if (LOCAL_STEP_IDS.some(id => !seen.has(id))) {
    throw new Error('Produktionsstatus enthält keine vollständigen Prüfschritte.')
  }
  return steps
}

const parsePublicRun = value => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Produktionsstatus ist ungültig.')
  const run = value
  if (
    typeof run.runId !== 'string' || !RUN_ID_PATTERN.test(run.runId) ||
    typeof run.status !== 'string' || !LOCAL_STATUSES.has(run.status) ||
    typeof run.progress !== 'number' || !Number.isFinite(run.progress) || run.progress < 0 || run.progress > 100
  ) throw new Error('Produktionsstatus ist unvollständig.')
  const completed = run.status === 'completed'
  const previewUrl = completed ? safeLocalPreviewUrl(run.previewUrl) : null
  const steps = parseLocalSteps(run.steps)
  return {
    runId: run.runId,
    status: run.status,
    progress: run.progress,
    currentStep: safeNullableText(run.currentStep, 100),
    message: safeNullableText(run.message),
    error: safeNullableText(run.error, 100),
    previewUrl,
    steps,
  }
}

const parseClaim = value => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Claim-Antwort ist ungültig.')
  const claim = value
  const run = claim.run
  const command = claim.command
  if (
    !run || typeof run !== 'object' || Array.isArray(run) ||
    typeof run.runId !== 'string' || !RUN_ID_PATTERN.test(run.runId) ||
    !command || typeof command !== 'object' || Array.isArray(command) ||
    typeof command.script !== 'string' || command.script.length < 80 || command.script.length > 20_000 ||
    typeof command.targetDurationSeconds !== 'number' || command.targetDurationSeconds < 61 || command.targetDurationSeconds > 70 ||
    typeof command.clientRequestId !== 'string' || command.clientRequestId.length > 128 ||
    typeof claim.leaseToken !== 'string' || claim.leaseToken.length < 20 || claim.leaseToken.length > 200
  ) throw new Error('Claim-Antwort ist unvollständig.')
  return {
    runId: run.runId,
    command: {
      script: command.script,
      targetDurationSeconds: command.targetDurationSeconds,
      clientRequestId: command.clientRequestId,
    },
    leaseToken: claim.leaseToken,
  }
}

export const claimNextRun = async config => {
  const response = await request(`${config.operatorApiUrl}/v1/runner/claim`, {
    method: 'POST',
    headers: operatorHeaders(config),
    body: JSON.stringify({ runnerId: config.runnerId, leaseSeconds: config.leaseSeconds }),
  }, config.requestTimeoutMs)
  if (response.status === 204) return null
  const body = await readJson(response)
  if (!response.ok) throw new Error(`Operator-API Claim fehlgeschlagen (HTTP ${response.status}).`)
  return parseClaim(body)
}

const remoteStatus = async (config, claim, local) => {
  const localStatus = local.status === 'queued' ? 'running' : local.status
  const failed = localStatus === 'failed'
  const response = await request(`${config.operatorApiUrl}/v1/runner/runs/${claim.runId}/status`, {
    method: 'POST',
    headers: operatorHeaders(config),
    body: JSON.stringify({
      runnerId: config.runnerId,
      leaseToken: claim.leaseToken,
      status: localStatus,
      progress: local.progress,
      currentStep: local.currentStep,
      message: local.message,
      error: failed ? (local.error || 'LOCAL_PRODUCTION_FAILED') : null,
      providerRunId: local.runId,
    }),
  }, config.requestTimeoutMs)
  if (response.status === 409) return false
  if (!response.ok) throw new Error(`Operator-Statusupdate fehlgeschlagen (HTTP ${response.status}).`)
  return true
}

const waitingStatus = (claim, message = 'Lokale Produktions-Engine ist vorübergehend nicht erreichbar.') => ({
  runId: claim.runId,
  status: 'waiting',
  progress: 0,
  currentStep: 'engine_connection',
  message,
  error: null,
})

const failedStatus = (claim, code) => ({
  runId: claim.runId,
  status: 'failed',
  progress: 0,
  currentStep: 'script_validation',
  message: (
    code === 'QUALITY_GATE_FAILED' ||
    code === 'MONETIZATION_GATE_FAILED' ||
    code === 'GATE_EVIDENCE_INVALID'
  )
    ? 'Die Vorschau hat eine verpflichtende Freigabeprüfung nicht bestanden.'
    : 'Lokale Produktions-Engine hat den Auftrag abgelehnt.',
  error: code,
})

const record = value =>
  value && typeof value === 'object' && !Array.isArray(value) ? value : null

const pathInside = (parent, child) => {
  const fromParent = relative(resolve(parent), resolve(child))
  return (
    fromParent !== '' &&
    fromParent !== '..' &&
    !fromParent.startsWith(`..${sep}`) &&
    !isAbsolute(fromParent)
  )
}

const readGateJson = async file => {
  let bytes
  try {
    bytes = await readFile(file.path)
  } catch {
    throw new Error('GATE_EVIDENCE_UNAVAILABLE')
  }
  if (
    bytes.byteLength !== file.sizeBytes ||
    bytes.byteLength < 2 ||
    bytes.byteLength > MAX_GATE_JSON_BYTES
  ) {
    throw new Error('GATE_EVIDENCE_INVALID')
  }
  try {
    return { value: JSON.parse(bytes.toString('utf8')), bytes }
  } catch {
    throw new Error('GATE_EVIDENCE_INVALID')
  }
}

const canonicalRunDirectory = async (configuredRunsRoot, runId) => {
  const runDirectory = resolve(configuredRunsRoot, runId)
  if (!pathInside(configuredRunsRoot, runDirectory)) throw new Error('GATE_EVIDENCE_INVALID')

  let canonicalRunsRoot
  let canonicalRun
  let runEntry
  try {
    canonicalRunsRoot = await realpath(configuredRunsRoot)
    runEntry = await lstat(runDirectory)
    canonicalRun = await realpath(runDirectory)
  } catch {
    throw new Error('GATE_EVIDENCE_UNAVAILABLE')
  }
  if (
    runEntry.isSymbolicLink() ||
    !runEntry.isDirectory() ||
    !pathInside(canonicalRunsRoot, canonicalRun)
  ) throw new Error('GATE_EVIDENCE_INVALID')

  return { runDirectory, canonicalRun }
}

const canonicalRegularFile = async (
  runDirectory,
  canonicalRun,
  candidate,
  maximumBytes,
) => {
  const artifactPath = resolve(runDirectory, candidate)
  if (!pathInside(runDirectory, artifactPath)) throw new Error('GATE_EVIDENCE_INVALID')

  let entry
  let canonicalPath
  let canonicalEntry
  try {
    entry = await lstat(artifactPath)
    canonicalPath = await realpath(artifactPath)
    canonicalEntry = await lstat(canonicalPath)
  } catch {
    throw new Error('GATE_EVIDENCE_UNAVAILABLE')
  }
  if (
    entry.isSymbolicLink() ||
    !entry.isFile() ||
    !canonicalEntry.isFile() ||
    entry.dev !== canonicalEntry.dev ||
    entry.ino !== canonicalEntry.ino ||
    entry.size !== canonicalEntry.size ||
    entry.size < 1 ||
    entry.size > maximumBytes ||
    !pathInside(canonicalRun, canonicalPath)
  ) throw new Error('GATE_EVIDENCE_INVALID')

  return { path: canonicalPath, sizeBytes: entry.size }
}

const privateArtifact = async (
  status,
  kind,
  runDirectory,
  canonicalRun,
  maximumBytes,
) => {
  if (!Array.isArray(status.privateArtifacts)) throw new Error('GATE_EVIDENCE_INVALID')
  const candidates = status.privateArtifacts.filter(candidate =>
    record(candidate)?.kind === kind
  )
  if (candidates.length !== 1) throw new Error('GATE_EVIDENCE_INVALID')
  const artifact = candidates[0]
  if (
    typeof artifact.path !== 'string' ||
    typeof artifact.sha256 !== 'string' ||
    !/^[a-f0-9]{64}$/u.test(artifact.sha256)
  ) throw new Error('GATE_EVIDENCE_INVALID')
  const file = await canonicalRegularFile(
    runDirectory,
    canonicalRun,
    artifact.path,
    maximumBytes,
  )
  return { ...file, sha256: artifact.sha256 }
}

const privateQaReady = (status, runId) => {
  if (
    status.schemaVersion !== '1.0.0' ||
    status.runId !== runId ||
    status.status !== 'qa_ready' ||
    status.currentStep !== 'preview_ready' ||
    !Number.isInteger(status.revision) ||
    status.revision < 1 ||
    !Array.isArray(status.steps) ||
    status.steps.some(step => record(step)?.status === 'failed')
  ) throw new Error('QUALITY_GATE_FAILED')
  const stepPassed = id => status.steps.some(step =>
    record(step)?.id === id && step.status === 'passed' && step.progress === 100
  )
  if (!stepPassed('quality_gate') || !stepPassed('preview_ready')) {
    throw new Error('QUALITY_GATE_FAILED')
  }
  return status.revision
}

const publicQaReady = local =>
  local.status === 'completed' &&
  local.currentStep === 'preview_ready' &&
  Boolean(local.previewUrl) &&
  local.steps.every(step => step.status === 'completed' && step.progress === 100)

const passedLocalMonetizationGate = report => {
  const explicitGate = record(report.monetizationGate)
  if (explicitGate) {
    return (
      explicitGate.status === 'passed' &&
      explicitGate.format === 'organic_flag_quiz' &&
      explicitGate.directPromotionPresent === false &&
      explicitGate.appBridgePresent === false &&
      Array.isArray(explicitGate.issues) &&
      explicitGate.issues.length === 0
    )
  }

  const creatorRewards = record(report.tiktokCreatorRewards)
  const checks = record(creatorRewards?.checks)
  const requiredChecks = [
    'durationAtLeast61Seconds',
    'sufficientSpokenContent',
    'fiveDistinctFlags',
    'noDirectDownloadPromotion',
    'originalMusic',
    'originalSoundEffects',
    'customVisualComposition',
  ]
  return (
    creatorRewards?.schemaVersion === '1.0.0' &&
    creatorRewards.program === 'tiktok_creator_rewards' &&
    creatorRewards.localGateStatus === 'passed' &&
    creatorRewards.platformEligibilityStatus === 'requires_tiktok_verification' &&
    Array.isArray(creatorRewards.issues) &&
    creatorRewards.issues.length === 0 &&
    Boolean(checks) &&
    requiredChecks.every(key => checks[key] === true)
  )
}

const verifyGateEvidence = async (config, local, previewSha256, previewSizeBytes) => {
  if (!publicQaReady(local)) throw new Error('QUALITY_GATE_FAILED')
  const { runDirectory, canonicalRun } = await canonicalRunDirectory(
    config.localRunsRoot,
    local.runId,
  )
  const statusFile = await canonicalRegularFile(
    runDirectory,
    canonicalRun,
    'status.json',
    MAX_GATE_JSON_BYTES,
  )
  const statusDocument = await readGateJson(statusFile)
  const status = record(statusDocument.value)
  if (!status) throw new Error('GATE_EVIDENCE_INVALID')
  const revision = privateQaReady(status, local.runId)
  const previewArtifact = await privateArtifact(
    status,
    'preview_video',
    runDirectory,
    canonicalRun,
    MAX_PREVIEW_BYTES,
  )
  const reportArtifact = await privateArtifact(
    status,
    'quality_report',
    runDirectory,
    canonicalRun,
    MAX_GATE_JSON_BYTES,
  )
  if (
    previewArtifact.sha256 !== previewSha256 ||
    previewArtifact.sizeBytes !== previewSizeBytes
  ) throw new Error('GATE_EVIDENCE_INVALID')

  const qualityDocument = await readGateJson(reportArtifact)
  const qualitySha256 = createHash('sha256').update(qualityDocument.bytes).digest('hex')
  if (qualitySha256 !== reportArtifact.sha256) throw new Error('GATE_EVIDENCE_INVALID')
  const report = record(qualityDocument.value)
  const video = record(report?.video)
  const blackFrames = record(report?.blackFrames)
  const timing = record(report?.timing)
  const flags = record(report?.flags)
  const assets = record(report?.assets)
  const textOverlays = record(report?.textOverlays)
  const audio = record(report?.audio)
  if (
    !report ||
    report.schemaVersion !== '1.0.0' ||
    report.status !== 'passed' ||
    report.publicationAuthorized !== false ||
    report.visibleTestMarker !== false ||
    video?.sha256 !== previewSha256 ||
    video.sizeBytes !== previewSizeBytes ||
    video.width !== 1080 ||
    video.height !== 1920 ||
    video.fps !== 30 ||
    video.videoCodec !== 'h264' ||
    video.audioCodec !== 'aac' ||
    typeof video.durationSeconds !== 'number' ||
    video.durationSeconds < 61 ||
    video.durationSeconds > 70.2 ||
    blackFrames?.status !== 'passed' ||
    timing?.status !== 'passed' ||
    flags?.status !== 'passed' ||
    assets?.status !== 'passed' ||
    textOverlays?.status !== 'passed' ||
    audio?.present !== true ||
    audio.clippingDetected !== false
  ) throw new Error('QUALITY_GATE_FAILED')
  if (!passedLocalMonetizationGate(report)) throw new Error('MONETIZATION_GATE_FAILED')
  const contentArtifact = await privateArtifact(
    status,
    'content_manifest',
    runDirectory,
    canonicalRun,
    MAX_GATE_JSON_BYTES,
  )
  const runtimeArtifact = await privateArtifact(
    status,
    'runtime_manifest',
    runDirectory,
    canonicalRun,
    MAX_GATE_JSON_BYTES,
  )
  const [contentDocument, runtimeDocument] = await Promise.all([
    readGateJson(contentArtifact),
    readGateJson(runtimeArtifact),
  ])
  const contentSha256 = createHash('sha256').update(contentDocument.bytes).digest('hex')
  const runtimeSha256 = createHash('sha256').update(runtimeDocument.bytes).digest('hex')
  if (contentSha256 !== contentArtifact.sha256 || runtimeSha256 !== runtimeArtifact.sha256) {
    throw new Error('GATE_EVIDENCE_INVALID')
  }
  return {
    revision,
    analysisManifest: buildOperatorAnalysisManifest({
      runId: local.runId,
      content: contentDocument.value,
      runtime: runtimeDocument.value,
    }),
  }
}

const uploadAnalysisManifest = async (config, claim, manifest) => {
  const response = await request(
    `${config.operatorApiUrl}/v1/runner/runs/${claim.runId}/analysis-manifest`,
    {
      method: 'POST',
      headers: operatorHeaders(config),
      body: JSON.stringify({
        runnerId: config.runnerId,
        leaseToken: claim.leaseToken,
        rounds: manifest.rounds,
        wordCues: manifest.wordCues,
      }),
    },
    config.requestTimeoutMs,
  )
  if (response.status === 409) throw new Error('ANALYSIS_MANIFEST_LEASE_LOST')
  if (!response.ok) throw new Error(`ANALYSIS_MANIFEST_HTTP_${response.status}`)
  const result = await readJson(response)
  if (
    !record(result) ||
    result.runId !== claim.runId ||
    result.roundsStored !== manifest.rounds.length ||
    typeof result.alignedPhraseCount !== 'number' ||
    typeof result.unmatchedPhraseCount !== 'number'
  ) throw new Error('ANALYSIS_MANIFEST_RESPONSE_INVALID')
}

const uploadPreview = async (config, claim, local) => {
  if (!local.previewUrl) throw new Error('PREVIEW_REQUIRED')
  if (!publicQaReady(local)) throw new Error('QUALITY_GATE_FAILED')
  const previewResponse = await request(local.previewUrl, {
    headers: { Accept: 'video/mp4' },
  }, config.previewTimeoutMs)
  if (!previewResponse.ok) throw new Error('PREVIEW_DOWNLOAD_FAILED')
  const contentType = previewResponse.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase()
  if (contentType !== 'video/mp4') throw new Error('PREVIEW_CONTENT_TYPE_INVALID')
  const bytes = new Uint8Array(await previewResponse.arrayBuffer())
  if (bytes.byteLength < 1 || bytes.byteLength > MAX_PREVIEW_BYTES) throw new Error('PREVIEW_SIZE_INVALID')
  const previewSha256 = createHash('sha256').update(bytes).digest('hex')
  const evidence = await verifyGateEvidence(config, local, previewSha256, bytes.byteLength)
  await uploadAnalysisManifest(config, claim, evidence.analysisManifest)
  const response = await request(`${config.operatorApiUrl}/v1/runner/runs/${claim.runId}/preview`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${config.runnerToken}`,
      'Content-Type': 'video/mp4',
      'Content-Length': String(bytes.byteLength),
      'X-Runner-Id': config.runnerId,
      'X-Lease-Token': claim.leaseToken,
      'X-Preview-Sha256': previewSha256,
      'X-Video-Revision': String(evidence.revision),
      'X-Quality-Gate': 'passed',
      'X-Monetization-Gate': 'passed',
    },
    body: bytes,
  }, config.previewTimeoutMs)
  if (!response.ok) throw new Error(`PREVIEW_UPLOAD_HTTP_${response.status}`)
  const metadata = await readJson(response)
  if (
    !metadata || typeof metadata !== 'object' || Array.isArray(metadata) ||
    metadata.sha256 !== previewSha256 || metadata.sizeBytes !== bytes.byteLength ||
    metadata.revision !== evidence.revision ||
    metadata.qualityPassed !== true ||
    metadata.monetizationPassed !== true
  ) throw new Error('PREVIEW_UPLOAD_RESPONSE_INVALID')
}

const prepareCompleted = async (config, claim, local) => {
  if (local.status !== 'completed') return local
  try {
    await uploadPreview(config, claim, local)
    return local
  } catch (error) {
    const code = error instanceof Error ? error.message : 'PREVIEW_UPLOAD_FAILED'
    if (
      code === 'QUALITY_GATE_FAILED' ||
      code === 'MONETIZATION_GATE_FAILED' ||
      code === 'GATE_EVIDENCE_INVALID' ||
      code === 'PREVIEW_REQUIRED'
    ) {
      return failedStatus(claim, code)
    }
    if (code === 'GATE_EVIDENCE_UNAVAILABLE') {
      return {
        ...waitingStatus(claim, 'Lokaler QA- und Monetarisierungsbeleg ist noch nicht verfügbar.'),
        progress: 99,
        currentStep: 'gate_verification',
      }
    }
    return {
      ...waitingStatus(claim, 'Vorschau konnte noch nicht sicher in die Cloud übertragen werden.'),
      progress: 99,
      currentStep: 'preview_upload',
    }
  }
}

const startLocal = async (config, claim) => {
  let response
  try {
    response = await request(`${config.controlApiUrl}/v1/video-runs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(claim.command),
    }, config.requestTimeoutMs)
  } catch {
    return waitingStatus(claim)
  }
  if (!response.ok) {
    return response.status >= 500
      ? waitingStatus(claim)
      : failedStatus(claim, response.status === 400 ? 'LOCAL_INPUT_REJECTED' : 'LOCAL_CONTROL_REJECTED')
  }
  const local = parsePublicRun(await readJson(response))
  if (
    local.status !== 'failed' ||
    !LOCALLY_RETRYABLE_PREVIEW_STEPS.has(local.currentStep)
  ) return local

  let retryResponse
  try {
    retryResponse = await request(
      `${config.controlApiUrl}/v1/video-runs/${encodeURIComponent(local.runId)}/retry`,
      { method: 'POST' },
      config.requestTimeoutMs,
    )
  } catch {
    return local
  }
  if (retryResponse.status !== 202) return local
  try {
    const retried = parsePublicRun(await readJson(retryResponse))
    return retried.runId === local.runId ? retried : local
  } catch {
    return local
  }
}

const readLocal = async (config, runId) => {
  const response = await request(`${config.controlApiUrl}/v1/video-runs/${encodeURIComponent(runId)}`, {
    headers: { Accept: 'application/json' },
  }, config.requestTimeoutMs)
  if (!response.ok) throw new Error(`Lokaler Statusabruf fehlgeschlagen (HTTP ${response.status}).`)
  return parsePublicRun(await readJson(response))
}

export const processClaim = async (config, claim, options = {}) => {
  const singleStatus = options.singleStatus === true
  let local = await startLocal(config, claim)
  local = await prepareCompleted(config, claim, local)
  if (!await remoteStatus(config, claim, local)) return 'lease-lost'
  if (singleStatus || ['waiting', 'completed', 'failed'].includes(local.status)) return local.status

  while (!['waiting', 'completed', 'failed'].includes(local.status)) {
    await delay(config.localPollIntervalMs)
    try {
      local = await readLocal(config, local.runId)
    } catch {
      local = waitingStatus(claim, 'Lokaler Status ist vorübergehend nicht erreichbar.')
    }
    local = await prepareCompleted(config, claim, local)
    if (!await remoteStatus(config, claim, local)) return 'lease-lost'
  }
  return local.status
}

export const runOnce = async (config, options = {}) => {
  const claim = await claimNextRun(config)
  if (!claim) return 'idle'
  return processClaim(config, claim, options)
}

export const runDaemon = async (config, options = {}) => {
  const signal = options.signal
  while (!signal?.aborted) {
    try {
      const result = await runOnce(config)
      if (result === 'idle' || result === 'waiting') await delay(config.pollIntervalMs)
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unbekannter Runner-Fehler.'
      console.error(`[operator-runner] ${message}`)
      await delay(config.pollIntervalMs)
    }
  }
}

const main = async () => {
  const config = loadRunnerConfig()
  const once = process.argv.includes('--once')
  if (once) {
    const result = await runOnce(config, { singleStatus: true })
    console.log(`[operator-runner] ${result}`)
    return
  }
  const controller = new AbortController()
  const stop = () => controller.abort()
  process.once('SIGINT', stop)
  process.once('SIGTERM', stop)
  console.log(`[operator-runner] aktiv als ${config.runnerId}`)
  await runDaemon(config, { signal: controller.signal })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {
    console.error(`[operator-runner] ${error instanceof Error ? error.message : 'Start fehlgeschlagen.'}`)
    process.exitCode = 1
  })
}
