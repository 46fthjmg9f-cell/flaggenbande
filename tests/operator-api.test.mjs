import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { DatabaseSync } from 'node:sqlite'
import test from 'node:test'
import worker from '../cloud/operator-api/src/index.ts'

const workerUrl = new URL('../cloud/operator-api/src/index.ts', import.meta.url)
const schemaUrl = new URL('../cloud/operator-api/schema.sql', import.meta.url)
const envUrl = new URL('../.env.operator.example', import.meta.url)

test('operator API separates browser and local-runner credentials', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.match(source, /OPERATOR_API_TOKEN/)
  assert.match(source, /OPERATOR_RUNNER_TOKEN/)
  assert.match(source, /const operatorAuthorized/)
  assert.match(source, /const runnerAuthorized/)
  assert.match(source, /url\.pathname\.startsWith\("\/v1\/runner\/"\)/)
  assert.doesNotMatch(source, /console\.(?:log|error)/)
})

test('operator API exposes separate operator and redacted public projections', async () => {
  const source = await readFile(workerUrl, 'utf8')
  for (const route of ['/v1/runs', '/v1/public/runs', '/v1/calendar', '/v1/runner/claim']) {
    assert.match(source, new RegExp(route.replaceAll('/', '\\/')))
  }
  const start = source.indexOf('const publicRun =')
  const end = source.indexOf('const completeRun =', start)
  const publicProjection = source.slice(start, end)
  for (const key of [
    'runId', 'releaseLabel', 'status', 'progress', 'targetDurationSeconds',
    'currentStep', 'message', 'error', 'scriptStatus', 'previewReady',
    'videoApprovalStatus', 'createdAt', 'updatedAt',
  ]) {
    assert.match(publicProjection, new RegExp(`${key}:`))
  }
  assert.doesNotMatch(publicProjection, /text:\s*row\.script|preview_object_key\s*:|\blease\b|clientRequestId|providerRunId|inputSha/)
})

test('queue schema is idempotent, leased and append-only observable', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  assert.match(schema, /input_sha256 TEXT NOT NULL UNIQUE/)
  assert.match(schema, /client_request_id TEXT NOT NULL UNIQUE/)
  assert.match(schema, /lease_token_sha256 TEXT/)
  assert.match(schema, /CHECK \(status IN \('queued', 'claimed', 'running', 'waiting', 'completed', 'failed'\)\)/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_production_events/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_production_reviews/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_release_requests/)
  assert.match(schema, /run_id TEXT NOT NULL UNIQUE/)
  assert.match(schema, /FOREIGN KEY \(run_id\) REFERENCES operator_production_runs\(run_id\)/)
})

test('calendar contract keeps all four platform states without provider secrets', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.match(source, /"youtube", "instagram", "facebook", "tiktok"/)
  assert.match(source, /"scheduled", "publishing", "published", "failed", "missing"/)
  const start = source.indexOf('const publicCalendarEntry =')
  const end = source.indexOf('const upsertCalendar =', start)
  const projection = source.slice(start, end)
  for (const key of ['id', 'contentId', 'title', 'scheduledAt', 'platforms']) {
    assert.match(projection, new RegExp(`${key}:`))
  }
  assert.doesNotMatch(projection, /token|secret|\blease\b|description/iu)
})

test('browser origins are explicit and wildcard CORS is absent', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.match(source, /DASHBOARD_ORIGINS/)
  assert.match(source, /ORIGIN_NOT_ALLOWED/)
  assert.doesNotMatch(source, /access-control-allow-origin["']?\s*[:,]\s*["']\*/iu)

  const env = await readFile(envUrl, 'utf8')
  assert.match(env, /^OPERATOR_API_TOKEN=$/mu)
  assert.match(env, /^OPERATOR_RUNNER_TOKEN=$/mu)
  assert.doesNotMatch(env, /Bearer\s+\S+/u)
})

test('operator API has no publishing capability', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.doesNotMatch(source, /media_publish|publishAt|videos\.insert|youtube\.googleapis|graph\.facebook|open\.tiktokapis/iu)
})

class D1Statement {
  constructor(database, query) {
    this.database = database
    this.query = query
    this.values = []
  }

  bind(...values) {
    const statement = new D1Statement(this.database, this.query)
    statement.values = values
    return statement
  }

