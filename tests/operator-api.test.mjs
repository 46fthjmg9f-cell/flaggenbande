import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

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

test('operator API exposes only the agreed redacted dashboard contract', async () => {
  const source = await readFile(workerUrl, 'utf8')
  for (const route of ['/v1/runs', '/v1/calendar', '/v1/runner/claim']) {
    assert.match(source, new RegExp(route.replaceAll('/', '\\/')))
  }
  const start = source.indexOf('const publicRun =')
  const end = source.indexOf('const runById =', start)
  const publicProjection = source.slice(start, end)
  for (const key of ['runId', 'status', 'progress', 'targetDurationSeconds', 'currentStep', 'message', 'error', 'createdAt', 'updatedAt']) {
    assert.match(publicProjection, new RegExp(`${key}:`))
  }
  assert.doesNotMatch(publicProjection, /script|lease|clientRequestId|providerRunId|inputSha/)
})

test('queue schema is idempotent, leased and append-only observable', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  assert.match(schema, /input_sha256 TEXT NOT NULL UNIQUE/)
  assert.match(schema, /client_request_id TEXT NOT NULL UNIQUE/)
  assert.match(schema, /lease_token_sha256 TEXT/)
  assert.match(schema, /CHECK \(status IN \('queued', 'claimed', 'running', 'waiting', 'completed', 'failed'\)\)/)
  assert.match(schema, /CREATE TABLE IF NOT EXISTS operator_production_events/)
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
  assert.doesNotMatch(projection, /token|secret|lease|description/iu)
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
