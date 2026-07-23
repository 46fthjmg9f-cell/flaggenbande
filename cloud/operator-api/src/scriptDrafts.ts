import {
  hasQuizPrompt,
  normalizeQuizScript,
  validateScriptProfile,
  type SupportedRoundCount,
} from "../../../shared/scriptProfileValidation.ts";

export {
  validateScriptProfile,
  type ScriptProfileIssue,
  type ScriptProfileIssueCode,
  type ScriptProfileValidation,
  type SupportedRoundCount,
} from "../../../shared/scriptProfileValidation.ts";

export type ScriptPhraseType =
  | "hook"
  | "question"
  | "reveal"
  | "reaction"
  | "transition"
  | "cta";

export interface ScriptPhrase {
  readonly phraseId: string;
  readonly formulationKey: string;
  readonly type: ScriptPhraseType;
  readonly text: string;
  readonly round: number | null;
  readonly position: number;
  readonly startSeconds: number | null;
  readonly endSeconds: number | null;
  readonly solutionCountry: string | null;
  readonly solutionCountryCode: string | null;
}

export interface ScriptRound {
  readonly round: number;
  readonly phraseIds: readonly string[];
  readonly questionPhraseId: string | null;
  readonly revealPhraseId: string;
  readonly solutionCountry: string | null;
  readonly solutionCountryCode: string | null;
  readonly flagShownAtSeconds: number | null;
  readonly revealAtSeconds: number | null;
}

export interface ScriptPhraseTimeline {
  readonly schemaVersion: "1.0.0";
  readonly roundCount: SupportedRoundCount;
  readonly phrases: readonly ScriptPhrase[];
  readonly rounds: readonly ScriptRound[];
}

export interface ScriptDraftRequest {
  readonly roundCount: SupportedRoundCount;
  readonly targetDurationSeconds: number;
  readonly recommendationId: string | null;
  readonly requestSeed: string;
}

export interface ScriptDraftResult {
  readonly script: string;
  readonly learnedSignals: readonly string[];
  readonly generatorVersion: string;
  readonly phrases: ScriptPhraseTimeline;
}

export interface ResearchRecommendation {
  readonly id: string;
  readonly title: string;
  readonly action: string;
  readonly primaryParameter: string;
  readonly targetMetric: string;
  readonly evidenceLevel: "measured" | "public" | "inferred" | "unavailable";
  readonly confidence: "low" | "medium" | "high";
  readonly sampleSize: number;
  readonly sourceRun: string;
  readonly autoApplicable: false;
}

export type RetentionDataStatus =
  | "measured"
  | "aggregate_only"
  | "pending"
  | "unavailable";

export interface ResearchPhraseEvaluation {
  readonly formulationKey: string;
  readonly phraseType: ScriptPhraseType;
  readonly formulation: string;
  readonly sampleSize: number;
  readonly videoCount: number;
  readonly medianEntryRetention: number;
  readonly medianExitRetention: number;
  readonly medianDeltaPercentagePoints: number;
  readonly evidenceLevel: "measured";
  readonly confidence: "low" | "medium" | "high";
  readonly causalInference: false;
}

export interface ResearchRecommendationFeed {
  readonly schemaVersion: "1.1.0";
  readonly generatedAt: string;
  readonly dataReadiness: {
    readonly status: "ready" | "insufficient";
    readonly retentionStatus: RetentionDataStatus;
    readonly platformVideoCount: number;
    readonly linkedYoutubeVideos: number;
    readonly retentionVideos: number;
    readonly averageViewPercentageVideos: number;
    readonly phraseTimelineVideos: number;
    readonly phraseRetentionVideos: number;
    readonly minimumComparableVideos: number;
    readonly message: string;
  };
  readonly recommendations: readonly ResearchRecommendation[];
  readonly phraseEvaluations: readonly ResearchPhraseEvaluation[];
}

export const SCRIPT_GENERATOR_VERSION = "creator-style-organic-v6";
export const DEFAULT_TARGET_DURATION: Readonly<Record<SupportedRoundCount, number>> = {
  5: 64,
  6: 66,
  7: 69,
  8: 69,
  9: 70,
  10: 70,
};

export const isSupportedRoundCount = (value: number): value is SupportedRoundCount =>
  Number.isInteger(value) && value >= 5 && value <= 10;

const hashSeed = (value: string): number => {
  let hash = 2_166_136_261;
  for (const character of value) {
    hash ^= character.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16_777_619);
  }
  return hash >>> 0;
};

const choose = <T>(values: readonly T[], seed: number, offset: number): T =>
  values[(seed + offset * 2_654_435_761) % values.length] as T;

const mixSeed = (value: number): number => {
  let mixed = value >>> 0;
  mixed ^= mixed >>> 16;
  mixed = Math.imul(mixed, 0x7feb352d);
  mixed ^= mixed >>> 15;
  mixed = Math.imul(mixed, 0x846ca68b);
  mixed ^= mixed >>> 16;
  return mixed >>> 0;
};

