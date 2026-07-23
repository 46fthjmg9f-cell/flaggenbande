import assert from 'node:assert/strict'
import test from 'node:test'
import {
  hasQuizPrompt,
  scriptProfileIssueMessage,
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
