import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { DatabaseSync } from 'node:sqlite'
import test from 'node:test'
import worker from '../cloud/operator-api/src/index.ts'
import {
  generateScriptDraft,
  validateScriptProfile,
} from '../cloud/operator-api/src/scriptDrafts.ts'

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
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_script_drafts_v2/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_script_origins_v2/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_script_style_examples_v2/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_script_structures/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_run_script_manifests/)
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

test('worker serves current hourly dashboard data and keeps a static fallback', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.match(source, /DASHBOARD_DATA_BASE_URL/)
  assert.match(source, /DASHBOARD_DATA_FILES/)
  assert.match(source, /cacheTtl:\s*300/)
  assert.match(source, /hourly-github-pages/)

  const originalFetch = globalThis.fetch
  const upstreamRequests = []
  globalThis.fetch = async input => {
    upstreamRequests.push(String(input))
    return new Response('{"schemaVersion":3,"generatedAt":"2026-07-23T08:00:00Z"}\n', {
      status: 200,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
    })
  }
  try {
    const live = await worker.fetch(request('/data/dashboard.json?refresh=123', 'operator-token'), {
      OPERATOR_API_TOKEN: 'operator-token',
      DASHBOARD_DATA_BASE_URL: 'https://dashboard-data.example.test/current/',
    })
    assert.equal(live.status, 200)
    assert.equal(live.headers.get('x-flaggenbande-data-source'), 'hourly-github-pages')
    assert.deepEqual(await live.json(), { schemaVersion: 3, generatedAt: '2026-07-23T08:00:00Z' })
    assert.deepEqual(upstreamRequests, ['https://dashboard-data.example.test/current/dashboard.json'])
  } finally {
    globalThis.fetch = originalFetch
  }

  const staticAsset = new Response('{"generatedAt":"static"}\n', {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
  const fallback = await worker.fetch(request('/data/dashboard.json', 'operator-token'), {
    OPERATOR_API_TOKEN: 'operator-token',
    ASSETS: { fetch: async () => staticAsset.clone() },
  })
  assert.equal(fallback.status, 200)
  assert.deepEqual(await fallback.json(), { generatedAt: 'static' })
})

test('worker never lets the dashboard HTML remain stale after a deployment', async () => {
  const response = await worker.fetch(request('/', 'operator-token'), {
    OPERATOR_API_TOKEN: 'operator-token',
    ASSETS: {
      fetch: async () => new Response('<!doctype html><title>Dashboard</title>', {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'public, max-age=14400',
        },
      }),
    },
  })
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('cache-control'), 'no-store, max-age=0, must-revalidate')
  assert.equal(response.headers.get('pragma'), 'no-cache')
})

