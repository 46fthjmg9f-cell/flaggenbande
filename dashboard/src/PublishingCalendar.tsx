import { useCallback, useMemo, useState } from 'react'
import {
  emptyContentOperations,
  parseContentOperations,
  type ContentOperationsData,
  type PlatformId,
  type PublicationStatus,
} from './contentOperations'
import {
  listCalendarEntries,
  type CalendarEntry,
  type CalendarPlatform,
} from './operatorApi'
import type { DashboardData, SocialPlatform, SocialVideo } from './types'
import { useAdaptiveRefresh } from './useAdaptiveRefresh'
import {
  calendarVisualStatus,
  chooseCalendarSlot,
  displayVideoName,
  mergeCalendarPlatformState,
  mergeReleaseDisplayMetadata,
  stableCalendarIdentity,
  type CalendarPlatformMergeState,
  type CalendarVisualStatus,
} from './videoDisplay'

const platforms: CalendarPlatform[] = ['youtube', 'instagram', 'facebook', 'tiktok']
const platformLabels: Record<CalendarPlatform, string> = { youtube: 'YT', instagram: 'IG', facebook: 'FB', tiktok: 'TT' }

type DisplayCalendarPlatformState = CalendarPlatformMergeState

interface DisplayCalendarEntry {
  id: string
  runId?: string
  contentId: string
  title: string
  releaseLabel?: string | null
  videoApproved?: boolean
  finalReleaseApproved?: boolean
  scheduledAt: string
  slotKind: 'scheduled' | 'published'
  platforms: Record<CalendarPlatform, DisplayCalendarPlatformState>
}

function startOfDay(date: Date): Date {
  const value = new Date(date)
  value.setHours(0, 0, 0, 0)
  return value
}

function addDays(date: Date, days: number): Date {
  const value = new Date(date)
  value.setDate(value.getDate() + days)
  return value
}

function localDayKey(date: Date): string {
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-')
}

function calendarStatus(status: PublicationStatus): CalendarVisualStatus {
  return calendarVisualStatus(status)
}

function blankPlatforms(): DisplayCalendarEntry['platforms'] {
  return {
    youtube: { status: 'missing' },
    instagram: { status: 'missing' },
    facebook: { status: 'missing' },
    tiktok: { status: 'missing' },
  }
}

export function publicCalendarEntries(data: ContentOperationsData): DisplayCalendarEntry[] {
  const runs = new Map(data.runs.map(run => [stableCalendarIdentity(run), run]))
  const grouped = new Map<string, typeof data.publications>()
  for (const publication of data.publications) {
    const key = stableCalendarIdentity(publication)
    grouped.set(key, [...(grouped.get(key) ?? []), publication])
  }
  return [...grouped.entries()].flatMap(([key, publications]) => {
    const slot = chooseCalendarSlot(
      publications.map(entry => entry.scheduledAt),
      publications.map(entry => entry.publishedAt),
    )
    if (!slot) return []
    const run = runs.get(key)
    const entry: DisplayCalendarEntry = {
      id: key,
      runId: publications[0]?.runId,
      contentId: publications[0]?.contentId ?? run?.contentId ?? key,
      title: publications.find(item => item.title)?.title ?? run?.title ?? 'Video',
      releaseLabel: run?.releaseLabel ?? publications.find(item => item.releaseLabel !== undefined)?.releaseLabel,
      videoApproved: run?.videoApproved ?? publications.some(item => item.videoApproved === true),
      finalReleaseApproved: run?.finalReleaseApproved ?? publications.some(item => item.finalReleaseApproved === true),
      scheduledAt: slot.scheduledAt,
      slotKind: slot.slotKind,
      platforms: blankPlatforms(),
    }
    for (const publication of publications) {
      const platform = publication.platform as PlatformId
      const incoming: DisplayCalendarPlatformState = {
        status: calendarStatus(publication.status),
        updatedAt: publication.updatedAt,
        ...(publication.publicUrl ? { publicUrl: publication.publicUrl } : {}),
      }
      const previous = entry.platforms[platform]
      entry.platforms[platform] = mergeCalendarPlatformState(previous, incoming)
    }
    return [entry]
  })
}