const chooseIndependent = <T>(
  values: readonly T[],
  seed: number,
  namespace: string,
): T => values[mixSeed(seed ^ hashSeed(namespace)) % values.length] as T;

const creatorStyleFlourish = (seed: number): string => {
  const reaction = chooseIndependent([
    "okok", "crazy", "ajo", "sauber", "stark", "was läuft", "lowkey wild",
    "alles klar", "sehr stabil", "weiter gehts", "uff", "na also",
    "hier geht was", "komplett wild", "ganz sauber", "nicht schlecht",
  ], seed, "reaction");
  const address = chooseIndependent([
    "bre", "Junge", "großer", "Chef", "Flaggenboss", "Meister", "Legende", "Baba",
  ], seed, "address");
  const transition = chooseIndependent([
    "bleib dran", "jetzt wirds kernig", "die nächste wird tough",
    "nicht zu früh feiern", "ab hier wirds eng", "weiter im Text",
    "jetzt sach ma an", "Fokus behalten", "noch bist du drin",
    "kein Zurück mehr", "jetzt zählt Ahnung", "die nächste beißt",
    "weiter im Quiz", "jetzt kommt Druck", "die Runde lebt", "aufgepasst",
  ], seed, "transition");
  return `${reaction} ${address}, ${transition}.`;
};

const learnedStyleSignals = (examples: readonly string[]): readonly string[] => {
  const corpus = examples.join(" ").toLocaleLowerCase("de");
  return [
    ["bre", /\bbre\b/u],
    ["crazy", /\bcrazy\b/u],
    ["junge", /\bjunge\b/u],
    ["flaggenboss", /\bflaggen(?:boss|chef)\b/u],
    ["lowkey", /\blowkey\b/u],
    ["sag an", /\bsag (?:mal )?an\b/u],
  ].filter(([, pattern]) => (pattern as RegExp).test(corpus)).map(([signal]) => signal as string);
};

const normalizeScript = (script: string): string => normalizeQuizScript(script);

const normalizeFormulation = (text: string): string => text
  .normalize("NFC")
  .toLocaleLowerCase("de")
  .replace(/[^\p{L}\p{N}]+/gu, " ")
  .trim();

const formulationKey = (type: ScriptPhraseType, text: string): string => {
  const source = `${type}:${normalizeFormulation(text)}`;
  const first = hashSeed(source).toString(16).padStart(8, "0");
  const second = hashSeed(`formulation:${source}`).toString(16).padStart(8, "0");
  return `formulation-${first}${second}`;
};

const splitQuestionSuffix = (text: string): readonly string[] => {
  if (!text.endsWith("?")) return [text];
  const match = text.match(
    /(?:^|[,:;]\s+)((?:welche|welcher|welches|welchem|was|wie|wer|wo|zu welchem|name|sag|wei(?:ß|ss)t)[^?]*\?)$/iu,
  );
  if (!match || match.index === undefined || match.index === 0) return [text];
  const question = match[1]?.trim() ?? "";
  const prefix = text.slice(0, match.index + (text[match.index] === "," ||
      text[match.index] === ":" || text[match.index] === ";" ? 1 : 0)).trim();
  return prefix && question ? [prefix, question] : [text];
};

const splitSpokenPhrases = (text: string): readonly string[] =>
  (text.match(/[^.!?]+[.!?]+|[^.!?]+$/gu) ?? [])
    .map((phrase) => phrase.trim())
    .filter(Boolean)
    .flatMap(splitQuestionSuffix);

const ctaPattern =
  /\b(?:kommentar|kommis|schreib|score|punktzahl|like|liken|folge|folgen)\b/iu;

const phraseSlotId = (
  round: number | null,
  type: ScriptPhraseType,
  ordinal: number,
  text: string,
): string => {
  const roundSlot = round === null ? "global" : `r${String(round).padStart(2, "0")}`;
  const textKey = formulationKey(type, text).slice(-6);
  return `phrase-${roundSlot}-${type}-${String(ordinal).padStart(2, "0")}-${textKey}`;
};

/**
 * Converts the human-readable script into deterministic phrase and round slots.
 *
 * Timings and solutions intentionally start as null. The production worker can
 * fill them from word timestamps and the selected flag without changing phrase
 * identity. formulationKey stays identical when the same wording is reused in
 * another video, enabling cross-video retention comparisons.
 */
