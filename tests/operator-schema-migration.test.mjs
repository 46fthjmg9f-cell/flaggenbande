import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { DatabaseSync } from 'node:sqlite'
import test from 'node:test'
import {
  buildDeployPlan,
  validateMigrationSql,
} from '../scripts/deploy-operator-worker.mjs'

const migrationUrl = new URL(
  '../cloud/operator-api/migrations/20260723_rounds_5_10_phrase_timelines.sql',
  import.meta.url,
)

const legacySchema = `
PRAGMA foreign_keys = ON;
CREATE TABLE operator_production_runs (run_id TEXT PRIMARY KEY);
CREATE TABLE operator_script_drafts (
  draft_id TEXT PRIMARY KEY,
  client_request_id TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  script_sha256 TEXT NOT NULL,
  round_count INTEGER NOT NULL CHECK (round_count IN (5, 7)),
  suggested_duration_seconds REAL NOT NULL,
  generator_version TEXT NOT NULL,
  style_example_count INTEGER NOT NULL DEFAULT 0,
  recommendation_id TEXT,
  learned_signals_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);
CREATE TABLE operator_script_origins (
  run_id TEXT PRIMARY KEY,
  draft_id TEXT,
  origin TEXT NOT NULL,
  reveal_count INTEGER NOT NULL CHECK (reveal_count IN (5, 7)),
  submitted_script_sha256 TEXT NOT NULL,
  draft_script_sha256 TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES operator_production_runs(run_id),
  FOREIGN KEY (draft_id) REFERENCES operator_script_drafts(draft_id)
);
CREATE TABLE operator_script_style_examples (
  example_id TEXT PRIMARY KEY,
  script_sha256 TEXT NOT NULL UNIQUE,
  script TEXT NOT NULL,
  source TEXT NOT NULL,
  reveal_count INTEGER NOT NULL CHECK (reveal_count IN (5, 7)),
  target_duration_seconds REAL NOT NULL,
  trust_level TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
`

