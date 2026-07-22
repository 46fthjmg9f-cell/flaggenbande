interface D1Statement {
  bind(...values: unknown[]): D1Statement;
  run(): Promise<unknown>;
  all<T>(): Promise<{ results?: T[] }>;
  first<T>(): Promise<T | null>;
}

interface D1Database {
  prepare(query: string): D1Statement;
  batch(statements: D1Statement[]): Promise<unknown>;
}
interface ScheduledEvent { readonly scheduledTime: number; }
interface ExportedHandler<T> {
  fetch?(request: Request, env: T): Response | Promise<Response>;
  scheduled?(event: ScheduledEvent, env: T): void | Promise<void>;
}

export interface Env {
  DB: D1Database;
  META_QUEUE_TOKEN: string;
  /** Optional dedicated token for the non-publishing staging lane. */
  UPLOAD_STAGING_TOKEN?: string;
  /** Public expected YouTube destination; used only for server-side idempotency binding. */
  YOUTUBE_CHANNEL_ID?: string;
  /** Only this temporary Cloudflare Pages project may serve staging media. */
  UPLOAD_STAGING_MEDIA_PROJECT?: string;
  ANALYTICS_INGEST_TOKEN?: string;
  /** Preferred Instagram Login token. Never reuse a Facebook Page token here. */
  META_INSTAGRAM_USER_ACCESS_TOKEN?: string;
  /** Transitional alias used by older deployments. */
  META_INSTAGRAM_ACCESS_TOKEN?: string;
  /** Deprecated transitional alias; retained only for zero-downtime migration. */
  META_ACCESS_TOKEN?: string;
  META_INSTAGRAM_ACCOUNT_ID: string;
  META_FACEBOOK_PAGE_ACCESS_TOKEN: string;
  META_FACEBOOK_PAGE_ID: string;
  META_GRAPH_API_VERSION?: string;
  /** Optional: enables deletion of temporary Pages deployments after publication. */
  CLOUDFLARE_API_TOKEN?: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
}

type Platform = "instagram" | "facebook";
type SocialPlatform = Platform | "youtube" | "tiktok";
type JobStatus = "scheduled" | "processing" | "waiting_for_meta" | "published" | "failed";
type PublicationFailureCode =
  | "api_access_blocked"
  | "authentication_failed"
  | "permission_denied"
  | "rate_limited"
  | "media_unavailable"
  | "processing_timeout"
  | "platform_rejected"
  | "unknown";

class MetaApiError extends Error {
  readonly failureCode: PublicationFailureCode;
  readonly retryable: boolean;

  constructor(message: string, failureCode: PublicationFailureCode, retryable: boolean) {
    super(message);
    this.name = "MetaApiError";
    this.failureCode = failureCode;
    this.retryable = retryable;
  }
}
type StagingPlatform = "youtube" | "instagram" | "facebook" | "tiktok";
type StagingMode = "private" | "container_unpublished" | "draft" | "manual_uploaded";
type StagingTransport = "planned" | "uploading" | "processing" | "ready" | "failed" | "expired" | "reconcile_required";
type StagingWorkflow = "ready" | "private_uploaded" | "container_unpublished" | "draft" | "manual_uploaded" | "failed" | "expired" | "reconcile_required" | "safety_violation";
type StagingRunStatus = "planned" | "running" | "partial" | "completed" | "failed" | "expired" | "reconcile_required" | "safety_violation";
type StagingVisibility = "not_created" | "non_public" | "unknown";

interface SocialMetrics {
  readonly views: number | null;
  readonly reach: number | null;
  readonly likes: number | null;
  readonly comments: number | null;
  readonly shares: number | null;
  readonly saves: number | null;
  readonly watchTimeMinutes: number | null;
  readonly averageViewDurationSeconds: number | null;
  readonly averageViewPercentage: number | null;
  readonly followersGained: number | null;
}

interface SocialVideo {
  readonly platformVideoId: string;
  readonly contentId?: string | null;
  readonly title: string;
  readonly description: string;
  readonly publishedAt: string | null;
  readonly url: string | null;
  readonly thumbnailUrl: string | null;
  readonly status: string;
  readonly durationSeconds: number | null;
  readonly metrics: SocialMetrics;
}

interface AnalyticsIngestPayload {
  readonly schemaVersion: 1;
  readonly platform: "youtube" | "tiktok";
  readonly accountName?: string | null;
  readonly collectedAt: string;
  readonly videos: SocialVideo[];
}

interface Metadata {
  readonly title: string;
  readonly description: string;
}

interface Job {
  readonly job_id: string;
  readonly source_video_id: string;
  readonly platform: Platform;
  readonly publish_at: string;
  readonly status: JobStatus;
  readonly metadata_json: string;
  readonly media_url: string;
  readonly media_project: string;
  readonly media_branch: string;
  readonly attempt_count: number;
  readonly platform_video_id: string | null;
  readonly publication_url: string | null;
  readonly container_id: string | null;
  readonly last_error: string | null;
}

interface PublicationFeedJobRow {
  readonly source_video_id: string;
  readonly platform: Platform;
  readonly publish_at: string;
  readonly status: JobStatus;
  readonly last_error: string | null;
  readonly updated_at: string;
  readonly published_at: string | null;
}

interface EnqueuePayload {
  readonly jobId: string;
  readonly sourceVideoId: string;
  readonly platform: Platform;
  readonly publishAt: string;
  readonly metadata: Metadata;
  readonly mediaUrl: string;
  readonly mediaProject: string;
  readonly mediaBranch: string;
}

interface StagingTargetInput {
  readonly platform: StagingPlatform;
  readonly mode: StagingMode;
  readonly accountFingerprint: string;
  readonly idempotencyKey: string;
  readonly transportState: StagingTransport;
  readonly visibilityState: StagingVisibility;
  readonly workflowState: StagingWorkflow;
  readonly publishedAt: null;
  readonly scheduledFor: null;
  readonly publicUrl: null;
}

interface StagingMetadata {
  readonly youtubeTitle: string;
  readonly description: string;
  readonly language: "de";
  readonly hashtags?: readonly string[];
  readonly forbiddenAnswerTerms?: readonly string[];
}

interface StagingRunPayload {
  readonly schemaVersion: 1;
  readonly lane: "non-publishing";
  readonly runId: string;
  readonly contentId: string;
  readonly assetSha256: string;
  readonly metadataSha256: string;
  readonly createdAt: string;
  readonly qualityStatus: "passed";
  readonly publicationAuthorized: false;
  readonly metadata: StagingMetadata;
  readonly targets: readonly StagingTargetInput[];
  readonly executeMeta?: boolean;
  readonly mediaUrl?: string;
  readonly mediaProject?: string;
  readonly mediaBranch?: string;
}

interface StagingRunRow {
  readonly run_id: string;
  readonly content_id: string;
  readonly asset_sha256: string;
  readonly metadata_sha256: string;
  readonly metadata_json: string;
  readonly status: StagingRunStatus;
  readonly quality_status: "passed";
  readonly publication_authorized: 0;
  readonly execution_requested: 0 | 1;
  readonly media_url: string | null;
  readonly media_project: string | null;
  readonly media_branch: string | null;
  readonly created_at: string;
  readonly updated_at: string;
  readonly completed_at: string | null;
  readonly media_cleaned_at: string | null;
}