export const extractScriptPhrases = (
  scriptInput: string,
  roundCount: SupportedRoundCount,
): ScriptPhraseTimeline => {
  if (!isSupportedRoundCount(roundCount)) {
    throw new Error("UNSUPPORTED_ROUND_COUNT");
  }
  const lines = normalizeScript(scriptInput).split("\n");
  const revealCount = lines.filter((line) => line === "(auflösung)").length;
  if (revealCount !== roundCount) {
    throw new Error("ROUND_COUNT_MISMATCH");
  }

  const phrases: ScriptPhrase[] = [];
  const phraseOrdinals = new Map<string, number>();
  let nextRound = 1;
  let lastRevealRound: number | null = null;
  let hasQuestion = false;

  const append = (
    type: ScriptPhraseType,
    text: string,
    round: number | null,
  ): ScriptPhrase => {
    const slot = `${round ?? "global"}:${type}`;
    const ordinal = (phraseOrdinals.get(slot) ?? 0) + 1;
    phraseOrdinals.set(slot, ordinal);
    const phrase: ScriptPhrase = {
      phraseId: phraseSlotId(round, type, ordinal, text),
      formulationKey: formulationKey(type, text),
      type,
      text,
      round,
      position: phrases.length,
      startSeconds: null,
      endSeconds: null,
      solutionCountry: null,
      solutionCountryCode: null,
    };
    phrases.push(phrase);
    return phrase;
  };

  for (const line of lines) {
    if (line === "(auflösung)") {
      append("reveal", line, nextRound);
      lastRevealRound = nextRound;
      nextRound += 1;
      continue;
    }
    for (const text of splitSpokenPhrases(line)) {
      const question = hasQuizPrompt(text);
      if (question) {
        append("question", text, Math.min(nextRound, roundCount));
        hasQuestion = true;
        lastRevealRound = null;
        continue;
      }
      if (ctaPattern.test(text)) {
        append("cta", text, Math.min(lastRevealRound ?? nextRound, roundCount));
        lastRevealRound = null;
        continue;
      }
      if (!hasQuestion && nextRound === 1) {
        append("hook", text, 1);
        continue;
      }
      if (lastRevealRound !== null) {
        append("reaction", text, lastRevealRound);
        lastRevealRound = null;
        continue;
      }
      append("transition", text, Math.min(nextRound, roundCount));
    }
  }

  const rounds: ScriptRound[] = Array.from({ length: roundCount }, (_, index) => {
    const round = index + 1;
    const roundPhrases = phrases.filter((phrase) => phrase.round === round);
    const reveal = roundPhrases.find((phrase) => phrase.type === "reveal");
    if (!reveal) throw new Error("REVEAL_PHRASE_MISSING");
    return {
      round,
      phraseIds: roundPhrases.map((phrase) => phrase.phraseId),
      questionPhraseId: roundPhrases.find((phrase) => phrase.type === "question")?.phraseId ?? null,
      revealPhraseId: reveal.phraseId,
      solutionCountry: null,
      solutionCountryCode: null,
      flagShownAtSeconds: null,
      revealAtSeconds: null,
    };
  });

  return {
    schemaVersion: "1.0.0",
    roundCount,
    phrases,
    rounds,
  };
};

const styleSegments = (
  script: string,
  roundCount: SupportedRoundCount,
  targetDurationSeconds: number,
): readonly string[] | null => {
  const normalized = normalizeScript(script);
  if (!validateScriptProfile(normalized, roundCount, targetDurationSeconds).valid) return null;
  const segments = normalized.split("\n(auflösung)\n");
  return segments.length === roundCount + 1 ? segments : null;
};

const remixApprovedStyle = (
  examples: readonly string[],
  fallbackScript: string,
  request: ScriptDraftRequest,
  seed: number,
): string | null => {
  const templates = examples.flatMap((script) => {
    const segments = styleSegments(script, request.roundCount, request.targetDurationSeconds);
    return segments ? [segments] : [];
  });
  if (templates.length === 0) return null;
  const fallback = styleSegments(
    fallbackScript,
    request.roundCount,
    request.targetDurationSeconds,
  );
  if (!fallback) return null;
  const base = choose(templates, seed, 0);
  const mixed = base.map((segment, index) => {
    const candidates = templates
      .map((template) => template[index] as string)
      .filter((candidate) => !/\bflaggenbande\b/iu.test(candidate));
    return candidates.length > 0
      ? choose(candidates, seed, index + 1)
      : fallback[index] as string;
  });
  // Mindestens ein Segment stammt bewusst aus dem validierten Generator.
  // So bleibt der freigegebene Creator-Stil klar erkennbar, ohne ein einzelnes
  // Lernbeispiel als vermeintlich "neues" Skript 1:1 zu kopieren.
  const variationIndexes = mixed
    .map((_, index) => index)
    .filter((index) => index !== 1);
  const variationIndex = choose(
    variationIndexes.length > 0 ? variationIndexes : [0],
    seed,
    11,
  );
  mixed[variationIndex] = fallback[variationIndex] as string;
  if (request.recommendationId === "first-reveal-delay-v1") {
    mixed[0] = "SCHNELLE FLAGGENRUNDE! Welches Land ist das?";
  }
  if (request.recommendationId === "difficulty-ladder-visibility-v1" && mixed[1]) {
    mixed[1] = `Ab jetzt steigt jede Runde eine Stufe. ${mixed[1]}`;
  }
  const remixed = mixed.join("\n(auflösung)\n");
  return validateScriptProfile(remixed, request.roundCount, request.targetDurationSeconds).valid
    ? remixed
    : fallbackScript;
};

