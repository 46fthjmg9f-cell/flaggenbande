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
