import assert from "node:assert/strict";
import test from "node:test";

import {
  buildResearchRecommendationFeed,
  DEFAULT_TARGET_DURATION,
  extractScriptPhrases,
  generateScriptDraft,
  validateScriptProfile,
} from "../cloud/operator-api/src/scriptDrafts.ts";

const roundCounts = [5, 6, 7, 8, 9, 10];

test("generates valid, brand-optional drafts for every supported round count", () => {
  for (const roundCount of roundCounts) {
    for (const recommendationId of [
      null,
      "first-reveal-delay-v1",
      "difficulty-ladder-visibility-v1",
    ]) {
      for (let seed = 0; seed < 32; seed += 1) {
        const result = generateScriptDraft({
          roundCount,
          targetDurationSeconds: DEFAULT_TARGET_DURATION[roundCount],
          recommendationId,
          requestSeed: `test-${roundCount}-${recommendationId ?? "baseline"}-${seed}`,
        }, []);
        assert.equal(
          validateScriptProfile(
            result.script,
            roundCount,
            DEFAULT_TARGET_DURATION[roundCount],
          ).valid,
          true,
          `rounds=${roundCount}, recommendation=${recommendationId ?? "baseline"}, seed=${seed}`,
        );
        assert.equal(result.phrases.roundCount, roundCount);
        assert.equal(result.phrases.rounds.length, roundCount);
        assert.equal(
          result.phrases.phrases.filter((phrase) => phrase.type === "reveal").length,
          roundCount,
        );
        assert.doesNotMatch(result.script, /\bflaggenbande\b/iu);
      }
    }
  }
});

test("extractScriptPhrases is deterministic and retention-ready", () => {
  const script = [
    "SCHNELLE FLAGGENRUNDE! Welches Land ist das?",
    "(auflösung)",
    "Crazy! Nächste Runde: Welche Flagge siehst du?",
    "(auflösung)",
    "Sauber. Jetzt wird es schwer: Welches Land ist das?",
    "(auflösung)",
    "Stark. Bleib fokussiert: Welche Flagge siehst du?",
    "(auflösung)",
    "Fast geschafft: Welches Land ist das?",
    "(auflösung)",
    "Schreib deine Punktzahl in die Kommentare.",
  ].join("\n");
  const first = extractScriptPhrases(script, 5);
  const second = extractScriptPhrases(script, 5);
  assert.deepEqual(first, second);
  assert.equal(new Set(first.phrases.map((phrase) => phrase.phraseId)).size, first.phrases.length);
  assert.ok(first.phrases.some((phrase) => phrase.type === "hook"));
  assert.ok(first.phrases.some((phrase) => phrase.type === "question"));
  assert.ok(first.phrases.some((phrase) => phrase.type === "reaction"));
  assert.ok(first.phrases.some((phrase) => phrase.type === "transition"));
  assert.ok(first.phrases.some((phrase) => phrase.type === "cta"));
  for (const phrase of first.phrases) {
    assert.equal(phrase.startSeconds, null);
    assert.equal(phrase.endSeconds, null);
    assert.equal(phrase.solutionCountry, null);
    assert.equal(phrase.solutionCountryCode, null);
  }
});

test("extractScriptPhrases classifies the validator's natural prompts as questions", () => {
  const expectedQuestionTexts = [
    "Schnelle Runde, sprich frei",
    "Sauber, sag mal die Flagge an",
    "Jetzt tell me",
    "Was ist deine Antwort",
    "Finale, weißt du das auch",
  ];
  const script = [
    expectedQuestionTexts[0],
    "(auflösung)",
    expectedQuestionTexts[1],
    "(auflösung)",
    expectedQuestionTexts[2],
    "(auflösung)",
    expectedQuestionTexts[3],
    "(auflösung)",
    expectedQuestionTexts[4],
    "(auflösung)",
    "Stark gespielt.",
  ].join("\n");

  const timeline = extractScriptPhrases(script, 5);
  assert.equal(timeline.rounds.every((round) => round.questionPhraseId !== null), true);
  assert.deepEqual(
    timeline.phrases.filter((phrase) => phrase.type === "question").map((phrase) => phrase.text),
    expectedQuestionTexts,
  );
});

test("rejects a round-count mismatch before persistence", () => {
  assert.throws(
    () => extractScriptPhrases("Welche Flagge ist das?\n(auflösung)\nSauber.", 5),
    /ROUND_COUNT_MISMATCH/u,
  );
});

const contentId = (index) =>
  `flaggenbande-${index.toString(16).padStart(64, "0")}`;

const youtubeVideo = (index, overrides = {}) => ({
  platform: "youtube",
  platformVideoId: `youtube-${index}`,
  contentId: contentId(index),
  durationSeconds: 64,
  metrics: {},
  retention: [],
  ...overrides,
});

