export type PublicNumeric = number | null

export const CONTENT_OPERATIONS_SCHEMA_VERSION = 1 as const
export const PLATFORM_IDS = ['youtube', 'instagram', 'tiktok', 'facebook'] as const

export type PlatformId = typeof PLATFORM_IDS[number]
export type ContentDataStatus = 'ok' | 'partial' | 'waiting_for_sources' | 'error'
export type SystemStatus = 'ready' | 'planned' | 'not_configured' | 'error'
export type PlatformStatus = 'not_configured' | 'planned' | 'ready' | 'uploading' | 'scheduled' | 'published' | 'failed'
export type PublicationStatus = PlatformStatus | 'planned' | 'processing' | 'private' | 'draft' | 'container_unpublished' | 'upload_ready' | 'manual_uploaded' | 'expired' | 'reconcile_required'
export type ProductionRunStatus = 'queued' | 'running' | 'partial' | 'qa_failed' | 'ready' | 'completed' | 'failed' | 'expired' | 'reconcile_required'
export type QualityStatus = 'not_run' | 'passed' | 'failed'

export interface PublicSystemComponent {
  id: 'engine' | 'release' | 'database' | 'quality'
  label: string
  value: string
  status: SystemStatus
  detail: string
  updatedAt: string | null
}

export interface PublicPlatformSummary {
  platform: PlatformId
  label: string
  status: PlatformStatus
  uploads: number
  publications: number
  performanceAvailable: boolean
  reason: string
  updatedAt: string | null
}

export interface PublicProductionRun {
  runId: string
  contentId: string
  title: string | null
  status: ProductionRunStatus
  qualityStatus: QualityStatus
  startedAt: string
  completedAt: string | null
}

export interface PublicPublication {
  runId: string
  contentId: string
  platform: PlatformId
  mode: 'private' | 'container_unpublished' | 'manual_uploaded' | 'draft'
  status: PublicationStatus
  updatedAt: string
  title: string | null
  scheduledAt: string | null
  publishedAt: string | null
  publicUrl: string | null
}

export interface PublicPerformanceSnapshot {
  contentId: string
  platform: PlatformId
  collectedAt: string
  views: PublicNumeric
  impressions: PublicNumeric
  watchTimeSeconds: PublicNumeric
  averageViewDurationSeconds: PublicNumeric
  averageViewedPercentage: PublicNumeric
  completionRate: PublicNumeric
  likes: PublicNumeric
  comments: PublicNumeric
  shares: PublicNumeric
  saves: PublicNumeric
  followersDelta: PublicNumeric
}

export interface ContentOperationsData {
  schemaVersion: typeof CONTENT_OPERATIONS_SCHEMA_VERSION
  generatedAt: string | null
  status: ContentDataStatus
  messages: string[]
  system: PublicSystemComponent[]
  platforms: PublicPlatformSummary[]
  runs: PublicProductionRun[]
  publications: PublicPublication[]
  performance: PublicPerformanceSnapshot[]
}

const dataStatuses: readonly ContentDataStatus[] = ['ok', 'partial', 'waiting_for_sources', 'error']
const systemStatuses: readonly SystemStatus[] = ['ready', 'planned', 'not_configured', 'error']
const platformStatuses: readonly PlatformStatus[] = ['not_configured', 'planned', 'ready', 'uploading', 'scheduled', 'published', 'failed']
const publicationStatuses: readonly PublicationStatus[] = [...platformStatuses, 'planned', 'processing', 'private', 'draft', 'container_unpublished', 'upload_ready', 'manual_uploaded', 'expired', 'reconcile_required']
const runStatuses: readonly ProductionRunStatus[] = ['queued', 'running', 'partial', 'qa_failed', 'ready', 'completed', 'failed', 'expired', 'reconcile_required']
const qualityStatuses: readonly QualityStatus[] = ['not_run', 'passed', 'failed']
const systemIds: readonly PublicSystemComponent['id'][] = ['engine', 'release', 'database', 'quality']

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function requiredRecord(value: unknown, path: string): Record<string, unknown> {
  if (!isRecord(value)) throw new Error(`${path} muss ein Objekt sein.`)
  return value
}

