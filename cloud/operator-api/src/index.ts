import {
  isProductionRoundCount,
  type ProductionRoundCount,
} from "../../../shared/scriptProfileValidation.ts";
import {
  buildResearchRecommendationFeed,
  DEFAULT_TARGET_DURATION,
  extractScriptPhrases,
  generateScriptDraft,
  isSupportedRoundCount,
  validateScriptProfile,
  type ScriptPhraseTimeline,
  type ScriptProfileValidation,
  type SupportedRoundCount,
} from "./scriptDrafts.ts";

interface D1Result {
  readonly success?: boolean;
  readonly meta?: { readonly changes?: number };
}

interface D1PreparedStatement {
  bind(...values: readonly unknown[]): D1PreparedStatement;
  first<T>(): Promise<T | null>;
  all<T>(): Promise<{ readonly results?: readonly T[] }>;
  run(): Promise<D1Result>;
}

interface D1Database {
  prepare(query: string): D1PreparedStatement;
  batch(statements: readonly D1PreparedStatement[]): Promise<readonly D1Result[]>;
}

interface R2ObjectBody {
  readonly body: ReadableStream;
  readonly size: number;
  readonly etag: string;
  readonly httpMetadata?: { readonly contentType?: string };
}

interface R2Bucket {
  put(
    key: string,
    value: ReadableStream,
    options?: {
      readonly httpMetadata?: { readonly contentType?: string };
      readonly customMetadata?: Readonly<Record<string, string>>;
      readonly sha256?: ArrayBuffer;
    },
  ): Promise<unknown>;
  get(
    key: string,
    options?: { readonly range?: { readonly offset: number; readonly length: number } },
  ): Promise<R2ObjectBody | null>;
  delete(key: string): Promise<void>;
}

interface Env {
  readonly DB: D1Database;
  readonly PREVIEWS: R2Bucket;
  readonly ASSETS?: Fetcher;
  readonly DASHBOARD_ORIGINS?: string;
  readonly DASHBOARD_DATA_BASE_URL?: string;
  readonly OPERATOR_API_TOKEN?: string;
  readonly OPERATOR_API_TOKEN_SECONDARY?: string;
  readonly OPERATOR_RUNNER_TOKEN?: string;
  readonly OPERATOR_RUNNER_TOKEN_SECONDARY?: string;
  readonly OPERATOR_RELEASE_TOKEN?: string;
  readonly OPERATOR_RELEASE_TOKEN_SECONDARY?: string;
  readonly RELEASE_PLATFORMS?: string;
  readonly TEAM_DOMAIN?: string;
  readonly POLICY_AUD?: string;
}

type RunStatus = "queued" | "claimed" | "running" | "waiting" | "completed" | "failed";
type ReviewRunStatus =
  | "awaiting_script_approval"
  | RunStatus
  | "awaiting_video_approval"
  | "release_queued"
  | "published";
type CalendarPlatform = "youtube" | "instagram" | "facebook" | "tiktok";
type CalendarStatus = "scheduled" | "publishing" | "published" | "failed" | "missing";

interface RunRow {
  readonly run_id: string;
  readonly input_sha256: string;
  readonly client_request_id: string;
  readonly script: string;
  readonly target_duration_seconds: number;
  readonly status: RunStatus;
  readonly progress: number;
  readonly current_step: string | null;
  readonly message: string | null;
  readonly error_code: string | null;
  readonly provider_run_id: string | null;
  readonly lease_owner: string | null;
  readonly lease_token_sha256: string | null;
  readonly lease_expires_at: string | null;
  readonly next_attempt_at: string;
  readonly attempt_count: number;
  readonly created_at: string;
  readonly updated_at: string;
  readonly completed_at: string | null;
}

interface ScriptDraftRow {
  readonly draft_id: string;
  readonly client_request_id: string;
  readonly script: string;
  readonly script_sha256: string;
  readonly round_count: SupportedRoundCount;
  readonly suggested_duration_seconds: number;
  readonly generator_version: string;
  readonly style_example_count: number;
  readonly recommendation_id: string | null;
  readonly learned_signals_json: string;
  readonly created_at: string;
}

interface ScriptOriginRow {
  readonly run_id: string;
  readonly draft_id: string | null;
  readonly origin: "manual" | "auto_unedited" | "auto_edited";
  readonly reveal_count: SupportedRoundCount;
  readonly submitted_script_sha256: string;
  readonly draft_script_sha256: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface StyleExampleRow {
  readonly script: string;
}

interface RunScriptManifestRow {
  readonly run_id: string;
  readonly script_sha256: string;
  readonly schema_version: "1.0.0";
  readonly round_count: SupportedRoundCount;
  readonly timing_source: "script_only" | "word_timestamps";
  readonly created_at: string;
  readonly updated_at: string;
}

interface CalendarRow {
  readonly entry_id: string;
  readonly content_id: string;
  readonly title: string;
  readonly scheduled_at: string;
  readonly platforms_json: string;
  readonly run_id?: string | null;
  readonly release_label?: string | null;
  readonly video_approved?: number | null;
  readonly final_release_approved?: number | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface ReviewRow {
  readonly run_id: string;
  readonly release_label: string;
  readonly script_sha256: string;
  readonly script_revision: number;
  readonly script_approval_status: "pending" | "approved";
  readonly script_approval_idempotency_key: string | null;
  readonly script_approved_at: string | null;
  readonly preview_object_key: string | null;
  readonly preview_sha256: string | null;
  readonly preview_size_bytes: number | null;
  readonly preview_content_type: string | null;
  readonly preview_uploaded_at: string | null;
  readonly quality_gate_passed: number;
  readonly monetization_gate_passed: number;
  readonly video_revision: number;
  readonly video_approval_status: "not_ready" | "pending" | "approved";
  readonly video_approval_idempotency_key: string | null;
  readonly video_approved_at: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface ReleaseRequestRow {
  readonly request_id: string;
  readonly run_id: string;
  readonly preview_sha256: string;
  readonly video_revision: number;
  readonly idempotency_key: string;
  readonly status: "queued" | "claimed" | "completed" | "failed";
  readonly created_at: string;
  readonly updated_at: string;
}

interface ReleaseExecutionRow {
  readonly request_id: string;
  readonly platforms_json: string;
  readonly platform_results_json: string;
  readonly runner_id: string | null;
  readonly lease_token_sha256: string | null;
  readonly lease_expires_at: string | null;
  readonly next_attempt_at: string;
  readonly attempt_count: number;
  readonly error_code: string | null;
  readonly completed_at: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface PlatformState {
  readonly status: CalendarStatus;
  readonly publicUrl?: string;
}

type CalendarPlatforms = Readonly<Record<CalendarPlatform, PlatformState>>;

const RUN_STATUSES: readonly RunStatus[] = ["queued", "claimed", "running", "waiting", "completed", "failed"];
const RUNNER_STATUSES: readonly RunStatus[] = ["running", "waiting", "completed", "failed"];
const CALENDAR_PLATFORMS: readonly CalendarPlatform[] = ["youtube", "instagram", "facebook", "tiktok"];
const CALENDAR_STATUSES: readonly CalendarStatus[] = ["scheduled", "publishing", "published", "failed", "missing"];
const DEFAULT_RELEASE_PLATFORMS: readonly CalendarPlatform[] = ["youtube", "instagram", "facebook"];
const MAX_REQUEST_BYTES = 64 * 1024;
const MIN_LEASE_SECONDS = 30;
const MAX_LEASE_SECONDS = 300;
const WAITING_RECHECK_SECONDS = 30;
const MAX_PREVIEW_BYTES = 512 * 1024 * 1024;
const ACCESS_TOKEN_MAX_BYTES = 16 * 1024;
const ACCESS_JWKS_TTL_MS = 60 * 60 * 1_000;
const MAX_DASHBOARD_DATA_BYTES = 2 * 1024 * 1024;
const DASHBOARD_DATA_FILES = new Set(["dashboard.json", "content-operations.json"]);
const DASHBOARD_DATA_SCHEMA_VERSIONS: Readonly<Record<string, number>> = {
  "dashboard.json": 3,
  "content-operations.json": 1,
};

const configuredReleasePlatforms = (env: Env): readonly CalendarPlatform[] => {
  const raw = env.RELEASE_PLATFORMS?.trim();
  if (!raw) return DEFAULT_RELEASE_PLATFORMS;
  const values = raw.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  if (
    values.length === 0 || values.some((value) => !CALENDAR_PLATFORMS.includes(value as CalendarPlatform))
  ) throw new Error("INVALID_RELEASE_PLATFORMS");
  return [...new Set(values)] as readonly CalendarPlatform[];
};

const initialReleasePlatformStates = (
  selected: readonly CalendarPlatform[],
): CalendarPlatforms => Object.fromEntries(CALENDAR_PLATFORMS.map((platform) => [
  platform,
  { status: selected.includes(platform) ? "scheduled" : "missing" },
])) as CalendarPlatforms;

const now = (): string => new Date().toISOString();

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const exactKeys = (value: Record<string, unknown>, allowed: readonly string[]): boolean => {
  const allowedSet = new Set(allowed);
  return Object.keys(value).every((key) => allowedSet.has(key));
};

const safeText = (value: unknown, maxLength: number): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= maxLength ? trimmed : null;
};

const safeMessage = (value: unknown): string | null => {
  const message = safeText(value, 500);
  if (!message) return null;
  return message
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/giu, "Bearer [redacted]")
    .replace(/[A-Za-z0-9_-]{32,}/gu, "[redacted]");
};

const safeErrorCode = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  const text = safeText(value, 80)?.toUpperCase();
  return text && /^[A-Z0-9_:-]+$/u.test(text) ? text : "LOCAL_PRODUCTION_FAILED";
};

const sha256 = async (value: string): Promise<string> => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
};

const hexToArrayBuffer = (value: string): ArrayBuffer => {
  if (!/^[a-f0-9]{64}$/u.test(value)) throw new Error("INVALID_PREVIEW");
  const bytes = Uint8Array.from(value.match(/.{2}/gu) ?? [], (part) => Number.parseInt(part, 16));
  return bytes.buffer;
};

const secureEqual = async (left: string, right: string): Promise<boolean> => {
  const [leftHash, rightHash] = await Promise.all([sha256(left), sha256(right)]);
  let difference = leftHash.length ^ rightHash.length;
  for (let index = 0; index < Math.max(leftHash.length, rightHash.length); index += 1) {
    difference |= (leftHash.charCodeAt(index) || 0) ^ (rightHash.charCodeAt(index) || 0);
  }
  return difference === 0;
};

const bearer = (request: Request): string | null => {
  const authorization = request.headers.get("authorization") ?? "";
  return authorization.startsWith("Bearer ") ? authorization.slice(7) : null;
};

const hasBearer = async (request: Request, tokens: readonly (string | undefined)[]): Promise<boolean> => {
  const candidate = bearer(request);
  if (!candidate || candidate.length > 512) return false;
  for (const token of tokens) {
    if (token && await secureEqual(candidate, token)) return true;
  }
  return false;
};

interface AccessClaims {
  readonly aud?: string | readonly string[];
  readonly exp?: number;
  readonly nbf?: number;
  readonly iss?: string;
}

interface AccessJwk {
  readonly kid?: string;
  readonly kty?: string;
  readonly alg?: string;
  readonly use?: string;
  readonly n?: string;
  readonly e?: string;
}

interface AccessJwks {
  readonly keys?: readonly AccessJwk[];
}

const accessJwksCache = new Map<string, {
  readonly expiresAt: number;
  readonly keys: readonly AccessJwk[];
}>();

const accessIssuer = (teamDomain: string): string | null => {
  try {
    const withProtocol = /^https:\/\//iu.test(teamDomain) ? teamDomain : `https://${teamDomain}`;
    const parsed = new URL(withProtocol);
    if (
      parsed.protocol !== "https:" || parsed.username || parsed.password ||
      (parsed.pathname !== "/" && parsed.pathname !== "") || parsed.search || parsed.hash
    ) return null;
    return parsed.origin;
  } catch {
    return null;
  }
};

const decodeBase64Url = (value: string): Uint8Array => {
  if (!/^[A-Za-z0-9_-]+$/u.test(value)) throw new Error("INVALID_ACCESS_JWT");
  const padded = `${value.replace(/-/gu, "+").replace(/_/gu, "/")}${"=".repeat((4 - value.length % 4) % 4)}`;
  const decoded = atob(padded);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
};

const parseJwtPart = (value: string): Record<string, unknown> => {
  const parsed = JSON.parse(new TextDecoder().decode(decodeBase64Url(value))) as unknown;
  if (!isRecord(parsed)) throw new Error("INVALID_ACCESS_JWT");
  return parsed;
};

const accessKeys = async (issuer: string): Promise<readonly AccessJwk[]> => {
  const cached = accessJwksCache.get(issuer);
  if (cached && cached.expiresAt > Date.now()) return cached.keys;
  const response = await fetch(`${issuer}/cdn-cgi/access/certs`, {
    headers: { Accept: "application/json" },
    cf: { cacheTtl: 3600, cacheEverything: true },
  } as RequestInit);
  if (!response.ok) throw new Error("ACCESS_JWKS_UNAVAILABLE");
  const value = await response.json() as AccessJwks;
  const keys = value.keys?.filter((key) =>
    key.kty === "RSA" && key.alg === "RS256" && typeof key.kid === "string" &&
    typeof key.n === "string" && typeof key.e === "string"
  ) ?? [];
  if (keys.length === 0) throw new Error("ACCESS_JWKS_UNAVAILABLE");
  accessJwksCache.set(issuer, { keys, expiresAt: Date.now() + ACCESS_JWKS_TTL_MS });
  return keys;
};

