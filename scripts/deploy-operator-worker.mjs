import { spawn } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const projectDirectory = fileURLToPath(new URL('../', import.meta.url))
const wranglerConfig = 'cloud/operator-api/wrangler.toml'
const migrationFile =
  'cloud/operator-api/migrations/20260723_rounds_5_10_phrase_timelines.sql'
const databaseName = 'flaggenbande-operator'
const wranglerVersion = '4.112.0'

export const validateMigrationSql = (sql) => {
  const destructiveStatement = /^\s*(?:DELETE|DROP|TRUNCATE)\b/im.exec(sql)
  if (destructiveStatement) {
    throw new Error(
      `Unsichere D1-Migration: ${destructiveStatement[0].trim()} ist nicht erlaubt.`,
    )
  }

  if (!sql.includes('CREATE TABLE IF NOT EXISTS operator_script_drafts_v2')) {
    throw new Error('Die erwartete Round-Count-Migration wurde nicht erkannt.')
  }
}

export const buildDeployPlan = ({ dryRun = false } = {}) => {
  const workerArguments = [
    '--yes',
    `wrangler@${wranglerVersion}`,
    'deploy',
    ...(dryRun ? ['--dry-run'] : []),
    '--config',
    wranglerConfig,
  ]

  if (dryRun) {
    return [
      {
        label: 'Worker-Dry-Run',
        command: 'npx',
        arguments: workerArguments,
      },
    ]
  }

  return [
    {
      label: 'D1-Migration',
      command: 'npx',
      arguments: [
        '--yes',
        `wrangler@${wranglerVersion}`,
        'd1',
        'execute',
        databaseName,
        '--remote',
        '--file',
        migrationFile,
        '--config',
        wranglerConfig,
      ],
    },
    {
      label: 'Worker-Deploy',
      command: 'npx',
      arguments: workerArguments,
    },
  ]
}

const runCommand = ({ label, command, arguments: commandArguments }) =>
  new Promise((resolve, reject) => {
    process.stdout.write(`[operator-deploy] ${label} startet.\n`)
    const child = spawn(command, commandArguments, {
      cwd: projectDirectory,
      stdio: 'inherit',
    })

    child.once('error', reject)
    child.once('exit', (code, signal) => {
      if (code === 0) {
        process.stdout.write(`[operator-deploy] ${label} erfolgreich.\n`)
        resolve()
        return
      }

      reject(
        new Error(
          `${label} fehlgeschlagen (${signal ? `Signal ${signal}` : `Code ${code ?? 'unbekannt'}`}).`,
        ),
      )
    })
  })

export const deployOperatorWorker = async ({ dryRun = false } = {}) => {
  const migrationSql = await readFile(
    new URL(`../${migrationFile}`, import.meta.url),
    'utf8',
  )
  validateMigrationSql(migrationSql)

  if (dryRun) {
    process.stdout.write(
      `[operator-deploy] Dry-Run: ${migrationFile} wurde geprüft und wird nicht auf D1 angewendet.\n`,
    )
  }

  for (const command of buildDeployPlan({ dryRun })) {
    await runCommand(command)
  }
}

const isCliEntry = process.argv[1]
  ? fileURLToPath(import.meta.url) === fileURLToPath(new URL(`file://${process.argv[1]}`))
  : false

if (isCliEntry) {
  deployOperatorWorker({ dryRun: process.argv.includes('--dry-run') }).catch(
    (error) => {
      process.stderr.write(
        `[operator-deploy] ${error instanceof Error ? error.message : String(error)}\n`,
      )
      process.exitCode = 1
    },
  )
}
