import assert from 'node:assert/strict'
import test from 'node:test'
import {
  fetchPublicationFeed,
  fetchStagingFeed,
  mergePublicationFeed,
  mergeStagingFeed,
  normalizePublicationFeed,
  normalizeStagingFeed,
  publicationFeedUrl,
  reconcilePublishedSocial,
  stagingFeedUrl,
} from '../scripts/collect-content-operations.mjs'

const contentId = `flaggenbande-${'a'.repeat(64)}`
const runId = 'upload-test-gameshow-five-flag-elevenlabs-v6'

const feed = () => ({
  schemaVersion: 1,
  generatedAt: '2026-07-21T12:00:00Z',
  runs: [{
    runId,
    contentId,
    status: 'completed',
    qualityStatus: 'passed',
    startedAt: '2026-07-21T11:00:00Z',
    completedAt: '2026-07-21T11:30:00Z',
    remoteObjectId: 'must-not-leak-from-run',
  }],
  publications: [
    { contentId, platform: 'youtube', status: 'ready', remoteObjectId: 'youtube-private-id' },
    { contentId, platform: 'instagram', status: 'upload_ready', containerId: 'instagram-container-id' },
    { contentId, platform: 'facebook', status: 'ready', providerStatus: 'DRAFT' },
    { contentId, platform: 'tiktok', status: 'manual_uploaded', accountFingerprint: 'private-account-fingerprint' },
  ],
  metadata: { title: 'unveröffentlichter Titel', answers: ['Brazil'] },
})

const previous = () => ({
  schemaVersion: 1,
  generatedAt: '2026-07-20T10:03:20Z',
  status: 'partial',
  messages: ['Bestehender sicherer Hinweis.'],
  system: [],
  platforms: ['youtube', 'instagram', 'tiktok', 'facebook'].map(platform => ({
    platform,
    label: platform,
    status: 'not_configured',
    uploads: 0,
    publications: 0,
    performanceAvailable: false,
    reason: 'Noch kein Testlauf.',
    updatedAt: null,
  })),
  runs: [],
  publications: [],
  performance: [],
})

const publicationFeed = (publications = [
  {
    contentId,
    platform: 'instagram',
    status: 'failed',
    scheduledAt: '2026-07-21T13:00:00Z',
    updatedAt: '2026-07-21T13:05:00Z',
    publishedAt: null,
    failureCode: 'api_access_blocked',
  },
  {
    contentId,
    platform: 'facebook',
    status: 'failed',
    scheduledAt: '2026-07-21T13:00:00Z',
    updatedAt: '2026-07-21T13:05:01Z',
    publishedAt: null,
    failureCode: 'authentication_failed',
  },
]) => ({
  schemaVersion: 1,
  lane: 'production-publication',
  generatedAt: '2026-07-21T13:06:00Z',
  publications,
})

test('staging feed is reduced to safe content-operation fields and confirmed non-public states', () => {
  const normalized = normalizeStagingFeed(feed())
  assert.equal(normalized.runs.length, 1)
  assert.equal(normalized.runs[0].title, null)
  assert.deepEqual(Object.fromEntries(normalized.publications.map(entry => [entry.platform, entry.status])), {
    youtube: 'private',
    instagram: 'upload_ready',
    tiktok: 'manual_uploaded',
    facebook: 'draft',
  })
  assert.ok(normalized.publications.every(entry => entry.runId === runId && entry.mode && entry.updatedAt === '2026-07-21T11:00:00.000Z'))
  assert.ok(normalized.publications.every(entry => entry.title === null && entry.scheduledAt === null && entry.publishedAt === null && entry.publicUrl === null))
  assert.doesNotMatch(JSON.stringify(normalized), /remoteObjectId|containerId|accountFingerprint|providerStatus|unveröffentlichter Titel|Brazil|private-id/)
})