test('round-count migration is lossless and safe to execute repeatedly', async () => {
  const database = new DatabaseSync(':memory:')
  database.exec(legacySchema)
  database.prepare('INSERT INTO operator_production_runs (run_id) VALUES (?)').run('video-legacy')
  database.prepare(`INSERT INTO operator_script_drafts
    (draft_id, client_request_id, script, script_sha256, round_count,
     suggested_duration_seconds, generator_version, style_example_count,
     recommendation_id, learned_signals_json, created_at)
    VALUES (?, ?, ?, ?, 5, 64, 'legacy', 1, NULL, '[]', ?)`)
    .run(
      'draft-legacy',
      'legacy-request',
      'legacy Flaggenbande script',
      'a'.repeat(64),
      '2026-07-23T00:00:00Z',
    )
  database.prepare(`INSERT INTO operator_script_origins
    (run_id, draft_id, origin, reveal_count, submitted_script_sha256,
     draft_script_sha256, created_at, updated_at)
    VALUES (?, ?, 'auto_unedited', 5, ?, ?, ?, ?)`)
    .run(
      'video-legacy',
      'draft-legacy',
      'a'.repeat(64),
      'a'.repeat(64),
      '2026-07-23T00:00:00Z',
      '2026-07-23T00:00:00Z',
    )
  database.prepare(`INSERT INTO operator_script_style_examples
    (example_id, script_sha256, script, source, reveal_count,
     target_duration_seconds, trust_level, created_at, updated_at)
    VALUES (?, ?, ?, 'seeded', 5, 64, 'high_confidence', ?, ?)`)
    .run(
      'legacy-example',
      'b'.repeat(64),
      'legacy Flaggenbande style',
      '2026-07-23T00:00:00Z',
      '2026-07-23T00:00:00Z',
    )

  const migration = await readFile(migrationUrl, 'utf8')
  database.exec(migration)
  database.exec(migration)

  assert.equal(database.prepare('SELECT COUNT(*) AS count FROM operator_script_drafts').get().count, 1)
  assert.equal(database.prepare('SELECT COUNT(*) AS count FROM operator_script_drafts_v2').get().count, 1)
  assert.equal(database.prepare('SELECT COUNT(*) AS count FROM operator_script_origins_v2').get().count, 1)
  assert.equal(database.prepare('SELECT COUNT(*) AS count FROM operator_script_style_examples_v2').get().count, 1)
  assert.equal(
    database.prepare('SELECT script FROM operator_script_drafts WHERE draft_id = ?')
      .get('draft-legacy').script,
    'legacy Flaggenbande script',
  )
  assert.equal(
    database.prepare('SELECT script FROM operator_script_drafts_v2 WHERE draft_id = ?')
      .get('draft-legacy').script,
    'legacy Flaggenbande script',
  )
  assert.equal(
    database.prepare('SELECT script FROM operator_script_style_examples WHERE example_id = ?')
      .get('legacy-example').script,
    'legacy Flaggenbande style',
  )
  assert.equal(
    database.prepare('SELECT script FROM operator_script_style_examples_v2 WHERE example_id = ?')
      .get('legacy-example').script,
    'legacy Flaggenbande style',
  )

  database.prepare(`INSERT INTO operator_script_drafts_v2
    (draft_id, client_request_id, script, script_sha256, round_count,
     suggested_duration_seconds, generator_version, style_example_count,
     recommendation_id, learned_signals_json, created_at)
    VALUES (?, ?, ?, ?, 10, 70, 'expanded', 0, NULL, '[]', ?)`)
    .run('draft-expanded', 'expanded-request', 'expanded script', 'c'.repeat(64), '2026-07-23T01:00:00Z')
  assert.equal(
    database.prepare('SELECT round_count FROM operator_script_drafts_v2 WHERE draft_id = ?')
      .get('draft-expanded').round_count,
    10,
  )
  assert.throws(() => {
    database.prepare(`INSERT INTO operator_script_drafts_v2
      (draft_id, client_request_id, script, script_sha256, round_count,
       suggested_duration_seconds, generator_version, style_example_count,
       recommendation_id, learned_signals_json, created_at)
      VALUES ('bad', 'bad-request', 'bad', ?, 11, 70, 'bad', 0, NULL, '[]', ?)`)
      .run('d'.repeat(64), '2026-07-23T01:00:00Z')
  })
  assert.deepEqual(database.prepare('PRAGMA foreign_key_check').all(), [])
})

test('operator deploy applies the named migration before deploying the Worker', async () => {
  const migration = await readFile(migrationUrl, 'utf8')
  assert.doesNotThrow(() => validateMigrationSql(migration))

  const deployPlan = buildDeployPlan()
  assert.deepEqual(
    deployPlan.map(({ label }) => label),
    ['D1-Migration', 'Worker-Deploy'],
  )
  assert.deepEqual(deployPlan[0].arguments.slice(2, 6), [
    'd1',
    'execute',
    'flaggenbande-operator',
    '--remote',
  ])
  assert.ok(
    deployPlan[0].arguments.includes(
      'cloud/operator-api/migrations/20260723_rounds_5_10_phrase_timelines.sql',
    ),
  )

  const dryRunPlan = buildDeployPlan({ dryRun: true })
  assert.deepEqual(
    dryRunPlan.map(({ label }) => label),
    ['Worker-Dry-Run'],
  )
  assert.ok(dryRunPlan[0].arguments.includes('--dry-run'))
  assert.equal(dryRunPlan.some(({ label }) => label === 'D1-Migration'), false)
})

test('operator deploy rejects destructive migrations', () => {
  assert.throws(
    () =>
      validateMigrationSql(`
        CREATE TABLE IF NOT EXISTS operator_script_drafts_v2 (draft_id TEXT);
        DELETE FROM operator_script_drafts_v2;
      `),
    /nicht erlaubt/,
  )
})