test("research feed distinguishes measured, aggregate-only, pending and unavailable retention", () => {
  const unavailable = buildResearchRecommendationFeed(
    { social: { videos: [] } },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(unavailable.dataReadiness.retentionStatus, "unavailable");

  const pending = buildResearchRecommendationFeed(
    { social: { videos: [youtubeVideo(1, { retentionCheckStatus: "pending" })] } },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(pending.dataReadiness.retentionStatus, "pending");

  const aggregateOnly = buildResearchRecommendationFeed(
    {
      social: {
        videos: [youtubeVideo(1, { metrics: { averageViewPercentage: 72 } })],
      },
    },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(aggregateOnly.dataReadiness.retentionStatus, "aggregate_only");

  const measured = buildResearchRecommendationFeed(
    {
      social: {
        videos: [youtubeVideo(1, {
          metrics: { averageViewPercentage: 72 },
          retention: [
            { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
            { elapsedVideoTimeRatio: 0.1, audienceWatchRatio: 0.7 },
          ],
        })],
      },
    },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(measured.dataReadiness.retentionStatus, "measured");
  assert.equal(measured.dataReadiness.status, "insufficient");
  assert.match(measured.dataReadiness.message, /Vergleichsmenge/u);
});

test("research feed never extrapolates a partial curve into measured 3-second retention", () => {
  const startsAfterThreeSeconds = buildResearchRecommendationFeed(
    {
      social: {
        videos: [youtubeVideo(1, {
          retention: [
            { elapsedVideoTimeRatio: 0.1, audienceWatchRatio: 0.82 },
            { elapsedVideoTimeRatio: 1, audienceWatchRatio: 0.4 },
          ],
        })],
      },
    },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(startsAfterThreeSeconds.dataReadiness.retentionVideos, 0);
  assert.equal(startsAfterThreeSeconds.dataReadiness.retentionStatus, "pending");

  const endsBeforeThreeSeconds = buildResearchRecommendationFeed(
    {
      social: {
        videos: [youtubeVideo(1, {
          retention: [
            { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
            { elapsedVideoTimeRatio: 2 / 64, audienceWatchRatio: 0.94 },
          ],
        })],
      },
    },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(endsBeforeThreeSeconds.dataReadiness.retentionVideos, 0);
  assert.equal(endsBeforeThreeSeconds.dataReadiness.retentionStatus, "pending");

  const bracketsThreeSeconds = buildResearchRecommendationFeed(
    {
      social: {
        videos: [youtubeVideo(1, {
          retention: [
            { elapsedVideoTimeRatio: 2 / 64, audienceWatchRatio: 0.94 },
            { elapsedVideoTimeRatio: 4 / 64, audienceWatchRatio: 0.88 },
          ],
        })],
      },
    },
    "2026-07-23T10:00:00Z",
  );
  assert.equal(bracketsThreeSeconds.dataReadiness.retentionVideos, 1);
  assert.equal(bracketsThreeSeconds.dataReadiness.retentionStatus, "measured");
});

test("phrase retention evaluates only exact timed phrases backed by real curves", () => {
  const videos = Array.from({ length: 3 }, (_, index) => youtubeVideo(index + 1, {
    retention: [
      { elapsedVideoTimeRatio: 0, audienceWatchRatio: 1 },
      { elapsedVideoTimeRatio: 1 / 64, audienceWatchRatio: 0.96 - index * 0.01 },
      { elapsedVideoTimeRatio: 2 / 64, audienceWatchRatio: 0.90 - index * 0.01 },
      { elapsedVideoTimeRatio: 1, audienceWatchRatio: 0.4 },
    ],
  }));
  const timelines = videos.map((video, index) => ({
    contentId: video.contentId,
    phrases: [
      {
        phraseId: `question-${index}`,
        formulationKey: "formulation-question-shared",
        type: "question",
        text: "Welche Flagge ist das?",
        startSeconds: 1,
        endSeconds: 2,
      },
      {
        phraseId: `untimed-${index}`,
        formulationKey: "formulation-untimed",
        type: "reaction",
        text: "Crazy.",
        startSeconds: null,
        endSeconds: null,
      },
    ],
  }));

  const feed = buildResearchRecommendationFeed(
    { social: { videos } },
    "2026-07-23T10:00:00Z",
    null,
    timelines,
  );
  assert.equal(feed.dataReadiness.phraseTimelineVideos, 3);
  assert.equal(feed.dataReadiness.phraseRetentionVideos, 3);
  assert.equal(feed.phraseEvaluations.length, 1);
  assert.deepEqual(feed.phraseEvaluations[0], {
    formulationKey: "formulation-question-shared",
    phraseType: "question",
    formulation: "Welche Flagge ist das?",
    sampleSize: 3,
    videoCount: 3,
    medianEntryRetention: 0.95,
    medianExitRetention: 0.89,
    medianDeltaPercentagePoints: -6,
    evidenceLevel: "measured",
    confidence: "low",
    causalInference: false,
  });
});

test("phrase retention does not manufacture evaluations without timings or curves", () => {
  const video = youtubeVideo(1, {
    metrics: { averageViewPercentage: 74 },
  });
  const feed = buildResearchRecommendationFeed(
    { social: { videos: [video] } },
    "2026-07-23T10:00:00Z",
    null,
    [{
      contentId: video.contentId,
      phrases: [{
        formulationKey: "formulation-question-shared",
        type: "question",
        text: "Welche Flagge ist das?",
        startSeconds: 1,
        endSeconds: 2,
      }],
    }],
  );
  assert.equal(feed.dataReadiness.retentionStatus, "aggregate_only");
  assert.equal(feed.dataReadiness.phraseTimelineVideos, 1);
  assert.equal(feed.dataReadiness.phraseRetentionVideos, 0);
  assert.deepEqual(feed.phraseEvaluations, []);
});
