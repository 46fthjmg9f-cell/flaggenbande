import assert from 'node:assert/strict'
import test from 'node:test'
import { collectSocialPlatforms, mergeSocialHistory } from '../scripts/social-platforms.mjs'

const jsonResponse = (payload, status = 200) => new Response(JSON.stringify(payload), {
  status,
  headers: { 'content-type': 'application/json' },
})

const metrics = overrides => ({
  views: null,
  reach: null,
  likes: null,
  comments: null,
  shares: null,
  saves: null,
  watchTimeMinutes: null,
  averageViewDurationSeconds: null,
  averageViewPercentage: null,
  followersGained: null,
  ...overrides,
})

const socialVideo = (platform, id, overrides = {}) => ({
  platform,
  platformVideoId: id,
  title: `Video ${id}`,
  description: '',
  publishedAt: '2026-07-20T10:00:00Z',
  url: `https://example.test/${id}`,
  thumbnailUrl: null,
  status: platform === 'youtube' ? 'public' : 'published',
  durationSeconds: 30,
  metrics: metrics({ views: 10 }),
  ...overrides,
})

const youtubeFetch = ({
  channelId = 'flaggenbande-channel-id',
  privacyById = { public: 'public' },
  scheduledAtById = {},
  uploadStatusById = {},
  analytics = true,
} = {}) => async url => {
  const value = String(url)
  if (value.includes('/youtube/v3/channels')) {
    return jsonResponse({
      items: [{
        id: channelId,
        snippet: { title: 'Flaggenbande' },
        contentDetails: { relatedPlaylists: { uploads: 'uploads-1' } },
      }],
    })
  }
  if (value.includes('/youtube/v3/playlistItems')) {
    return jsonResponse({
      items: Object.keys(privacyById).map(videoId => ({ contentDetails: { videoId } })),
    })
  }
  if (value.includes('/youtube/v3/videos')) {
    return jsonResponse({
      items: Object.entries(privacyById).map(([id, privacyStatus], index) => ({
        id,
        snippet: {
          title: `Flag quiz ${id}`,
          description: 'Quiz description',
          publishedAt: `2026-07-20T${String(index % 24).padStart(2, '0')}:00:00Z`,
          thumbnails: { default: { url: `https://img.test/${id}.jpg` } },
        },
        status: {
          privacyStatus,
          publishAt: scheduledAtById[id],
          uploadStatus: uploadStatusById[id] ?? 'processed',
        },
        contentDetails: { duration: 'PT35S' },
        statistics: { viewCount: String(100 + index), likeCount: '12', commentCount: '3' },
      })),
    })
  }
  if (value.includes('youtubeanalytics.googleapis.com')) {
    if (!analytics) return jsonResponse({ error: { message: 'not available' } }, 403)
    return jsonResponse({
      columnHeaders: [
        { name: 'video' },
        { name: 'views' },
        { name: 'estimatedMinutesWatched' },
        { name: 'averageViewDuration' },
        { name: 'averageViewPercentage' },
      ],
      rows: Object.keys(privacyById).map((id, index) => [id, 200 + index, 60, 18, 52]),
    })
  }
  throw new Error(`Unexpected request: ${value}`)
}

test('unconfigured social collectors do not call the network or invent metrics', async () => {
  const social = await collectSocialPlatforms({
    env: {},
    fetchImpl: async () => { throw new Error('Network must not be called.') },
  })

  assert.deepEqual(Object.values(social.platforms).map(platform => platform.status), [
    'not_configured',
    'not_configured',
    'not_configured',
    'not_configured',
  ])
  assert.equal(social.videos.length, 0)
  assert.equal(social.uploads.length, 0)
  assert.equal(social.totals.views, 0)
  assert.equal(social.totals.averageViewDurationSeconds, null)
  assert.equal(social.totals.averageViewPercentage, null)
})

test('YouTube keeps all uploads in inventory but exports only public videos to analytics', async () => {
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-test-token' },
    fetchImpl: youtubeFetch({
      privacyById: {
        publicVideo: 'public',
        privateVideo: 'private',
        scheduledVideo: 'private',
        unlistedVideo: 'unlisted',
      },
      scheduledAtById: { scheduledVideo: '2026-07-22T09:00:00Z' },
    }),
  })

  assert.equal(social.platforms.youtube.status, 'available')
  assert.equal(social.platforms.youtube.videoCount, 1)
  assert.equal(social.platforms.youtube.uploadCount, 4)
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['publicVideo'])
  assert.equal(social.videos[0].status, 'public')
  assert.equal(social.videos[0].metrics.views, 200)
  assert.deepEqual(social.uploads.map(entry => entry.status).sort(), ['private', 'public', 'scheduled', 'unlisted'])
  const nonPublicUploads = social.uploads.filter(entry => entry.status !== 'public')
  assert.ok(nonPublicUploads.every(entry => entry.platformVideoId.startsWith('non-public-')))
  assert.ok(nonPublicUploads.every(entry => entry.title === 'Nichtöffentlicher YouTube-Upload'))
  assert.ok(nonPublicUploads.every(entry => entry.description === '' && entry.url === null && entry.thumbnailUrl === null))
  assert.ok(nonPublicUploads.every(entry => !['privateVideo', 'scheduledVideo', 'unlistedVideo'].includes(entry.platformVideoId)))
  assert.equal('metrics' in social.uploads[0], false)
  assert.equal(social.uploads.find(entry => entry.status === 'scheduled').scheduledAt, null)
  assert.equal(social.totals.views, 200)
  assert.equal(social.totals.averageViewDurationSeconds, null)
  assert.equal(social.snapshots.length, 1)
})