test('release numbering and both approval stages are validated and inherited by every platform target', () => {
  const payload = feed()
  Object.assign(payload.runs[0], {
    releaseLabel: '2307.04',
    videoApproved: true,
    finalReleaseApproved: true,
  })
  Object.assign(payload.publications[0], {
    releaseLabel: '2307.04',
    videoApproved: true,
    finalReleaseApproved: true,
  })

  const normalized = normalizeStagingFeed(payload)

  assert.deepEqual(
    {
      releaseLabel: normalized.runs[0].releaseLabel,
      videoApproved: normalized.runs[0].videoApproved,
      finalReleaseApproved: normalized.runs[0].finalReleaseApproved,
    },
    { releaseLabel: '2307.04', videoApproved: true, finalReleaseApproved: true },
  )
  assert.ok(normalized.publications.every(publication =>
    publication.releaseLabel === '2307.04'
    && publication.videoApproved === true
    && publication.finalReleaseApproved === true))

  for (const invalidLabel of ['2307.04X', '3207.04', '3002.04', '2307.4']) {
    const invalid = feed()
    invalid.runs[0].releaseLabel = invalidLabel
    assert.throws(() => normalizeStagingFeed(invalid), /releaseLabel/)
  }

  const incompleteApproval = feed()
  incompleteApproval.runs[0].releaseLabel = '2307.04'
  incompleteApproval.runs[0].finalReleaseApproved = true
  assert.throws(() => normalizeStagingFeed(incompleteApproval), /setzt videoApproved voraus/)

  const mismatched = feed()
  mismatched.runs[0].releaseLabel = '2307.04'
  mismatched.publications[0].releaseLabel = '2307.05'
  assert.throws(() => normalizeStagingFeed(mismatched), /widerspricht den Laufdaten/)
})

test('transport problems remain explicit and container_unpublished mode is preserved', () => {
  const payload = feed()
  payload.runs[0].status = 'reconcile_required'
  payload.runs[0].completedAt = null
  payload.publications[0].status = 'private_uploaded'
  payload.publications[1].status = 'ready'
  payload.publications[1].mode = 'container_unpublished'
  payload.publications[2].status = 'reconcile_required'
  payload.publications[3].status = 'expired'

  const normalized = normalizeStagingFeed(payload)
  assert.equal(normalized.runs[0].status, 'reconcile_required')
  assert.deepEqual(Object.fromEntries(normalized.publications.map(entry => [entry.platform, entry.status])), {
    youtube: 'private',
    instagram: 'container_unpublished',
    tiktok: 'expired',
    facebook: 'reconcile_required',
  })
})

test('run start uses the earliest trusted target timestamp when platform updates slightly lead the run record', () => {
  const payload = feed()
  payload.runs[0].startedAt = '2026-07-23T19:45:00Z'
  payload.runs[0].completedAt = null
  payload.publications.forEach((publication, index) => {
    publication.runId = runId
    publication.updatedAt = index < 2
      ? '2026-07-23T19:43:59Z'
      : '2026-07-23T19:44:06Z'
  })

  const normalized = normalizeStagingFeed(payload)

  assert.equal(normalized.runs[0].startedAt, '2026-07-23T19:43:59.000Z')
  assert.deepEqual(
    normalized.publications.map(publication => publication.updatedAt),
    [
      '2026-07-23T19:43:59.000Z',
      '2026-07-23T19:43:59.000Z',
      '2026-07-23T19:44:06.000Z',
      '2026-07-23T19:44:06.000Z',
    ],
  )
})

test('staging feed rejects public claims, authorization, mismatched modes, and incomplete runs', () => {
  const published = feed()
  published.publications[0].status = 'published'
  assert.throws(() => normalizeStagingFeed(published), /keine Veröffentlichung/)

  const authorized = feed()
  authorized.publicationAuthorized = true
  assert.throws(() => normalizeStagingFeed(authorized), /keine Veröffentlichung autorisieren/)

  const wrongMode = feed()
  wrongMode.publications[0].mode = 'draft'
  assert.throws(() => normalizeStagingFeed(wrongMode), /passt nicht zur Plattform/)

  const incomplete = feed()
  incomplete.publications.pop()
  assert.throws(() => normalizeStagingFeed(incomplete), /nicht alle vier Plattformstatus/)
})

test('merge updates only safe staging sections and leaves publication counts at zero', () => {
  const merged = mergeStagingFeed(previous(), normalizeStagingFeed(feed()))
  assert.equal(merged.generatedAt, '2026-07-21T12:00:00.000Z')
  assert.equal(merged.status, 'ok')
  assert.equal(merged.runs.length, 1)
  assert.equal(merged.publications.length, 4)
  assert.ok(merged.platforms.every(entry => entry.status === 'ready'))
  assert.ok(merged.platforms.every(entry => entry.uploads === 1 && entry.publications === 0))
  assert.ok(merged.messages.some(message => message.includes('keine Veröffentlichung autorisiert')))
})

