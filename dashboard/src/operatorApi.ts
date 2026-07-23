import {
  scriptProfileIssueMessage,
  type ScriptProfileIssue,
  type ScriptProfileIssueCode,
  type SupportedRoundCount,
} from '../../shared/scriptProfileValidation'

export type { SupportedRoundCount } from '../../shared/scriptProfileValidation'

export type OperatorProductionStatus = 'queued' | 'claimed' | 'running' | 'waiting' | 'completed' | 'failed'
export type OperatorRunStatus =
  | 'awaiting_script_approval'
  | OperatorProductionStatus
  | 'awaiting_video_approval'
  | 'release_queued'
  | 'published'

export interface OperatorScriptReview {
  text: string
  sha256: string
  revision: number
  status: 'pending' | 'approved'
  approvedAt: string | null
}

export interface OperatorPreview {
  ready: boolean
  url: string | null
  sha256: string | null
  revision: number
  sizeBytes: number | null
  contentType: string | null
  qualityPassed: boolean
  monetizationPassed: boolean
  uploadedAt: string | null
}

export interface OperatorVideoApproval {
  status: 'not_ready' | 'pending' | 'approved'
  revision: number
  approvedAt: string | null
}

export interface OperatorRelease {
  requestId: string | null
  status: 'pending' | 'queued' | 'claimed' | 'processing' | 'completed' | 'published' | 'failed' | null
  platforms: Record<CalendarPlatform, CalendarPlatformState>
  error: string | null
  createdAt: string | null
}

export interface OperatorRun {
  runId: string
  releaseLabel: string
  status: OperatorRunStatus
  productionStatus: OperatorProductionStatus
  progress: number
  targetDurationSeconds: number
  currentStep: string | null
  message: string | null
  error: string | null
  script: OperatorScriptReview
  preview: OperatorPreview
  videoApproval: OperatorVideoApproval
  release: OperatorRelease
  createdAt: string
  updatedAt: string
}

export type CalendarPlatform = 'youtube' | 'instagram' | 'facebook' | 'tiktok'
export type CalendarPlatformStatus = 'scheduled' | 'publishing' | 'published' | 'failed' | 'missing'

export interface CalendarPlatformState {
  status: CalendarPlatformStatus
  publicUrl?: string
  updatedAt?: string
}

export interface CalendarEntry {
  id: string
  runId?: string
  contentId: string
  title: string
  releaseLabel?: string | null
  videoApproved?: boolean
  finalReleaseApproved?: boolean
  scheduledAt: string
  platforms: Record<CalendarPlatform, CalendarPlatformState>
}

export interface ScriptDraft {
  draftId: string
  script: string
  scriptSha256: string
  roundCount: SupportedRoundCount
  suggestedDurationSeconds: number
  generatorVersion: string
  styleExampleCount: number
  recommendationId: string | null
  learnedSignals: string[]
  createdAt: string
}

export interface ResearchRecommendation {
  id: string
  title: string
  action: string
  primaryParameter: string
  targetMetric: string
  evidenceLevel: 'measured' | 'public' | 'inferred' | 'unavailable'
  confidence: 'low' | 'medium' | 'high'
  sampleSize: number
  sourceRun: string
  autoApplicable: false
}

export interface ResearchRecommendationFeed {
  schemaVersion: '1.0.0'
  generatedAt: string
  dataReadiness: {
    status: 'ready' | 'insufficient'
    platformVideoCount: number
    linkedYoutubeVideos: number
    retentionVideos: number
    averageViewPercentageVideos: number
    minimumComparableVideos: number
    message: string
  }
  recommendations: ResearchRecommendation[]
}

interface StartRunInput {
  script: string
  targetDurationSeconds: number
  roundCount: SupportedRoundCount
  draftId?: string
}

function configuredBaseUrl(): string | null {
  const value = import.meta.env.VITE_OPERATOR_API_URL?.trim()
  const sameWorkerOrigin = typeof window !== 'undefined' &&
    window.location.protocol === 'https:' &&
    !window.location.hostname.endsWith('.github.io')
    ? window.location.origin
    : null
  if (!value && !sameWorkerOrigin) return null
  const url = new URL(value || sameWorkerOrigin || '')
  const local = url.hostname === '127.0.0.1' || url.hostname === 'localhost'
  if (url.protocol !== 'https:' && !(import.meta.env.DEV && local)) {
    throw new Error('Die Steuer-API muss HTTPS verwenden.')
  }
  return url.toString().replace(/\/$/, '')
}

