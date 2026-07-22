import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  clearOperatorToken,
  listOperatorRuns,
  operatorApiConfigured,
  readOperatorToken,
  saveOperatorToken,
  startOperatorRun,
  type OperatorRun,
  type OperatorRunStatus,
} from './operatorApi'

const statusLabels: Record<OperatorRunStatus, string> = {
  queued: 'Warteschlange',
  claimed: 'Wird gestartet',
  running: 'Produktion läuft',
  waiting: 'Wartet auf Stimme',
  completed: 'Fertig',
  failed: 'Fehler',
}

const markerPattern = /^\s*\(auflösung\)\s*$/gimu

function markerCount(script: string): number {
  return [...script.matchAll(markerPattern)].length
}

function formatTime(value: string): string {
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? '—' : new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' }).format(date)
}

function RunRow({ run }: { run: OperatorRun }) {
  return <article className={`operator-run ${run.status}`}>
    <div className="operator-run-top">
      <strong>{statusLabels[run.status]}</strong>
      <span>{Math.round(run.progress)} %</span>
    </div>
    <div className="operator-progress" aria-label={`${Math.round(run.progress)} Prozent`}>
      <span style={{ width: `${run.progress}%` }} />
    </div>
    <div className="operator-run-detail">
      <span>{run.currentStep ?? run.message ?? 'Eingereiht'}</span>
      <time dateTime={run.updatedAt}>{formatTime(run.updatedAt)}</time>
    </div>
    {run.error && <p className="operator-error">{run.error}</p>}
  </article>
}

export default function VideoProductionControl() {
  const [unlocked, setUnlocked] = useState(() => Boolean(readOperatorToken()))
  const [token, setToken] = useState('')
  const [script, setScript] = useState('')
  const [targetDurationSeconds, setTargetDurationSeconds] = useState(65)
  const [runs, setRuns] = useState<OperatorRun[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const markers = useMemo(() => markerCount(script), [script])
  const scriptValid = script.trim().length >= 80 && markers === 5

  const refresh = useCallback(async (silent = false) => {
    if (!readOperatorToken()) return
    if (!silent) setBusy(true)
    try {
      setRuns(await listOperatorRuns())
      setError(null)
      setUnlocked(true)
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : String(reason)
      setError(message)
      if (!readOperatorToken()) setUnlocked(false)
    } finally {
      if (!silent) setBusy(false)
    }
  }, [])

  useEffect(() => {
    if (!unlocked) return
    void refresh(true)
    const timer = window.setInterval(() => void refresh(true), 4_000)
    return () => window.clearInterval(timer)
  }, [refresh, unlocked])

  const unlock = async () => {
    setBusy(true)
    setError(null)
    try {
      saveOperatorToken(token)
      const nextRuns = await listOperatorRuns()
      setRuns(nextRuns)
      setToken('')
      setUnlocked(true)
    } catch (reason) {
      clearOperatorToken()
      setUnlocked(false)
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusy(false)
    }
  }

  const lock = () => {
    clearOperatorToken()
    setUnlocked(false)
    setRuns([])
    setError(null)
  }

  const start = async () => {
    if (!scriptValid) return
    setBusy(true)
    setError(null)
    try {
      const run = await startOperatorRun({ script: script.trim(), targetDurationSeconds })
      setRuns(previous => [run, ...previous.filter(entry => entry.runId !== run.runId)])
      setScript('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusy(false)
    }
  }

  if (!operatorApiConfigured) {
    return <section className="operator-card"><div className="compact-heading"><h2>Neue Produktion</h2><span className="status-badge failed">Offline</span></div></section>
  }

  if (!unlocked) {
    return <section className="operator-card">
      <div className="compact-heading"><h2>Neue Produktion</h2><span className="status-badge planned">Gesperrt</span></div>
      <div className="operator-unlock">
        <input
          aria-label="Steuerungsschlüssel"
          autoComplete="current-password"
          onChange={event => setToken(event.target.value)}
          onKeyDown={event => { if (event.key === 'Enter') void unlock() }}
          placeholder="Steuerungsschlüssel"
          type="password"
          value={token}
        />
        <button type="button" onClick={() => void unlock()} disabled={busy || !token.trim()}>Öffnen</button>
      </div>
      {error && <p className="operator-error">{error}</p>}
    </section>
  }

  return <section className="operator-layout">
    <article className="operator-card">
      <div className="compact-heading"><h2>Neue Produktion</h2><button className="text-button" type="button" onClick={lock}>Sperren</button></div>
      <textarea
        aria-label="Videoskript"
        onChange={event => setScript(event.target.value)}
        placeholder="Skript einfügen …"
        rows={12}
        value={script}
      />
      <div className="operator-controls">
        <label>Länge
          <select value={targetDurationSeconds} onChange={event => setTargetDurationSeconds(Number(event.target.value))}>
            {[61, 62, 63, 64, 65, 66, 67, 68, 69, 70].map(seconds => <option value={seconds} key={seconds}>{seconds} s</option>)}
          </select>
        </label>
        <span className={markers === 5 ? 'marker-count valid' : 'marker-count'}>{markers}/5 Auflösungen</span>
        <button className="primary-action" type="button" onClick={() => void start()} disabled={busy || !scriptValid}>{busy ? 'Bitte warten …' : 'Video starten'}</button>
      </div>
      {error && <p className="operator-error">{error}</p>}
    </article>

    <aside className="operator-card operator-runs">
      <div className="compact-heading"><h2>Läufe</h2><button className="text-button" type="button" onClick={() => void refresh()} disabled={busy}>↻</button></div>
      <div className="operator-run-list">
        {runs.length > 0 ? runs.slice(0, 8).map(run => <RunRow key={run.runId} run={run} />) : <p className="compact-empty">Keine Läufe</p>}
      </div>
    </aside>
  </section>
}
