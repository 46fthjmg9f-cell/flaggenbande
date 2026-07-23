import { useEffect } from 'react'

export const VISIBLE_REFRESH_MS = 15_000
export const HIDDEN_REFRESH_MS = 60_000

export function adaptiveRefreshDelay(hidden: boolean): number {
  return hidden ? HIDDEN_REFRESH_MS : VISIBLE_REFRESH_MS
}

export function useAdaptiveRefresh(refresh: () => Promise<void>): void {
  useEffect(() => {
    let disposed = false
    let running = false
    let timer: ReturnType<typeof setTimeout> | null = null

    const clearTimer = () => {
      if (timer !== null) clearTimeout(timer)
      timer = null
    }
    const schedule = () => {
      clearTimer()
      if (disposed) return
      timer = setTimeout(() => void run(), adaptiveRefreshDelay(document.hidden))
    }
    const run = async () => {
      if (disposed || running) return
      running = true
      try {
        await refresh()
      } finally {
        running = false
        schedule()
      }
    }
    const handleFocus = () => {
      clearTimer()
      void run()
    }
    const handleVisibility = () => {
      clearTimer()
      if (document.hidden) schedule()
      else void run()
    }

    void run()
    window.addEventListener('focus', handleFocus)
    document.addEventListener('visibilitychange', handleVisibility)
    return () => {
      disposed = true
      clearTimer()
      window.removeEventListener('focus', handleFocus)
      document.removeEventListener('visibilitychange', handleVisibility)
    }
  }, [refresh])
}
