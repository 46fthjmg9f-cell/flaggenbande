import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { claimNextRun, loadRunnerConfig, runOnce } from '../scripts/operator-runner.mjs'

const listen = async handler => {
  const server = createServer(handler)
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolve)
  })
  const address = server.address()
  if (!address || typeof address === 'string') throw new Error('Testserver konnte nicht gestartet werden.')
  return {
    url: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())),
  }
}

const config = (operatorApiUrl, controlApiUrl, localRunsRoot = join(tmpdir(), 'unused-operator-runs')) => ({
  operatorApiUrl,
  runnerToken: 'runner-test-token',
  runnerId: 'test-mac',
  controlApiUrl,
  localRunsRoot,
  pollIntervalMs: 10,
  requestTimeoutMs: 1_000,
  previewTimeoutMs: 1_000,
  localPollIntervalMs: 10,
  leaseSeconds: 60,
})

const publicSteps = () => [
  'script_validation',
  'flag_selection',
  'voice_preparation',
  'timeline_build',
  'audio_design',
  'render',
  'quality_check',
  'preview_ready',
].map(id => ({
  id,
  label: id,
  status: 'completed',
  progress: 100,
  message: null,
}))

const writeGateEvidence = async (runsRoot, runId, previewBytes, options = {}) => {
  const runDirectory = join(runsRoot, runId)
  const artifactsDirectory = join(runDirectory, 'artifacts', 'production')
  await mkdir(artifactsDirectory, { recursive: true })
  const previewPath = join(artifactsDirectory, `${runId}.mp4`)
  const qualityReportPath = join(artifactsDirectory, `${runId}-quality-report.json`)
  const previewSha256 = createHash('sha256').update(previewBytes).digest('hex')
  await writeFile(previewPath, previewBytes)
  const monetizationPassed = options.monetizationPassed !== false
  const qualityReport = {
    schemaVersion: '1.0.0',
    status: 'passed',
    publicationAuthorized: false,
    video: {
      path: previewPath,
      sha256: previewSha256,
      sizeBytes: previewBytes.byteLength,
      width: 1080,
      height: 1920,
      fps: 30,
      durationSeconds: 64.2,
      videoCodec: 'h264',
      audioCodec: 'aac',
    },
    audio: { present: true, clippingDetected: false },
    blackFrames: { status: 'passed' },
    timing: { status: 'passed' },
    flags: { status: 'passed' },
    assets: { status: 'passed' },
    textOverlays: { status: 'passed' },
    visibleTestMarker: false,
    tiktokCreatorRewards: {
      schemaVersion: '1.0.0',
      program: 'tiktok_creator_rewards',
      localGateStatus: monetizationPassed ? 'passed' : 'failed',
      platformEligibilityStatus: 'requires_tiktok_verification',
      checks: {
        durationAtLeast61Seconds: true,
        sufficientSpokenContent: true,
        fiveDistinctFlags: true,
        noDirectDownloadPromotion: monetizationPassed,
        originalMusic: true,
        originalSoundEffects: true,
        customVisualComposition: true,
      },
      issues: monetizationPassed ? [] : ['Direkte Werbung erkannt.'],
    },
  }
  const qualityBytes = Buffer.from(`${JSON.stringify(qualityReport, null, 2)}\n`)
  const qualitySha256 = createHash('sha256').update(qualityBytes).digest('hex')
  await writeFile(qualityReportPath, qualityBytes)
  await writeFile(join(runDirectory, 'status.json'), `${JSON.stringify({
    schemaVersion: '1.0.0',
    runId,
    revision: 17,
    status: 'qa_ready',
    currentStep: 'preview_ready',
    steps: [
      { id: 'quality_gate', status: 'passed', progress: 100 },
      { id: 'preview_ready', status: 'passed', progress: 100 },
    ],
    privateArtifacts: [
      { kind: 'preview_video', path: previewPath, sha256: previewSha256 },
      { kind: 'quality_report', path: qualityReportPath, sha256: qualitySha256 },
    ],
  }, null, 2)}\n`)
  return { previewSha256 }
}

