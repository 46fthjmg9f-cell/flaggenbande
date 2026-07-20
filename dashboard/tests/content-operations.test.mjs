import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const fixtureUrl = new URL('../public/data/content-operations.json', import.meta.url)
const forbiddenKey = /(secret|token|password|api.?key|private.?key|authorization|local.?path|onedrive.?path)/i
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

test('public content contract starts with all four unconfigured platforms', async () => {
  const fixture = await loadFixture()
  assert.equal(fixture.schemaVersion, 1)
  assert.equal(fixture.status, 'waiting_for_sources')
  assert.deepEqual(fixture.system.map(entry => entry.id).sort(), ['database', 'engine', 'quality', 'release'])
  assert.deepEqual(fixture.platforms.map(entry => entry.platform).sort(), ['facebook', 'instagram', 'tiktok', 'youtube'])
  assert.ok(fixture.platforms.every(entry => entry.status === 'not_configured'))
  assert.deepEqual(fixture.runs, [])
  assert.deepEqual(fixture.publications, [])
  assert.deepEqual(fixture.performance, [])
})

test('public content contract contains no secrets or local paths', async () => {
  inspectPublicValue(await loadFixture())
})
