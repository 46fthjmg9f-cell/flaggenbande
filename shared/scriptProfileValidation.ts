export type SupportedRoundCount = 5 | 7;

export type ScriptProfileIssueCode =
  | "SCRIPT_LENGTH_TOO_LOW"
  | "SCRIPT_LENGTH_TOO_HIGH"
  | "ROUND_COUNT"
  | "QUESTION_TEXT_MISSING"
  | "QUESTION_PROMPT_MISSING"
  | "FINAL_REACTION_MISSING"
  | "SPOKEN_WORDS_TOO_LOW"
  | "BRAND_MENTION_FORBIDDEN"
  | "DIRECT_PROMOTION"
  | "GERMAN_LANGUAGE_SIGNAL"
  | "DURATION_PLAUSIBILITY";

export interface ScriptProfileIssue {
  readonly code: ScriptProfileIssueCode;
  readonly roundIndex?: number;
  readonly actual?: number;
  readonly expected?: number;
  readonly minimum?: number;
  readonly maximum?: number;
}

export interface ScriptProfileValidation {
  readonly valid: boolean;
  readonly issues: readonly ScriptProfileIssueCode[];
  readonly details: readonly ScriptProfileIssue[];
  readonly spokenWordCount: number;
  readonly revealCount: number;
  readonly brandMentionCount: number;
  readonly germanSignalCount: number;
  readonly plausibleMinimumSeconds: number;
  readonly plausibleMaximumSeconds: number;
  readonly normalizedLength: number;
}

const revealMarker = /^\(auflösung\)$/iu;

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
  "junge", "letzte", "nicht", "schaffst", "welche", "welches", "welcher", "weisst",
  "weißt", "wird", "wissen", "läuft", "laeuft", "schwere", "schwerer",
]);

const spokenPromptPatterns = [
  /[?]/u,
  /\b(?:welche|welches|welcher|was|wie|wo|wer|wann|wessen)\b/iu,
  /\b(?:weißt|weisst|kennst|erkennst)\s+du\b/iu,
  /\bsag(?:\s+mal)?(?:\s+[\p{L}\p{N}]+){0,5}\s+an\b/iu,
  /\bsprich\s+frei\b/iu,
  /\b(?:deine|eure)\s+antwort\b/iu,
  /\bantwort(?:e|en|est)?\b/iu,
  /\b(?:tell\s+me|name\s+it|lock\s+(?:it\s+)?in)\b/iu,
] as const;

export const normalizeQuizScript = (script: string): string => script
  .normalize("NFC")
  .replace(/\r\n?/gu, "\n")
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => revealMarker.test(line) ? "(auflösung)" : line)
  .join("\n");

export const hasQuizPrompt = (segment: string): boolean =>
  spokenPromptPatterns.some((pattern) => pattern.test(segment));

