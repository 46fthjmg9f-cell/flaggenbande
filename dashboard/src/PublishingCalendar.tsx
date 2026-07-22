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

export default function PublishingCalendar() {
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
      setEntries(mergeEntries(protectedEntries, publicCalendarEntries(publicData)))
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setRefreshing(false)
    }
  }, [weekEnd, weekStart])

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