test('worker rejects invalid or incomplete live dashboard data and uses the static fallback', async () => {
  const staticAsset = new Response('{"generatedAt":"safe-static"}\n', {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
  const responses = [
    new Response('{"schemaVersion":3', { status: 200, headers: { 'Content-Type': 'application/json' } }),
    new Response('{"schemaVersion":99,"generatedAt":"2026-07-23T08:00:00Z"}', { status: 200, headers: { 'Content-Type': 'application/json' } }),
    new Response('temporary outage', { status: 503, headers: { 'Content-Type': 'application/json' } }),
    new Response('not json', { status: 200, headers: { 'Content-Type': 'text/plain' } }),
    new Response(new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"schemaVersion":3,'))
        controller.error(new Error('upstream aborted'))
      },
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  ]
  const originalFetch = globalThis.fetch
  try {
    for (const upstream of responses) {
      globalThis.fetch = async () => upstream
      const response = await worker.fetch(request('/data/dashboard.json', 'operator-token'), {
        OPERATOR_API_TOKEN: 'operator-token',
        DASHBOARD_DATA_BASE_URL: 'https://dashboard-data.example.test/current/',
        ASSETS: { fetch: async () => staticAsset.clone() },
      })
      assert.equal(response.status, 200)
      assert.deepEqual(await response.json(), { generatedAt: 'safe-static' })
      assert.equal(response.headers.get('x-flaggenbande-data-source'), null)
    }
  } finally {
    globalThis.fetch = originalFetch
  }
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

test('script drafts are editable, do not start production and only approved human input becomes style evidence', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const env = {
    DB,
    PREVIEWS: new PreviewBucket(),
    OPERATOR_API_TOKEN: 'operator-token',
  }
  const draftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 5,
    targetDurationSeconds: 64,
    recommendationId: 'difficulty-ladder-visibility-v1',
    clientRequestId: 'draft-contract-test-0001',
  })), env)
  assert.equal(draftResponse.status, 201)
  const draft = await draftResponse.json()
  assert.equal(draft.roundCount, 5)
  assert.equal(draft.suggestedDurationSeconds, 64)
  assert.equal(draft.styleExampleCount, 1)
  assert.equal(draft.script.match(/^\(auflösung\)$/gmu)?.length, 5)
  assert.doesNotMatch(draft.script, /\bflaggenbande\b/iu)
  assert.equal(
    DB.database.prepare(
      "SELECT COUNT(*) AS count FROM operator_script_style_examples_v2 WHERE instr(lower(script), 'flaggenbande') > 0",
    ).get().count,
    0,
  )
  assert.equal(DB.database.prepare('SELECT COUNT(*) AS count FROM operator_production_runs').get().count, 0)

  const generatedRunResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: draft.script,
    targetDurationSeconds: 64,
    roundCount: 5,
    draftId: draft.draftId,
    clientRequestId: 'draft-run-contract-0001',
  })), env)
  assert.equal(generatedRunResponse.status, 202)
  const generatedRun = await generatedRunResponse.json()
  assert.equal(
    DB.database.prepare('SELECT origin FROM operator_script_origins_v2 WHERE run_id = ?').get(generatedRun.runId).origin,
    'auto_unedited',
  )
  const generatedApproval = await worker.fetch(request(
    `/v1/runs/${generatedRun.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: generatedRun.script.sha256,
      scriptRevision: 1,
      idempotencyKey: 'draft-script-approval-0001',
    }),
  ), env)
  assert.equal(generatedApproval.status, 200)
  assert.equal(DB.database.prepare('SELECT COUNT(*) AS count FROM operator_script_style_examples_v2').get().count, 1)

  const sevenDraftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 7,
    targetDurationSeconds: 69,
    recommendationId: null,
    clientRequestId: 'draft-contract-test-0007',
  })), env)
  const sevenDraft = await sevenDraftResponse.json()
  assert.equal(sevenDraftResponse.status, 201)
  assert.equal(sevenDraft.script.match(/^\(auflösung\)$/gmu)?.length, 7)
  const uneditedSevenRunResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: sevenDraft.script,
    targetDurationSeconds: 69,
    roundCount: 7,
    draftId: sevenDraft.draftId,
    clientRequestId: 'draft-run-contract-0007',
  })), env)
  assert.equal(uneditedSevenRunResponse.status, 202)
  const uneditedSevenRun = await uneditedSevenRunResponse.json()
  assert.equal(
    DB.database.prepare('SELECT origin FROM operator_script_origins_v2 WHERE run_id = ?').get(uneditedSevenRun.runId).origin,
    'auto_unedited',
  )

  const imperativeSegments = sevenDraft.script.split('\n(auflösung)\n')
  imperativeSegments[1] = 'Sauber Meister, die nächste wissen wenige, sprich frei.'
  const imperativeScript = imperativeSegments.join('\n(auflösung)\n')
  const imperativeRunResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: imperativeScript,
    targetDurationSeconds: 69,
    roundCount: 7,
    draftId: 'draft-aaaaaaaaaaaaaaaaaaaaaaaa',
    clientRequestId: 'stale-draft-run-contract-0007',
  })), env)
  assert.equal(imperativeRunResponse.status, 202)
  const imperativeRun = await imperativeRunResponse.json()
  assert.equal(
    DB.database.prepare('SELECT origin FROM operator_script_origins_v2 WHERE run_id = ?').get(imperativeRun.runId).origin,
    'manual',
  )

  const invalidPromptSegments = [...imperativeSegments]
  invalidPromptSegments[1] = 'Sauber Meister, die nächste Runde wird schwierig und startet jetzt.'
  const invalidPromptResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: invalidPromptSegments.join('\n(auflösung)\n'),
    targetDurationSeconds: 69,
    roundCount: 7,
    clientRequestId: 'invalid-prompt-contract-0007',
  })), env)
  assert.equal(invalidPromptResponse.status, 400)
  const invalidPrompt = await invalidPromptResponse.json()
  assert.equal(invalidPrompt.error, 'INVALID_VIDEO_RUN_INPUT')
  assert.ok(invalidPrompt.issues.some(issue =>
    issue.code === 'QUESTION_PROMPT_MISSING' && issue.roundIndex === 2))
  assert.equal(typeof invalidPrompt.metrics.spokenWordCount, 'number')
  assert.equal('script' in invalidPrompt, false)

  const manualSevenScript = sevenDraft.script.replace(
    '(auflösung)\n',
    '(auflösung)\nGurkenminister-Modus, genau mein Tempo. ',
  )
  const manualRunResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: manualSevenScript,
    targetDurationSeconds: 69,
    roundCount: 7,
    clientRequestId: 'manual-run-contract-0007',
  })), env)
  assert.equal(manualRunResponse.status, 202)
  const manualRun = await manualRunResponse.json()
  const manualApproval = await worker.fetch(request(
    `/v1/runs/${manualRun.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: manualRun.script.sha256,
      scriptRevision: 1,
      idempotencyKey: 'manual-script-approval-0007',
    }),
  ), env)
  assert.equal(manualApproval.status, 200)
  const learned = DB.database.prepare(
    "SELECT source, trust_level FROM operator_script_style_examples_v2 WHERE reveal_count = 7",
  ).get()
  assert.equal(learned.source, 'manual')
  assert.equal(learned.trust_level, 'candidate')

  const learnedDraftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 7,
    targetDurationSeconds: 69,
    recommendationId: null,
    clientRequestId: 'draft-after-learning-0007',
  })), env)
  const learnedDraft = await learnedDraftResponse.json()
  assert.equal(learnedDraft.styleExampleCount, 1)
  assert.match(learnedDraft.script, /Gurkenminister-Modus/u)
  assert.notEqual(learnedDraft.script, manualSevenScript)

  const secondLearnedDraftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 7,
    targetDurationSeconds: 69,
    recommendationId: null,
    clientRequestId: 'draft-after-learning-0008',
  })), env)
  const secondLearnedDraft = await secondLearnedDraftResponse.json()
  assert.equal(secondLearnedDraftResponse.status, 201)
  assert.notEqual(secondLearnedDraft.scriptSha256, learnedDraft.scriptSha256)
  assert.match(secondLearnedDraft.script, /Gurkenminister-Modus/u)

  const sixDraftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 6,
    targetDurationSeconds: 66,
    recommendationId: null,
    clientRequestId: 'six-draft-contract-0001',
  })), env)
  assert.equal(sixDraftResponse.status, 201)
  const sixDraft = await sixDraftResponse.json()
  assert.equal(sixDraft.roundCount, 6)
  assert.equal(sixDraft.phrases.rounds.length, 6)
  assert.equal(
    DB.database.prepare(
      'SELECT COUNT(*) AS count FROM operator_script_phrases WHERE script_sha256 = ?',
    ).get(sixDraft.scriptSha256).count,
    sixDraft.phrases.phrases.length,
  )

  for (const unsupportedRoundCount of [6, 8, 9, 10]) {
    const generated = unsupportedRoundCount === 6
      ? { script: sixDraft.script, targetDurationSeconds: 66 }
      : {
          script: generateScriptDraft({
            roundCount: unsupportedRoundCount,
            targetDurationSeconds: unsupportedRoundCount < 9 ? 69 : 70,
            recommendationId: null,
            requestSeed: `unsupported-production-${unsupportedRoundCount}`,
          }, []).script,
          targetDurationSeconds: unsupportedRoundCount < 9 ? 69 : 70,
        }
    const runCountBeforeUnsupported = DB.database.prepare(
      'SELECT COUNT(*) AS count FROM operator_production_runs',
    ).get().count
    const unsupportedRunResponse = await worker.fetch(request(
      '/v1/runs',
      'operator-token',
      jsonBody({
        script: generated.script,
        targetDurationSeconds: generated.targetDurationSeconds,
        roundCount: unsupportedRoundCount,
        clientRequestId: `unsupported-run-${unsupportedRoundCount}-0001`,
      }),
    ), env)
    assert.equal(unsupportedRunResponse.status, 400)
    assert.deepEqual(await unsupportedRunResponse.json(), {
      error: 'UNSUPPORTED_PRODUCTION_ROUND_COUNT',
    })
    assert.equal(
      DB.database.prepare('SELECT COUNT(*) AS count FROM operator_production_runs').get().count,
      runCountBeforeUnsupported,
    )
  }
})

