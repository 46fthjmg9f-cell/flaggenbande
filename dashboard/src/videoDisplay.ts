export type CalendarVisualStatus = 'published' | 'ready' | 'processing' | 'failed' | 'missing'

export interface CalendarPlatformMergeState {
  status: CalendarVisualStatus
  publicUrl?: string
  updatedAt?: string
}

export interface ReleaseDisplayInput {
  runId?: string | null
  contentId?: string | null
  releaseLabel?: string | null
  videoApproved?: boolean
  finalReleaseApproved?: boolean
}

export interface VideoDisplayInput extends ReleaseDisplayInput {
  title?: string | null
}

export function mergeReleaseDisplayMetadata(
  previous: ReleaseDisplayInput,
  incoming: ReleaseDisplayInput,
): Pick<ReleaseDisplayInput, 'releaseLabel' | 'videoApproved' | 'finalReleaseApproved'> {
  return {
    releaseLabel: incoming.releaseLabel === undefined ? previous.releaseLabel : incoming.releaseLabel,
    videoApproved: incoming.videoApproved === undefined ? previous.videoApproved : incoming.videoApproved,
    finalReleaseApproved: incoming.finalReleaseApproved === undefined
      ? previous.finalReleaseApproved
      : incoming.finalReleaseApproved,
  }
}

function cleanReleaseLabel(value: string | null | undefined): string | null {
  if (typeof value !== 'string') return null
  const label = value.trim().replace(/x$/iu, '')
  return label || null
}

interface HistoricalRelease {
  label: string
  approved: boolean
}

const historicalByRunId = new Map<string, HistoricalRelease>([
  ['upload-gameshow-v7-professional-cold-open-experiment', { label: '2107.01', approved: true }],
  ['upload-gameshow-v8-check-das-mal-aus', { label: '2107.02', approved: true }],
  ['upload-gameshow-five-flag-60plus-20260722-v2', { label: '2207.02', approved: true }],
  ['upload-video-e5866d048c7f5cf134ccaaac-aligned-v3', { label: '2207.05', approved: false }],
  ['video-cb9acc1e7b8f4de4f2ac0994', { label: '2207.07', approved: true }],
  ['video-96ea90bc9a4358947eff8bae', { label: '2207.08', approved: false }],
])

const historicalByContentId = new Map<string, HistoricalRelease>([
  ['flaggenbande-adeebf2787e0b5a8c64b924bc1ff6cb02504520b3af1b195993ada6ce35d95f9', { label: '2107.01', approved: true }],
  ['flaggenbande-60b324334e3dfad6864547fcfc6ca6f95fb181dcf2d33b1741308a5cfa41900f', { label: '2107.02', approved: true }],
  ['flaggenbande-2937437f0c18c124cb527f5919ffacbfcc14144ed9d6c48d33fa55787eae42f3', { label: '2207.02', approved: true }],
  ['flaggenbande-d5d58ed0a267906df92b71bdd913555f27f3a7be064765f5d6b4d3cd092dc67d', { label: '2207.05', approved: false }],
  ['flaggenbande-c8308857c76af5d5fcd74cd726f7eb85a6940d84f20b31993cf739da6a9307ff', { label: '2207.07', approved: true }],
])

function historicalRelease(input: ReleaseDisplayInput): HistoricalRelease | null {
  const byRun = input.runId ? historicalByRunId.get(input.runId) : undefined
  if (byRun) return byRun
  return input.contentId ? historicalByContentId.get(input.contentId) ?? null : null
}

export function displayReleaseLabel(input: ReleaseDisplayInput): string | null {
  const historical = historicalRelease(input)
  const label = cleanReleaseLabel(input.releaseLabel ?? historical?.label)
  if (!label) return null
  const approved = input.videoApproved === true || input.finalReleaseApproved === true || historical?.approved === true
  return approved ? `${label}X` : label
}