export const operatorApiConfigured = configuredBaseUrl() !== null

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

const scriptProfileIssueCodes = new Set<ScriptProfileIssueCode>([
  'SCRIPT_LENGTH_TOO_LOW',
  'SCRIPT_LENGTH_TOO_HIGH',
  'ROUND_COUNT',
  'QUESTION_TEXT_MISSING',
  'QUESTION_PROMPT_MISSING',
  'FINAL_REACTION_MISSING',
  'SPOKEN_WORDS_TOO_LOW',
  'BRAND_MENTION_FORBIDDEN',
  'DIRECT_PROMOTION',
  'GERMAN_LANGUAGE_SIGNAL',
  'DURATION_PLAUSIBILITY',
])

function parseScriptProfileIssues(value: unknown): ScriptProfileIssue[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((entry): ScriptProfileIssue[] => {
    if (!isRecord(entry) || typeof entry.code !== 'string' ||
        !scriptProfileIssueCodes.has(entry.code as ScriptProfileIssueCode)) return []
    const numeric = (key: string): number | undefined =>
      typeof entry[key] === 'number' && Number.isFinite(entry[key]) ? entry[key] : undefined
    return [{
      code: entry.code as ScriptProfileIssueCode,
      ...(numeric('roundIndex') === undefined ? {} : { roundIndex: numeric('roundIndex') }),
      ...(numeric('actual') === undefined ? {} : { actual: numeric('actual') }),
      ...(numeric('expected') === undefined ? {} : { expected: numeric('expected') }),
      ...(numeric('minimum') === undefined ? {} : { minimum: numeric('minimum') }),
      ...(numeric('maximum') === undefined ? {} : { maximum: numeric('maximum') }),
    }]
  })
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${field} fehlt.`)
  return value
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null
}

function requiredNumber(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${field} fehlt.`)
  return value
}

function nullableNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== 'boolean') throw new Error(`${field} fehlt.`)
  return value
}

function requiredFalse(value: unknown, field: string): false {
  if (value !== false) throw new Error(`${field} ist ungültig.`)
  return false
}

function requiredInteger(value: unknown, field: string): number {
  const number = requiredNumber(value, field)
  if (!Number.isInteger(number)) throw new Error(`${field} ist ungültig.`)
  return number
}

function enumValue<const T extends readonly string[]>(value: unknown, allowed: T, field: string): T[number] {
  const text = requiredString(value, field)
  if (!allowed.includes(text)) throw new Error(`${field} ist ungültig.`)
  return text as T[number]
}

const productionStatuses = ['queued', 'claimed', 'running', 'waiting', 'completed', 'failed'] as const
const runStatuses = [
  'awaiting_script_approval',
  ...productionStatuses,
  'awaiting_video_approval',
  'release_queued',
  'published',
] as const

