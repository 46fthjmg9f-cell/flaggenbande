import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  approveOperatorScript,
  approveOperatorVideo,
  generateOperatorScriptDraft,
  getResearchRecommendations,
  listOperatorRuns,
  operatorApiConfigured,
  operatorPreviewUrl,
  startOperatorRun,
  type OperatorRun,
  type OperatorRunStatus,
  type ResearchRecommendationFeed,
  type ScriptDraft,
  type SupportedRoundCount,
} from './operatorApi'
import { displayReleaseLabel } from './videoDisplay'

const statusLabels: Record<OperatorRunStatus, string> = {
  awaiting_script_approval: 'Skript prüfen',
  queued: 'Warteschlange',
  claimed: 'Wird gestartet',
  running: 'Produktion läuft',
  waiting: 'Produktion wartet',
  completed: 'Video fertig',
  failed: 'Fehler',
  awaiting_video_approval: 'Video prüfen',
  release_queued: 'Veröffentlichung läuft',
  published: 'Veröffentlicht',
}

const markerPattern = /^\s*\(auflösung\)\s*$/gimu

function markerCount(script: string): number {
  return [...script.matchAll(markerPattern)].length
}

function spokenWordCount(script: string): number {
  return script.replace(markerPattern, '').match(/[\p{L}\p{N}]+/gu)?.length ?? 0
}

function brandMentionCount(script: string): number {
  return script.match(/\bflaggenbande\b/giu)?.length ?? 0
}

const targetDurationByRounds: Record<SupportedRoundCount, number> = {
  5: 64,
  7: 69,
}

function formatTime(value: string): string {
  const date = new Date(value)
  return Number.isNaN(date.valueOf())
    ? '—'
    : new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' }).format(date)
}

function runDisplayLabel(run: OperatorRun): string {
  return displayReleaseLabel({
    releaseLabel: run.releaseLabel,
    videoApproved: run.videoApproval.status === 'approved',
    finalReleaseApproved: run.release.status === 'published',
  }) ?? run.releaseLabel
}

function releaseStatus(run: OperatorRun): string | null {
  if (run.status === 'published' || run.release.status === 'published' || run.release.status === 'completed') {
    return 'Auf allen ausgewählten Plattformen veröffentlicht'
  }
  if (run.release.status === 'failed') return 'Veröffentlichung fehlgeschlagen'
  if (run.release.status === 'claimed' || run.release.status === 'processing') return 'Wird veröffentlicht'
  if (run.release.status === 'queued') return 'Zur Veröffentlichung eingeplant'
  if (run.videoApproval.status === 'approved') return 'Video freigegeben'
  return null
}

interface RunCardProps {
  run: OperatorRun
  busyAction: string | null
  onApproveScript: (run: OperatorRun) => Promise<void>
  onApproveVideo: (run: OperatorRun) => Promise<void>
  initiallyOpen: boolean
}

