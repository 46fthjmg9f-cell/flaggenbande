import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  approveOperatorScript,
  approveOperatorVideo,
  generateOperatorScriptDraft,
  getResearchRecommendations,
  listOperatorRuns,
  operatorApiConfigured,
  operatorPreviewUrl,
  retryOperatorRun,
  reviseOperatorVideo,
  startOperatorRun,
  type OperatorRun,
  type OperatorRunStatus,
  type ResearchRecommendationFeed,
  type ScriptDraft,
  type SupportedRoundCount,
} from './operatorApi'
import { displayReleaseLabel } from './videoDisplay'
import {
  durationOptionsForRounds,
  isProductionRoundCount,
  minimumSpokenWordsForRounds,
  recommendedTargetDuration,
  scriptProfileIssueMessage,
  supportedRoundCounts,
  validateScriptProfile,
} from '../../shared/scriptProfileValidation'

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

type RetentionEvidenceStatus = 'measured' | 'aggregate_only' | 'pending' | 'unavailable'

function retentionEvidence(
  research: ResearchRecommendationFeed | null,
  researchError: string | null,
): { status: RetentionEvidenceStatus; label: string; detail: string } {
  if (!research) {
    return researchError
      ? { status: 'unavailable', label: 'Nicht verfügbar', detail: researchError }
      : { status: 'pending', label: 'Wird geprüft', detail: 'Retention-Daten werden geladen.' }
  }
  const readiness = research.dataReadiness
  if (readiness.retentionVideos > 0) {
    return {
      status: 'measured',
      label: `${readiness.retentionVideos} gemessen`,
      detail: `${readiness.retentionVideos} Videos mit echter Retention-Kurve.`,
    }
  }
  if (readiness.averageViewPercentageVideos > 0) {
    return {
      status: 'aggregate_only',
      label: 'Nur Durchschnitt',
      detail: `${readiness.averageViewPercentageVideos} Videos mit Durchschnittswert, aber ohne Retention-Kurve.`,
    }
  }
  if (readiness.linkedYoutubeVideos > 0 || readiness.platformVideoCount > 0) {
    return {
      status: 'pending',
      label: 'Noch ausstehend',
      detail: `${readiness.linkedYoutubeVideos} verknüpfte Videos, noch keine Retention-Messpunkte.`,
    }
  }
  return {
    status: 'unavailable',
    label: 'Nicht verfügbar',
    detail: 'Noch keine verknüpften Videos mit Retention-Daten.',
  }
}