test('one learned style example still produces hundreds of valid distinct drafts', () => {
  const approvedStyle = [
    'was läuft was läuft, schnelles flaggenquiz, fünf flaggen, eine wird richtig kernig. fängt easy an: welches land ist das?',
    '(auflösung)',
    'okok, sauber. die nächste wird schon tougher, also nicht zu früh feiern. wie schaut es hier aus?',
    '(auflösung)',
    'crazy, der bre hat ahnung. jetzt wird es knifflig: welches land gehört zu dieser flagge?',
    '(auflösung)',
    'drei von drei wäre stark. ab hier trennt sich glück von echter ahnung. bereit fürs halbfinale, welches land ist das?',
    '(auflösung)',
    'junge, vielleicht ist hier wirklich der flaggenboss am start. letzte runde, mann oder maus: welche flagge siehst du?',
    '(auflösung)',
    'anscheinend der allerechte flaggenchef. schreib ehrlich, wie viele du sauber erkannt hast.',
  ].join('\n')
  const scripts = new Set()
  for (let index = 0; index < 250; index += 1) {
    const generated = generateScriptDraft({
      roundCount: 5,
      targetDurationSeconds: 64,
      recommendationId: null,
      requestSeed: `scale-contract-${String(index).padStart(4, '0')}`,
    }, [approvedStyle])
    assert.equal(validateScriptProfile(generated.script, 5, 64).valid, true)
    assert.doesNotMatch(generated.script, /\bflaggenbande\b/iu)
    scripts.add(generated.script)
  }
  assert.ok(scripts.size >= 240, `only ${scripts.size} distinct drafts generated`)
  const forbiddenBrand = validateScriptProfile(`${approvedStyle}\nFlaggenbande`, 5, 64)
  assert.equal(forbiddenBrand.valid, false)
  assert.ok(forbiddenBrand.issues.includes('BRAND_MENTION_FORBIDDEN'))
})