function parseRun(value: unknown): OperatorRun {
  if (!isRecord(value)) throw new Error('Ungültige Laufantwort.')
  if (!isRecord(value.script) || !isRecord(value.preview) || !isRecord(value.videoApproval)) {
    throw new Error('Unvollständige Freigabedaten.')
  }
  const release = value.release === null || value.release === undefined ? null : value.release
  if (release !== null && !isRecord(release)) throw new Error('Ungültige Veröffentlichungsdaten.')
  const progress = typeof value.progress === 'number' && Number.isFinite(value.progress)
    ? Math.min(100, Math.max(0, value.progress))
    : 0
  return {
    runId: requiredString(value.runId, 'runId'),
    releaseLabel: requiredString(value.releaseLabel, 'releaseLabel'),
    status: enumValue(value.status, runStatuses, 'status'),
    productionStatus: enumValue(value.productionStatus, productionStatuses, 'productionStatus'),
    progress,
    targetDurationSeconds: requiredNumber(value.targetDurationSeconds, 'targetDurationSeconds'),
    currentStep: nullableString(value.currentStep),
    message: nullableString(value.message),
    error: nullableString(value.error),
    script: {
      text: requiredString(value.script.text, 'script.text'),
      sha256: requiredString(value.script.sha256, 'script.sha256'),
      revision: requiredNumber(value.script.revision, 'script.revision'),
      status: enumValue(value.script.status, ['pending', 'approved'] as const, 'script.status'),
      approvedAt: nullableString(value.script.approvedAt),
    },
    preview: {
      ready: requiredBoolean(value.preview.ready, 'preview.ready'),
      url: nullableString(value.preview.url),
      sha256: nullableString(value.preview.sha256),
      revision: typeof value.preview.revision === 'number' && Number.isFinite(value.preview.revision)
        ? value.preview.revision
        : 1,
      sizeBytes: nullableNumber(value.preview.sizeBytes),
      contentType: nullableString(value.preview.contentType),
      qualityPassed: requiredBoolean(value.preview.qualityPassed, 'preview.qualityPassed'),
      monetizationPassed: requiredBoolean(value.preview.monetizationPassed, 'preview.monetizationPassed'),
      uploadedAt: nullableString(value.preview.uploadedAt),
    },
    videoApproval: {
      status: enumValue(value.videoApproval.status, ['not_ready', 'pending', 'approved'] as const, 'videoApproval.status'),
      revision: requiredNumber(value.videoApproval.revision, 'videoApproval.revision'),
      approvedAt: nullableString(value.videoApproval.approvedAt),
    },
    release: release === null ? {
      requestId: null,
      status: null,
      platforms: {
        youtube: { status: 'missing' },
        instagram: { status: 'missing' },
        facebook: { status: 'missing' },
        tiktok: { status: 'missing' },
      },
      error: null,
      createdAt: null,
    } : {
      requestId: nullableString(release.requestId),
      status: release.status === null || release.status === undefined
        ? null
        : enumValue(release.status, ['pending', 'queued', 'claimed', 'processing', 'completed', 'published', 'failed'] as const, 'release.status'),
      platforms: isRecord(release.platforms) ? {
        youtube: parseCalendarState(release.platforms.youtube),
        instagram: parseCalendarState(release.platforms.instagram),
        facebook: parseCalendarState(release.platforms.facebook),
        tiktok: parseCalendarState(release.platforms.tiktok),
      } : {
        youtube: { status: 'missing' },
        instagram: { status: 'missing' },
        facebook: { status: 'missing' },
        tiktok: { status: 'missing' },
      },
      error: nullableString(release.error),
      createdAt: nullableString(release.createdAt),
    },
    createdAt: requiredString(value.createdAt, 'createdAt'),
    updatedAt: requiredString(value.updatedAt, 'updatedAt'),
  }
}

function parseCalendarState(value: unknown): CalendarPlatformState {
  if (!isRecord(value)) return { status: 'missing' }
  const status = typeof value.status === 'string' && ['scheduled', 'publishing', 'published', 'failed', 'missing'].includes(value.status)
    ? value.status as CalendarPlatformStatus
    : 'missing'
  const publicUrl = typeof value.publicUrl === 'string' && value.publicUrl.startsWith('https://') ? value.publicUrl : undefined
  const updatedAt = typeof value.updatedAt === 'string' && Number.isFinite(Date.parse(value.updatedAt))
    ? value.updatedAt
    : undefined
  return { status, ...(publicUrl ? { publicUrl } : {}), ...(updatedAt ? { updatedAt } : {}) }
}

function parseCalendarEntry(value: unknown): CalendarEntry {
  if (!isRecord(value) || !isRecord(value.platforms)) throw new Error('Ungültiger Kalendereintrag.')
  return {
    id: requiredString(value.id, 'id'),
    runId: typeof value.runId === 'string' && value.runId.trim() ? value.runId : undefined,
    contentId: requiredString(value.contentId, 'contentId'),
    title: requiredString(value.title, 'title'),
    releaseLabel: value.releaseLabel === null || typeof value.releaseLabel === 'string' ? value.releaseLabel : undefined,
    videoApproved: typeof value.videoApproved === 'boolean' ? value.videoApproved : undefined,
    finalReleaseApproved: typeof value.finalReleaseApproved === 'boolean' ? value.finalReleaseApproved : undefined,
    scheduledAt: requiredString(value.scheduledAt, 'scheduledAt'),
    platforms: {
      youtube: parseCalendarState(value.platforms.youtube),
      instagram: parseCalendarState(value.platforms.instagram),
      facebook: parseCalendarState(value.platforms.facebook),
      tiktok: parseCalendarState(value.platforms.tiktok),
    },
  }
}

