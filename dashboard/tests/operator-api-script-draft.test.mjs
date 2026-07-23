import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const operatorApiUrl = new URL('../src/operatorApi.ts', import.meta.url)

test('operator API parses five through ten rounds and typed phrase timelines', async () => {
  const source = await readFile(operatorApiUrl, 'utf8')

  assert.match(source, /export type ScriptPhraseType = 'hook' \| 'question' \| 'reveal'/u)
  assert.match(source, /phrases: ScriptPhraseTimeline/u)
  assert.match(source, /isSupportedRoundCount\(roundCount\)/u)
  assert.match(source, /parseScriptPhraseTimeline\(value\.phrases/u)
  assert.match(source, /rounds\.length !== expectedRoundCount/u)
})

test('research API validates and uses the backend retention availability state', async () => {
  const source = await readFile(operatorApiUrl, 'utf8')

  for (const status of ['measured', 'aggregate_only', 'pending', 'unavailable']) {
    assert.match(source, new RegExp(`'${status}'`, 'u'))
  }
  assert.match(source, /enumValue\(\s*value\.dataReadiness\.retentionStatus,/u)
  assert.doesNotMatch(source, /retentionVideos > 0\s*\?\s*'measured'/u)
})