test('YouTube exports the configured channel when YOUTUBE_CHANNEL_ID matches', async () => {
  const social = await collectSocialPlatforms({
    env: {
      YOUTUBE_ACCESS_TOKEN: 'youtube-test-token',
      YOUTUBE_CHANNEL_ID: 'flaggenbande-channel-id',
    },
    fetchImpl: youtubeFetch(),
  })

  assert.equal(social.platforms.youtube.status, 'available')
  assert.equal(social.platforms.youtube.accountName, 'Flaggenbande')
  assert.equal(social.platforms.youtube.videoCount, 1)
})

test('YouTube fails closed before reading uploads when YOUTUBE_CHANNEL_ID mismatches', async () => {
  const calls = []
  const baseFetch = youtubeFetch({ channelId: 'different-channel-id' })
  const social = await collectSocialPlatforms({
    env: {
      YOUTUBE_ACCESS_TOKEN: 'youtube-test-token',
      YOUTUBE_CHANNEL_ID: 'flaggenbande-channel-id',
    },
    fetchImpl: async (...args) => {
      calls.push(String(args[0]))
      return baseFetch(...args)
    },
  })

  assert.equal(social.platforms.youtube.status, 'error')
  assert.equal(social.platforms.youtube.reason, 'The authorized YouTube channel does not match YOUTUBE_CHANNEL_ID.')
  assert.equal(social.platforms.youtube.videoCount, 0)
  assert.equal(social.platforms.youtube.uploadCount, 0)
  assert.deepEqual(social.videos, [])
  assert.deepEqual(social.uploads, [])
  assert.equal(calls.some(value => value.includes('/youtube/v3/playlistItems')), false)
  assert.equal(calls.some(value => value.includes('/youtube/v3/videos')), false)
})

test('non-retryable API responses are not requested repeatedly', async () => {
  let calls = 0
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-test-token' },
    fetchImpl: async () => {
      calls += 1
      return jsonResponse({ error: { message: 'invalid credentials' } }, 401)
    },
  })

  assert.equal(calls, 1)
  assert.equal(social.platforms.youtube.status, 'error')
  assert.equal(social.platforms.youtube.reason, 'API request failed with HTTP 401.')
})

test('a successful refresh removes a formerly public YouTube video after it becomes private', async () => {
  const previousVideo = socialVideo('youtube', 'old-public')
  const previous = {
    platforms: {
      youtube: { status: 'available', accountName: 'Flaggenbande', videoCount: 1 },
    },
    videos: [previousVideo],
    snapshots: [{
      platform: 'youtube',
      platformVideoId: 'old-public',
      capturedAt: new Date().toISOString(),
      metrics: previousVideo.metrics,
    }],
  }
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-test-token' },
    previous,
    fetchImpl: youtubeFetch({ privacyById: { 'old-public': 'private' } }),
  })

  assert.equal(social.platforms.youtube.status, 'available')
  assert.equal(social.platforms.youtube.videoCount, 0)
  assert.equal(social.platforms.youtube.uploadCount, 1)
  assert.equal(social.videos.length, 0)
  assert.equal(social.uploads[0].status, 'private')
  assert.equal(social.snapshots.length, 0)
})

test('TikTok video/list uses POST with a JSON body and forwards the numeric cursor', async () => {
  const calls = []
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url: String(url), options })
    const body = JSON.parse(options.body)
    if (calls.length === 1) {
      assert.deepEqual(body, { max_count: 20 })
      return jsonResponse({
        data: {
          videos: [{ id: 'tt-1', title: 'First', share_url: 'https://tiktok.test/tt-1', create_time: 1, view_count: 7 }],
          has_more: true,
          cursor: 1720000000123,
        },
        error: { code: 'ok' },
      })
    }
    assert.deepEqual(body, { max_count: 20, cursor: 1720000000123 })
    return jsonResponse({
      data: {
        videos: [{ id: 'tt-2', title: 'Second', share_url: 'https://tiktok.test/tt-2', create_time: 2, view_count: 11 }],
        has_more: false,
      },
      error: { code: 'ok' },
    })
  }

  const social = await collectSocialPlatforms({
    env: { TIKTOK_ACCESS_TOKEN: 'tiktok-test-token' },
    fetchImpl,
  })

  assert.equal(calls.length, 2)
  for (const call of calls) {
    assert.equal(call.options.method, 'POST')
    assert.equal(call.options.headers['content-type'], 'application/json')
    assert.match(call.url, /^https:\/\/open\.tiktokapis\.com\/v2\/video\/list\/\?fields=/)
    assert.equal(new URL(call.url).searchParams.has('max_count'), false)
  }
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['tt-2', 'tt-1'])
  assert.equal(social.totals.views, 18)
})

