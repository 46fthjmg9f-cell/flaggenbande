import { createHash } from 'node:crypto'

const PLATFORM_NAMES = ['youtube', 'instagram', 'facebook', 'tiktok']
const METRIC_NAMES = [
  'views',
  'reach',
  'likes',
  'comments',
  'shares',
  'saves',
  'watchTimeMinutes',
  'averageViewDurationSeconds',
  'averageViewPercentage',
  'skipRate',
  'followersGained',
]
const ADDITIVE_METRIC_NAMES = new Set([
  'views',
  'reach',
  'likes',
  'comments',
  'shares',
  'saves',
  'watchTimeMinutes',
  'followersGained',
])

const now = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
const numberOrNull = value => {
  if (value === null || value === undefined || value === '') return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}
const compactMetrics = values => Object.fromEntries(
  METRIC_NAMES.map(name => [name, numberOrNull(values[name])]),
)
const preserveKnownMetrics = (previous, current) => compactMetrics(Object.fromEntries(
  METRIC_NAMES.map(name => [name, current?.[name] ?? previous?.[name] ?? null]),
))
const summarizeMetrics = videos => compactMetrics(Object.fromEntries(METRIC_NAMES.map(name => [
  name,
  ADDITIVE_METRIC_NAMES.has(name)
    ? videos.reduce((sum, entry) => sum + (entry.metrics[name] ?? 0), 0)
    : null,
])))

const redactSensitiveText = (value, maximumLength = 300) => String(value ?? '')
  .replace(/\bBearer\s+[^\s,;]+/gi, 'Bearer [redacted]')
  .replace(/((?:access|refresh)[_-]?token|client[_-]?secret|api[_-]?key|authorization)(\s*[=:]\s*)[^\s,;&}"']+/gi, '$1$2[redacted]')
  .replace(/([?&](?:access_token|refresh_token|client_secret|api_key|key)=)[^&\s]+/gi, '$1[redacted]')
  .replace(/\b(?:sk|act|clt)\.[A-Za-z0-9._~-]+\b/g, '[redacted]')
  .slice(0, maximumLength)

const sanitizedPublicReason = error => {
  const explicit = error && typeof error === 'object' && 'publicReason' in error
    ? String(error.publicReason)
    : 'Die Plattform-API konnte voruebergehend nicht aktualisiert werden.'
  return redactSensitiveText(explicit)
}

const publicError = (message, publicReason) => {
  const error = new Error(message)
  error.publicReason = publicReason
  return error
}

async function fetchJson(fetchImpl, url, options = {}, retries = 2) {
  let lastError
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    let response
    try {
      response = await fetchImpl(url, options)
    } catch (error) {
      lastError = error
      if (attempt === retries) throw error
      await new Promise(resolve => setTimeout(resolve, 400 * (2 ** attempt)))
      continue
    }

    if (response.ok) return response.json()
    const body = await response.text()
    let apiPayload = null
    try {
      apiPayload = body ? JSON.parse(body) : null
    } catch {
      // Non-JSON error bodies still receive the safe HTTP-only public reason.
    }
    const error = publicError(
      `API request failed with HTTP ${response.status}.`,
      `API request failed with HTTP ${response.status}.`,
    )
    const apiError = apiPayload?.error
    error.apiFailure = {
      httpStatus: response.status,
      code: numberOrNull(apiError?.code) ?? nullableString(apiError?.code, 80),
      subcode: numberOrNull(apiError?.error_subcode) ?? nullableString(apiError?.error_subcode, 80),
      type: nullableString(apiError?.type, 100),
      message: apiError?.message ? redactSensitiveText(apiError.message, 240) : null,
    }
    const retryable = [429, 500, 502, 503, 504].includes(response.status)
    if (!retryable || attempt === retries) throw error
    lastError = error
    await new Promise(resolve => setTimeout(resolve, 400 * (2 ** attempt)))
  }
  throw lastError
}

const bearer = token => ({ authorization: `Bearer ${token}` })

const parseIsoDuration = value => {
  const match = String(value ?? '').match(/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/)
  if (!match) return null
  return (Number(match[1] ?? 0) * 86400) + (Number(match[2] ?? 0) * 3600) + (Number(match[3] ?? 0) * 60) + Number(match[4] ?? 0)
}

const audienceRetentionPoints = payload => {
  const names = (payload?.columnHeaders ?? []).map(header => String(header?.name ?? ''))
  const elapsedIndex = names.indexOf('elapsedVideoTimeRatio')
  const audienceIndex = names.indexOf('audienceWatchRatio')
  const relativeIndex = names.indexOf('relativeRetentionPerformance')
  if ([elapsedIndex, audienceIndex].some(index => index < 0)) return []

  const byElapsedRatio = new Map()
  for (const row of payload?.rows ?? []) {
    if (!Array.isArray(row)) continue
    const elapsedVideoTimeRatio = numberOrNull(row[elapsedIndex])
    const audienceWatchRatio = numberOrNull(row[audienceIndex])
    const rawRelativeRetention = relativeIndex < 0 ? null : numberOrNull(row[relativeIndex])
    if (elapsedVideoTimeRatio === null || elapsedVideoTimeRatio <= 0 || elapsedVideoTimeRatio > 1) continue
    if (audienceWatchRatio === null || audienceWatchRatio < 0 || audienceWatchRatio > 100) continue
    const relativeRetentionPerformance = rawRelativeRetention !== null && rawRelativeRetention >= 0 && rawRelativeRetention <= 1
      ? rawRelativeRetention
      : null
    byElapsedRatio.set(elapsedVideoTimeRatio, {
      elapsedVideoTimeRatio,
      audienceWatchRatio,
      relativeRetentionPerformance,
    })
  }
  return [...byElapsedRatio.values()]
    .sort((left, right) => left.elapsedVideoTimeRatio - right.elapsedVideoTimeRatio)
    .slice(0, 100)
}

async function collectYouTubeRetention(fetchImpl, headers, videoId, startDate, endDate) {
  const query = new URLSearchParams({
    ids: 'channel==MINE',
    startDate,
    endDate,
    filters: `video==${videoId}`,
    dimensions: 'elapsedVideoTimeRatio',
    metrics: 'audienceWatchRatio,relativeRetentionPerformance',
    sort: 'elapsedVideoTimeRatio',
    maxResults: '100',
  })
  try {
    const report = await fetchJson(fetchImpl, `https://youtubeanalytics.googleapis.com/v2/reports?${query}`, { headers }, 0)
    if (!Array.isArray(report?.rows) || report.rows.length === 0) {
      return {
        status: 'pending',
        points: [],
        reason: 'YouTube Analytics hat fuer dieses Video noch keine Retention-Daten geliefert.',
      }
    }
    const points = audienceRetentionPoints(report)
    if (points.length === 0) {
      return {
        status: 'no_data',
        points: [],
        reason: 'Der YouTube-Retention-Bericht enthielt keine verwertbaren Messpunkte.',
      }
    }
    return { status: 'available', points, reason: null }
  } catch (error) {
    return { status: 'error', points: [], reason: sanitizedPublicReason(error) }
  }
}