const hasCloudflareAccessJwt = async (request: Request, env: Env): Promise<boolean> => {
  const assertion = request.headers.get("cf-access-jwt-assertion");
  if (!assertion) return false;
  if (!env.TEAM_DOMAIN || !env.POLICY_AUD || assertion.length > ACCESS_TOKEN_MAX_BYTES) return false;
  const issuer = accessIssuer(env.TEAM_DOMAIN);
  if (!issuer) return false;
  try {
    const parts = assertion.split(".");
    if (parts.length !== 3) return false;
    const header = parseJwtPart(parts[0]);
    const claims = parseJwtPart(parts[1]) as AccessClaims;
    if (header.alg !== "RS256" || typeof header.kid !== "string") return false;
    const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    const seconds = Math.floor(Date.now() / 1_000);
    if (
      claims.iss !== issuer || !audience.includes(env.POLICY_AUD) ||
      typeof claims.exp !== "number" || claims.exp <= seconds ||
      (typeof claims.nbf === "number" && claims.nbf > seconds + 30)
    ) return false;
    const jwk = (await accessKeys(issuer)).find((candidate) => candidate.kid === header.kid);
    if (!jwk) return false;
    const key = await crypto.subtle.importKey(
      "jwk",
      { ...jwk, ext: true } as JsonWebKey,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    return crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      decodeBase64Url(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    return false;
  }
};

const isLocalOrigin = (url: URL): boolean =>
  url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);

const configuredOrigins = (env: Env): readonly string[] => {
  const values = env.DASHBOARD_ORIGINS?.split(",").map((entry) => entry.trim()).filter(Boolean) ?? [];
  const origins = values.map((entry) => {
    const parsed = new URL(entry);
    if ((parsed.protocol !== "https:" && !isLocalOrigin(parsed)) || parsed.pathname !== "/" || parsed.search || parsed.hash) {
      throw new Error("INVALID_DASHBOARD_ORIGIN");
    }
    return parsed.origin;
  });
  return [...new Set(origins)];
};

const allowedRequestOrigin = (request: Request, env: Env): string | null => {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  if (origin === new URL(request.url).origin) return origin;
  return configuredOrigins(env).includes(origin) ? origin : "";
};

const responseHeaders = (origin: string | null, contentType = "application/json; charset=utf-8"): Headers => {
  const headers = new Headers({
    "content-type": contentType,
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  if (origin) {
    headers.set("access-control-allow-origin", origin);
    headers.set("access-control-allow-credentials", "true");
    headers.set("vary", "Origin");
  }
  return headers;
};

const json = (value: unknown, status = 200, origin: string | null = null): Response =>
  new Response(`${JSON.stringify(value)}\n`, { status, headers: responseHeaders(origin) });

const errorResponse = (code: string, status: number, origin: string | null): Response =>
  json({ error: code }, status, origin);

const readJson = async (request: Request): Promise<unknown> => {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") throw new Error("CONTENT_TYPE_JSON_REQUIRED");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_REQUEST_BYTES) throw new Error("REQUEST_BODY_TOO_LARGE");
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new Error("INVALID_JSON");
  }
};

const normalizeScript = (script: string): string => script
  .normalize("NFC")
  .replace(/\r\n?/gu, "\n")
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => /^\(auflösung\)$/iu.test(line) ? "(auflösung)" : line)
  .join("\n");

const berlinDay = (timestamp: string): { readonly dayKey: string; readonly display: string } => {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(timestamp));
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    dayKey: `${value.year}-${value.month}-${value.day}`,
    display: `${value.day}${value.month}`,
  };
};

interface NewRunInput {
  readonly script: string;
  readonly targetDurationSeconds: number;
  readonly roundCount: ProductionRoundCount;
  readonly draftId?: string;
  readonly clientRequestId?: string;
}

class InvalidVideoRunInputError extends Error {
  readonly validation?: ScriptProfileValidation;

  constructor(validation?: ScriptProfileValidation) {
    super("INVALID_VIDEO_RUN_INPUT");
    this.name = "InvalidVideoRunInputError";
    this.validation = validation;
  }
}

const parseNewRun = (value: unknown): NewRunInput => {
  if (!isRecord(value) || !exactKeys(value, [
    "script", "targetDurationSeconds", "roundCount", "draftId", "clientRequestId",
  ])) {
    throw new InvalidVideoRunInputError();
  }
  const script = typeof value.script === "string" ? normalizeScript(value.script) : "";
  const target = typeof value.targetDurationSeconds === "number"
    ? Number(value.targetDurationSeconds.toFixed(3))
    : Number.NaN;
  const clientRequestId = value.clientRequestId === undefined ? undefined : safeText(value.clientRequestId, 128);
  const draftId = value.draftId === undefined ? undefined : safeText(value.draftId, 80);
  const revealCount = script.split("\n").filter((line) => line === "(auflösung)").length;
  const roundCount = value.roundCount === undefined ? revealCount : Number(value.roundCount);
  if (isSupportedRoundCount(roundCount) && !isProductionRoundCount(roundCount)) {
    throw new Error("UNSUPPORTED_PRODUCTION_ROUND_COUNT");
  }
  if (
    typeof value.script !== "string" ||
    !isProductionRoundCount(roundCount) || revealCount !== roundCount ||
    !Number.isFinite(target) || target < 61 || target > 70 ||
    (value.draftId !== undefined && (!draftId || !/^draft-[a-f0-9]{24}$/u.test(draftId))) ||
    (value.clientRequestId !== undefined && (!clientRequestId || !/^[A-Za-z0-9._:-]{8,128}$/u.test(clientRequestId)))
  ) throw new InvalidVideoRunInputError();
  const validation = validateScriptProfile(script, roundCount, target);
  if (!validation.valid) {
    throw new InvalidVideoRunInputError(validation);
  }
  return {
    script,
    targetDurationSeconds: target,
    roundCount,
    ...(draftId ? { draftId } : {}),
    ...(clientRequestId ? { clientRequestId } : {}),
  };
};

interface NewDraftInput {
  readonly roundCount: SupportedRoundCount;
  readonly targetDurationSeconds: number;
  readonly recommendationId: string | null;
  readonly clientRequestId: string;
}

const RESEARCH_RECOMMENDATION_IDS = new Set([
  "difficulty-ladder-visibility-v1",
  "first-reveal-delay-v1",
]);

const parseNewDraft = (value: unknown): NewDraftInput => {
  if (!isRecord(value) || !exactKeys(value, [
    "roundCount", "targetDurationSeconds", "recommendationId", "clientRequestId",
  ])) throw new Error("INVALID_SCRIPT_DRAFT_INPUT");
  const roundCount = Number(value.roundCount);
  const defaultTarget = isSupportedRoundCount(roundCount)
    ? DEFAULT_TARGET_DURATION[roundCount]
    : Number.NaN;
  const target = value.targetDurationSeconds === undefined
    ? defaultTarget
    : Number(value.targetDurationSeconds);
  const recommendationId = value.recommendationId === null || value.recommendationId === undefined
    ? null
    : safeText(value.recommendationId, 80);
  const clientRequestId = safeText(value.clientRequestId, 128);
  if (
    !isSupportedRoundCount(roundCount) ||
    !Number.isFinite(target) || target < 61 || target > 70 ||
    !clientRequestId || !/^[A-Za-z0-9._:-]{8,128}$/u.test(clientRequestId) ||
    (recommendationId !== null && !RESEARCH_RECOMMENDATION_IDS.has(recommendationId))
  ) throw new Error("INVALID_SCRIPT_DRAFT_INPUT");
  return {
    roundCount,
    targetDurationSeconds: Number(target.toFixed(3)),
    recommendationId,
    clientRequestId,
  };
};

const draftById = (env: Env, draftId: string): Promise<ScriptDraftRow | null> =>
  env.DB.prepare("SELECT * FROM operator_script_drafts_v2 WHERE draft_id = ?")
    .bind(draftId).first<ScriptDraftRow>();

const draftProjection = (row: ScriptDraftRow): Record<string, unknown> => {
  let learnedSignals: readonly string[] = [];
  try {
    const parsed = JSON.parse(row.learned_signals_json) as unknown;
    learnedSignals = Array.isArray(parsed)
      ? parsed.filter((value): value is string => typeof value === "string").slice(0, 12)
      : [];
  } catch {
    learnedSignals = [];
  }
  return {
    draftId: row.draft_id,
    script: row.script,
    scriptSha256: row.script_sha256,
    roundCount: row.round_count,
    suggestedDurationSeconds: row.suggested_duration_seconds,
    generatorVersion: row.generator_version,
    styleExampleCount: row.style_example_count,
    recommendationId: row.recommendation_id,
    learnedSignals,
    phrases: extractScriptPhrases(row.script, row.round_count),
    createdAt: row.created_at,
  };
};

const scriptStructureStatements = (
  env: Env,
  scriptSha256: string,
  sourceDraftId: string | null,
  timeline: ScriptPhraseTimeline,
  timestamp: string,
): readonly D1PreparedStatement[] => [
  env.DB.prepare(`INSERT INTO operator_script_structures
    (script_sha256, source_draft_id, schema_version, round_count, structure_json,
     created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(script_sha256) DO UPDATE SET
      source_draft_id = COALESCE(operator_script_structures.source_draft_id, excluded.source_draft_id),
      structure_json = excluded.structure_json,
      updated_at = excluded.updated_at`).bind(
    scriptSha256,
    sourceDraftId,
    timeline.schemaVersion,
    timeline.roundCount,
    JSON.stringify(timeline),
    timestamp,
    timestamp,
  ),
  ...timeline.phrases.map((phrase) => env.DB.prepare(`INSERT INTO operator_script_phrases
    (script_sha256, phrase_id, formulation_key, phrase_type, position_index,
     round_number, text, start_seconds, end_seconds, solution_country,
     solution_country_code, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(script_sha256, phrase_id) DO UPDATE SET
      formulation_key = excluded.formulation_key,
      phrase_type = excluded.phrase_type,
      position_index = excluded.position_index,
      round_number = excluded.round_number,
      text = excluded.text,
      updated_at = excluded.updated_at`).bind(
    scriptSha256,
    phrase.phraseId,
    phrase.formulationKey,
    phrase.type,
    phrase.position,
    phrase.round,
    phrase.text,
    phrase.startSeconds,
    phrase.endSeconds,
    phrase.solutionCountry,
    phrase.solutionCountryCode,
    timestamp,
    timestamp,
  )),
  ...timeline.rounds.map((round) => env.DB.prepare(`INSERT INTO operator_script_rounds
    (script_sha256, round_number, question_phrase_id, reveal_phrase_id,
     solution_country, solution_country_code, flag_shown_at_seconds,
     reveal_at_seconds, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(script_sha256, round_number) DO UPDATE SET
      question_phrase_id = excluded.question_phrase_id,
      reveal_phrase_id = excluded.reveal_phrase_id,
      updated_at = excluded.updated_at`).bind(
    scriptSha256,
    round.round,
    round.questionPhraseId,
    round.revealPhraseId,
    round.solutionCountry,
    round.solutionCountryCode,
    round.flagShownAtSeconds,
    round.revealAtSeconds,
    timestamp,
    timestamp,
  )),
];

const runScriptManifestStatements = (
  env: Env,
  runId: string,
  scriptSha256: string,
  timeline: ScriptPhraseTimeline,
  timestamp: string,
): readonly D1PreparedStatement[] => [
  env.DB.prepare(`INSERT INTO operator_run_script_manifests
    (run_id, script_sha256, schema_version, round_count, timing_source,
     created_at, updated_at)
    VALUES (?, ?, ?, ?, 'script_only', ?, ?)
    ON CONFLICT(run_id) DO UPDATE SET
      script_sha256 = excluded.script_sha256,
      schema_version = excluded.schema_version,
      round_count = excluded.round_count,
      updated_at = excluded.updated_at`).bind(
    runId,
    scriptSha256,
    timeline.schemaVersion,
    timeline.roundCount,
    timestamp,
    timestamp,
  ),
  ...timeline.phrases.map((phrase) => env.DB.prepare(`INSERT INTO operator_run_script_phrases
    (run_id, script_sha256, phrase_id, start_seconds, end_seconds,
     solution_country, solution_country_code, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(run_id, phrase_id) DO UPDATE SET
      script_sha256 = excluded.script_sha256,
      updated_at = excluded.updated_at`).bind(
    runId,
    scriptSha256,
    phrase.phraseId,
    phrase.startSeconds,
    phrase.endSeconds,
    phrase.solutionCountry,
    phrase.solutionCountryCode,
    timestamp,
    timestamp,
  )),
  ...timeline.rounds.map((round) => env.DB.prepare(`INSERT INTO operator_run_script_rounds
    (run_id, script_sha256, round_number, solution_country,
     solution_country_code, flag_shown_at_seconds, reveal_at_seconds,
     created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(run_id, round_number) DO UPDATE SET
      script_sha256 = excluded.script_sha256,
      updated_at = excluded.updated_at`).bind(
    runId,
    scriptSha256,
    round.round,
    round.solutionCountry,
    round.solutionCountryCode,
    round.flagShownAtSeconds,
    round.revealAtSeconds,
    timestamp,
    timestamp,
  )),
];