  async first() {
    return this.database.prepare(this.query).get(...this.values) ?? null
  }

  async all() {
    return { results: this.database.prepare(this.query).all(...this.values) }
  }

  async run() {
    const result = this.database.prepare(this.query).run(...this.values)
    return { success: true, meta: { changes: Number(result.changes) } }
  }
}

class D1TestDatabase {
  constructor(schema) {
    this.database = new DatabaseSync(':memory:')
    this.database.exec(schema)
  }

  prepare(query) {
    return new D1Statement(this.database, query)
  }

  async batch(statements) {
    this.database.exec('BEGIN IMMEDIATE')
    try {
      const results = []
      for (const statement of statements) results.push(await statement.run())
      this.database.exec('COMMIT')
      return results
    } catch (error) {
      this.database.exec('ROLLBACK')
      throw error
    }
  }
}

class PreviewBucket {
  constructor() {
    this.objects = new Map()
  }

  async put(key, stream, options) {
    const bytes = new Uint8Array(await new Response(stream).arrayBuffer())
    const actual = createHash('sha256').update(bytes).digest('hex')
    const expected = Buffer.from(options.sha256).toString('hex')
    if (actual !== expected) throw new Error('checksum')
    this.objects.set(key, bytes)
  }

  async get(key, options) {
    const bytes = this.objects.get(key)
    if (!bytes) return null
    const range = options?.range
    const selected = range ? bytes.slice(range.offset, range.offset + range.length) : bytes
    return {
      body: new Response(selected).body,
      size: bytes.byteLength,
      etag: `"${createHash('sha256').update(bytes).digest('hex')}"`,
      httpMetadata: { contentType: 'video/mp4' },
    }
  }

  async delete(key) {
    this.objects.delete(key)
  }
}

const request = (path, token, init = {}) => new Request(`https://operator.example.test${path}`, {
  ...init,
  headers: {
    Authorization: `Bearer ${token}`,
    ...(init.headers ?? {}),
  },
})

const jsonBody = (body, method = 'POST') => ({
  method,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
})