test('planned targets are not counted as completed uploads', () => {
  const payload = feed()
  payload.runs[0].status = 'partial'
  payload.runs[0].completedAt = null
  payload.publications[0].status = 'planned'
  const merged = mergeStagingFeed(previous(), normalizeStagingFeed(payload))
  assert.equal(merged.status, 'partial')
  assert.equal(merged.platforms.find(entry => entry.platform === 'youtube').uploads, 0)
  assert.equal(merged.platforms.find(entry => entry.platform === 'instagram').uploads, 1)
})

test('production publication feed accepts only the safe status contract', () => {
  const payload = publicationFeed()
  payload.publications[0].lastError = 'raw provider error must not survive normalization'
  payload.publications[0].platformVideoId = 'private-platform-id'
  payload.publications[0].mediaUrl = 'https://media.example.test/private.mp4'
  payload.publications[0].metadata = { title: 'private title' }
  const normalized = normalizePublicationFeed(payload)
  assert.equal(normalized.publications.length, 2)
  assert.deepEqual(normalized.publications[0], {
    contentId,
    platform: 'instagram',
    status: 'failed',
    scheduledAt: '2026-07-21T13:00:00.000Z',
    updatedAt: '2026-07-21T13:05:00.000Z',
    publishedAt: null,
    publicUrl: null,
    failureCode: 'api_access_blocked',
  })
  assert.doesNotMatch(JSON.stringify(normalized), /raw provider|platform-id|media\.example|private title/)

  const rawFailure = publicationFeed()
  rawFailure.publications[0].failureCode = 'OAuthException raw text'
  assert.throws(() => normalizePublicationFeed(rawFailure), /failureCode ist unbekannt/)

  const missingPublishedAt = publicationFeed([{
    ...publicationFeed().publications[0],
    status: 'published',
    publicUrl: 'https://www.instagram.com/flaggenbande/reel/DbGSI2gFgL_/',
    failureCode: null,
  }])
  assert.throws(() => normalizePublicationFeed(missingPublishedAt), /publishedAt fehlt/)

  const published = normalizePublicationFeed(publicationFeed([{
    contentId,
    platform: 'instagram',
    status: 'published',
    scheduledAt: '2026-07-21T13:00:00Z',
    updatedAt: '2026-07-21T13:05:00Z',
    publishedAt: '2026-07-21T13:04:00Z',
    publicUrl: 'https://www.instagram.com/flaggenbande/reel/DbGSI2gFgL_/?utm_source=test#fragment',
    failureCode: null,
  }]))
  assert.equal(published.publications[0].publicUrl, 'https://www.instagram.com/flaggenbande/reel/DbGSI2gFgL_/')

  const missingPublicUrl = publicationFeed([{
    contentId,
    platform: 'facebook',
    status: 'published',
    scheduledAt: '2026-07-21T13:00:00Z',
    updatedAt: '2026-07-21T13:05:00Z',
    publishedAt: '2026-07-21T13:04:00Z',
    failureCode: null,
  }])
  assert.throws(() => normalizePublicationFeed(missingPublicUrl), /publicUrl fehlt/)
})

test('production queue failures override planned staging targets with safe failure codes', () => {
  const payload = feed()
  payload.runs[0].status = 'partial'
  payload.runs[0].completedAt = null
  payload.publications.find(entry => entry.platform === 'instagram').status = 'planned'
  payload.publications.find(entry => entry.platform === 'facebook').status = 'planned'
  const staged = mergeStagingFeed(previous(), normalizeStagingFeed(payload))
  const overlaid = mergePublicationFeed(staged, normalizePublicationFeed(publicationFeed()))

  assert.equal(overlaid.runs[0].status, 'failed')
  assert.equal(overlaid.publications.find(entry => entry.platform === 'instagram').status, 'failed')
  assert.equal(overlaid.publications.find(entry => entry.platform === 'instagram').failureCode, 'api_access_blocked')
  assert.equal(overlaid.publications.find(entry => entry.platform === 'facebook').status, 'failed')
  assert.equal(overlaid.platforms.find(entry => entry.platform === 'facebook').status, 'failed')
  assert.doesNotMatch(JSON.stringify(overlaid), /OAuthException|Page-Token|access[_ -]?token/i)
})