const video = ({ platform, id, contentId, title, description, publishedAt, url, thumbnailUrl, status, durationSeconds, metrics, retention, retentionCheckedAt, retentionCheckStatus, retentionCheckReason }) => ({
  platform,
  platformVideoId: String(id),
  contentId: typeof contentId === 'string' && contentId.trim() ? contentId.trim().slice(0, 200) : null,
  title: String(title || description || 'Ohne Titel').trim().slice(0, 240),
  description: String(description || '').trim().slice(0, 500),
  publishedAt: publishedAt || null,
  url: url || null,
  thumbnailUrl: thumbnailUrl || null,
  status: status || 'unknown',
  durationSeconds: numberOrNull(durationSeconds),
  metrics: compactMetrics(metrics || {}),
  ...(Array.isArray(retention) ? { retention: retention.slice(0, 100) } : {}),
  ...(normalizedDate(retentionCheckedAt) ? { retentionCheckedAt: normalizedDate(retentionCheckedAt) } : {}),
  ...(['available', 'pending', 'no_data', 'error'].includes(retentionCheckStatus) ? { retentionCheckStatus } : {}),
  ...(['pending', 'no_data', 'error'].includes(retentionCheckStatus) && retentionCheckReason
    ? { retentionCheckReason: String(retentionCheckReason).slice(0, 200) }
    : {}),
})

const nullableString = (value, maximumLength) => typeof value === 'string' && value.trim()
  ? value.trim().slice(0, maximumLength)
  : null

const normalizedDate = value => {
  if (value === null || value === undefined || value === '') return null
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? null : date.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

const upload = ({
  platform,
  id,
  contentId,
  title,
  description,
  uploadedAt,
  publishedAt,
  scheduledAt,
  url,
  thumbnailUrl,
  status,
  privacyStatus,
  uploadStatus,
  durationSeconds,
}) => {
  const normalizedPrivacy = nullableString(privacyStatus, 50)
  const isNonPublicYouTube = platform === 'youtube' && normalizedPrivacy !== null && normalizedPrivacy !== 'public'
  const rawId = String(id).trim().slice(0, 200)
  return {
    platform,
    platformVideoId: isNonPublicYouTube
      ? `non-public-${createHash('sha256').update(rawId).digest('hex').slice(0, 20)}`
      : rawId,
    contentId: isNonPublicYouTube ? null : nullableString(contentId, 200),
    title: isNonPublicYouTube ? 'Nichtöffentlicher YouTube-Upload' : String(title || description || 'Ohne Titel').trim().slice(0, 240),
    description: isNonPublicYouTube ? '' : String(description || '').trim().slice(0, 500),
    uploadedAt: normalizedDate(uploadedAt),
    publishedAt: isNonPublicYouTube ? null : normalizedDate(publishedAt),
    scheduledAt: isNonPublicYouTube ? null : normalizedDate(scheduledAt),
    url: isNonPublicYouTube ? null : nullableString(url, 500),
    thumbnailUrl: isNonPublicYouTube ? null : nullableString(thumbnailUrl, 500),
    status: nullableString(status, 50) ?? 'unknown',
    privacyStatus: normalizedPrivacy,
    uploadStatus: nullableString(uploadStatus, 50),
    durationSeconds: numberOrNull(durationSeconds),
  }
}

const youtubeUpload = item => {
  const privacyStatus = nullableString(item.status?.privacyStatus, 50) ?? 'unknown'
  const scheduledAt = normalizedDate(item.status?.publishAt)
  const status = scheduledAt && privacyStatus === 'private' ? 'scheduled' : privacyStatus
  const uploadedAt = normalizedDate(item.snippet?.publishedAt)
  return upload({
    platform: 'youtube',
    id: item.id,
    title: item.snippet?.title,
    description: item.snippet?.description,
    uploadedAt,
    publishedAt: privacyStatus === 'public' ? uploadedAt : null,
    scheduledAt,
    url: `https://www.youtube.com/watch?v=${item.id}`,
    thumbnailUrl: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.default?.url,
    status,
    privacyStatus,
    uploadStatus: item.status?.uploadStatus,
    durationSeconds: parseIsoDuration(item.contentDetails?.duration),
  })
}

async function googleAccessToken(env, fetchImpl) {
  if (env.YOUTUBE_ACCESS_TOKEN) return env.YOUTUBE_ACCESS_TOKEN
  const refreshToken = env.YOUTUBE_REFRESH_TOKEN || env.YOUTUBE_ANALYTICS_REFRESH_TOKEN
  const response = await fetchJson(fetchImpl, 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.YOUTUBE_CLIENT_ID,
      client_secret: env.YOUTUBE_CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  }, 0)
  if (!response.access_token) throw publicError('Google returned no access token.', 'Google returned no access token.')
  return response.access_token
}

const hasYouTubeCredentials = env => Boolean(
  env.YOUTUBE_ACCESS_TOKEN || (
    env.YOUTUBE_CLIENT_ID &&
    env.YOUTUBE_CLIENT_SECRET &&
    (env.YOUTUBE_REFRESH_TOKEN || env.YOUTUBE_ANALYTICS_REFRESH_TOKEN)
  ),
)

const YOUTUBE_RETENTION_CACHE_MS = 24 * 60 * 60 * 1000
const YOUTUBE_RETENTION_RETRY_MS = 2 * 60 * 60 * 1000
const YOUTUBE_RETENTION_REQUEST_LIMIT = 12