const addCreatorStyleVariation = (
  script: string,
  request: ScriptDraftRequest,
  seed: number,
): string => {
  const segments = styleSegments(
    script,
    request.roundCount,
    request.targetDurationSeconds,
  );
  if (!segments) return script;
  const varied = [...segments];
  const flourishIndexes = varied
    .map((_, index) => index)
    .filter((index) => index > 0);
  const flourishIndex = chooseIndependent(
    flourishIndexes.length > 0 ? flourishIndexes : [0],
    seed,
    "flourish-position",
  );
  varied[flourishIndex] = `${creatorStyleFlourish(seed)} ${varied[flourishIndex]}`;
  const candidate = varied.join("\n(auflösung)\n");
  return validateScriptProfile(candidate, request.roundCount, request.targetDurationSeconds).valid
    ? candidate
    : script;
};

const interjection = (
  available: readonly string[],
  fallback: readonly string[],
  seed: number,
  offset: number,
): string => {
  const preferred = available.length > 0 ? available : fallback;
  return choose(preferred, seed, offset);
};

const generateFiveRoundScript = (
  seed: number,
  signals: readonly string[],
  recommendationId: string | null,
): string => {
  const opener = recommendationId === "first-reveal-delay-v1"
    ? "SCHNELLE FLAGGENRUNDE! Welches Land ist das?"
    : choose([
        "BINGOBANGOFLAGGENQUIZ! Fünf Flaggen, eine davon wird komplett wild. Welches Land ist das?",
        "CHECK DAS MAL AUS, schnelle Flaggenrunde! Fängt easy an: Welches Land ist das?",
        "WAS LÄUFT WAS LÄUFT, fünf Flaggen und am Ende wird es kernig. Welches Land ist das?",
      ], seed, 0);
  const hype = interjection(signals, ["crazy", "sauber", "stark"], seed, 1);
  const address = signals.includes("bre") ? "bre" : signals.includes("junge") ? "junge" : "Chef";
  const finalTitle = signals.includes("flaggenboss") ? "Flaggenboss" : "Flaggenchef";
  const ladder = recommendationId === "difficulty-ladder-visibility-v1"
    ? "Runde zwei ist schon deutlich schwerer, also nicht zu früh feiern."
    : "Die nächste wird tougher, also nicht zu früh feiern.";
  return [
    opener,
    "(auflösung)",
    `${hype}! Eins von eins. ${ladder} Wie schaut es bei dieser Flagge aus?`,
    "(auflösung)",
    `Okay ${address}, hier geht was. Jetzt wird es wirklich knifflig: Welches Land gehört zu dieser Flagge?`,
    "(auflösung)",
    "Drei von drei wäre brutal stark. Ab hier trennt sich Glück von echter Ahnung. Bereit fürs Halbfinale, welches Land ist das?",
    "(auflösung)",
    `${hype}, vielleicht ist hier wirklich der ${finalTitle} am Start. Letzte Runde, Mann oder Maus: Welche Flagge siehst du?`,
    "(auflösung)",
    `Ansage! Wenn du alle hattest, bist du offiziell der ${finalTitle}. Schreib ehrlich in die Kommentare, wie viele du sauber erkannt hast.`,
  ].join("\n");
};

const generateSevenRoundScript = (
  seed: number,
  signals: readonly string[],
  recommendationId: string | null,
): string => {
  const opener = recommendationId === "first-reveal-delay-v1"
    ? "FLINKE FLAGGENRUNDE! Welches Land ist das?"
    : choose([
        "BINGOBANGOFLAGGENQUIZ! Sieben Flaggen, kein Zurück. Welches Land ist das?",
        "CHECK DAS MAL AUS, schnelle Flaggenrunde! Welche Flagge ist das?",
        "WAS LÄUFT WAS LÄUFT, sieben Flaggen bis zum Boss-Level. Welches Land ist das?",
      ], seed, 0);
  const hype = interjection(signals, ["crazy", "stabil", "sauber"], seed, 1);
  const address = signals.includes("bre") ? "bre" : signals.includes("junge") ? "junge" : "großer";
  const ladder = recommendationId === "difficulty-ladder-visibility-v1"
    ? "Ab jetzt steigt jede Runde sichtbar eine Stufe."
    : "Ab jetzt wird es schrittweise härter.";
  return [
    opener,
    "(auflösung)",
    `${hype}! Eins von eins. ${ladder} Welche Flagge kommt dir hier bekannt vor?`,
    "(auflösung)",
    `Okay ${address}, du bist noch dabei. Runde drei ist nicht mehr geschenkt: Welches Land ist das?`,
    "(auflösung)",
    "Drei von drei wäre stark, aber jetzt trennt sich Glück von Ahnung. Wie lautet deine Antwort?",
    "(auflösung)",
    `${hype}, Halbfinale erreicht. Die nächsten beiden werfen fast alle raus: Welche Flagge siehst du?`,
    "(auflösung)",
    `Fünf Runden geschafft? Dann sag jetzt frei heraus: Zu welchem Land gehört diese Flagge?`,
    "(auflösung)",
    "Noch genau eine. Finaler Boss-Modus, nicht blinzeln: Welches Land ist das?",
    "(auflösung)",
    "Das war die komplette Runde. Wenn du sieben hattest, bist du offiziell der Flaggenboss. Schreib deine ehrliche Punktzahl in die Kommentare.",
  ].join("\n");
};