test('research recommendations expose coverage and only use linked retention when sample size is sufficient', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const videos = Array.from({ length: 5 }, (_, index) => ({
    platform: 'youtube',
    platformVideoId: `youtube-${index}`,
    contentId: null,
    durationSeconds: 64,
    metrics: { averageViewPercentage: 51 },
    retention: [
      { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
      { elapsedVideoTimeRatio: 0.05, audienceWatchRatio: 0.62 },
    ],
  }))
  videos.push({
    platform: 'youtube',
    platformVideoId: 'short-prototype',
    contentId: `flaggenbande-${'f'.repeat(64)}`,
    durationSeconds: 30,
    metrics: { averageViewPercentage: 91 },
    retention: [
      { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
      { elapsedVideoTimeRatio: 0.1, audienceWatchRatio: 0.2 },
    ],
  })
  const publications = Array.from({ length: 5 }, (_, index) => ({
    platform: 'youtube',
    platformVideoId: `youtube-${index}`,
    contentId: `flaggenbande-${index.toString(16).padStart(64, '0')}`,
    status: 'published',
  }))
  const originalFetch = globalThis.fetch
  globalThis.fetch = async input => {
    const requestUrl = input instanceof URL
      ? input
      : new URL(typeof input === 'string' ? input : input.url)
    const path = requestUrl.pathname
    const payload = path.endsWith('/content-operations.json')
      ? {
          schemaVersion: 1,
          generatedAt: '2026-07-23T09:00:00Z',
          publications,
        }
      : {
          schemaVersion: 3,
          generatedAt: '2026-07-23T09:00:00Z',
          social: { videos },
        }
    return new Response(JSON.stringify(payload), {
      headers: { 'Content-Type': 'application/json' },
    })
  }
  try {
    const response = await worker.fetch(request('/v1/research/recommendations', 'operator-token'), {
      DB,
      PREVIEWS: new PreviewBucket(),
      OPERATOR_API_TOKEN: 'operator-token',
      DASHBOARD_DATA_BASE_URL: 'https://dashboard.example.test/data/',
    })
    assert.equal(response.status, 200)
    const feed = await response.json()
    assert.equal(feed.dataReadiness.status, 'ready')
    assert.equal(feed.dataReadiness.retentionVideos, 5)
    assert.equal(feed.recommendations[0].id, 'first-reveal-delay-v1')
    assert.equal(feed.recommendations[0].evidenceLevel, 'measured')
    assert.equal(feed.recommendations[0].autoApplicable, false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('research joins stored run phrases to publication content IDs without using calendar IDs', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const runId = `video-${'1'.repeat(24)}`
  const scriptSha256 = '2'.repeat(64)
  const contentId = `flaggenbande-${'3'.repeat(64)}`
  const timestamp = '2026-07-23T09:00:00Z'
  DB.database.prepare(`INSERT INTO operator_production_runs
    (run_id, input_sha256, client_request_id, script, target_duration_seconds,
     status, progress, next_attempt_at, provider_run_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, 64, 'completed', 100, ?, ?, ?, ?)`).run(
    runId,
    '4'.repeat(64),
    'phrase-research-run',
    'Welche Flagge ist das?\\n(auflösung)\\nSauber.',
    timestamp,
    runId,
    timestamp,
    timestamp,
  )
  DB.database.prepare(`INSERT INTO operator_script_structures
    (script_sha256, source_draft_id, schema_version, round_count, structure_json,
     created_at, updated_at)
    VALUES (?, NULL, '1.0.0', 5, '{}', ?, ?)`).run(scriptSha256, timestamp, timestamp)
  DB.database.prepare(`INSERT INTO operator_script_phrases
    (script_sha256, phrase_id, formulation_key, phrase_type, position_index,
     round_number, text, created_at, updated_at)
    VALUES (?, 'phrase-r01-question-01-test', 'formulation-test', 'question', 0,
      1, 'Welche Flagge ist das?', ?, ?)`).run(scriptSha256, timestamp, timestamp)
  DB.database.prepare(`INSERT INTO operator_run_script_manifests
    (run_id, script_sha256, schema_version, round_count, timing_source,
     created_at, updated_at)
    VALUES (?, ?, '1.0.0', 5, 'word_timestamps', ?, ?)`).run(
    runId,
    scriptSha256,
    timestamp,
    timestamp,
  )
  DB.database.prepare(`INSERT INTO operator_run_script_phrases
    (run_id, script_sha256, phrase_id, start_seconds, end_seconds,
     created_at, updated_at)
    VALUES (?, ?, 'phrase-r01-question-01-test', 1, 4, ?, ?)`).run(
    runId,
    scriptSha256,
    timestamp,
    timestamp,
  )

  const originalFetch = globalThis.fetch
  globalThis.fetch = async input => {
    const path = new URL(input instanceof URL ? input : typeof input === 'string' ? input : input.url).pathname
    const payload = path.endsWith('/content-operations.json')
      ? {
          schemaVersion: 1,
          generatedAt: timestamp,
          publications: [{
            platform: 'youtube',
            platformVideoId: 'youtube-phrase',
            contentId,
            runId: `upload-${runId}-2207-07`,
            status: 'published',
          }],
        }
      : {
          schemaVersion: 3,
          generatedAt: timestamp,
          social: {
            videos: [{
              platform: 'youtube',
              platformVideoId: 'youtube-phrase',
              durationSeconds: 64,
              retention: [
                { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
                { elapsedVideoTimeRatio: 0.02, audienceWatchRatio: 0.9 },
                { elapsedVideoTimeRatio: 0.08, audienceWatchRatio: 0.7 },
              ],
              metrics: {},
            }],
          },
        }
    return new Response(JSON.stringify(payload), {
      headers: { 'Content-Type': 'application/json' },
    })
  }
  try {
    const response = await worker.fetch(request('/v1/research/recommendations', 'operator-token'), {
      DB,
      PREVIEWS: new PreviewBucket(),
      OPERATOR_API_TOKEN: 'operator-token',
      DASHBOARD_DATA_BASE_URL: 'https://dashboard.example.test/data/',
    })
    assert.equal(response.status, 200)
    const feed = await response.json()
    assert.equal(feed.schemaVersion, '1.1.0')
    assert.equal(feed.dataReadiness.phraseTimelineVideos, 1)
    assert.equal(feed.dataReadiness.phraseRetentionVideos, 1)
    assert.equal(feed.phraseEvaluations.length, 1)
    assert.equal(feed.phraseEvaluations[0].formulationKey, 'formulation-test')
  } finally {
    globalThis.fetch = originalFetch
  }
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
    'was läuft was läuft, schnelles flaggenquiz, fünf flaggen, eine wird richtig kernig. fängt easy an: welches land ist das?',
    '(auflösung)',
    'okok, sauber. die nächste wird schon tougher, also nicht zu früh feiern. wie schaut es hier aus?',
    '(auflösung)',
    'crazy, der bre hat ahnung. jetzt wird es knifflig: welches land gehört zu dieser flagge?',
    '(auflösung)',
    'drei von drei wäre stark. ab hier trennt sich glück von echter ahnung. bereit fürs halbfinale, welches land ist das?',
    '(auflösung)',
    'junge, vielleicht ist hier wirklich der flaggenboss am start. letzte runde, mann oder maus: welche flagge siehst du?',
    '(auflösung)',
    'anscheinend der allerechte flaggenchef. schreib ehrlich, wie viele du sauber erkannt hast.',
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
  assert.equal(claim.command.roundCount, 5)
  assert.equal(claim.command.phraseTimeline.rounds.length, 5)

  const spokenWords = script
    .replaceAll('(auflösung)', '')
    .match(/[\p{L}\p{N}]+/gu)
  const wordCues = spokenWords.map((word, index) => ({
    word,
    startSeconds: Number((index * 0.25).toFixed(3)),
    endSeconds: Number((index * 0.25 + 0.2).toFixed(3)),
  }))
  const analysisResponse = await worker.fetch(request(
    `/v1/runner/runs/${created.runId}/analysis-manifest`,
    'runner-token',
    jsonBody({
      runnerId: 'test-runner',
      leaseToken: claim.leaseToken,
      rounds: Array.from({ length: 5 }, (_, index) => ({
        round: index + 1,
        solutionCountry: `Country ${String(index + 1)}`,
        solutionCountryCode: ['DE', 'UY', 'MZ', 'JP', 'CA'][index],
        flagShownAtSeconds: index * 10 + 1,
        revealAtSeconds: index * 10 + 5,
      })),
      wordCues,
    }),
  ), env)
  assert.equal(analysisResponse.status, 200)
  const storedAnalysis = await analysisResponse.json()
  assert.ok(storedAnalysis.alignedPhraseCount > 0)
  assert.equal(storedAnalysis.unmatchedPhraseCount, 0)
  assert.equal(storedAnalysis.roundsStored, 5)
  assert.equal(
    DB.database.prepare(
      'SELECT COUNT(*) AS count FROM operator_run_script_rounds WHERE run_id = ? AND solution_country IS NOT NULL',
    ).get(created.runId).count,
    5,
  )
  assert.equal(
    DB.database.prepare(
      'SELECT COUNT(*) AS count FROM operator_run_script_phrases WHERE run_id = ? AND start_seconds IS NOT NULL',
    ).get(created.runId).count,
    claim.command.phraseTimeline.phrases.length,
  )

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

test('operator can retry a failed flag-selection run without creating a duplicate', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const env = {
    DB,
    PREVIEWS: new PreviewBucket(),
    OPERATOR_API_TOKEN: 'operator-token',
  }
  const draftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 5,
    targetDurationSeconds: 64,
    recommendationId: null,
    clientRequestId: 'retry-draft-0001',
  })), env)
  assert.equal(draftResponse.status, 201)
  const draft = await draftResponse.json()
  const createdResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: draft.script,
    targetDurationSeconds: 64,
    roundCount: 5,
    draftId: draft.draftId,
    clientRequestId: 'retry-run-0001',
  })), env)
  assert.equal(createdResponse.status, 202)
  const created = await createdResponse.json()
  const approvedResponse = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: created.script.sha256,
      scriptRevision: created.script.revision,
      idempotencyKey: 'retry-script-approval-0001',
    }),
  ), env)
  assert.equal(approvedResponse.status, 200)
  DB.database.prepare(`UPDATE operator_production_runs SET
    status = 'failed', progress = 23, current_step = 'flag_selection',
    error_code = 'PRODUCTION_STEP_FAILED'
    WHERE run_id = ?`).run(created.runId)

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const retryResponse = await worker.fetch(request(
      `/v1/runs/${created.runId}/retry`,
      'operator-token',
      { method: 'POST' },
    ), env)
    assert.equal(retryResponse.status, 200)
    const retried = await retryResponse.json()
    assert.equal(retried.runId, created.runId)
    assert.equal(retried.productionStatus, 'queued')
    assert.equal(retried.currentStep, 'production_queue')
    assert.equal(retried.error, null)
  }
  assert.equal(
    DB.database.prepare('SELECT COUNT(*) AS count FROM operator_production_runs').get().count,
    1,
  )
})