test('two-stage approvals are hash-bound, idempotent and release exactly once', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const PREVIEWS = new PreviewBucket()
  const env = {
    DB,
    PREVIEWS,
    OPERATOR_API_TOKEN: 'operator-token',
    OPERATOR_RUNNER_TOKEN: 'runner-token',
  }
  const script = [
    'was läuft was läuft, schnelles flaggenquiz',
    'fängt easy an, welches land ist das?',
    '(auflösung)',
    'okok lass den bre mal kochen, weißt du das auch?',
    '(auflösung)',
    'okay hier geht was, welches land ist hier?',
    '(auflösung)',
    'crazy, sag an welche flagge ist das?',
    '(auflösung)',
    'ready fürs große finale, welche flagge ist das?',
    '(auflösung)',
    'anscheinend der allerechte flaggenboss, nice',
  ].join('\n')

  const createdResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script,
    targetDurationSeconds: 65,
    clientRequestId: 'approval-test-0001',
  })), env)
  assert.equal(createdResponse.status, 202)
  const created = await createdResponse.json()
  assert.equal(created.status, 'awaiting_script_approval')
  assert.match(created.releaseLabel, /^\d{4}\.\d{2}$/u)
  assert.equal(created.script.text, script)
  assert.equal(created.preview.revision, 0)

  const sameOriginList = await worker.fetch(request('/v1/runs', 'operator-token', {
    headers: { Origin: 'https://operator.example.test' },
  }), env)
  assert.equal(sameOriginList.status, 200)
  assert.equal(sameOriginList.headers.get('access-control-allow-origin'), 'https://operator.example.test')
  assert.equal(sameOriginList.headers.get('access-control-allow-credentials'), 'true')

  const claimBeforeApproval = await worker.fetch(request('/v1/runner/claim', 'runner-token', jsonBody({
    runnerId: 'test-runner',
    leaseSeconds: 60,
  })), env)
  assert.equal(claimBeforeApproval.status, 204)

  const wrongHash = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: '0'.repeat(64),
      scriptRevision: 1,
      idempotencyKey: 'script-approval-0001',
    }),
  ), env)
  assert.equal(wrongHash.status, 409)
  const wrongRevision = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: created.script.sha256,
      scriptRevision: 2,
      idempotencyKey: 'script-approval-0002',
    }),
  ), env)
  assert.equal(wrongRevision.status, 409)

  const approvalPayload = {
    scriptSha256: created.script.sha256,
    scriptRevision: created.script.revision,
    idempotencyKey: 'script-approval-0001',
  }
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const approved = await worker.fetch(request(
      `/v1/runs/${created.runId}/approve-script`,
      'operator-token',
      jsonBody(approvalPayload),
    ), env)
    assert.equal(approved.status, 200)
  }

  const runnerCannotApprove = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-video`,
    'runner-token',
    jsonBody({
      previewSha256: '1'.repeat(64),
      videoRevision: 1,
      idempotencyKey: 'video-approval-0001',
    }),
  ), env)
  assert.equal(runnerCannotApprove.status, 401)

  const prematureVideoApproval = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-video`,
    'operator-token',
    jsonBody({
      previewSha256: '1'.repeat(64),
      videoRevision: 1,
      idempotencyKey: 'video-approval-0001',
    }),
  ), env)
  assert.equal(prematureVideoApproval.status, 409)

  const claimResponse = await worker.fetch(request('/v1/runner/claim', 'runner-token', jsonBody({
    runnerId: 'test-runner',
    leaseSeconds: 60,
  })), env)
  assert.equal(claimResponse.status, 200)
  const claim = await claimResponse.json()

  const videoBytes = Buffer.from('verified-private-preview')
  const previewSha256 = createHash('sha256').update(videoBytes).digest('hex')
  const uploadResponse = await worker.fetch(request(
    `/v1/runner/runs/${created.runId}/preview`,
    'runner-token',
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'video/mp4',
        'Content-Length': String(videoBytes.byteLength),
        'X-Runner-Id': 'test-runner',
        'X-Lease-Token': claim.leaseToken,
        'X-Preview-Sha256': previewSha256,
        'X-Video-Revision': '1',
        'X-Quality-Gate': 'passed',
        'X-Monetization-Gate': 'passed',
      },
      body: videoBytes,
    },
  ), env)
  assert.equal(uploadResponse.status, 200)

  const previewWithoutAuth = await worker.fetch(new Request(
    `https://operator.example.test/v1/runs/${created.runId}/preview`,
  ), env)
  assert.equal(previewWithoutAuth.status, 401)
  const previewRange = await worker.fetch(request(
    `/v1/runs/${created.runId}/preview`,
    'operator-token',
    { headers: { Range: 'bytes=0-6' } },
  ), env)
  assert.equal(previewRange.status, 206)
  assert.equal(previewRange.headers.get('content-range'), `bytes 0-6/${videoBytes.byteLength}`)
  assert.equal(Buffer.from(await previewRange.arrayBuffer()).toString('utf8'), 'verifie')

  const beforeCompleted = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-video`,
    'operator-token',
    jsonBody({
      previewSha256,
      videoRevision: 1,
      idempotencyKey: 'video-approval-0001',
    }),
  ), env)
  assert.equal(beforeCompleted.status, 409)
  assert.equal((await beforeCompleted.json()).error, 'VIDEO_GATES_NOT_PASSED')

  const completed = await worker.fetch(request(
    `/v1/runner/runs/${created.runId}/status`,
    'runner-token',
    jsonBody({
      runnerId: 'test-runner',
      leaseToken: claim.leaseToken,
      status: 'completed',
      progress: 100,
      currentStep: 'preview_ready',
      message: 'Vorschau bereit.',
      error: null,
      providerRunId: created.runId,
    }),
  ), env)
  assert.equal(completed.status, 200)

  const videoApprovalPayload = {
    previewSha256,
    videoRevision: 1,
    idempotencyKey: 'video-approval-0001',
  }
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const approved = await worker.fetch(request(
      `/v1/runs/${created.runId}/approve-video`,
      'operator-token',
      jsonBody(videoApprovalPayload),
    ), env)
    assert.equal(approved.status, 200)
    const run = await approved.json()
    assert.equal(run.status, 'release_queued')
  }
  const releaseCount = DB.database.prepare(
    'SELECT COUNT(*) AS count FROM operator_release_requests WHERE run_id = ?',
  ).get(created.runId)
  assert.equal(releaseCount.count, 1)

  const publicResponse = await worker.fetch(new Request(
    `https://operator.example.test/v1/public/runs/${created.runId}`,
  ), env)
  assert.equal(publicResponse.status, 200)
  const publicRun = await publicResponse.json()
  assert.equal(publicRun.releaseLabel, created.releaseLabel)
  assert.equal(publicRun.scriptStatus, 'approved')
  assert.equal(publicRun.videoApprovalStatus, 'approved')
  assert.equal('script' in publicRun, false)
  assert.equal('preview' in publicRun, false)
  assert.doesNotMatch(JSON.stringify(publicRun), new RegExp(created.script.sha256, 'u'))
  assert.doesNotMatch(JSON.stringify(publicRun), /was läuft/iu)

  const releaseClaimResponse = await worker.fetch(request(
    '/v1/release-runner/claim',
    'runner-token',
    jsonBody({ runnerId: 'release-runner', leaseSeconds: 60 }),
  ), env)
  assert.equal(releaseClaimResponse.status, 200)
  const releaseClaim = await releaseClaimResponse.json()
  assert.equal(releaseClaim.request.runId, created.runId)
  assert.equal(releaseClaim.request.releaseLabel, created.releaseLabel)
  assert.equal(releaseClaim.request.previewSha256, previewSha256)
  assert.deepEqual(releaseClaim.request.platforms, ['youtube', 'instagram', 'facebook'])

  const releasePreviewResponse = await worker.fetch(request(
    releaseClaim.request.previewUrl,
    'runner-token',
  ), env)
  assert.equal(releasePreviewResponse.status, 200)
  assert.equal(releasePreviewResponse.headers.get('x-preview-sha256'), previewSha256)
  assert.equal(Buffer.from(await releasePreviewResponse.arrayBuffer()).toString('utf8'), videoBytes.toString('utf8'))

  const publishedPlatforms = {
    youtube: { status: 'published', publicUrl: 'https://www.youtube.com/shorts/example' },
    instagram: { status: 'published', publicUrl: 'https://www.instagram.com/reel/example/' },
    facebook: { status: 'published', publicUrl: 'https://www.facebook.com/reel/example/' },
    tiktok: { status: 'missing' },
  }
  const releaseUpdateResponse = await worker.fetch(request(
    `/v1/release-runner/requests/${releaseClaim.request.requestId}/status`,
    'runner-token',
    jsonBody({
      runnerId: 'release-runner',
      leaseToken: releaseClaim.leaseToken,
      platforms: publishedPlatforms,
      message: 'Drei Plattformen veröffentlicht.',
      error: null,
    }),
  ), env)
  assert.equal(releaseUpdateResponse.status, 200)
  const publishedRun = await releaseUpdateResponse.json()
  assert.equal(publishedRun.status, 'published')
  assert.equal(publishedRun.release.status, 'completed')
  assert.deepEqual(publishedRun.release.platforms, publishedPlatforms)

  const calendarResponse = await worker.fetch(new Request(
    'https://operator.example.test/v1/public/calendar?from=2026-01-01T00:00:00.000Z&to=2027-01-01T00:00:00.000Z',
  ), env)
  assert.equal(calendarResponse.status, 400, 'calendar ranges remain capped at 31 days')
  const createdAt = new Date(created.createdAt)
  const calendarFrom = new Date(createdAt.getTime() - 60_000).toISOString()
  const calendarTo = new Date(createdAt.getTime() + 86_400_000).toISOString()
  const focusedCalendar = await worker.fetch(new Request(
    `https://operator.example.test/v1/public/calendar?from=${encodeURIComponent(calendarFrom)}&to=${encodeURIComponent(calendarTo)}`,
  ), env)
  assert.equal(focusedCalendar.status, 200)
  const calendar = await focusedCalendar.json()
  assert.equal(calendar.entries.length, 1)
  assert.equal(calendar.entries[0].releaseLabel, created.releaseLabel)
  assert.equal(calendar.entries[0].videoApproved, true)
  assert.equal(calendar.entries[0].finalReleaseApproved, true)
  assert.deepEqual(calendar.entries[0].platforms, publishedPlatforms)
})