async function request(path: string, init: RequestInit = {}): Promise<unknown> {
  const baseUrl = configuredBaseUrl()
  if (!baseUrl) throw new Error('Steuer-API ist noch nicht konfiguriert.')
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    cache: 'no-store',
    credentials: 'include',
    headers: {
      Accept: 'application/json',
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
  })
  const contentType = response.headers.get('content-type') ?? ''
  const payload: unknown = contentType.includes('application/json')
    ? await response.json().catch(() => null)
    : null
  if (response.status === 401 || response.status === 403) {
    throw new Error('Anmeldung für die Produktionssteuerung erforderlich.')
  }
  if (!response.ok) {
    const errorCode = isRecord(payload) && typeof payload.error === 'string'
      ? payload.error
      : `HTTP ${response.status}`
    const profileIssues = isRecord(payload) ? parseScriptProfileIssues(payload.issues) : []
    const detail = errorCode === 'INVALID_VIDEO_RUN_INPUT' && profileIssues.length > 0
      ? profileIssues.map(scriptProfileIssueMessage).join(' ')
      : errorCode
    throw new Error(detail)
  }
  return payload
}

function idempotencyKey(prefix: string, runId: string, revision: number): string {
  return `${prefix}:${runId}:${revision}`
}

export async function listOperatorRuns(limit = 20): Promise<OperatorRun[]> {
  const payload = await request(`/v1/runs?limit=${Math.min(50, Math.max(1, Math.round(limit)))}`)
  if (!isRecord(payload) || !Array.isArray(payload.runs)) throw new Error('Ungültige Laufliste.')
  return payload.runs.map(parseRun)
}

export async function startOperatorRun(input: StartRunInput): Promise<OperatorRun> {
  return parseRun(await request('/v1/runs', { method: 'POST', body: JSON.stringify(input) }))
}

function parseScriptDraft(value: unknown): ScriptDraft {
  if (!isRecord(value) || !Array.isArray(value.learnedSignals)) throw new Error('Ungültiger Skriptentwurf.')
  const roundCount = requiredInteger(value.roundCount, 'roundCount')
  if (roundCount !== 5 && roundCount !== 7) throw new Error('roundCount ist ungültig.')
  return {
    draftId: requiredString(value.draftId, 'draftId'),
    script: requiredString(value.script, 'script'),
    scriptSha256: requiredString(value.scriptSha256, 'scriptSha256'),
    roundCount,
    suggestedDurationSeconds: requiredNumber(value.suggestedDurationSeconds, 'suggestedDurationSeconds'),
    generatorVersion: requiredString(value.generatorVersion, 'generatorVersion'),
    styleExampleCount: requiredInteger(value.styleExampleCount, 'styleExampleCount'),
    recommendationId: nullableString(value.recommendationId),
    learnedSignals: value.learnedSignals.map((entry, index) => requiredString(entry, `learnedSignals.${index}`)),
    createdAt: requiredString(value.createdAt, 'createdAt'),
  }
}

function parseResearchRecommendation(value: unknown): ResearchRecommendation {
  if (!isRecord(value)) throw new Error('Ungültige Research-Empfehlung.')
  return {
    id: requiredString(value.id, 'recommendation.id'),
    title: requiredString(value.title, 'recommendation.title'),
    action: requiredString(value.action, 'recommendation.action'),
    primaryParameter: requiredString(value.primaryParameter, 'recommendation.primaryParameter'),
    targetMetric: requiredString(value.targetMetric, 'recommendation.targetMetric'),
    evidenceLevel: enumValue(value.evidenceLevel, ['measured', 'public', 'inferred', 'unavailable'] as const, 'recommendation.evidenceLevel'),
    confidence: enumValue(value.confidence, ['low', 'medium', 'high'] as const, 'recommendation.confidence'),
    sampleSize: requiredInteger(value.sampleSize, 'recommendation.sampleSize'),
    sourceRun: requiredString(value.sourceRun, 'recommendation.sourceRun'),
    autoApplicable: requiredFalse(value.autoApplicable, 'recommendation.autoApplicable'),
  }
}