const approvedRetryRun = async (env, suffix) => {
  const draftResponse = await worker.fetch(request('/v1/script-drafts', 'operator-token', jsonBody({
    roundCount: 5,
    targetDurationSeconds: 64,
    recommendationId: null,
    clientRequestId: `retry-draft-${suffix}`,
  })), env)
  assert.equal(draftResponse.status, 201)
  const draft = await draftResponse.json()
  const createdResponse = await worker.fetch(request('/v1/runs', 'operator-token', jsonBody({
    script: draft.script,
    targetDurationSeconds: 64,
    roundCount: 5,
    draftId: draft.draftId,
    clientRequestId: `retry-run-${suffix}`,
  })), env)
  assert.equal(createdResponse.status, 202)
  const created = await createdResponse.json()
  const approvedResponse = await worker.fetch(request(
    `/v1/runs/${created.runId}/approve-script`,
    'operator-token',
    jsonBody({
      scriptSha256: created.script.sha256,
      scriptRevision: created.script.revision,
      idempotencyKey: `retry-approval-${suffix}`,
    }),
  ), env)
  assert.equal(approvedResponse.status, 200)
  return created
}

test('operator can retry a failed pre-preview timeline build without creating a duplicate', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const env = {
    DB,
    PREVIEWS: new PreviewBucket(),
    OPERATOR_API_TOKEN: 'operator-token',
  }
  const created = await approvedRetryRun(env, 'timeline-0001')
  DB.database.prepare(`UPDATE operator_production_runs SET
    status = 'failed', progress = 45, current_step = 'timeline_build',
    error_code = 'PRODUCTION_STEP_FAILED'
    WHERE run_id = ?`).run(created.runId)

  for (let attempt = 0; attempt < 2; attempt += 1) {
    if (attempt > 0) {
      DB.database.prepare(`UPDATE operator_production_runs SET
        status = 'failed', progress = 45, current_step = 'timeline_build',
        error_code = 'PRODUCTION_STEP_FAILED'
        WHERE run_id = ?`).run(created.runId)
    }
    const response = await worker.fetch(request(
      `/v1/runs/${created.runId}/retry`,
      'operator-token',
      { method: 'POST' },
    ), env)
    assert.equal(response.status, 200)
    const retried = await response.json()
    assert.equal(retried.runId, created.runId)
    assert.equal(retried.productionStatus, 'queued')
    assert.equal(retried.currentStep, 'production_queue')
    assert.equal(retried.error, null)
  }
  assert.equal(
    DB.database.prepare('SELECT COUNT(*) AS count FROM operator_production_runs').get().count,
    1,
  )
})