const generateVariableRoundScript = (
  roundCount: SupportedRoundCount,
  seed: number,
  signals: readonly string[],
  recommendationId: string | null,
): string => {
  const hype = interjection(signals, ["crazy", "stabil", "sauber"], seed, 1);
  const address = signals.includes("bre") ? "bre" : signals.includes("junge") ? "junge" : "Chef";
  const questions = [
    "Fängt noch locker an: Welches Land ist das?",
    "Nicht zu früh feiern. Wie schaut es bei dieser Flagge aus?",
    "Ab jetzt wird es knifflig: Welches Land gehört zu dieser Flagge?",
    "Bleib fokussiert: Welche Flagge siehst du?",
    "Jetzt zählt Ahnung. Zu welchem Land gehört diese Flagge?",
    "Die Runde wird kernig: Wie lautet deine Antwort?",
    "Fast niemand bleibt hier sauber: Welches Land ist das?",
    "Boss-Modus: Welche Flagge siehst du?",
    "Kein Raten mehr: Zu welchem Land gehört diese Flagge?",
    "Finale, Mann oder Maus: Welches Land ist das?",
  ] as const;
  const reactions = [
    `${hype}! Eins von eins.`,
    `Okay ${address}, hier geht was.`,
    "Sauber, aber die Schwierigkeit zieht jetzt an.",
    "Stark geblieben, die nächste wirft viele raus.",
    `${hype}, noch bist du perfekt unterwegs.`,
    "Nicht schlecht, ab hier zählt echte Flaggenahnung.",
    `Okay ${address}, jetzt kommt Druck.`,
    "Komplett wild, nur noch zwei.",
    "Eine einzige Flagge fehlt noch.",
    "Ansage! Schreib ehrlich in die Kommentare, wie viele du erkannt hast.",
  ] as const;
  const opener = recommendationId === "first-reveal-delay-v1"
    ? `SCHNELLE FLAGGENRUNDE! ${questions[0]}`
    : choose([
        `BINGOBANGOFLAGGENQUIZ! ${roundCount} Flaggen, eine davon wird komplett wild. ${questions[0]}`,
        `CHECK DAS MAL AUS, schnelle Flaggenrunde! ${roundCount} Flaggen bis zum Boss-Level. ${questions[0]}`,
        `WAS LÄUFT WAS LÄUFT, ${roundCount} Flaggen und kein Zurück. ${questions[0]}`,
      ], seed, 0);
  const lines = [opener, "(auflösung)"];
  for (let index = 0; index < roundCount; index += 1) {
    const finalRound = index === roundCount - 1;
    if (finalRound) {
      lines.push(reactions.at(-1) as string);
      break;
    }
    const transition = recommendationId === "difficulty-ladder-visibility-v1"
      ? `Stufe ${String(index + 2)}.`
      : reactions[index] ?? reactions[reactions.length - 2];
    lines.push(`${transition} ${questions[index + 1]}`, "(auflösung)");
  }
  return lines.join("\n");
};

export const generateScriptDraft = (
  request: ScriptDraftRequest,
  styleExamples: readonly string[],
): ScriptDraftResult => {
  const learnedSignals = learnedStyleSignals(styleExamples);
  const seed = hashSeed(`${request.requestSeed}:${request.roundCount}:${request.recommendationId ?? "baseline"}`);
  const fallback = request.roundCount === 5
    ? generateFiveRoundScript(seed, learnedSignals, request.recommendationId)
    : request.roundCount === 7
      ? generateSevenRoundScript(seed, learnedSignals, request.recommendationId)
      : generateVariableRoundScript(
          request.roundCount,
          seed,
          learnedSignals,
          request.recommendationId,
        );
  const remixed = remixApprovedStyle(styleExamples, fallback, request, seed);
  const script = addCreatorStyleVariation(remixed ?? fallback, request, seed);
  return {
    script,
    learnedSignals,
    generatorVersion: SCRIPT_GENERATOR_VERSION,
    phrases: extractScriptPhrases(script, request.roundCount),
  };
};

const record = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;

const finiteNumber = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

