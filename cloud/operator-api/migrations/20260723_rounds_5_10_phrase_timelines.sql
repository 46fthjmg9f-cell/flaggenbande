PRAGMA foreign_keys = ON;

-- Lossless, rerunnable expansion of the legacy five/seven-round tables.
-- The legacy tables are deliberately retained as a rollback copy because
-- SQLite cannot alter an existing CHECK constraint in place.
CREATE TABLE IF NOT EXISTS operator_script_drafts_v2 (
  draft_id TEXT PRIMARY KEY,
  client_request_id TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  script_sha256 TEXT NOT NULL,
  round_count INTEGER NOT NULL CHECK (round_count BETWEEN 5 AND 10),
  suggested_duration_seconds REAL NOT NULL
    CHECK (suggested_duration_seconds >= 61 AND suggested_duration_seconds <= 70),
  generator_version TEXT NOT NULL,
  style_example_count INTEGER NOT NULL DEFAULT 0 CHECK (style_example_count >= 0),
  recommendation_id TEXT,
  learned_signals_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS operator_script_drafts_v2_created_idx
  ON operator_script_drafts_v2(created_at);

INSERT OR IGNORE INTO operator_script_drafts_v2
  (draft_id, client_request_id, script, script_sha256, round_count,
   suggested_duration_seconds, generator_version, style_example_count,
   recommendation_id, learned_signals_json, created_at)
SELECT
  draft_id, client_request_id, script, script_sha256, round_count,
  suggested_duration_seconds, generator_version, style_example_count,
  recommendation_id, learned_signals_json, created_at
FROM operator_script_drafts;

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

INSERT OR IGNORE INTO operator_script_origins_v2
  (run_id, draft_id, origin, reveal_count, submitted_script_sha256,
   draft_script_sha256, created_at, updated_at)
SELECT
  run_id, draft_id, origin, reveal_count, submitted_script_sha256,
  draft_script_sha256, created_at, updated_at
FROM operator_script_origins;

CREATE TABLE IF NOT EXISTS operator_script_style_examples_v2 (
  example_id TEXT PRIMARY KEY,
  script_sha256 TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('seeded', 'manual', 'auto_edited')),
  reveal_count INTEGER NOT NULL CHECK (reveal_count BETWEEN 5 AND 10),
  target_duration_seconds REAL NOT NULL
    CHECK (target_duration_seconds >= 61 AND target_duration_seconds <= 70),
  trust_level TEXT NOT NULL CHECK (trust_level IN ('candidate', 'high_confidence')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS operator_script_style_examples_v2_retrieval_idx
  ON operator_script_style_examples_v2(reveal_count, trust_level, updated_at);

INSERT OR IGNORE INTO operator_script_style_examples_v2
  (example_id, script_sha256, script, source, reveal_count,
   target_duration_seconds, trust_level, created_at, updated_at)
SELECT
  example_id, script_sha256, script, source, reveal_count,
  target_duration_seconds, trust_level, created_at, updated_at
FROM operator_script_style_examples;

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