const createScriptDraft = async (
  request: Request,
  env: Env,
  origin: string | null,
): Promise<Response> => {
  const input = parseNewDraft(await readJson(request));
  const existingByRequest = await env.DB.prepare(
    "SELECT * FROM operator_script_drafts_v2 WHERE client_request_id = ?",
  ).bind(input.clientRequestId).first<ScriptDraftRow>();
  if (existingByRequest) {
    const timestamp = now();
    await env.DB.batch(scriptStructureStatements(
      env,
      existingByRequest.script_sha256,
      existingByRequest.draft_id,
      extractScriptPhrases(existingByRequest.script, existingByRequest.round_count),
      timestamp,
    ));
    return json(draftProjection(existingByRequest), 200, origin);
  }

  const examples = await env.DB.prepare(`SELECT script FROM operator_script_style_examples_v2
    WHERE reveal_count = ? AND instr(lower(script), 'flaggenbande') = 0
    ORDER BY CASE trust_level WHEN 'high_confidence' THEN 0 ELSE 1 END, updated_at DESC
    LIMIT 20`).bind(input.roundCount).all<StyleExampleRow>();
  const styleScripts = (examples.results ?? []).map((example) => example.script);
  const priorHashes = await env.DB.prepare(`SELECT script_sha256
    FROM operator_script_drafts_v2
    WHERE round_count = ?
    UNION
    SELECT script_sha256
    FROM operator_script_style_examples_v2
    WHERE reveal_count = ?`).bind(input.roundCount, input.roundCount)
    .all<{ readonly script_sha256: string }>();
  const seenHashes = new Set(
    (priorHashes.results ?? []).map((row) => row.script_sha256),
  );
  let generated: ReturnType<typeof generateScriptDraft> | null = null;
  let script = "";
  let scriptSha256 = "";
  for (let attempt = 0; attempt < 16; attempt += 1) {
    const candidate = generateScriptDraft({
      roundCount: input.roundCount,
      targetDurationSeconds: input.targetDurationSeconds,
      recommendationId: input.recommendationId,
      requestSeed: `${input.clientRequestId}:${String(attempt)}`,
    }, styleScripts);
    const normalized = normalizeScript(candidate.script);
    const validation = validateScriptProfile(
      normalized,
      input.roundCount,
      input.targetDurationSeconds,
    );
    if (!validation.valid) continue;
    const candidateSha256 = await sha256(normalized);
    if (seenHashes.has(candidateSha256)) continue;
    generated = candidate;
    script = normalized;
    scriptSha256 = candidateSha256;
    break;
  }
  if (!generated || !script || !scriptSha256) {
    return errorResponse("SCRIPT_DRAFT_UNIQUE_VARIATION_FAILED", 409, origin);
  }
  if (!validateScriptProfile(script, input.roundCount, input.targetDurationSeconds).valid) {
    return errorResponse("SCRIPT_DRAFT_VALIDATION_FAILED", 500, origin);
  }
  const draftId = `draft-${(await sha256(`${input.clientRequestId}:${scriptSha256}`)).slice(0, 24)}`;
  const timestamp = now();
  const timeline = extractScriptPhrases(script, input.roundCount);
  try {
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO operator_script_drafts_v2
        (draft_id, client_request_id, script, script_sha256, round_count,
         suggested_duration_seconds, generator_version, style_example_count,
         recommendation_id, learned_signals_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).bind(
        draftId,
        input.clientRequestId,
        script,
        scriptSha256,
        input.roundCount,
        input.targetDurationSeconds,
        generated.generatorVersion,
        styleScripts.length,
        input.recommendationId,
        JSON.stringify(generated.learnedSignals),
        timestamp,
      ),
      ...scriptStructureStatements(env, scriptSha256, draftId, timeline, timestamp),
    ]);
  } catch {
    const raced = await env.DB.prepare(
      "SELECT * FROM operator_script_drafts_v2 WHERE client_request_id = ?",
    ).bind(input.clientRequestId).first<ScriptDraftRow>();
    return raced
      ? json(draftProjection(raced), 200, origin)
      : errorResponse("SCRIPT_DRAFT_CREATE_FAILED", 500, origin);
  }
  const created = await draftById(env, draftId);
  return created
    ? json(draftProjection(created), 201, origin)
    : errorResponse("SCRIPT_DRAFT_CREATE_FAILED", 500, origin);
};

const runById = (env: Env, runId: string): Promise<RunRow | null> =>
  env.DB.prepare("SELECT * FROM operator_production_runs WHERE run_id = ?").bind(runId).first<RunRow>();

const ensureRunScriptManifest = async (
  env: Env,
  row: RunRow,
  timestamp: string,
): Promise<{ readonly manifest: RunScriptManifestRow; readonly timeline: ScriptPhraseTimeline }> => {
  const existing = await env.DB.prepare(
    "SELECT * FROM operator_run_script_manifests WHERE run_id = ?",
  ).bind(row.run_id).first<RunScriptManifestRow>();
  if (existing) {
    return {
      manifest: existing,
      timeline: extractScriptPhrases(row.script, existing.round_count),
    };
  }
  const origin = await env.DB.prepare(
    "SELECT * FROM operator_script_origins_v2 WHERE run_id = ?",
  ).bind(row.run_id).first<ScriptOriginRow>();
  const fallbackCount = row.script.split("\n").filter((line) => line === "(auflösung)").length;
  const roundCount = origin?.reveal_count ?? fallbackCount;
  if (!isSupportedRoundCount(roundCount)) throw new Error("RUN_SCRIPT_STRUCTURE_INVALID");
  const scriptSha256 = origin?.submitted_script_sha256 ?? await sha256(row.script);
  const timeline = extractScriptPhrases(row.script, roundCount);
  await env.DB.batch([
    ...scriptStructureStatements(env, scriptSha256, origin?.draft_id ?? null, timeline, timestamp),
    ...runScriptManifestStatements(env, row.run_id, scriptSha256, timeline, timestamp),
  ]);
  const created = await env.DB.prepare(
    "SELECT * FROM operator_run_script_manifests WHERE run_id = ?",
  ).bind(row.run_id).first<RunScriptManifestRow>();
  if (!created) throw new Error("RUN_SCRIPT_STRUCTURE_CREATE_FAILED");
  return { manifest: created, timeline };
};

const reviewByRunId = (env: Env, runId: string): Promise<ReviewRow | null> =>
  env.DB.prepare("SELECT * FROM operator_production_reviews WHERE run_id = ?").bind(runId).first<ReviewRow>();

const releaseByRunId = (env: Env, runId: string): Promise<ReleaseRequestRow | null> =>
  env.DB.prepare("SELECT * FROM operator_release_requests WHERE run_id = ?").bind(runId).first<ReleaseRequestRow>();

const releaseExecutionByRequestId = (env: Env, requestId: string): Promise<ReleaseExecutionRow | null> =>
  env.DB.prepare("SELECT * FROM operator_release_executions WHERE request_id = ?")
    .bind(requestId).first<ReleaseExecutionRow>();

const releasePlatformStates = (execution: ReleaseExecutionRow | null): CalendarPlatforms => {
  if (!execution) return initialReleasePlatformStates([]);
  try {
    return parsePlatforms(JSON.parse(execution.platform_results_json) as unknown);
  } catch {
    return initialReleasePlatformStates([]);
  }
};

const reviewStatus = (
  row: RunRow,
  review: ReviewRow | null,
  release: ReleaseRequestRow | null,
): ReviewRunStatus => {
  if (row.status === "failed") return "failed";
  if (!review || review.script_approval_status !== "approved") return "awaiting_script_approval";
  if (release?.status === "failed") return "failed";
  if (release?.status === "completed") return "published";
  if (release || review.video_approval_status === "approved") return "release_queued";
  if (row.status === "completed" && review.preview_object_key) return "awaiting_video_approval";
  return row.status;
};