test('Meta collectors keep Instagram Login and Facebook Page credentials on separate API hosts', async () => {
  const calls = []
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    calls.push({ value, authorization: options.headers?.authorization })
    if (value.includes('/media')) return jsonResponse({ data: [] })
    if (value.includes('graph.instagram.com')) return jsonResponse({ username: 'flaggenbande' })
    if (value.includes('graph.facebook.com')) return jsonResponse({ name: 'Flaggenbande' })
    throw new Error(`Unexpected request: ${value}`)
  }

  const social = await collectSocialPlatforms({
    env: {
      META_ACCESS_TOKEN: 'instagram-login-token',
      META_INSTAGRAM_ACCOUNT_ID: 'ig-account',
      META_FACEBOOK_PAGE_ACCESS_TOKEN: 'facebook-page-token',
      META_FACEBOOK_PAGE_ID: 'fb-page',
    },
    fetchImpl,
  })

  assert.equal(social.platforms.instagram.status, 'available')
  assert.equal(social.platforms.facebook.status, 'available')
  const instagramCalls = calls.filter(call => call.value.includes('graph.instagram.com'))
  const facebookCalls = calls.filter(call => call.value.includes('graph.facebook.com'))
  assert.ok(instagramCalls.length >= 2)
  assert.ok(facebookCalls.length >= 2)
  assert.ok(instagramCalls.every(call => call.authorization === 'Bearer instagram-login-token'))
  assert.ok(facebookCalls.every(call => call.authorization === 'Bearer facebook-page-token'))
})

test('Facebook keeps basic video data, reports missing insights and builds a working Reel fallback URL', async () => {
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    assert.equal(options.headers?.authorization, 'Bearer facebook-page-token')
    if (value.includes('/fb-page/videos')) {
      return jsonResponse({
        data: [{
          id: '1594633352224956',
          title: 'Flag quiz',
          description: 'Quiz description',
          created_time: '2026-07-21T13:17:29Z',
          permalink_url: 'https://www.facebook.com/1594633352224956',
          published: true,
          status: { video_status: 'ready' },
          length: 66.5,
          likes: { summary: { total_count: 7 } },
          comments: { summary: { total_count: 2 } },
        }],
      })
    }
    if (value.includes('/1594633352224956/video_insights')) {
      return jsonResponse({ error: { message: 'access_token=must-not-leak' } }, 403)
    }
    if (value.includes('/fb-page?')) return jsonResponse({ name: 'Flaggenbande' })
    throw new Error(`Unexpected request: ${value}`)
  }

  const social = await collectSocialPlatforms({
    env: {
      META_FACEBOOK_PAGE_ACCESS_TOKEN: 'facebook-page-token',
      META_FACEBOOK_PAGE_ID: 'fb-page',
    },
    fetchImpl,
  })

  assert.equal(social.platforms.facebook.status, 'partial')
  assert.match(social.platforms.facebook.reason, /Insights fehlen fuer 1 Video/)
  assert.match(social.platforms.facebook.reason, /HTTP 403/)
  assert.doesNotMatch(social.platforms.facebook.reason, /must-not-leak|facebook-page-token|access_token/)
  const facebook = social.videos.find(entry => entry.platform === 'facebook')
  assert.equal(facebook.url, 'https://www.facebook.com/reel/1594633352224956')
  assert.equal(facebook.metrics.likes, 7)
  assert.equal(facebook.metrics.comments, 2)
  assert.equal(facebook.metrics.views, null)
})