function recommendationDelta(recommendation: ResearchRecommendationFeed['recommendations'][number]): string | null {
  const value = recommendation as typeof recommendation & {
    readonly delta?: unknown
    readonly metricDelta?: unknown
    readonly deltaPercent?: unknown
  }
  const candidate = value.delta ?? value.metricDelta ?? value.deltaPercent
  if (typeof candidate === 'number' && Number.isFinite(candidate)) {
    const prefix = candidate > 0 ? '+' : ''
    return `${prefix}${candidate.toLocaleString('de-DE')} %`
  }
  return typeof candidate === 'string' && candidate.trim() ? candidate.trim() : null
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

const safelyRetryablePreviewSteps = new Set(['flag_selection', 'timeline_build', 'render'])

interface RunCardProps {
  run: OperatorRun
  busyAction: string | null
  onApproveScript: (run: OperatorRun) => Promise<void>
  onApproveVideo: (run: OperatorRun) => Promise<void>
  onReviseVideo: (run: OperatorRun) => Promise<void>
  onRetry: (run: OperatorRun) => Promise<void>
  initiallyOpen: boolean
}

function RunCard({ run, busyAction, onApproveScript, onApproveVideo, onReviseVideo, onRetry, initiallyOpen }: RunCardProps) {
  const previewUrl = operatorPreviewUrl(run)
  const approvingScript = busyAction === `script:${run.runId}`
  const approvingVideo = busyAction === `video:${run.runId}`
  const revisingVideo = busyAction === `revision:${run.runId}`
  const retrying = busyAction === `retry:${run.runId}`
  const gatesPassed = run.preview.qualityPassed && run.preview.monetizationPassed
  const scriptPending = run.status === 'awaiting_script_approval' && run.script.status === 'pending'
  const videoPending = run.status === 'awaiting_video_approval' && run.videoApproval.status === 'pending'
  const safelyRevisableFailedPreview = run.status === 'failed' &&
    (run.currentStep === 'preview_revision' || run.currentStep === 'script_validation') &&
    run.error === 'LOCAL_PREVIEW_REVISION_REJECTED' &&
    run.script.status === 'approved' &&
    run.preview.ready &&
    gatesPassed &&
    run.videoApproval.status === 'pending' &&
    run.release.requestId === null &&
    run.release.status === null
  const canReviseVideo = videoPending || safelyRevisableFailedPreview
  const safelyRetryable = run.status === 'failed' &&
    safelyRetryablePreviewSteps.has(run.currentStep ?? '') &&
    run.script.status === 'approved' &&
    !run.preview.ready &&
    run.videoApproval.status === 'not_ready' &&
    run.release.requestId === null &&
    run.release.status === null
  const release = releaseStatus(run)

  return <details className={`operator-run operator-review ${run.status}`} open={initiallyOpen || scriptPending || canReviseVideo}>
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
      {canReviseVideo && <button
        className="secondary-action"
        type="button"
        onClick={() => void onReviseVideo(run)}
        disabled={Boolean(busyAction)}
      >
        {revisingVideo ? 'Nachbesserung wird eingeplant …' : 'Video nachbessern'}
      </button>}
      {safelyRetryable && <button
        className="secondary-action"
        type="button"
        onClick={() => void onRetry(run)}
        disabled={Boolean(busyAction)}
      >
        {retrying ? 'Wird erneut eingeplant …' : 'Produktion erneut versuchen'}
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
  const [targetDurationSeconds, setTargetDurationSeconds] = useState(recommendedTargetDuration(5))
  const [draft, setDraft] = useState<ScriptDraft | null>(null)
  const [research, setResearch] = useState<ResearchRecommendationFeed | null>(null)
  const [researchError, setResearchError] = useState<string | null>(null)
  const [selectedRecommendationId, setSelectedRecommendationId] = useState<string | null>(null)
  const [runs, setRuns] = useState<OperatorRun[]>([])
  const [saving, setSaving] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [busyAction, setBusyAction] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const validation = useMemo(
    () => validateScriptProfile(script, roundCount, targetDurationSeconds),
    [roundCount, script, targetDurationSeconds],
  )
  const markers = validation.revealCount
  const words = validation.spokenWordCount
  const brandMentions = validation.brandMentionCount
  const minimumWords = minimumSpokenWordsForRounds(roundCount)
  const durationOptions = useMemo(() => durationOptionsForRounds(roundCount), [roundCount])
  const brandValid = brandMentions === 0
  const retention = useMemo(() => retentionEvidence(research, researchError), [research, researchError])
  const scriptValid = validation.valid
  const productionRoundCountSupported = isProductionRoundCount(roundCount)
  const validationMessages = useMemo(
    () => [...new Set(validation.details.map(scriptProfileIssueMessage))],
    [validation.details],
  )
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
    if (!scriptValid || !productionRoundCountSupported) return
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
    setTargetDurationSeconds(recommendedTargetDuration(value))
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

  const reviseVideo = async (run: OperatorRun) => {
    setBusyAction(`revision:${run.runId}`)
    setError(null)
    try {
      updateRun(await reviseOperatorVideo(run))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusyAction(null)
    }
  }

  const retryRun = async (run: OperatorRun) => {
    setBusyAction(`retry:${run.runId}`)
    setError(null)
    try {
      updateRun(await retryOperatorRun(run))
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
            {supportedRoundCounts.map(value => <option value={value} key={value}>{value}</option>)}
          </select>
        </label>
        <label>Ziellänge
          <select value={targetDurationSeconds} onChange={event => setTargetDurationSeconds(Number(event.target.value))}>
            {durationOptions.map(seconds => <option value={seconds} key={seconds}>{seconds} s</option>)}
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
        <button
          className="primary-action"
          type="button"
          onClick={() => void saveScript()}
          disabled={saving || !scriptValid || !productionRoundCountSupported}
        >
          {saving ? 'Wird gespeichert …' : 'Skript zur Prüfung speichern'}
        </button>
      </div>
      {!productionRoundCountSupported && <p className="production-round-limit">
        Produktion aktuell nur 5 oder 7
      </p>}
      {script.trim() && !scriptValid && <ul className="operator-validation-errors">
        {validationMessages.map(message => <li key={message}>{message}</li>)}
      </ul>}
      {error && <p className="operator-error">{error}</p>}

      <section className="research-suggestions">
        <div className="compact-heading">
          <h2>Research</h2>
          <span className={`retention-status ${retention.status}`}>{retention.label}</span>
        </div>
        {research
          ? <>
              <p className="research-readiness">{retention.detail}</p>
              <div className="research-options">
                <button
                  type="button"
                  className={selectedRecommendationId === null ? 'selected' : ''}
                  onClick={() => selectRecommendation(null)}
                >
                  Baseline
                </button>
                {research.recommendations.map(recommendation => {
                  const delta = recommendationDelta(recommendation)
                  return <button
                    type="button"
                    key={recommendation.id}
                    className={selectedRecommendationId === recommendation.id ? 'selected' : ''}
                    onClick={() => selectRecommendation(recommendation.id)}
                  >
                    <strong>{recommendation.title}</strong>
                    <small className="research-wording">{recommendation.action}</small>
                    <small>{recommendation.primaryParameter} · {recommendation.targetMetric}</small>
                    <small>n={recommendation.sampleSize} · Δ {delta ?? '—'} · {recommendation.confidence}</small>
                  </button>
                })}
              </div>
              {research.recommendations.length === 0 &&
                <p className="compact-empty research-empty">Noch keine belastbare Formulierungsempfehlung.</p>}
              {selectedRecommendationId && <p className="research-action">
                {research.recommendations.find(entry => entry.id === selectedRecommendationId)?.action}
              </p>}
              {research.phraseEvaluations.length > 0 && <div className="phrase-retention-list">
                <strong>Formulierungen</strong>
                {research.phraseEvaluations.slice(0, 5).map(evaluation =>
                  <div key={evaluation.formulationKey}>
                    <span>{evaluation.formulation}</span>
                    <small>
                      {evaluation.phraseType} · {evaluation.videoCount} Videos · Δ{' '}
                      {evaluation.medianDeltaPercentagePoints.toLocaleString('de-DE')} pp
                    </small>
                  </div>)}
              </div>}
            </>
          : <p className="compact-empty">{retention.detail}</p>}
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
            onReviseVideo={reviseVideo}
            onRetry={retryRun}
            initiallyOpen={index === 0}
          />)
          : <p className="compact-empty">Keine Läufe</p>}
      </div>
    </aside>
  </section>
}