const operatorRun = (
  row: RunRow,
  review: ReviewRow,
  release: ReleaseRequestRow | null,
  releaseExecution: ReleaseExecutionRow | null,
): Record<string, unknown> => ({
  runId: row.run_id,
  releaseLabel: review.release_label,
  status: reviewStatus(row, review, release),
  productionStatus: row.status,
  progress: row.progress,
  targetDurationSeconds: row.target_duration_seconds,
  currentStep: row.current_step,
  message: row.message,
  error: row.error_code,
  script: {
    text: row.script,
    sha256: review.script_sha256,
    revision: review.script_revision,
    status: review.script_approval_status,
    approvedAt: review.script_approved_at,
  },
  preview: {
    ready: Boolean(review.preview_object_key),
    url: review.preview_object_key ? `/v1/runs/${row.run_id}/preview` : null,
    sha256: review.preview_sha256,
    sizeBytes: review.preview_size_bytes,
    contentType: review.preview_content_type,
    qualityPassed: review.quality_gate_passed === 1,
    monetizationPassed: review.monetization_gate_passed === 1,
    revision: review.video_revision,
    uploadedAt: review.preview_uploaded_at,
  },
  videoApproval: {
    status: review.video_approval_status,
    revision: review.video_revision,
    approvedAt: review.video_approved_at,
  },
  release: release ? {
    requestId: release.request_id,
    status: release.status,
    platforms: releasePlatformStates(releaseExecution),
    error: releaseExecution?.error_code ?? null,
    createdAt: release.created_at,
  } : null,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const publicRun = (
  row: RunRow,
  review: ReviewRow,
  release: ReleaseRequestRow | null,
  releaseExecution: ReleaseExecutionRow | null,
): Record<string, unknown> => ({
  runId: row.run_id,
  releaseLabel: review.release_label,
  status: reviewStatus(row, review, release),
  productionStatus: row.status,
  progress: row.progress,
  targetDurationSeconds: row.target_duration_seconds,
  currentStep: row.current_step,
  message: row.message,
  error: row.error_code,
  scriptStatus: review.script_approval_status,
  previewReady: Boolean(review.preview_object_key),
  qualityPassed: review.quality_gate_passed === 1,
  monetizationPassed: review.monetization_gate_passed === 1,
  videoApprovalStatus: review.video_approval_status,
  releaseStatus: release?.status ?? null,
  releasePlatforms: releasePlatformStates(releaseExecution),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const completeRun = async (
  env: Env,
  row: RunRow,
  projection: "operator" | "public",
): Promise<Record<string, unknown> | null> => {
  const [review, release] = await Promise.all([
    reviewByRunId(env, row.run_id),
    releaseByRunId(env, row.run_id),
  ]);
  if (!review) return null;
  const releaseExecution = release
    ? await releaseExecutionByRequestId(env, release.request_id)
    : null;
  return projection === "operator"
    ? operatorRun(row, review, release, releaseExecution)
    : publicRun(row, review, release, releaseExecution);
};

const allocateReleaseLabel = async (env: Env, timestamp: string): Promise<string> => {
  const day = berlinDay(timestamp);
  const sequence = await env.DB.prepare(`INSERT INTO operator_release_label_sequences
    (day_key, next_sequence, updated_at) VALUES (?, 1, ?)
    ON CONFLICT(day_key) DO UPDATE SET
      next_sequence = operator_release_label_sequences.next_sequence + 1,
      updated_at = excluded.updated_at
    RETURNING next_sequence`).bind(day.dayKey, timestamp).first<{ readonly next_sequence: number }>();
  if (!sequence || !Number.isInteger(sequence.next_sequence) || sequence.next_sequence < 1) {
    throw new Error("RELEASE_LABEL_ALLOCATION_FAILED");
  }
  return `${day.display}.${String(sequence.next_sequence).padStart(2, "0")}`;
};

const insertEventStatement = (
  env: Env,
  runId: string,
  status: RunStatus,
  progress: number,
  currentStep: string | null,
  message: string | null,
  errorCode: string | null,
  timestamp: string,
): D1PreparedStatement => env.DB.prepare(`INSERT INTO operator_production_events
  (run_id, timestamp, status, progress, current_step, message, error_code) VALUES (?, ?, ?, ?, ?, ?, ?)`).bind(
  runId, timestamp, status, progress, currentStep, message, errorCode,
);

const createRun = async (request: Request, env: Env, origin: string | null): Promise<Response> => {
  const input = parseNewRun(await readJson(request));
  const linkedDraft = input.draftId ? await draftById(env, input.draftId) : null;
  if (linkedDraft && linkedDraft.round_count !== input.roundCount) {
    return errorResponse("SCRIPT_DRAFT_NOT_FOUND", 404, origin);
  }
  const canonical = JSON.stringify({
    schemaVersion: "1.0.0",
    language: "de",
    script: input.script,
    targetDurationSeconds: input.targetDurationSeconds,
  });
  const inputSha256 = await sha256(canonical);
  const scriptSha256 = await sha256(input.script);
  const timeline = extractScriptPhrases(input.script, input.roundCount);
  const scriptOrigin: ScriptOriginRow["origin"] = !linkedDraft
    ? "manual"
    : linkedDraft.script_sha256 === scriptSha256
      ? "auto_unedited"
      : "auto_edited";
  const runId = `video-${inputSha256.slice(0, 24)}`;
  const clientRequestId = input.clientRequestId ?? `dashboard-${inputSha256.slice(0, 32)}`;
  const byRequest = await env.DB.prepare(
    "SELECT * FROM operator_production_runs WHERE client_request_id = ?",
  ).bind(clientRequestId).first<RunRow>();
  if (byRequest) {
    if (byRequest.input_sha256 !== inputSha256) return errorResponse("IDEMPOTENCY_CONFLICT", 409, origin);
    const projection = await completeRun(env, byRequest, "operator");
    return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
  }
  const existing = await env.DB.prepare(
    "SELECT * FROM operator_production_runs WHERE input_sha256 = ?",
  ).bind(inputSha256).first<RunRow>();
  if (existing) {
    const projection = await completeRun(env, existing, "operator");
    return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
  }

  const timestamp = now();
  const releaseLabel = await allocateReleaseLabel(env, timestamp);
  const message = "Skriptfreigabe ausstehend.";
  try {
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO operator_production_runs
        (run_id, input_sha256, client_request_id, script, target_duration_seconds, status, progress,
         current_step, message, next_attempt_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'queued', 0, 'script_validation', ?, ?, ?, ?)`).bind(
        runId, inputSha256, clientRequestId, input.script, input.targetDurationSeconds,
        message, timestamp, timestamp, timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_production_reviews
        (run_id, release_label, script_sha256, script_revision, script_approval_status,
         video_approval_status, created_at, updated_at)
        VALUES (?, ?, ?, 1, 'pending', 'not_ready', ?, ?)`).bind(
        runId, releaseLabel, scriptSha256, timestamp, timestamp,
      ),
      ...scriptStructureStatements(
        env,
        scriptSha256,
        linkedDraft?.draft_id ?? null,
        timeline,
        timestamp,
      ),
      ...runScriptManifestStatements(
        env,
        runId,
        scriptSha256,
        timeline,
        timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_script_origins_v2
        (run_id, draft_id, origin, reveal_count, submitted_script_sha256,
         draft_script_sha256, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(
        runId,
        linkedDraft?.draft_id ?? null,
        scriptOrigin,
        input.roundCount,
        scriptSha256,
        linkedDraft?.script_sha256 ?? null,
        timestamp,
        timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_review_events
        (run_id, timestamp, event_type, revision, artifact_sha256)
        VALUES (?, ?, 'script_created', 1, ?)`).bind(runId, timestamp, scriptSha256),
      insertEventStatement(env, runId, "queued", 0, "script_validation", message, null, timestamp),
    ]);
  } catch {
    const raced = await env.DB.prepare(
      "SELECT * FROM operator_production_runs WHERE input_sha256 = ? OR client_request_id = ? LIMIT 1",
    ).bind(inputSha256, clientRequestId).first<RunRow>();
    if (!raced || raced.input_sha256 !== inputSha256) return errorResponse("IDEMPOTENCY_CONFLICT", 409, origin);
    const projection = await completeRun(env, raced, "operator");
    return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
  }
  const created = await runById(env, runId);
  const projection = created ? await completeRun(env, created, "operator") : null;
  return projection ? json(projection, 202, origin) : errorResponse("RUN_CREATE_FAILED", 500, origin);
};

const listRuns = async (
  url: URL,
  env: Env,
  origin: string | null,
  projection: "operator" | "public",
): Promise<Response> => {
  const rawLimit = url.searchParams.get("limit") ?? "20";
  const limit = Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) return errorResponse("INVALID_LIMIT", 400, origin);
  const rows = await env.DB.prepare(
    "SELECT * FROM operator_production_runs ORDER BY created_at DESC LIMIT ?",
  ).bind(limit).all<RunRow>();
  const runs = (await Promise.all((rows.results ?? []).map((row) => completeRun(env, row, projection))))
    .filter((run): run is Record<string, unknown> => run !== null);
  return json({ runs }, 200, origin);
};

const getRun = async (
  env: Env,
  runId: string,
  origin: string | null,
  projection: "operator" | "public",
): Promise<Response> => {
  const row = await runById(env, runId);
  if (!row) return errorResponse("RUN_NOT_FOUND", 404, origin);
  const run = await completeRun(env, row, projection);
  return run ? json(run, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 404, origin);
};

interface ScriptApprovalInput {
  readonly scriptSha256: string;
  readonly scriptRevision: number;
  readonly idempotencyKey: string;
}

interface VideoApprovalInput {
  readonly previewSha256: string;
  readonly videoRevision: number;
  readonly idempotencyKey: string;
}

const approvalKey = (value: unknown): string | null => {
  const key = safeText(value, 128);
  return key && /^[A-Za-z0-9._:-]{8,128}$/u.test(key) ? key : null;
};

const artifactHash = (value: unknown): string | null =>
  typeof value === "string" && /^[a-f0-9]{64}$/u.test(value) ? value : null;

const parseScriptApproval = (value: unknown): ScriptApprovalInput => {
  if (!isRecord(value) || !exactKeys(value, ["scriptSha256", "scriptRevision", "idempotencyKey"])) {
    throw new Error("INVALID_SCRIPT_APPROVAL");
  }
  const scriptSha256 = artifactHash(value.scriptSha256);
  const idempotencyKey = approvalKey(value.idempotencyKey);
  if (!scriptSha256 || !idempotencyKey || !Number.isInteger(value.scriptRevision) || Number(value.scriptRevision) < 1) {
    throw new Error("INVALID_SCRIPT_APPROVAL");
  }
  return { scriptSha256, scriptRevision: Number(value.scriptRevision), idempotencyKey };
};

const parseVideoApproval = (value: unknown): VideoApprovalInput => {
  if (!isRecord(value) || !exactKeys(value, ["previewSha256", "videoRevision", "idempotencyKey"])) {
    throw new Error("INVALID_VIDEO_APPROVAL");
  }
  const previewSha256 = artifactHash(value.previewSha256);
  const idempotencyKey = approvalKey(value.idempotencyKey);
  if (!previewSha256 || !idempotencyKey || !Number.isInteger(value.videoRevision) || Number(value.videoRevision) < 1) {
    throw new Error("INVALID_VIDEO_APPROVAL");
  }
  return { previewSha256, videoRevision: Number(value.videoRevision), idempotencyKey };
};

const approveScript = async (
  request: Request,
  env: Env,
  runId: string,
  origin: string | null,
): Promise<Response> => {
  const input = parseScriptApproval(await readJson(request));
  const [row, review] = await Promise.all([runById(env, runId), reviewByRunId(env, runId)]);
  if (!row || !review) return errorResponse("RUN_NOT_FOUND", 404, origin);
  if (review.script_sha256 !== input.scriptSha256 || review.script_revision !== input.scriptRevision) {
    return errorResponse("SCRIPT_REVISION_CONFLICT", 409, origin);
  }
  if (review.script_approval_status === "approved") {
    if (
      review.script_approval_idempotency_key !== input.idempotencyKey &&
      review.script_approval_idempotency_key !== null
    ) return errorResponse("SCRIPT_ALREADY_APPROVED", 409, origin);
    const projection = await completeRun(env, row, "operator");
    return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
  }
  if (row.status !== "queued") return errorResponse("SCRIPT_APPROVAL_NOT_ALLOWED", 409, origin);

  const timestamp = now();
  const message = "Skript freigegeben. Wartet auf Produktionsrechner.";
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE operator_production_reviews SET
        script_approval_status = 'approved', script_approval_idempotency_key = ?,
        script_approved_at = ?, updated_at = ?
        WHERE run_id = ? AND script_approval_status = 'pending'
          AND script_sha256 = ? AND script_revision = ?`).bind(
        input.idempotencyKey, timestamp, timestamp, runId, input.scriptSha256, input.scriptRevision,
      ),
      env.DB.prepare(`UPDATE operator_production_runs SET
        message = ?, current_step = 'production_queue', next_attempt_at = ?, updated_at = ?
        WHERE run_id = ? AND status = 'queued'`).bind(message, timestamp, timestamp, runId),
      env.DB.prepare(`INSERT INTO operator_review_events
        (run_id, timestamp, event_type, revision, artifact_sha256)
        VALUES (?, ?, 'script_approved', ?, ?)`).bind(
        runId, timestamp, input.scriptRevision, input.scriptSha256,
      ),
      env.DB.prepare(`INSERT OR IGNORE INTO operator_script_style_examples_v2
        (example_id, script_sha256, script, source, reveal_count,
         target_duration_seconds, trust_level, created_at, updated_at)
        SELECT ?, origins.submitted_script_sha256, runs.script,
          CASE origins.origin WHEN 'manual' THEN 'manual' ELSE 'auto_edited' END,
          origins.reveal_count, runs.target_duration_seconds, 'candidate', ?, ?
        FROM operator_production_runs AS runs
        JOIN operator_script_origins_v2 AS origins ON origins.run_id = runs.run_id
        JOIN operator_production_reviews AS reviews ON reviews.run_id = runs.run_id
        WHERE runs.run_id = ? AND reviews.script_approval_status = 'approved'
          AND origins.origin IN ('manual', 'auto_edited')`).bind(
        `style-${input.scriptSha256.slice(0, 24)}`, timestamp, timestamp, runId,
      ),
      insertEventStatement(env, runId, "queued", row.progress, "production_queue", message, null, timestamp),
    ]);
  } catch {
    const current = await reviewByRunId(env, runId);
    if (
      !current || current.script_approval_status !== "approved" ||
      current.script_sha256 !== input.scriptSha256 ||
      current.script_revision !== input.scriptRevision ||
      current.script_approval_idempotency_key !== input.idempotencyKey
    ) return errorResponse("SCRIPT_APPROVAL_CONFLICT", 409, origin);
  }
  const updated = await runById(env, runId);
  const projection = updated ? await completeRun(env, updated, "operator") : null;
  return projection ? json(projection, 200, origin) : errorResponse("RUN_NOT_FOUND", 404, origin);
};

const retryRun = async (
  env: Env,
  runId: string,
  origin: string | null,
): Promise<Response> => {
  const [row, review, release] = await Promise.all([
    runById(env, runId),
    reviewByRunId(env, runId),
    releaseByRunId(env, runId),
  ]);
  if (!row || !review) return errorResponse("RUN_NOT_FOUND", 404, origin);
  if (row.status !== "failed") {
    if (["queued", "claimed", "running", "waiting"].includes(row.status)) {
      const projection = await completeRun(env, row, "operator");
      return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
    }
    return errorResponse("RUN_RETRY_NOT_ALLOWED", 409, origin);
  }
  const safelyRetryableSteps = new Set(["flag_selection", "timeline_build"]);
  const safelyRetryable =
    safelyRetryableSteps.has(row.current_step ?? "") &&
    review.script_approval_status === "approved" &&
    review.preview_object_key === null &&
    review.video_approval_status === "not_ready" &&
    release === null;
  if (!safelyRetryable) return errorResponse("RUN_RETRY_NOT_ALLOWED", 409, origin);

  const timestamp = now();
  const message = "Sicherer Vorstufenschritt erneut eingeplant.";
  const update = await env.DB.prepare(`UPDATE operator_production_runs SET
    status = 'queued', current_step = 'production_queue', message = ?, error_code = NULL,
    lease_owner = NULL, lease_token_sha256 = NULL, lease_expires_at = NULL,
    next_attempt_at = ?, updated_at = ?
    WHERE run_id = ? AND status = 'failed'
      AND current_step IN ('flag_selection', 'timeline_build')`).bind(
    message, timestamp, timestamp, runId,
  ).run();
  if ((update.meta?.changes ?? 0) !== 1) {
    const current = await runById(env, runId);
    if (!current || !["queued", "claimed", "running", "waiting"].includes(current.status)) {
      return errorResponse("RUN_RETRY_CONFLICT", 409, origin);
    }
  } else {
    await insertEventStatement(
      env,
      runId,
      "queued",
      row.progress,
      "production_queue",
      message,
      null,
      timestamp,
    ).run();
  }
  const retried = await runById(env, runId);
  const projection = retried ? await completeRun(env, retried, "operator") : null;
  return projection ? json(projection, 200, origin) : errorResponse("RUN_NOT_FOUND", 404, origin);
};

const approveVideo = async (
  request: Request,
  env: Env,
  runId: string,
  origin: string | null,
): Promise<Response> => {
  const input = parseVideoApproval(await readJson(request));
  const [row, review, existingRelease] = await Promise.all([
    runById(env, runId),
    reviewByRunId(env, runId),
    releaseByRunId(env, runId),
  ]);
  if (!row || !review) return errorResponse("RUN_NOT_FOUND", 404, origin);
  if (review.preview_sha256 !== input.previewSha256 || review.video_revision !== input.videoRevision) {
    return errorResponse("VIDEO_REVISION_CONFLICT", 409, origin);
  }
  if (review.video_approval_status === "approved" || existingRelease) {
    if (
      review.video_approval_status !== "approved" || !existingRelease ||
      existingRelease.preview_sha256 !== input.previewSha256 ||
      existingRelease.video_revision !== input.videoRevision ||
      existingRelease.idempotency_key !== input.idempotencyKey
    ) return errorResponse("VIDEO_ALREADY_APPROVED", 409, origin);
    const projection = await completeRun(env, row, "operator");
    return projection ? json(projection, 200, origin) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, origin);
  }
  if (
    row.status !== "completed" || review.script_approval_status !== "approved" ||
    !review.preview_object_key || review.video_approval_status !== "pending" ||
    review.quality_gate_passed !== 1 || review.monetization_gate_passed !== 1
  ) return errorResponse("VIDEO_GATES_NOT_PASSED", 409, origin);

  const timestamp = now();
  const requestId = `release-${(await sha256(`${runId}:${input.previewSha256}:${input.videoRevision}`)).slice(0, 24)}`;
  const selectedPlatforms = configuredReleasePlatforms(env);
  const platformStates = initialReleasePlatformStates(selectedPlatforms);
  const calendarEntryId = `release:${runId}`;
  const calendarTitle = row.script.split("\n").find((line) => line !== "(auflösung)")?.slice(0, 140)
    ?? review.release_label;
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE operator_production_reviews SET
        video_approval_status = 'approved', video_approval_idempotency_key = ?,
        video_approved_at = ?, updated_at = ?
        WHERE run_id = ? AND video_approval_status = 'pending'
          AND preview_sha256 = ? AND video_revision = ?
          AND quality_gate_passed = 1 AND monetization_gate_passed = 1`).bind(
        input.idempotencyKey, timestamp, timestamp, runId, input.previewSha256, input.videoRevision,
      ),
      env.DB.prepare(`INSERT INTO operator_release_requests
        (request_id, run_id, preview_sha256, video_revision, idempotency_key, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'queued', ?, ?)`).bind(
        requestId, runId, input.previewSha256, input.videoRevision,
        input.idempotencyKey, timestamp, timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_release_executions
        (request_id, platforms_json, platform_results_json, next_attempt_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)`).bind(
        requestId, JSON.stringify(selectedPlatforms), JSON.stringify(platformStates),
        timestamp, timestamp, timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_release_events
        (request_id, timestamp, status, platform_results_json, message, error_code)
        VALUES (?, ?, 'queued', ?, 'Video freigegeben. Veröffentlichung wartet auf Plattform-Runner.', NULL)`).bind(
        requestId, timestamp, JSON.stringify(platformStates),
      ),
      env.DB.prepare(`INSERT INTO operator_calendar_entries
        (entry_id, content_id, title, scheduled_at, platforms_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(entry_id) DO UPDATE SET
          content_id = excluded.content_id, title = excluded.title,
          scheduled_at = excluded.scheduled_at, platforms_json = excluded.platforms_json,
          updated_at = excluded.updated_at`).bind(
        calendarEntryId, row.provider_run_id ?? runId, calendarTitle, timestamp,
        JSON.stringify(platformStates), timestamp, timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_calendar_reviews
        (entry_id, run_id, release_label, video_approved, final_release_approved, updated_at)
        VALUES (?, ?, ?, 1, 0, ?)
        ON CONFLICT(entry_id) DO UPDATE SET
          run_id = excluded.run_id, release_label = excluded.release_label,
          video_approved = 1, updated_at = excluded.updated_at`).bind(
        calendarEntryId, runId, review.release_label, timestamp,
      ),
      env.DB.prepare(`INSERT INTO operator_review_events
        (run_id, timestamp, event_type, revision, artifact_sha256)
        VALUES (?, ?, 'video_approved', ?, ?)`).bind(
        runId, timestamp, input.videoRevision, input.previewSha256,
      ),
    ]);
  } catch {
    const release = await releaseByRunId(env, runId);
    if (
      !release || release.request_id !== requestId ||
      release.preview_sha256 !== input.previewSha256 ||
      release.video_revision !== input.videoRevision ||
      release.idempotency_key !== input.idempotencyKey
    ) return errorResponse("VIDEO_APPROVAL_CONFLICT", 409, origin);
  }
  const updated = await runById(env, runId);
  const projection = updated ? await completeRun(env, updated, "operator") : null;
  return projection ? json(projection, 200, origin) : errorResponse("RUN_NOT_FOUND", 404, origin);
};

interface ClaimInput {
  readonly runnerId: string;
  readonly leaseSeconds: number;
}

const parseClaim = (value: unknown): ClaimInput => {
  if (!isRecord(value) || !exactKeys(value, ["runnerId", "leaseSeconds"])) throw new Error("INVALID_CLAIM");
  const runnerId = safeText(value.runnerId, 100);
  const leaseSeconds = value.leaseSeconds === undefined ? 60 : value.leaseSeconds;
  if (
    !runnerId || !/^[A-Za-z0-9._:-]{3,100}$/u.test(runnerId) ||
    typeof leaseSeconds !== "number" || !Number.isInteger(leaseSeconds) ||
    leaseSeconds < MIN_LEASE_SECONDS || leaseSeconds > MAX_LEASE_SECONDS
  ) throw new Error("INVALID_CLAIM");
  return { runnerId, leaseSeconds };
};