const safeYoutubeVideoId = (value: unknown): string | null => {
  if (typeof value !== "string" || value.trim() === "") return null;
  const direct = value.trim();
  if (/^[A-Za-z0-9_-]{6,32}$/u.test(direct)) return direct;
  try {
    const url = new URL(direct);
    const hostname = url.hostname.toLocaleLowerCase("en");
    if (hostname === "youtu.be") {
      const id = url.pathname.split("/").filter(Boolean)[0] ?? "";
      return /^[A-Za-z0-9_-]{6,32}$/u.test(id) ? id : null;
    }
    if (!["youtube.com", "www.youtube.com", "m.youtube.com"].includes(hostname)) return null;
    const queryId = url.searchParams.get("v") ?? "";
    if (/^[A-Za-z0-9_-]{6,32}$/u.test(queryId)) return queryId;
    const [, pathId = ""] = url.pathname.match(/^\/(?:shorts|embed|live)\/([^/]+)/u) ?? [];
    return /^[A-Za-z0-9_-]{6,32}$/u.test(pathId) ? pathId : null;
  } catch {
    return null;
  }
};

const linkYoutubeContentIds = (
  dashboardVideos: readonly unknown[],
  contentOperations: unknown,
): readonly Record<string, unknown>[] => {
  const operations = record(contentOperations);
  const publications = Array.isArray(operations?.publications)
    ? operations.publications
    : [];
  const contentByVideoId = new Map<string, string>();
  for (const entry of publications) {
    const publication = record(entry);
    if (publication?.platform !== "youtube") continue;
    const contentId = typeof publication.contentId === "string"
      ? publication.contentId.trim()
      : "";
    const videoId = safeYoutubeVideoId(publication.platformVideoId) ??
      safeYoutubeVideoId(publication.publicUrl);
    if (!videoId || !/^flaggenbande-[a-f0-9]{64}$/u.test(contentId)) continue;
    contentByVideoId.set(videoId, contentId);
  }
  return dashboardVideos.flatMap((entry) => {
    const video = record(entry);
    if (!video) return [];
    if (
      video.platform !== "youtube" ||
      (typeof video.contentId === "string" && video.contentId.trim() !== "")
    ) return [video];
    const videoId = safeYoutubeVideoId(video.platformVideoId);
    const contentId = videoId ? contentByVideoId.get(videoId) : undefined;
    return [contentId ? { ...video, contentId } : video];
  });
};

const retentionAt = (
  retention: readonly unknown[],
  durationSeconds: number,
  elapsedSeconds: number,
): number | null => {
  if (
    durationSeconds <= 0 ||
    elapsedSeconds < 0 ||
    elapsedSeconds > durationSeconds ||
    retention.length === 0
  ) return null;
  const target = elapsedSeconds / durationSeconds;
  const points = retention.flatMap((entry) => {
    const point = record(entry);
    const elapsed = finiteNumber(point?.elapsedVideoTimeRatio);
    const ratio = finiteNumber(point?.audienceWatchRatio);
    return (
      elapsed === null ||
      ratio === null ||
      elapsed < 0 ||
      elapsed > 1 ||
      ratio < 0
    ) ? [] : [{ elapsed, ratio }];
  }).sort((left, right) => left.elapsed - right.elapsed);
  if (points.length === 0) return null;
  const exact = points.find((point) => point.elapsed === target);
  if (exact) return exact.ratio;
  const rightIndex = points.findIndex((point) => point.elapsed > target);
  // A point outside the measured interval is unknown. Returning the nearest
  // endpoint here would turn a partial curve into invented 3-second retention.
  if (rightIndex <= 0) return null;
  const left = points[rightIndex - 1];
  const right = points[rightIndex];
  if (!left || !right || right.elapsed === left.elapsed) return null;
  const fraction = (target - left.elapsed) / (right.elapsed - left.elapsed);
  return left.ratio + (right.ratio - left.ratio) * fraction;
};

const median = (values: readonly number[]): number | null => {
  if (values.length === 0) return null;
  const ordered = [...values].sort((left, right) => left - right);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2 === 0
    ? ((ordered[middle - 1] as number) + (ordered[middle] as number)) / 2
    : ordered[middle] as number;
};

const roundedMetric = (value: number, decimals = 6): number => {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
};

interface PhraseTimelineEntry {
  readonly contentId: string;
  readonly phrases: readonly Record<string, unknown>[];
}

const supportedPhraseTypes = new Set<ScriptPhraseType>([
  "hook",
  "question",
  "reveal",
  "reaction",
  "transition",
  "cta",
]);