export function displayVideoName(input: VideoDisplayInput): string {
  const label = displayReleaseLabel(input)
  const title = input.title?.trim() || 'Video'
  if (!label) return title

  const baseLabel = cleanReleaseLabel(input.releaseLabel ?? historicalRelease(input)?.label)
  const lowerTitle = title.toLocaleLowerCase('de-DE')
  const labels = [label, baseLabel].filter((value): value is string => typeof value === 'string')
  const prefixes = labels.flatMap(value => [`${value} · `, `${value}: `, `${value} `])
    .sort((left, right) => right.length - left.length)
  const prefix = prefixes.find(value => lowerTitle.startsWith(value.toLocaleLowerCase('de-DE')))
  const cleanTitle = prefix ? title.slice(prefix.length).trim() : title
  return cleanTitle && cleanTitle !== label && cleanTitle !== baseLabel ? `${label} · ${cleanTitle}` : label
}

export function calendarVisualStatus(status: string | null | undefined): CalendarVisualStatus {
  if (status === 'published') return 'published'
  if (['planned', 'ready', 'scheduled', 'private', 'draft', 'container_unpublished', 'upload_ready', 'manual_uploaded'].includes(status ?? '')) return 'ready'
  if (status === 'uploading' || status === 'processing' || status === 'publishing' || status === 'running') return 'processing'
  if (status === 'failed' || status === 'expired' || status === 'reconcile_required') return 'failed'
  return 'missing'
}

function validTimestamp(value: string | undefined): number | null {
  if (!value) return null
  const timestamp = Date.parse(value)
  return Number.isFinite(timestamp) ? timestamp : null
}

export function mergeCalendarPlatformState(
  previous: CalendarPlatformMergeState,
  incoming: CalendarPlatformMergeState,
  preferIncoming = false,
): CalendarPlatformMergeState {
  if (previous.status === 'published' && incoming.status !== 'published') return previous
  if (incoming.status === 'published' && previous.status !== 'published') return incoming
  if (incoming.status === 'missing') return previous
  if (previous.status === 'missing') return incoming

  const previousTimestamp = validTimestamp(previous.updatedAt)
  const incomingTimestamp = validTimestamp(incoming.updatedAt)
  if (previousTimestamp !== null && incomingTimestamp !== null && previousTimestamp !== incomingTimestamp) {
    return incomingTimestamp > previousTimestamp ? incoming : previous
  }
  if (preferIncoming) return incoming

  const priority: Record<CalendarVisualStatus, number> = {
    missing: 0,
    ready: 1,
    processing: 2,
    failed: 3,
    published: 4,
  }
  return priority[incoming.status] >= priority[previous.status] ? incoming : previous
}

export function stableCalendarIdentity(input: {
  contentId?: string | null
  runId?: string | null
  id?: string | null
}): string {
  const contentId = input.contentId?.trim()
  const runId = input.runId?.trim()
  if (contentId && runId) return `content:${contentId}:run:${runId}`
  if (contentId) return `content:${contentId}`
  if (runId) return `run:${runId}`
  return `entry:${input.id?.trim() || 'unknown'}`
}

export function chooseCalendarSlot(
  scheduledDates: ReadonlyArray<string | null | undefined>,
  publishedDates: ReadonlyArray<string | null | undefined>,
): { scheduledAt: string; slotKind: 'scheduled' | 'published' } | null {
  const firstValid = (values: ReadonlyArray<string | null | undefined>): string | null => {
    const valid = values
      .filter((value): value is string => typeof value === 'string' && Number.isFinite(Date.parse(value)))
      .sort()
    return valid[0] ?? null
  }
  const scheduledAt = firstValid(scheduledDates)
  if (scheduledAt) return { scheduledAt, slotKind: 'scheduled' }
  const publishedAt = firstValid(publishedDates)
  return publishedAt ? { scheduledAt: publishedAt, slotKind: 'published' } : null
}
