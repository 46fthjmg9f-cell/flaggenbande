import assert from 'node:assert/strict'
import test from 'node:test'
import { buildOperatorAnalysisManifest } from '../scripts/operator-analysis-manifest.mjs'

test('operator analysis manifest keeps exact solutions and frame-derived timings', () => {
  const rounds = Array.from({ length: 5 }, (_, index) => ({
    round: index + 1,
    iso: ['de', 'uy', 'mz', 'pw', 'vu'][index],
    answer: ['Deutschland', 'Uruguay', 'Mosambik', 'Palau', 'Vanuatu'][index],
  }))
  const manifest = buildOperatorAnalysisManifest({
    runId: 'video-1234567890abcdef12345678',
    content: {
      schemaVersion: '1.0.0',
      runId: 'video-1234567890abcdef12345678',
      roundCount: 5,
      rounds,
    },
    runtime: {
      schemaVersion: '1.0.0',
      fps: 30,
      rounds: rounds.map((round, index) => ({
        round: round.round,
        questionFromFrame: index * 300,
        revealFrame: index * 300 + 120,
      })),
      words: [
        { word: 'welche', fromFrame: 0, durationInFrames: 9 },
        { word: 'flagge', fromFrame: 10, durationInFrames: 8 },
      ],
    },
  })

  assert.equal(manifest.timingSource, 'verified_word_cues')
  assert.deepEqual(manifest.rounds[0], {
    round: 1,
    solutionCountry: 'Deutschland',
    solutionCountryCode: 'DE',
    flagShownAtSeconds: 0,
    revealAtSeconds: 4,
  })
  assert.deepEqual(manifest.wordCues[1], {
    word: 'flagge',
    startSeconds: 0.333,
    endSeconds: 0.6,
  })
})

test('operator analysis manifest fails closed on mismatched round artifacts', () => {
  assert.throws(() => buildOperatorAnalysisManifest({
    runId: 'video-1234567890abcdef12345678',
    content: {
      schemaVersion: '1.0.0',
      runId: 'video-1234567890abcdef12345678',
      roundCount: 5,
      rounds: [],
    },
    runtime: { schemaVersion: '1.0.0', fps: 30, rounds: [], words: [] },
  }), /ANALYSIS_MANIFEST_INVALID/u)
})