test('Facebook maps official Reel insights before considering classic video metrics', async () => {
  const insightRequests = []
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    assert.equal(options.headers?.authorization, 'Bearer facebook-page-token')
    if (value.includes('/fb-page/videos')) {
      return jsonResponse({ data: [{
        id: 'reel-1', created_time: '2026-07-21T13:17:29Z', published: true, length: 40,
        permalink_url: 'https://www.facebook.com/reel/reel-1',
        likes: { summary: { total_count: 3 } }, comments: { summary: { total_count: 1 } },
      }] })
    }
    if (value.includes('/reel-1/video_insights')) {
      const metric = new URL(value).searchParams.get('metric')
      insightRequests.push(metric)
      return jsonResponse({ data: [
        { name: 'blue_reels_play_count', values: [{ value: 125 }] },
        { name: 'post_impressions_unique', values: [{ value: 90 }] },
        { name: 'post_video_avg_time_watched', values: [{ value: 12_500 }] },
        { name: 'post_video_view_time', values: [{ value: 750_000 }] },
        { name: 'post_video_followers', values: [{ value: 4 }] },
      ] })
    }
    if (value.includes('/fb-page?')) return jsonResponse({ name: 'Flaggenbande' })
    throw new Error(`Unexpected request: ${value}`)
  }

  const social = await collectSocialPlatforms({
    env: { META_FACEBOOK_PAGE_ACCESS_TOKEN: 'facebook-page-token', META_FACEBOOK_PAGE_ID: 'fb-page' },
    fetchImpl,
  })

  assert.equal(social.platforms.facebook.status, 'available')
  assert.equal(insightRequests.length, 1)
  assert.match(insightRequests[0], /blue_reels_play_count/)
  assert.doesNotMatch(insightRequests[0], /total_video_views/)
  const facebook = social.videos.find(entry => entry.platform === 'facebook')
  assert.equal(facebook.metrics.views, 125)
  assert.equal(facebook.metrics.reach, 90)
  assert.equal(facebook.metrics.averageViewDurationSeconds, 12.5)
  assert.equal(facebook.metrics.watchTimeMinutes, 12.5)
  assert.equal(facebook.metrics.followersGained, 4)
})

test('Facebook falls back to classic video metrics and treats two empty insight responses as partial', async () => {
  const run = async classicPayload => {
    const requests = []
    const fetchImpl = async (url, options = {}) => {
      const value = String(url)
      assert.equal(options.headers?.authorization, 'Bearer facebook-page-token')
      if (value.includes('/fb-page/videos')) {
        return jsonResponse({ data: [{ id: 'video-1', created_time: '2026-07-21T13:17:29Z', published: true, length: 50 }] })
      }
      if (value.includes('/video-1/video_insights')) {
        const metric = new URL(value).searchParams.get('metric')
        requests.push(metric)
        return metric.includes('blue_reels_play_count') ? jsonResponse({ data: [] }) : jsonResponse(classicPayload)
      }
      if (value.includes('/fb-page?')) return jsonResponse({ name: 'Flaggenbande' })
      throw new Error(`Unexpected request: ${value}`)
    }
    return {
      requests,
      social: await collectSocialPlatforms({
        env: { META_FACEBOOK_PAGE_ACCESS_TOKEN: 'facebook-page-token', META_FACEBOOK_PAGE_ID: 'fb-page' },
        fetchImpl,
      }),
    }
  }

  const classic = await run({ data: [
    { name: 'total_video_views', values: [{ value: 40 }] },
    { name: 'total_video_views_unique', values: [{ value: 32 }] },
    { name: 'total_video_view_total_time', values: [{ value: 180_000 }] },
    { name: 'total_video_avg_time_watched', values: [{ value: 4_500 }] },
  ] })
  assert.equal(classic.requests.length, 2)
  assert.match(classic.requests[1], /total_video_views/)
  assert.equal(classic.social.platforms.facebook.status, 'available')
  assert.equal(classic.social.videos[0].metrics.views, 40)
  assert.equal(classic.social.videos[0].metrics.reach, 32)
  assert.equal(classic.social.videos[0].metrics.watchTimeMinutes, 3)
  assert.equal(classic.social.videos[0].metrics.averageViewDurationSeconds, 4.5)

  const empty = await run({ data: [] })
  assert.equal(empty.social.platforms.facebook.status, 'partial')
  assert.match(empty.social.platforms.facebook.reason, /Insights fehlen fuer 1 Video/)
  assert.equal(empty.social.videos[0].metrics.views, null)
})

test('YouTube collects validated audience retention per public video without inventing missing points', async () => {
  const calls = []
  const baseFetch = youtubeFetch()
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    if (value.includes('youtubeanalytics.googleapis.com')) {
      const query = new URL(value).searchParams
      if (query.get('dimensions') === 'elapsedVideoTimeRatio') {
        calls.push(query)
        const validRows = Array.from({ length: 101 }, (_, index) => [index / 100, 1 - (index / 200), index / 100])
        return jsonResponse({
          columnHeaders: [
            { name: 'elapsedVideoTimeRatio' },
            { name: 'audienceWatchRatio' },
            { name: 'relativeRetentionPerformance' },
          ],
          rows: [[-0.1, 1, 0.5], [0.5, -1, 0.5], [0.005, 0.9, null], [0.5, 1, 2], ...validRows],
        })
      }
    }
    return baseFetch(url, options)
  }

  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-token' },
    fetchImpl,
  })

  assert.equal(calls.length, 1)
  assert.equal(calls[0].get('filters'), 'video==public')
  assert.equal(calls[0].get('metrics'), 'audienceWatchRatio,relativeRetentionPerformance')
  assert.equal(calls[0].get('maxResults'), '100')
  const youtube = social.videos.find(entry => entry.platform === 'youtube')
  assert.equal(youtube.retention.length, 100)
  assert.deepEqual(youtube.retention[0], {
    elapsedVideoTimeRatio: 0.005,
    audienceWatchRatio: 0.9,
    relativeRetentionPerformance: null,
  })
  assert.ok(youtube.retention.every(point => point.elapsedVideoTimeRatio > 0 && point.elapsedVideoTimeRatio <= 1))
})