interface StagingTargetRow {
  readonly run_id: string;
  readonly platform: StagingPlatform;
  readonly mode: StagingMode;
  readonly idempotency_key: string;
  readonly initial_transport_state: "planned" | "ready";
  readonly initial_visibility_state: "not_created" | "unknown";
  readonly initial_workflow_state: "ready" | "manual_uploaded";
  readonly transport_state: StagingTransport;
  readonly visibility_state: StagingVisibility;
  readonly workflow_state: StagingWorkflow;
  readonly remote_object_id: string | null;
  readonly provider_status: string | null;
  readonly expires_at: string | null;
  readonly receipt_sha256: string | null;
  readonly remote_create_started_at: string | null;
  readonly lease_owner: string | null;
  readonly lease_expires_at: string | null;
  readonly last_error: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface StagingReceiptPayload {
  readonly schemaVersion: 1;
  readonly lane: "non-publishing";
  readonly runId: string;
  readonly platform: StagingPlatform;
  readonly idempotencyKey: string;
  readonly claimId: string;
  readonly accountFingerprint: string;
  readonly confirmedAt: string;
  readonly transportState: "ready";
  readonly visibilityState: "non_public";
  readonly workflowState: "private_uploaded" | "container_unpublished" | "draft" | "manual_uploaded";
  readonly remoteObjectId?: string | null;
  readonly providerStatus?: string | null;
  readonly publishedAt: null;
  readonly scheduledFor: null;
  readonly publicUrl: null;
}

interface StagingClaimPayload {
  readonly schemaVersion: 1;
  readonly lane: "non-publishing";
  readonly runId: string;
  readonly platform: "youtube";
  readonly idempotencyKey: string;
}

const json = (value: unknown, status = 200): Response => new Response(JSON.stringify(value), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const now = (): string => new Date().toISOString();

const validPlatform = (value: unknown): value is Platform => value === "instagram" || value === "facebook";

const validPayload = (value: unknown): value is EnqueuePayload => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const item = value as Record<string, unknown>;
  return typeof item.jobId === "string" && typeof item.sourceVideoId === "string" && validPlatform(item.platform) &&
    typeof item.publishAt === "string" && Number.isFinite(Date.parse(item.publishAt)) &&
    typeof item.mediaUrl === "string" && item.mediaUrl.startsWith("https://") &&
    typeof item.mediaProject === "string" && typeof item.mediaBranch === "string" &&
    typeof item.metadata === "object" && item.metadata !== null && !Array.isArray(item.metadata);
};

const stagingPlatforms: readonly StagingPlatform[] = ["youtube", "instagram", "facebook", "tiktok"];
const stagingModes: Readonly<Record<StagingPlatform, StagingMode>> = {
  youtube: "private",
  instagram: "container_unpublished",
  facebook: "draft",
  tiktok: "manual_uploaded",
};
const completedStagingWorkflows: Readonly<Record<StagingPlatform, StagingWorkflow>> = {
  youtube: "private_uploaded",
  instagram: "container_unpublished",
  facebook: "draft",
  tiktok: "manual_uploaded",
};

const recordValue = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const canonicalJson = (value: unknown): string => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (recordValue(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
};

const sha256Hex = async (value: unknown): Promise<string> => {
  const bytes = new TextEncoder().encode(canonicalJson(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
};

const safeHttpsUrl = (value: unknown): value is string => {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
};

const validStagingPayload = (value: unknown): value is StagingRunPayload => {
  if (!recordValue(value)) return false;
  const item = value as Record<string, unknown>;
  if (item.schemaVersion !== 1 || item.lane !== "non-publishing" || item.qualityStatus !== "passed" || item.publicationAuthorized !== false) return false;
  if (typeof item.runId !== "string" || !/^[a-z0-9][a-z0-9_-]{3,119}$/i.test(item.runId)) return false;
  if (typeof item.contentId !== "string" || !/^flaggenbande-[a-f0-9]{64}$/i.test(item.contentId)) return false;
  if (typeof item.assetSha256 !== "string" || !/^[a-f0-9]{64}$/i.test(item.assetSha256)) return false;
  if (typeof item.metadataSha256 !== "string" || !/^[a-f0-9]{64}$/i.test(item.metadataSha256)) return false;
  if (item.contentId.toLowerCase() !== `flaggenbande-${item.assetSha256.toLowerCase()}`) return false;
  if (typeof item.createdAt !== "string" || !Number.isFinite(Date.parse(item.createdAt))) return false;
  if (item.executeMeta !== undefined && typeof item.executeMeta !== "boolean") return false;
  if (!recordValue(item.metadata)) return false;
  const details = item.metadata as Record<string, unknown>;
  if (typeof details.youtubeTitle !== "string" || !details.youtubeTitle.trim() || details.youtubeTitle.length > 100) return false;
  if (typeof details.description !== "string" || !details.description.trim() || details.description.length > 2200 || details.language !== "de") return false;
  if (details.hashtags !== undefined && (!Array.isArray(details.hashtags) || details.hashtags.some((tag) => typeof tag !== "string"))) return false;
  if (details.forbiddenAnswerTerms !== undefined && (!Array.isArray(details.forbiddenAnswerTerms) || details.forbiddenAnswerTerms.some((term) => typeof term !== "string"))) return false;
  if (!Array.isArray(item.targets) || item.targets.length !== stagingPlatforms.length) return false;
  const platforms = new Set<string>();
  const idempotencyKeys = new Set<string>();
  for (const raw of item.targets) {
    if (!recordValue(raw)) return false;
    const target = raw as Record<string, unknown>;
    const platform = target.platform as StagingPlatform;
    if (!stagingPlatforms.includes(platform) || platforms.has(platform) || target.mode !== stagingModes[platform]) return false;
    if (typeof target.accountFingerprint !== "string" || !target.accountFingerprint.trim() || target.accountFingerprint.length > 200) return false;
    if (typeof target.idempotencyKey !== "string" || !/^[a-f0-9]{64}$/i.test(target.idempotencyKey) || idempotencyKeys.has(target.idempotencyKey)) return false;
    if (target.publishedAt !== null || target.scheduledFor !== null || target.publicUrl !== null) return false;
    const validInitialState = platform === "tiktok"
      ? (target.transportState === "planned" && target.workflowState === "ready" && target.visibilityState === "not_created") ||
        (target.transportState === "ready" && target.workflowState === "manual_uploaded" && target.visibilityState === "unknown")
      : target.transportState === "planned" && target.workflowState === "ready" && target.visibilityState === "not_created";
    if (!validInitialState) return false;
    platforms.add(platform);
    idempotencyKeys.add(target.idempotencyKey);
  }
  if (item.executeMeta === true) {
    if (!safeHttpsUrl(item.mediaUrl)) return false;
    if (typeof item.mediaProject !== "string" || !item.mediaProject.trim()) return false;
    if (typeof item.mediaBranch !== "string" || !item.mediaBranch.trim()) return false;
  } else if (item.mediaUrl !== undefined || item.mediaProject !== undefined || item.mediaBranch !== undefined) {
    return false;
  }
  return platforms.size === stagingPlatforms.length;
};

const validStagingHashes = async (payload: StagingRunPayload): Promise<boolean> => {
  if (await sha256Hex(payload.metadata) !== payload.metadataSha256.toLowerCase()) return false;
  const expectedKeys = await Promise.all(payload.targets.map((target) => sha256Hex({
    schemaVersion: 1,
    lane: "non-publishing",
    platform: target.platform,
    accountFingerprint: target.accountFingerprint.trim(),
    assetSha256: payload.assetSha256.toLowerCase(),
    mode: target.mode,
  })));
  return expectedKeys.every((key, index) => key === payload.targets[index].idempotencyKey.toLowerCase());
};

const configuredStagingAccount = (env: Env, platform: StagingPlatform, input: StagingTargetInput): string | null => {
  if (platform === "youtube") return env.YOUTUBE_CHANNEL_ID?.trim() || null;
  if (platform === "instagram") return env.META_INSTAGRAM_ACCOUNT_ID?.trim() || null;
  if (platform === "facebook") return env.META_FACEBOOK_PAGE_ID?.trim() || null;
  return input.accountFingerprint.trim() || null;
};

const serverStagingKeys = async (
  env: Env,
  payload: StagingRunPayload,
): Promise<Map<StagingPlatform, string> | null> => {
  const entries: Array<readonly [StagingPlatform, string]> = [];
  for (const target of payload.targets) {
    const accountId = configuredStagingAccount(env, target.platform, target);
    if (!accountId) return null;
    const accountFingerprint = await sha256Hex({ platform: target.platform, accountId });
    const key = await sha256Hex({
      schemaVersion: 1,
      lane: "non-publishing",
      platform: target.platform,
      accountFingerprint,
      assetSha256: payload.assetSha256.toLowerCase(),
      mode: target.mode,
    });
    entries.push([target.platform, key]);
  }
  return new Map(entries);
};

const validStagingMediaOrigin = (payload: StagingRunPayload, env: Env): boolean => {
  if (payload.executeMeta !== true) return true;
  const expectedProject = env.UPLOAD_STAGING_MEDIA_PROJECT?.trim();
  if (!expectedProject || payload.mediaProject !== expectedProject ||
      !/^upload-test-[a-z0-9][a-z0-9-]{0,50}$/i.test(payload.mediaBranch ?? "")) return false;
  try {
    const url = new URL(payload.mediaUrl!);
    const expectedHost = `${expectedProject}.pages.dev`;
    const validHost = url.hostname === expectedHost || url.hostname.endsWith(`.${expectedHost}`);
    return url.protocol === "https:" && validHost && !url.username && !url.password &&
      !url.search && !url.hash && url.pathname.toLowerCase().endsWith(".mp4");
  } catch {
    return false;
  }
};

const validStagingReceipt = (value: unknown): value is StagingReceiptPayload => {
  if (!recordValue(value)) return false;
  const item = value as Record<string, unknown>;
  if (item.schemaVersion !== 1 || item.lane !== "non-publishing") return false;
  if (typeof item.runId !== "string" || !/^[a-z0-9][a-z0-9_-]{3,119}$/i.test(item.runId)) return false;
  const platform = item.platform as StagingPlatform;
  if (platform !== "youtube" || item.workflowState !== completedStagingWorkflows.youtube) return false;
  if (typeof item.idempotencyKey !== "string" || !/^[a-f0-9]{64}$/i.test(item.idempotencyKey)) return false;
  if (typeof item.claimId !== "string" || !/^[a-f0-9-]{20,100}$/i.test(item.claimId)) return false;
  if (typeof item.accountFingerprint !== "string" || !/^[a-f0-9]{64}$/i.test(item.accountFingerprint)) return false;
  if (typeof item.confirmedAt !== "string" || !Number.isFinite(Date.parse(item.confirmedAt))) return false;
  if (item.transportState !== "ready" || item.visibilityState !== "non_public") return false;
  if (item.publishedAt !== null || item.scheduledFor !== null || item.publicUrl !== null) return false;
  if (item.remoteObjectId !== undefined && item.remoteObjectId !== null &&
      (typeof item.remoteObjectId !== "string" || !item.remoteObjectId.trim() || item.remoteObjectId.length > 300)) return false;
  if (typeof item.remoteObjectId !== "string" || !item.remoteObjectId.trim()) return false;
  return typeof item.providerStatus === "string" && item.providerStatus.toUpperCase() === "PRIVATE";
};

const validStagingClaim = (value: unknown): value is StagingClaimPayload => {
  if (!recordValue(value)) return false;
  const item = value as Record<string, unknown>;
  return item.schemaVersion === 1 && item.lane === "non-publishing" && item.platform === "youtube" &&
    typeof item.runId === "string" && /^[a-z0-9][a-z0-9_-]{3,119}$/i.test(item.runId) &&
    typeof item.idempotencyKey === "string" && /^[a-f0-9]{64}$/i.test(item.idempotencyKey);
};

const ensureStagingSchema = async (env: Env): Promise<void> => {
  const statements = [
    `CREATE TABLE IF NOT EXISTS upload_staging_runs (
      run_id TEXT PRIMARY KEY, content_id TEXT NOT NULL, asset_sha256 TEXT NOT NULL, metadata_sha256 TEXT NOT NULL,
      metadata_json TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('planned', 'running', 'partial', 'completed', 'failed', 'expired', 'reconcile_required', 'safety_violation')),
      quality_status TEXT NOT NULL CHECK (quality_status = 'passed'),
      publication_authorized INTEGER NOT NULL DEFAULT 0 CHECK (publication_authorized = 0),
      execution_requested INTEGER NOT NULL DEFAULT 0 CHECK (execution_requested IN (0, 1)),
      media_url TEXT, media_project TEXT, media_branch TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, completed_at TEXT, media_cleaned_at TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS upload_staging_targets (
      run_id TEXT NOT NULL,
      platform TEXT NOT NULL CHECK (platform IN ('youtube', 'instagram', 'facebook', 'tiktok')),
      mode TEXT NOT NULL CHECK (mode IN ('private', 'container_unpublished', 'draft', 'manual_uploaded')),
      idempotency_key TEXT NOT NULL UNIQUE,
      initial_transport_state TEXT NOT NULL CHECK (initial_transport_state IN ('planned', 'ready')),
      initial_visibility_state TEXT NOT NULL CHECK (initial_visibility_state IN ('not_created', 'unknown')),
      initial_workflow_state TEXT NOT NULL CHECK (initial_workflow_state IN ('ready', 'manual_uploaded')),
      transport_state TEXT NOT NULL CHECK (transport_state IN ('planned', 'uploading', 'processing', 'ready', 'failed', 'expired', 'reconcile_required')),
      visibility_state TEXT NOT NULL CHECK (visibility_state IN ('not_created', 'non_public', 'unknown')),
      workflow_state TEXT NOT NULL CHECK (workflow_state IN ('ready', 'private_uploaded', 'container_unpublished', 'draft', 'manual_uploaded', 'failed', 'expired', 'reconcile_required', 'safety_violation')),
      remote_object_id TEXT, provider_status TEXT, expires_at TEXT, receipt_sha256 TEXT,
      remote_create_started_at TEXT, lease_owner TEXT, lease_expires_at TEXT, last_error TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      PRIMARY KEY(run_id, platform), FOREIGN KEY(run_id) REFERENCES upload_staging_runs(run_id)
    )`,
    `CREATE TABLE IF NOT EXISTS upload_staging_events (
      event_id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL, platform TEXT,
      timestamp TEXT NOT NULL, level TEXT NOT NULL CHECK (level IN ('info', 'warning', 'error')),
      message TEXT NOT NULL, FOREIGN KEY(run_id) REFERENCES upload_staging_runs(run_id)
    )`,
    "CREATE INDEX IF NOT EXISTS upload_staging_targets_status_idx ON upload_staging_targets(platform, transport_state, updated_at)",
    "CREATE INDEX IF NOT EXISTS upload_staging_targets_lease_idx ON upload_staging_targets(lease_expires_at, transport_state)",
    "CREATE INDEX IF NOT EXISTS upload_staging_events_run_idx ON upload_staging_events(run_id, timestamp)",
  ];
  for (const statement of statements) await env.DB.prepare(statement).run();
};

const stagingEvent = async (
  env: Env,
  runId: string,
  platform: StagingPlatform | null,
  level: "info" | "warning" | "error",
  message: string,
): Promise<void> => {
  await env.DB.prepare("INSERT INTO upload_staging_events (run_id, platform, timestamp, level, message) VALUES (?, ?, ?, ?, ?)")
    .bind(runId, platform, now(), level, message.slice(0, 600)).run();
};

const setStagingTarget = async (
  env: Env,
  runId: string,
  platform: StagingPlatform,
  values: Readonly<{
    transport: StagingTransport;
    visibility: StagingVisibility;
    workflow: StagingWorkflow;
    remoteObjectId?: string | null;
    providerStatus?: string | null;
    expiresAt?: string | null;
    receiptSha256?: string | null;
    error?: string | null;
    clearLease?: boolean;
    leaseOwner?: string;
  }>,
): Promise<void> => {
  await env.DB.prepare(`UPDATE upload_staging_targets SET transport_state = ?, visibility_state = ?, workflow_state = ?,
    remote_object_id = CASE WHEN ? = 1 THEN ? ELSE remote_object_id END,
    provider_status = CASE WHEN ? = 1 THEN ? ELSE provider_status END,
    expires_at = CASE WHEN ? = 1 THEN ? ELSE expires_at END,
    receipt_sha256 = CASE WHEN ? = 1 THEN ? ELSE receipt_sha256 END,
    last_error = CASE WHEN ? = 1 THEN ? ELSE last_error END,
    lease_owner = CASE WHEN ? = 1 THEN NULL ELSE lease_owner END,
    lease_expires_at = CASE WHEN ? = 1 THEN NULL ELSE lease_expires_at END,
    updated_at = ?
    WHERE run_id = ? AND platform = ? AND (? IS NULL OR lease_owner = ?)`)
    .bind(
      values.transport,
      values.visibility,
      values.workflow,
      values.remoteObjectId === undefined ? 0 : 1,
      values.remoteObjectId ?? null,
      values.providerStatus === undefined ? 0 : 1,
      values.providerStatus ?? null,
      values.expiresAt === undefined ? 0 : 1,
      values.expiresAt ?? null,
      values.receiptSha256 === undefined ? 0 : 1,
      values.receiptSha256 ?? null,
      values.error === undefined ? 0 : 1,
      values.error?.slice(0, 600) ?? null,
      values.clearLease ? 1 : 0,
      values.clearLease ? 1 : 0,
      now(),
      runId,
      platform,
      values.leaseOwner ?? null,
      values.leaseOwner ?? null,
    ).run();
};

const stagingLeaseDurationMs = 30 * 60 * 1000;

const claimStagingCreate = async (env: Env, runId: string, platform: "instagram" | "facebook"): Promise<string | null> => {
  const owner = crypto.randomUUID();
  const claimedAt = now();
  const leaseExpiresAt = new Date(Date.now() + stagingLeaseDurationMs).toISOString();
  await env.DB.prepare(`UPDATE upload_staging_targets SET
      transport_state = 'uploading', visibility_state = 'unknown', provider_status = 'CREATE_STARTED',
      remote_create_started_at = ?, lease_owner = ?, lease_expires_at = ?, updated_at = ?
    WHERE run_id = ? AND platform = ? AND transport_state = 'planned' AND workflow_state = 'ready'
      AND remote_object_id IS NULL AND receipt_sha256 IS NULL
      AND (lease_owner IS NULL OR lease_expires_at <= ?)`)
    .bind(claimedAt, owner, leaseExpiresAt, claimedAt, runId, platform, claimedAt).run();
  const row = await env.DB.prepare("SELECT lease_owner FROM upload_staging_targets WHERE run_id = ? AND platform = ?")
    .bind(runId, platform).first<{ lease_owner: string | null }>();
  return row?.lease_owner === owner ? owner : null;
};

const claimInstagramInspection = async (env: Env, target: StagingTargetRow): Promise<string | null> => {
  const owner = crypto.randomUUID();
  const claimedAt = now();
  const leaseExpiresAt = new Date(Date.now() + 2 * 60 * 1000).toISOString();
  await env.DB.prepare(`UPDATE upload_staging_targets SET lease_owner = ?, lease_expires_at = ?, updated_at = ?
    WHERE run_id = ? AND platform = 'instagram'
      AND ((transport_state = 'processing' AND workflow_state = 'ready')
        OR (transport_state = 'ready' AND workflow_state = 'container_unpublished'))
      AND remote_object_id = ? AND (lease_owner IS NULL OR lease_expires_at <= ?)`)
    .bind(owner, leaseExpiresAt, claimedAt, target.run_id, target.remote_object_id, claimedAt).run();
  const row = await env.DB.prepare("SELECT lease_owner FROM upload_staging_targets WHERE run_id = ? AND platform = 'instagram'")
    .bind(target.run_id).first<{ lease_owner: string | null }>();
  return row?.lease_owner === owner ? owner : null;
};

const failClosedExpiredCreateLeases = async (env: Env): Promise<void> => {
  const cutoff = now();
  const stale = await env.DB.prepare(`SELECT run_id, platform FROM upload_staging_targets
    WHERE transport_state = 'uploading' AND remote_create_started_at IS NOT NULL
      AND lease_expires_at IS NOT NULL AND lease_expires_at <= ?`).bind(cutoff)
    .all<{ run_id: string; platform: StagingPlatform }>();
  await env.DB.prepare(`UPDATE upload_staging_targets SET
      transport_state = 'reconcile_required', visibility_state = 'unknown', workflow_state = 'reconcile_required',
      provider_status = 'CREATE_RESULT_UNKNOWN',
      last_error = 'Remote-Erstellung wurde begonnen, aber nicht eindeutig bestätigt; automatischer Wiederholungsversuch gesperrt.',
      lease_owner = NULL, lease_expires_at = NULL, updated_at = ?
    WHERE transport_state = 'uploading' AND remote_create_started_at IS NOT NULL
      AND lease_expires_at IS NOT NULL AND lease_expires_at <= ?`)
    .bind(cutoff, cutoff).run();
  for (const target of stale.results ?? []) {
    await stagingEvent(env, target.run_id, target.platform, "error", "Abgelaufener Create-Lease wurde fail-closed gesperrt; manuelle Abstimmung erforderlich.");
    await recalculateStagingRun(env, target.run_id);
  }
};

const event = async (env: Env, jobId: string, level: "info" | "warning" | "error", message: string): Promise<void> => {
  await env.DB.prepare("INSERT INTO meta_publication_events (job_id, timestamp, level, message) VALUES (?, ?, ?, ?)")
    .bind(jobId, now(), level, message.slice(0, 1000)).run();
};

const graphVersion = (env: Env): string => env.META_GRAPH_API_VERSION || "v24.0";
const graphBase = (platform: Platform): string => platform === "instagram" ? "https://graph.instagram.com" : "https://graph.facebook.com";
const accountFor = (platform: Platform, env: Env): string => platform === "instagram" ? env.META_INSTAGRAM_ACCOUNT_ID : env.META_FACEBOOK_PAGE_ID;
const graphUrl = (platform: Platform, env: Env, path: string): string => `${graphBase(platform)}/${graphVersion(env)}/${path.replace(/^\//, "")}`;

const instagramTokenFor = (env: Env): string | null =>
  env.META_INSTAGRAM_USER_ACCESS_TOKEN?.trim()
  || env.META_INSTAGRAM_ACCESS_TOKEN?.trim()
  || env.META_ACCESS_TOKEN?.trim()
  || null;

/** The Facebook secret is already a Page Access Token. Passing it back through
 * the user-token exchange endpoint invalidates an otherwise usable credential. */
const tokenFor = (platform: Platform, env: Env): string => {
  const token = platform === "instagram" ? instagramTokenFor(env) : env.META_FACEBOOK_PAGE_ACCESS_TOKEN?.trim();
  if (!token) {
    throw new MetaApiError(
      `${platform === "instagram" ? "Instagram" : "Facebook"}-Zugangstoken fehlt.`,
      "authentication_failed",
      false,
    );
  }
  return token;
};

const metaApiError = (body: Record<string, unknown>, httpStatus: number): MetaApiError => {
  const provider = typeof body.error === "object" && body.error !== null
    ? body.error as Record<string, unknown>
    : {};
  const code = typeof provider.code === "number" ? provider.code : null;
  const rawMessage = typeof provider.message === "string" ? provider.message.toLowerCase() : "";
  const retryable = provider.is_transient === true || httpStatus === 429 || httpStatus >= 500
    || (code !== null && [4, 17, 32, 613].includes(code));
  if (rawMessage.includes("api access blocked")) {
    return new MetaApiError("Meta hat den API-Zugriff fuer dieses Entwicklerkonto blockiert.", "api_access_blocked", false);
  }
  if (code === 190) {
    return new MetaApiError("Meta-Zugangstoken ist ungueltig oder abgelaufen (Code 190).", "authentication_failed", false);
  }
  if (code !== null && code >= 200 && code <= 299) {
    return new MetaApiError(`Meta-Berechtigung fehlt oder wurde entzogen (Code ${code}).`, "permission_denied", false);
  }
  if (retryable) {
    return new MetaApiError("Meta ist voruebergehend nicht erreichbar oder hat das Ratenlimit erreicht.", "rate_limited", true);
  }
  return new MetaApiError(
    `Meta hat die Anfrage abgelehnt${code === null ? ` (HTTP ${httpStatus})` : ` (Code ${code})`}.`,
    "platform_rejected",
    false,
  );
};

const graphForPlatform = async (platform: Platform, env: Env, path: string, values: Record<string, string>, method: "GET" | "POST" = "POST"): Promise<Record<string, unknown>> => {
  const params = new URLSearchParams(values);
  const headers = { Authorization: `Bearer ${tokenFor(platform, env)}` };
  const response = method === "GET"
    ? await fetch(`${graphUrl(platform, env, path)}?${params.toString()}`, { headers })
    : await fetch(graphUrl(platform, env, path), {
      method: "POST",
      headers: { ...headers, "content-type": "application/x-www-form-urlencoded" },
      body: params,
    });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) throw metaApiError(body, response.status);
  return body;
};

const graph = async (job: Job, env: Env, path: string, values: Record<string, string>, method: "GET" | "POST" = "POST"): Promise<Record<string, unknown>> =>
  graphForPlatform(job.platform, env, path, values, method);

const metadata = (job: Job): Metadata => JSON.parse(job.metadata_json) as Metadata;

const setState = async (env: Env, job: Job, state: JobStatus, changes: Partial<Job> & { readonly publishedAt?: string } = {}): Promise<void> => {
  const changed = <K extends keyof Job>(key: K, fallback: Job[K]): Job[K] =>
    Object.prototype.hasOwnProperty.call(changes, key) ? changes[key] as Job[K] : fallback;
  await env.DB.prepare(`UPDATE meta_publication_jobs
      SET status = ?, attempt_count = ?, platform_video_id = ?, publication_url = ?, container_id = ?, last_error = ?, updated_at = ?, published_at = ?
      WHERE job_id = ?`)
    .bind(state, changed("attempt_count", job.attempt_count), changed("platform_video_id", job.platform_video_id),
      changed("publication_url", job.publication_url), changed("container_id", job.container_id),
      changed("last_error", job.last_error), now(), changes.publishedAt ?? (state === "published" ? now() : null), job.job_id).run();
};

const currentJob = async (env: Env, jobId: string): Promise<Job | null> =>
  env.DB.prepare("SELECT * FROM meta_publication_jobs WHERE job_id = ?").bind(jobId).first<Job>();

const facebookReelUrl = (id: string): string => `https://www.facebook.com/reel/${encodeURIComponent(id)}`;

const publicUrl = (platform: Platform, id: string): string =>
  platform === "instagram" ? `https://www.instagram.com/p/${id}/` : facebookReelUrl(id);

const verifiedFacebookPermalink = (id: unknown, value: unknown): string => {
  try {
    const candidate = new URL(String(value ?? ""));
    const hostname = candidate.hostname.toLowerCase();
    const isVideoPath = /^\/reel\/[^/]+/.test(candidate.pathname) || /\/videos\/[^/]+/.test(candidate.pathname) ||
      (candidate.pathname.startsWith("/watch") && candidate.searchParams.has("v"));
    if (candidate.protocol === "https:" && (hostname === "facebook.com" || hostname.endsWith(".facebook.com")) && isVideoPath) {
      return candidate.toString();
    }
  } catch { /* Missing or malformed Graph permalinks use the stable Reel route. */ }
  return facebookReelUrl(String(id));
};

/**
 * Pages is used as a short-lived, free Meta import origin. Cleanup is enabled
 * only when a restricted Cloudflare API token is configured as a Worker secret.
 * A missing cleanup secret never blocks a publication, but is recorded so it
 * can be corrected before the free storage allowance is needlessly consumed.
 */
const removeTemporaryPagesDeployment = async (job: Job, env: Env): Promise<void> => {
  if (!env.CLOUDFLARE_API_TOKEN || !env.CLOUDFLARE_ACCOUNT_ID) {
    await event(env, job.job_id, "warning", "Temporäre Pages-MP4 wartet auf Bereinigung: Cloudflare-Cleanup-Token fehlt.");
    return;
  }
  const list = await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${job.media_project}/deployments`, {
    headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` },
  });
  const payload = await list.json().catch(() => null) as { result?: Array<{ id?: string; deployment_trigger?: { metadata?: { branch?: string } } }> } | null;
  const deployments = payload?.result ?? [];
  for (const deployment of deployments) {
    if (deployment.deployment_trigger?.metadata?.branch !== job.media_branch || !deployment.id) continue;
    await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${job.media_project}/deployments/${deployment.id}?force=true`, {
      method: "DELETE", headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` },
    });
  }
};