test('an older queue failure cannot overwrite a newer retry-ready staging target', () => {
  const payload = feed()
  payload.runs[0].status = 'partial'
  payload.runs[0].completedAt = null
  const instagram = payload.publications.find(entry => entry.platform === 'instagram')
  instagram.status = 'planned'
  instagram.updatedAt = '2026-07-21T13:06:00Z'
  const staged = mergeStagingFeed(previous(), normalizeStagingFeed(payload))
  const staleFailure = publicationFeed([publicationFeed().publications[0]])

  const overlaid = mergePublicationFeed(staged, normalizePublicationFeed(staleFailure))

  assert.equal(overlaid.publications.find(entry => entry.platform === 'instagram').status, 'planned')
  assert.equal(overlaid.publications.find(entry => entry.platform === 'instagram').updatedAt, '2026-07-21T13:06:00.000Z')
  assert.equal(overlaid.platforms.find(entry => entry.platform === 'instagram').status, 'planned')
  assert.equal(overlaid.runs[0].status, 'partial')
})

test('production queue association fails closed for duplicate runs or duplicate queue rows', () => {
  const staged = staleOperations()
  const duplicateRunId = 'upload-test-duplicate-content'
  staged.runs.push({ ...staged.runs[0], runId: duplicateRunId })
  staged.publications.push(...staged.publications.map(publication => ({ ...publication, runId: duplicateRunId })))
  const ambiguousRun = mergePublicationFeed(staged, normalizePublicationFeed(publicationFeed()))
  assert.equal(ambiguousRun.publications.find(entry => entry.runId === runId && entry.platform === 'facebook').status, 'planned')

  const oneRun = staleOperations()
  const duplicateQueue = publicationFeed([
    publicationFeed().publications[1],
    { ...publicationFeed().publications[1], updatedAt: '2026-07-21T13:05:02Z' },
  ])
  const ambiguousQueue = mergePublicationFeed(oneRun, normalizePublicationFeed(duplicateQueue))
  assert.equal(ambiguousQueue.publications.find(entry => entry.platform === 'facebook').status, 'planned')
})

const publicVideo = ({
  platform,
  contentId: videoContentId = contentId,
  description = 'Three flags. Keep your score.\n\n#FlagQuiz',
  publishedAt = '2026-07-21T13:00:00Z',
  status = platform === 'youtube' ? 'public' : 'published',
  title = `${platform} title`,
  url = {
    youtube: 'https://www.youtube.com/watch?v=abcdefghijk',
    instagram: 'https://www.instagram.com/reel/ABC123/',
    facebook: 'https://www.facebook.com/reel/123456789',
    tiktok: 'https://www.tiktok.com/@flaggenbande/video/123456789',
  }[platform],
} = {}) => ({
  platform,
  contentId: videoContentId,
  description,
  publishedAt,
  status,
  title,
  url,
})

const staleOperations = () => {
  const payload = feed()
  payload.runs[0].status = 'failed'
  payload.runs[0].completedAt = null
  payload.publications[0].status = 'planned'
  payload.publications[1].status = 'failed'
  payload.publications[2].status = 'planned'
  payload.publications[3].status = 'planned'
  return mergeStagingFeed(previous(), normalizeStagingFeed(payload))
}

test('authoritative public analytics proof wins over a failed production queue status', () => {
  const queued = mergePublicationFeed(staleOperations(), normalizePublicationFeed(publicationFeed()))
  assert.equal(queued.publications.find(entry => entry.platform === 'instagram').status, 'failed')
  const reconciled = reconcilePublishedSocial(queued, [
    publicVideo({ platform: 'youtube' }),
    publicVideo({ platform: 'instagram' }),
    publicVideo({ platform: 'facebook' }),
  ])
  assert.equal(reconciled.runs[0].status, 'completed')
  assert.equal(reconciled.publications.find(entry => entry.platform === 'instagram').status, 'published')
  assert.equal(reconciled.publications.find(entry => entry.platform === 'instagram').failureCode, null)
  assert.equal(reconciled.publications.find(entry => entry.platform === 'facebook').status, 'published')
})