test('YouTube retention checks are cached for 24 hours and capped at 12 overdue videos per run', async () => {
  const privacyById = Object.fromEntries(Array.from({ length: 16 }, (_, index) => [`public-${String(index + 1).padStart(2, '0')}`, 'public']))
  const baseFetch = youtubeFetch({ privacyById })
  let retentionCalls = 0
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    if (value.includes('youtubeanalytics.googleapis.com')) {
      const query = new URL(value).searchParams
      if (query.get('dimensions') === 'elapsedVideoTimeRatio') {
        retentionCalls += 1
        return jsonResponse({
          columnHeaders: [
            { name: 'elapsedVideoTimeRatio' },
            { name: 'audienceWatchRatio' },
            { name: 'relativeRetentionPerformance' },
          ],
          rows: [[0.01, 1, 0.5], [1, 0.4, 0.3]],
        })
      }
    }
    return baseFetch(url, options)
  }

  const first = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-token' },
    fetchImpl,
  })

  assert.equal(retentionCalls, 12)
  assert.equal(first.platforms.youtube.status, 'partial')
  assert.match(first.platforms.youtube.reason, /Retention fuer 4 Videos werden in spaeteren Laeufen nachgeladen/)
  assert.equal(first.videos.filter(entry => entry.retentionCheckedAt).length, 12)
  assert.equal(first.videos.filter(entry => entry.retention?.length === 2).length, 12)

  const second = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-token' },
    fetchImpl,
    previous: first,
  })

  assert.equal(retentionCalls, 16)
  assert.equal(second.platforms.youtube.status, 'available')
  assert.equal(second.videos.filter(entry => entry.retentionCheckedAt).length, 16)
  assert.ok(second.videos.every(entry => entry.retention?.length === 2))
})

test('YouTube retention API errors mark the platform partial and preserve the last known curve', async () => {
  const oldCheckedAt = new Date(Date.now() - (25 * 60 * 60 * 1000)).toISOString().replace(/\.\d{3}Z$/, 'Z')
  const previousPoint = { elapsedVideoTimeRatio: 0.5, audienceWatchRatio: 0.62, relativeRetentionPerformance: 0.4 }
  const previousVideo = socialVideo('youtube', 'public', {
    retention: [previousPoint],
    retentionCheckedAt: oldCheckedAt,
  })
  const previous = {
    platforms: { youtube: { status: 'available', accountName: 'Flaggenbande', videoCount: 1 } },
    videos: [previousVideo],
    snapshots: [],
  }
  const baseFetch = youtubeFetch()
  let retentionCalls = 0
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    if (value.includes('youtubeanalytics.googleapis.com')) {
      const query = new URL(value).searchParams
      if (query.get('dimensions') === 'elapsedVideoTimeRatio') {
        retentionCalls += 1
        return jsonResponse({ error: { message: 'quota exceeded' } }, 429)
      }
    }
    return baseFetch(url, options)
  }

  const attemptedAt = Date.now()
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-token' },
    fetchImpl,
    previous,
  })

  assert.equal(retentionCalls, 1)
  assert.equal(social.platforms.youtube.status, 'partial')
  assert.match(social.platforms.youtube.reason, /Retention konnte fuer 1 Video nicht aktualisiert werden/)
  assert.deepEqual(social.videos[0].retention, [previousPoint])
  assert.ok(Date.parse(social.videos[0].retentionCheckedAt) >= attemptedAt - 1_000)
  assert.equal(social.videos[0].retentionCheckStatus, 'error')

  const checkedAtAfterFailure = social.videos[0].retentionCheckedAt
  const cached = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-token' },
    fetchImpl,
    previous: social,
  })

  assert.equal(retentionCalls, 1)
  assert.equal(cached.platforms.youtube.status, 'partial')
  assert.deepEqual(cached.videos[0].retention, [previousPoint])
  assert.equal(cached.videos[0].retentionCheckedAt, checkedAtAfterFailure)
  assert.equal(cached.videos[0].retentionCheckStatus, 'error')
})

test('TikTok refresh credentials obtain a short-lived access token before video collection', async () => {
  const calls = []
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    calls.push({ value, options })
    if (value.endsWith('/v2/oauth/token/')) {
      const body = new URLSearchParams(options.body)
      assert.equal(body.get('client_key'), 'client-key')
      assert.equal(body.get('client_secret'), 'client-secret')
      assert.equal(body.get('grant_type'), 'refresh_token')
      assert.equal(body.get('refresh_token'), 'refresh-token')
      return jsonResponse({ access_token: 'fresh-access-token', refresh_token: 'refresh-token' })
    }
    if (value.includes('/v2/video/list/')) {
      assert.equal(options.headers.authorization, 'Bearer fresh-access-token')
      return jsonResponse({ data: { videos: [], has_more: false }, error: { code: 'ok' } })
    }
    throw new Error(`Unexpected request: ${value}`)
  }

  const social = await collectSocialPlatforms({
    env: {
      TIKTOK_CLIENT_KEY: 'client-key',
      TIKTOK_CLIENT_SECRET: 'client-secret',
      TIKTOK_REFRESH_TOKEN: 'refresh-token',
    },
    fetchImpl,
  })

  assert.equal(calls.length, 2)
  assert.equal(social.platforms.tiktok.status, 'available')
})

