const record = value =>
  value && typeof value === 'object' && !Array.isArray(value) ? value : null

const finiteNonNegative = value =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null

const boundedText = (value, maximumLength) =>
  typeof value === 'string' && value.trim() && value.trim().length <= maximumLength
    ? value.trim()
    : null

const seconds = (frame, fps) => Number((frame / fps).toFixed(3))

/**
 * Converts the already verified production artifacts into the small,
 * provider-independent payload stored by the operator API. It deliberately
 * sends no local paths and no audio/media data.
 */
export const buildOperatorAnalysisManifest = ({ runId, content, runtime }) => {
  const contentRoot = record(content)
  const runtimeRoot = record(runtime)
  if (
    !/^video-[a-f0-9]{24}$/u.test(runId) ||
    contentRoot?.schemaVersion !== '1.0.0' ||
    contentRoot.runId !== runId ||
    runtimeRoot?.schemaVersion !== '1.0.0'
  ) throw new Error('ANALYSIS_MANIFEST_INVALID')

  const fps = finiteNonNegative(runtimeRoot.fps)
  const contentRounds = Array.isArray(contentRoot.rounds) ? contentRoot.rounds : []
  const runtimeRounds = Array.isArray(runtimeRoot.rounds) ? runtimeRoot.rounds : []
  const roundCount = Number(contentRoot.roundCount)
  if (
    !Number.isInteger(fps) || fps < 1 || fps > 120 ||
    !Number.isInteger(roundCount) || roundCount < 5 || roundCount > 10 ||
    contentRounds.length !== roundCount || runtimeRounds.length !== roundCount
  ) throw new Error('ANALYSIS_MANIFEST_INVALID')

  const runtimeByRound = new Map(runtimeRounds.flatMap(value => {
    const round = record(value)
    return Number.isInteger(round?.round) ? [[round.round, round]] : []
  }))
  const rounds = contentRounds.map((value, index) => {
    const contentRound = record(value)
    const roundNumber = index + 1
    const runtimeRound = runtimeByRound.get(roundNumber)
    const solutionCountry = boundedText(contentRound?.answer, 120)
    const solutionCountryCode = boundedText(contentRound?.iso, 3)?.toLocaleUpperCase('en') ?? null
    const flagFrame = finiteNonNegative(runtimeRound?.questionFromFrame)
    const revealFrame = finiteNonNegative(runtimeRound?.revealFrame)
    if (
      contentRound?.round !== roundNumber ||
      runtimeRound?.round !== roundNumber ||
      !solutionCountry ||
      !solutionCountryCode ||
      flagFrame === null ||
      revealFrame === null ||
      revealFrame < flagFrame
    ) throw new Error('ANALYSIS_MANIFEST_INVALID')
    return {
      round: roundNumber,
      solutionCountry,
      solutionCountryCode,
      flagShownAtSeconds: seconds(flagFrame, fps),
      revealAtSeconds: seconds(revealFrame, fps),
    }
  })

  const words = Array.isArray(runtimeRoot.words) ? runtimeRoot.words : []
  const wordCues = words.slice(0, 1_000).map(value => {
    const cue = record(value)
    const word = boundedText(cue?.word, 80)
    const fromFrame = finiteNonNegative(cue?.fromFrame)
    const durationInFrames = finiteNonNegative(cue?.durationInFrames)
    if (!word || fromFrame === null || durationInFrames === null) {
      throw new Error('ANALYSIS_MANIFEST_INVALID')
    }
    return {
      word,
      startSeconds: seconds(fromFrame, fps),
      endSeconds: seconds(fromFrame + durationInFrames, fps),
    }
  })

  return {
    schemaVersion: '1.0.0',
    timingSource: wordCues.length > 0 ? 'verified_word_cues' : 'round_boundaries',
    rounds,
    wordCues,
  }
}