const phraseTimelineEntries = (value: unknown): readonly PhraseTimelineEntry[] => {
  const root = record(value);
  const candidates = Array.isArray(value)
    ? value
    : Array.isArray(root?.timelines)
      ? root.timelines
      : Array.isArray(root?.items)
        ? root.items
        : Array.isArray(root?.videos)
          ? root.videos
          : [];
  return candidates.flatMap((candidate) => {
    const entry = record(candidate);
    const contentId = typeof entry?.contentId === "string" ? entry.contentId.trim() : "";
    const nestedTimeline = record(entry?.timeline);
    const phrases = Array.isArray(entry?.phrases)
      ? entry.phrases
      : Array.isArray(nestedTimeline?.phrases)
        ? nestedTimeline.phrases
        : [];
    if (!/^flaggenbande-[a-f0-9]{64}$/u.test(contentId) || phrases.length === 0) return [];
    return [{
      contentId,
      phrases: phrases.flatMap((phrase) => {
        const parsed = record(phrase);
        return parsed ? [parsed] : [];
      }),
    }];
  });
};

interface PhraseRetentionObservation {
  readonly formulationKey: string;
  readonly phraseType: ScriptPhraseType;
  readonly formulation: string;
  readonly contentId: string;
  readonly entryRetention: number;
  readonly exitRetention: number;
  readonly deltaPercentagePoints: number;
}

const phraseRetentionObservations = (
  linkedVideos: readonly Record<string, unknown>[],
  phraseTimelines: unknown,
): readonly PhraseRetentionObservation[] => {
  const videosByContentId = new Map(
    linkedVideos.flatMap((video) => {
      const contentId = typeof video.contentId === "string" ? video.contentId.trim() : "";
      const durationSeconds = finiteNumber(video.durationSeconds);
      const retention = Array.isArray(video.retention) ? video.retention : [];
      return (
        /^flaggenbande-[a-f0-9]{64}$/u.test(contentId) &&
        durationSeconds !== null &&
        durationSeconds > 0 &&
        retention.length > 0
      ) ? [[contentId, { durationSeconds, retention }] as const] : [];
    }),
  );
  return phraseTimelineEntries(phraseTimelines).flatMap((timeline) => {
    const video = videosByContentId.get(timeline.contentId);
    if (!video) return [];
    return timeline.phrases.flatMap((phrase) => {
      const formulationKey = typeof phrase.formulationKey === "string"
        ? phrase.formulationKey.trim()
        : "";
      const formulation = typeof phrase.text === "string" ? phrase.text.trim() : "";
      const phraseType = typeof phrase.type === "string" && supportedPhraseTypes.has(
          phrase.type as ScriptPhraseType,
        )
        ? phrase.type as ScriptPhraseType
        : null;
      const startSeconds = finiteNumber(phrase.startSeconds);
      const endSeconds = finiteNumber(phrase.endSeconds);
      if (
        formulationKey === "" ||
        formulation === "" ||
        phraseType === null ||
        startSeconds === null ||
        endSeconds === null ||
        startSeconds < 0 ||
        endSeconds <= startSeconds ||
        endSeconds > video.durationSeconds
      ) return [];
      const entryRetention = retentionAt(video.retention, video.durationSeconds, startSeconds);
      const exitRetention = retentionAt(video.retention, video.durationSeconds, endSeconds);
      if (entryRetention === null || exitRetention === null) return [];
      return [{
        formulationKey,
        phraseType,
        formulation,
        contentId: timeline.contentId,
        entryRetention,
        exitRetention,
        deltaPercentagePoints: (exitRetention - entryRetention) * 100,
      }];
    });
  });
};

const evaluatePhraseRetention = (
  observations: readonly PhraseRetentionObservation[],
): readonly ResearchPhraseEvaluation[] => {
  const grouped = new Map<string, PhraseRetentionObservation[]>();
  for (const observation of observations) {
    const existing = grouped.get(observation.formulationKey) ?? [];
    existing.push(observation);
    grouped.set(observation.formulationKey, existing);
  }
  return [...grouped.values()].flatMap((entries) => {
    const representative = entries[0];
    if (!representative) return [];
    const videoCount = new Set(entries.map((entry) => entry.contentId)).size;
    const medianEntryRetention = median(entries.map((entry) => entry.entryRetention));
    const medianExitRetention = median(entries.map((entry) => entry.exitRetention));
    const medianDeltaPercentagePoints = median(
      entries.map((entry) => entry.deltaPercentagePoints),
    );
    if (
      medianEntryRetention === null ||
      medianExitRetention === null ||
      medianDeltaPercentagePoints === null
    ) return [];
    return [{
      formulationKey: representative.formulationKey,
      phraseType: representative.phraseType,
      formulation: representative.formulation,
      sampleSize: entries.length,
      videoCount,
      medianEntryRetention: roundedMetric(medianEntryRetention),
      medianExitRetention: roundedMetric(medianExitRetention),
      medianDeltaPercentagePoints: roundedMetric(medianDeltaPercentagePoints),
      evidenceLevel: "measured" as const,
      confidence: videoCount >= 30 ? "high" as const : videoCount >= 10 ? "medium" as const : "low" as const,
      causalInference: false as const,
    }];
  }).sort((left, right) =>
    right.videoCount - left.videoCount ||
    right.sampleSize - left.sampleSize ||
    left.formulationKey.localeCompare(right.formulationKey)
  );
};