test('operator can queue a failed render for the local fail-closed recovery without creating a duplicate', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const env = {
    DB,
    PREVIEWS: new PreviewBucket(),
    OPERATOR_API_TOKEN: 'operator-token',
  }
  const created = await approvedRetryRun(env, 'render-0001')
  DB.database.prepare(`UPDATE operator_production_runs SET
    status = 'failed', progress = 68, current_step = 'render',
    error_code = 'PRODUCTION_STEP_FAILED'
    WHERE run_id = ?`).run(created.runId)

  const response = await worker.fetch(request(
    `/v1/runs/${created.runId}/retry`,
    'operator-token',
    { method: 'POST' },
  ), env)
  assert.equal(response.status, 200)
  const retried = await response.json()
  assert.equal(retried.runId, created.runId)
  assert.equal(retried.productionStatus, 'queued')
  assert.equal(retried.currentStep, 'production_queue')
  assert.equal(retried.error, null)
  assert.equal(
    DB.database.prepare('SELECT COUNT(*) AS count FROM operator_production_runs').get().count,
    1,
  )
})

test('operator rejects retry after a preview exists', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  const DB = new D1TestDatabase(schema)
  const env = {
    DB,
    PREVIEWS: new PreviewBucket(),
    OPERATOR_API_TOKEN: 'operator-token',
  }
  const created = await approvedRetryRun(env, 'preview-0001')
  DB.database.prepare(`UPDATE operator_production_runs SET
    status = 'failed', progress = 45, current_step = 'timeline_build',
    error_code = 'PRODUCTION_STEP_FAILED'
    WHERE run_id = ?`).run(created.runId)
  DB.database.prepare(`UPDATE operator_production_reviews SET
    preview_object_key = 'previews/existing.mp4'
    WHERE run_id = ?`).run(created.runId)

  const response = await worker.fetch(request(
    `/v1/runs/${created.runId}/retry`,
    'operator-token',
    { method: 'POST' },
  ), env)
  assert.equal(response.status, 409)
  assert.equal((await response.json()).error, 'RUN_RETRY_NOT_ALLOWED')
  assert.equal(
    DB.database.prepare('SELECT status FROM operator_production_runs WHERE run_id = ?').get(created.runId).status,
    'failed',
  )
})

test('operator rejects retry for non-allowlisted and post-preview steps', async () => {
  for (const [index, currentStep] of ['voice_preparation', 'preview_ready', 'quality_check'].entries()) {
    const schema = await readFile(schemaUrl, 'utf8')
    const DB = new D1TestDatabase(schema)
    const env = {
      DB,
      PREVIEWS: new PreviewBucket(),
      OPERATOR_API_TOKEN: 'operator-token',
    }
    const created = await approvedRetryRun(env, `unsafe-${index + 1}`)
    DB.database.prepare(`UPDATE operator_production_runs SET
      status = 'failed', progress = 77, current_step = ?,
      error_code = 'PRODUCTION_STEP_FAILED'
      WHERE run_id = ?`).run(currentStep, created.runId)

    const response = await worker.fetch(request(
      `/v1/runs/${created.runId}/retry`,
      'operator-token',
      { method: 'POST' },
    ), env)
    assert.equal(response.status, 409, currentStep)
    assert.equal((await response.json()).error, 'RUN_RETRY_NOT_ALLOWED')
    assert.equal(
      DB.database.prepare('SELECT status FROM operator_production_runs WHERE run_id = ?').get(created.runId).status,
      'failed',
    )
  }
})