const publishInstagram = async (job: Job, env: Env): Promise<void> => {
  const details = metadata(job);
  if (!job.container_id) {
    const container = await graph(job, env, `${accountFor("instagram", env)}/media`, {
      media_type: "REELS", video_url: job.media_url, caption: details.description, share_to_feed: "true",
    });
    const id = typeof container.id === "string" ? container.id : null;
    if (!id) throw new Error("Instagram lieferte keinen Reel-Container.");
    await setState(env, job, "waiting_for_meta", { container_id: id, attempt_count: job.attempt_count + 1, last_error: null });
    await event(env, job.job_id, "info", "Instagram verarbeitet das Reel in der Cloud.");
    return;
  }
  const status = await graph(job, env, job.container_id, { fields: "status_code,status" }, "GET");
  const code = typeof status.status_code === "string" ? status.status_code.toUpperCase() : "";
  if (code === "IN_PROGRESS" || code === "") {
    await setState(env, job, "waiting_for_meta", { last_error: null });
    return;
  }
  if (code === "PUBLISHED") {
    const media = await graph(job, env, `${accountFor("instagram", env)}/media`, {
      fields: "id,caption,permalink,timestamp",
      limit: "50",
    }, "GET");
    const candidates = Array.isArray(media.data) ? media.data.filter((item): item is Record<string, unknown> =>
      typeof item === "object" && item !== null) : [];
    const expectedCaption = details.description.trim();
    const earliest = Date.parse(job.publish_at) - 6 * 60 * 60 * 1000;
    const match = candidates
      .filter((item) => typeof item.id === "string" && typeof item.caption === "string" && item.caption.trim() === expectedCaption)
      .filter((item) => typeof item.timestamp !== "string" || !Number.isFinite(Date.parse(item.timestamp)) || Date.parse(item.timestamp) >= earliest)
      .sort((left, right) => Date.parse(String(right.timestamp ?? 0)) - Date.parse(String(left.timestamp ?? 0)))[0];
    const id = typeof match?.id === "string" ? match.id : null;
    if (!id) {
      throw new MetaApiError(
        "Instagram meldet den Container als veroeffentlicht, die Reel-ID konnte noch nicht eindeutig zugeordnet werden.",
        "processing_timeout",
        true,
      );
    }
    const permalink = typeof match.permalink === "string" && match.permalink.startsWith("https://www.instagram.com/")
      ? match.permalink
      : publicUrl("instagram", id);
    await setState(env, job, "published", { platform_video_id: id, publication_url: permalink, last_error: null });
    await event(env, job.job_id, "info", "Instagram-Reel nach unterbrochener Bestaetigung abgeglichen.");
    await removeTemporaryPagesDeployment(job, env);
    return;
  }
  if (code !== "FINISHED") throw new Error(`Instagram-Verarbeitung fehlgeschlagen: ${typeof status.status === "string" ? status.status : code}`);
  const result = await graph(job, env, `${accountFor("instagram", env)}/media_publish`, { creation_id: job.container_id });
  const id = typeof result.id === "string" ? result.id : null;
  if (!id) throw new Error("Instagram bestätigte keine Reel-ID.");
  await setState(env, job, "published", { platform_video_id: id, publication_url: publicUrl("instagram", id), last_error: null });
  await event(env, job.job_id, "info", "Instagram-Reel veröffentlicht.");
  await removeTemporaryPagesDeployment(job, env);
};

const publishFacebook = async (job: Job, env: Env): Promise<void> => {
  const details = metadata(job);
  const edge = `${accountFor("facebook", env)}/video_reels`;
  let videoId = job.platform_video_id;
  let uploadUrl = job.container_id;
  if (videoId) {
    try {
      const remote = await graph(job, env, videoId, { fields: "published,status,permalink_url" }, "GET");
      if (remote.published === true) {
        const permalink = verifiedFacebookPermalink(videoId, remote.permalink_url);
        await setState(env, job, "published", {
          platform_video_id: videoId,
          publication_url: permalink,
          container_id: null,
          last_error: null,
        });
        await event(env, job.job_id, "info", "Facebook-Reel nach unterbrochener Bestaetigung abgeglichen.");
        await removeTemporaryPagesDeployment(job, env);
        return;
      }
    } catch (error) {
      if (error instanceof MetaApiError && ["authentication_failed", "permission_denied", "api_access_blocked", "rate_limited"].includes(error.failureCode)) {
        throw error;
      }
      // A freshly created unpublished Reel may not yet be readable. The saved
      // upload URL still lets this exact session resume without creating a duplicate.
    }
  }
  if (!videoId || !uploadUrl) {
    if (videoId || uploadUrl) {
      throw new MetaApiError("Facebook-Upload-Session ist unvollstaendig; neuer Remote-Upload wird sicherheitshalber nicht erzeugt.", "platform_rejected", false);
    }
    const session = await graph(job, env, edge, { upload_phase: "start" });
    videoId = typeof session.video_id === "string" ? session.video_id : null;
    uploadUrl = typeof session.upload_url === "string" ? session.upload_url : null;
    if (!videoId || !uploadUrl) throw new Error("Facebook lieferte keine Reels-Upload-Session.");
    await setState(env, job, "processing", {
      platform_video_id: videoId,
      container_id: uploadUrl,
      last_error: null,
    });
  }
  const media = await fetch(job.media_url);
  if (!media.ok || !media.body) {
    throw new MetaApiError(
      media.status >= 500 ? "Die vorbereitete Cloud-MP4 ist voruebergehend nicht erreichbar." : "Die vorbereitete Cloud-MP4 ist nicht mehr erreichbar.",
      "media_unavailable",
      media.status >= 500,
    );
  }
  const size = media.headers.get("content-length");
  const uploaded = await fetch(uploadUrl, {
    method: "POST",
    // Meta's rupload endpoint is the exception to Graph's Bearer convention.
    headers: { Authorization: `OAuth ${tokenFor("facebook", env)}`, offset: "0", file_size: size || "0", "content-type": "application/octet-stream" },
    body: media.body,
  });
  if (!uploaded.ok) {
    const body = await uploaded.json().catch(() => ({})) as Record<string, unknown>;
    if (uploaded.status === 401) throw new MetaApiError("Facebook-Zugangstoken wurde beim Medienupload abgelehnt.", "authentication_failed", false);
    if (uploaded.status === 403) throw new MetaApiError("Facebook-Berechtigung fuer den Medienupload fehlt.", "permission_denied", false);
    throw metaApiError(body, uploaded.status);
  }
  await graph(job, env, edge, { video_id: videoId, upload_phase: "finish", video_state: "PUBLISHED", description: details.description, title: details.title });
  await setState(env, job, "published", {
    platform_video_id: videoId,
    publication_url: publicUrl("facebook", videoId),
    container_id: null,
    attempt_count: job.attempt_count + 1,
    last_error: null,
  });
  await event(env, job.job_id, "info", "Facebook-Reel veröffentlicht.");
  await removeTemporaryPagesDeployment(job, env);
};