test('cloud analytics feed is preferred and preserves the internal content ID', async () => {
  let calls = 0
  const fetchImpl = async url => {
    calls += 1
    assert.equal(String(url), 'https://analytics.example.test/feed')
    return jsonResponse({
      schemaVersion: 1,
      generatedAt: '2026-07-20T20:00:00Z',
      platforms: {
        youtube: { status: 'available', accountName: 'Flaggenbande', completedAt: '2026-07-20T20:00:00Z' },
      },
      videos: [{
        platform: 'youtube',
        platformVideoId: 'yt-v5',
        contentId: 'gameshow-retention-leda-v5',
        title: 'Only 0.14% can name all three',
        description: '',
        publishedAt: '2026-07-20T18:27:00Z',
        url: 'https://youtube.test/yt-v5',
        thumbnailUrl: null,
        status: 'public',
        durationSeconds: 36,
        metrics: { views: 42, likes: 4 },
      }],
    })
  }

  const social = await collectSocialPlatforms({
    env: { SOCIAL_ANALYTICS_FEED_URL: 'https://analytics.example.test/feed' },
    fetchImpl,
  })

  assert.equal(calls, 1)
  assert.equal(social.platforms.youtube.status, 'available')
  assert.equal(social.platforms.youtube.videoCount, 1)
  assert.equal(social.platforms.youtube.uploadCount, 1)
  assert.equal(social.videos[0].contentId, 'gameshow-retention-leda-v5')
  assert.equal(social.videos[0].metrics.views, 42)
  assert.deepEqual(social.uploads, [])
})

test('complete YouTube OAuth credentials prefer direct upload inventory while Meta stays on the cloud feed', async () => {
  const calls = []
  const directYouTubeFetch = youtubeFetch({
    privacyById: {
      directPublic: 'public',
      directPrivate: 'private',
    },
  })
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    calls.push(value)
    if (value === 'https://analytics.example.test/feed') {
      return jsonResponse({
        schemaVersion: 1,
        generatedAt: '2026-07-21T12:00:00Z',
        platforms: {
          youtube: { status: 'available', accountName: 'Feed channel' },
          instagram: { status: 'available', accountName: 'flaggenbande' },
          facebook: { status: 'available', accountName: 'Flaggenbande' },
        },
        videos: [
          {
            platform: 'youtube',
            platformVideoId: 'feed-public',
            title: 'Feed-only YouTube video',
            publishedAt: '2026-07-21T10:00:00Z',
            status: 'public',
            metrics: { views: 999 },
          },
          {
            platform: 'instagram',
            platformVideoId: 'ig-feed-video',
            title: 'Instagram feed video',
            publishedAt: '2026-07-21T10:00:00Z',
            status: 'published',
            metrics: { views: 25 },
          },
        ],
      })
    }
    if (value === 'https://oauth2.googleapis.com/token') {
      const body = new URLSearchParams(options.body)
      assert.equal(body.get('client_id'), 'youtube-client-id')
      assert.equal(body.get('client_secret'), 'youtube-client-secret')
      assert.equal(body.get('refresh_token'), 'youtube-refresh-token')
      return jsonResponse({ access_token: 'fresh-youtube-access-token' })
    }
    return directYouTubeFetch(url, options)
  }

  const social = await collectSocialPlatforms({
    env: {
      SOCIAL_ANALYTICS_FEED_URL: 'https://analytics.example.test/feed',
      YOUTUBE_CLIENT_ID: 'youtube-client-id',
      YOUTUBE_CLIENT_SECRET: 'youtube-client-secret',
      YOUTUBE_REFRESH_TOKEN: 'youtube-refresh-token',
    },
    fetchImpl,
  })

  assert.ok(calls.includes('https://oauth2.googleapis.com/token'))
  assert.ok(calls.some(value => value.includes('/youtube/v3/channels')))
  assert.equal(calls.some(value => value.includes('graph.instagram.com')), false)
  assert.equal(calls.some(value => value.includes('graph.facebook.com')), false)
  assert.equal(social.platforms.youtube.accountName, 'Flaggenbande')
  assert.equal(social.platforms.youtube.videoCount, 1)
  assert.equal(social.platforms.youtube.uploadCount, 2)
  assert.deepEqual(
    social.videos.filter(entry => entry.platform === 'youtube').map(entry => entry.platformVideoId),
    ['directPublic'],
  )
  assert.deepEqual(
    social.videos.filter(entry => entry.platform === 'instagram').map(entry => entry.platformVideoId),
    ['ig-feed-video'],
  )
  assert.equal(social.videos.some(entry => entry.platformVideoId === 'feed-public'), false)
  assert.equal(social.uploads.filter(entry => entry.platform === 'youtube').length, 2)
})