test('direct content IDs reconcile only valid public proofs and refresh counts, titles, and times', () => {
  const videos = [
    publicVideo({ platform: 'youtube', title: 'Public YouTube title', publishedAt: '2026-07-21T13:01:00Z' }),
    publicVideo({ platform: 'instagram', publishedAt: '2026-07-21T13:02:00Z' }),
    publicVideo({ platform: 'facebook', publishedAt: '2026-07-21T13:03:00Z' }),
  ]
  const reconciled = reconcilePublishedSocial(staleOperations(), videos)

  assert.equal(reconciled.runs[0].status, 'completed')
  assert.equal(reconciled.runs[0].title, 'Public YouTube title')
  assert.equal(reconciled.runs[0].completedAt, '2026-07-21T13:03:00.000Z')
  assert.deepEqual(Object.fromEntries(reconciled.publications.map(entry => [entry.platform, entry.status])), {
    youtube: 'published',
    instagram: 'published',
    tiktok: 'not_configured',
    facebook: 'published',
  })
  const youtube = reconciled.publications.find(entry => entry.platform === 'youtube')
  assert.equal(youtube.title, 'Public YouTube title')
  assert.equal(youtube.publishedAt, '2026-07-21T13:01:00.000Z')
  assert.equal(youtube.publicUrl, 'https://www.youtube.com/watch?v=abcdefghijk')
  assert.equal(reconciled.platforms.find(entry => entry.platform === 'youtube').publications, 1)
  assert.equal(reconciled.platforms.find(entry => entry.platform === 'youtube').status, 'published')
  assert.equal(reconciled.platforms.find(entry => entry.platform === 'tiktok').status, 'not_configured')
})

test('YouTube without a content ID reconciles through one exact normalized Meta description', () => {
  const videos = [
    publicVideo({ platform: 'instagram', description: 'Three flags.\nKeep your score. #FlagQuiz' }),
    publicVideo({ platform: 'facebook', description: 'Three flags. Keep your score. #FlagQuiz' }),
    publicVideo({ platform: 'youtube', contentId: null, description: '  Three flags.   Keep your score. #FlagQuiz  ' }),
  ]
  const reconciled = reconcilePublishedSocial(staleOperations(), videos)
  assert.equal(reconciled.publications.find(entry => entry.platform === 'youtube').status, 'published')
  assert.equal(reconciled.runs[0].status, 'completed')
})

test('ambiguous exact descriptions fail closed for YouTube association', () => {
  const secondContentId = `flaggenbande-${'b'.repeat(64)}`
  const secondRunId = 'upload-test-second-video'
  const payload = feed()
  payload.runs[0].status = 'partial'
  payload.runs[0].completedAt = null
  payload.runs.push({
    ...payload.runs[0],
    runId: secondRunId,
    contentId: secondContentId,
    startedAt: '2026-07-21T10:00:00Z',
    completedAt: null,
    status: 'partial',
  })
  payload.publications.push(...payload.publications.map(entry => ({
    ...entry,
    runId: secondRunId,
    contentId: secondContentId,
  })))
  const operations = mergeStagingFeed(previous(), normalizeStagingFeed(payload))
  const description = 'Same exact upload copy'
  const videos = [
    publicVideo({ platform: 'instagram', description }),
    publicVideo({ platform: 'facebook', description }),
    publicVideo({ platform: 'instagram', contentId: secondContentId, description, url: 'https://www.instagram.com/reel/SECOND/' }),
    publicVideo({ platform: 'facebook', contentId: secondContentId, description, url: 'https://www.facebook.com/reel/987654321' }),
    publicVideo({ platform: 'youtube', contentId: null, description }),
  ]
  const reconciled = reconcilePublishedSocial(operations, videos)
  assert.ok(reconciled.publications.filter(entry => entry.platform === 'youtube').every(entry => entry.status !== 'published'))
  assert.ok(reconciled.runs.every(run => run.status !== 'completed'))
})

