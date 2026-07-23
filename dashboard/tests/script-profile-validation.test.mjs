import assert from 'node:assert/strict'
import test from 'node:test'
import {
  durationOptionsForRounds,
  hasQuizPrompt,
  minimumSpokenWordsForRounds,
  isProductionRoundCount,
  productionRoundCounts,
  recommendedTargetDuration,
  scriptProfileIssueMessage,
  supportedRoundCounts,
  validateScriptProfile,
} from '../../shared/scriptProfileValidation.ts'

test('natural creator prompts count as quiz questions without forced punctuation', () => {
  for (const prompt of [
    'sprich frei',
    'sag mal die Flagge an',
    'tell me',
    'deine Antwort',
    'weißt du das auch',
  ]) {
    assert.equal(hasQuizPrompt(prompt), true, prompt)
  }
  assert.equal(hasQuizPrompt('die nächste Runde wird schwieriger und startet jetzt'), false)
})

test('script profile reports the exact round with a missing prompt', () => {
  const segments = [
    'Welches Land ist das? Los geht die schnelle Runde.',
    'Sauber, sprich frei.',
    'Okay, Runde drei wird schwieriger. Welche Flagge ist das?',
    'Drei von drei wäre stark. Sag mal diese Flagge an.',
    'Halbfinale erreicht. Wie lautet deine Antwort?',
    'Noch zwei Runden. Tell me.',
    'Finale, nicht blinzeln. Welches Land ist das?',
    'Stark gespielt. Schreib deine ehrliche Punktzahl in die Kommentare und sag direkt dazu, welche Runde dich wirklich fast komplett rausgeworfen hätte.',
  ]
  const validScript = segments.join('\n(auflösung)\n')
  assert.equal(validateScriptProfile(validScript, 7, 69).valid, true)

  segments[1] = 'Sauber, die nächste Runde wird schwieriger und startet jetzt.'
  const validation = validateScriptProfile(segments.join('\n(auflösung)\n'), 7, 69)
  assert.equal(validation.valid, false)
  const issue = validation.details.find(entry => entry.code === 'QUESTION_PROMPT_MISSING')
  assert.equal(issue?.roundIndex, 2)
  assert.match(scriptProfileIssueMessage(issue), /Runde 2/u)
})

test('shared profile supports every production round count from five through ten', () => {
  assert.deepEqual(supportedRoundCounts, [5, 6, 7, 8, 9, 10])

  for (const roundCount of supportedRoundCounts) {
    const questions = Array.from(
      { length: roundCount },
      (_, index) => `Runde ${index + 1}: Welche Flagge ist das? Weißt du die Antwort wirklich sicher?`,
    )
    const ending = [
      'Stark gespielt, du warst bis zum Ende dabei und hast jede Runde konzentriert beantwortet.',
      'Schreib ehrlich in die Kommentare, wie viele Flaggen du wirklich erkannt hast.',
      'Welche Runde war für dich am schwersten?',
    ].join(' ')
    const script = `${questions.join('\n(auflösung)\n')}\n(auflösung)\n${ending}`
    const validation = validateScriptProfile(script, roundCount, recommendedTargetDuration(roundCount))

    assert.equal(validation.revealCount, roundCount)
    assert.ok(validation.spokenWordCount >= minimumSpokenWordsForRounds(roundCount))
    assert.equal(validation.valid, true, `${roundCount}: ${validation.issues.join(', ')}`)
    assert.ok(durationOptionsForRounds(roundCount).includes(recommendedTargetDuration(roundCount)))
  }
})

test('production adapters stay explicitly limited to five and seven rounds', () => {
  assert.deepEqual(productionRoundCounts, [5, 7])
  for (const roundCount of supportedRoundCounts) {
    assert.equal(isProductionRoundCount(roundCount), roundCount === 5 || roundCount === 7)
  }
})
