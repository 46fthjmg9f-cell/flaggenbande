PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS operator_production_runs (
  run_id TEXT PRIMARY KEY,
  input_sha256 TEXT NOT NULL UNIQUE,
  client_request_id TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  target_duration_seconds REAL NOT NULL CHECK (target_duration_seconds >= 61 AND target_duration_seconds <= 70),
  status TEXT NOT NULL CHECK (status IN ('queued', 'claimed', 'running', 'waiting', 'completed', 'failed')),
  progress REAL NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
  current_step TEXT,
  message TEXT,
  error_code TEXT,
  provider_run_id TEXT,
  lease_owner TEXT,
  lease_token_sha256 TEXT,
  lease_expires_at TEXT,
  next_attempt_at TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS operator_production_runs_claim_idx
  ON operator_production_runs(status, next_attempt_at, lease_expires_at, created_at);

CREATE TABLE IF NOT EXISTS operator_production_events (
  event_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'claimed', 'running', 'waiting', 'completed', 'failed')),
  progress REAL NOT NULL CHECK (progress >= 0 AND progress <= 100),
  current_step TEXT,
  message TEXT,
  error_code TEXT,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id)
);

CREATE INDEX IF NOT EXISTS operator_production_events_run_idx
  ON operator_production_events(run_id, timestamp);

CREATE TABLE IF NOT EXISTS operator_calendar_entries (
  entry_id TEXT PRIMARY KEY,
  content_id TEXT NOT NULL,
  title TEXT NOT NULL,
  scheduled_at TEXT NOT NULL,
  platforms_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS operator_calendar_entries_schedule_idx
  ON operator_calendar_entries(scheduled_at);

-- Approval data intentionally lives outside operator_production_runs. This keeps
-- the established production status CHECK compatible with already deployed D1
-- databases while adding the two mandatory human review gates.
CREATE TABLE IF NOT EXISTS operator_release_label_sequences (
  day_key TEXT PRIMARY KEY,
  next_sequence INTEGER NOT NULL CHECK (next_sequence >= 1),
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS operator_production_reviews (
  run_id TEXT PRIMARY KEY,
  release_label TEXT NOT NULL UNIQUE,
  script_sha256 TEXT NOT NULL,
  script_revision INTEGER NOT NULL DEFAULT 1 CHECK (script_revision >= 1),
  script_approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (script_approval_status IN ('pending', 'approved')),
  script_approval_idempotency_key TEXT UNIQUE,
  script_approved_at TEXT,
  preview_object_key TEXT,
  preview_sha256 TEXT,
  preview_size_bytes INTEGER CHECK (preview_size_bytes IS NULL OR preview_size_bytes > 0),
  preview_content_type TEXT,
  preview_uploaded_at TEXT,
  quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0, 1)),
  monetization_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (monetization_gate_passed IN (0, 1)),
  video_revision INTEGER NOT NULL DEFAULT 0 CHECK (video_revision >= 0),
  video_approval_status TEXT NOT NULL DEFAULT 'not_ready'
    CHECK (video_approval_status IN ('not_ready', 'pending', 'approved')),
  video_approval_idempotency_key TEXT UNIQUE,
  video_approved_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id)
);

CREATE INDEX IF NOT EXISTS operator_production_reviews_release_label_idx
  ON operator_production_reviews(release_label);

CREATE TABLE IF NOT EXISTS operator_review_events (
  review_event_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  event_type TEXT NOT NULL
    CHECK (event_type IN ('script_created', 'script_approved', 'preview_uploaded', 'video_approved')),
  revision INTEGER NOT NULL CHECK (revision >= 1),
  artifact_sha256 TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id)
);

CREATE INDEX IF NOT EXISTS operator_review_events_run_idx
  ON operator_review_events(run_id, timestamp);

-- This is an internal release queue only. Platform adapters consume it outside
-- this Worker; the Worker itself deliberately has no publishing capability.
CREATE TABLE IF NOT EXISTS operator_release_requests (
  request_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL UNIQUE,
  preview_sha256 TEXT NOT NULL,
  video_revision INTEGER NOT NULL CHECK (video_revision >= 1),
  idempotency_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'claimed', 'completed', 'failed')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id)
);

CREATE INDEX IF NOT EXISTS operator_release_requests_status_idx
  ON operator_release_requests(status, created_at);

-- Execution data is kept in a separate table so the release queue remains
-- backwards-compatible with already deployed D1 databases.
CREATE TABLE IF NOT EXISTS operator_release_executions (
  request_id TEXT PRIMARY KEY,
  platforms_json TEXT NOT NULL,
  platform_results_json TEXT NOT NULL,
  runner_id TEXT,
  lease_token_sha256 TEXT,
  lease_expires_at TEXT,
  next_attempt_at TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (request_id) REFERENCES operator_release_requests(request_id)
);

CREATE INDEX IF NOT EXISTS operator_release_executions_claim_idx
  ON operator_release_executions(next_attempt_at, lease_expires_at);

CREATE TABLE IF NOT EXISTS operator_release_events (
  release_event_id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'claimed', 'completed', 'failed')),
  platform_results_json TEXT NOT NULL,
  message TEXT,
  error_code TEXT,
  FOREIGN KEY (request_id) REFERENCES operator_release_requests(request_id)
);

CREATE INDEX IF NOT EXISTS operator_release_events_request_idx
  ON operator_release_events(request_id, timestamp);

-- Calendar approval metadata is separated from the original calendar table to
-- avoid destructive ALTER TABLE migrations.
CREATE TABLE IF NOT EXISTS operator_calendar_reviews (
  entry_id TEXT PRIMARY KEY,
  run_id TEXT,
  release_label TEXT,
  video_approved INTEGER NOT NULL DEFAULT 0 CHECK (video_approved IN (0, 1)),
  final_release_approved INTEGER NOT NULL DEFAULT 0 CHECK (final_release_approved IN (0, 1)),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES operator_calendar_entries(entry_id)
);