function RunCard({ run, busyAction, onApproveScript, onApproveVideo, initiallyOpen }: RunCardProps) {
  const previewUrl = operatorPreviewUrl(run)
  const approvingScript = busyAction === `script:${run.runId}`
  const approvingVideo = busyAction === `video:${run.runId}`
  const gatesPassed = run.preview.qualityPassed && run.preview.monetizationPassed
  const scriptPending = run.status === 'awaiting_script_approval' && run.script.status === 'pending'
  const videoPending = run.status === 'awaiting_video_approval' && run.videoApproval.status === 'pending'
  const release = releaseStatus(run)

  return <details className={`operator-run operator-review ${run.status}`} open={initiallyOpen || scriptPending || videoPending}>
    <summary>
      <span className="operator-run-label">{runDisplayLabel(run)}</span>
      <strong>{statusLabels[run.status]}</strong>
      <span>{Math.round(run.progress)} %</span>
    </summary>

    <div className="operator-progress" aria-label={`${Math.round(run.progress)} Prozent`}>
      <span style={{ width: `${run.progress}%` }} />
    </div>

    <div className="operator-run-detail">
      <span>{run.currentStep ?? run.message ?? statusLabels[run.status]}</span>
      <time dateTime={run.updatedAt}>{formatTime(run.updatedAt)}</time>
    </div>

    <section className="operator-review-stage">
      <div className="operator-stage-heading">
        <strong>1 · Skript</strong>
        <span className={`review-state ${run.script.status}`}>{run.script.status === 'approved' ? 'Freigegeben' : 'Offen'}</span>
      </div>
      <pre className="operator-script">{run.script.text}</pre>
      {scriptPending && <button
        className="primary-action"
        type="button"
        onClick={() => void onApproveScript(run)}
        disabled={Boolean(busyAction)}
      >
        {approvingScript ? 'Wird freigegeben …' : 'Skript freigeben'}
      </button>}
    </section>

    <section className="operator-review-stage">
      <div className="operator-stage-heading">
        <strong>2 · Video</strong>
        <span className={`review-state ${run.videoApproval.status}`}>
          {run.videoApproval.status === 'approved' ? 'Freigegeben' : run.preview.ready ? 'Offen' : 'Noch nicht fertig'}
        </span>
      </div>
      {previewUrl
        ? <video className="operator-preview" controls crossOrigin="use-credentials" playsInline preload="metadata" src={previewUrl} />
        : <div className="operator-preview-empty">Video wird nach der Skriptfreigabe erzeugt.</div>}
      {run.preview.ready && <div className="operator-gates" aria-label="Freigabeprüfungen">
        <span className={run.preview.qualityPassed ? 'passed' : 'failed'}>Qualität</span>
        <span className={run.preview.monetizationPassed ? 'passed' : 'failed'}>Monetarisierung</span>
      </div>}
      {videoPending && <button
        className="primary-action"
        type="button"
        onClick={() => void onApproveVideo(run)}
        disabled={Boolean(busyAction) || !gatesPassed || !run.preview.sha256}
      >
        {approvingVideo ? 'Wird freigegeben …' : 'Video freigeben & Veröffentlichung starten'}
      </button>}
    </section>

    {release && <div className={`operator-release-state ${run.release.status ?? 'approved'}`}>
      <strong>{release}</strong>
      {run.release.requestId && <div className="operator-release-platforms">
        {([
          ['youtube', 'YT'],
          ['instagram', 'IG'],
          ['facebook', 'FB'],
          ['tiktok', 'TT'],
        ] as const).map(([platform, label]) =>
          <span className={run.release.platforms[platform].status} key={platform}>
            {label} · {run.release.platforms[platform].status}
          </span>)}
      </div>}
      {run.release.error && <small>{run.release.error}</small>}
    </div>}
    {run.error && <p className="operator-error">{run.error}</p>}
  </details>
}

