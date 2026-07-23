import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const componentUrl = new URL('../src/VideoProductionControl.tsx', import.meta.url)
const stylesUrl = new URL('../src/styles.css', import.meta.url)

test('production control exposes five through ten resolutions with adaptive targets', async () => {
  const source = await readFile(componentUrl, 'utf8')

  assert.match(source, /supportedRoundCounts\.map/u)
  assert.match(source, /recommendedTargetDuration\(value/u)
  assert.match(source, /minimumSpokenWordsForRounds\(roundCount/u)
  assert.match(source, /durationOptionsForRounds\(roundCount/u)
  assert.match(source, /brandValid = brandMentions === 0/u)
  assert.doesNotMatch(source, /brandMentions === 1/u)
  assert.doesNotMatch(source, /function markerCount/u)
  assert.match(source, /validateScriptProfile\(script, roundCount, targetDurationSeconds\)/u)
  assert.match(source, /isProductionRoundCount\(roundCount\)/u)
  assert.match(source, /Produktion aktuell nur 5 oder 7/u)
  assert.match(source, /!scriptValid \|\| !productionRoundCountSupported/u)
})

test('retention status never claims a measured curve without measurement points', async () => {
  const [source, styles] = await Promise.all([
    readFile(componentUrl, 'utf8'),
    readFile(stylesUrl, 'utf8'),
  ])

  for (const status of ['measured', 'aggregate_only', 'pending', 'unavailable']) {
    assert.match(source, new RegExp(`['"]${status}['"]`, 'u'))
  }
  assert.match(source, /if \(readiness\.retentionVideos > 0\)/u)
  assert.match(source, /if \(readiness\.averageViewPercentageVideos > 0\)/u)
  assert.match(source, /ohne Retention-Kurve/u)
  assert.doesNotMatch(source, />available</iu)
  assert.match(styles, /\.retention-status\.measured/u)
  assert.match(styles, /\.retention-status\.aggregate_only/u)
  assert.match(styles, /\.retention-status\.pending/u)
  assert.match(styles, /\.retention-status\.unavailable/u)
})

test('research wording cards show evidence sample and only supplied deltas', async () => {
  const source = await readFile(componentUrl, 'utf8')

  assert.match(source, /n=\{recommendation\.sampleSize\}/u)
  assert.match(source, /Δ \{delta \?\? '—'\}/u)
  assert.match(source, /recommendation\.action/u)
  assert.match(source, /Noch keine belastbare Formulierungsempfehlung/u)
})

test('production retry is visible only for locally validated pre-preview steps', async () => {
  const source = await readFile(componentUrl, 'utf8')

  assert.match(source, /new Set\(\['flag_selection', 'timeline_build', 'render'\]\)/u)
  assert.match(source, /safelyRetryablePreviewSteps\.has\(run\.currentStep \?\? ''\)/u)
  assert.match(source, /run\.videoApproval\.status === 'not_ready'/u)
  assert.match(source, /run\.release\.requestId === null/u)
  assert.match(source, /run\.release\.status === null/u)
})

test('an unapproved preview can be safely sent back for revision without releasing it', async () => {
  const source = await readFile(componentUrl, 'utf8')

  assert.match(source, /reviseOperatorVideo/u)
  assert.match(source, /const canReviseVideo = videoPending \|\| safelyRevisableFailedPreview/u)
  assert.match(source, /\{canReviseVideo && <button/u)
  assert.match(source, /Video nachbessern/u)
  assert.match(source, /Video freigeben & Veröffentlichung starten/u)
})

test('a failed local preview revision keeps the safe dashboard revision action', async () => {
  const source = await readFile(componentUrl, 'utf8')

  assert.match(source, /run\.status === 'failed'/u)
  assert.match(source, /run\.currentStep === 'preview_revision' \|\| run\.currentStep === 'script_validation'/u)
  assert.match(
    source,
    /run\.error === 'LOCAL_PREVIEW_REVISION_REJECTED' \|\| run\.error === 'LOCAL_INPUT_REJECTED'/u,
  )
  assert.match(source, /run\.script\.status === 'approved'/u)
  assert.match(source, /run\.preview\.ready/u)
  assert.match(source, /run\.videoApproval\.status === 'pending'/u)
  assert.match(source, /run\.release\.requestId === null/u)
  assert.match(source, /run\.release\.status === null/u)
})
