interface D1Statement {
  bind(...values: unknown[]): D1Statement;
  run(): Promise<unknown>;
  all<T>(): Promise<{ results?: T[] }>;
  first<T>(): Promise<T | null>;
}

interface D1Database { prepare(query: string): D1Statement; }
interface ScheduledEvent { readonly scheduledTime: number; }
interface ExportedHandler<T> {
  fetch?(request: Request, env: T): Response | Promise<Response>;
  scheduled?(event: ScheduledEvent, env: T): void | Promise<void>;
}

export interface Env {
  DB: D1Database;
  META_QUEUE_TOKEN: string;
  ANALYTICS_INGEST_TOKEN?: string;
  META_ACCESS_TOKEN: string;
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

const event = async (env: Env, jobId: string, level: "info" | "warning" | "error", message: string): Promise<void> => {
  await env.DB.prepare("INSERT INTO meta_publication_events (job_id, timestamp, level, message) VALUES (?, ?, ?, ?)")
    .bind(jobId, now(), level, message.slice(0, 1000)).run();
};

const graphVersion = (env: Env): string => env.META_GRAPH_API_VERSION || "v24.0";
const graphBase = (platform: Platform): string => platform === "instagram" ? "https://graph.instagram.com" : "https://graph.facebook.com";
const accountFor = (platform: Platform, env: Env): string => platform === "instagram" ? env.META_INSTAGRAM_ACCOUNT_ID : env.META_FACEBOOK_PAGE_ID;
const graphUrl = (platform: Platform, env: Env, path: string): string => `${graphBase(platform)}/${graphVersion(env)}/${path.replace(/^\//, "")}`;

/** Meta accepts a user token locally, but the Page Reels edge requires the
 * short-lived Page token derived from it. Resolve it per Worker invocation and
 * never persist or expose it. */
const pageTokenFor = async (env: Env): Promise<string> => {
  const parameters = new URLSearchParams({ fields: "access_token", access_token: env.META_FACEBOOK_PAGE_ACCESS_TOKEN });
  const response = await fetch(`${graphUrl("facebook", env, accountFor("facebook", env))}?${parameters.toString()}`);
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || typeof body.access_token !== "string" || !body.access_token) {
    throw new Error("Facebook konnte keinen berechtigten Page-Token ableiten.");
  }
  return body.access_token;
};

const tokenFor = async (platform: Platform, env: Env): Promise<string> =>
  platform === "instagram" ? env.META_ACCESS_TOKEN : pageTokenFor(env);

const graph = async (job: Job, env: Env, path: string, values: Record<string, string>, method: "GET" | "POST" = "POST"): Promise<Record<string, unknown>> => {
  const params = new URLSearchParams({ ...values, access_token: await tokenFor(job.platform, env) });
  const response = method === "GET"
    ? await fetch(`${graphUrl(job.platform, env, path)}?${params.toString()}`)
    : await fetch(graphUrl(job.platform, env, path), { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: params });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) {
    const error = typeof body.error === "object" && body.error ? JSON.stringify(body.error) : `HTTP ${response.status}`;
    throw new Error(`Meta API: ${error}`);
  }
  return body;
};

const metadata = (job: Job): Metadata => JSON.parse(job.metadata_json) as Metadata;

const setState = async (env: Env, job: Job, state: JobStatus, changes: Partial<Job> & { readonly publishedAt?: string } = {}): Promise<void> => {
  await env.DB.prepare(`UPDATE meta_publication_jobs
      SET status = ?, attempt_count = ?, platform_video_id = ?, publication_url = ?, container_id = ?, last_error = ?, updated_at = ?, published_at = ?
      WHERE job_id = ?`)
    .bind(state, changes.attempt_count ?? job.attempt_count, changes.platform_video_id ?? job.platform_video_id,
      changes.publication_url ?? job.publication_url, changes.container_id ?? job.container_id,
      changes.last_error ?? job.last_error, now(), changes.publishedAt ?? (state === "published" ? now() : null), job.job_id).run();
};