export default function VideoProductionControl() {
  const [script, setScript] = useState('')
  const [autoGenerate, setAutoGenerate] = useState(false)
  const [roundCount, setRoundCount] = useState<SupportedRoundCount>(5)
  const [targetDurationSeconds, setTargetDurationSeconds] = useState(targetDurationByRounds[5])
  const [draft, setDraft] = useState<ScriptDraft | null>(null)
  const [research, setResearch] = useState<ResearchRecommendationFeed | null>(null)
  const [researchError, setResearchError] = useState<string | null>(null)
  const [selectedRecommendationId, setSelectedRecommendationId] = useState<string | null>(null)
  const [runs, setRuns] = useState<OperatorRun[]>([])
  const [saving, setSaving] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [busyAction, setBusyAction] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const markers = useMemo(() => markerCount(script), [script])
  const words = useMemo(() => spokenWordCount(script), [script])
  const brandMentions = useMemo(() => brandMentionCount(script), [script])
  const minimumWords = roundCount === 5 ? 90 : 70
  const brandValid = brandMentions === 0
  const scriptValid = script.trim().length >= 80 &&
    markers === roundCount &&
    words >= minimumWords &&
    brandValid
  const activeRun = runs.some(run => !['published', 'completed', 'failed'].includes(run.status))

  const refresh = useCallback(async (silent = false) => {
    if (!operatorApiConfigured) return
    if (!silent) setSaving(true)
    try {
      setRuns(await listOperatorRuns())
      setError(null)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      if (!silent) setSaving(false)
    }
  }, [])

  useEffect(() => {
    void refresh(true)
    const timer = window.setInterval(() => void refresh(true), activeRun ? 4_000 : 15_000)
    const onFocus = () => void refresh(true)
    window.addEventListener('focus', onFocus)
    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', onFocus)
    }
  }, [activeRun, refresh])

  useEffect(() => {
    if (!operatorApiConfigured) return
    const loadResearch = () => {
      void getResearchRecommendations()
        .then(value => {
          setResearch(value)
          setResearchError(null)
        })
        .catch(reason => setResearchError(reason instanceof Error ? reason.message : String(reason)))
    }
    loadResearch()
    const timer = window.setInterval(loadResearch, 5 * 60_000)
    const onFocus = () => loadResearch()
    window.addEventListener('focus', onFocus)
    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', onFocus)
    }
  }, [])

  const updateRun = (run: OperatorRun) => {
    setRuns(previous => [run, ...previous.filter(entry => entry.runId !== run.runId)])
  }

  const saveScript = async () => {
    if (!scriptValid) return
    setSaving(true)
    setError(null)
    try {
      updateRun(await startOperatorRun({
        script: script.trim(),
        targetDurationSeconds,
        roundCount,
        ...(draft ? { draftId: draft.draftId } : {}),
      }))
      setScript('')
      setDraft(null)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setSaving(false)
    }
  }

  const generateDraft = async () => {
    setGenerating(true)
    setError(null)
    try {
      const generated = await generateOperatorScriptDraft({
        roundCount,
        targetDurationSeconds,
        recommendationId: selectedRecommendationId,
      })
      setDraft(generated)
      setScript(generated.script)
      setTargetDurationSeconds(generated.suggestedDurationSeconds)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setGenerating(false)
    }
  }

  const changeRoundCount = (value: SupportedRoundCount) => {
    setRoundCount(value)
    setTargetDurationSeconds(targetDurationByRounds[value])
    setDraft(null)
  }

  const selectRecommendation = (recommendationId: string | null) => {
    setSelectedRecommendationId(recommendationId)
    // Ein bereits erzeugter Draft gehört weiterhin zu seiner ursprünglichen
    // Research-Hypothese. Nach einem Wechsel wird er als manueller Text
    // behandelt, bis ein neuer Entwurf explizit erzeugt wurde.
    setDraft(null)
  }

  const approveScript = async (run: OperatorRun) => {
    setBusyAction(`script:${run.runId}`)
    setError(null)
    try {
      updateRun(await approveOperatorScript(run))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusyAction(null)
    }
  }

  const approveVideo = async (run: OperatorRun) => {
    setBusyAction(`video:${run.runId}`)
    setError(null)
    try {
      updateRun(await approveOperatorVideo(run))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusyAction(null)
    }
  }

  if (!operatorApiConfigured) {
    return <section className="operator-card">
      <div className="compact-heading"><h2>Neue Produktion</h2><span className="status-badge failed">Offline</span></div>
    </section>
  }

  return <section className="operator-layout">
    <article className="operator-card">
      <div className="compact-heading">
        <h2>Neues Skript</h2>
        <label className="auto-script-toggle">
          <input
            type="checkbox"
            checked={autoGenerate}
            onChange={event => setAutoGenerate(event.target.checked)}
          />
          <span>Autogenerate Skript</span>
        </label>
      </div>
      <div className="production-profile-controls">
        <label>Auflösungen
          <select
            value={roundCount}
            onChange={event => changeRoundCount(Number(event.target.value) as SupportedRoundCount)}
          >
            <option value={5}>5</option>
            <option value={7}>7</option>
          </select>
        </label>
        <label>Ziellänge
          <select value={targetDurationSeconds} onChange={event => setTargetDurationSeconds(Number(event.target.value))}>
            {[61, 62, 63, 64, 65, 66, 67, 68, 69, 70].map(seconds => <option value={seconds} key={seconds}>{seconds} s</option>)}
          </select>
        </label>
        {autoGenerate && <button
          className="secondary-action"
          type="button"
          onClick={() => void generateDraft()}
          disabled={generating || saving}
        >
          {generating ? 'Entwurf wird erstellt …' : 'Entwurf erstellen'}
        </button>}
      </div>
      {autoGenerate && <div className="auto-script-meta">
        {draft
          ? <span>{draft.styleExampleCount} freigegebene Stilbeispiele · Entwurf bleibt editierbar</span>
          : <span>Erstellt nur einen Entwurf. Produktion startet erst nach deiner Freigabe.</span>}
      </div>}
      <textarea
        aria-label="Videoskript"
        onChange={event => setScript(event.target.value)}
        placeholder={autoGenerate ? 'Entwurf erstellen oder Skript selbst eingeben …' : 'Skript einfügen …'}
        rows={14}
        value={script}
      />
      <div className="operator-controls">
        <span className={markers === roundCount ? 'marker-count valid' : 'marker-count'}>{markers}/{roundCount} Auflösungen</span>
        <span className={words >= minimumWords ? 'marker-count valid' : 'marker-count'}>{words}/{minimumWords} Wörter</span>
        <span className={brandValid ? 'marker-count valid' : 'marker-count'}>
          {brandValid ? 'keine App-Nennung' : 'App-Nennung entfernen'}
        </span>
        <button className="primary-action" type="button" onClick={() => void saveScript()} disabled={saving || !scriptValid}>
          {saving ? 'Wird gespeichert …' : 'Skript zur Prüfung speichern'}
        </button>
      </div>
      {error && <p className="operator-error">{error}</p>}

      <section className="research-suggestions">
        <div className="compact-heading">
          <h2>Research</h2>
          {research && <span className={research.dataReadiness.status}>
            Retention {research.dataReadiness.retentionVideos}/{research.dataReadiness.minimumComparableVideos}
          </span>}
        </div>
        {research
          ? <>
              <p className="research-readiness">{research.dataReadiness.message}</p>
              <div className="research-options">
                <button
                  type="button"
                  className={selectedRecommendationId === null ? 'selected' : ''}
                  onClick={() => selectRecommendation(null)}
                >
                  Baseline
                </button>
                {research.recommendations.map(recommendation => <button
                  type="button"
                  key={recommendation.id}
                  className={selectedRecommendationId === recommendation.id ? 'selected' : ''}
                  onClick={() => selectRecommendation(recommendation.id)}
                >
                  <strong>{recommendation.title}</strong>
                  <small>{recommendation.primaryParameter} · {recommendation.confidence}</small>
                </button>)}
              </div>
              {selectedRecommendationId && <p className="research-action">
                {research.recommendations.find(entry => entry.id === selectedRecommendationId)?.action}
              </p>}
            </>
          : <p className="compact-empty">{researchError ?? 'Research wird geladen …'}</p>}
      </section>
    </article>

    <aside className="operator-card operator-runs">
      <div className="compact-heading">
        <h2>Freigaben</h2>
        <button className="text-button" type="button" onClick={() => void refresh()} disabled={saving}>↻</button>
      </div>
      <div className="operator-run-list">
        {runs.length > 0
          ? runs.slice(0, 8).map((run, index) => <RunCard
            key={run.runId}
            run={run}
            busyAction={busyAction}
            onApproveScript={approveScript}
            onApproveVideo={approveVideo}
            initiallyOpen={index === 0}
          />)
          : <p className="compact-empty">Keine Läufe</p>}
      </div>
    </aside>
  </section>
}