const script = [
  'was läuft was läuft, schnelles flaggenquiz',
  'fängt easy an, welches land ist das?',
  '(auflösung)',
  'okok lass den bre mal kochen, weißt du das auch?',
  '(auflösung)',
  'okay hier geht was, welches land ist hier?',
  '(auflösung)',
  'crazy, ab hier trennt sich glück von echter ahnung, sag an?',
  '(auflösung)',
  'ready fürs große finale, welche flagge ist das?',
  '(auflösung)',
  'anscheinend der allerechte flaggenboss, nice',
].join('\n')

test('runner config refuses an internet-facing local production API', () => {
  assert.throws(() => loadRunnerConfig({
    OPERATOR_API_URL: 'https://operator.example.test',
    OPERATOR_RUNNER_TOKEN: 'secret',
    VIDEO_CONTROL_API_URL: 'https://production.example.test',
  }), /Loopback/)
})

test('runner config requires the private local run root for checksum-bound gate evidence', () => {
  assert.throws(() => loadRunnerConfig({
    OPERATOR_API_URL: 'https://operator.example.test',
    OPERATOR_RUNNER_TOKEN: 'secret',
    VIDEO_CONTROL_API_URL: 'http://127.0.0.1:4317',
  }), /OPERATOR_LOCAL_RUNS_ROOT fehlt/)
})

test('claim sends only the separate runner token and handles an empty queue', async t => {
  let authorization = null
  const operator = await listen((request, response) => {
    authorization = request.headers.authorization
    response.writeHead(204).end()
  })
  t.after(() => operator.close())
  const result = await claimNextRun(config(operator.url, 'http://127.0.0.1:4317'))
  assert.equal(result, null)
  assert.equal(authorization, 'Bearer runner-test-token')
})

test('runner forwards one queued command to loopback and reports completion', async t => {
  const cloudRunId = 'video-aaaaaaaaaaaaaaaaaaaaaaaa'
  const localRunId = 'video-0123456789abcdef01234567'
  const runsRoot = await mkdtemp(join(tmpdir(), 'operator-runner-'))
  t.after(() => rm(runsRoot, { recursive: true, force: true }))
  const statusUpdates = []
  const previewUploads = []
  let receivedScript = null
  let claimCount = 0
  const previewBytes = Buffer.from('preview-bytes')
  await writeGateEvidence(runsRoot, localRunId, previewBytes)

  const local = await listen(async (request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      receivedScript = JSON.parse(Buffer.concat(chunks).toString('utf8')).script
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId: localRunId,
        status: 'completed',
        progress: 100,
        targetDurationSeconds: 65,
        actualDurationSeconds: 64.2,
        currentStep: 'preview_ready',
        steps: publicSteps(),
        message: 'Vorschau bereit.',
        error: null,
        previewUrl: `${local.url}/preview`,
      }))
      return
    }
    if (request.method === 'GET' && request.url === '/preview') {
      response.writeHead(200, {
        'content-type': 'video/mp4',
        'content-length': String(previewBytes.byteLength),
      }).end(previewBytes)
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      claimCount += 1
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId: cloudRunId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-12345678' },
        leaseToken: 'lease-token-12345678901234567890',
      }))
      return
    }
    if (request.url === `/v1/runner/runs/${cloudRunId}/status`) {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      statusUpdates.push(JSON.parse(Buffer.concat(chunks).toString('utf8')))
      response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
      return
    }
    if (request.method === 'PUT' && request.url === `/v1/runner/runs/${cloudRunId}/preview`) {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      const bytes = Buffer.concat(chunks)
      previewUploads.push({
        headers: request.headers,
        bytes,
      })
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        sha256: request.headers['x-preview-sha256'],
        sizeBytes: bytes.byteLength,
        revision: Number(request.headers['x-video-revision']),
        qualityPassed: true,
        monetizationPassed: true,
      }))
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, local.url, runsRoot), { singleStatus: true })
  assert.equal(result, 'completed')
  assert.equal(claimCount, 1)
  assert.equal(receivedScript, script)
  assert.equal(previewUploads.length, 1)
  assert.equal(previewUploads[0].headers['x-quality-gate'], 'passed')
  assert.equal(previewUploads[0].headers['x-monetization-gate'], 'passed')
  assert.equal(previewUploads[0].headers['x-video-revision'], '17')
  assert.equal(previewUploads[0].bytes.toString('utf8'), 'preview-bytes')
  assert.equal(statusUpdates.length, 1)
  assert.deepEqual(statusUpdates[0], {
    runnerId: 'test-mac',
    leaseToken: 'lease-token-12345678901234567890',
    status: 'completed',
    progress: 100,
    currentStep: 'preview_ready',
    message: 'Vorschau bereit.',
    error: null,
    providerRunId: localRunId,
  })
})

