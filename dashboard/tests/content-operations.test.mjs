import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const fixtureUrl = new URL('../public/data/content-operations.json', import.meta.url)
const forbiddenKey = /(secret|token|password|api.?key|private.?key|authorization|local.?path|onedrive.?path|remote.?object.?id|container.?id|platform.?video.?id|account.?fingerprint|media.?(url|project|branch)|provider.?status|last.?error)/i
const forbiddenValue = /(^|\s)(\/Users\/|file:\/\/|~\/|[A-Za-z]:\\)/

async function loadFixture() {
  return JSON.parse(await readFile(fixtureUrl, 'utf8'))
}

function inspectPublicValue(value, path = 'root') {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => inspectPublicValue(entry, `${path}[${index}]`))
    return
  }
  if (value && typeof value === 'object') {
    for (const [key, entry] of Object.entries(value)) {
      assert.equal(forbiddenKey.test(key), false, `verbotener öffentlicher Schlüssel: ${path}.${key}`)
      inspectPublicValue(entry, `${path}.${key}`)
    }
    return
  }
  if (typeof value === 'string') assert.equal(forbiddenValue.test(value), false, `lokaler Pfad in ${path}`)
}

test('public content contract reports the current run state with all four platforms without claiming publication', async () => {
  const fixture = await loadFixture()
  assert.equal(fixture.schemaVersion, 1)
  const expectedStatus = fixture.runs.some(run => ['failed', 'qa_failed', 'reconcile_required'].includes(run.status))
    ? 'error'
    : fixture.runs.length > 0 && fixture.runs.every(run => run.status === 'completed')
      ? 'ok'
      : 'partial'
  assert.equal(fixture.status, expectedStatus)
  assert.deepEqual(fixture.system.map(entry => entry.id).sort(), ['database', 'engine', 'quality', 'release'])
  assert.deepEqual(fixture.platforms.map(entry => entry.platform).sort(), ['facebook', 'instagram', 'tiktok', 'youtube'])
  assert.ok(fixture.platforms.every(entry => ['not_configured', 'planned', 'ready', 'uploading', 'failed'].includes(entry.status)))
  assert.ok(fixture.platforms.every(entry => entry.publications === 0))
  assert.ok(fixture.publications.every(entry => !['scheduled', 'published'].includes(entry.status)))
  assert.deepEqual(fixture.performance, [])
})

test('public content contract reports the country-data candidate without claiming production readiness', async () => {
  const fixture = await loadFixture()
  const database = fixture.system.find(entry => entry.id === 'database')

  assert.equal(database.value, '0.2.0-candidate.1')
  assert.equal(database.status, 'planned')
  assert.match(database.detail, /193 Länder/)
  assert.match(database.detail, /193 Flaggen/)
  assert.match(database.detail, /193 Reviews offen/)
  assert.match(database.detail, /0 produktionsberechtigt/)
  assert.match(database.detail, /Human Review ausstehend/)
  assert.match(database.detail, /Remote-Sync unbestätigt/)
  assert.match(database.detail, /20ae94f73128f458c6938c67a2c5649313f853a87e4796381e5dccf040d31336/)
})

test('public content contract contains no secrets or local paths', async () => {
  inspectPublicValue(await loadFixture())
})
