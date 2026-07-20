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

const youtubeFetch = ({ privacyById = { public: 'public' }, analytics = true } = {}) => async url => {
  const value = String(url)
  if (value.includes('/youtube/v3/channels')) {
    return jsonResponse({
      items: [{
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
          publishedAt: `2026-07-20T1${index}:00:00Z`,
          thumbnails: { default: { url: `https://img.test/${id}.jpg` } },
        },
        status: { privacyStatus },
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
  assert.equal(social.totals.views, 0)
  assert.equal(social.totals.averageViewDurationSeconds, null)
  assert.equal(social.totals.averageViewPercentage, null)
})

test('YouTube exports public videos only and never scheduled, private, or unlisted uploads', async () => {
  const social = await collectSocialPlatforms({
    env: { YOUTUBE_ACCESS_TOKEN: 'youtube-test-token' },
    fetchImpl: youtubeFetch({
      privacyById: {
        publicVideo: 'public',
        privateVideo: 'private',
        scheduledVideo: 'private',
        unlistedVideo: 'unlisted',
      },
    }),
  })

  assert.equal(social.platforms.youtube.status, 'available')
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['publicVideo'])
  assert.equal(social.videos[0].status, 'public')
  assert.equal(social.videos[0].metrics.views, 200)
  assert.equal(social.totals.views, 200)
  assert.equal(social.totals.averageViewDurationSeconds, null)
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
  assert.equal(social.videos.length, 0)
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
  assert.equal(social.videos[0].contentId, 'gameshow-retention-leda-v5')
  assert.equal(social.videos[0].metrics.views, 42)
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
  assert.match(social.platforms.youtube.reason, /bekannte Daten bleiben erhalten/)
  assert.deepEqual(social.videos.map(entry => entry.platformVideoId), ['known-public'])
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