const claimRun = async (request: Request, env: Env): Promise<Response> => {
  const input = parseClaim(await readJson(request));
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const timestamp = now();
    const candidate = await env.DB.prepare(`SELECT * FROM operator_production_runs
      WHERE status IN ('queued', 'claimed', 'running', 'waiting')
        AND next_attempt_at <= ?
        AND (lease_expires_at IS NULL OR lease_expires_at <= ?)
        AND EXISTS (
          SELECT 1 FROM operator_production_reviews review
          WHERE review.run_id = operator_production_runs.run_id
            AND review.script_approval_status = 'approved'
        )
      ORDER BY CASE status WHEN 'queued' THEN 0 ELSE 1 END, created_at ASC
      LIMIT 1`).bind(timestamp, timestamp).first<RunRow>();
    if (!candidate) return new Response(null, { status: 204, headers: responseHeaders(null) });

    const leaseToken = crypto.randomUUID();
    const leaseHash = await sha256(leaseToken);
    const leaseExpiresAt = new Date(Date.now() + input.leaseSeconds * 1_000).toISOString();
    const message = "Vom lokalen Runner übernommen.";
    const update = await env.DB.prepare(`UPDATE operator_production_runs SET
      status = 'claimed', lease_owner = ?, lease_token_sha256 = ?, lease_expires_at = ?,
      next_attempt_at = ?, attempt_count = attempt_count + 1, message = ?, error_code = NULL, updated_at = ?
      WHERE run_id = ? AND status IN ('queued', 'claimed', 'running', 'waiting')
        AND next_attempt_at <= ? AND (lease_expires_at IS NULL OR lease_expires_at <= ?)`).bind(
      input.runnerId, leaseHash, leaseExpiresAt, leaseExpiresAt, message, timestamp,
      candidate.run_id, timestamp, timestamp,
    ).run();
    if ((update.meta?.changes ?? 0) !== 1) continue;
    await insertEventStatement(env, candidate.run_id, "claimed", candidate.progress, candidate.current_step, message, null, timestamp).run();
    const claimed = await runById(env, candidate.run_id);
    if (!claimed) return errorResponse("CLAIM_FAILED", 500, null);
    const scriptManifest = await ensureRunScriptManifest(env, claimed, timestamp);
    return json({
      run: {
        runId: claimed.run_id,
        status: claimed.status,
        progress: claimed.progress,
        currentStep: claimed.current_step,
      },
      command: {
        script: claimed.script,
        targetDurationSeconds: claimed.target_duration_seconds,
        clientRequestId: claimed.client_request_id,
        roundCount: scriptManifest.manifest.round_count,
        phraseTimeline: scriptManifest.timeline,
      },
      leaseToken,
    });
  }
  return new Response(null, { status: 204, headers: responseHeaders(null) });
};

interface RunnerUpdate {
  readonly runnerId: string;
  readonly leaseToken: string;
  readonly status: "running" | "waiting" | "completed" | "failed";
  readonly progress: number;
  readonly currentStep: string | null;
  readonly message: string | null;
  readonly error: string | null;
  readonly providerRunId: string;
}

const parseRunnerUpdate = (value: unknown): RunnerUpdate => {
  if (!isRecord(value) || !exactKeys(value, [
    "runnerId", "leaseToken", "status", "progress", "currentStep", "message", "error", "providerRunId",
  ])) throw new Error("INVALID_RUNNER_UPDATE");
  const runnerId = safeText(value.runnerId, 100);
  const leaseToken = safeText(value.leaseToken, 200);
  const status = value.status as RunStatus;
  const progress = value.progress;
  const currentStep = value.currentStep === null ? null : safeText(value.currentStep, 100);
  const message = value.message === null ? null : safeMessage(value.message);
  const error = safeErrorCode(value.error);
  const providerRunId = safeText(value.providerRunId, 100);
  if (
    !runnerId || !leaseToken || !RUNNER_STATUSES.includes(status) ||
    typeof progress !== "number" || !Number.isFinite(progress) || progress < 0 || progress > 100 ||
    (value.currentStep !== null && !currentStep) || (value.message !== null && !message) ||
    !providerRunId || !/^video-[a-f0-9]{24}$/u.test(providerRunId) ||
    (status === "failed" && !error) || (status !== "failed" && error)
  ) throw new Error("INVALID_RUNNER_UPDATE");
  return { runnerId, leaseToken, status, progress, currentStep, message, error, providerRunId };
};

const ownsLease = async (
  row: RunRow,
  runnerId: string,
  leaseToken: string,
  timestamp: string,
): Promise<boolean> =>
  row.lease_owner === runnerId && Boolean(row.lease_token_sha256) &&
  await secureEqual(await sha256(leaseToken), row.lease_token_sha256 ?? "") &&
  Boolean(row.lease_expires_at) && (row.lease_expires_at ?? "") >= timestamp;

const uploadPreview = async (
  request: Request,
  env: Env,
  runId: string,
): Promise<Response> => {
  const row = await runById(env, runId);
  if (!row) return errorResponse("RUN_NOT_FOUND", 404, null);
  const runnerId = safeText(request.headers.get("x-runner-id"), 100);
  const leaseToken = safeText(request.headers.get("x-lease-token"), 200);
  const previewSha256 = artifactHash(request.headers.get("x-preview-sha256"));
  const rawSize = request.headers.get("content-length");
  const sizeBytes = rawSize ? Number(rawSize) : Number.NaN;
  const rawRevision = request.headers.get("x-video-revision");
  const videoRevision = rawRevision ? Number(rawRevision) : Number.NaN;
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  const qualityPassed = request.headers.get("x-quality-gate") === "passed";
  const monetizationPassed = request.headers.get("x-monetization-gate") === "passed";
  const timestamp = now();
  if (
    !runnerId || !leaseToken || !previewSha256 || contentType !== "video/mp4" ||
    !Number.isInteger(sizeBytes) || sizeBytes < 1 || sizeBytes > MAX_PREVIEW_BYTES ||
    !Number.isInteger(videoRevision) || videoRevision < 1 ||
    !qualityPassed || !monetizationPassed || !request.body
  ) return errorResponse("INVALID_PREVIEW", 400, null);
  if (!await ownsLease(row, runnerId, leaseToken, timestamp)) {
    return errorResponse("LEASE_NOT_OWNED", 409, null);
  }
  const review = await reviewByRunId(env, runId);
  if (!review || review.script_approval_status !== "approved") {
    return errorResponse("SCRIPT_APPROVAL_REQUIRED", 409, null);
  }
  if (
    review.preview_sha256 === previewSha256 &&
    review.video_revision === videoRevision &&
    review.preview_object_key
  ) {
    return json({
      sha256: previewSha256,
      sizeBytes: review.preview_size_bytes,
      revision: videoRevision,
      qualityPassed: review.quality_gate_passed === 1,
      monetizationPassed: review.monetization_gate_passed === 1,
    });
  }
  if (videoRevision !== review.video_revision + 1 || review.video_approval_status === "approved") {
    return errorResponse("VIDEO_REVISION_CONFLICT", 409, null);
  }

  const objectKey = `previews/${runId}/v${videoRevision}/${previewSha256}.mp4`;
  try {
    await env.PREVIEWS.put(objectKey, request.body, {
      httpMetadata: { contentType: "video/mp4" },
      customMetadata: {
        runId,
        sha256: previewSha256,
        revision: String(videoRevision),
      },
      sha256: hexToArrayBuffer(previewSha256),
    });
  } catch {
    return errorResponse("PREVIEW_HASH_MISMATCH", 409, null);
  }

  const result = await env.DB.prepare(`UPDATE operator_production_reviews SET
    preview_object_key = ?, preview_sha256 = ?, preview_size_bytes = ?,
    preview_content_type = 'video/mp4', preview_uploaded_at = ?,
    quality_gate_passed = 1, monetization_gate_passed = 1,
    video_revision = ?, video_approval_status = 'pending',
    video_approval_idempotency_key = NULL, video_approved_at = NULL, updated_at = ?
    WHERE run_id = ? AND script_approval_status = 'approved'
      AND video_approval_status != 'approved' AND video_revision = ?`).bind(
    objectKey, previewSha256, sizeBytes, timestamp, videoRevision, timestamp,
    runId, videoRevision - 1,
  ).run();
  if ((result.meta?.changes ?? 0) !== 1) {
    await env.PREVIEWS.delete(objectKey);
    return errorResponse("VIDEO_REVISION_CONFLICT", 409, null);
  }
  await env.DB.prepare(`INSERT INTO operator_review_events
    (run_id, timestamp, event_type, revision, artifact_sha256)
    VALUES (?, ?, 'preview_uploaded', ?, ?)`).bind(
    runId, timestamp, videoRevision, previewSha256,
  ).run();
  return json({
    sha256: previewSha256,
    sizeBytes,
    revision: videoRevision,
    qualityPassed: true,
    monetizationPassed: true,
  });
};

interface RunnerAnalysisRound {
  readonly round: number;
  readonly solutionCountry: string | null;
  readonly solutionCountryCode: string | null;
  readonly flagShownAtSeconds: number | null;
  readonly revealAtSeconds: number | null;
}

interface RunnerWordCue {
  readonly word: string;
  readonly startSeconds: number;
  readonly endSeconds: number;
}

interface RunnerAnalysisManifest {
  readonly runnerId: string;
  readonly leaseToken: string;
  readonly rounds: readonly RunnerAnalysisRound[];
  readonly wordCues: readonly RunnerWordCue[];
}

const nullableTimestamp = (value: unknown): number | null | undefined => {
  if (value === null) return null;
  if (
    typeof value !== "number" || !Number.isFinite(value) ||
    value < 0 || value > 600
  ) return undefined;
  return Number(value.toFixed(3));
};