test('cloud analytics feed accepts a validated optional upload inventory without changing KPIs', async () => {
  const fetchImpl = async () => jsonResponse({
    schemaVersion: 1,
    generatedAt: '2026-07-21T10:00:00Z',
    platforms: {
      youtube: { status: 'available', accountName: 'Flaggenbande' },
    },
    videos: [{
      platform: 'youtube',
      platformVideoId: 'public-1',
      title: 'Public quiz',
      publishedAt: '2026-07-21T08:00:00Z',
      status: 'public',
      metrics: { views: 25 },
    }],
    uploads: [
      {
        platform: 'youtube',
        platformVideoId: 'public-1',
        title: 'Public quiz',
        uploadedAt: '2026-07-21T08:00:00Z',
        publishedAt: '2026-07-21T08:00:00Z',
        status: 'public',
        privacyStatus: 'public',
        uploadStatus: 'processed',
        durationSeconds: 39,
      },
      {
        platform: 'youtube',
        platformVideoId: 'scheduled-1',
        title: 'Next quiz',
        uploadedAt: '2026-07-21T09:00:00Z',
        scheduledAt: '2026-07-22T09:00:00Z',
        status: 'scheduled',
        privacyStatus: 'private',
        uploadStatus: 'processed',
        durationSeconds: 39,
        metrics: { views: 999999 },
      },
    ],
  })

  const social = await collectSocialPlatforms({
    env: { SOCIAL_ANALYTICS_FEED_URL: 'https://analytics.example.test/feed' },
    fetchImpl,
  })

  assert.equal(social.platforms.youtube.videoCount, 1)
  assert.equal(social.platforms.youtube.uploadCount, 2)
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['public-1'])
  assert.equal(social.uploads[0].status, 'scheduled')
  assert.match(social.uploads[0].platformVideoId, /^non-public-[a-f0-9]{20}$/)
  assert.equal(social.uploads[1].platformVideoId, 'public-1')
  assert.equal('metrics' in social.uploads[0], false)
  assert.equal(social.totals.views, 25)
  assert.equal(social.snapshots.length, 1)
})

test('invalid cloud upload inventory is rejected and cannot leak into social data', async () => {
  const social = await collectSocialPlatforms({
    env: { SOCIAL_ANALYTICS_FEED_URL: 'https://analytics.example.test/feed' },
    fetchImpl: async () => jsonResponse({
      schemaVersion: 1,
      platforms: { youtube: { status: 'available' } },
      videos: [],
      uploads: [{ platform: 'youtube', platformVideoId: '', status: 'private' }],
    }),
  })

  assert.equal(social.platforms.youtube.status, 'not_configured')
  assert.equal(social.platforms.youtube.videoCount, 0)
  assert.equal(social.platforms.youtube.uploadCount, 0)
  assert.deepEqual(social.uploads, [])
})

test('one platform failure is isolated and public reasons redact API response secrets', async () => {
  const leakedAccessToken = 'act.this-must-never-be-public'
  const leakedClientSecret = 'client-secret-value'
  const fetchImpl = async (url, options = {}) => {
    const value = String(url)
    if (value.includes('/youtube/v3/channels')) {
      return new Response(JSON.stringify({
        error: {
          message: `access_token=${leakedAccessToken} client_secret=${leakedClientSecret}`,
        },
      }), { status: 401 })
    }
    if (value.includes('/v2/video/list/')) {
      assert.equal(options.method, 'POST')
      return jsonResponse({
        data: {
          videos: [{ id: 'tt-ok', title: 'Still collected', share_url: 'https://tiktok.test/tt-ok', create_time: 2, view_count: 5 }],
          has_more: false,
        },
        error: { code: 'ok' },
      })
    }
    throw new Error(`Unexpected request: ${value}`)
  }

  const social = await collectSocialPlatforms({
    env: {
      YOUTUBE_ACCESS_TOKEN: 'youtube-test-token',
      TIKTOK_ACCESS_TOKEN: 'tiktok-test-token',
    },
    fetchImpl,
  })

  assert.equal(social.platforms.youtube.status, 'error')
  assert.equal(social.platforms.youtube.reason, 'API request failed with HTTP 401.')
  assert.doesNotMatch(JSON.stringify(social), /this-must-never-be-public|client-secret-value/)
  assert.equal(social.platforms.tiktok.status, 'available')
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['tt-ok'])
})