async function collectYouTube(env, fetchImpl, previous = null) {
  if (!hasYouTubeCredentials(env)) {
    return {
      platform: 'youtube',
      status: 'not_configured',
      reason: 'YouTube OAuth secrets are missing.',
      videos: [],
      uploads: [],
      uploadsRefreshed: false,
    }
  }
  const token = await googleAccessToken(env, fetchImpl)
  const headers = bearer(token)
  const channels = await fetchJson(fetchImpl, 'https://www.googleapis.com/youtube/v3/channels?part=snippet,contentDetails&mine=true', { headers })
  const channel = channels.items?.[0]
  const expectedChannelId = nullableString(env.YOUTUBE_CHANNEL_ID, 200)
  if (expectedChannelId && nullableString(channel?.id, 200) !== expectedChannelId) {
    throw publicError(
      'The authorized YouTube channel does not match YOUTUBE_CHANNEL_ID.',
      'The authorized YouTube channel does not match YOUTUBE_CHANNEL_ID.',
    )
  }
  const uploadsPlaylistId = channel?.contentDetails?.relatedPlaylists?.uploads
  if (!uploadsPlaylistId) throw publicError(
    'The authorized YouTube account has no uploads playlist.',
    'The authorized YouTube account has no uploads playlist.',
  )

  const ids = []
  let pageToken
  do {
    const query = new URLSearchParams({ part: 'contentDetails', playlistId: uploadsPlaylistId, maxResults: '50' })
    if (pageToken) query.set('pageToken', pageToken)
    const page = await fetchJson(fetchImpl, `https://www.googleapis.com/youtube/v3/playlistItems?${query}`, { headers })
    ids.push(...(page.items ?? []).map(item => item.contentDetails?.videoId).filter(Boolean))
    pageToken = page.nextPageToken
  } while (pageToken && ids.length < 500)

  const detailItems = []
  for (let index = 0; index < ids.length; index += 50) {
    const query = new URLSearchParams({
      part: 'snippet,statistics,status,contentDetails',
      id: ids.slice(index, index + 50).join(','),
      maxResults: '50',
    })
    const page = await fetchJson(fetchImpl, `https://www.googleapis.com/youtube/v3/videos?${query}`, { headers })
    detailItems.push(...(page.items ?? []))
  }

  const analyticsById = new Map()
  const analyticsEndDate = new Date().toISOString().slice(0, 10)
  const analyticsStartDate = new Date(Date.now() - (90 * 86400000)).toISOString().slice(0, 10)
  let analyticsAvailable = true
  try {
    const query = new URLSearchParams({
      ids: 'channel==MINE',
      startDate: analyticsStartDate,
      endDate: analyticsEndDate,
      dimensions: 'video',
      metrics: 'views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage,subscribersGained,likes,comments,shares',
      sort: '-views',
      maxResults: '200',
    })
    const analytics = await fetchJson(fetchImpl, `https://youtubeanalytics.googleapis.com/v2/reports?${query}`, { headers })
    const names = (analytics.columnHeaders ?? []).map(header => header.name)
    for (const row of analytics.rows ?? []) {
      analyticsById.set(String(row[0]), Object.fromEntries(names.map((name, index) => [name, row[index]])))
    }
  } catch {
    analyticsAvailable = false
  }

  const publicItems = detailItems.filter(item => item.status?.privacyStatus === 'public')
  const retentionById = new Map()
  const retentionCheckedAtById = new Map()
  const retentionCheckStatusById = new Map()
  const retentionCheckReasonById = new Map()
  const previousYouTubeVideos = new Map((previous?.videos ?? [])
    .filter(entry => entry?.platform === 'youtube' && entry?.platformVideoId)
    .map(entry => [String(entry.platformVideoId), entry]))
  const retentionErrors = []
  let pendingRetentionCount = 0
  let noDataRetentionCount = 0
  let deferredRetentionCount = 0

  const reusePreviousRetention = (id, previousEntry) => {
    if (Array.isArray(previousEntry?.retention)) retentionById.set(id, previousEntry.retention.slice(0, 100))
    const previousCheckedAt = normalizedDate(previousEntry?.retentionCheckedAt)
    if (previousCheckedAt) retentionCheckedAtById.set(id, previousCheckedAt)
    if (['available', 'pending', 'no_data', 'error'].includes(previousEntry?.retentionCheckStatus)) {
      retentionCheckStatusById.set(id, previousEntry.retentionCheckStatus)
    }
    if (['pending', 'no_data', 'error'].includes(previousEntry?.retentionCheckStatus) && previousEntry?.retentionCheckReason) {
      retentionCheckReasonById.set(id, sanitizedPublicReason(publicError('', previousEntry.retentionCheckReason)))
    }
  }

  // Audience retention requires a separate query for every video. Cache each
  // successful check for 24 hours. Empty or failed reports are retried after
  // two hours because YouTube can publish retention data later than Studio.
  // Process at most 12 overdue videos per run.
  // Never spend a burst of hundreds of Analytics requests on an hourly sync.
  if (analyticsAvailable) {
    const checkedAt = now()
    const checkedAtMs = Date.parse(checkedAt)
    const due = []
    for (const item of publicItems) {
      const id = String(item.id)
      const previousEntry = previousYouTubeVideos.get(id)
      const previousCheckedAt = normalizedDate(previousEntry?.retentionCheckedAt)
      const previousCheckedAtMs = previousCheckedAt ? Date.parse(previousCheckedAt) : Number.NaN
      const cacheAge = checkedAtMs - previousCheckedAtMs
      const previousStatus = previousEntry?.retentionCheckStatus
      const cacheTtl = previousStatus === 'available'
        ? YOUTUBE_RETENTION_CACHE_MS
        : YOUTUBE_RETENTION_RETRY_MS
      if (Number.isFinite(cacheAge) && cacheAge >= 0 && cacheAge < cacheTtl) {
        reusePreviousRetention(id, previousEntry)
        if (previousStatus === 'error') {
          retentionErrors.push(previousEntry.retentionCheckReason || 'Der letzte YouTube-Retention-Abruf ist fehlgeschlagen.')
        } else if (previousStatus === 'pending') {
          pendingRetentionCount += 1
        } else if (previousStatus === 'no_data') {
          noDataRetentionCount += 1
        }
      } else {
        due.push({ item, id, previousEntry, previousCheckedAtMs })
      }
    }

    due.sort((left, right) => {
      const leftNeverChecked = !Number.isFinite(left.previousCheckedAtMs)
      const rightNeverChecked = !Number.isFinite(right.previousCheckedAtMs)
      if (leftNeverChecked !== rightNeverChecked) return leftNeverChecked ? -1 : 1
      if (!leftNeverChecked) return left.previousCheckedAtMs - right.previousCheckedAtMs
      return String(right.item.snippet?.publishedAt ?? '').localeCompare(String(left.item.snippet?.publishedAt ?? ''))
    })

    const requested = due.slice(0, YOUTUBE_RETENTION_REQUEST_LIMIT)
    const deferred = due.slice(YOUTUBE_RETENTION_REQUEST_LIMIT)
    deferredRetentionCount = deferred.length
    for (const entry of deferred) reusePreviousRetention(entry.id, entry.previousEntry)

    for (let index = 0; index < requested.length; index += 4) {
      const batch = requested.slice(index, index + 4)
      const reports = await Promise.all(batch.map(entry => {
        const item = entry.item
        const publishedDate = normalizedDate(item.snippet?.publishedAt)?.slice(0, 10) ?? analyticsStartDate
        return collectYouTubeRetention(fetchImpl, headers, String(item.id), publishedDate, analyticsEndDate)
      }))
      reports.forEach((report, offset) => {
        const entry = batch[offset]
        if (report.status === 'available') {
          retentionById.set(entry.id, report.points)
          retentionCheckedAtById.set(entry.id, checkedAt)
          retentionCheckStatusById.set(entry.id, 'available')
          retentionCheckReasonById.delete(entry.id)
        } else if (['pending', 'no_data'].includes(report.status)) {
          if (report.status === 'pending') pendingRetentionCount += 1
          else noDataRetentionCount += 1
          reusePreviousRetention(entry.id, entry.previousEntry)
          retentionCheckedAtById.set(entry.id, checkedAt)
          retentionCheckStatusById.set(entry.id, report.status)
          retentionCheckReasonById.set(entry.id, report.reason)
        } else {
          retentionErrors.push(report.reason)
          reusePreviousRetention(entry.id, entry.previousEntry)
          retentionCheckedAtById.set(entry.id, checkedAt)
          retentionCheckStatusById.set(entry.id, 'error')
          retentionCheckReasonById.set(entry.id, report.reason)
        }
      })
    }
  }

  const videos = publicItems.map(item => {
    const analytics = analyticsById.get(String(item.id)) ?? {}
    return video({
      platform: 'youtube',
      id: item.id,
      title: item.snippet?.title,
      description: item.snippet?.description,
      publishedAt: item.snippet?.publishedAt,
      url: `https://www.youtube.com/watch?v=${item.id}`,
      thumbnailUrl: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.default?.url,
      status: item.status?.privacyStatus,
      durationSeconds: parseIsoDuration(item.contentDetails?.duration),
      retention: retentionById.get(String(item.id)) ?? [],
      retentionCheckedAt: retentionCheckedAtById.get(String(item.id)),
      retentionCheckStatus: retentionCheckStatusById.get(String(item.id)),
      retentionCheckReason: retentionCheckReasonById.get(String(item.id)),
      metrics: {
        views: analytics.views ?? item.statistics?.viewCount,
        likes: analytics.likes ?? item.statistics?.likeCount,
        comments: analytics.comments ?? item.statistics?.commentCount,
        shares: analytics.shares,
        watchTimeMinutes: analytics.estimatedMinutesWatched,
        averageViewDurationSeconds: analytics.averageViewDuration,
        averageViewPercentage: analytics.averageViewPercentage,
        followersGained: analytics.subscribersGained,
      },
    })
  })
  const uploadInventory = detailItems.map(youtubeUpload)
  const partialReasons = []
  if (!analyticsAvailable) partialReasons.push('YouTube Data API works; Analytics scope or report access is still missing.')
  if (retentionErrors.length > 0) {
    const detail = [...new Set(retentionErrors.filter(Boolean))].join(' ')
    partialReasons.push(`YouTube-Retention konnte fuer ${retentionErrors.length} ${retentionErrors.length === 1 ? 'Video' : 'Videos'} nicht aktualisiert werden.${detail ? ` ${detail}` : ''}`)
  }
  if (pendingRetentionCount > 0) {
    partialReasons.push(`YouTube-Retention fuer ${pendingRetentionCount} ${pendingRetentionCount === 1 ? 'Video steht noch aus und wird' : 'Videos stehen noch aus und werden'} nach zwei Stunden erneut abgefragt.`)
  }
  if (noDataRetentionCount > 0) {
    partialReasons.push(`YouTube lieferte fuer ${noDataRetentionCount} ${noDataRetentionCount === 1 ? 'Video keine verwertbare Retention' : 'Videos keine verwertbare Retention'}; erneuter Versuch in zwei Stunden.`)
  }
  if (deferredRetentionCount > 0) {
    partialReasons.push(`YouTube-Retention fuer ${deferredRetentionCount} ${deferredRetentionCount === 1 ? 'Video wird' : 'Videos werden'} in spaeteren Laeufen nachgeladen.`)
  }
  return {
    platform: 'youtube',
    status: partialReasons.length > 0 ? 'partial' : 'available',
    reason: partialReasons.length > 0 ? partialReasons.join(' ').slice(0, 300) : undefined,
    accountName: channel.snippet?.title ?? null,
    videos,
    uploads: uploadInventory,
    uploadsRefreshed: true,
  }
}

