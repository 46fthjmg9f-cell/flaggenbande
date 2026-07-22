import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  emptyContentOperations,
  parseContentOperations,
  type ContentOperationsData,
  type PlatformId,
  type PublicationStatus,
} from './contentOperations'
import {
  listCalendarEntries,
  readOperatorToken,
  type CalendarEntry,
  type CalendarPlatform,
  type CalendarPlatformState,
} from './operatorApi'
import type { SocialPlatform, SocialVideo } from './types'

const platforms: CalendarPlatform[] = ['youtube', 'instagram', 'facebook', 'tiktok']
const platformLabels: Record<CalendarPlatform, string> = { youtube: 'YT', instagram: 'IG', facebook: 'FB', tiktok: 'TT' }

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

function calendarStatus(status: PublicationStatus): CalendarPlatformState['status'] {
  if (status === 'published') return 'published'
  if (status === 'scheduled') return 'scheduled'
  if (status === 'uploading' || status === 'processing') return 'publishing'
  if (status === 'failed' || status === 'expired' || status === 'reconcile_required') return 'failed'
  return 'missing'
}

function blankPlatforms(): CalendarEntry['platforms'] {
  return {
    youtube: { status: 'missing' },
    instagram: { status: 'missing' },
    facebook: { status: 'missing' },
    tiktok: { status: 'missing' },
  }
}

function publicCalendarEntries(data: ContentOperationsData): CalendarEntry[] {
  const runs = new Map(data.runs.map(run => [run.contentId, run]))
  const grouped = new Map<string, CalendarEntry>()
  for (const publication of data.publications) {
    const scheduledAt = publication.publishedAt ?? publication.scheduledAt
    if (!scheduledAt) continue
    const key = `${publication.contentId}:${scheduledAt}`
    const existing = grouped.get(key) ?? {
      id: key,
      contentId: publication.contentId,
      title: publication.title ?? runs.get(publication.contentId)?.title ?? 'Video',
      scheduledAt,
      platforms: blankPlatforms(),
    }
    existing.platforms[publication.platform as PlatformId] = {
      status: calendarStatus(publication.status),
      ...(publication.publicUrl ? { publicUrl: publication.publicUrl } : {}),
    }
    grouped.set(key, existing)
  }
  return [...grouped.values()]
}

function normalizeContentText(value: string): string {
  return value.normalize('NFKC').toLocaleLowerCase('en').replace(/https?:\/\/\S+/gu, ' ').replace(/#/gu, '').replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/gu, ' ').trim()
}

function cleanTitle(value: string): string {
  const title = value.split(/\r?\n/u)[0]?.replace(/(?:\s*#[\p{L}\p{N}_-]+)+\s*$/gu, '').trim() ?? ''
  return title || 'Video'
}

function socialCalendarEntries(videos: readonly SocialVideo[]): CalendarEntry[] {
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
    const platforms = blankPlatforms()
    for (const video of grouped) {
      let publicUrl: string | undefined
      try {
        const parsed = video.url ? new URL(video.url) : null
        publicUrl = parsed?.protocol === 'https:' ? parsed.toString() : undefined
      } catch {
        publicUrl = undefined
      }
      platforms[video.platform] = { status: 'published', ...(publicUrl ? { publicUrl } : {}) }
    }
    const preferred = grouped.find(video => video.platform === 'youtube') ?? grouped[0]
    return [{ id: `social:${key}`, contentId: key, title: cleanTitle(preferred?.title ?? 'Video'), scheduledAt, platforms }]
  })
}

function mergeEntries(primary: CalendarEntry[], fallback: CalendarEntry[]): CalendarEntry[] {
  const byContent = new Map<string, CalendarEntry>()
  for (const entry of [...fallback, ...primary]) {
    const key = `${entry.contentId}:${entry.scheduledAt}`
    const previous = byContent.get(key)
    if (!previous) {
      byContent.set(key, entry)
      continue
    }
    byContent.set(key, {
      ...previous,
      ...entry,
      platforms: Object.fromEntries(platforms.map(platform => {
        const incoming = entry.platforms[platform]
        return [platform, incoming.status === 'missing' ? previous.platforms[platform] : incoming]
      })) as CalendarEntry['platforms'],
    })
  }
  return [...byContent.values()].sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt))
}

function weekLabel(start: Date, end: Date): string {
  const format = new Intl.DateTimeFormat('de-DE', { day: '2-digit', month: '2-digit' })
  return `${format.format(start)}–${format.format(addDays(end, -1))}`
}

export default function PublishingCalendar({ socialVideos }: { readonly socialVideos: readonly SocialVideo[] }) {
  const [weekStart, setWeekStart] = useState(() => startOfDay(new Date()))
  const [entries, setEntries] = useState<CalendarEntry[]>([])
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const weekEnd = useMemo(() => addDays(weekStart, 7), [weekStart])

  const refresh = useCallback(async () => {
    setRefreshing(true)
    setError(null)
    try {
      const publicResponse = await fetch(`./data/content-operations.json?refresh=${Date.now()}`, { cache: 'no-store' })
      const publicData = publicResponse.ok ? parseContentOperations(await publicResponse.json()) : emptyContentOperations
      let protectedEntries: CalendarEntry[] = []
      if (readOperatorToken()) {
        try {
          protectedEntries = await listCalendarEntries(weekStart.toISOString(), weekEnd.toISOString())
        } catch (reason) {
          setError(reason instanceof Error ? reason.message : String(reason))
        }
      }
      setEntries(mergeEntries(protectedEntries, [...publicCalendarEntries(publicData), ...socialCalendarEntries(socialVideos)]))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setRefreshing(false)
    }
  }, [socialVideos, weekEnd, weekStart])

  useEffect(() => {
    void refresh()
  }, [refresh])

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
              <strong title={entry.title}>{entry.title}</strong>
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