const recalculateStagingRun = async (env: Env, runId: string): Promise<void> => {
  const targets = await env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ?")
    .bind(runId).all<StagingTargetRow>();
  const rows = targets.results ?? [];
  const completed = rows.length === stagingPlatforms.length && rows.every((target) =>
    ["private_uploaded", "container_unpublished", "draft", "manual_uploaded"].includes(target.workflow_state));
  const safetyViolation = rows.some((target) => target.workflow_state === "safety_violation");
  const failed = rows.some((target) => target.workflow_state === "failed");
  const expired = rows.some((target) => target.workflow_state === "expired");
  const reconcile = rows.some((target) => target.workflow_state === "reconcile_required");
  const running = rows.some((target) => ["uploading", "processing"].includes(target.transport_state));
  const allPlanned = rows.length === stagingPlatforms.length && rows.every((target) => target.transport_state === "planned");
  const status: StagingRunStatus = safetyViolation ? "safety_violation"
    : reconcile ? "reconcile_required"
      : failed ? "failed"
        : expired ? "expired"
          : completed ? "completed"
            : running ? "running"
              : allPlanned ? "planned" : "partial";
  const updatedAt = now();
  await env.DB.prepare("UPDATE upload_staging_runs SET status = ?, updated_at = ?, completed_at = ? WHERE run_id = ?")
    .bind(status, updatedAt, completed ? updatedAt : null, runId).run();
};

type StagingCleanupStatus = "not_applicable" | "waiting" | "blocked" | "cleaned" | "already_cleaned" | "retry_required";

interface PagesDeployment {
  readonly id?: string;
  readonly url?: string;
  readonly deployment_trigger?: { readonly metadata?: { readonly branch?: string } };
}

interface PagesDeploymentList {
  readonly success?: boolean;
  readonly result?: PagesDeployment[];
  readonly result_info?: { readonly page?: number; readonly total_pages?: number };
}

const pagesOrigin = (value: string | undefined): string | null => {
  if (!value) return null;
  try {
    return new URL(value).origin;
  } catch {
    return null;
  }
};

const listPagesDeployments = async (env: Env, project: string): Promise<PagesDeployment[]> => {
  const deployments: PagesDeployment[] = [];
  let page = 1;
  let totalPages = 1;
  do {
    const url = new URL(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${project}/deployments`);
    url.searchParams.set("page", String(page));
    url.searchParams.set("per_page", "100");
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` },
    });
    const payload = await response.json().catch(() => null) as PagesDeploymentList | null;
    if (!response.ok || payload?.success === false || !Array.isArray(payload?.result)) {
      throw new Error(`Deployment-Liste HTTP ${response.status}`);
    }
    deployments.push(...payload.result);
    const reportedPages = Number(payload.result_info?.total_pages ?? 1);
    if (!Number.isSafeInteger(reportedPages) || reportedPages < 1 || reportedPages > 100) {
      throw new Error("Deployment-Paginierung ist außerhalb der sicheren Grenzen.");
    }
    totalPages = reportedPages;
    page += 1;
  } while (page <= totalPages);
  return deployments;
};

const matchingStagingDeployments = (
  deployments: readonly PagesDeployment[],
  run: StagingRunRow,
): PagesDeployment[] => {
  const expectedOrigin = pagesOrigin(run.media_url ?? undefined);
  if (!expectedOrigin) return [];
  return deployments.filter((deployment) =>
    deployment.id && deployment.deployment_trigger?.metadata?.branch === run.media_branch &&
    pagesOrigin(deployment.url) === expectedOrigin);
};

const markStagingMediaCleaned = async (env: Env, runId: string): Promise<void> => {
  const cleanedAt = now();
  await env.DB.prepare("UPDATE upload_staging_runs SET media_cleaned_at = ?, updated_at = ? WHERE run_id = ? AND media_cleaned_at IS NULL")
    .bind(cleanedAt, cleanedAt, runId).run();
  await stagingEvent(env, runId, null, "info", "Temporäre Pages-MP4 wurde nach sicherer Meta-Übernahme entfernt.");
};

const cleanupStagingMediaIfSafe = async (env: Env, runId: string): Promise<StagingCleanupStatus> => {
  const run = await env.DB.prepare("SELECT * FROM upload_staging_runs WHERE run_id = ?")
    .bind(runId).first<StagingRunRow>();
  if (!run || !run.media_project || !run.media_branch || !run.media_url) return "not_applicable";
  if (run.media_cleaned_at) return "already_cleaned";
  const targets = await env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ?")
    .bind(runId).all<StagingTargetRow>();
  const byPlatform = new Map((targets.results ?? []).map((target) => [target.platform, target]));
  const instagram = byPlatform.get("instagram");
  const facebook = byPlatform.get("facebook");
  const instagramNoLongerNeedsMedia = Boolean(instagram &&
    ["container_unpublished", "expired"].includes(instagram.workflow_state));
  const facebookNoLongerNeedsMedia = Boolean(facebook &&
    facebook.workflow_state === "draft");
  if (!instagramNoLongerNeedsMedia || !facebookNoLongerNeedsMedia) return "waiting";
  if (!env.CLOUDFLARE_API_TOKEN || !env.CLOUDFLARE_ACCOUNT_ID ||
      run.media_project !== env.UPLOAD_STAGING_MEDIA_PROJECT) {
    await stagingEvent(env, runId, null, "error", "Temporäre Staging-MP4 konnte wegen fehlendem Cleanup-Schutz nicht entfernt werden.");
    return "blocked";
  }
  try {
    const deployments = matchingStagingDeployments(
      await listPagesDeployments(env, run.media_project),
      run,
    );
    if (deployments.length === 0) {
      const media = await fetch(run.media_url, { method: "HEAD" });
      if (media.status === 404 || media.status === 410) {
        await markStagingMediaCleaned(env, runId);
        return "cleaned";
      }
      throw new Error("Kein eindeutig zur Medien-URL passendes Pages-Deployment gefunden.");
    }
    for (const deployment of deployments) {
      const removed = await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${run.media_project}/deployments/${deployment.id}?force=true`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` },
      });
      const result = await removed.json().catch(() => null) as { success?: boolean } | null;
      if ((!removed.ok || result?.success === false) && removed.status !== 404) {
        throw new Error(`Deployment-Cleanup HTTP ${removed.status}`);
      }
    }
    const remaining = matchingStagingDeployments(
      await listPagesDeployments(env, run.media_project),
      run,
    );
    if (remaining.length > 0) throw new Error("Deployment ist nach dem Cleanup weiterhin vorhanden.");
    await markStagingMediaCleaned(env, runId);
    return "cleaned";
  } catch (error) {
    await stagingEvent(env, runId, null, "warning", `Temporäres Pages-Deployment bleibt für Cleanup-Retry erhalten: ${error instanceof Error ? error.message : "unbekannter Fehler"}`);
    return "retry_required";
  }
};

const stageInstagramContainer = async (env: Env, run: StagingRunPayload): Promise<void> => {
  const platform = "instagram" as const;
  const leaseOwner = await claimStagingCreate(env, run.runId, platform);
  if (!leaseOwner) return;
  let containerId: string | null = null;
  try {
    await stagingEvent(env, run.runId, platform, "info", "Instagram-Container wird nichtöffentlich erstellt.");
    const container = await graphForPlatform("instagram", env, `${accountFor("instagram", env)}/media`, {
      media_type: "REELS",
      video_url: run.mediaUrl!,
      caption: run.metadata.description,
    });
    containerId = typeof container.id === "string" && container.id ? container.id : null;
    if (!containerId) throw new Error("Instagram lieferte keine Container-ID.");
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    await setStagingTarget(env, run.runId, platform, {
      transport: "processing", visibility: "non_public", workflow: "ready",
      remoteObjectId: containerId, providerStatus: "IN_PROGRESS", expiresAt,
      error: null, clearLease: true, leaseOwner,
    });
    await stagingEvent(env, run.runId, platform, "info", "Instagram verarbeitet den unveröffentlichten Container; es gibt keinen Veröffentlichungsaufruf in der Staging-Lane.");
  } catch (error) {
    await setStagingTarget(env, run.runId, platform, {
      transport: "reconcile_required", visibility: "unknown", workflow: "reconcile_required",
      remoteObjectId: containerId, providerStatus: "CREATE_RESULT_UNKNOWN",
      error: error instanceof Error ? error.message : "Unklarer Instagram-Fehler.",
      clearLease: true, leaseOwner,
    });
    await stagingEvent(env, run.runId, platform, "error", "Instagram-Ergebnis ist unklar; es wird kein zweiter Container erstellt.");
  }
};

