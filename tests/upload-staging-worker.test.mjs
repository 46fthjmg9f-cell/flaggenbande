import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const workerUrl = new URL('../cloud/meta-scheduler/src/index.ts', import.meta.url)
const schemaUrl = new URL('../cloud/meta-scheduler/schema.sql', import.meta.url)

test('staging lane has dedicated routes, claims and no publishing call', async () => {
  const source = await readFile(workerUrl, 'utf8')
  for (const route of ['/staging/runs', '/staging/claims', '/staging/receipts', '/staging/poll', '/staging/feed']) {
    assert.match(source, new RegExp(route.replaceAll('/', '\\/')))
  }
  const start = source.indexOf('const stageInstagramContainer')
  const end = source.indexOf('const processJob', start)
  assert.ok(start >= 0 && end > start)
  const stagingLane = source.slice(start, end)
  assert.doesNotMatch(stagingLane, /media_publish/)
  assert.doesNotMatch(stagingLane, /video_state:\s*"PUBLISHED"/)
  assert.doesNotMatch(stagingLane, /meta_publication_jobs/)
  assert.match(stagingLane, /video_state:\s*"DRAFT"/)
  assert.match(stagingLane, /fields:\s*"published,status"/)
})

test('staging schema is separate and cannot authorize publication', async () => {
  const schema = await readFile(schemaUrl, 'utf8')
  assert.match(schema, /CREATE TABLE IF NOT EXISTS upload_staging_runs/)
  assert.match(schema, /publication_authorized INTEGER NOT NULL DEFAULT 0 CHECK \(publication_authorized = 0\)/)
  assert.match(schema, /idempotency_key TEXT NOT NULL UNIQUE/)
  assert.match(schema, /initial_visibility_state TEXT NOT NULL CHECK \(initial_visibility_state IN \('not_created', 'unknown'\)\)/)

  const source = await readFile(workerUrl, 'utf8')
  const start = source.indexOf('const ensureStagingSchema =')
  const end = source.indexOf('const stagingEvent =', start)
  const runtimeSchema = source.slice(start, end)
  assert.match(runtimeSchema, /publication_authorized INTEGER NOT NULL DEFAULT 0 CHECK \(publication_authorized = 0\)/)
  assert.match(runtimeSchema, /FOREIGN KEY\(run_id\) REFERENCES upload_staging_runs\(run_id\)/)
})

test('public staging feed omits remote IDs and private metadata', async () => {
  const source = await readFile(workerUrl, 'utf8')
  const start = source.indexOf('const stagingFeed =')
  const end = source.indexOf('const analyticsMetricNames', start)
  assert.ok(start >= 0 && end > start)
  const feed = source.slice(start, end)
  assert.doesNotMatch(feed, /remoteObjectId|remote_object_id|metadata_json|last_error|accountFingerprint/)
  assert.match(feed, /publicationAuthorized:\s*false/)
  assert.match(feed, /publishedAt:\s*null/)
  assert.match(feed, /publicUrl:\s*null/)
})

test('protected staging receipts expose an authoritative confirmation timestamp', async () => {
  const source = await readFile(workerUrl, 'utf8')
  const start = source.indexOf('const stagingTargetResponse =')
  const end = source.indexOf('const stagingRunResponse =', start)
  assert.ok(start >= 0 && end > start)
  const response = source.slice(start, end)
  assert.match(response, /confirmedAt:/)
  assert.match(response, /target\.updated_at/)
})

test('temporary Pages media cleanup removes active preview aliases explicitly', async () => {
  const source = await readFile(workerUrl, 'utf8')
  assert.equal((source.match(/deployments\/\$\{deployment\.id\}\?force=true/g) ?? []).length, 2)
  const cleanupStart = source.indexOf('interface PagesDeployment')
  const cleanupEnd = source.indexOf('const stageInstagramContainer', cleanupStart)
  const cleanup = source.slice(cleanupStart, cleanupEnd)
  assert.match(cleanup, /searchParams\.set\("page"/)
  assert.match(cleanup, /searchParams\.set\("per_page", "100"\)/)
  assert.match(cleanup, /pagesOrigin\(deployment\.url\) === expectedOrigin/)
  assert.match(cleanup, /\["container_unpublished", "expired"\]/)
  assert.match(cleanup, /facebook\.workflow_state === "draft"/)
  assert.doesNotMatch(cleanup, /\["draft", "failed", "reconcile_required"/)
  const start = source.indexOf('const pollStagingRun =')
  const end = source.indexOf('interface StagingFeedTargetRow', start)
  const poll = source.slice(start, end)
  assert.match(poll, /inspectInstagramStaging\(env, runId, false\)/)
  assert.match(poll, /cleanupStagingMediaIfSafe\(env, runId\)/)
})