test('duplicate production runs for one content ID are never reconciled by guesswork', () => {
  const operations = staleOperations()
  const duplicateRunId = 'upload-test-retry-same-content'
  operations.runs.push({
    ...operations.runs[0],
    runId: duplicateRunId,
    startedAt: '2026-07-22T12:00:00.000Z',
    completedAt: null,
  })
  operations.publications.push(...operations.publications.map(publication => ({
    ...publication,
    runId: duplicateRunId,
    status: 'planned',
    updatedAt: '2026-07-22T12:00:00.000Z',
  })))
  const videos = ['youtube', 'instagram', 'facebook'].map(platform => publicVideo({ platform }))

  const reconciled = reconcilePublishedSocial(operations, videos)

  assert.ok(reconciled.runs.every(run => run.status !== 'completed'))
  assert.ok(reconciled.publications.every(publication => publication.status !== 'published'))
})

test('invalid status, timestamp, and cross-platform URLs never count as publication proof', () => {
  const videos = [
    publicVideo({ platform: 'youtube', status: 'private' }),
    publicVideo({ platform: 'instagram', publishedAt: 'not-a-date' }),
    publicVideo({ platform: 'facebook', url: 'https://www.instagram.com/reel/WRONG/' }),
  ]
  const reconciled = reconcilePublishedSocial(staleOperations(), videos)
  assert.equal(reconciled.runs[0].status, 'failed')
  assert.ok(reconciled.publications.every(entry => entry.status !== 'published'))
  assert.equal(reconciled.publications.find(entry => entry.platform === 'tiktok').status, 'planned')
})

test('quality approval remains mandatory even when all core platforms are public', () => {
  const operations = staleOperations()
  operations.runs[0].qualityStatus = 'failed'
  const videos = ['youtube', 'instagram', 'facebook'].map(platform => publicVideo({ platform }))
  const reconciled = reconcilePublishedSocial(operations, videos)
  assert.equal(reconciled.runs[0].status, 'failed')
  assert.ok(reconciled.publications.filter(entry => entry.platform !== 'tiktok').every(entry => entry.status === 'published'))
  assert.equal(reconciled.publications.find(entry => entry.platform === 'tiktok').status, 'planned')
})

test('collector uses a public HTTPS feed without authorization headers', async () => {
  const expectedUrl = 'https://staging.example.test/staging/feed'
  assert.equal(stagingFeedUrl({ UPLOAD_STAGING_API_URL: 'https://staging.example.test/private/path' }), expectedUrl)
  assert.equal(stagingFeedUrl({}), null)
  assert.throws(() => stagingFeedUrl({ UPLOAD_STAGING_FEED_URL: 'http://staging.example.test/staging/feed' }), /HTTPS/)

  let request
  const normalized = await fetchStagingFeed(expectedUrl, async (url, options) => {
    request = { url, options }
    return new Response(JSON.stringify(feed()), { status: 200, headers: { 'content-type': 'application/json' } })
  })
  assert.equal(request.url, expectedUrl)
  assert.deepEqual(request.options.headers, { accept: 'application/json' })
  assert.equal('authorization' in request.options.headers, false)
  assert.equal(normalized.publications.length, 4)
})

test('collector derives and fetches the public production feed without authorization headers', async () => {
  const expectedUrl = 'https://staging.example.test/publication/feed'
  assert.equal(publicationFeedUrl({ UPLOAD_STAGING_API_URL: 'https://staging.example.test/private/path' }), expectedUrl)
  assert.equal(publicationFeedUrl({ UPLOAD_STAGING_FEED_URL: 'https://staging.example.test/staging/feed' }), expectedUrl)
  assert.equal(publicationFeedUrl({ META_PUBLICATION_FEED_URL: expectedUrl }), expectedUrl)
  assert.throws(() => publicationFeedUrl({ META_PUBLICATION_FEED_URL: 'http://staging.example.test/publication/feed' }), /HTTPS/)

  let request
  const normalized = await fetchPublicationFeed(expectedUrl, async (url, options) => {
    request = { url, options }
    return new Response(JSON.stringify(publicationFeed()), { status: 200, headers: { 'content-type': 'application/json' } })
  })
  assert.equal(request.url, expectedUrl)
  assert.deepEqual(request.options.headers, { accept: 'application/json' })
  assert.equal('authorization' in request.options.headers, false)
  assert.equal(normalized.publications.length, 2)
})
