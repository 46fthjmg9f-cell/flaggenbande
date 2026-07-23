export type SupportedRoundCount = 5 | 7;

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

export interface ResearchRecommendationFeed {
  readonly schemaVersion: "1.0.0";
  readonly generatedAt: string;
  readonly dataReadiness: {
    readonly status: "ready" | "insufficient";
    readonly platformVideoCount: number;
    readonly linkedYoutubeVideos: number;
    readonly retentionVideos: number;
    readonly averageViewPercentageVideos: number;
    readonly minimumComparableVideos: number;
    readonly message: string;
  };
  readonly recommendations: readonly ResearchRecommendation[];
}

export const SCRIPT_GENERATOR_VERSION = "creator-style-organic-v5";
export const DEFAULT_TARGET_DURATION: Readonly<Record<SupportedRoundCount, number>> = {
  5: 64,
  7: 69,
};

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

const directPromotionPatterns = [
  /https?:\/\//iu,
  /\bapps\.apple\.com\b/iu,
  /\b(?:app\s*store|play\s*store)\b/iu,
  /\b(?:download|herunterladen|runterladen)\b/iu,
  /\blad(?:e)?\b[^\n.!?]{0,100}\brunter\b/iu,
  /\b(?:kauf|kaufe|abonnier|bestell)(?:e|en|st)?\b/iu,
] as const;

const germanSignals = new Set([
  "aber", "alle", "das", "der", "die", "du", "flagge", "flaggen", "hier", "jetzt",
  "junge", "letzte", "nicht", "schaffst", "welche", "welches", "welcher", "weißt",
  "wird", "wissen", "läuft", "schwere", "schwerer",
]);

const normalizeScript = (script: string): string => script
  .normalize("NFC")
  .replace(/\r\n?/gu, "\n")
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => /^\(auflösung\)$/iu.test(line) ? "(auflösung)" : line)
  .join("\n");

export interface ScriptProfileValidation {
  readonly valid: boolean;
  readonly issues: readonly string[];
  readonly spokenWordCount: number;
}

export const validateScriptProfile = (
  scriptInput: string,
  roundCount: SupportedRoundCount,
  targetDurationSeconds: number,
): ScriptProfileValidation => {
  const script = normalizeScript(scriptInput);
  const lines = script.split("\n");
  const markerIndexes = lines.flatMap((line, index) => line === "(auflösung)" ? [index] : []);
  const issues: string[] = [];
  if (markerIndexes.length !== roundCount) issues.push("ROUND_COUNT");
  let segmentStart = 0;
  for (const markerIndex of markerIndexes) {
    if (markerIndex === 0 || lines[markerIndex - 1] === "(auflösung)") issues.push("QUESTION_TEXT_MISSING");
    if (!lines.slice(segmentStart, markerIndex).some((line) => line.includes("?"))) {
      issues.push("QUESTION_MARK_MISSING");
    }
    segmentStart = markerIndex + 1;
  }
  if (markerIndexes.at(-1) === lines.length - 1) issues.push("FINAL_REACTION_MISSING");
  const words = script.replaceAll("(auflösung)", "").match(/[\p{L}\p{N}]+/gu)?.length ?? 0;
  const minimumWords = roundCount === 5 ? 90 : 70;
  if (words < minimumWords) issues.push("SPOKEN_WORDS_TOO_LOW");
  const brandMentions = script.match(/\bflaggenbande\b/giu)?.length ?? 0;
  if (brandMentions > 0) issues.push("BRAND_MENTION_FORBIDDEN");
  if (directPromotionPatterns.some((pattern) => pattern.test(script))) issues.push("DIRECT_PROMOTION");
  const foundGermanSignals = new Set(
    (script.toLocaleLowerCase("de").match(/[\p{L}]+/gu) ?? []).filter((token) => germanSignals.has(token)),
  );
  if (foundGermanSignals.size < 2) issues.push("GERMAN_LANGUAGE_SIGNAL");
  const plausibleMinimumSeconds = words / 4 + roundCount * 3;
  const plausibleMaximumSeconds = words / 1.5 + roundCount * 7;
  if (
    !Number.isFinite(targetDurationSeconds) ||
    targetDurationSeconds < 61 ||
    targetDurationSeconds > 70 ||
    targetDurationSeconds < plausibleMinimumSeconds ||
    targetDurationSeconds > plausibleMaximumSeconds
  ) issues.push("DURATION_PLAUSIBILITY");
  return { valid: issues.length === 0, issues: [...new Set(issues)], spokenWordCount: words };
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
    return candidates.length > 0 ? choose(candidates, seed, index + 1) : segment;
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

export const generateScriptDraft = (
  request: ScriptDraftRequest,
  styleExamples: readonly string[],
): ScriptDraftResult => {
  const learnedSignals = learnedStyleSignals(styleExamples);
  const seed = hashSeed(`${request.requestSeed}:${request.roundCount}:${request.recommendationId ?? "baseline"}`);
  const fallback = request.roundCount === 5
    ? generateFiveRoundScript(seed, learnedSignals, request.recommendationId)
    : generateSevenRoundScript(seed, learnedSignals, request.recommendationId);
  const remixed = remixApprovedStyle(styleExamples, fallback, request, seed);
  const script = addCreatorStyleVariation(remixed ?? fallback, request, seed);
  return { script, learnedSignals, generatorVersion: SCRIPT_GENERATOR_VERSION };
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
  if (durationSeconds <= 0 || retention.length === 0) return null;
  const target = Math.min(1, elapsedSeconds / durationSeconds);
  const points = retention.flatMap((entry) => {
    const point = record(entry);
    const elapsed = finiteNumber(point?.elapsedVideoTimeRatio);
    const ratio = finiteNumber(point?.audienceWatchRatio);
    return elapsed === null || ratio === null ? [] : [{ elapsed, ratio }];
  });
  if (points.length === 0) return null;
  return points.reduce((closest, point) =>
    Math.abs(point.elapsed - target) < Math.abs(closest.elapsed - target) ? point : closest
  ).ratio;
};

const median = (values: readonly number[]): number | null => {
  if (values.length === 0) return null;
  const ordered = [...values].sort((left, right) => left - right);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2 === 0
    ? ((ordered[middle - 1] as number) + (ordered[middle] as number)) / 2
    : ordered[middle] as number;
};

export const buildResearchRecommendationFeed = (
  dashboard: unknown,
  generatedAt: string,
  contentOperations: unknown = null,
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
  return {
    schemaVersion: "1.0.0",
    generatedAt,
    dataReadiness: {
      status: ready ? "ready" : "insufficient",
      platformVideoCount: videos.length,
      linkedYoutubeVideos: linked.length,
      retentionVideos: retentionVideos.length,
      averageViewPercentageVideos: withAveragePercentage.length,
      minimumComparableVideos,
      message: ready
        ? "Retention-Daten reichen für vorsichtige, kontrollierte Hypothesen."
        : "Retention noch nicht belastbar; Research-Vorschläge bleiben gekennzeichnete Hypothesen.",
    },
    recommendations: measuredRecommendations.slice(0, 5),
  };
};