const stageFacebookDraft = async (env: Env, run: StagingRunPayload): Promise<void> => {
  const platform = "facebook" as const;
  const leaseOwner = await claimStagingCreate(env, run.runId, platform);
  if (!leaseOwner) return;
  let videoId: string | null = null;
  try {
    await stagingEvent(env, run.runId, platform, "info", "Facebook-Reel-Entwurf wird hochgeladen.");
    const edge = `${accountFor("facebook", env)}/video_reels`;
    const session = await graphForPlatform("facebook", env, edge, { upload_phase: "start" });
    videoId = typeof session.video_id === "string" && session.video_id ? session.video_id : null;
    const uploadUrl = typeof session.upload_url === "string" ? session.upload_url : null;
    if (!videoId || !uploadUrl) throw new Error("Facebook lieferte keine Upload-Session.");
    await setStagingTarget(env, run.runId, platform, {
      transport: "uploading", visibility: "unknown", workflow: "ready",
      remoteObjectId: videoId, providerStatus: "UPLOAD_SESSION_CREATED", leaseOwner,
    });
    const media = await fetch(run.mediaUrl!);
    if (!media.ok || !media.body) throw new Error("Die temporäre Cloud-MP4 ist nicht erreichbar.");
    const uploaded = await fetch(uploadUrl, {
      method: "POST",
      headers: {
        Authorization: `OAuth ${tokenFor("facebook", env)}`,
        offset: "0",
        file_size: media.headers.get("content-length") || "0",
        "content-type": "application/octet-stream",
      },
      body: media.body,
    });
    if (!uploaded.ok) throw new Error(`Facebook-Medienupload fehlgeschlagen (HTTP ${uploaded.status}).`);
    await graphForPlatform("facebook", env, edge, {
      video_id: videoId,
      upload_phase: "finish",
      video_state: "DRAFT",
      description: run.metadata.description,
      title: run.metadata.youtubeTitle.replace(/(?:\s+#[\p{L}\p{N}_]+){5}$/u, "").trim(),
    });
    const verification = await graphForPlatform("facebook", env, videoId, { fields: "published,status" }, "GET");
    if (verification.published !== false) {
      throw new Error("Facebook bestätigte den nichtöffentlichen Entwurfsstatus nicht.");
    }
    await setStagingTarget(env, run.runId, platform, {
      transport: "ready", visibility: "non_public", workflow: "draft",
      remoteObjectId: videoId, providerStatus: "DRAFT", error: null,
      clearLease: true, leaseOwner,
    });
    await stagingEvent(env, run.runId, platform, "info", "Facebook bestätigte den nichtöffentlichen Entwurf.");
  } catch (error) {
    await setStagingTarget(env, run.runId, platform, {
      transport: "reconcile_required", visibility: "unknown", workflow: "reconcile_required",
      remoteObjectId: videoId, providerStatus: "CREATE_OR_FINISH_RESULT_UNKNOWN",
      error: error instanceof Error ? error.message : "Unklarer Facebook-Fehler.",
      clearLease: true, leaseOwner,
    });
    await stagingEvent(env, run.runId, platform, "error", "Facebook-Ergebnis ist unklar; es wird kein zweiter Entwurf erstellt.");
  }
};

const inspectInstagramStaging = async (
  env: Env,
  runId?: string,
  cleanupAfterInspection = true,
): Promise<void> => {
  await ensureStagingSchema(env);
  await failClosedExpiredCreateLeases(env);
  const finishedPollCutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const runFilter = runId ? " AND run_id = ?" : "";
  const query = `SELECT * FROM upload_staging_targets
    WHERE platform = 'instagram' AND (
      (transport_state = 'processing' AND workflow_state = 'ready')
      OR (transport_state = 'ready' AND workflow_state = 'container_unpublished'
        AND (expires_at <= ? OR updated_at <= ?))
    )${runFilter} ORDER BY updated_at ASC LIMIT 10`;
  const bindings: unknown[] = [now(), finishedPollCutoff];
  if (runId) bindings.push(runId);
  const targets = await env.DB.prepare(query).bind(...bindings)
    .all<StagingTargetRow>();
  for (const target of targets.results ?? []) {
    if (!target.remote_object_id) {
      await setStagingTarget(env, target.run_id, "instagram", {
        transport: "reconcile_required", visibility: "unknown", workflow: "reconcile_required",
        providerStatus: "MISSING_CONTAINER_ID", error: "Verarbeitung ohne Container-ID kann nicht sicher abgestimmt werden.",
        clearLease: true,
      });
      await recalculateStagingRun(env, target.run_id);
      if (cleanupAfterInspection) await cleanupStagingMediaIfSafe(env, target.run_id);
      continue;
    }
    const leaseOwner = await claimInstagramInspection(env, target);
    if (!leaseOwner) continue;
    if (target.expires_at && Date.parse(target.expires_at) <= Date.now()) {
      await setStagingTarget(env, target.run_id, "instagram", {
        transport: "expired", visibility: "non_public", workflow: "expired",
        remoteObjectId: target.remote_object_id, providerStatus: "EXPIRED", expiresAt: target.expires_at,
        clearLease: true, leaseOwner,
      });
      await stagingEvent(env, target.run_id, "instagram", "warning", "Der unveröffentlichte Instagram-Container ist erwartungsgemäß abgelaufen.");
      await recalculateStagingRun(env, target.run_id);
      if (cleanupAfterInspection) await cleanupStagingMediaIfSafe(env, target.run_id);
      continue;
    }
    try {
      const status = await graphForPlatform("instagram", env, target.remote_object_id, { fields: "status_code,status" }, "GET");
      const code = typeof status.status_code === "string" ? status.status_code.toUpperCase() : "";
      if (code === "FINISHED") {
        await setStagingTarget(env, target.run_id, "instagram", {
          transport: "ready", visibility: "non_public", workflow: "container_unpublished",
          remoteObjectId: target.remote_object_id, providerStatus: code, expiresAt: target.expires_at,
          error: null, clearLease: true, leaseOwner,
        });
        await stagingEvent(env, target.run_id, "instagram", "info", "Instagram-Container ist uploadbereit und bleibt unveröffentlicht.");
      } else if (code === "PUBLISHED") {
        await setStagingTarget(env, target.run_id, "instagram", {
          transport: "failed", visibility: "unknown", workflow: "safety_violation",
          remoteObjectId: target.remote_object_id, providerStatus: code, expiresAt: target.expires_at,
          error: "Unerwarteter öffentlicher Instagram-Status.", clearLease: true, leaseOwner,
        });
        await stagingEvent(env, target.run_id, "instagram", "error", "Sicherheitsverletzung: Instagram meldet unerwartet PUBLISHED.");
      } else if (code === "IN_PROGRESS") {
        if (target.workflow_state === "container_unpublished") {
          await setStagingTarget(env, target.run_id, "instagram", {
            transport: "reconcile_required", visibility: "unknown", workflow: "reconcile_required",
            remoteObjectId: target.remote_object_id, providerStatus: code, expiresAt: target.expires_at,
            error: "Instagram fiel nach FINISHED auf IN_PROGRESS zurück; automatische Verarbeitung wurde gesperrt.",
            clearLease: true, leaseOwner,
          });
        } else {
          await setStagingTarget(env, target.run_id, "instagram", {
            transport: "processing", visibility: "non_public", workflow: "ready",
            remoteObjectId: target.remote_object_id, providerStatus: code, expiresAt: target.expires_at,
            clearLease: true, leaseOwner,
          });
        }
      } else if (code === "ERROR" || code === "EXPIRED") {
        await setStagingTarget(env, target.run_id, "instagram", {
          transport: code === "EXPIRED" ? "expired" : "failed", visibility: "non_public",
          workflow: code === "EXPIRED" ? "expired" : "failed", remoteObjectId: target.remote_object_id,
          providerStatus: code, expiresAt: target.expires_at, error: `Instagram-Containerstatus: ${code}`,
          clearLease: true, leaseOwner,
        });
      } else {
        await setStagingTarget(env, target.run_id, "instagram", {
          transport: "reconcile_required", visibility: "unknown", workflow: "reconcile_required",
          remoteObjectId: target.remote_object_id, providerStatus: code || "STATUS_MISSING", expiresAt: target.expires_at,
          error: "Instagram lieferte einen unbekannten Containerstatus; automatische Verarbeitung wurde gesperrt.",
          clearLease: true, leaseOwner,
        });
      }
    } catch {
      // Read-only polling is retried by the next cron tick. No create call is repeated.
      await setStagingTarget(env, target.run_id, "instagram", {
        transport: "processing", visibility: "non_public", workflow: "ready",
        remoteObjectId: target.remote_object_id, clearLease: true, leaseOwner,
      });
    }
    await recalculateStagingRun(env, target.run_id);
    if (cleanupAfterInspection) await cleanupStagingMediaIfSafe(env, target.run_id);
  }
};

const processJob = async (job: Job, env: Env): Promise<void> => {
  try {
    if (job.platform === "instagram") await publishInstagram(job, env);
    else await publishFacebook(job, env);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unbekannter Cloud-Veröffentlichungsfehler.";
    const canRetry = !(error instanceof MetaApiError) || error.retryable;
    const retryable = canRetry && job.attempt_count < 4;
    // A publisher may already have persisted a remote container/session. Read
    // that authoritative row before changing status so a retry never erases it.
    const persisted = await currentJob(env, job.job_id) ?? job;
    await setState(env, persisted, retryable ? "scheduled" : "failed", {
      attempt_count: persisted.attempt_count + 1,
      last_error: message,
    });
    await event(env, job.job_id, "error", retryable ? `Wird erneut versucht: ${message}` : message);
  }
};

const publicationClaimTimeoutMs = 20 * 60 * 1000;

const recoverStalePublicationClaims = async (env: Env): Promise<void> => {
  const cutoff = new Date(Date.now() - publicationClaimTimeoutMs).toISOString();
  const stale = await env.DB.prepare(`SELECT job_id, platform_video_id, container_id FROM meta_publication_jobs
    WHERE status = 'processing' AND updated_at <= ?`).bind(cutoff)
    .all<{ job_id: string; platform_video_id: string | null; container_id: string | null }>();
  for (const job of stale.results ?? []) {
    const resumable = Boolean(job.platform_video_id || job.container_id);
    const recovered = await env.DB.prepare(`UPDATE meta_publication_jobs SET status = ?, last_error = ?, updated_at = ?
      WHERE job_id = ? AND status = 'processing' AND updated_at <= ? RETURNING job_id`)
      .bind(
        resumable ? "scheduled" : "failed",
        resumable
          ? "Unterbrochener Meta-Upload wird anhand der gespeicherten Remote-Session fortgesetzt."
          : "Unterbrochener Meta-Create-Aufruf kann ohne Remote-ID nicht duplikatsicher wiederholt werden.",
        now(),
        job.job_id,
        cutoff,
      ).first<{ job_id: string }>();
    if (!recovered) continue;
    await event(
      env,
      job.job_id,
      resumable ? "warning" : "error",
      resumable
        ? "Veralteter Job-Claim freigegeben; vorhandene Remote-Session bleibt erhalten."
        : "Veralteter Job-Claim fail-closed beendet; kein unkontrollierter zweiter Upload.",
    );
  }
};

const claimPublicationJob = async (env: Env, jobId: string): Promise<Job | null> => {
  const claimedAt = now();
  return env.DB.prepare(`UPDATE meta_publication_jobs SET status = 'processing', updated_at = ?
    WHERE job_id = ? AND status IN ('scheduled', 'waiting_for_meta') AND publish_at <= ?
    RETURNING *`).bind(claimedAt, jobId, claimedAt).first<Job>();
};

const processDue = async (env: Env): Promise<void> => {
  await recoverStalePublicationClaims(env);
  const rows = await env.DB.prepare(`SELECT job_id FROM meta_publication_jobs
    WHERE status IN ('scheduled', 'waiting_for_meta') AND publish_at <= ?
    ORDER BY publish_at ASC LIMIT 10`).bind(now()).all<{ job_id: string }>();
  for (const candidate of rows.results ?? []) {
    const claimed = await claimPublicationJob(env, candidate.job_id);
    if (claimed) await processJob(claimed, env);
  }
};

const authorized = (request: Request, env: Env): boolean => request.headers.get("authorization") === `Bearer ${env.META_QUEUE_TOKEN}`;

interface MetaCredentialStatus {
  readonly status: "ready" | "invalid";
  readonly failureCode: PublicationFailureCode | null;
  readonly reason: string | null;
}

const verifyMetaCredential = async (platform: Platform, env: Env): Promise<void> => {
  const expectedId = accountFor(platform, env);
  if (!expectedId) {
    throw new MetaApiError(`${platform === "instagram" ? "Instagram" : "Facebook"}-Konto-ID fehlt.`, "authentication_failed", false);
  }
  const account = await graphForPlatform(platform, env, expectedId, {
    // A Page Access Token can validate its Page node directly, but the `tasks`
    // field belongs to the User-token `/me/accounts` flow and is not available
    // on this direct Page request.
    fields: platform === "instagram" ? "id,username" : "id,name",
  }, "GET");
  if (String(account.id ?? "") !== expectedId) {
    throw new MetaApiError("Meta-Token und konfigurierte Konto-ID gehoeren nicht zusammen.", "authentication_failed", false);
  }
  if (platform === "facebook") {
    if (typeof account.name !== "string" || !account.name.trim()) {
      throw new MetaApiError("Facebook-Page-Token konnte keinen gueltigen Seitennamen lesen.", "authentication_failed", false);
    }
    return;
  }
  // A successful publishing-limit read proves the Instagram token has access
  // to the Content Publishing surface, not merely read access to the account.
  await graphForPlatform("instagram", env, `${expectedId}/content_publishing_limit`, {
    fields: "quota_usage,config",
  }, "GET");
};

const metaCredentialStatus = async (platform: Platform, env: Env): Promise<MetaCredentialStatus> => {
  try {
    await verifyMetaCredential(platform, env);
    return { status: "ready", failureCode: null, reason: null };
  } catch (error) {
    if (error instanceof MetaApiError) {
      return { status: "invalid", failureCode: error.failureCode, reason: error.message };
    }
    return { status: "invalid", failureCode: "unknown", reason: "Meta-Zugang konnte nicht verifiziert werden." };
  }
};

const enqueue = async (request: Request, env: Env): Promise<Response> => {
  // Do not accept media unless the Worker can delete the temporary Pages
  // deployment afterwards. This is an explicit cost/storage guardrail, not a
  // best-effort cleanup that could silently accumulate videos.
  if (!env.CLOUDFLARE_API_TOKEN || !env.CLOUDFLARE_ACCOUNT_ID) {
    return json({ error: "Cloudflare-Cleanup ist noch nicht konfiguriert; der Scheduler nimmt aus Kostenschutzgründen keine MP4 an." }, 503);
  }
  const payload = await request.json().catch(() => null);
  if (!validPayload(payload)) return json({ error: "Ungültiger Queue-Auftrag." }, 400);
  const credential = await metaCredentialStatus(payload.platform, env);
  if (credential.status !== "ready") {
    return json({
      error: "Meta-Zugang ist nicht veröffentlichungsbereit.",
      platform: payload.platform,
      failureCode: credential.failureCode,
      reason: credential.reason,
    }, 503);
  }
  const createdAt = now();
  await env.DB.prepare(`INSERT INTO meta_publication_jobs (
    job_id, source_video_id, platform, publish_at, status, metadata_json, media_url, media_project, media_branch,
    created_at, updated_at
  ) VALUES (?, ?, ?, ?, 'scheduled', ?, ?, ?, ?, ?, ?)
  ON CONFLICT(job_id) DO UPDATE SET publish_at = excluded.publish_at, metadata_json = excluded.metadata_json,
    media_url = excluded.media_url, media_project = excluded.media_project, media_branch = excluded.media_branch,
    status = CASE WHEN meta_publication_jobs.status = 'published' THEN 'published' ELSE 'scheduled' END,
    updated_at = excluded.updated_at`)
    .bind(payload.jobId, payload.sourceVideoId, payload.platform, new Date(payload.publishAt).toISOString(), JSON.stringify(payload.metadata),
      payload.mediaUrl, payload.mediaProject, payload.mediaBranch, createdAt, createdAt).run();
  await event(env, payload.jobId, "info", "Cloud-Veröffentlichung eingeplant.");
  return json({ jobId: payload.jobId, status: "scheduled" }, 201);
};

const stagingAuthError = (request: Request, env: Env): Response | null => {
  if (!env.UPLOAD_STAGING_TOKEN) return json({ error: "Staging-API ist nicht konfiguriert." }, 503);
  return request.headers.get("authorization") === `Bearer ${env.UPLOAD_STAGING_TOKEN}`
    ? null
    : json({ error: "Nicht autorisiert." }, 401);
};

const stagingTargetResponse = (target: StagingTargetRow): Record<string, unknown> => ({
  platform: target.platform,
  mode: target.mode,
  idempotencyKey: target.idempotency_key,
  transportState: target.transport_state,
  visibilityState: target.visibility_state,
  workflowState: target.workflow_state,
  remoteObjectId: target.remote_object_id,
  providerStatus: target.provider_status,
  confirmedAt: ["private_uploaded", "container_unpublished", "draft"].includes(target.workflow_state)
    ? target.updated_at
    : null,
  expiresAt: target.expires_at,
  lastError: target.last_error,
  publishedAt: null,
  scheduledFor: null,
  publicUrl: null,
});

const stagingRunResponse = async (env: Env, runId: string): Promise<Record<string, unknown> | null> => {
  const run = await env.DB.prepare("SELECT * FROM upload_staging_runs WHERE run_id = ?")
    .bind(runId).first<StagingRunRow>();
  if (!run) return null;
  const targets = await env.DB.prepare(`SELECT * FROM upload_staging_targets WHERE run_id = ?
    ORDER BY CASE platform WHEN 'youtube' THEN 1 WHEN 'instagram' THEN 2 WHEN 'facebook' THEN 3 ELSE 4 END`)
    .bind(runId).all<StagingTargetRow>();
  return {
    schemaVersion: 1,
    lane: "non-publishing",
    runId: run.run_id,
    contentId: run.content_id,
    status: run.status,
    qualityStatus: run.quality_status,
    createdAt: run.created_at,
    updatedAt: run.updated_at,
    completedAt: run.completed_at,
    targets: (targets.results ?? []).map(stagingTargetResponse),
  };
};

const sameStagingRun = (
  run: StagingRunRow,
  targets: readonly StagingTargetRow[],
  payload: StagingRunPayload,
  idempotencyKeys: ReadonlyMap<StagingPlatform, string>,
): boolean => {
  let storedMetadata: unknown;
  try {
    storedMetadata = JSON.parse(run.metadata_json);
  } catch {
    return false;
  }
  const executionCompatible = payload.executeMeta === true
    ? run.execution_requested === 0 || (run.execution_requested === 1 &&
      run.media_url === payload.mediaUrl && run.media_project === payload.mediaProject && run.media_branch === payload.mediaBranch)
    : true;
  if (run.run_id !== payload.runId || run.content_id !== payload.contentId.toLowerCase() ||
      run.asset_sha256 !== payload.assetSha256.toLowerCase() || run.metadata_sha256 !== payload.metadataSha256.toLowerCase() ||
      canonicalJson(storedMetadata) !== canonicalJson(payload.metadata) || run.quality_status !== "passed" ||
      run.publication_authorized !== 0 || !executionCompatible ||
      run.created_at !== new Date(payload.createdAt).toISOString() ||
      targets.length !== stagingPlatforms.length) return false;
  const storedTargets = new Map(targets.map((target) => [target.platform, target]));
  return payload.targets.every((target) => {
    const stored = storedTargets.get(target.platform);
    return stored?.mode === target.mode && stored.idempotency_key === idempotencyKeys.get(target.platform) &&
      stored.initial_transport_state === target.transportState && stored.initial_visibility_state === target.visibilityState &&
      stored.initial_workflow_state === target.workflowState;
  });
};

const insertStagingRun = async (
  env: Env,
  payload: StagingRunPayload,
  idempotencyKeys: ReadonlyMap<StagingPlatform, string>,
): Promise<void> => {
  const insertedAt = now();
  const initialStatus: StagingRunStatus = payload.targets.every((target) => target.transportState === "planned") ? "planned" : "partial";
  const statements = [
    env.DB.prepare(`INSERT INTO upload_staging_runs (
      run_id, content_id, asset_sha256, metadata_sha256, metadata_json, status, quality_status,
      publication_authorized, execution_requested, media_url, media_project, media_branch,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, 'passed', 0, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(run_id) DO NOTHING`).bind(
      payload.runId,
      payload.contentId.toLowerCase(),
      payload.assetSha256.toLowerCase(),
      payload.metadataSha256.toLowerCase(),
      canonicalJson(payload.metadata),
      initialStatus,
      payload.executeMeta === true ? 1 : 0,
      payload.mediaUrl ?? null,
      payload.mediaProject ?? null,
      payload.mediaBranch ?? null,
      new Date(payload.createdAt).toISOString(),
      insertedAt,
    ),
    ...payload.targets.map((target) => env.DB.prepare(`INSERT INTO upload_staging_targets (
      run_id, platform, mode, idempotency_key, initial_transport_state, initial_visibility_state, initial_workflow_state,
      transport_state, visibility_state, workflow_state, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(run_id, platform) DO NOTHING`).bind(
      payload.runId,
      target.platform,
      target.mode,
      idempotencyKeys.get(target.platform)!,
      target.transportState,
      target.visibilityState,
      target.workflowState,
      target.transportState,
      target.visibilityState,
      target.workflowState,
      insertedAt,
      insertedAt,
    )),
  ];
  await env.DB.batch(statements);
};

const metaStagingConfiguration = (env: Env): string[] => [
  ["META_INSTAGRAM_USER_ACCESS_TOKEN", instagramTokenFor(env)],
  ["META_INSTAGRAM_ACCOUNT_ID", env.META_INSTAGRAM_ACCOUNT_ID],
  ["META_FACEBOOK_PAGE_ACCESS_TOKEN", env.META_FACEBOOK_PAGE_ACCESS_TOKEN],
  ["META_FACEBOOK_PAGE_ID", env.META_FACEBOOK_PAGE_ID],
  ["CLOUDFLARE_API_TOKEN", env.CLOUDFLARE_API_TOKEN],
  ["CLOUDFLARE_ACCOUNT_ID", env.CLOUDFLARE_ACCOUNT_ID],
  ["UPLOAD_STAGING_MEDIA_PROJECT", env.UPLOAD_STAGING_MEDIA_PROJECT],
].filter(([, value]) => !value).map(([name]) => name);

const createStagingRun = async (request: Request, env: Env): Promise<Response> => {
  const authorizationError = stagingAuthError(request, env);
  if (authorizationError) return authorizationError;
  const payload = await request.json().catch(() => null);
  if (!validStagingPayload(payload)) return json({ error: "Ungültiger oder nicht sicherer Staging-Auftrag." }, 400);
  if (!await validStagingHashes(payload)) return json({ error: "Metadaten-Hash oder Idempotenzschlüssel ist ungültig." }, 400);
  if (!validStagingMediaOrigin(payload, env)) return json({ error: "Die temporäre Medienquelle gehört nicht zum erlaubten Pages-Projekt." }, 400);
  const idempotencyKeys = await serverStagingKeys(env, payload);
  if (!idempotencyKeys) return json({ error: "Mindestens ein Zielkonto für den Staging-Test ist nicht konfiguriert." }, 503);
  const missing = payload.executeMeta === true ? metaStagingConfiguration(env) : [];
  if (missing.length > 0) return json({ error: "Meta-Staging ist nicht vollständig konfiguriert.", missing }, 503);
  await ensureStagingSchema(env);
  await failClosedExpiredCreateLeases(env);

  const existing = await env.DB.prepare("SELECT * FROM upload_staging_runs WHERE run_id = ?")
    .bind(payload.runId).first<StagingRunRow>();
  let created = false;
  if (!existing) {
    try {
      await insertStagingRun(env, payload, idempotencyKeys);
      created = true;
    } catch {
      return json({ error: "Run-ID oder Idempotenzschlüssel steht bereits für einen anderen Staging-Auftrag." }, 409);
    }
  }

  const [storedRun, storedTargets] = await Promise.all([
    env.DB.prepare("SELECT * FROM upload_staging_runs WHERE run_id = ?").bind(payload.runId).first<StagingRunRow>(),
    env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ? ORDER BY platform")
      .bind(payload.runId).all<StagingTargetRow>(),
  ]);
  if (!storedRun || !sameStagingRun(storedRun, storedTargets.results ?? [], payload, idempotencyKeys)) {
    return json({ error: "Run-ID steht bereits für einen abweichenden Staging-Auftrag." }, 409);
  }

  if (payload.executeMeta === true && storedRun.execution_requested === 0) {
    const upgradedAt = now();
    await env.DB.prepare(`UPDATE upload_staging_runs SET execution_requested = 1,
        media_url = ?, media_project = ?, media_branch = ?, updated_at = ?
      WHERE run_id = ? AND execution_requested = 0 AND media_url IS NULL AND media_project IS NULL AND media_branch IS NULL`)
      .bind(payload.mediaUrl!, payload.mediaProject!, payload.mediaBranch!, upgradedAt, payload.runId).run();
    const upgraded = await env.DB.prepare("SELECT * FROM upload_staging_runs WHERE run_id = ?")
      .bind(payload.runId).first<StagingRunRow>();
    if (!upgraded || upgraded.execution_requested !== 1 || upgraded.media_url !== payload.mediaUrl ||
        upgraded.media_project !== payload.mediaProject || upgraded.media_branch !== payload.mediaBranch) {
      return json({ error: "Der Staging-Plan wurde gleichzeitig mit einer anderen Medienquelle gestartet." }, 409);
    }
  }

  if (created) await stagingEvent(env, payload.runId, null, "info", "Nichtveröffentlichender Staging-Auftrag wurde angelegt.");
  if (payload.executeMeta === true) {
    await Promise.all([stageInstagramContainer(env, payload), stageFacebookDraft(env, payload)]);
  }
  await recalculateStagingRun(env, payload.runId);
  await cleanupStagingMediaIfSafe(env, payload.runId);
  const response = await stagingRunResponse(env, payload.runId);
  return json(response, created ? 201 : 200);
};

const claimExternalStagingUpload = async (request: Request, env: Env): Promise<Response> => {
  const authorizationError = stagingAuthError(request, env);
  if (authorizationError) return authorizationError;
  const payload = await request.json().catch(() => null);
  if (!validStagingClaim(payload)) return json({ error: "Ungültiger Staging-Claim." }, 400);
  await ensureStagingSchema(env);
  await failClosedExpiredCreateLeases(env);
  const target = await env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ? AND platform = 'youtube'")
    .bind(payload.runId).first<StagingTargetRow>();
  if (!target) return json({ error: "Staging-Auftrag nicht gefunden." }, 404);
  if (target.idempotency_key !== payload.idempotencyKey.toLowerCase()) {
    return json({ error: "Idempotenzschlüssel passt nicht zum verifizierten YouTube-Ziel." }, 409);
  }
  if (target.workflow_state === "private_uploaded" && target.receipt_sha256) {
    return json({ status: "already_completed", target: stagingTargetResponse(target) });
  }
  if (target.transport_state !== "planned" || target.workflow_state !== "ready" || target.remote_create_started_at) {
    return json({ error: "YouTube-Ziel ist bereits beansprucht oder muss abgestimmt werden." }, 409);
  }
  const claimId = crypto.randomUUID();
  const claimedAt = now();
  const leaseExpiresAt = new Date(Date.now() + stagingLeaseDurationMs).toISOString();
  await env.DB.prepare(`UPDATE upload_staging_targets SET transport_state = 'uploading', visibility_state = 'unknown',
      provider_status = 'EXTERNAL_CREATE_INTENT', remote_create_started_at = ?, lease_owner = ?, lease_expires_at = ?, updated_at = ?
    WHERE run_id = ? AND platform = 'youtube' AND idempotency_key = ?
      AND transport_state = 'planned' AND workflow_state = 'ready' AND remote_create_started_at IS NULL`)
    .bind(claimedAt, claimId, leaseExpiresAt, claimedAt, payload.runId, payload.idempotencyKey.toLowerCase()).run();
  const claimed = await env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ? AND platform = 'youtube'")
    .bind(payload.runId).first<StagingTargetRow>();
  if (!claimed || claimed.lease_owner !== claimId) {
    return json({ error: "YouTube-Ziel wurde gleichzeitig von einem anderen Lauf beansprucht." }, 409);
  }
  await stagingEvent(env, payload.runId, "youtube", "info", "Globaler YouTube-Claim wurde vor der Session-Erstellung gesetzt.");
  await recalculateStagingRun(env, payload.runId);
  return json({ status: "claimed", claimId, leaseExpiresAt }, 201);
};

const saveStagingReceipt = async (request: Request, env: Env): Promise<Response> => {
  const authorizationError = stagingAuthError(request, env);
  if (authorizationError) return authorizationError;
  const payload = await request.json().catch(() => null);
  if (!validStagingReceipt(payload)) return json({ error: "Ungültiger oder veröffentlichender Staging-Beleg." }, 400);
  await ensureStagingSchema(env);
  const target = await env.DB.prepare("SELECT * FROM upload_staging_targets WHERE run_id = ? AND platform = ?")
    .bind(payload.runId, payload.platform).first<StagingTargetRow>();
  if (!target) return json({ error: "Staging-Auftrag nicht gefunden." }, 404);
  if (target.idempotency_key !== payload.idempotencyKey.toLowerCase()) {
    return json({ error: "Idempotenzschlüssel passt nicht zum Staging-Ziel." }, 409);
  }
  const expectedAccountFingerprint = env.YOUTUBE_CHANNEL_ID
    ? await sha256Hex({ platform: "youtube", accountId: env.YOUTUBE_CHANNEL_ID.trim() })
    : null;
  if (!expectedAccountFingerprint || payload.accountFingerprint.toLowerCase() !== expectedAccountFingerprint) {
    return json({ error: "YouTube-Beleg gehört nicht zum konfigurierten Zielkanal." }, 409);
  }
  if (target.workflow_state === "safety_violation" || target.workflow_state === "expired" ||
      target.provider_status?.toUpperCase() === "PUBLISHED") {
    return json({ error: "Der Plattformzustand kann nicht sicher durch einen Beleg überschrieben werden." }, 409);
  }
  const remoteObjectId = payload.remoteObjectId ?? null;
  if (target.remote_object_id && target.remote_object_id !== remoteObjectId) {
    return json({ error: "Remote-Objekt-ID widerspricht dem bereits bekannten Plattformzustand." }, 409);
  }
  const receiptSha256 = await sha256Hex({
    schemaVersion: 1,
    lane: "non-publishing",
    runId: payload.runId,
    platform: payload.platform,
    idempotencyKey: payload.idempotencyKey.toLowerCase(),
    claimId: payload.claimId,
    accountFingerprint: payload.accountFingerprint.toLowerCase(),
    confirmedAt: new Date(payload.confirmedAt).toISOString(),
    transportState: payload.transportState,
    visibilityState: payload.visibilityState,
    workflowState: payload.workflowState,
    remoteObjectId,
    providerStatus: payload.providerStatus ?? null,
    publishedAt: null,
    scheduledFor: null,
    publicUrl: null,
  });
  if (target.receipt_sha256 && target.receipt_sha256 !== receiptSha256) {
    return json({ error: "Für dieses Staging-Ziel wurde bereits ein anderer Beleg angenommen." }, 409);
  }
  if (!target.receipt_sha256) {
    if (target.lease_owner !== payload.claimId || target.transport_state !== "uploading") {
      return json({ error: "Der YouTube-Beleg gehört zu keinem aktiven globalen Claim." }, 409);
    }
    const receivedAt = now();
    await env.DB.prepare(`UPDATE upload_staging_targets SET
        transport_state = 'ready', visibility_state = 'non_public', workflow_state = ?,
        remote_object_id = ?, provider_status = ?, receipt_sha256 = ?, last_error = NULL,
        lease_owner = NULL, lease_expires_at = NULL, updated_at = ?
      WHERE run_id = ? AND platform = ? AND idempotency_key = ? AND receipt_sha256 IS NULL
        AND workflow_state NOT IN ('safety_violation', 'expired')`)
      .bind(payload.workflowState, remoteObjectId, payload.providerStatus ?? null, receiptSha256,
        receivedAt, payload.runId, payload.platform, payload.idempotencyKey.toLowerCase()).run();
    const saved = await env.DB.prepare("SELECT receipt_sha256 FROM upload_staging_targets WHERE run_id = ? AND platform = ?")
      .bind(payload.runId, payload.platform).first<{ receipt_sha256: string | null }>();
    if (saved?.receipt_sha256 !== receiptSha256) {
      return json({ error: "Gleichzeitiger abweichender Beleg; Zustand wurde nicht überschrieben." }, 409);
    }
    await stagingEvent(env, payload.runId, payload.platform, "info", "Nichtveröffentlichender Plattformbeleg wurde angenommen.");
  }
  await recalculateStagingRun(env, payload.runId);
  return json(await stagingRunResponse(env, payload.runId), target.receipt_sha256 ? 200 : 202);
};

const getStagingRun = async (request: Request, env: Env, runId: string): Promise<Response> => {
  const authorizationError = stagingAuthError(request, env);
  if (authorizationError) return authorizationError;
  if (!/^[a-z0-9][a-z0-9_-]{3,119}$/i.test(runId)) return json({ error: "Ungültige Run-ID." }, 400);
  await ensureStagingSchema(env);
  await failClosedExpiredCreateLeases(env);
  await recalculateStagingRun(env, runId);
  const response = await stagingRunResponse(env, runId);
  return response ? json(response) : json({ error: "Nicht gefunden." }, 404);
};

const pollStagingRun = async (request: Request, env: Env): Promise<Response> => {
  const authorizationError = stagingAuthError(request, env);
  if (authorizationError) return authorizationError;
  const payload = await request.json().catch(() => null) as { runId?: unknown } | null;
  const runId = typeof payload?.runId === "string" ? payload.runId : "";
  if (!/^[a-z0-9][a-z0-9_-]{3,119}$/i.test(runId)) return json({ error: "Ungültige Run-ID." }, 400);
  await inspectInstagramStaging(env, runId, false);
  await recalculateStagingRun(env, runId);
  const cleanupStatus = await cleanupStagingMediaIfSafe(env, runId);
  const response = await stagingRunResponse(env, runId);
  return response ? json({ ...response, cleanupStatus }) : json({ error: "Nicht gefunden." }, 404);
};

interface StagingFeedTargetRow extends StagingTargetRow { readonly content_id: string; }

const stagingFeed = async (env: Env): Promise<Response> => {
  await ensureStagingSchema(env);
  const [runs, targets] = await Promise.all([
    env.DB.prepare("SELECT * FROM upload_staging_runs ORDER BY created_at DESC LIMIT 100").all<StagingRunRow>(),
    env.DB.prepare(`SELECT target.*, run.content_id FROM upload_staging_targets AS target
      JOIN upload_staging_runs AS run ON run.run_id = target.run_id
      WHERE target.run_id IN (SELECT run_id FROM upload_staging_runs ORDER BY created_at DESC LIMIT 100)
      ORDER BY run.created_at DESC, target.platform`).all<StagingFeedTargetRow>(),
  ]);
  const body = {
    schemaVersion: 1,
    lane: "non-publishing",
    publicationAuthorized: false,
    generatedAt: now(),
    runs: (runs.results ?? []).map((run) => ({
      runId: run.run_id,
      contentId: run.content_id,
      title: null,
      status: run.status,
      qualityStatus: run.quality_status,
      startedAt: run.created_at,
      completedAt: run.completed_at,
    })),
    publications: (targets.results ?? []).map((target) => ({
      runId: target.run_id,
      contentId: target.content_id,
      platform: target.platform,
      mode: target.mode,
      status: ["private_uploaded", "container_unpublished", "draft", "manual_uploaded"].includes(target.workflow_state)
        ? target.workflow_state
        : target.transport_state,
      updatedAt: target.updated_at,
      title: null,
      scheduledAt: null,
      publishedAt: null,
      publicUrl: null,
    })),
  };
  return new Response(JSON.stringify(body), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=30, s-maxage=30",
      "access-control-allow-origin": "*",
    },
  });
};