test('runner ignores invented gate booleans when the real public QA steps are incomplete', async t => {
  const runId = 'video-bbbbbbbbbbbbbbbbbbbbbbbb'
  const updates = []
  let previewRequested = false
  const local = await listen((request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      const steps = publicSteps()
      steps.find(step => step.id === 'quality_check').status = 'waiting'
      steps.find(step => step.id === 'quality_check').progress = 99
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId,
        status: 'completed',
        progress: 100,
        currentStep: 'preview_ready',
        steps,
        message: 'Vorschau bereit.',
        error: null,
        previewUrl: `${local.url}/preview`,
        qualityPassed: true,
        monetizationPassed: true,
      }))
      return
    }
    if (request.url === '/preview') previewRequested = true
    response.writeHead(404).end()
  })
  t.after(() => local.close())
  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-gate-shape' },
        leaseToken: 'lease-token-bbbbbbbbbbbbbbbbbbbbbbbb',
      }))
      return
    }
    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    updates.push(JSON.parse(Buffer.concat(chunks).toString('utf8')))
    response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, local.url), { singleStatus: true })
  assert.equal(result, 'failed')
  assert.equal(previewRequested, false)
  assert.equal(updates.length, 1)
  assert.equal(updates[0].error, 'QUALITY_GATE_FAILED')
})

test('runner refuses upload when the checksum-bound local monetization report failed', async t => {
  const runId = 'video-cccccccccccccccccccccccc'
  const runsRoot = await mkdtemp(join(tmpdir(), 'operator-runner-'))
  t.after(() => rm(runsRoot, { recursive: true, force: true }))
  const previewBytes = Buffer.from('preview-with-failed-gate')
  await writeGateEvidence(runsRoot, runId, previewBytes, { monetizationPassed: false })
  const updates = []
  let previewUploadCount = 0

  const local = await listen((request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId,
        status: 'completed',
        progress: 100,
        currentStep: 'preview_ready',
        steps: publicSteps(),
        message: 'Vorschau bereit.',
        error: null,
        previewUrl: `${local.url}/preview`,
      }))
      return
    }
    if (request.url === '/preview') {
      response.writeHead(200, {
        'content-type': 'video/mp4',
        'content-length': String(previewBytes.byteLength),
      }).end(previewBytes)
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-gate-failed' },
        leaseToken: 'lease-token-cccccccccccccccccccccccc',
      }))
      return
    }
    if (request.method === 'PUT' && request.url.endsWith('/preview')) {
      previewUploadCount += 1
      response.writeHead(500).end()
      return
    }
    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    updates.push(JSON.parse(Buffer.concat(chunks).toString('utf8')))
    response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, local.url, runsRoot), { singleStatus: true })
  assert.equal(result, 'failed')
  assert.equal(previewUploadCount, 0)
  assert.equal(updates.length, 1)
  assert.equal(updates[0].error, 'MONETIZATION_GATE_FAILED')
})

test('unreachable local engine leaves the cloud job waiting instead of failing or publishing', async t => {
  const runId = 'video-fedcba9876543210fedcba98'
  const updates = []
  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-87654321' },
        leaseToken: 'lease-token-abcdefghijklmnopqrstuvwxyz',
      }))
      return
    }
    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    updates.push(JSON.parse(Buffer.concat(chunks).toString('utf8')))
    response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, 'http://127.0.0.1:1'), { singleStatus: true })
  assert.equal(result, 'waiting')
  assert.equal(updates[0].status, 'waiting')
  assert.equal(updates[0].error, null)
})
