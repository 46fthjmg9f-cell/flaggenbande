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
  const contentManifestPath = join(artifactsDirectory, `${runId}-content.json`)
  const runtimeManifestPath = join(artifactsDirectory, `${runId}-runtime.json`)
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
  const countries = [
    ['de', 'Deutschland'],
    ['uy', 'Uruguay'],
    ['mz', 'Mosambik'],
    ['pw', 'Palau'],
    ['vu', 'Vanuatu'],
  ]
  const contentBytes = Buffer.from(`${JSON.stringify({
    schemaVersion: '1.0.0',
    runId,
    roundCount: 5,
    rounds: countries.map(([iso, answer], index) => ({ round: index + 1, iso, answer })),
  }, null, 2)}\n`)
  const runtimeBytes = Buffer.from(`${JSON.stringify({
    schemaVersion: '1.0.0',
    fps: 30,
    rounds: countries.map((_, index) => ({
      round: index + 1,
      questionFromFrame: index * 300,
      revealFrame: index * 300 + 120,
    })),
    words: [
      { word: 'welche', fromFrame: 0, durationInFrames: 9 },
      { word: 'flagge', fromFrame: 10, durationInFrames: 8 },
    ],
  }, null, 2)}\n`)
  const contentSha256 = createHash('sha256').update(contentBytes).digest('hex')
  const runtimeSha256 = createHash('sha256').update(runtimeBytes).digest('hex')
  await Promise.all([
    writeFile(contentManifestPath, contentBytes),
    writeFile(runtimeManifestPath, runtimeBytes),
  ])
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
      { kind: 'content_manifest', path: contentManifestPath, sha256: contentSha256 },
      { kind: 'runtime_manifest', path: runtimeManifestPath, sha256: runtimeSha256 },
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
  const analysisManifests = []
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
    if (request.method === 'POST' && request.url === `/v1/runner/runs/${cloudRunId}/analysis-manifest`) {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      const manifest = JSON.parse(Buffer.concat(chunks).toString('utf8'))
      analysisManifests.push(manifest)
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId: cloudRunId,
        roundsStored: manifest.rounds.length,
        alignedPhraseCount: 1,
        unmatchedPhraseCount: 8,
      }))
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
  assert.equal(analysisManifests.length, 1)
  assert.equal(analysisManifests[0].rounds[0].solutionCountry, 'Deutschland')
  assert.deepEqual(analysisManifests[0].wordCues[0], {
    word: 'welche',
    startSeconds: 0,
    endSeconds: 0.3,
  })
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

test('runner retries one matching local flag-selection failure without creating a new run', async t => {
  const cloudRunId = 'video-dddddddddddddddddddddddd'
  const localRunId = 'video-eeeeeeeeeeeeeeeeeeeeeeee'
  let startCount = 0
  let retryCount = 0
  const updates = []
  const failedRun = {
    runId: localRunId,
    status: 'failed',
    progress: 23,
    currentStep: 'flag_selection',
    steps: publicSteps(),
    message: 'Flaggenauswahl fehlgeschlagen.',
    error: 'PRODUCTION_STEP_FAILED',
    previewUrl: null,
  }

  const local = await listen((request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      startCount += 1
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(failedRun))
      return
    }
    if (request.method === 'POST' && request.url === `/v1/video-runs/${localRunId}/retry`) {
      retryCount += 1
      response.writeHead(202, { 'content-type': 'application/json' }).end(JSON.stringify({
        ...failedRun,
        status: 'queued',
        message: 'Sicher erneut eingeplant.',
        error: null,
      }))
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId: cloudRunId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-local-retry-0001' },
        leaseToken: 'lease-token-dddddddddddddddddddddddd',
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
  assert.equal(result, 'queued')
  assert.equal(startCount, 1)
  assert.equal(retryCount, 1)
  assert.equal(updates.length, 1)
  assert.equal(updates[0].status, 'running')
  assert.equal(updates[0].providerRunId, localRunId)
  assert.equal(updates[0].error, null)
})

test('runner preserves the failed status when the one local retry is rejected', async t => {
  const cloudRunId = 'video-111111111111111111111111'
  const localRunId = 'video-222222222222222222222222'
  let retryCount = 0
  const updates = []
  const failedRun = {
    runId: localRunId,
    status: 'failed',
    progress: 23,
    currentStep: 'flag_selection',
    steps: publicSteps(),
    message: 'Flaggenauswahl fehlgeschlagen.',
    error: 'PRODUCTION_STEP_FAILED',
    previewUrl: null,
  }

  const local = await listen((request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(failedRun))
      return
    }
    if (request.method === 'POST' && request.url === `/v1/video-runs/${localRunId}/retry`) {
      retryCount += 1
      response.writeHead(409, { 'content-type': 'application/json' }).end('{"error":"RUN_RETRY_NOT_ALLOWED"}')
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId: cloudRunId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-local-retry-0002' },
        leaseToken: 'lease-token-111111111111111111111111',
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
  assert.equal(retryCount, 1)
  assert.equal(updates.length, 1)
  assert.equal(updates[0].status, 'failed')
  assert.equal(updates[0].providerRunId, localRunId)
  assert.equal(updates[0].error, 'PRODUCTION_STEP_FAILED')
})

test('runner never retries a local failure outside the safe flag-selection step', async t => {
  const runId = 'video-333333333333333333333333'
  let retryCount = 0
  const local = await listen((request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId,
        status: 'failed',
        progress: 77,
        currentStep: 'render',
        steps: publicSteps(),
        message: 'Render fehlgeschlagen.',
        error: 'PRODUCTION_STEP_FAILED',
        previewUrl: null,
      }))
      return
    }
    if (request.method === 'POST' && request.url.includes('/retry')) retryCount += 1
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-local-retry-0003' },
        leaseToken: 'lease-token-333333333333333333333333',
      }))
      return
    }
    for await (const _chunk of request) {
      // Drain the request before replying.
    }
    response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, local.url), { singleStatus: true })
  assert.equal(result, 'failed')
  assert.equal(retryCount, 0)
})