export const validateScriptProfile = (
  scriptInput: string,
  roundCount: SupportedRoundCount,
  targetDurationSeconds: number,
): ScriptProfileValidation => {
  const script = normalizeQuizScript(scriptInput);
  const lines = script.split("\n");
  const markerIndexes = lines.flatMap((line, index) => line === "(auflösung)" ? [index] : []);
  const details: ScriptProfileIssue[] = [];
  const add = (issue: ScriptProfileIssue): void => {
    details.push(issue);
  };

  if (script.length < 80) {
    add({ code: "SCRIPT_LENGTH_TOO_LOW", actual: script.length, minimum: 80 });
  }
  if (script.length > 20_000) {
    add({ code: "SCRIPT_LENGTH_TOO_HIGH", actual: script.length, maximum: 20_000 });
  }

  if (markerIndexes.length !== roundCount) {
    add({ code: "ROUND_COUNT", actual: markerIndexes.length, expected: roundCount });
  }

  let segmentStart = 0;
  for (const [markerOffset, markerIndex] of markerIndexes.entries()) {
    const roundIndex = markerOffset + 1;
    if (markerIndex === 0 || lines[markerIndex - 1] === "(auflösung)") {
      add({ code: "QUESTION_TEXT_MISSING", roundIndex });
    }
    const segment = lines.slice(segmentStart, markerIndex).join(" ");
    if (!hasQuizPrompt(segment)) {
      add({ code: "QUESTION_PROMPT_MISSING", roundIndex });
    }
    segmentStart = markerIndex + 1;
  }

  if (markerIndexes.at(-1) === lines.length - 1) {
    add({ code: "FINAL_REACTION_MISSING" });
  }

  const spokenWordCount =
    script.replaceAll("(auflösung)", "").match(/[\p{L}\p{N}]+/gu)?.length ?? 0;
  const minimumWords = roundCount === 5 ? 90 : 70;
  if (spokenWordCount < minimumWords) {
    add({ code: "SPOKEN_WORDS_TOO_LOW", actual: spokenWordCount, minimum: minimumWords });
  }

  const brandMentionCount = script.match(/\bflaggenbande\b/giu)?.length ?? 0;
  if (brandMentionCount > 0) {
    add({ code: "BRAND_MENTION_FORBIDDEN", actual: brandMentionCount, expected: 0 });
  }
  if (directPromotionPatterns.some((pattern) => pattern.test(script))) {
    add({ code: "DIRECT_PROMOTION" });
  }

  const foundGermanSignals = new Set(
    (script.toLocaleLowerCase("de").match(/[\p{L}]+/gu) ?? [])
      .filter((token) => germanSignals.has(token)),
  );
  const germanSignalCount = foundGermanSignals.size;
  if (germanSignalCount < 2) {
    add({ code: "GERMAN_LANGUAGE_SIGNAL", actual: germanSignalCount, minimum: 2 });
  }

  const plausibleMinimumSeconds = spokenWordCount / 4 + roundCount * 3;
  const plausibleMaximumSeconds = spokenWordCount / 1.5 + roundCount * 7;
  if (
    !Number.isFinite(targetDurationSeconds) ||
    targetDurationSeconds < 61 ||
    targetDurationSeconds > 70 ||
    targetDurationSeconds < plausibleMinimumSeconds ||
    targetDurationSeconds > plausibleMaximumSeconds
  ) {
    add({
      code: "DURATION_PLAUSIBILITY",
      actual: targetDurationSeconds,
      minimum: plausibleMinimumSeconds,
      maximum: plausibleMaximumSeconds,
    });
  }

  return {
    valid: details.length === 0,
    issues: [...new Set(details.map((issue) => issue.code))],
    details,
    spokenWordCount,
    revealCount: markerIndexes.length,
    brandMentionCount,
    germanSignalCount,
    plausibleMinimumSeconds,
    plausibleMaximumSeconds,
    normalizedLength: script.length,
  };
};

export const scriptProfileIssueMessage = (issue: ScriptProfileIssue): string => {
  switch (issue.code) {
    case "SCRIPT_LENGTH_TOO_LOW":
      return "Das Skript ist noch zu kurz.";
    case "SCRIPT_LENGTH_TOO_HIGH":
      return "Das Skript überschreitet 20.000 Zeichen.";
    case "ROUND_COUNT":
      return `${String(issue.expected ?? "–")} Auflösungen benötigt; gefunden: ${String(issue.actual ?? "–")}.`;
    case "QUESTION_TEXT_MISSING":
      return `Vor Auflösung ${String(issue.roundIndex ?? "–")} fehlt gesprochener Fragetext.`;
    case "QUESTION_PROMPT_MISSING":
      return `Runde ${String(issue.roundIndex ?? "–")} braucht eine klare Frage oder Aufforderung.`;
    case "FINAL_REACTION_MISSING":
      return "Nach der letzten Auflösung fehlt der Abschluss.";
    case "SPOKEN_WORDS_TOO_LOW":
      return `Das Skript braucht mindestens ${String(issue.minimum ?? "–")} gesprochene Wörter.`;
    case "BRAND_MENTION_FORBIDDEN":
      return "Marken- und App-Nennungen sind im Video nicht erlaubt.";
    case "DIRECT_PROMOTION":
      return "Werbe-, Download- oder Kaufaufforderungen sind im Video nicht erlaubt.";
    case "GERMAN_LANGUAGE_SIGNAL":
      return "Das Skript wurde nicht sicher als deutschsprachiges Quiz erkannt.";
    case "DURATION_PLAUSIBILITY":
      return "Wortmenge, Ratefenster und Ziellänge passen noch nicht zusammen.";
  }
};