function requiredArray(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`${path} muss eine Liste sein.`)
  return value
}

function requiredString(value: unknown, path: string): string {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${path} muss ein nicht-leerer Text sein.`)
  return value
}

function nullableString(value: unknown, path: string): string | null {
  if (value === null) return null
  return requiredString(value, path)
}

function requiredNumber(value: unknown, path: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${path} muss eine endliche Zahl sein.`)
  return value
}

function requiredCount(value: unknown, path: string): number {
  const number = requiredNumber(value, path)
  if (!Number.isInteger(number) || number < 0) throw new Error(`${path} muss eine nicht-negative ganze Zahl sein.`)
  return number
}

function nullableNumber(value: unknown, path: string): PublicNumeric {
  return value === null ? null : requiredNumber(value, path)
}

function requiredBoolean(value: unknown, path: string): boolean {
  if (typeof value !== 'boolean') throw new Error(`${path} muss true oder false sein.`)
  return value
}

function nullablePublicUrl(value: unknown, path: string): string | null {
  const text = nullableString(value, path)
  if (text === null) return null
  try {
    const url = new URL(text)
    if (url.protocol !== 'https:') throw new Error('Nur HTTPS ist öffentlich zulässig.')
  } catch {
    throw new Error(`${path} muss eine öffentliche HTTPS-Adresse sein.`)
  }
  return text
}

function enumValue<T extends string>(value: unknown, allowed: readonly T[], path: string): T {
  if (typeof value !== 'string' || !allowed.includes(value as T)) throw new Error(`${path} enthält einen unbekannten Status.`)
  return value as T
}

function parseSystem(value: unknown, index: number): PublicSystemComponent {
  const path = `system[${index}]`
  const record = requiredRecord(value, path)
  return {
    id: enumValue(record.id, systemIds, `${path}.id`),
    label: requiredString(record.label, `${path}.label`),
    value: requiredString(record.value, `${path}.value`),
    status: enumValue(record.status, systemStatuses, `${path}.status`),
    detail: requiredString(record.detail, `${path}.detail`),
    updatedAt: nullableString(record.updatedAt, `${path}.updatedAt`),
  }
}

function parsePlatform(value: unknown, index: number): PublicPlatformSummary {
  const path = `platforms[${index}]`
  const record = requiredRecord(value, path)
  return {
    platform: enumValue(record.platform, PLATFORM_IDS, `${path}.platform`),
    label: requiredString(record.label, `${path}.label`),
    status: enumValue(record.status, platformStatuses, `${path}.status`),
    uploads: requiredCount(record.uploads, `${path}.uploads`),
    publications: requiredCount(record.publications, `${path}.publications`),
    performanceAvailable: requiredBoolean(record.performanceAvailable, `${path}.performanceAvailable`),
    reason: requiredString(record.reason, `${path}.reason`),
    updatedAt: nullableString(record.updatedAt, `${path}.updatedAt`),
  }
}

function parseRun(value: unknown, index: number): PublicProductionRun {
  const path = `runs[${index}]`
  const record = requiredRecord(value, path)
  return {
    runId: requiredString(record.runId, `${path}.runId`),
    contentId: requiredString(record.contentId, `${path}.contentId`),
    title: nullableString(record.title, `${path}.title`),
    status: enumValue(record.status, runStatuses, `${path}.status`),
    qualityStatus: enumValue(record.qualityStatus, qualityStatuses, `${path}.qualityStatus`),
    startedAt: requiredString(record.startedAt, `${path}.startedAt`),
    completedAt: nullableString(record.completedAt, `${path}.completedAt`),
  }
}