export async function generateOperatorScriptDraft(input: {
  roundCount: SupportedRoundCount
  targetDurationSeconds: number
  recommendationId: string | null
}): Promise<ScriptDraft> {
  const clientRequestId = `draft:${crypto.randomUUID()}`
  return parseScriptDraft(await request('/v1/script-drafts', {
    method: 'POST',
    body: JSON.stringify({ ...input, clientRequestId }),
  }))
}

export async function getResearchRecommendations(): Promise<ResearchRecommendationFeed> {
  const value = await request('/v1/research/recommendations')
  if (!isRecord(value) || !isRecord(value.dataReadiness) || !Array.isArray(value.recommendations)) {
    throw new Error('Ungültige Research-Antwort.')
  }
  return {
    schemaVersion: enumValue(value.schemaVersion, ['1.0.0'] as const, 'schemaVersion'),
    generatedAt: requiredString(value.generatedAt, 'generatedAt'),
    dataReadiness: {
      status: enumValue(value.dataReadiness.status, ['ready', 'insufficient'] as const, 'dataReadiness.status'),
      platformVideoCount: requiredInteger(value.dataReadiness.platformVideoCount, 'dataReadiness.platformVideoCount'),
      linkedYoutubeVideos: requiredInteger(value.dataReadiness.linkedYoutubeVideos, 'dataReadiness.linkedYoutubeVideos'),
      retentionVideos: requiredInteger(value.dataReadiness.retentionVideos, 'dataReadiness.retentionVideos'),
      averageViewPercentageVideos: requiredInteger(value.dataReadiness.averageViewPercentageVideos, 'dataReadiness.averageViewPercentageVideos'),
      minimumComparableVideos: requiredInteger(value.dataReadiness.minimumComparableVideos, 'dataReadiness.minimumComparableVideos'),
      message: requiredString(value.dataReadiness.message, 'dataReadiness.message'),
    },
    recommendations: value.recommendations.map(parseResearchRecommendation),
  }
}

export async function approveOperatorScript(run: OperatorRun): Promise<OperatorRun> {
  return parseRun(await request(`/v1/runs/${encodeURIComponent(run.runId)}/approve-script`, {
    method: 'POST',
    body: JSON.stringify({
      scriptSha256: run.script.sha256,
      scriptRevision: run.script.revision,
      idempotencyKey: idempotencyKey('script', run.runId, run.script.revision),
    }),
  }))
}

export async function approveOperatorVideo(run: OperatorRun): Promise<OperatorRun> {
  if (!run.preview.sha256) throw new Error('Video-Prüfsumme fehlt.')
  return parseRun(await request(`/v1/runs/${encodeURIComponent(run.runId)}/approve-video`, {
    method: 'POST',
    body: JSON.stringify({
      previewSha256: run.preview.sha256,
      videoRevision: run.preview.revision,
      idempotencyKey: idempotencyKey('video', run.runId, run.preview.revision),
    }),
  }))
}

export function operatorPreviewUrl(run: OperatorRun): string | null {
  const baseUrl = configuredBaseUrl()
  if (!baseUrl || !run.preview.ready) return null
  if (!run.preview.url) return `${baseUrl}/v1/runs/${encodeURIComponent(run.runId)}/preview`
  return new URL(run.preview.url, `${baseUrl}/`).toString()
}

export async function listCalendarEntries(from: string, to: string): Promise<CalendarEntry[]> {
  const query = new URLSearchParams({ from, to })
  const payload = await request(`/v1/public/calendar?${query.toString()}`)
  if (!isRecord(payload) || !Array.isArray(payload.entries)) throw new Error('Ungültiger Kalender.')
  return payload.entries.map(parseCalendarEntry)
}