const nullableCountry = (value: unknown): string | null | undefined => {
  if (value === null) return null;
  const country = safeText(value, 100);
  if (!country || !/^[\p{L}\p{M}][\p{L}\p{M}\p{N} .,'’()/-]{0,99}$/u.test(country)) {
    return undefined;
  }
  return country;
};

const nullableCountryCode = (value: unknown): string | null | undefined => {
  if (value === null) return null;
  const code = safeText(value, 3)?.toUpperCase();
  return code && /^[A-Z]{2,3}$/u.test(code) ? code : undefined;
};

const normalizedSpeechTokens = (value: string): readonly string[] =>
  (value.normalize("NFKD").toLocaleLowerCase("de").replaceAll("ß", "ss")
    .match(/[\p{L}\p{N}]+/gu) ?? [])
    .map((token) => token.normalize("NFC"));

const parseRunnerAnalysisManifest = (
  value: unknown,
  roundCount: SupportedRoundCount,
): RunnerAnalysisManifest => {
  if (!isRecord(value) || !exactKeys(value, ["runnerId", "leaseToken", "rounds", "wordCues"])) {
    throw new Error("INVALID_ANALYSIS_MANIFEST");
  }
  const runnerId = safeText(value.runnerId, 100);
  const leaseToken = safeText(value.leaseToken, 200);
  if (
    !runnerId || !/^[A-Za-z0-9._:-]{3,100}$/u.test(runnerId) ||
    !leaseToken || !Array.isArray(value.rounds) || !Array.isArray(value.wordCues) ||
    value.rounds.length !== roundCount || value.wordCues.length > 1_500
  ) throw new Error("INVALID_ANALYSIS_MANIFEST");

  const rounds = value.rounds.map((entry): RunnerAnalysisRound => {
    if (!isRecord(entry) || !exactKeys(entry, [
      "round", "solutionCountry", "solutionCountryCode",
      "flagShownAtSeconds", "revealAtSeconds",
    ])) throw new Error("INVALID_ANALYSIS_MANIFEST");
    const round = Number(entry.round);
    const solutionCountry = nullableCountry(entry.solutionCountry);
    const solutionCountryCode = nullableCountryCode(entry.solutionCountryCode);
    const flagShownAtSeconds = nullableTimestamp(entry.flagShownAtSeconds);
    const revealAtSeconds = nullableTimestamp(entry.revealAtSeconds);
    if (
      !Number.isInteger(round) || round < 1 || round > roundCount ||
      solutionCountry === undefined || solutionCountryCode === undefined ||
      flagShownAtSeconds === undefined || revealAtSeconds === undefined ||
      (solutionCountry === null) !== (solutionCountryCode === null) ||
      (flagShownAtSeconds !== null && revealAtSeconds !== null &&
        revealAtSeconds < flagShownAtSeconds)
    ) throw new Error("INVALID_ANALYSIS_MANIFEST");
    return {
      round,
      solutionCountry,
      solutionCountryCode,
      flagShownAtSeconds,
      revealAtSeconds,
    };
  });
  if (new Set(rounds.map((round) => round.round)).size !== roundCount) {
    throw new Error("INVALID_ANALYSIS_MANIFEST");
  }

  let priorStart = -1;
  const wordCues = value.wordCues.map((entry): RunnerWordCue => {
    if (!isRecord(entry) || !exactKeys(entry, ["word", "startSeconds", "endSeconds"])) {
      throw new Error("INVALID_ANALYSIS_MANIFEST");
    }
    const word = safeText(entry.word, 100);
    const startSeconds = nullableTimestamp(entry.startSeconds);
    const endSeconds = nullableTimestamp(entry.endSeconds);
    if (
      !word || normalizedSpeechTokens(word).length === 0 ||
      startSeconds === null || startSeconds === undefined ||
      endSeconds === null || endSeconds === undefined ||
      endSeconds < startSeconds || startSeconds < priorStart
    ) throw new Error("INVALID_ANALYSIS_MANIFEST");
    priorStart = startSeconds;
    return { word, startSeconds, endSeconds };
  });
  return { runnerId, leaseToken, rounds, wordCues };
};

interface CueToken {
  readonly token: string;
  readonly cue: RunnerWordCue;
}

const alignPhraseTimings = (
  timeline: ScriptPhraseTimeline,
  rounds: readonly RunnerAnalysisRound[],
  wordCues: readonly RunnerWordCue[],
): readonly {
  readonly phraseId: string;
  readonly startSeconds: number | null;
  readonly endSeconds: number | null;
  readonly solutionCountry: string | null;
  readonly solutionCountryCode: string | null;
}[] => {
  const cueTokens: CueToken[] = wordCues.flatMap((cue) =>
    normalizedSpeechTokens(cue.word).map((token) => ({ token, cue })));
  const roundByNumber = new Map(rounds.map((round) => [round.round, round]));
  let cursor = 0;
  return timeline.phrases.map((phrase) => {
    const round = phrase.round === null ? null : roundByNumber.get(phrase.round) ?? null;
    if (phrase.type === "reveal") {
      return {
        phraseId: phrase.phraseId,
        startSeconds: round?.revealAtSeconds ?? null,
        endSeconds: round?.revealAtSeconds ?? null,
        solutionCountry: round?.solutionCountry ?? null,
        solutionCountryCode: round?.solutionCountryCode ?? null,
      };
    }
    const expected = normalizedSpeechTokens(phrase.text);
    let matchStart = -1;
    if (expected.length > 0) {
      for (let candidate = cursor; candidate + expected.length <= cueTokens.length; candidate += 1) {
        if (expected.every((token, offset) => cueTokens[candidate + offset]?.token === token)) {
          matchStart = candidate;
          break;
        }
      }
    }
    if (matchStart < 0) {
      return {
        phraseId: phrase.phraseId,
        startSeconds: null,
        endSeconds: null,
        solutionCountry: null,
        solutionCountryCode: null,
      };
    }
    const matchEnd = matchStart + expected.length - 1;
    cursor = matchEnd + 1;
    return {
      phraseId: phrase.phraseId,
      startSeconds: cueTokens[matchStart]?.cue.startSeconds ?? null,
      endSeconds: cueTokens[matchEnd]?.cue.endSeconds ?? null,
      solutionCountry: null,
      solutionCountryCode: null,
    };
  });
};

const uploadAnalysisManifest = async (
  request: Request,
  env: Env,
  runId: string,
): Promise<Response> => {
  const row = await runById(env, runId);
  if (!row) return errorResponse("RUN_NOT_FOUND", 404, null);
  const timestamp = now();
  const persisted = await ensureRunScriptManifest(env, row, timestamp);
  const input = parseRunnerAnalysisManifest(
    await readJson(request),
    persisted.manifest.round_count,
  );
  if (!await ownsLease(row, input.runnerId, input.leaseToken, timestamp)) {
    return errorResponse("LEASE_NOT_OWNED", 409, null);
  }

  const phraseUpdates = alignPhraseTimings(
    persisted.timeline,
    input.rounds,
    input.wordCues,
  );
  const spokenPhraseCount = persisted.timeline.phrases
    .filter((phrase) => phrase.type !== "reveal").length;
  const alignedSpokenPhraseCount = phraseUpdates
    .filter((phrase) => phrase.startSeconds !== null && phrase.endSeconds !== null)
    .length - input.rounds.filter((round) => round.revealAtSeconds !== null).length;
  if (input.wordCues.length > 0 && alignedSpokenPhraseCount < 1) {
    return errorResponse("WORD_CUES_NOT_ALIGNED", 422, null);
  }

  await env.DB.batch([
    env.DB.prepare(`UPDATE operator_run_script_manifests SET
      timing_source = ?, updated_at = ? WHERE run_id = ?`).bind(
      alignedSpokenPhraseCount > 0 ? "word_timestamps" : "script_only",
      timestamp,
      runId,
    ),
    ...phraseUpdates.map((phrase) => env.DB.prepare(`UPDATE operator_run_script_phrases SET
      start_seconds = COALESCE(?, start_seconds),
      end_seconds = COALESCE(?, end_seconds),
      solution_country = COALESCE(?, solution_country),
      solution_country_code = COALESCE(?, solution_country_code),
      updated_at = ?
      WHERE run_id = ? AND phrase_id = ?`).bind(
      phrase.startSeconds,
      phrase.endSeconds,
      phrase.solutionCountry,
      phrase.solutionCountryCode,
      timestamp,
      runId,
      phrase.phraseId,
    )),
    ...input.rounds.map((round) => env.DB.prepare(`UPDATE operator_run_script_rounds SET
      solution_country = COALESCE(?, solution_country),
      solution_country_code = COALESCE(?, solution_country_code),
      flag_shown_at_seconds = COALESCE(?, flag_shown_at_seconds),
      reveal_at_seconds = COALESCE(?, reveal_at_seconds),
      updated_at = ?
      WHERE run_id = ? AND round_number = ?`).bind(
      round.solutionCountry,
      round.solutionCountryCode,
      round.flagShownAtSeconds,
      round.revealAtSeconds,
      timestamp,
      runId,
      round.round,
    )),
  ]);
  return json({
    runId,
    schemaVersion: persisted.manifest.schema_version,
    roundCount: persisted.manifest.round_count,
    timingSource: alignedSpokenPhraseCount > 0 ? "word_timestamps" : "script_only",
    alignedPhraseCount: alignedSpokenPhraseCount,
    spokenPhraseCount,
    unmatchedPhraseCount: Math.max(0, spokenPhraseCount - alignedSpokenPhraseCount),
    roundsStored: input.rounds.length,
  });
};

const updateFromRunner = async (
  request: Request,
  env: Env,
  runId: string,
): Promise<Response> => {
  const input = parseRunnerUpdate(await readJson(request));
  const row = await runById(env, runId);
  if (!row) return errorResponse("RUN_NOT_FOUND", 404, null);
  const timestamp = now();
  if (!await ownsLease(row, input.runnerId, input.leaseToken, timestamp)) {
    return errorResponse("LEASE_NOT_OWNED", 409, null);
  }
  if (input.status === "completed") {
    const review = await reviewByRunId(env, runId);
    if (
      !review?.preview_object_key || !review.preview_sha256 ||
      review.video_approval_status !== "pending" ||
      review.quality_gate_passed !== 1 || review.monetization_gate_passed !== 1
    ) return errorResponse("PREVIEW_AND_GATES_REQUIRED", 409, null);
  }

  const terminal = input.status === "completed" || input.status === "failed";
  const waiting = input.status === "waiting";
  const nextAttemptAt = waiting
    ? new Date(Date.now() + WAITING_RECHECK_SECONDS * 1_000).toISOString()
    : terminal ? timestamp : new Date(Date.now() + 60_000).toISOString();
  const leaseExpiresAt = terminal || waiting ? null : nextAttemptAt;
  const completedAt = terminal ? timestamp : null;
  const result = await env.DB.prepare(`UPDATE operator_production_runs SET
      status = ?, progress = ?, current_step = ?, message = ?, error_code = ?, provider_run_id = ?,
      lease_owner = ?, lease_token_sha256 = ?, lease_expires_at = ?, next_attempt_at = ?,
      completed_at = ?, updated_at = ?
      WHERE run_id = ? AND lease_owner = ? AND lease_token_sha256 = ?`).bind(
      input.status, input.progress, input.currentStep, input.message, input.error, input.providerRunId,
      terminal || waiting ? null : input.runnerId,
      terminal || waiting ? null : row.lease_token_sha256,
      leaseExpiresAt, nextAttemptAt, completedAt, timestamp,
      runId, input.runnerId, row.lease_token_sha256,
    ).run();
  if ((result.meta?.changes ?? 0) !== 1) return errorResponse("LEASE_NOT_OWNED", 409, null);
  await insertEventStatement(
    env, runId, input.status, input.progress, input.currentStep, input.message, input.error, timestamp,
  ).run();
  const updated = await runById(env, runId);
  if (!updated) return errorResponse("RUN_NOT_FOUND", 404, null);
  const projection = await completeRun(env, updated, "public");
  return projection ? json(projection) : errorResponse("RUN_REVIEW_NOT_FOUND", 500, null);
};

const releaseRunnerAuthorized = (request: Request, env: Env): Promise<boolean> =>
  hasBearer(request, [
    env.OPERATOR_RELEASE_TOKEN,
    env.OPERATOR_RELEASE_TOKEN_SECONDARY,
    env.OPERATOR_RUNNER_TOKEN,
    env.OPERATOR_RUNNER_TOKEN_SECONDARY,
  ]);

const claimRelease = async (request: Request, env: Env): Promise<Response> => {
  const input = parseClaim(await readJson(request));
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const timestamp = now();
    const candidate = await env.DB.prepare(`SELECT requests.*
      FROM operator_release_requests AS requests
      INNER JOIN operator_release_executions AS execution ON execution.request_id = requests.request_id
      WHERE requests.status IN ('queued', 'claimed')
        AND execution.next_attempt_at <= ?
        AND (execution.lease_expires_at IS NULL OR execution.lease_expires_at <= ?)
      ORDER BY requests.created_at ASC LIMIT 1`).bind(
      timestamp, timestamp,
    ).first<ReleaseRequestRow>();
    if (!candidate) return new Response(null, { status: 204, headers: responseHeaders(null) });

    const leaseToken = crypto.randomUUID();
    const leaseHash = await sha256(leaseToken);
    const leaseExpiresAt = new Date(Date.now() + input.leaseSeconds * 1_000).toISOString();
    const claimed = await env.DB.prepare(`UPDATE operator_release_executions SET
      runner_id = ?, lease_token_sha256 = ?, lease_expires_at = ?, next_attempt_at = ?,
      attempt_count = attempt_count + 1, error_code = NULL, updated_at = ?
      WHERE request_id = ? AND next_attempt_at <= ?
        AND (lease_expires_at IS NULL OR lease_expires_at <= ?)`).bind(
      input.runnerId, leaseHash, leaseExpiresAt, leaseExpiresAt, timestamp,
      candidate.request_id, timestamp, timestamp,
    ).run();
    if ((claimed.meta?.changes ?? 0) !== 1) continue;
    await env.DB.batch([
      env.DB.prepare(`UPDATE operator_release_requests SET status = 'claimed', updated_at = ?
        WHERE request_id = ? AND status IN ('queued', 'claimed')`).bind(timestamp, candidate.request_id),
      env.DB.prepare(`INSERT INTO operator_release_events
        (request_id, timestamp, status, platform_results_json, message, error_code)
        SELECT ?, ?, 'claimed', platform_results_json, 'Veröffentlichungsauftrag übernommen.', NULL
        FROM operator_release_executions WHERE request_id = ?`).bind(
        candidate.request_id, timestamp, candidate.request_id,
      ),
    ]);

    const [execution, row, review] = await Promise.all([
      releaseExecutionByRequestId(env, candidate.request_id),
      runById(env, candidate.run_id),
      reviewByRunId(env, candidate.run_id),
    ]);
    if (!execution || !row || !review || review.preview_sha256 !== candidate.preview_sha256) {
      return errorResponse("RELEASE_CLAIM_INVALID", 500, null);
    }
    const platforms = JSON.parse(execution.platforms_json) as unknown;
    if (
      !Array.isArray(platforms) || platforms.length === 0 ||
      platforms.some((platform) => !CALENDAR_PLATFORMS.includes(platform as CalendarPlatform))
    ) return errorResponse("RELEASE_CLAIM_INVALID", 500, null);
    return json({
      request: {
        requestId: candidate.request_id,
        runId: candidate.run_id,
        providerRunId: row.provider_run_id,
        releaseLabel: review.release_label,
        previewSha256: candidate.preview_sha256,
        videoRevision: candidate.video_revision,
        platforms,
        previewUrl: `/v1/release-runner/requests/${candidate.request_id}/preview`,
      },
      leaseToken,
    });
  }
  return new Response(null, { status: 204, headers: responseHeaders(null) });
};

const ownsReleaseLease = async (
  execution: ReleaseExecutionRow,
  runnerId: string,
  leaseToken: string,
  timestamp: string,
): Promise<boolean> =>
  execution.runner_id === runnerId && Boolean(execution.lease_token_sha256) &&
  await secureEqual(await sha256(leaseToken), execution.lease_token_sha256 ?? "") &&
  Boolean(execution.lease_expires_at) && (execution.lease_expires_at ?? "") >= timestamp;

const serveReleasePreview = async (env: Env, requestId: string): Promise<Response> => {
  const release = await env.DB.prepare(
    "SELECT * FROM operator_release_requests WHERE request_id = ?",
  ).bind(requestId).first<ReleaseRequestRow>();
  if (!release) return errorResponse("RELEASE_NOT_FOUND", 404, null);
  const review = await reviewByRunId(env, release.run_id);
  if (
    !review?.preview_object_key || review.preview_sha256 !== release.preview_sha256 ||
    review.video_revision !== release.video_revision ||
    review.video_approval_status !== "approved"
  ) return errorResponse("RELEASE_PREVIEW_NOT_APPROVED", 409, null);
  const object = await env.PREVIEWS.get(review.preview_object_key);
  if (!object) return errorResponse("PREVIEW_NOT_FOUND", 404, null);
  const headers = responseHeaders(null, review.preview_content_type ?? "video/mp4");
  headers.set("content-length", String(review.preview_size_bytes ?? object.size));
  headers.set("etag", object.etag);
  headers.set("x-preview-sha256", release.preview_sha256);
  return new Response(object.body, { status: 200, headers });
};

interface ReleaseUpdate {
  readonly runnerId: string;
  readonly leaseToken: string;
  readonly platforms: CalendarPlatforms;
  readonly message: string | null;
  readonly error: string | null;
}

const parseReleaseUpdate = (value: unknown): ReleaseUpdate => {
  if (!isRecord(value) || !exactKeys(value, ["runnerId", "leaseToken", "platforms", "message", "error"])) {
    throw new Error("INVALID_RELEASE_UPDATE");
  }
  const runnerId = safeText(value.runnerId, 100);
  const leaseToken = safeText(value.leaseToken, 200);
  const message = value.message === null ? null : safeMessage(value.message);
  const error = value.error === null ? null : safeErrorCode(value.error);
  if (
    !runnerId || !leaseToken || (value.message !== null && !message) ||
    (value.error !== null && !error)
  ) throw new Error("INVALID_RELEASE_UPDATE");
  return { runnerId, leaseToken, platforms: parsePlatforms(value.platforms), message, error };
};