function parsePublication(value: unknown, index: number): PublicPublication {
  const path = `publications[${index}]`
  const record = requiredRecord(value, path)
  return {
    runId: requiredString(record.runId, `${path}.runId`),
    contentId: requiredString(record.contentId, `${path}.contentId`),
    platform: enumValue(record.platform, PLATFORM_IDS, `${path}.platform`),
    mode: enumValue(record.mode, ['private', 'container_unpublished', 'manual_uploaded', 'draft'] as const, `${path}.mode`),
    status: enumValue(record.status, publicationStatuses, `${path}.status`),
    updatedAt: requiredString(record.updatedAt, `${path}.updatedAt`),
    title: nullableString(record.title, `${path}.title`),
    scheduledAt: nullableString(record.scheduledAt, `${path}.scheduledAt`),
    publishedAt: nullableString(record.publishedAt, `${path}.publishedAt`),
    publicUrl: nullablePublicUrl(record.publicUrl, `${path}.publicUrl`),
  }
}

function parsePerformance(value: unknown, index: number): PublicPerformanceSnapshot {
  const path = `performance[${index}]`
  const record = requiredRecord(value, path)
  return {
    contentId: requiredString(record.contentId, `${path}.contentId`),
    platform: enumValue(record.platform, PLATFORM_IDS, `${path}.platform`),
    collectedAt: requiredString(record.collectedAt, `${path}.collectedAt`),
    views: nullableNumber(record.views, `${path}.views`),
    impressions: nullableNumber(record.impressions, `${path}.impressions`),
    watchTimeSeconds: nullableNumber(record.watchTimeSeconds, `${path}.watchTimeSeconds`),
    averageViewDurationSeconds: nullableNumber(record.averageViewDurationSeconds, `${path}.averageViewDurationSeconds`),
    averageViewedPercentage: nullableNumber(record.averageViewedPercentage, `${path}.averageViewedPercentage`),
    completionRate: nullableNumber(record.completionRate, `${path}.completionRate`),
    likes: nullableNumber(record.likes, `${path}.likes`),
    comments: nullableNumber(record.comments, `${path}.comments`),
    shares: nullableNumber(record.shares, `${path}.shares`),
    saves: nullableNumber(record.saves, `${path}.saves`),
    followersDelta: nullableNumber(record.followersDelta, `${path}.followersDelta`),
  }
}

export function parseContentOperations(value: unknown): ContentOperationsData {
  const root = requiredRecord(value, 'content-operations')
  if (root.schemaVersion !== CONTENT_OPERATIONS_SCHEMA_VERSION) throw new Error('Unbekannte Content-System-Schemaversion.')

  const messages = requiredArray(root.messages, 'messages').map((entry, index) => requiredString(entry, `messages[${index}]`))
  const system = requiredArray(root.system, 'system').map(parseSystem)
  const platforms = requiredArray(root.platforms, 'platforms').map(parsePlatform)

  const componentIds = new Set(system.map(entry => entry.id))
  if (componentIds.size !== systemIds.length || systemIds.some(component => !componentIds.has(component))) {
    throw new Error('Engine, Release, Datenbank oder Quality-Status fehlen oder sind doppelt.')
  }

  const platformIds = new Set(platforms.map(entry => entry.platform))
  if (platformIds.size !== PLATFORM_IDS.length || PLATFORM_IDS.some(platform => !platformIds.has(platform))) {
    throw new Error('Die vier erwarteten Plattformstatus fehlen oder sind doppelt.')
  }

  return {
    schemaVersion: CONTENT_OPERATIONS_SCHEMA_VERSION,
    generatedAt: nullableString(root.generatedAt, 'generatedAt'),
    status: enumValue(root.status, dataStatuses, 'status'),
    messages,
    system,
    platforms,
    runs: requiredArray(root.runs, 'runs').map(parseRun),
    publications: requiredArray(root.publications, 'publications').map(parsePublication),
    performance: requiredArray(root.performance, 'performance').map(parsePerformance),
  }
}

export const emptyContentOperations: ContentOperationsData = {
  schemaVersion: CONTENT_OPERATIONS_SCHEMA_VERSION,
  generatedAt: null,
  status: 'waiting_for_sources',
  messages: [],
  system: [],
  platforms: [],
  runs: [],
  publications: [],
  performance: [],
}