function normalizeContentText(value: string): string {
  return value.normalize('NFKC').toLocaleLowerCase('en').replace(/https?:\/\/\S+/gu, ' ').replace(/#/gu, '').replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/gu, ' ').trim()
}

function cleanTitle(value: string): string {
  const title = value.split(/\r?\n/u)[0]?.replace(/(?:\s*#[\p{L}\p{N}_-]+)+\s*$/gu, '').trim() ?? ''
  return title || 'Video'
}

function socialCalendarEntries(videos: readonly SocialVideo[]): DisplayCalendarEntry[] {
  const signature = (video: SocialVideo): string | null => {
    const description = normalizeContentText(video.description)
    if (description.length >= 40) return description
    const title = normalizeContentText(video.title)
    return title.length >= 24 ? title : null
  }
  const candidates = new Map<string, { contentIds: Set<string>; platforms: Map<SocialPlatform, number> }>()
  for (const video of videos) {
    const value = signature(video)
    if (!value) continue
    const candidate = candidates.get(value) ?? { contentIds: new Set<string>(), platforms: new Map<SocialPlatform, number>() }
    if (video.contentId) candidate.contentIds.add(video.contentId)
    candidate.platforms.set(video.platform, (candidate.platforms.get(video.platform) ?? 0) + 1)
    candidates.set(value, candidate)
  }
  const groupKeys = new Map([...candidates.entries()]
    .filter(([, candidate]) => candidate.contentIds.size <= 1 && candidate.platforms.size >= 2 && [...candidate.platforms.values()].every(count => count === 1))
    .map(([value, candidate]) => [value, [...candidate.contentIds][0] ?? `copy:${value}`]))
  const groups = new Map<string, SocialVideo[]>()
  for (const video of videos) {
    if (!video.publishedAt) continue
    const value = signature(video)
    const key = video.contentId ?? (value ? groupKeys.get(value) : undefined) ?? `${video.platform}:${video.platformVideoId}`
    groups.set(key, [...(groups.get(key) ?? []), video])
  }
  return [...groups.entries()].flatMap(([key, grouped]) => {
    const scheduledAt = grouped.map(video => video.publishedAt).filter((value): value is string => Boolean(value)).sort().at(-1)
    if (!scheduledAt) return []
    const platformStates = blankPlatforms()
    for (const video of grouped) {
      let publicUrl: string | undefined
      try {
        const parsed = video.url ? new URL(video.url) : null
        publicUrl = parsed?.protocol === 'https:' ? parsed.toString() : undefined
      } catch {
        publicUrl = undefined
      }
      platformStates[video.platform] = {
        status: calendarVisualStatus(video.status === 'published' || video.publishedAt ? 'published' : video.status),
        ...(video.publishedAt ? { updatedAt: video.publishedAt } : {}),
        ...(publicUrl ? { publicUrl } : {}),
      }
    }
    const preferred = grouped.find(video => video.platform === 'youtube') ?? grouped[0]
    return [{
      id: `social:${key}`,
      contentId: key,
      title: cleanTitle(preferred?.title ?? 'Video'),
      scheduledAt,
      slotKind: 'published' as const,
      platforms: platformStates,
    }]
  })
}

function protectedCalendarEntries(entries: CalendarEntry[]): DisplayCalendarEntry[] {
  return entries.map(entry => ({
    ...entry,
    slotKind: 'scheduled',
    platforms: Object.fromEntries(platforms.map(platform => [
      platform,
      {
        ...entry.platforms[platform],
        status: calendarVisualStatus(entry.platforms[platform].status),
      },
    ])) as DisplayCalendarEntry['platforms'],
  }))
}

export function mergeEntries(primary: DisplayCalendarEntry[], fallback: DisplayCalendarEntry[]): DisplayCalendarEntry[] {
  const entries: DisplayCalendarEntry[] = []
  const mergeEntry = (entry: DisplayCalendarEntry, preferIncoming: boolean) => {
    const identity = stableCalendarIdentity(entry)
    const index = entries.findIndex(candidate =>
      stableCalendarIdentity(candidate) === identity ||
      (candidate.contentId === entry.contentId && (!candidate.runId || !entry.runId)),
    )
    const previous = index >= 0 ? entries[index] : undefined
    if (!previous) {
      entries.push(entry)
      return
    }
    const scheduledAt = entry.slotKind === 'scheduled'
      ? entry.scheduledAt
      : previous.slotKind === 'scheduled'
        ? previous.scheduledAt
        : entry.scheduledAt
    entries[index] = {
      ...previous,
      ...entry,
      ...mergeReleaseDisplayMetadata(previous, entry),
      scheduledAt,
      slotKind: previous.slotKind === 'scheduled' || entry.slotKind === 'scheduled' ? 'scheduled' : 'published',
      platforms: Object.fromEntries(platforms.map(platform => {
        return [
          platform,
          mergeCalendarPlatformState(previous.platforms[platform], entry.platforms[platform], preferIncoming),
        ]
      })) as DisplayCalendarEntry['platforms'],
    }
  }
  for (const entry of fallback) mergeEntry(entry, false)
  for (const entry of primary) mergeEntry(entry, true)
  return entries.sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt))
}

function weekLabel(start: Date, end: Date): string {
  const format = new Intl.DateTimeFormat('de-DE', { day: '2-digit', month: '2-digit' })
  return `${format.format(start)}–${format.format(addDays(end, -1))}`
}

export default function PublishingCalendar({ socialVideos }: { readonly socialVideos: readonly SocialVideo[] }) {
  const [weekStart, setWeekStart] = useState(() => startOfDay(new Date()))
  const [entries, setEntries] = useState<DisplayCalendarEntry[]>([])
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const weekEnd = useMemo(() => addDays(weekStart, 7), [weekStart])

  const refresh = useCallback(async () => {
    setRefreshing(true)
    setError(null)
    try {
      const refreshKey = Date.now()
      const [publicResponse, dashboardResponse] = await Promise.all([
        fetch(`./data/content-operations.json?refresh=${refreshKey}`, { cache: 'no-store' }),
        fetch(`./data/dashboard.json?refresh=${refreshKey}`, { cache: 'no-store' }),
      ])
      const publicData = publicResponse.ok ? parseContentOperations(await publicResponse.json()) : emptyContentOperations
      let currentSocialVideos = socialVideos
      if (dashboardResponse.ok) {
        const dashboardData = await dashboardResponse.json() as Partial<DashboardData>
        if (Array.isArray(dashboardData.social?.videos)) currentSocialVideos = dashboardData.social.videos
      }
      let protectedEntries: CalendarEntry[] = []
      try {
        protectedEntries = await listCalendarEntries(weekStart.toISOString(), weekEnd.toISOString())
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : String(reason))
      }
      setEntries(mergeEntries(
        protectedCalendarEntries(protectedEntries),
        [...publicCalendarEntries(publicData), ...socialCalendarEntries(currentSocialVideos)],
      ))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setRefreshing(false)
    }
  }, [socialVideos, weekEnd, weekStart])

  useAdaptiveRefresh(refresh)

  const days = useMemo(() => Array.from({ length: 7 }, (_, index) => addDays(weekStart, index)), [weekStart])

  return <section id="calendar-view" className="dashboard-view" role="tabpanel" aria-labelledby="calendar-tab" tabIndex={0}>
    <header className="compact-page-header">
      <h1>Kalender</h1>
      <div className="calendar-navigation">
        <button type="button" onClick={() => setWeekStart(value => addDays(value, -7))} aria-label="Vorherige Woche">‹</button>
        <button type="button" onClick={() => setWeekStart(startOfDay(new Date()))}>{weekLabel(weekStart, weekEnd)}</button>
        <button type="button" onClick={() => setWeekStart(value => addDays(value, 7))} aria-label="Nächste Woche">›</button>
        <button type="button" onClick={() => void refresh()} disabled={refreshing} aria-label="Kalender aktualisieren">↻</button>
      </div>
    </header>
    {error && <p className="operator-error calendar-error">{error}</p>}
    <div className="publication-calendar">
      {days.map(day => {
        const dayKey = localDayKey(day)
        const dayEntries = entries.filter(entry => {
          const scheduled = new Date(entry.scheduledAt)
          return !Number.isNaN(scheduled.valueOf()) && localDayKey(scheduled) === dayKey
        })
        return <section className="calendar-day" key={dayKey}>
          <header><strong>{new Intl.DateTimeFormat('de-DE', { weekday: 'short' }).format(day)}</strong><span>{new Intl.DateTimeFormat('de-DE', { day: '2-digit', month: '2-digit' }).format(day)}</span></header>
          <div className="calendar-day-list">
            {dayEntries.length > 0 ? dayEntries.map(entry => <article className="calendar-slot" key={entry.id}>
              <time dateTime={entry.scheduledAt}>{new Intl.DateTimeFormat('de-DE', { hour: '2-digit', minute: '2-digit' }).format(new Date(entry.scheduledAt))}</time>
              <strong title={displayVideoName(entry)}>{displayVideoName(entry)}</strong>
              <div className="calendar-platforms">
                {platforms.map(platform => {
                  const state = entry.platforms[platform]
                  const label = <span className={`calendar-platform ${state.status}`} title={`${platform}: ${state.status}`}>{platformLabels[platform]}</span>
                  return state.publicUrl ? <a href={state.publicUrl} target="_blank" rel="noreferrer" key={platform}>{label}</a> : <span key={platform}>{label}</span>
                })}
              </div>
            </article>) : <span className="calendar-empty">—</span>}
          </div>
        </section>
      })}
    </div>
  </section>
}