const graphUrl = (host, version, path, parameters = {}) => {
  const query = new URLSearchParams(parameters)
  return `${host}/${version}/${path}${query.size ? `?${query}` : ''}`
}

const facebookGraphUrl = (version, path, parameters = {}) => graphUrl('https://graph.facebook.com', version, path, parameters)
const instagramGraphUrl = (version, path, parameters = {}) => graphUrl('https://graph.instagram.com', version, path, parameters)

const facebookReelUrl = id => `https://www.facebook.com/reel/${encodeURIComponent(String(id))}`

const verifiedFacebookPermalink = (id, value) => {
  try {
    const candidate = new URL(String(value ?? ''))
    const hostname = candidate.hostname.toLowerCase()
    const isVideoPath = /^\/reel\/[^/]+/.test(candidate.pathname) || /\/videos\/[^/]+/.test(candidate.pathname) ||
      (candidate.pathname.startsWith('/watch') && candidate.searchParams.has('v'))
    if (candidate.protocol === 'https:' && (hostname === 'facebook.com' || hostname.endsWith('.facebook.com')) && isVideoPath) {
      return candidate.toString()
    }
  } catch {
    // Missing or malformed Graph permalinks use the stable public Reel route.
  }
  return facebookReelUrl(id)
}

const insightValues = payload => Object.fromEntries((payload.data ?? []).map(metric => [
  metric.name,
  metric.values?.at(-1)?.value ?? metric.total_value?.value ?? null,
]))

const insightDiagnostic = ({ platform, videoId, endpoint, metricNames, error, outcome = 'error' }) => {
  const failure = error?.apiFailure ?? {}
  return {
    platform,
    videoId: String(videoId),
    endpoint,
    metricNames: metricNames.map(String),
    outcome,
    httpStatus: numberOrNull(failure.httpStatus),
    code: failure.code ?? null,
    subcode: failure.subcode ?? null,
    type: failure.type ?? null,
    message: failure.message ?? sanitizedPublicReason(error),
  }
}

const appendUniqueDiagnostics = (target, additions) => {
  const known = new Set(target.map(entry => JSON.stringify(entry)))
  for (const entry of additions) {
    const key = JSON.stringify(entry)
    if (known.has(key)) continue
    known.add(key)
    target.push(entry)
  }
}

const isPermissionFailure = error => {
  const status = numberOrNull(error?.apiFailure?.httpStatus)
  const code = numberOrNull(error?.apiFailure?.code)
  return [401, 403].includes(status) || [10, 190, 200].includes(code)
}

const FACEBOOK_REEL_METRICS = [
  'blue_reels_play_count',
  'post_impressions_unique',
  'post_video_avg_time_watched',
  'post_video_view_time',
  'post_video_followers',
]
const FACEBOOK_CLASSIC_VIDEO_METRICS = [
  'total_video_views',
  'total_video_views_unique',
  'total_video_view_total_time',
  'total_video_avg_time_watched',
]

const hasNumericInsight = (insights, metricNames) => metricNames.some(name => numberOrNull(insights[name]) !== null)

async function readFacebookInsightSet(fetchImpl, version, videoId, headers, kind, metricNames) {
  const read = async names => insightValues(await fetchJson(fetchImpl, facebookGraphUrl(version, `${videoId}/video_insights`, {
    metric: names.join(','),
    period: 'lifetime',
  }), { headers }, 0))
  try {
    return { insights: await read(metricNames), diagnostics: [] }
  } catch (batchError) {
    const diagnostics = [insightDiagnostic({
      platform: 'facebook',
      videoId,
      endpoint: `video_insights:${kind}`,
      metricNames,
      error: batchError,
    })]
    const insights = {}
    if (isPermissionFailure(batchError)) return { insights, diagnostics }
    for (const metricName of metricNames) {
      try {
        Object.assign(insights, await read([metricName]))
      } catch (error) {
        diagnostics.push(insightDiagnostic({
          platform: 'facebook',
          videoId,
          endpoint: `video_insights:${kind}`,
          metricNames: [metricName],
          error,
        }))
      }
    }
    return { insights, diagnostics }
  }
}