const retentionDataStatus = (
  linkedVideos: readonly Record<string, unknown>[],
  retentionVideoCount: number,
  aggregateVideoCount: number,
): RetentionDataStatus => {
  if (retentionVideoCount > 0) return "measured";
  if (aggregateVideoCount > 0) return "aggregate_only";
  if (linkedVideos.length > 0) return "pending";
  return "unavailable";
};

export const buildResearchRecommendationFeed = (
  dashboard: unknown,
  generatedAt: string,
  contentOperations: unknown = null,
  phraseTimelines: unknown = null,
): ResearchRecommendationFeed => {
  const root = record(dashboard);
  const social = record(root?.social);
  const rawVideos = Array.isArray(social?.videos) ? social.videos : [];
  const videos = linkYoutubeContentIds(rawVideos, contentOperations);
  const youtube = videos.filter((video) => video.platform === "youtube");
  const comparableYoutube = youtube.filter((video) => {
    const duration = finiteNumber(video.durationSeconds);
    const contentId = typeof video.contentId === "string" ? video.contentId : "";
    return (
      duration !== null &&
      duration >= 61 &&
      duration <= 70 &&
      /^flaggenbande-[a-f0-9]{64}$/u.test(contentId)
    );
  });
  const linked = comparableYoutube;
  const withAveragePercentage = comparableYoutube.filter((video) =>
    finiteNumber(record(video.metrics)?.averageViewPercentage) !== null
  );
  const retentionVideos = linked.flatMap((video) => {
    const duration = finiteNumber(video.durationSeconds);
    const retention = Array.isArray(video.retention) ? video.retention : [];
    const atThree = duration === null ? null : retentionAt(retention, duration, 3);
    return atThree === null ? [] : [{ atThree }];
  });
  const minimumComparableVideos = 5;
  const retentionCoverage = linked.length === 0 ? 0 : retentionVideos.length / linked.length;
  const ready = retentionVideos.length >= minimumComparableVideos && retentionCoverage >= 0.8;
  const retentionStatus = retentionDataStatus(
    linked,
    retentionVideos.length,
    withAveragePercentage.length,
  );
  const timelines = phraseTimelineEntries(phraseTimelines);
  const linkedContentIds = new Set(
    linked.flatMap((video) =>
      typeof video.contentId === "string" ? [video.contentId.trim()] : []
    ),
  );
  const linkedTimelineContentIds = new Set(
    timelines
      .map((timeline) => timeline.contentId)
      .filter((contentId) => linkedContentIds.has(contentId)),
  );
  const phraseObservations = phraseRetentionObservations(linked, timelines);
  const phraseEvaluations = evaluatePhraseRetention(phraseObservations);
  const phraseRetentionContentIds = new Set(
    phraseObservations.map((observation) => observation.contentId),
  );
  const measuredRecommendations: ResearchRecommendation[] = [];
  if (ready) {
    const threeSecondMedian = median(retentionVideos.map((video) => video.atThree));
    if (threeSecondMedian !== null && threeSecondMedian < 0.75) {
      measuredRecommendations.push({
        id: "first-reveal-delay-v1",
        title: "Erste Auflösung früher testen",
        action: "Die erste Frage und Auflösung verdichten; alle übrigen Parameter unverändert lassen.",
        primaryParameter: "first_reveal_delay_seconds",
        targetMetric: "retention_3s",
        evidenceLevel: "measured",
        confidence: retentionVideos.length >= 10 ? "medium" : "low",
        sampleSize: retentionVideos.length,
        sourceRun: "hourly-platform-analytics",
        autoApplicable: false,
      });
    }
  }
  const message = ready
    ? "Retention-Kurven reichen für vorsichtige, kontrollierte Hypothesen."
    : retentionStatus === "measured"
      ? "Echte Retention-Kurven liegen vor, aber die Vergleichsmenge ist noch zu klein."
      : retentionStatus === "aggregate_only"
        ? "Nur aggregierte Wiedergabewerte liegen vor; Kurven- und Formulierungsvergleiche warten."
        : retentionStatus === "pending"
          ? "Verknüpfte Videos sind vorhanden; der Retention-Abruf liefert noch keine Kurven."
          : "Keine verknüpften, vergleichbaren YouTube-Videos für die Retention-Auswertung.";
  return {
    schemaVersion: "1.1.0",
    generatedAt,
    dataReadiness: {
      status: ready ? "ready" : "insufficient",
      retentionStatus,
      platformVideoCount: videos.length,
      linkedYoutubeVideos: linked.length,
      retentionVideos: retentionVideos.length,
      averageViewPercentageVideos: withAveragePercentage.length,
      phraseTimelineVideos: linkedTimelineContentIds.size,
      phraseRetentionVideos: phraseRetentionContentIds.size,
      minimumComparableVideos,
      message,
    },
    recommendations: measuredRecommendations.slice(0, 5),
    phraseEvaluations,
  };
};
