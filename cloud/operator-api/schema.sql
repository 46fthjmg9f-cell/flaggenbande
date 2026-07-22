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