async function facebookVideoInsights(fetchImpl, version, videoId, headers) {
  const diagnostics = []
  const reel = await readFacebookInsightSet(fetchImpl, version, videoId, headers, 'reel', FACEBOOK_REEL_METRICS)
  appendUniqueDiagnostics(diagnostics, reel.diagnostics)
  if (hasNumericInsight(reel.insights, FACEBOOK_REEL_METRICS)) {
    return { kind: 'reel', insights: reel.insights, reason: null, diagnostics }
  }
  diagnostics.push({
    platform: 'facebook',
    videoId: String(videoId),
    endpoint: 'video_insights:reel',
    metricNames: [...FACEBOOK_REEL_METRICS],
    outcome: 'no_data',
    httpStatus: null,
    code: null,
    subcode: null,
    type: null,
    message: 'Der Reel-Insights-Endpunkt lieferte keine nutzbaren Metriken.',
  })

  const classic = await readFacebookInsightSet(fetchImpl, version, videoId, headers, 'classic', FACEBOOK_CLASSIC_VIDEO_METRICS)
  appendUniqueDiagnostics(diagnostics, classic.diagnostics)
  if (hasNumericInsight(classic.insights, FACEBOOK_CLASSIC_VIDEO_METRICS)) {
    return { kind: 'classic', insights: classic.insights, reason: null, diagnostics }
  }
  diagnostics.push({
    platform: 'facebook',
    videoId: String(videoId),
    endpoint: 'video_insights:classic',
    metricNames: [...FACEBOOK_CLASSIC_VIDEO_METRICS],
    outcome: 'no_data',
    httpStatus: null,
    code: null,
    subcode: null,
    type: null,
    message: 'Der klassische Video-Insights-Endpunkt lieferte keine nutzbaren Metriken.',
  })
  const safeFailures = diagnostics.map(entry => entry.outcome === 'error' && entry.httpStatus
    ? `API request failed with HTTP ${entry.httpStatus}.`
    : entry.message).filter(Boolean)
  return {
    kind: null,
    insights: {},
    reason: [...new Set(safeFailures)].join(' ').slice(0, 240),
    diagnostics,
  }
}

const INSTAGRAM_BASE_METRICS = ['views', 'reach', 'saved', 'shares', 'total_interactions']
const INSTAGRAM_TIMING_METRIC_VARIANTS = {
  totalWatchTime: ['ig_reels_video_view_total_time', 'video_view_total_time'],
  averageWatchTime: ['ig_reels_avg_watch_time', 'average_watch_time'],
  skipRate: ['reels_skip_rate', 'skip_rate'],
}

async function readInstagramInsightMetrics(fetchImpl, version, mediaId, headers, metricNames, label) {
  const read = async names => insightValues(await fetchJson(fetchImpl, instagramGraphUrl(version, `${mediaId}/insights`, {
    metric: names.join(','),
  }), { headers }, 0))
  try {
    return { insights: await read(metricNames), diagnostics: [] }
  } catch (batchError) {
    const diagnostics = [insightDiagnostic({
      platform: 'instagram',
      videoId: mediaId,
      endpoint: `insights:${label}`,
      metricNames,
      error: batchError,
    })]
    const insights = {}
    if (metricNames.length === 1 || isPermissionFailure(batchError)) return { insights, diagnostics }
    for (const metricName of metricNames) {
      try {
        Object.assign(insights, await read([metricName]))
      } catch (error) {
        diagnostics.push(insightDiagnostic({
          platform: 'instagram',
          videoId: mediaId,
          endpoint: `insights:${label}`,
          metricNames: [metricName],
          error,
        }))
      }
    }
    return { insights, diagnostics }
  }
}

async function collectInstagramInsights(fetchImpl, version, mediaId, headers) {
  const diagnostics = []
  const base = await readInstagramInsightMetrics(fetchImpl, version, mediaId, headers, INSTAGRAM_BASE_METRICS, 'base')
  appendUniqueDiagnostics(diagnostics, base.diagnostics)
  const insights = { ...base.insights }
  const resolved = {}
  for (const [name, candidates] of Object.entries(INSTAGRAM_TIMING_METRIC_VARIANTS)) {
    for (const metricName of candidates) {
      const result = await readInstagramInsightMetrics(fetchImpl, version, mediaId, headers, [metricName], name)
      appendUniqueDiagnostics(diagnostics, result.diagnostics)
      const value = numberOrNull(result.insights[metricName])
      if (value === null) continue
      insights[metricName] = value
      resolved[name] = { metricName, value }
      break
    }
  }
  return { insights, resolved, diagnostics }
}

async function collectInstagram(env, fetchImpl) {
  const accessToken = env.META_INSTAGRAM_ACCESS_TOKEN || env.INSTAGRAM_ACCESS_TOKEN || env.META_ACCESS_TOKEN
  const accountId = env.META_INSTAGRAM_ACCOUNT_ID || env.INSTAGRAM_ACCOUNT_ID || env.INSTAGRAM_BUSINESS_ACCOUNT_ID
  if (!accessToken || !accountId) {
    return { platform: 'instagram', status: 'not_configured', reason: 'Instagram access token or account ID is missing.', videos: [] }
  }
  const version = env.META_GRAPH_API_VERSION || 'v24.0'
  const headers = bearer(accessToken)
  const account = await fetchJson(fetchImpl, instagramGraphUrl(version, accountId, { fields: 'username,name' }), { headers })
  const mediaPage = await fetchJson(fetchImpl, instagramGraphUrl(version, `${accountId}/media`, {
    fields: 'id,caption,media_type,media_product_type,permalink,timestamp,thumbnail_url,like_count,comments_count',
    limit: '100',
  }), { headers })
  const videos = []
  const diagnostics = []
  let missingBaseInsightCount = 0
  let missingTimingInsightCount = 0
  for (const item of mediaPage.data ?? []) {
    if (!['VIDEO', 'REELS'].includes(item.media_type) && item.media_product_type !== 'REELS') continue
    const insightResult = await collectInstagramInsights(fetchImpl, version, item.id, headers)
    appendUniqueDiagnostics(diagnostics, insightResult.diagnostics)
    const insights = insightResult.insights
    if (!hasNumericInsight(insights, INSTAGRAM_BASE_METRICS)) missingBaseInsightCount += 1
    if (!insightResult.resolved.totalWatchTime && !insightResult.resolved.averageWatchTime) {
      missingTimingInsightCount += 1
    }
    const totalWatchTime = insightResult.resolved.totalWatchTime?.value ?? null
    const averageWatchTime = insightResult.resolved.averageWatchTime?.value ?? null
    const skipRate = insightResult.resolved.skipRate?.value ?? null
    videos.push(video({
      platform: 'instagram',
      id: item.id,
      title: item.caption?.split('\n')[0],
      description: item.caption,
      publishedAt: item.timestamp,
      url: item.permalink,
      thumbnailUrl: item.thumbnail_url,
      status: 'published',
      metrics: {
        views: insights.views,
        reach: insights.reach,
        likes: item.like_count,
        comments: item.comments_count,
        shares: insights.shares,
        saves: insights.saved,
        watchTimeMinutes: totalWatchTime === null ? null : totalWatchTime / 60000,
        averageViewDurationSeconds: averageWatchTime === null ? null : averageWatchTime / 1000,
        skipRate,
      },
    }))
  }
  const reasons = []
  if (missingBaseInsightCount > 0) {
    reasons.push(`Instagram-Basis-Insights fehlen fuer ${missingBaseInsightCount} ${missingBaseInsightCount === 1 ? 'Video' : 'Videos'}.`)
  }
  if (missingTimingInsightCount > 0) {
    reasons.push(`Instagram-Watchtime-Metriken fehlen fuer ${missingTimingInsightCount} ${missingTimingInsightCount === 1 ? 'Video' : 'Videos'}.`)
  }
  return {
    platform: 'instagram',
    status: reasons.length > 0 ? 'partial' : 'available',
    reason: reasons.length > 0 ? reasons.join(' ').slice(0, 300) : undefined,
    accountName: account.username ?? account.name ?? null,
    videos,
    diagnostics: diagnostics.slice(0, 100),
  }
}

