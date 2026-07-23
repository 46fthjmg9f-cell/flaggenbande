interface BrowserLocation {
  readonly hostname: string
  readonly origin: string
  readonly search: string
  readonly hash: string
}

export function operatorDashboardRedirect(
  location: BrowserLocation,
  configuredOperatorApiUrl: string | undefined,
): string | null {
  if (!location.hostname.endsWith('.github.io')) return null

  const configuredUrl = configuredOperatorApiUrl?.trim()
  if (!configuredUrl) return null

  try {
    const target = new URL(configuredUrl)
    if (target.protocol !== 'https:' || target.origin === location.origin) return null

    target.pathname = '/'
    target.search = location.search
    target.hash = location.hash
    return target.toString()
  } catch {
    return null
  }
}