const publicUrl = (platform: Platform, id: string): string => platform === "instagram" ? `https://www.instagram.com/p/${id}/` : `https://www.facebook.com/${id}`;

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
    await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${job.media_project}/deployments/${deployment.id}`, {
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
  if (code === "IN_PROGRESS" || code === "" || code === "PUBLISHED") return;
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
  const session = await graph(job, env, edge, { upload_phase: "start" });
  const videoId = typeof session.video_id === "string" ? session.video_id : null;
  const uploadUrl = typeof session.upload_url === "string" ? session.upload_url : null;
  if (!videoId || !uploadUrl) throw new Error("Facebook lieferte keine Reels-Upload-Session.");
  const media = await fetch(job.media_url);
  if (!media.ok || !media.body) throw new Error("Die vorbereitete Cloud-MP4 ist nicht mehr erreichbar.");
  const size = media.headers.get("content-length");
  const uploaded = await fetch(uploadUrl, {
    method: "POST",
    headers: { Authorization: `OAuth ${await tokenFor("facebook", env)}`, offset: "0", file_size: size || "0", "content-type": "application/octet-stream" },
    body: media.body,
  });
  if (!uploaded.ok) throw new Error(`Facebook-Medienupload fehlgeschlagen (HTTP ${uploaded.status}).`);
  await graph(job, env, edge, { video_id: videoId, upload_phase: "finish", video_state: "PUBLISHED", description: details.description, title: details.title });
  await setState(env, job, "published", { platform_video_id: videoId, publication_url: publicUrl("facebook", videoId), attempt_count: job.attempt_count + 1, last_error: null });
  await event(env, job.job_id, "info", "Facebook-Reel veröffentlicht.");
  await removeTemporaryPagesDeployment(job, env);
};

const processJob = async (job: Job, env: Env): Promise<void> => {
  try {
    if (job.platform === "instagram") await publishInstagram(job, env);
    else await publishFacebook(job, env);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unbekannter Cloud-Veröffentlichungsfehler.";
    const retryable = job.attempt_count < 4;
    await setState(env, job, retryable ? "scheduled" : "failed", { attempt_count: job.attempt_count + 1, last_error: message });
    await event(env, job.job_id, "error", retryable ? `Wird erneut versucht: ${message}` : message);
  }
};

const processDue = async (env: Env): Promise<void> => {
  const rows = await env.DB.prepare(`SELECT * FROM meta_publication_jobs
    WHERE status IN ('scheduled', 'waiting_for_meta') AND publish_at <= ?
    ORDER BY publish_at ASC LIMIT 10`).bind(now()).all<Job>();
  for (const job of rows.results ?? []) await processJob(job, env);
};

const authorized = (request: Request, env: Env): boolean => request.headers.get("authorization") === `Bearer ${env.META_QUEUE_TOKEN}`;

const enqueue = async (request: Request, env: Env): Promise<Response> => {
  // Do not accept media unless the Worker can delete the temporary Pages
  // deployment afterwards. This is an explicit cost/storage guardrail, not a
  // best-effort cleanup that could silently accumulate videos.
  if (!env.CLOUDFLARE_API_TOKEN || !env.CLOUDFLARE_ACCOUNT_ID) {
    return json({ error: "Cloudflare-Cleanup ist noch nicht konfiguriert; der Scheduler nimmt aus Kostenschutzgründen keine MP4 an." }, 503);
  }
  const payload = await request.json().catch(() => null);
  if (!validPayload(payload)) return json({ error: "Ungültiger Queue-Auftrag." }, 400);
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

const saveAnalyticsPlatform = async (
  env: Env,
  platform: SocialPlatform,
  accountName: string | null,
  videos: SocialVideo[],
  collectedAt: string,
): Promise<void> => {
  await env.DB.prepare(`INSERT INTO social_analytics_platforms (platform, status, account_name, reason, updated_at)
    VALUES (?, 'available', ?, NULL, ?)
    ON CONFLICT(platform) DO UPDATE SET status = 'available', account_name = excluded.account_name,
      reason = NULL, updated_at = excluded.updated_at`).bind(platform, accountName, collectedAt).run();
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
    const metricsJson = JSON.stringify(item.metrics);
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
    .bind(platform, status, reason.replace(/[^a-zA-Z0-9 äöüÄÖÜß.,:;()_-]/g, "").slice(0, 240), now()).run();
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
  const query = new URLSearchParams({ ...parameters, access_token: await tokenFor(platform, env) });
  const response = await fetch(`${graphUrl(platform, env, path)}?${query.toString()}`);
  if (!response.ok) throw new Error(`${platform} Analytics HTTP ${response.status}`);
  return response.json() as Promise<Record<string, unknown>>;
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

const collectFacebookAnalytics = async (env: Env): Promise<{ accountName: string | null; videos: SocialVideo[] }> => {
  const pageId = accountFor("facebook", env);
  const account = await analyticsGraph("facebook", env, pageId, { fields: "name" });
  const media = await analyticsGraph("facebook", env, `${pageId}/videos`, {
    fields: "id,title,description,created_time,permalink_url,published,status,length,likes.limit(0).summary(true),comments.limit(0).summary(true)",
    limit: "100",
  });
  const videos: SocialVideo[] = [];
  for (const raw of Array.isArray(media.data) ? media.data : []) {
    const item = raw as Record<string, unknown>;
    const rawStatus = String((item.status as Record<string, unknown> | undefined)?.video_status ?? "").toLowerCase();
    if (item.published === false || ["processing", "error", "blocked", "copyright_blocked"].includes(rawStatus)) continue;
    let insights: Record<string, unknown> = {};
    try {
      insights = insightValues(await analyticsGraph("facebook", env, `${String(item.id)}/video_insights`, {
        metric: "total_video_views,total_video_view_total_time,total_video_avg_time_watched",
      }));
    } catch { /* Basic counters still provide a valid partial record. */ }
    const likes = (item.likes as Record<string, unknown> | undefined)?.summary as Record<string, unknown> | undefined;
    const comments = (item.comments as Record<string, unknown> | undefined)?.summary as Record<string, unknown> | undefined;
    const totalTime = nullableNumber(insights.total_video_view_total_time);
    const averageTime = nullableNumber(insights.total_video_avg_time_watched);
    const entry = normalizedSocialVideo({
      platformVideoId: item.id,
      title: item.title,
      description: item.description,
      publishedAt: item.created_time,
      url: item.permalink_url,
      status: "published",
      durationSeconds: item.length,
      metrics: {
        views: insights.total_video_views,
        likes: likes?.total_count,
        comments: comments?.total_count,
        watchTimeMinutes: totalTime === null ? null : totalTime / 60000,
        averageViewDurationSeconds: averageTime === null ? null : averageTime / 1000,
      },
    });
    if (entry) videos.push(entry);
  }
  return { accountName: String(account.name ?? "") || null, videos };
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
      await saveAnalyticsPlatform(env, platform, result.accountName, result.videos, collectedAt);
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
    if (!authorized(request, env)) return json({ error: "Nicht autorisiert." }, 401);
    if (request.method === "GET" && url.pathname === "/ready") {
      const missing = [
        ["META_ACCESS_TOKEN", env.META_ACCESS_TOKEN],
        ["META_INSTAGRAM_ACCOUNT_ID", env.META_INSTAGRAM_ACCOUNT_ID],
        ["META_FACEBOOK_PAGE_ACCESS_TOKEN", env.META_FACEBOOK_PAGE_ACCESS_TOKEN],
        ["META_FACEBOOK_PAGE_ID", env.META_FACEBOOK_PAGE_ID],
        ["CLOUDFLARE_API_TOKEN", env.CLOUDFLARE_API_TOKEN],
        ["CLOUDFLARE_ACCOUNT_ID", env.CLOUDFLARE_ACCOUNT_ID],
      ].filter(([, value]) => !value).map(([name]) => name);
      return json({ status: missing.length === 0 ? "ready" : "configuration_incomplete", missing });
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
    await Promise.all([processDue(env), refreshMetaAnalyticsIfDue(env)]);
  },
} satisfies ExportedHandler<Env>;