async function collectFacebook(env, fetchImpl) {
  const accessToken = env.META_FACEBOOK_PAGE_ACCESS_TOKEN || env.FACEBOOK_PAGE_ACCESS_TOKEN || env.FACEBOOK_ACCESS_TOKEN || env.META_ACCESS_TOKEN
  const pageId = env.META_FACEBOOK_PAGE_ID || env.FACEBOOK_PAGE_ID || env.META_PAGE_ID
  if (!accessToken || !pageId) {
    return { platform: 'facebook', status: 'not_configured', reason: 'Facebook Page access token or Page ID is missing.', videos: [] }
  }
  const version = env.META_GRAPH_API_VERSION || 'v24.0'
  const headers = bearer(accessToken)
  const account = await fetchJson(fetchImpl, facebookGraphUrl(version, pageId, { fields: 'name' }), { headers })
  const mediaPage = await fetchJson(fetchImpl, facebookGraphUrl(version, `${pageId}/videos`, {
    fields: 'id,title,description,created_time,permalink_url,published,status,length,likes.limit(0).summary(true),comments.limit(0).summary(true)',
    limit: '100',
  }), { headers })
  const videos = []
  const insightFailures = []
  const diagnostics = []
  for (const item of mediaPage.data ?? []) {
    const rawStatus = String(item.status?.video_status ?? '').toLowerCase()
    if (item.published === false || ['processing', 'error', 'blocked', 'copyright_blocked'].includes(rawStatus)) continue
    const insightResult = await facebookVideoInsights(fetchImpl, version, item.id, headers)
    const insights = insightResult.insights
    appendUniqueDiagnostics(diagnostics, insightResult.diagnostics ?? [])
    if (!insightResult.kind) insightFailures.push(insightResult.reason)
    const isReel = insightResult.kind === 'reel'
    const totalTime = numberOrNull(isReel ? insights.post_video_view_time : insights.total_video_view_total_time)
    const averageTime = numberOrNull(isReel ? insights.post_video_avg_time_watched : insights.total_video_avg_time_watched)
    videos.push(video({
      platform: 'facebook',
      id: item.id,
      title: item.title,
      description: item.description,
      publishedAt: item.created_time,
      url: verifiedFacebookPermalink(item.id, item.permalink_url),
      status: 'published',
      durationSeconds: item.length,
      metrics: {
        views: isReel ? insights.blue_reels_play_count : insights.total_video_views,
        reach: isReel ? insights.post_impressions_unique : insights.total_video_views_unique,
        likes: item.likes?.summary?.total_count,
        comments: item.comments?.summary?.total_count,
        watchTimeMinutes: totalTime === null ? null : totalTime / 60000,
        averageViewDurationSeconds: averageTime === null ? null : averageTime / 1000,
        followersGained: isReel ? insights.post_video_followers : null,
      },
    }))
  }
  const insightFailureCount = insightFailures.length
  const reason = insightFailureCount > 0
    ? `Facebook-Basisdaten geladen; Video-Insights fehlen fuer ${insightFailureCount} ${insightFailureCount === 1 ? 'Video' : 'Videos'}. Erweiterte Insights erfordern read_insights und pages_manage_engagement. ${[...new Set(insightFailures)].join(' ')}`.slice(0, 300)
    : undefined
  return {
    platform: 'facebook',
    status: insightFailureCount > 0 ? 'partial' : 'available',
    reason,
    accountName: account.name ?? null,
    videos,
    diagnostics: diagnostics.slice(0, 100),
  }
}

async function tikTokAccessToken(env, fetchImpl) {
  if (env.TIKTOK_ACCESS_TOKEN) return { accessToken: env.TIKTOK_ACCESS_TOKEN, refreshTokenRotated: false }
  if (!env.TIKTOK_CLIENT_KEY || !env.TIKTOK_CLIENT_SECRET || !env.TIKTOK_REFRESH_TOKEN) return null
  const response = await fetchJson(fetchImpl, 'https://open.tiktokapis.com/v2/oauth/token/', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_key: env.TIKTOK_CLIENT_KEY,
      client_secret: env.TIKTOK_CLIENT_SECRET,
      grant_type: 'refresh_token',
      refresh_token: env.TIKTOK_REFRESH_TOKEN,
    }),
  }, 0)
  if (!response.access_token) throw publicError('TikTok returned no access token.', 'TikTok returned no access token.')
  return {
    accessToken: response.access_token,
    refreshTokenRotated: Boolean(response.refresh_token && response.refresh_token !== env.TIKTOK_REFRESH_TOKEN),
  }
}

