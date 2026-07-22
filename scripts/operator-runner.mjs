import { hostname } from 'node:os'
import { pathToFileURL } from 'node:url'

const RUN_ID_PATTERN = /^video-[a-f0-9]{24}$/u
const LOCAL_STATUSES = new Set(['queued', 'running', 'waiting', 'completed', 'failed'])

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

export const loadRunnerConfig = (env = process.env) => ({
  operatorApiUrl: normalizedUrl(required(env, 'OPERATOR_API_URL'), 'OPERATOR_API_URL'),
  runnerToken: required(env, 'OPERATOR_RUNNER_TOKEN'),
  runnerId: safeRunnerId(env.OPERATOR_RUNNER_ID?.trim() || `mac-${hostname()}`),
  controlApiUrl: normalizedUrl(env.VIDEO_CONTROL_API_URL?.trim() || 'http://127.0.0.1:4317', 'VIDEO_CONTROL_API_URL'),
  pollIntervalMs: integerSetting(env, 'OPERATOR_POLL_INTERVAL_MS', 5_000, 1_000, 60_000),
  requestTimeoutMs: integerSetting(env, 'OPERATOR_REQUEST_TIMEOUT_MS', 15_000, 1_000, 120_000),
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

const parsePublicRun = value => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Produktionsstatus ist ungültig.')
  const run = value
  if (
    typeof run.runId !== 'string' || !RUN_ID_PATTERN.test(run.runId) ||
    typeof run.status !== 'string' || !LOCAL_STATUSES.has(run.status) ||
    typeof run.progress !== 'number' || !Number.isFinite(run.progress) || run.progress < 0 || run.progress > 100
  ) throw new Error('Produktionsstatus ist unvollständig.')
  return {
    runId: run.runId,
    status: run.status,
    progress: run.progress,
    currentStep: safeNullableText(run.currentStep, 100),
    message: safeNullableText(run.message),
    error: safeNullableText(run.error, 100),
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
      error: failed ? 'LOCAL_PRODUCTION_FAILED' : null,
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
  message: 'Lokale Produktions-Engine hat den Auftrag abgelehnt.',
  error: code,
})

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
  return parsePublicRun(await readJson(response))
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
  if (!await remoteStatus(config, claim, local)) return 'lease-lost'
  if (singleStatus || ['waiting', 'completed', 'failed'].includes(local.status)) return local.status

  while (!['waiting', 'completed', 'failed'].includes(local.status)) {
    await delay(config.localPollIntervalMs)
    try {
      local = await readLocal(config, local.runId)
    } catch {
      local = waitingStatus(claim, 'Lokaler Status ist vorübergehend nicht erreichbar.')
    }
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