const publicationFailureCode = (error: string | null): PublicationFailureCode => {
  const value = (error ?? "").normalize("NFKC").toLowerCase();
  if (value.includes("api access blocked") || (value.includes("api-zugriff") && value.includes("blockiert"))) return "api_access_blocked";
  if (/page-token|access[_ -]?token|oauth|token.*(invalid|expired|ungueltig|abgelaufen)|invalid.*token/.test(value)) return "authentication_failed";
  if (/permission|berechtigung|not authorized|not authorised|code[\"': ]+200/.test(value)) return "permission_denied";
  if (/rate.?limit|quota|too many requests|code[\"': ]+(4|17|32|613)\b/.test(value)) return "rate_limited";
  if (/media|video.*(download|fetch|unavailable)|source url|mp4/.test(value)) return "media_unavailable";
  if (/timeout|timed out|processing.*(expired|timeout)/.test(value)) return "processing_timeout";
  if (/rejected|unsupported|invalid parameter|code[\"': ]+(100|36000)\b/.test(value)) return "platform_rejected";
  return "unknown";
};

/**
 * Public, read-only production queue projection. Raw provider errors and every
 * remote/media identifier stay inside D1; the dashboard receives only the
 * minimum state needed to distinguish planned, active, failed and completed
 * publication attempts.
 */
const publicationFeed = async (env: Env): Promise<Response> => {
  const jobs = await env.DB.prepare(`SELECT source_video_id, platform, publish_at, status,
      last_error, updated_at, published_at
    FROM meta_publication_jobs
    ORDER BY updated_at DESC LIMIT 400`).all<PublicationFeedJobRow>();
  const publications = (jobs.results ?? [])
    .filter((job) => /^[a-z0-9][a-z0-9._-]{2,199}$/i.test(job.source_video_id) && validPlatform(job.platform))
    .map((job) => ({
      contentId: job.source_video_id,
      platform: job.platform,
      status: job.status,
      scheduledAt: job.publish_at,
      updatedAt: job.updated_at,
      publishedAt: job.status === "published" ? job.published_at : null,
      failureCode: job.status === "failed" ? publicationFailureCode(job.last_error) : null,
    }));
  return new Response(JSON.stringify({
    schemaVersion: 1,
    lane: "production-publication",
    generatedAt: now(),
    publications,
  }), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=15, s-maxage=15",
      "access-control-allow-origin": "*",
    },
  });
};

const analyticsMetricNames: ReadonlyArray<keyof SocialMetrics> = [
  "views", "reach", "likes", "comments", "shares", "saves", "watchTimeMinutes",
  "averageViewDurationSeconds", "averageViewPercentage", "followersGained",
];

const nullableNumber = (value: unknown): number | null => {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizedMetrics = (value: unknown): SocialMetrics => {
  const input = value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
  return Object.fromEntries(analyticsMetricNames.map((name) => [name, nullableNumber(input[name])])) as unknown as SocialMetrics;
};

const normalizedSocialVideo = (value: unknown): SocialVideo | null => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const item = value as Record<string, unknown>;
  const platformVideoId = String(item.platformVideoId ?? "").trim();
  if (!platformVideoId || platformVideoId.length > 200) return null;
  const publishedAt = typeof item.publishedAt === "string" && Number.isFinite(Date.parse(item.publishedAt))
    ? new Date(item.publishedAt).toISOString()
    : null;
  return {
    platformVideoId,
    contentId: typeof item.contentId === "string" && item.contentId.trim() ? item.contentId.trim().slice(0, 200) : null,
    title: String(item.title ?? "Ohne Titel").trim().slice(0, 240),
    description: String(item.description ?? "").trim().slice(0, 2000),
    publishedAt,
    url: typeof item.url === "string" && item.url.startsWith("https://") ? item.url.slice(0, 1000) : null,
    thumbnailUrl: typeof item.thumbnailUrl === "string" && item.thumbnailUrl.startsWith("https://") ? item.thumbnailUrl.slice(0, 1000) : null,
    status: String(item.status ?? "published").trim().slice(0, 40),
    durationSeconds: nullableNumber(item.durationSeconds),
    metrics: normalizedMetrics(item.metrics),
  };
};

const ensureAnalyticsSchema = async (env: Env): Promise<void> => {
  const statements = [
    `CREATE TABLE IF NOT EXISTS social_analytics_platforms (
      platform TEXT PRIMARY KEY, status TEXT NOT NULL, account_name TEXT, reason TEXT, updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS social_analytics_videos (
      platform TEXT NOT NULL, platform_video_id TEXT NOT NULL, content_id TEXT, title TEXT NOT NULL,
      description TEXT NOT NULL, published_at TEXT, url TEXT, thumbnail_url TEXT, status TEXT NOT NULL,
      duration_seconds REAL, metrics_json TEXT NOT NULL, updated_at TEXT NOT NULL,
      PRIMARY KEY(platform, platform_video_id)
    )`,
    `CREATE TABLE IF NOT EXISTS social_analytics_snapshots (
      platform TEXT NOT NULL, platform_video_id TEXT NOT NULL, captured_date TEXT NOT NULL,
      captured_at TEXT NOT NULL, metrics_json TEXT NOT NULL,
      PRIMARY KEY(platform, platform_video_id, captured_date)
    )`,
    `CREATE TABLE IF NOT EXISTS social_analytics_state (
      state_key TEXT PRIMARY KEY, state_value TEXT NOT NULL, updated_at TEXT NOT NULL
    )`,
    "CREATE INDEX IF NOT EXISTS social_analytics_snapshots_date_idx ON social_analytics_snapshots(captured_at)",
  ];
  for (const statement of statements) await env.DB.prepare(statement).run();
};

const analyticsState = async (env: Env, key: string): Promise<string | null> => {
  const row = await env.DB.prepare("SELECT state_value FROM social_analytics_state WHERE state_key = ?")
    .bind(key).first<{ state_value: string }>();
  return row?.state_value ?? null;
};

const setAnalyticsState = async (env: Env, key: string, value: string): Promise<void> => {
  await env.DB.prepare(`INSERT INTO social_analytics_state (state_key, state_value, updated_at) VALUES (?, ?, ?)
    ON CONFLICT(state_key) DO UPDATE SET state_value = excluded.state_value, updated_at = excluded.updated_at`)
    .bind(key, value, now()).run();
};

const safeAnalyticsReason = (reason: unknown): string => {
  const value = String(reason ?? "");
  if (/^Facebook-Basisdaten geladen; Video-Insights fehlen fuer \d+ Videos?\. Erweiterte Insights erfordern read_insights und pages_manage_engagement\.$/.test(value)) return value;
  const status = value.match(/HTTP\s+(\d{3})/i)?.[1];
  return status
    ? `Meta Analytics HTTP ${status}. Berechtigung oder Metrikverfuegbarkeit pruefen.`
    : "Meta Analytics konnte voruebergehend nicht vollstaendig aktualisiert werden.";
};

const saveAnalyticsPlatform = async (
  env: Env,
  platform: SocialPlatform,
  accountName: string | null,
  videos: SocialVideo[],
  collectedAt: string,
  status: "available" | "partial" = "available",
  reason: string | null = null,
): Promise<void> => {
  const previousMetrics = new Map<string, SocialMetrics>();
  if (status === "partial") {
    const previous = await env.DB.prepare("SELECT platform_video_id, metrics_json FROM social_analytics_videos WHERE platform = ?")
      .bind(platform).all<{ platform_video_id: string; metrics_json: string }>();
    for (const row of previous.results ?? []) {
      try { previousMetrics.set(row.platform_video_id, normalizedMetrics(JSON.parse(row.metrics_json))); } catch { /* Ignore invalid legacy metrics. */ }
    }
  }
  await env.DB.prepare(`INSERT INTO social_analytics_platforms (platform, status, account_name, reason, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(platform) DO UPDATE SET status = excluded.status, account_name = excluded.account_name,
      reason = excluded.reason, updated_at = excluded.updated_at`)
    .bind(platform, status, accountName, reason ? safeAnalyticsReason(reason) : null, collectedAt).run();
  await env.DB.prepare("DELETE FROM social_analytics_videos WHERE platform = ?").bind(platform).run();
  const capturedDate = collectedAt.slice(0, 10);
  for (const item of videos) {
    let contentId = item.contentId ?? null;
    if (!contentId && (platform === "instagram" || platform === "facebook")) {
      const link = await env.DB.prepare(`SELECT source_video_id FROM meta_publication_jobs
        WHERE platform = ? AND platform_video_id = ? LIMIT 1`).bind(platform, item.platformVideoId)
        .first<{ source_video_id: string }>();
      contentId = link?.source_video_id ?? null;
    }
    const previous = previousMetrics.get(item.platformVideoId);
    const effectiveMetrics = previous
      ? Object.fromEntries(analyticsMetricNames.map((name) => [name, item.metrics[name] ?? previous[name] ?? null])) as unknown as SocialMetrics
      : item.metrics;
    const metricsJson = JSON.stringify(effectiveMetrics);
    await env.DB.prepare(`INSERT INTO social_analytics_videos (
      platform, platform_video_id, content_id, title, description, published_at, url, thumbnail_url,
      status, duration_seconds, metrics_json, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(platform, item.platformVideoId, contentId, item.title, item.description, item.publishedAt,
        item.url, item.thumbnailUrl, item.status, item.durationSeconds, metricsJson, collectedAt).run();
    await env.DB.prepare(`INSERT INTO social_analytics_snapshots (
      platform, platform_video_id, captured_date, captured_at, metrics_json
    ) VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(platform, platform_video_id, captured_date) DO UPDATE SET
      captured_at = excluded.captured_at, metrics_json = excluded.metrics_json`)
      .bind(platform, item.platformVideoId, capturedDate, collectedAt, metricsJson).run();
  }
  // Manual prototype uploads predate the publication registry. An exact shared
  // description is deterministic for these cross-posts and lets the already
  // linked YouTube record supply the stable content ID without fuzzy guessing.
  // Future automated uploads continue to use meta_publication_jobs first.
  await env.DB.prepare(`UPDATE social_analytics_videos AS target
    SET content_id = (
      SELECT source.content_id FROM social_analytics_videos AS source
      WHERE source.platform = 'youtube' AND source.content_id IS NOT NULL
        AND source.description = target.description
      LIMIT 1
    )
    WHERE target.platform IN ('instagram', 'facebook') AND target.content_id IS NULL
      AND target.description <> ''
      AND 1 = (
        SELECT COUNT(*) FROM social_analytics_videos AS candidate
        WHERE candidate.platform = 'youtube' AND candidate.content_id IS NOT NULL
          AND candidate.description = target.description
      )`).run();
};

const saveAnalyticsError = async (env: Env, platform: SocialPlatform, reason: string): Promise<void> => {
  const existing = await env.DB.prepare("SELECT COUNT(*) AS count FROM social_analytics_videos WHERE platform = ?")
    .bind(platform).first<{ count: number }>();
  const status = Number(existing?.count ?? 0) > 0 ? "partial" : "error";
  await env.DB.prepare(`INSERT INTO social_analytics_platforms (platform, status, account_name, reason, updated_at)
    VALUES (?, ?, NULL, ?, ?)
    ON CONFLICT(platform) DO UPDATE SET status = excluded.status, reason = excluded.reason, updated_at = excluded.updated_at`)
    .bind(platform, status, safeAnalyticsReason(reason), now()).run();
};

const insightValues = (payload: Record<string, unknown>): Record<string, unknown> => Object.fromEntries(
  (Array.isArray(payload.data) ? payload.data : []).map((raw) => {
    const metric = raw as Record<string, unknown>;
    const values = Array.isArray(metric.values) ? metric.values : [];
    const latest = values.at(-1) as Record<string, unknown> | undefined;
    const total = metric.total_value as Record<string, unknown> | undefined;
    return [String(metric.name ?? ""), latest?.value ?? total?.value ?? null];
  }).filter(([name]) => Boolean(name)),
);

const analyticsGraph = async (
  platform: Platform,
  env: Env,
  path: string,
  parameters: Record<string, string>,
): Promise<Record<string, unknown>> => {
  const query = new URLSearchParams(parameters);
  const response = await fetch(`${graphUrl(platform, env, path)}?${query.toString()}`, {
    headers: { Authorization: `Bearer ${tokenFor(platform, env)}` },
  });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) throw metaApiError(body, response.status);
  return body;
};

const facebookReelMetrics = [
  "blue_reels_play_count",
  "post_impressions_unique",
  "post_video_avg_time_watched",
  "post_video_view_time",
  "post_video_followers",
] as const;
const facebookClassicVideoMetrics = [
  "total_video_views",
  "total_video_views_unique",
  "total_video_view_total_time",
  "total_video_avg_time_watched",
] as const;

const hasNumericInsight = (insights: Record<string, unknown>, names: readonly string[]): boolean =>
  names.some((name) => nullableNumber(insights[name]) !== null);

const facebookVideoInsights = async (env: Env, videoId: string): Promise<{
  kind: "reel" | "classic" | null;
  insights: Record<string, unknown>;
  reason: string | null;
}> => {
  const read = async (names: readonly string[]): Promise<Record<string, unknown>> => insightValues(
    await analyticsGraph("facebook", env, `${videoId}/video_insights`, { metric: names.join(","), period: "lifetime" }),
  );
  const safeFailures: string[] = [];
  try {
    const insights = await read(facebookReelMetrics);
    if (hasNumericInsight(insights, facebookReelMetrics)) return { kind: "reel", insights, reason: null };
    safeFailures.push("Der Reel-Insights-Endpunkt lieferte keine nutzbaren Metriken.");
  } catch (error) {
    safeFailures.push(safeAnalyticsReason(error instanceof Error ? error.message : error));
  }
  try {
    const insights = await read(facebookClassicVideoMetrics);
    if (hasNumericInsight(insights, facebookClassicVideoMetrics)) return { kind: "classic", insights, reason: null };
    safeFailures.push("Der klassische Video-Insights-Endpunkt lieferte keine nutzbaren Metriken.");
  } catch (error) {
    safeFailures.push(safeAnalyticsReason(error instanceof Error ? error.message : error));
  }
  return { kind: null, insights: {}, reason: [...new Set(safeFailures)].join(" ").slice(0, 240) };
};

const collectInstagramAnalytics = async (env: Env): Promise<{ accountName: string | null; videos: SocialVideo[] }> => {
  const accountId = accountFor("instagram", env);
  const account = await analyticsGraph("instagram", env, accountId, { fields: "username,name" });
  const media = await analyticsGraph("instagram", env, `${accountId}/media`, {
    fields: "id,caption,media_type,media_product_type,permalink,timestamp,thumbnail_url,like_count,comments_count",
    limit: "100",
  });
  const videos: SocialVideo[] = [];
  for (const raw of Array.isArray(media.data) ? media.data : []) {
    const item = raw as Record<string, unknown>;
    if (!(["VIDEO", "REELS"].includes(String(item.media_type))) && item.media_product_type !== "REELS") continue;
    let insights: Record<string, unknown> = {};
    try {
      insights = insightValues(await analyticsGraph("instagram", env, `${String(item.id)}/insights`, {
        metric: "views,reach,saved,shares,total_interactions",
      }));
    } catch { /* Basic counters still provide a valid partial record. */ }
    const entry = normalizedSocialVideo({
      platformVideoId: item.id,
      title: String(item.caption ?? "").split("\n")[0],
      description: item.caption,
      publishedAt: item.timestamp,
      url: item.permalink,
      thumbnailUrl: item.thumbnail_url,
      status: "published",
      metrics: {
        views: insights.views, reach: insights.reach, likes: item.like_count, comments: item.comments_count,
        shares: insights.shares, saves: insights.saved,
      },
    });
    if (entry) videos.push(entry);
  }
  return { accountName: String(account.username ?? account.name ?? "") || null, videos };
};

const collectFacebookAnalytics = async (env: Env): Promise<{
  accountName: string | null;
  videos: SocialVideo[];
  status: "available" | "partial";
  reason: string | null;
}> => {
  const pageId = accountFor("facebook", env);
  const account = await analyticsGraph("facebook", env, pageId, { fields: "name" });
  const media = await analyticsGraph("facebook", env, `${pageId}/videos`, {
    fields: "id,title,description,created_time,permalink_url,published,status,length,likes.limit(0).summary(true),comments.limit(0).summary(true)",
    limit: "100",
  });
  const videos: SocialVideo[] = [];
  const insightFailures: string[] = [];
  for (const raw of Array.isArray(media.data) ? media.data : []) {
    const item = raw as Record<string, unknown>;
    const rawStatus = String((item.status as Record<string, unknown> | undefined)?.video_status ?? "").toLowerCase();
    if (item.published === false || ["processing", "error", "blocked", "copyright_blocked"].includes(rawStatus)) continue;
    const insightResult = await facebookVideoInsights(env, String(item.id));
    const insights = insightResult.insights;
    if (!insightResult.kind && insightResult.reason) insightFailures.push(insightResult.reason);
    const isReel = insightResult.kind === "reel";
    const likes = (item.likes as Record<string, unknown> | undefined)?.summary as Record<string, unknown> | undefined;
    const comments = (item.comments as Record<string, unknown> | undefined)?.summary as Record<string, unknown> | undefined;
    const totalTime = nullableNumber(isReel ? insights.post_video_view_time : insights.total_video_view_total_time);
    const averageTime = nullableNumber(isReel ? insights.post_video_avg_time_watched : insights.total_video_avg_time_watched);
    const entry = normalizedSocialVideo({
      platformVideoId: item.id,
      title: item.title,
      description: item.description,
      publishedAt: item.created_time,
      url: verifiedFacebookPermalink(item.id, item.permalink_url),
      status: "published",
      durationSeconds: item.length,
      metrics: {
        views: isReel ? insights.blue_reels_play_count : insights.total_video_views,
        reach: isReel ? insights.post_impressions_unique : insights.total_video_views_unique,
        likes: likes?.total_count,
        comments: comments?.total_count,
        watchTimeMinutes: totalTime === null ? null : totalTime / 60000,
        averageViewDurationSeconds: averageTime === null ? null : averageTime / 1000,
        followersGained: isReel ? insights.post_video_followers : null,
      },
    });
    if (entry) videos.push(entry);
  }
  const failureCount = insightFailures.length;
  return {
    accountName: String(account.name ?? "") || null,
    videos,
    status: failureCount > 0 ? "partial" : "available",
    reason: failureCount > 0
      ? `Facebook-Basisdaten geladen; Video-Insights fehlen fuer ${failureCount} ${failureCount === 1 ? "Video" : "Videos"}. Erweiterte Insights erfordern read_insights und pages_manage_engagement.`
      : null,
  };
};

const refreshMetaAnalyticsIfDue = async (env: Env, force = false): Promise<void> => {
  await ensureAnalyticsSchema(env);
  const lastAttempt = await analyticsState(env, "meta_last_attempt");
  if (!force && lastAttempt && Date.now() - Date.parse(lastAttempt) < 55 * 60 * 1000) return;
  const collectedAt = now();
  await setAnalyticsState(env, "meta_last_attempt", collectedAt);
  for (const [platform, collector] of [
    ["instagram", collectInstagramAnalytics],
    ["facebook", collectFacebookAnalytics],
  ] as const) {
    try {
      const result = await collector(env);
      const status = "status" in result ? result.status : "available";
      const reason = "reason" in result ? result.reason : null;
      await saveAnalyticsPlatform(env, platform, result.accountName, result.videos, collectedAt, status, reason);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Meta Analytics konnte nicht aktualisiert werden.";
      await saveAnalyticsError(env, platform, message);
    }
  }
  await env.DB.prepare("DELETE FROM social_analytics_snapshots WHERE captured_at < ?")
    .bind(new Date(Date.now() - 90 * 86400000).toISOString()).run();
};

const validAnalyticsIngest = (value: unknown): value is AnalyticsIngestPayload => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const item = value as Record<string, unknown>;
  return item.schemaVersion === 1 && (item.platform === "youtube" || item.platform === "tiktok") &&
    typeof item.collectedAt === "string" && Number.isFinite(Date.parse(item.collectedAt)) &&
    Array.isArray(item.videos) && item.videos.length <= 500;
};

const ingestAnalytics = async (request: Request, env: Env): Promise<Response> => {
  if (!env.ANALYTICS_INGEST_TOKEN || request.headers.get("authorization") !== `Bearer ${env.ANALYTICS_INGEST_TOKEN}`) {
    return json({ error: "Nicht autorisiert." }, 401);
  }
  const payload = await request.json().catch(() => null);
  if (!validAnalyticsIngest(payload)) return json({ error: "Ungültiger Analytics-Datensatz." }, 400);
  const videos = payload.videos.map(normalizedSocialVideo).filter((item): item is SocialVideo => item !== null);
  if (videos.length !== payload.videos.length) return json({ error: "Mindestens ein Video ist ungültig." }, 400);
  await ensureAnalyticsSchema(env);
  await saveAnalyticsPlatform(env, payload.platform, payload.accountName ?? null, videos, new Date(payload.collectedAt).toISOString());
  return json({ status: "accepted", platform: payload.platform, videoCount: videos.length }, 202);
};

interface AnalyticsPlatformRow { platform: SocialPlatform; status: string; account_name: string | null; reason: string | null; updated_at: string; }
interface AnalyticsVideoRow {
  platform: SocialPlatform; platform_video_id: string; content_id: string | null; title: string; description: string;
  published_at: string | null; url: string | null; thumbnail_url: string | null; status: string;
  duration_seconds: number | null; metrics_json: string; updated_at: string;
}
interface AnalyticsSnapshotRow { platform: SocialPlatform; platform_video_id: string; captured_at: string; metrics_json: string; }

const analyticsFeed = async (env: Env): Promise<Response> => {
  await ensureAnalyticsSchema(env);
  const [platformRows, videoRows, snapshotRows] = await Promise.all([
    env.DB.prepare("SELECT * FROM social_analytics_platforms ORDER BY platform").all<AnalyticsPlatformRow>(),
    env.DB.prepare("SELECT * FROM social_analytics_videos ORDER BY published_at DESC LIMIT 500").all<AnalyticsVideoRow>(),
    env.DB.prepare("SELECT platform, platform_video_id, captured_at, metrics_json FROM social_analytics_snapshots ORDER BY captured_at DESC LIMIT 10000").all<AnalyticsSnapshotRow>(),
  ]);
  const platforms = Object.fromEntries((platformRows.results ?? []).map((row) => [row.platform, {
    status: row.status,
    accountName: row.account_name,
    reason: row.reason,
    completedAt: row.updated_at,
  }]));
  const videos = (videoRows.results ?? []).map((row) => ({
    platform: row.platform,
    platformVideoId: row.platform_video_id,
    contentId: row.content_id,
    title: row.title,
    description: row.description,
    publishedAt: row.published_at,
    url: row.url,
    thumbnailUrl: row.thumbnail_url,
    status: row.status,
    durationSeconds: row.duration_seconds,
    metrics: normalizedMetrics(JSON.parse(row.metrics_json)),
  }));
  const snapshots = (snapshotRows.results ?? []).map((row) => ({
    platform: row.platform,
    platformVideoId: row.platform_video_id,
    capturedAt: row.captured_at,
    metrics: normalizedMetrics(JSON.parse(row.metrics_json)),
  }));
  return new Response(JSON.stringify({ schemaVersion: 1, generatedAt: now(), platforms, videos, snapshots }), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=300, s-maxage=300",
      "access-control-allow-origin": "*",
    },
  });
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") return json({ status: "ok", scheduler: "cloudflare", analytics: "enabled" });
    if (request.method === "GET" && url.pathname === "/analytics/feed") return analyticsFeed(env);
    if (request.method === "POST" && url.pathname === "/analytics/ingest") return ingestAnalytics(request, env);
    if (request.method === "GET" && url.pathname === "/staging/feed") return stagingFeed(env);
    if (request.method === "GET" && url.pathname === "/publication/feed") return publicationFeed(env);
    if (request.method === "POST" && url.pathname === "/staging/runs") return createStagingRun(request, env);
    if (request.method === "POST" && url.pathname === "/staging/claims") return claimExternalStagingUpload(request, env);
    if (request.method === "POST" && url.pathname === "/staging/receipts") return saveStagingReceipt(request, env);
    if (request.method === "POST" && url.pathname === "/staging/poll") return pollStagingRun(request, env);
    if (request.method === "GET" && url.pathname.startsWith("/staging/runs/")) {
      return getStagingRun(request, env, url.pathname.slice("/staging/runs/".length));
    }
    if (!authorized(request, env)) return json({ error: "Nicht autorisiert." }, 401);
    if (request.method === "GET" && url.pathname === "/ready") {
      const missing = [
        ["META_INSTAGRAM_USER_ACCESS_TOKEN", instagramTokenFor(env)],
        ["META_INSTAGRAM_ACCOUNT_ID", env.META_INSTAGRAM_ACCOUNT_ID],
        ["META_FACEBOOK_PAGE_ACCESS_TOKEN", env.META_FACEBOOK_PAGE_ACCESS_TOKEN],
        ["META_FACEBOOK_PAGE_ID", env.META_FACEBOOK_PAGE_ID],
        ["CLOUDFLARE_API_TOKEN", env.CLOUDFLARE_API_TOKEN],
        ["CLOUDFLARE_ACCOUNT_ID", env.CLOUDFLARE_ACCOUNT_ID],
      ].filter(([, value]) => !value).map(([name]) => name);
      if (missing.length > 0) return json({ status: "configuration_incomplete", missing });
      const [instagram, facebook] = await Promise.all([
        metaCredentialStatus("instagram", env),
        metaCredentialStatus("facebook", env),
      ]);
      return json({
        status: instagram.status === "ready" && facebook.status === "ready" ? "ready" : "credentials_invalid",
        missing: [],
        credentials: { instagram, facebook },
      });
    }
    if (request.method === "POST" && url.pathname === "/analytics/refresh-meta") {
      await refreshMetaAnalyticsIfDue(env, true);
      return json({ status: "refreshed" });
    }
    if (request.method === "POST" && url.pathname === "/jobs") return enqueue(request, env);
    if (request.method === "GET" && url.pathname.startsWith("/jobs/")) {
      const job = await env.DB.prepare("SELECT * FROM meta_publication_jobs WHERE job_id = ?").bind(url.pathname.slice("/jobs/".length)).first<Job>();
      return job ? json(job) : json({ error: "Nicht gefunden." }, 404);
    }
    return json({ error: "Nicht gefunden." }, 404);
  },
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    await Promise.all([processDue(env), refreshMetaAnalyticsIfDue(env), inspectInstagramStaging(env)]);
  },
} satisfies ExportedHandler<Env>;
