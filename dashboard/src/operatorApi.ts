export type OperatorRunStatus = 'queued' | 'claimed' | 'running' | 'waiting' | 'completed' | 'failed'

export interface OperatorRun {
  runId: string
  status: OperatorRunStatus
  progress: number
  targetDurationSeconds: number
  currentStep: string | null
  message: string | null
  error: string | null
  createdAt: string
  updatedAt: string
}

export type CalendarPlatform = 'youtube' | 'instagram' | 'facebook' | 'tiktok'
export type CalendarPlatformStatus = 'scheduled' | 'publishing' | 'published' | 'failed' | 'missing'

export interface CalendarPlatformState {
  status: CalendarPlatformStatus
  publicUrl?: string
}

export interface CalendarEntry {
  id: string
  contentId: string
  title: string
  scheduledAt: string
  platforms: Record<CalendarPlatform, CalendarPlatformState>
}

interface StartRunInput {
  script: string
  targetDurationSeconds: number
}

const TOKEN_KEY = 'flaggenbande-operator-token'

function configuredBaseUrl(): string | null {
  const value = import.meta.env.VITE_OPERATOR_API_URL?.trim()
  if (!value) return null
  const url = new URL(value)
  const local = url.hostname === '127.0.0.1' || url.hostname === 'localhost'
  if (url.protocol !== 'https:' && !(import.meta.env.DEV && local)) {
    throw new Error('Die Steuer-API muss HTTPS verwenden.')
  }
  return url.toString().replace(/\/$/, '')
}

export const operatorApiConfigured = configuredBaseUrl() !== null

export function readOperatorToken(): string | null {
  return sessionStorage.getItem(TOKEN_KEY)
}

export function saveOperatorToken(token: string): void {
  const value = token.trim()
  if (!value) throw new Error('Steuerungsschlüssel fehlt.')
  sessionStorage.setItem(TOKEN_KEY, value)
}

export function clearOperatorToken(): void {
  sessionStorage.removeItem(TOKEN_KEY)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${field} fehlt.`)
  return value
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null
}

function parseRun(value: unknown): OperatorRun {
  if (!isRecord(value)) throw new Error('Ungültige Laufantwort.')
  const status = requiredString(value.status, 'status')
  if (!['queued', 'claimed', 'running', 'waiting', 'completed', 'failed'].includes(status)) {
    throw new Error('Unbekannter Laufstatus.')
  }
  const progress = typeof value.progress === 'number' && Number.isFinite(value.progress)
    ? Math.min(100, Math.max(0, value.progress))
    : 0
  const targetDurationSeconds = typeof value.targetDurationSeconds === 'number' && Number.isFinite(value.targetDurationSeconds)
    ? value.targetDurationSeconds
    : 65
  return {
    runId: requiredString(value.runId, 'runId'),
    status: status as OperatorRunStatus,
    progress,
    targetDurationSeconds,
    currentStep: nullableString(value.currentStep),
    message: nullableString(value.message),
    error: nullableString(value.error),
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
  return { status, ...(publicUrl ? { publicUrl } : {}) }
}

function parseCalendarEntry(value: unknown): CalendarEntry {
  if (!isRecord(value) || !isRecord(value.platforms)) throw new Error('Ungültiger Kalendereintrag.')
  return {
    id: requiredString(value.id, 'id'),
    contentId: requiredString(value.contentId, 'contentId'),
    title: requiredString(value.title, 'title'),
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
  const token = readOperatorToken()
  if (!token) throw new Error('Steuerung ist gesperrt.')
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
  })
  if (response.status === 401 || response.status === 403) {
    clearOperatorToken()
    throw new Error('Steuerungsschlüssel ungültig.')
  }
  const payload: unknown = await response.json().catch(() => null)
  if (!response.ok) {
    const detail = isRecord(payload) && typeof payload.error === 'string' ? payload.error : `HTTP ${response.status}`
    throw new Error(detail)
  }
  return payload
}

export async function listOperatorRuns(limit = 20): Promise<OperatorRun[]> {
  const payload = await request(`/v1/runs?limit=${Math.min(50, Math.max(1, Math.round(limit)))}`)
  if (!isRecord(payload) || !Array.isArray(payload.runs)) throw new Error('Ungültige Laufliste.')
  return payload.runs.map(parseRun)
}

export async function startOperatorRun(input: StartRunInput): Promise<OperatorRun> {
  return parseRun(await request('/v1/runs', { method: 'POST', body: JSON.stringify(input) }))
}

export async function listCalendarEntries(from: string, to: string): Promise<CalendarEntry[]> {
  const query = new URLSearchParams({ from, to })
  const payload = await request(`/v1/calendar?${query.toString()}`)
  if (!isRecord(payload) || !Array.isArray(payload.entries)) throw new Error('Ungültiger Kalender.')
  return payload.entries.map(parseCalendarEntry)
}