async function collectTikTok(env, fetchImpl) {
  const token = await tikTokAccessToken(env, fetchImpl)
  if (!token) {
    return {
      platform: 'tiktok',
      status: 'not_configured',
      reason: 'TikTok access token or refresh credentials are missing.',
      videos: [],
    }
  }
  const headers = bearer(token.accessToken)
  const videos = []
  let cursor
  do {
    const query = new URLSearchParams({
      fields: 'id,create_time,cover_image_url,share_url,video_description,duration,height,width,title,like_count,comment_count,share_count,view_count',
    })
    const body = { max_count: 20 }
    if (cursor !== undefined && cursor !== null) body.cursor = cursor
    const page = await fetchJson(fetchImpl, `https://open.tiktokapis.com/v2/video/list/?${query}`, {
      method: 'POST',
      headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (page.error?.code && page.error.code !== 'ok') {
      const code = String(page.error.code).replace(/[^a-z0-9_.-]/gi, '').slice(0, 80) || 'unknown_error'
      throw publicError(`TikTok API: ${page.error.code}`, `TikTok API request failed (${code}).`)
    }
    videos.push(...(page.data?.videos ?? []).map(item => video({
      platform: 'tiktok',
      id: item.id,
      title: item.title,
      description: item.video_description,
      publishedAt: item.create_time ? new Date(Number(item.create_time) * 1000).toISOString() : null,
      url: item.share_url,
      thumbnailUrl: item.cover_image_url,
      status: 'published',
      durationSeconds: item.duration,
      metrics: {
        views: item.view_count,
        likes: item.like_count,
        comments: item.comment_count,
        shares: item.share_count,
      },
    })))
    cursor = page.data?.has_more ? page.data.cursor : null
  } while (cursor && videos.length < 500)
  return {
    platform: 'tiktok',
    status: token.refreshTokenRotated ? 'partial' : 'available',
    reason: token.refreshTokenRotated
      ? 'TikTok rotated the refresh token; update TIKTOK_REFRESH_TOKEN before the next refresh.'
      : undefined,
    accountName: null,
    videos,
  }
}

async function collectAnalyticsFeed(env, fetchImpl) {
  if (!env.SOCIAL_ANALYTICS_FEED_URL) return null
  const payload = await fetchJson(fetchImpl, env.SOCIAL_ANALYTICS_FEED_URL, {}, 1)
  if (
    payload?.schemaVersion !== 1 ||
    !payload.platforms ||
    !Array.isArray(payload.videos) ||
    (payload.uploads !== undefined && !Array.isArray(payload.uploads))
  ) {
    throw publicError('The social analytics feed is invalid.', 'The social analytics feed is invalid.')
  }
  const uploadsProvided = Array.isArray(payload.uploads)
  if (uploadsProvided && !payload.uploads.every(entry => {
    if (!entry || typeof entry !== 'object') return false
    if (!PLATFORM_NAMES.includes(entry.platform)) return false
    if (typeof entry.platformVideoId !== 'string' || !entry.platformVideoId.trim() || entry.platformVideoId.length > 200) return false
    if (!payload.platforms[entry.platform] || typeof payload.platforms[entry.platform] !== 'object') return false
    for (const [name, maximumLength] of [
      ['contentId', 200],
      ['title', 240],
      ['description', 500],
      ['url', 500],
      ['thumbnailUrl', 500],
      ['status', 50],
      ['privacyStatus', 50],
      ['uploadStatus', 50],
    ]) {
      if (entry[name] !== undefined && entry[name] !== null && (typeof entry[name] !== 'string' || entry[name].length > maximumLength)) return false
    }
    for (const name of ['uploadedAt', 'publishedAt', 'scheduledAt']) {
      if (entry[name] !== undefined && entry[name] !== null && normalizedDate(entry[name]) === null) return false
    }
    if (entry.durationSeconds !== undefined && entry.durationSeconds !== null) {
      const duration = numberOrNull(entry.durationSeconds)
      if (duration === null || duration < 0) return false
    }
    return true
  })) {
    throw publicError('The social analytics feed contains invalid upload inventory.', 'The social analytics feed is invalid.')
  }
  const generatedAt = typeof payload.generatedAt === 'string' ? payload.generatedAt : now()
  return Object.fromEntries(PLATFORM_NAMES.flatMap(platform => {
    const state = payload.platforms[platform]
    if (!state || typeof state !== 'object') return []
    const stateStatus = ['available', 'partial', 'error', 'not_configured'].includes(state.status) ? state.status : 'error'
    const videos = payload.videos
      .filter(entry => entry?.platform === platform && entry?.platformVideoId)
      .map(entry => video({
        platform,
        id: entry.platformVideoId,
        contentId: entry.contentId,
        title: entry.title,
        description: entry.description,
        publishedAt: entry.publishedAt,
        url: entry.url,
        thumbnailUrl: entry.thumbnailUrl,
        status: entry.status,
        durationSeconds: entry.durationSeconds,
        metrics: entry.metrics,
        retention: entry.retention,
        retentionCheckedAt: entry.retentionCheckedAt,
        retentionCheckStatus: entry.retentionCheckStatus,
        retentionCheckReason: entry.retentionCheckReason,
      }))
      .filter(isPublishedVideo)
    const uploads = uploadsProvided
      ? payload.uploads
        .filter(entry => entry.platform === platform)
        .map(entry => upload({
          platform,
          id: entry.platformVideoId,
          contentId: entry.contentId,
          title: entry.title,
          description: entry.description,
          uploadedAt: entry.uploadedAt,
          publishedAt: entry.publishedAt,
          scheduledAt: entry.scheduledAt,
          url: entry.url,
          thumbnailUrl: entry.thumbnailUrl,
          status: entry.status,
          privacyStatus: entry.privacyStatus,
          uploadStatus: entry.uploadStatus,
          durationSeconds: entry.durationSeconds,
        }))
      : []
    return [[platform, {
      platform,
      status: stateStatus,
      reason: state.reason,
      accountName: state.accountName ?? null,
      diagnostics: Array.isArray(state.diagnostics) ? state.diagnostics.slice(0, 100) : [],
      videos,
      uploads,
      uploadsRefreshed: uploadsProvided && ['available', 'partial'].includes(stateStatus),
      startedAt: generatedAt,
      completedAt: state.completedAt ?? generatedAt,
    }]]
  }))
}

const collectSafely = async (platform, collector) => {
  const startedAt = now()
  try {
    const result = await collector()
    return { ...result, platform, startedAt, completedAt: now() }
  } catch (error) {
    return { platform, status: 'error', reason: sanitizedPublicReason(error), videos: [], startedAt, completedAt: now() }
  }
}

const isPublishedVideo = entry => {
  const status = String(entry?.status ?? '').toLowerCase()
  return entry?.platform === 'youtube'
    ? status === 'public'
    : status === 'published'
}

export function mergeSocialHistory(previous, current, capturedAt = now()) {
  const preservePlatforms = new Set(current.preservePlatforms ?? [])
  const hasRefreshMetadata = Array.isArray(current.refreshedPlatforms)
  const refreshedPlatforms = new Set(current.refreshedPlatforms ?? [])
  const hasUploadRefreshMetadata = Array.isArray(current.refreshedUploadPlatforms)
  const refreshedUploadPlatforms = new Set(current.refreshedUploadPlatforms ?? [])
  const previousByKey = new Map((previous?.videos ?? [])
    .filter(isPublishedVideo)
    .map(entry => [`${entry.platform}:${entry.platformVideoId}`, entry]))
  const videosByKey = new Map()
  for (const entry of previous?.videos ?? []) {
    if (!isPublishedVideo(entry)) continue
    if (!hasRefreshMetadata || preservePlatforms.has(entry.platform) || !refreshedPlatforms.has(entry.platform)) {
      videosByKey.set(`${entry.platform}:${entry.platformVideoId}`, entry)
    }
  }
  for (const entry of current.videos) {
    if (!isPublishedVideo(entry)) continue
    const key = `${entry.platform}:${entry.platformVideoId}`
    const previousEntry = previousByKey.get(key)
    const platformIsPartial = current.platforms?.[entry.platform]?.status === 'partial'
    const mergedEntry = platformIsPartial && previousEntry
      ? {
          ...entry,
          metrics: preserveKnownMetrics(previousEntry.metrics, entry.metrics),
        }
      : { ...entry }
    if ((entry.retention?.length ?? 0) === 0 && (previousEntry?.retention?.length ?? 0) > 0) {
      mergedEntry.retention = previousEntry.retention
    }
    if (!mergedEntry.retentionCheckedAt && previousEntry?.retentionCheckedAt) {
      mergedEntry.retentionCheckedAt = previousEntry.retentionCheckedAt
    }
    if (!mergedEntry.retentionCheckStatus && previousEntry?.retentionCheckStatus) {
      mergedEntry.retentionCheckStatus = previousEntry.retentionCheckStatus
      if (['pending', 'no_data', 'error'].includes(previousEntry.retentionCheckStatus) && previousEntry.retentionCheckReason) {
        mergedEntry.retentionCheckReason = previousEntry.retentionCheckReason
      }
    }
    videosByKey.set(key, mergedEntry)
  }
  const videos = [...videosByKey.values()]
  const liveVideoKeys = new Set(videos.map(entry => `${entry.platform}:${entry.platformVideoId}`))

  const uploadsByKey = new Map()
  for (const entry of previous?.uploads ?? []) {
    if (!entry?.platform || !entry?.platformVideoId) continue
    if (!hasUploadRefreshMetadata || preservePlatforms.has(entry.platform) || !refreshedUploadPlatforms.has(entry.platform)) {
      uploadsByKey.set(`${entry.platform}:${entry.platformVideoId}`, entry)
    }
  }
  for (const entry of current.uploads ?? []) {
    if (entry?.platform && entry?.platformVideoId) uploadsByKey.set(`${entry.platform}:${entry.platformVideoId}`, entry)
  }
  const uploads = [...uploadsByKey.values()]

  const snapshotByKey = new Map()
  const cutoff = Date.now() - (90 * 86400000)
  for (const snapshot of previous?.snapshots ?? []) {
    if (new Date(snapshot.capturedAt).valueOf() >= cutoff && liveVideoKeys.has(`${snapshot.platform}:${snapshot.platformVideoId}`)) {
      snapshotByKey.set(`${snapshot.platform}:${snapshot.platformVideoId}:${snapshot.capturedAt}`, snapshot)
    }
  }
  for (const entry of current.videos) {
    if (!isPublishedVideo(entry)) continue
    const mergedEntry = videosByKey.get(`${entry.platform}:${entry.platformVideoId}`)
    const snapshot = { platform: entry.platform, platformVideoId: entry.platformVideoId, capturedAt, metrics: mergedEntry?.metrics ?? entry.metrics }
    snapshotByKey.set(`${snapshot.platform}:${snapshot.platformVideoId}:${snapshot.capturedAt}`, snapshot)
  }

  return {
    schemaVersion: 1,
    syncedAt: capturedAt,
    platforms: current.platforms,
    totals: summarizeMetrics(videos),
    videos: videos.sort((left, right) => String(right.publishedAt ?? '').localeCompare(String(left.publishedAt ?? ''))),
    uploads: uploads.sort((left, right) => {
      const rightDate = right.scheduledAt ?? right.uploadedAt ?? right.publishedAt ?? ''
      const leftDate = left.scheduledAt ?? left.uploadedAt ?? left.publishedAt ?? ''
      return String(rightDate).localeCompare(String(leftDate))
    }),
    snapshots: [...snapshotByKey.values()].sort((left, right) => left.capturedAt.localeCompare(right.capturedAt)),
  }
}

export async function collectSocialPlatforms({ env = process.env, fetchImpl = fetch, previous = null } = {}) {
  let feedResults = null
  try {
    feedResults = await collectAnalyticsFeed(env, fetchImpl)
  } catch {
    // Direct credentials remain a safe fallback when the cloud feed is unavailable.
  }
  const collectors = {
    youtube: () => collectYouTube(env, fetchImpl, previous),
    instagram: () => collectInstagram(env, fetchImpl),
    facebook: () => collectFacebook(env, fetchImpl),
    tiktok: () => collectTikTok(env, fetchImpl),
  }
  const results = await Promise.all(PLATFORM_NAMES.map(async platform => {
    const feedResult = feedResults?.[platform]
    if (platform === 'youtube' && hasYouTubeCredentials(env)) {
      return collectSafely(platform, collectors[platform])
    }
    if (feedResult && feedResult.status !== 'not_configured') return feedResult
    return collectSafely(platform, collectors[platform])
  }))
  const videos = results.flatMap(result => result.videos)
  const uploads = results.flatMap(result => result.uploads ?? [])
  const preservePlatforms = []
  const refreshedPlatforms = []
  const refreshedUploadPlatforms = []
  const current = {
    platforms: Object.fromEntries(PLATFORM_NAMES.map(name => {
      const result = results.find(entry => entry.platform === name)
      const previousState = previous?.platforms?.[name]
      refreshedPlatforms.push(name)
      if (result?.uploadsRefreshed) refreshedUploadPlatforms.push(name)
      if (result?.status === 'error' && ['available', 'partial'].includes(previousState?.status)) {
        preservePlatforms.push(name)
        const previousVideoCount = (previous?.videos ?? []).filter(entry => entry.platform === name && isPublishedVideo(entry)).length
        const previousUploadCount = (previous?.uploads ?? []).filter(entry => entry.platform === name).length
        return [name, {
          ...previousState,
          reason: `Letzte Aktualisierung fehlgeschlagen; bekannte Daten bleiben erhalten. ${result.reason}`.slice(0, 300),
          videoCount: previousVideoCount,
          uploadCount: previousState.uploadCount ?? Math.max(previousUploadCount, previousVideoCount),
          startedAt: result.startedAt ?? previousState.startedAt ?? null,
          completedAt: result.completedAt ?? previousState.completedAt ?? null,
          diagnostics: Array.isArray(result?.diagnostics)
            ? result.diagnostics.slice(0, 100)
            : (Array.isArray(previousState?.diagnostics) ? previousState.diagnostics.slice(0, 100) : []),
        }]
      }
      const publishedVideoCount = result?.videos.filter(isPublishedVideo).length ?? 0
      const knownUploadCount = result?.uploadsRefreshed
        ? (result.uploads?.length ?? 0)
        : (previousState?.uploadCount ?? publishedVideoCount)
      return [name, {
        status: result?.status ?? 'error',
        reason: result?.reason,
        accountName: result?.accountName ?? null,
        videoCount: publishedVideoCount,
        uploadCount: Math.max(publishedVideoCount, knownUploadCount),
        startedAt: result?.startedAt ?? null,
        completedAt: result?.completedAt ?? null,
        diagnostics: Array.isArray(result?.diagnostics) ? result.diagnostics.slice(0, 100) : [],
      }]
    })),
    videos,
    uploads,
    preservePlatforms,
    refreshedPlatforms,
    refreshedUploadPlatforms,
  }
  return mergeSocialHistory(previous, current)
}
