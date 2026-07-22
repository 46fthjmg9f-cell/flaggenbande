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

interface Env {
  readonly DB: D1Database;
  readonly DASHBOARD_ORIGINS?: string;
  readonly OPERATOR_API_TOKEN?: string;
  readonly OPERATOR_API_TOKEN_SECONDARY?: string;
  readonly OPERATOR_RUNNER_TOKEN?: string;
  readonly OPERATOR_RUNNER_TOKEN_SECONDARY?: string;
}

type RunStatus = "queued" | "claimed" | "running" | "waiting" | "completed" | "failed";
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

interface CalendarRow {
  readonly entry_id: string;
  readonly content_id: string;
  readonly title: string;
  readonly scheduled_at: string;
  readonly platforms_json: string;
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
const MAX_REQUEST_BYTES = 64 * 1024;
const MIN_LEASE_SECONDS = 30;
const MAX_LEASE_SECONDS = 300;
const WAITING_RECHECK_SECONDS = 30;

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

interface NewRunInput {
  readonly script: string;
  readonly targetDurationSeconds: number;
  readonly clientRequestId?: string;
}

const parseNewRun = (value: unknown): NewRunInput => {
  if (!isRecord(value) || !exactKeys(value, ["script", "targetDurationSeconds", "clientRequestId"])) {
    throw new Error("INVALID_VIDEO_RUN_INPUT");
  }
  const script = typeof value.script === "string" ? normalizeScript(value.script) : "";
  const target = typeof value.targetDurationSeconds === "number"
    ? Number(value.targetDurationSeconds.toFixed(3))
    : Number.NaN;
  const clientRequestId = value.clientRequestId === undefined ? undefined : safeText(value.clientRequestId, 128);
  const revealCount = script.split("\n").filter((line) => line === "(auflösung)").length;
  if (
    script.length < 80 || script.length > 20_000 || revealCount !== 5 ||
    !Number.isFinite(target) || target < 61 || target > 70 ||
    (value.clientRequestId !== undefined && (!clientRequestId || !/^[A-Za-z0-9._:-]{8,128}$/u.test(clientRequestId)))
  ) throw new Error("INVALID_VIDEO_RUN_INPUT");
  return { script, targetDurationSeconds: target, ...(clientRequestId ? { clientRequestId } : {}) };
};

const publicRun = (row: RunRow): Record<string, unknown> => ({
  runId: row.run_id,
  status: row.status,
  progress: row.progress,
  targetDurationSeconds: row.target_duration_seconds,
  currentStep: row.current_step,
  message: row.message,
  error: row.error_code,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const runById = (env: Env, runId: string): Promise<RunRow | null> =>
  env.DB.prepare("SELECT * FROM operator_production_runs WHERE run_id = ?").bind(runId).first<RunRow>();

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
  const canonical = JSON.stringify({
    schemaVersion: "1.0.0",
    language: "de",
    script: input.script,
    targetDurationSeconds: input.targetDurationSeconds,
  });
  const inputSha256 = await sha256(canonical);
  const runId = `video-${inputSha256.slice(0, 24)}`;
  const clientRequestId = input.clientRequestId ?? `dashboard-${inputSha256.slice(0, 32)}`;
  const byRequest = await env.DB.prepare(
    "SELECT * FROM operator_production_runs WHERE client_request_id = ?",
  ).bind(clientRequestId).first<RunRow>();
  if (byRequest) {
    return byRequest.input_sha256 === inputSha256
      ? json(publicRun(byRequest), 200, origin)
      : errorResponse("IDEMPOTENCY_CONFLICT", 409, origin);
  }
  const existing = await env.DB.prepare(
    "SELECT * FROM operator_production_runs WHERE input_sha256 = ?",
  ).bind(inputSha256).first<RunRow>();
  if (existing) return json(publicRun(existing), 200, origin);

  const timestamp = now();
  const message = "Wartet auf lokalen Produktionsrechner.";
  try {
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO operator_production_runs
        (run_id, input_sha256, client_request_id, script, target_duration_seconds, status, progress,
         current_step, message, next_attempt_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'queued', 0, 'script_validation', ?, ?, ?, ?)`).bind(
        runId, inputSha256, clientRequestId, input.script, input.targetDurationSeconds,
        message, timestamp, timestamp, timestamp,
      ),
      insertEventStatement(env, runId, "queued", 0, "script_validation", message, null, timestamp),
    ]);
  } catch {
    const raced = await env.DB.prepare(
      "SELECT * FROM operator_production_runs WHERE input_sha256 = ? OR client_request_id = ? LIMIT 1",
    ).bind(inputSha256, clientRequestId).first<RunRow>();
    if (!raced || raced.input_sha256 !== inputSha256) return errorResponse("IDEMPOTENCY_CONFLICT", 409, origin);
    return json(publicRun(raced), 200, origin);
  }
  const created = await runById(env, runId);
  return created ? json(publicRun(created), 202, origin) : errorResponse("RUN_CREATE_FAILED", 500, origin);
};

const listRuns = async (url: URL, env: Env, origin: string | null): Promise<Response> => {
  const rawLimit = url.searchParams.get("limit") ?? "20";
  const limit = Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) return errorResponse("INVALID_LIMIT", 400, origin);
  const rows = await env.DB.prepare(
    "SELECT * FROM operator_production_runs ORDER BY created_at DESC LIMIT ?",
  ).bind(limit).all<RunRow>();
  return json({ runs: (rows.results ?? []).map(publicRun) }, 200, origin);
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
    return json({
      run: publicRun(claimed),
      command: {
        script: claimed.script,
        targetDurationSeconds: claimed.target_duration_seconds,
        clientRequestId: claimed.client_request_id,
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

const updateFromRunner = async (
  request: Request,
  env: Env,
  runId: string,
): Promise<Response> => {
  const input = parseRunnerUpdate(await readJson(request));
  const row = await runById(env, runId);
  if (!row) return errorResponse("RUN_NOT_FOUND", 404, null);
  const timestamp = now();
  if (
    row.lease_owner !== input.runnerId || !row.lease_token_sha256 ||
    !await secureEqual(await sha256(input.leaseToken), row.lease_token_sha256) ||
    !row.lease_expires_at || row.lease_expires_at < timestamp
  ) return errorResponse("LEASE_NOT_OWNED", 409, null);

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
  return updated ? json(publicRun(updated)) : errorResponse("RUN_NOT_FOUND", 404, null);
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
  readonly contentId: string;
  readonly title: string;
  readonly scheduledAt: string;
  readonly platforms: CalendarPlatforms;
}

const parseCalendarInput = (value: unknown): CalendarInput => {
  if (!isRecord(value) || !exactKeys(value, ["id", "contentId", "title", "scheduledAt", "platforms"])) {
    throw new Error("INVALID_CALENDAR_ENTRY");
  }
  const id = safeText(value.id, 180);
  const contentId = safeText(value.contentId, 200);
  const title = safeText(value.title, 140);
  const scheduledAt = safeText(value.scheduledAt, 40);
  if (
    !id || !/^[A-Za-z0-9._:-]{4,180}$/u.test(id) ||
    !contentId || !/^[A-Za-z0-9._:-]{4,200}$/u.test(contentId) ||
    !title || !scheduledAt || !Number.isFinite(Date.parse(scheduledAt))
  ) throw new Error("INVALID_CALENDAR_ENTRY");
  return { id, contentId, title, scheduledAt: new Date(scheduledAt).toISOString(), platforms: parsePlatforms(value.platforms) };
};

const publicCalendarEntry = (row: CalendarRow): Record<string, unknown> => ({
  id: row.entry_id,
  contentId: row.content_id,
  title: row.title,
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
  const row = await env.DB.prepare(
    "SELECT * FROM operator_calendar_entries WHERE entry_id = ?",
  ).bind(entry.id).first<CalendarRow>();
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
  const rows = await env.DB.prepare(`SELECT * FROM operator_calendar_entries
    WHERE scheduled_at >= ? AND scheduled_at < ? ORDER BY scheduled_at ASC`).bind(
    new Date(fromMs).toISOString(), new Date(toMs).toISOString(),
  ).all<CalendarRow>();
  return json({ entries: (rows.results ?? []).map(publicCalendarEntry) }, 200, origin);
};

const preflight = (origin: string): Response => {
  const headers = responseHeaders(origin);
  headers.set("access-control-allow-methods", "GET,POST,OPTIONS");
  headers.set("access-control-allow-headers", "Authorization,Content-Type");
  headers.set("access-control-max-age", "600");
  return new Response(null, { status: 204, headers });
};

const operatorAuthorized = (request: Request, env: Env): Promise<boolean> =>
  hasBearer(request, [env.OPERATOR_API_TOKEN, env.OPERATOR_API_TOKEN_SECONDARY]);

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

  const isRunnerRoute = url.pathname.startsWith("/v1/runner/");
  const authorized = isRunnerRoute
    ? await runnerAuthorized(request, env)
    : await operatorAuthorized(request, env);
  if (!authorized) return errorResponse("NOT_AUTHORIZED", 401, origin);

  if (request.method === "POST" && url.pathname === "/v1/runs") return createRun(request, env, origin);
  if (request.method === "GET" && url.pathname === "/v1/runs") return listRuns(url, env, origin);
  if (request.method === "GET" && url.pathname === "/v1/calendar") return calendar(url, env, origin);
  if (request.method === "POST" && url.pathname === "/v1/calendar") return upsertCalendar(request, env, origin);
  if (request.method === "POST" && url.pathname === "/v1/runner/claim") return claimRun(request, env);
  const statusMatch = request.method === "POST"
    ? url.pathname.match(/^\/v1\/runner\/runs\/(video-[a-f0-9]{24})\/status$/u)
    : null;
  if (statusMatch) return updateFromRunner(request, env, statusMatch[1]);
  return errorResponse("NOT_FOUND", 404, origin);
};

const safeClientErrors = new Map<string, number>([
  ["CONTENT_TYPE_JSON_REQUIRED", 415],
  ["REQUEST_BODY_TOO_LARGE", 413],
  ["INVALID_JSON", 400],
  ["INVALID_VIDEO_RUN_INPUT", 400],
  ["INVALID_CLAIM", 400],
  ["INVALID_RUNNER_UPDATE", 400],
  ["INVALID_CALENDAR_ENTRY", 400],
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
      return status
        ? errorResponse(code, status, origin)
        : errorResponse("INTERNAL_SERVER_ERROR", 500, origin);
    }
  },
};
