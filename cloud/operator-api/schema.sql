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

-- Versioned tables are intentional. The original production tables only allow
-- five or seven rounds in their immutable SQLite CHECK constraints. Keeping
-- them untouched makes the online migration lossless and repeatable while the
-- API writes exclusively to the expanded v2 tables.
CREATE TABLE IF NOT EXISTS operator_script_drafts_v2 (
  draft_id TEXT PRIMARY KEY,
  client_request_id TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  script_sha256 TEXT NOT NULL,
  round_count INTEGER NOT NULL CHECK (round_count BETWEEN 5 AND 10),
  suggested_duration_seconds REAL NOT NULL CHECK (suggested_duration_seconds >= 61 AND suggested_duration_seconds <= 70),
  generator_version TEXT NOT NULL,
  style_example_count INTEGER NOT NULL DEFAULT 0 CHECK (style_example_count >= 0),
  recommendation_id TEXT,
  learned_signals_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS operator_script_drafts_v2_created_idx
  ON operator_script_drafts_v2(created_at);

-- A content-addressed script structure can be attached to generated drafts as
-- well as manually approved scripts. Timings and solutions remain nullable
-- until narration alignment and flag selection have completed.
CREATE TABLE IF NOT EXISTS operator_script_structures (
  script_sha256 TEXT PRIMARY KEY,
  source_draft_id TEXT,
  schema_version TEXT NOT NULL CHECK (schema_version = '1.0.0'),
  round_count INTEGER NOT NULL CHECK (round_count BETWEEN 5 AND 10),
  structure_json TEXT NOT NULL CHECK (json_valid(structure_json)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (source_draft_id) REFERENCES operator_script_drafts_v2(draft_id)
);

CREATE INDEX IF NOT EXISTS operator_script_structures_draft_idx
  ON operator_script_structures(source_draft_id);

CREATE TABLE IF NOT EXISTS operator_script_phrases (
  script_sha256 TEXT NOT NULL,
  phrase_id TEXT NOT NULL,
  formulation_key TEXT NOT NULL,
  phrase_type TEXT NOT NULL
    CHECK (phrase_type IN ('hook', 'question', 'reveal', 'reaction', 'transition', 'cta')),
  position_index INTEGER NOT NULL CHECK (position_index >= 0),
  round_number INTEGER CHECK (round_number IS NULL OR round_number BETWEEN 1 AND 10),
  text TEXT NOT NULL,
  start_seconds REAL CHECK (start_seconds IS NULL OR start_seconds >= 0),
  end_seconds REAL CHECK (
    end_seconds IS NULL OR (
      end_seconds >= 0 AND
      (start_seconds IS NULL OR end_seconds >= start_seconds)
    )
  ),
  solution_country TEXT,
  solution_country_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (script_sha256, phrase_id),
  FOREIGN KEY (script_sha256) REFERENCES operator_script_structures(script_sha256)
);

CREATE UNIQUE INDEX IF NOT EXISTS operator_script_phrases_position_idx
  ON operator_script_phrases(script_sha256, position_index);

-- Cross-video research groups identical formulations through formulation_key.
CREATE INDEX IF NOT EXISTS operator_script_phrases_formulation_idx
  ON operator_script_phrases(formulation_key, phrase_type);

CREATE TABLE IF NOT EXISTS operator_script_rounds (
  script_sha256 TEXT NOT NULL,
  round_number INTEGER NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  question_phrase_id TEXT,
  reveal_phrase_id TEXT NOT NULL,
  solution_country TEXT,
  solution_country_code TEXT,
  flag_shown_at_seconds REAL
    CHECK (flag_shown_at_seconds IS NULL OR flag_shown_at_seconds >= 0),
  reveal_at_seconds REAL CHECK (
    reveal_at_seconds IS NULL OR (
      reveal_at_seconds >= 0 AND
      (flag_shown_at_seconds IS NULL OR reveal_at_seconds >= flag_shown_at_seconds)
    )
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (script_sha256, round_number),
  FOREIGN KEY (script_sha256) REFERENCES operator_script_structures(script_sha256)
);

CREATE TABLE IF NOT EXISTS operator_run_script_manifests (
  run_id TEXT PRIMARY KEY,
  script_sha256 TEXT NOT NULL,
  schema_version TEXT NOT NULL CHECK (schema_version = '1.0.0'),
  round_count INTEGER NOT NULL CHECK (round_count BETWEEN 5 AND 10),
  timing_source TEXT NOT NULL DEFAULT 'script_only'
    CHECK (timing_source IN ('script_only', 'word_timestamps')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id),
  FOREIGN KEY (script_sha256) REFERENCES operator_script_structures(script_sha256)
);

CREATE INDEX IF NOT EXISTS operator_run_script_manifests_script_idx
  ON operator_run_script_manifests(script_sha256);

CREATE TABLE IF NOT EXISTS operator_run_script_phrases (
  run_id TEXT NOT NULL,
  script_sha256 TEXT NOT NULL,
  phrase_id TEXT NOT NULL,
  start_seconds REAL CHECK (start_seconds IS NULL OR start_seconds >= 0),
  end_seconds REAL CHECK (
    end_seconds IS NULL OR (
      end_seconds >= 0 AND
      (start_seconds IS NULL OR end_seconds >= start_seconds)
    )
  ),
  solution_country TEXT,
  solution_country_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (run_id, phrase_id),
  FOREIGN KEY (run_id) REFERENCES operator_run_script_manifests(run_id),
  FOREIGN KEY (script_sha256, phrase_id)
    REFERENCES operator_script_phrases(script_sha256, phrase_id)
);

CREATE INDEX IF NOT EXISTS operator_run_script_phrases_script_idx
  ON operator_run_script_phrases(script_sha256, phrase_id);

CREATE TABLE IF NOT EXISTS operator_run_script_rounds (
  run_id TEXT NOT NULL,
  script_sha256 TEXT NOT NULL,
  round_number INTEGER NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  solution_country TEXT,
  solution_country_code TEXT,
  flag_shown_at_seconds REAL
    CHECK (flag_shown_at_seconds IS NULL OR flag_shown_at_seconds >= 0),
  reveal_at_seconds REAL CHECK (
    reveal_at_seconds IS NULL OR (
      reveal_at_seconds >= 0 AND
      (flag_shown_at_seconds IS NULL OR reveal_at_seconds >= flag_shown_at_seconds)
    )
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (run_id, round_number),
  FOREIGN KEY (run_id) REFERENCES operator_run_script_manifests(run_id),
  FOREIGN KEY (script_sha256, round_number)
    REFERENCES operator_script_rounds(script_sha256, round_number)
);

CREATE INDEX IF NOT EXISTS operator_run_script_rounds_script_idx
  ON operator_run_script_rounds(script_sha256, round_number);

CREATE TABLE IF NOT EXISTS operator_script_origins_v2 (
  run_id TEXT PRIMARY KEY,
  draft_id TEXT,
  origin TEXT NOT NULL CHECK (origin IN ('manual', 'auto_unedited', 'auto_edited')),
  reveal_count INTEGER NOT NULL CHECK (reveal_count BETWEEN 5 AND 10),
  submitted_script_sha256 TEXT NOT NULL,
  draft_script_sha256 TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id),
  FOREIGN KEY (draft_id) REFERENCES operator_script_drafts_v2(draft_id)
);

CREATE INDEX IF NOT EXISTS operator_script_origins_v2_origin_idx
  ON operator_script_origins_v2(origin, updated_at);

CREATE TABLE IF NOT EXISTS operator_script_style_examples_v2 (
  example_id TEXT PRIMARY KEY,
  script_sha256 TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('seeded', 'manual', 'auto_edited')),
  reveal_count INTEGER NOT NULL CHECK (reveal_count BETWEEN 5 AND 10),
  target_duration_seconds REAL NOT NULL CHECK (target_duration_seconds >= 61 AND target_duration_seconds <= 70),
  trust_level TEXT NOT NULL CHECK (trust_level IN ('candidate', 'high_confidence')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS operator_script_style_examples_v2_retrieval_idx
  ON operator_script_style_examples_v2(reveal_count, trust_level, updated_at);

DELETE FROM operator_script_drafts_v2
WHERE instr(lower(script), 'flaggenbande') > 0
  AND NOT EXISTS (
    SELECT 1
    FROM operator_script_origins_v2
    WHERE operator_script_origins_v2.draft_id = operator_script_drafts_v2.draft_id
  );

DELETE FROM operator_script_style_examples_v2
WHERE instr(lower(script), 'flaggenbande') > 0;

INSERT OR IGNORE INTO operator_script_style_examples_v2
  (example_id, script_sha256, script, source, reveal_count, target_duration_seconds,
   trust_level, created_at, updated_at)
VALUES (
  'style-seed-german-v5-organic',
  '34725210bd9f3933be511dbcdbbbf2486a32cc34abd1fc20bc012df49736416f',
  'was läuft was läuft, schnelles flaggenquiz, fünf flaggen, eine wird richtig kernig. fängt easy an: welches land ist das?
(auflösung)
okok, sauber. die nächste wird schon tougher, also nicht zu früh feiern. wie schaut es hier aus?
(auflösung)
crazy, der bre hat ahnung. jetzt wird es knifflig: welches land gehört zu dieser flagge?
(auflösung)
drei von drei wäre stark. ab hier trennt sich glück von echter ahnung. bereit fürs halbfinale, welches land ist das?
(auflösung)
junge, vielleicht ist hier wirklich der flaggenboss am start. letzte runde, mann oder maus: welche flagge siehst du?
(auflösung)
anscheinend der allerechte flaggenchef. schreib ehrlich, wie viele du sauber erkannt hast.',
  'seeded',
  5,
  64,
  'high_confidence',
  '2026-07-23T00:00:00.000Z',
  '2026-07-23T00:00:00.000Z'
);

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