const updateRelease = async (
  request: Request,
  env: Env,
  requestId: string,
): Promise<Response> => {
  const input = parseReleaseUpdate(await readJson(request));
  const [release, execution] = await Promise.all([
    env.DB.prepare("SELECT * FROM operator_release_requests WHERE request_id = ?")
      .bind(requestId).first<ReleaseRequestRow>(),
    releaseExecutionByRequestId(env, requestId),
  ]);
  if (!release || !execution) return errorResponse("RELEASE_NOT_FOUND", 404, null);
  const timestamp = now();
  if (!await ownsReleaseLease(execution, input.runnerId, input.leaseToken, timestamp)) {
    return errorResponse("LEASE_NOT_OWNED", 409, null);
  }
  const selected = JSON.parse(execution.platforms_json) as unknown;
  if (!Array.isArray(selected) || selected.length === 0) {
    return errorResponse("RELEASE_CONFIGURATION_INVALID", 500, null);
  }
  for (const platform of CALENDAR_PLATFORMS) {
    const expected = selected.includes(platform);
    const state = input.platforms[platform];
    if ((!expected && state.status !== "missing") || (expected && state.status === "missing")) {
      return errorResponse("RELEASE_PLATFORM_MISMATCH", 409, null);
    }
    if (state.status === "published" && !state.publicUrl) {
      return errorResponse("PUBLIC_URL_REQUIRED", 409, null);
    }
  }
  const selectedStates = selected.map((platform) => input.platforms[platform as CalendarPlatform]);
  const allPublished = selectedStates.every((state) => state.status === "published");
  const anyFailed = selectedStates.some((state) => state.status === "failed");
  if (anyFailed && !input.error) return errorResponse("RELEASE_ERROR_REQUIRED", 409, null);
  const status: ReleaseRequestRow["status"] = allPublished ? "completed" : anyFailed ? "failed" : "queued";
  const nextAttemptAt = allPublished || anyFailed
    ? timestamp
    : new Date(Date.now() + WAITING_RECHECK_SECONDS * 1_000).toISOString();
  const resultsJson = JSON.stringify(input.platforms);
  const calendarEntryId = `release:${release.run_id}`;
  await env.DB.batch([
    env.DB.prepare(`UPDATE operator_release_requests SET status = ?, updated_at = ?
      WHERE request_id = ? AND status = 'claimed'`).bind(status, timestamp, requestId),
    env.DB.prepare(`UPDATE operator_release_executions SET
      platform_results_json = ?, runner_id = NULL, lease_token_sha256 = NULL,
      lease_expires_at = NULL, next_attempt_at = ?, error_code = ?,
      completed_at = ?, updated_at = ? WHERE request_id = ?`).bind(
      resultsJson, nextAttemptAt, input.error, allPublished ? timestamp : null, timestamp, requestId,
    ),
    env.DB.prepare(`UPDATE operator_calendar_entries SET platforms_json = ?, updated_at = ?
      WHERE entry_id = ?`).bind(resultsJson, timestamp, calendarEntryId),
    env.DB.prepare(`UPDATE operator_calendar_reviews SET
      final_release_approved = ?, updated_at = ? WHERE entry_id = ?`).bind(
      allPublished ? 1 : 0, timestamp, calendarEntryId,
    ),
    env.DB.prepare(`UPDATE operator_script_style_examples_v2 SET
      trust_level = CASE WHEN ? = 1 THEN 'high_confidence' ELSE trust_level END,
      updated_at = CASE WHEN ? = 1 THEN ? ELSE updated_at END
      WHERE script_sha256 = (
        SELECT submitted_script_sha256 FROM operator_script_origins_v2 WHERE run_id = ?
      )`).bind(
      allPublished ? 1 : 0, allPublished ? 1 : 0, timestamp, release.run_id,
    ),
    env.DB.prepare(`INSERT INTO operator_release_events
      (request_id, timestamp, status, platform_results_json, message, error_code)
      VALUES (?, ?, ?, ?, ?, ?)`).bind(
      requestId, timestamp, status, resultsJson, input.message, input.error,
    ),
  ]);
  const row = await runById(env, release.run_id);
  const projection = row ? await completeRun(env, row, "operator") : null;
  return projection ? json(projection) : errorResponse("RUN_NOT_FOUND", 404, null);
};

interface ByteRange {
  readonly offset: number;
  readonly length: number;
  readonly end: number;
}

const byteRange = (header: string | null, size: number): ByteRange | null | "invalid" => {
  if (!header) return null;
  const match = header.match(/^bytes=(\d*)-(\d*)$/u);
  if (!match || (match[1] === "" && match[2] === "")) return "invalid";
  if (match[1] === "") {
    const suffix = Number(match[2]);
    if (!Number.isInteger(suffix) || suffix < 1) return "invalid";
    const length = Math.min(suffix, size);
    return { offset: size - length, length, end: size - 1 };
  }
  const offset = Number(match[1]);
  const requestedEnd = match[2] === "" ? size - 1 : Number(match[2]);
  if (
    !Number.isInteger(offset) || !Number.isInteger(requestedEnd) ||
    offset < 0 || requestedEnd < offset || offset >= size
  ) return "invalid";
  const end = Math.min(requestedEnd, size - 1);
  return { offset, length: end - offset + 1, end };
};

const servePreview = async (
  request: Request,
  env: Env,
  runId: string,
  origin: string | null,
): Promise<Response> => {
  const review = await reviewByRunId(env, runId);
  if (!review?.preview_object_key || !review.preview_size_bytes) {
    return errorResponse("PREVIEW_NOT_FOUND", 404, origin);
  }
  const range = byteRange(request.headers.get("range"), review.preview_size_bytes);
  if (range === "invalid") {
    const headers = responseHeaders(origin, "video/mp4");
    headers.set("content-range", `bytes */${review.preview_size_bytes}`);
    return new Response(null, { status: 416, headers });
  }
  const object = await env.PREVIEWS.get(
    review.preview_object_key,
    range ? { range: { offset: range.offset, length: range.length } } : undefined,
  );
  if (!object) return errorResponse("PREVIEW_NOT_FOUND", 404, origin);
  const headers = responseHeaders(origin, review.preview_content_type ?? "video/mp4");
  headers.set("accept-ranges", "bytes");
  headers.set("content-length", String(range?.length ?? review.preview_size_bytes));
  headers.set("etag", object.etag);
  if (range) headers.set("content-range", `bytes ${range.offset}-${range.end}/${review.preview_size_bytes}`);
  return new Response(object.body, { status: range ? 206 : 200, headers });
};

const httpsUrl = (value: unknown): string | undefined => {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value.length > 2_048) throw new Error("INVALID_CALENDAR_ENTRY");
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password) throw new Error("INVALID_CALENDAR_ENTRY");
    return parsed.href;
  } catch {
    throw new Error("INVALID_CALENDAR_ENTRY");
  }
};

const parsePlatforms = (value: unknown): CalendarPlatforms => {
  if (!isRecord(value) || !exactKeys(value, CALENDAR_PLATFORMS) || Object.keys(value).length !== CALENDAR_PLATFORMS.length) {
    throw new Error("INVALID_CALENDAR_ENTRY");
  }
  const entries = CALENDAR_PLATFORMS.map((platform): readonly [CalendarPlatform, PlatformState] => {
    const raw = value[platform];
    if (!isRecord(raw) || !exactKeys(raw, ["status", "publicUrl"])) throw new Error("INVALID_CALENDAR_ENTRY");
    const status = raw.status as CalendarStatus;
    if (!CALENDAR_STATUSES.includes(status)) throw new Error("INVALID_CALENDAR_ENTRY");
    const publicUrl = httpsUrl(raw.publicUrl);
    return [platform, { status, ...(publicUrl ? { publicUrl } : {}) }];
  });
  return Object.fromEntries(entries) as CalendarPlatforms;
};

interface CalendarInput {
  readonly id: string;
  readonly runId?: string;
  readonly contentId: string;
  readonly title: string;
  readonly releaseLabel?: string;
  readonly videoApproved: boolean;
  readonly finalReleaseApproved: boolean;
  readonly scheduledAt: string;
  readonly platforms: CalendarPlatforms;
}

const parseCalendarInput = (value: unknown): CalendarInput => {
  if (!isRecord(value) || !exactKeys(value, [
    "id", "runId", "contentId", "title", "releaseLabel",
    "videoApproved", "finalReleaseApproved", "scheduledAt", "platforms",
  ])) {
    throw new Error("INVALID_CALENDAR_ENTRY");
  }
  const id = safeText(value.id, 180);
  const runId = value.runId === undefined ? undefined : safeText(value.runId, 180) ?? undefined;
  const contentId = safeText(value.contentId, 200);
  const title = safeText(value.title, 140);
  const releaseLabel = value.releaseLabel === undefined
    ? undefined
    : safeText(value.releaseLabel, 20) ?? undefined;
  const videoApproved = value.videoApproved === true;
  const finalReleaseApproved = value.finalReleaseApproved === true;
  const scheduledAt = safeText(value.scheduledAt, 40);
  if (
    !id || !/^[A-Za-z0-9._:-]{4,180}$/u.test(id) ||
    (runId !== undefined && !/^[A-Za-z0-9._:-]{4,180}$/u.test(runId)) ||
    !contentId || !/^[A-Za-z0-9._:-]{4,200}$/u.test(contentId) ||
    (releaseLabel !== undefined && !/^\d{4}\.\d{2}$/u.test(releaseLabel)) ||
    !title || !scheduledAt || !Number.isFinite(Date.parse(scheduledAt))
  ) throw new Error("INVALID_CALENDAR_ENTRY");
  return {
    id,
    ...(runId ? { runId } : {}),
    contentId,
    title,
    ...(releaseLabel ? { releaseLabel } : {}),
    videoApproved,
    finalReleaseApproved,
    scheduledAt: new Date(scheduledAt).toISOString(),
    platforms: parsePlatforms(value.platforms),
  };
};

const publicCalendarEntry = (row: CalendarRow): Record<string, unknown> => ({
  id: row.entry_id,
  runId: row.run_id ?? undefined,
  contentId: row.content_id,
  title: row.title,
  releaseLabel: row.release_label ?? undefined,
  videoApproved: row.video_approved === 1,
  finalReleaseApproved: row.final_release_approved === 1,
  scheduledAt: row.scheduled_at,
  platforms: parsePlatforms(JSON.parse(row.platforms_json) as unknown),
});

const upsertCalendar = async (request: Request, env: Env, origin: string | null): Promise<Response> => {
  const entry = parseCalendarInput(await readJson(request));
  const timestamp = now();
  await env.DB.prepare(`INSERT INTO operator_calendar_entries
    (entry_id, content_id, title, scheduled_at, platforms_json, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(entry_id) DO UPDATE SET content_id = excluded.content_id, title = excluded.title,
      scheduled_at = excluded.scheduled_at, platforms_json = excluded.platforms_json, updated_at = excluded.updated_at`).bind(
    entry.id, entry.contentId, entry.title, entry.scheduledAt, JSON.stringify(entry.platforms), timestamp, timestamp,
  ).run();
  await env.DB.prepare(`INSERT INTO operator_calendar_reviews
    (entry_id, run_id, release_label, video_approved, final_release_approved, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(entry_id) DO UPDATE SET
      run_id = excluded.run_id, release_label = excluded.release_label,
      video_approved = excluded.video_approved,
      final_release_approved = excluded.final_release_approved,
      updated_at = excluded.updated_at`).bind(
    entry.id, entry.runId ?? null, entry.releaseLabel ?? null,
    entry.videoApproved ? 1 : 0, entry.finalReleaseApproved ? 1 : 0, timestamp,
  ).run();
  const row = await env.DB.prepare(`SELECT entries.*, reviews.run_id, reviews.release_label,
      reviews.video_approved, reviews.final_release_approved
    FROM operator_calendar_entries AS entries
    LEFT JOIN operator_calendar_reviews AS reviews ON reviews.entry_id = entries.entry_id
    WHERE entries.entry_id = ?`).bind(entry.id).first<CalendarRow>();
  return row ? json(publicCalendarEntry(row), 200, origin) : errorResponse("CALENDAR_WRITE_FAILED", 500, origin);
};

const calendar = async (url: URL, env: Env, origin: string | null): Promise<Response> => {
  const from = url.searchParams.get("from");
  const to = url.searchParams.get("to");
  const fromMs = Date.parse(from ?? "");
  const toMs = Date.parse(to ?? "");
  if (!Number.isFinite(fromMs) || !Number.isFinite(toMs) || fromMs >= toMs || toMs - fromMs > 31 * 86_400_000) {
    return errorResponse("INVALID_CALENDAR_RANGE", 400, origin);
  }
  const rows = await env.DB.prepare(`SELECT entries.*, reviews.run_id, reviews.release_label,
      reviews.video_approved, reviews.final_release_approved
    FROM operator_calendar_entries AS entries
    LEFT JOIN operator_calendar_reviews AS reviews ON reviews.entry_id = entries.entry_id
    WHERE entries.scheduled_at >= ? AND entries.scheduled_at < ?
    ORDER BY entries.scheduled_at ASC`).bind(
    new Date(fromMs).toISOString(), new Date(toMs).toISOString(),
  ).all<CalendarRow>();
  return json({ entries: (rows.results ?? []).map(publicCalendarEntry) }, 200, origin);
};

const dashboardDataBaseUrl = (env: Env): URL | null => {
  const value = env.DASHBOARD_DATA_BASE_URL?.trim();
  if (!value) return null;
  try {
    const url = new URL(value.endsWith("/") ? value : `${value}/`);
    if (
      url.protocol !== "https:" || url.username || url.password ||
      url.search || url.hash
    ) return null;
    return url;
  } catch {
    return null;
  }
};

const boundedResponseBytes = async (response: Response, maximumBytes: number): Promise<Uint8Array> => {
  const contentLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maximumBytes) throw new Error("DASHBOARD_DATA_TOO_LARGE");
  if (!response.body) throw new Error("DASHBOARD_DATA_EMPTY");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > maximumBytes) {
        await reader.cancel();
        throw new Error("DASHBOARD_DATA_TOO_LARGE");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  if (size === 0) throw new Error("DASHBOARD_DATA_EMPTY");
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
};

const validDashboardData = (bytes: Uint8Array, fileName: string): boolean => {
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
    if (!isRecord(value) || value.schemaVersion !== DASHBOARD_DATA_SCHEMA_VERSIONS[fileName]) return false;
    return typeof value.generatedAt === "string" && Number.isFinite(Date.parse(value.generatedAt));
  } catch {
    return false;
  }
};

