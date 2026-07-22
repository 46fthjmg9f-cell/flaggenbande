import assert from 'node:assert/strict'
import { createServer } from 'node:http'
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

const config = (operatorApiUrl, controlApiUrl) => ({
  operatorApiUrl,
  runnerToken: 'runner-test-token',
  runnerId: 'test-mac',
  controlApiUrl,
  pollIntervalMs: 10,
  requestTimeoutMs: 1_000,
  localPollIntervalMs: 10,
  leaseSeconds: 60,
})

const script = [
  'was läuft was läuft, schnelles flaggenquiz',
  'fängt easy an, welches land ist das?',
  '(auflösung)',
  'okok lass den bre mal kochen, weißt du das auch?',
  '(auflösung)',
  'okay hier geht was, welches land ist hier?',
  '(auflösung)',
  'crazy, lad dir flink die flaggenbande app runter, sag an?',
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
  const runId = 'video-0123456789abcdef01234567'
  const statusUpdates = []
  let receivedScript = null
  let claimCount = 0

  const local = await listen(async (request, response) => {
    if (request.method === 'POST' && request.url === '/v1/video-runs') {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      receivedScript = JSON.parse(Buffer.concat(chunks).toString('utf8')).script
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        runId,
        status: 'completed',
        progress: 100,
        targetDurationSeconds: 65,
        actualDurationSeconds: 64.2,
        currentStep: 'preview_ready',
        steps: [],
        message: 'Vorschau bereit.',
        error: null,
        previewUrl: 'http://127.0.0.1/preview',
      }))
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => local.close())

  const operator = await listen(async (request, response) => {
    if (request.url === '/v1/runner/claim') {
      claimCount += 1
      response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
        run: { runId },
        command: { script, targetDurationSeconds: 65, clientRequestId: 'request-12345678' },
        leaseToken: 'lease-token-12345678901234567890',
      }))
      return
    }
    if (request.url === `/v1/runner/runs/${runId}/status`) {
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      statusUpdates.push(JSON.parse(Buffer.concat(chunks).toString('utf8')))
      response.writeHead(200, { 'content-type': 'application/json' }).end('{}')
      return
    }
    response.writeHead(404).end()
  })
  t.after(() => operator.close())

  const result = await runOnce(config(operator.url, local.url), { singleStatus: true })
  assert.equal(result, 'completed')
  assert.equal(claimCount, 1)
  assert.equal(receivedScript, script)
  assert.equal(statusUpdates.length, 1)
  assert.deepEqual(statusUpdates[0], {
    runnerId: 'test-mac',
    leaseToken: 'lease-token-12345678901234567890',
    status: 'completed',
    progress: 100,
    currentStep: 'preview_ready',
    message: 'Vorschau bereit.',
    error: null,
    providerRunId: runId,
  })
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
