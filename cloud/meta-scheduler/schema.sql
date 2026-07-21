CREATE TABLE IF NOT EXISTS meta_publication_jobs (
  job_id TEXT PRIMARY KEY,
  source_video_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('instagram', 'facebook')),
  publish_at TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('scheduled', 'processing', 'waiting_for_meta', 'published', 'failed')),
  metadata_json TEXT NOT NULL,
  media_url TEXT NOT NULL,
  media_project TEXT NOT NULL,
  media_branch TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  platform_video_id TEXT,
  publication_url TEXT,
  container_id TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  published_at TEXT
);

CREATE INDEX IF NOT EXISTS meta_publication_jobs_due_idx
  ON meta_publication_jobs(status, publish_at);

CREATE TABLE IF NOT EXISTS meta_publication_events (
  event_id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  level TEXT NOT NULL CHECK (level IN ('info', 'warning', 'error')),
  message TEXT NOT NULL,
  FOREIGN KEY(job_id) REFERENCES meta_publication_jobs(job_id)
);

CREATE INDEX IF NOT EXISTS meta_publication_events_job_idx
  ON meta_publication_events(job_id, timestamp);

CREATE TABLE IF NOT EXISTS social_analytics_platforms (
  platform TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  account_name TEXT,
  reason TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS social_analytics_videos (
  platform TEXT NOT NULL,
  platform_video_id TEXT NOT NULL,
  content_id TEXT,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  published_at TEXT,
  url TEXT,
  thumbnail_url TEXT,
  status TEXT NOT NULL,
  duration_seconds REAL,
  metrics_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, platform_video_id)
);

CREATE TABLE IF NOT EXISTS social_analytics_snapshots (
  platform TEXT NOT NULL,
  platform_video_id TEXT NOT NULL,
  captured_date TEXT NOT NULL,
  captured_at TEXT NOT NULL,
  metrics_json TEXT NOT NULL,
  PRIMARY KEY(platform, platform_video_id, captured_date)
);

CREATE INDEX IF NOT EXISTS social_analytics_snapshots_date_idx
  ON social_analytics_snapshots(captured_at);

CREATE TABLE IF NOT EXISTS social_analytics_state (
  state_key TEXT PRIMARY KEY,
  state_value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Separate, fail-closed lane for connection tests and private/draft uploads.
-- These rows are never consumed by the publication scheduler above.
CREATE TABLE IF NOT EXISTS upload_staging_runs (
  run_id TEXT PRIMARY KEY,
  content_id TEXT NOT NULL,
  asset_sha256 TEXT NOT NULL,
  metadata_sha256 TEXT NOT NULL,
  metadata_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('planned', 'running', 'partial', 'completed', 'failed', 'expired', 'reconcile_required', 'safety_violation')),
  quality_status TEXT NOT NULL CHECK (quality_status = 'passed'),
  publication_authorized INTEGER NOT NULL DEFAULT 0 CHECK (publication_authorized = 0),
  execution_requested INTEGER NOT NULL DEFAULT 0 CHECK (execution_requested IN (0, 1)),
  media_url TEXT,
  media_project TEXT,
  media_branch TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  media_cleaned_at TEXT
);

CREATE TABLE IF NOT EXISTS upload_staging_targets (
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
  remote_object_id TEXT,
  provider_status TEXT,
  expires_at TEXT,
  receipt_sha256 TEXT,
  remote_create_started_at TEXT,
  lease_owner TEXT,
  lease_expires_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (run_id, platform),
  FOREIGN KEY (run_id) REFERENCES upload_staging_runs(run_id)
);

CREATE INDEX IF NOT EXISTS upload_staging_targets_status_idx
  ON upload_staging_targets(platform, transport_state, updated_at);

CREATE INDEX IF NOT EXISTS upload_staging_targets_lease_idx
  ON upload_staging_targets(lease_expires_at, transport_state);

CREATE TABLE IF NOT EXISTS upload_staging_events (
  event_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  platform TEXT,
  timestamp TEXT NOT NULL,
  level TEXT NOT NULL CHECK (level IN ('info', 'warning', 'error')),
  message TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES upload_staging_runs(run_id)
);

CREATE INDEX IF NOT EXISTS upload_staging_events_run_idx
  ON upload_staging_events(run_id, timestamp);