interface RetentionPhraseRow {
  readonly run_id: string;
  readonly provider_run_id: string | null;
  readonly phrase_id: string;
  readonly formulation_key: string;
  readonly phrase_type: string;
  readonly text: string;
  readonly position_index: number;
  readonly start_seconds: number | null;
  readonly end_seconds: number | null;
}

const publicationContentIds = (contentOperations: unknown): ReadonlyMap<string, string> => {
  const root = isRecord(contentOperations) ? contentOperations : null;
  const publications = Array.isArray(root?.publications) ? root.publications : [];
  const result = new Map<string, string>();
  for (const value of publications) {
    if (!isRecord(value) || value.platform !== "youtube") continue;
    const runId = safeText(value.runId, 220);
    const contentId = safeText(value.contentId, 100);
    if (
      !runId || !contentId ||
      !/^flaggenbande-[a-f0-9]{64}$/u.test(contentId)
    ) continue;
    result.set(runId, contentId);
  }
  return result;
};

const storedPhraseTimelines = async (
  env: Env,
  contentOperations: unknown,
): Promise<{ readonly timelines: readonly Record<string, unknown>[] }> => {
  const publications = publicationContentIds(contentOperations);
  if (publications.size === 0) return { timelines: [] };
  const rows = await env.DB.prepare(`SELECT
      manifests.run_id,
      runs.provider_run_id,
      run_phrases.phrase_id,
      phrases.formulation_key,
      phrases.phrase_type,
      phrases.text,
      phrases.position_index,
      run_phrases.start_seconds,
      run_phrases.end_seconds
    FROM operator_run_script_manifests AS manifests
    INNER JOIN operator_production_runs AS runs
      ON runs.run_id = manifests.run_id
    INNER JOIN operator_run_script_phrases AS run_phrases
      ON run_phrases.run_id = manifests.run_id
    INNER JOIN operator_script_phrases AS phrases
      ON phrases.script_sha256 = run_phrases.script_sha256
      AND phrases.phrase_id = run_phrases.phrase_id
    ORDER BY manifests.run_id, phrases.position_index`)
    .all<RetentionPhraseRow>();
  const grouped = new Map<string, RetentionPhraseRow[]>();
  for (const row of rows.results ?? []) {
    const current = grouped.get(row.run_id) ?? [];
    current.push(row);
    grouped.set(row.run_id, current);
  }
  const timelines = [...grouped.entries()].flatMap(([runId, phrases]) => {
    const providerRunId = phrases[0]?.provider_run_id ?? runId;
    const publication = [...publications.entries()].find(([publicationRunId]) =>
      publicationRunId === providerRunId ||
      publicationRunId.startsWith(`upload-${providerRunId}-`)
    );
    if (!publication) return [];
    return [{
      runId,
      contentId: publication[1],
      phrases: phrases.map((phrase) => ({
        phraseId: phrase.phrase_id,
        formulationKey: phrase.formulation_key,
        type: phrase.phrase_type,
        text: phrase.text,
        position: phrase.position_index,
        startSeconds: phrase.start_seconds,
        endSeconds: phrase.end_seconds,
      })),
    }];
  });
  return { timelines };
};

const researchRecommendations = async (
  env: Env,
  origin: string | null,
): Promise<Response> => {
  const baseUrl = dashboardDataBaseUrl(env);
  if (!baseUrl) {
    return json(buildResearchRecommendationFeed(null, now()), 200, origin);
  }
  try {
    const loadDataFile = async (
      fileName: "dashboard.json" | "content-operations.json",
    ): Promise<unknown | null> => {
      const upstream = await fetch(new URL(fileName, baseUrl), {
        headers: { Accept: "application/json" },
        cf: { cacheEverything: true, cacheTtl: 300 },
      } as RequestInit);
      if (
        !upstream.ok ||
        !upstream.headers.get("content-type")?.toLowerCase().includes("application/json")
      ) return null;
      const bytes = await boundedResponseBytes(upstream, MAX_DASHBOARD_DATA_BYTES);
      if (!validDashboardData(bytes, fileName)) return null;
      return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
    };
    const [dashboard, contentOperations] = await Promise.all([
      loadDataFile("dashboard.json"),
      loadDataFile("content-operations.json"),
    ]);
    if (!dashboard) {
      return json(buildResearchRecommendationFeed(null, now()), 200, origin);
    }
    const generatedAt = isRecord(dashboard) && typeof dashboard.generatedAt === "string"
      ? dashboard.generatedAt
      : now();
    const phraseTimelines = await storedPhraseTimelines(env, contentOperations);
    return json(
      buildResearchRecommendationFeed(
        dashboard,
        generatedAt,
        contentOperations,
        phraseTimelines,
      ),
      200,
      origin,
    );
  } catch {
    return json(buildResearchRecommendationFeed(null, now()), 200, origin);
  }
};

const serveCurrentDashboardData = async (
  request: Request,
  env: Env,
  origin: string | null,
): Promise<Response | null> => {
  if (request.method !== "GET") return null;
  const requestUrl = new URL(request.url);
  const match = requestUrl.pathname.match(/^\/data\/([a-z-]+\.json)$/u);
  const fileName = match?.[1];
  if (!fileName || !DASHBOARD_DATA_FILES.has(fileName)) return null;

  const baseUrl = dashboardDataBaseUrl(env);
  if (!baseUrl) return env.ASSETS ? env.ASSETS.fetch(request) : null;
  try {
    const upstreamUrl = new URL(fileName, baseUrl);
    const upstream = await fetch(upstreamUrl, {
      headers: { Accept: "application/json" },
      cf: { cacheEverything: true, cacheTtl: 300 },
    } as RequestInit);
    if (!upstream.ok || !upstream.headers.get("content-type")?.toLowerCase().includes("application/json")) {
      return env.ASSETS ? env.ASSETS.fetch(request) : null;
    }
    const bytes = await boundedResponseBytes(upstream, MAX_DASHBOARD_DATA_BYTES);
    if (!validDashboardData(bytes, fileName)) return env.ASSETS ? env.ASSETS.fetch(request) : null;
    const headers = responseHeaders(origin);
    headers.set("x-flaggenbande-data-source", "hourly-github-pages");
    return new Response(bytes, { status: 200, headers });
  } catch {
    return env.ASSETS ? env.ASSETS.fetch(request) : null;
  }
};

const preflight = (origin: string): Response => {
  const headers = responseHeaders(origin);
  headers.set("access-control-allow-methods", "GET,POST,PUT,OPTIONS");
  headers.set("access-control-allow-headers", "Authorization,Content-Type,Range");
  headers.set("access-control-max-age", "600");
  return new Response(null, { status: 204, headers });
};

const serveDashboardAsset = async (request: Request, env: Env): Promise<Response | null> => {
  if (!env.ASSETS) return null;
  const response = await env.ASSETS.fetch(request);
  const contentType = response.headers.get("content-type")?.toLocaleLowerCase("en") ?? "";
  if (!contentType.includes("text/html")) return response;
  const headers = new Headers(response.headers);
  headers.set("cache-control", "no-store, max-age=0, must-revalidate");
  headers.set("pragma", "no-cache");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
};

const operatorAuthorized = async (request: Request, env: Env): Promise<boolean> =>
  await hasBearer(request, [env.OPERATOR_API_TOKEN, env.OPERATOR_API_TOKEN_SECONDARY]) ||
  await hasCloudflareAccessJwt(request, env);

const runnerAuthorized = (request: Request, env: Env): Promise<boolean> =>
  hasBearer(request, [env.OPERATOR_RUNNER_TOKEN, env.OPERATOR_RUNNER_TOKEN_SECONDARY]);

const handle = async (request: Request, env: Env): Promise<Response> => {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") {
    return json({ status: "ok", service: "flaggenbande-operator-api" });
  }

  let origin: string | null;
  try {
    origin = allowedRequestOrigin(request, env);
  } catch {
    return errorResponse("SERVER_CONFIGURATION_ERROR", 500, null);
  }
  if (origin === "") return errorResponse("ORIGIN_NOT_ALLOWED", 403, null);
  if (request.method === "OPTIONS") return origin ? preflight(origin) : errorResponse("ORIGIN_REQUIRED", 403, null);

  const publicRunMatch = request.method === "GET"
    ? url.pathname.match(/^\/v1\/public\/runs\/(video-[a-f0-9]{24})$/u)
    : null;
  if (request.method === "GET" && url.pathname === "/v1/public/runs") {
    return listRuns(url, env, origin, "public");
  }
  if (publicRunMatch) return getRun(env, publicRunMatch[1], origin, "public");
  if (request.method === "GET" && url.pathname === "/v1/public/calendar") {
    return calendar(url, env, origin);
  }

  const isProductionRunnerRoute = url.pathname.startsWith("/v1/runner/");
  const isReleaseRunnerRoute = url.pathname.startsWith("/v1/release-runner/");
  const authorized = isProductionRunnerRoute
    ? await runnerAuthorized(request, env)
    : isReleaseRunnerRoute
      ? await releaseRunnerAuthorized(request, env)
      : await operatorAuthorized(request, env);
  if (!authorized) return errorResponse("NOT_AUTHORIZED", 401, origin);

  if (request.method === "POST" && url.pathname === "/v1/script-drafts") {
    return createScriptDraft(request, env, origin);
  }
  if (request.method === "GET" && url.pathname === "/v1/research/recommendations") {
    return researchRecommendations(env, origin);
  }
  if (request.method === "POST" && url.pathname === "/v1/runs") return createRun(request, env, origin);
  if (request.method === "GET" && url.pathname === "/v1/runs") return listRuns(url, env, origin, "operator");
  const runMatch = url.pathname.match(/^\/v1\/runs\/(video-[a-f0-9]{24})$/u);
  if (request.method === "GET" && runMatch) return getRun(env, runMatch[1], origin, "operator");
  const scriptApprovalMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runs\/(video-[a-f0-9]{24})\/approve-script$/u)
    : null;
  if (scriptApprovalMatch) return approveScript(request, env, scriptApprovalMatch[1], origin);
  const retryMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runs\/(video-[a-f0-9]{24})\/retry$/u)
    : null;
  if (retryMatch) return retryRun(env, retryMatch[1], origin);
  const videoApprovalMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runs\/(video-[a-f0-9]{24})\/approve-video$/u)
    : null;
  if (videoApprovalMatch) return approveVideo(request, env, videoApprovalMatch[1], origin);
  const previewMatch = request.method === "GET"
    ? url.pathname.match(/^\/v1\/runs\/(video-[a-f0-9]{24})\/preview$/u)
    : null;
  if (previewMatch) return servePreview(request, env, previewMatch[1], origin);
  if (request.method === "GET" && url.pathname === "/v1/calendar") return calendar(url, env, origin);
  if (request.method === "POST" && url.pathname === "/v1/calendar") return upsertCalendar(request, env, origin);
  if (request.method === "POST" && url.pathname === "/v1/runner/claim") return claimRun(request, env);
  const previewUploadMatch = request.method === "PUT"
    ? url.pathname.match(/^\/v1\/runner\/runs\/(video-[a-f0-9]{24})\/preview$/u)
    : null;
  if (previewUploadMatch) return uploadPreview(request, env, previewUploadMatch[1]);
  const statusMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runner\/runs\/(video-[a-f0-9]{24})\/status$/u)
    : null;
  if (statusMatch) return updateFromRunner(request, env, statusMatch[1]);
  const analysisManifestMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runner\/runs\/(video-[a-f0-9]{24})\/analysis-manifest$/u)
    : null;
  if (analysisManifestMatch) {
    return uploadAnalysisManifest(request, env, analysisManifestMatch[1]);
  }
  if (request.method === "POST" && url.pathname === "/v1/release-runner/claim") {
    return claimRelease(request, env);
  }
  const releasePreviewMatch = request.method === "GET"
    ? url.pathname.match(/^\/v1\/release-runner\/requests\/(release-[a-f0-9]{24})\/preview$/u)
    : null;
  if (releasePreviewMatch) return serveReleasePreview(env, releasePreviewMatch[1]);
  const releaseStatusMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/release-runner\/requests\/(release-[a-f0-9]{24})\/status$/u)
    : null;
  if (releaseStatusMatch) return updateRelease(request, env, releaseStatusMatch[1]);
  const dashboardData = await serveCurrentDashboardData(request, env, origin);
  if (dashboardData) return dashboardData;
  if (request.method === "GET" && env.ASSETS && !url.pathname.startsWith("/v1/")) {
    return await serveDashboardAsset(request, env) ?? errorResponse("NOT_FOUND", 404, origin);
  }
  return errorResponse("NOT_FOUND", 404, origin);
};

const safeClientErrors = new Map<string, number>([
  ["CONTENT_TYPE_JSON_REQUIRED", 415],
  ["REQUEST_BODY_TOO_LARGE", 413],
  ["INVALID_JSON", 400],
  ["INVALID_VIDEO_RUN_INPUT", 400],
  ["UNSUPPORTED_PRODUCTION_ROUND_COUNT", 400],
  ["INVALID_SCRIPT_DRAFT_INPUT", 400],
  ["INVALID_CLAIM", 400],
  ["INVALID_RUNNER_UPDATE", 400],
  ["INVALID_ANALYSIS_MANIFEST", 400],
  ["INVALID_CALENDAR_ENTRY", 400],
  ["INVALID_SCRIPT_APPROVAL", 400],
  ["INVALID_VIDEO_APPROVAL", 400],
  ["INVALID_PREVIEW", 400],
  ["INVALID_RELEASE_UPDATE", 400],
  ["INVALID_RELEASE_PLATFORMS", 500],
]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = safeClientErrors.get(code);
      let origin: string | null = null;
      try {
        const candidate = allowedRequestOrigin(request, env);
        origin = candidate || null;
      } catch {
        return errorResponse("SERVER_CONFIGURATION_ERROR", 500, null);
      }
      if (error instanceof InvalidVideoRunInputError && error.validation) {
        return json({
          error: code,
          issues: error.validation.details,
          metrics: {
            spokenWordCount: error.validation.spokenWordCount,
            revealCount: error.validation.revealCount,
            plausibleMinimumSeconds: error.validation.plausibleMinimumSeconds,
            plausibleMaximumSeconds: error.validation.plausibleMaximumSeconds,
          },
        }, 400, origin);
      }
      return status
        ? errorResponse(code, status, origin)
        : errorResponse("INTERNAL_SERVER_ERROR", 500, origin);
    }
  },
};