test('a temporary platform error preserves the last known videos, status, totals, and snapshots', async () => {
  const previousVideo = socialVideo('youtube', 'known-public', {
    metrics: metrics({ views: 321, likes: 14, averageViewDurationSeconds: 19 }),
  })
  const previous = {
    platforms: {
      youtube: {
        status: 'available',
        accountName: 'Flaggenbande',
        videoCount: 1,
        startedAt: '2026-07-20T08:00:00Z',
        completedAt: '2026-07-20T08:00:01Z',
      },
    },
    videos: [previousVideo],
    uploads: [{
      platform: 'youtube',
      platformVideoId: 'known-private',
      title: 'Known private upload',
      uploadedAt: '2026-07-20T07:00:00Z',
      publishedAt: null,
      scheduledAt: null,
      status: 'private',
      privacyStatus: 'private',
      uploadStatus: 'processed',
      durationSeconds: 30,
    }],
    snapshots: [{
      platform: 'youtube',
      platformVideoId: 'known-public',
      capturedAt: new Date().toISOString(),
      metrics: previousVideo.metrics,
    }],
  }
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-test-token' },
    previous,
    fetchImpl: async () => jsonResponse({ error: { message: 'temporary' } }, 401),
  })

  assert.equal(social.platforms.youtube.status, 'available')
  assert.equal(social.platforms.youtube.accountName, 'Flaggenbande')
  assert.equal(social.platforms.youtube.videoCount, 1)
  assert.equal(social.platforms.youtube.uploadCount, 1)
  assert.match(social.platforms.youtube.reason, /bekannte Daten bleiben erhalten/)
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['known-public'])
  assert.deepEqual(social.uploads.map(entry => entry.title), ['Known private upload'])
  assert.equal(social.totals.views, 321)
  assert.equal(social.totals.averageViewDurationSeconds, null)
  assert.equal(social.snapshots.length, 1)
})

test('history merge retains videos and adds one timestamped metric snapshot', () => {
  const current = {
    platforms: {},
    videos: [socialVideo('youtube', 'video-1', { metrics: metrics({ views: 10, likes: 2 }) })],
  }
  const merged = mergeSocialHistory(null, current, '2026-07-20T12:00:00Z')
  assert.equal(merged.videos.length, 1)
  assert.deepEqual(merged.uploads, [])
  assert.equal(merged.snapshots.length, 1)
  assert.equal(merged.snapshots[0].metrics.views, 10)

  const updated = mergeSocialHistory(merged, {
    ...current,
    videos: [{ ...current.videos[0], metrics: metrics({ views: 18, likes: 3 }) }],
  }, '2026-07-20T13:00:00Z')
  assert.equal(updated.videos.length, 1)
  assert.equal(updated.videos[0].metrics.views, 18)
  assert.equal(updated.snapshots.length, 2)
})

test('partial refresh preserves known metrics and retention using the independent previous index', () => {
  const retentionCheckedAt = '2026-07-20T08:00:00Z'
  const previousPoint = { elapsedVideoTimeRatio: 0.5, audienceWatchRatio: 0.64, relativeRetentionPerformance: 0.45 }
  const previousVideo = socialVideo('youtube', 'video-1', {
    metrics: metrics({ views: 100, likes: 8 }),
    retention: [previousPoint],
    retentionCheckedAt,
  })
  const previous = {
    platforms: { youtube: { status: 'available' } },
    videos: [previousVideo],
    snapshots: [],
  }
  const refreshed = socialVideo('youtube', 'video-1', {
    metrics: metrics({ views: null, likes: 9 }),
    retention: [],
  })
  const merged = mergeSocialHistory(previous, {
    platforms: { youtube: { status: 'partial' } },
    videos: [refreshed],
    refreshedPlatforms: ['youtube'],
  }, '2026-07-21T10:00:00Z')

  assert.equal(merged.videos[0].metrics.views, 100)
  assert.equal(merged.videos[0].metrics.likes, 9)
  assert.deepEqual(merged.videos[0].retention, [previousPoint])
  assert.equal(merged.videos[0].retentionCheckedAt, retentionCheckedAt)
  assert.equal(merged.snapshots[0].metrics.views, 100)
})

test('totals sum additive metrics only and leave averages unset', () => {
  const merged = mergeSocialHistory(null, {
    platforms: {},
    videos: [
      socialVideo('youtube', 'yt', {
        metrics: metrics({
          views: 10,
          reach: 8,
          likes: 2,
          watchTimeMinutes: 4,
          averageViewDurationSeconds: 16,
          averageViewPercentage: 44,
        }),
      }),
      socialVideo('instagram', 'ig', {
        metrics: metrics({
          views: 20,
          reach: 15,
          likes: 5,
          watchTimeMinutes: 9,
          averageViewDurationSeconds: 28,
          averageViewPercentage: 71,
        }),
      }),
    ],
  }, '2026-07-20T12:00:00Z')

  assert.equal(merged.totals.views, 30)
  assert.equal(merged.totals.reach, 23)
  assert.equal(merged.totals.likes, 7)
  assert.equal(merged.totals.watchTimeMinutes, 13)
  assert.equal(merged.totals.averageViewDurationSeconds, null)
  assert.equal(merged.totals.averageViewPercentage, null)
})
