import assert from 'node:assert/strict'
import test from 'node:test'
import {
  assertNonPublishingReceipt,
  assertSafeYouTubeInsert,
  buildStagingPlan,
  facebookDraftFinishPayload,
  instagramContainerPayload,
  publicStagingSnapshot,
  resolveExecutionErrors,
  validateStagingApiBaseUrl,
  validatePlatformMetadata,
  validateStagingRegistration,
} from '../scripts/upload-staging-core.mjs'

const metadata = {
  youtubeTitle: 'The 0.14% Flag Challenge #FlagQuiz #Flags #Geography #Quiz #Shorts',
  description: 'Five flags. Keep your score—no spoilers.\n\n#FlagQuiz #GeographyQuiz #GuessTheFlag #Flaggenbande #QuizChallenge\n\nhttps://apps.apple.com/us/app/flaggenbande/id6778848528',
  language: 'en',
  forbiddenAnswerTerms: ['Brazil', 'Sweden'],
}

const basePlanInput = {
  runId: 'test-run',
  assetSha256: 'a'.repeat(64),
  metadata,
  accountFingerprints: { youtube: 'yt', instagram: 'ig', facebook: 'fb', tiktok: 'tt' },
  createdAt: '2026-07-21T08:00:00Z',
  manualTikTokReceipt: {
    confirmedManualUpload: true,
    accountFingerprint: 'tt',
    confirmedAt: '2026-07-21T08:00:00Z',
  },
}

test('platform copy has five case-insensitively unique hashtags and does not leak whole answers', () => {
  const result = validatePlatformMetadata(metadata)
  assert.equal(result.hashtags.length, 5)
  assert.equal('forbiddenAnswerTerms' in result, false)
  assert.throws(() => validatePlatformMetadata({
    ...metadata,
    description: metadata.description.replace('\n\nhttps://apps.apple.com', '\nBrazil\n\nhttps://apps.apple.com'),
  }), /Quizantwort/)
  assert.doesNotThrow(() => validatePlatformMetadata({ ...metadata, forbiddenAnswerTerms: ['Oman'], description: metadata.description.replace('Five', 'Woman-friendly five') }))
  assert.throws(() => validatePlatformMetadata({
    ...metadata,
    youtubeTitle: 'Quiz #FlagQuiz #flagquiz #Geography #Quiz #Shorts',
  }), /exakt fünf/)
  assert.throws(() => validatePlatformMetadata({ ...metadata, description: `x${'a'.repeat(2200)}\n${metadata.description}` }), /2\.200/)
})

test('plan creates stable provider/account keys that do not change for QA-only answer terms', () => {
  const first = buildStagingPlan(basePlanInput)
  const second = buildStagingPlan({
    ...basePlanInput,
    metadata: { ...metadata, forbiddenAnswerTerms: ['Brazil', 'Sweden', 'Estonia'] },
  })
  assert.deepEqual(first.targets.map(target => target.idempotencyKey), second.targets.map(target => target.idempotencyKey))
  assert.equal(new Set(first.targets.map(target => target.idempotencyKey)).size, 4)
  assert.equal(first.publicationAuthorized, false)
  assert.equal(first.targets.find(target => target.platform === 'tiktok').workflowState, 'manual_uploaded')
  assert.equal(first.targets.find(target => target.platform === 'tiktok').visibilityState, 'unknown')
  assert.equal(JSON.stringify(first).includes('Brazil'), false)
})

test('staging API is HTTPS-host-pinned and registration confirms an unchanged non-public plan', () => {
  assert.equal(
    validateStagingApiBaseUrl('https://safe-worker.example.workers.dev', 'safe-worker.example.workers.dev'),
    'https://safe-worker.example.workers.dev',
  )
  assert.throws(() => validateStagingApiBaseUrl('http://safe-worker.example.workers.dev'), /HTTPS/)
  assert.throws(() => validateStagingApiBaseUrl('https://wrong.example.test', 'safe-worker.example.workers.dev'), /freigegebenen/)

  const plan = buildStagingPlan(basePlanInput)
  const registration = {
    schemaVersion: 1,
    lane: 'non-publishing',
    runId: plan.runId,
    contentId: plan.contentId,
    status: 'partial',
    qualityStatus: 'passed',
    targets: plan.targets.map((target, index) => ({
      platform: target.platform,
      mode: target.mode,
      idempotencyKey: String(index + 1).repeat(64),
      transportState: target.transportState,
      visibilityState: target.visibilityState,
      workflowState: target.workflowState,
      remoteObjectId: null,
      providerStatus: null,
      publishedAt: null,
      scheduledFor: null,
      publicUrl: null,
    })),
  }
  assert.equal(validateStagingRegistration(plan, registration), registration)
  assert.throws(() => validateStagingRegistration(plan, {
    ...registration,
    targets: registration.targets.map((target, index) => index === 0 ? { ...target, remoteObjectId: 'unexpected' } : target),
  }), /unerwartet/)
  assert.throws(() => validateStagingRegistration(plan, {
    ...registration,
    targets: registration.targets.map(target => ({ ...target, idempotencyKey: 'f'.repeat(64) })),
  }), /eindeutigen/)
})

test('manual TikTok confirmation requires account and timestamp evidence', () => {
  assert.throws(() => buildStagingPlan({
    ...basePlanInput,
    manualTikTokReceipt: { confirmedManualUpload: true },
  }), /accountFingerprint/)
  assert.throws(() => buildStagingPlan({
    ...basePlanInput,
    manualTikTokReceipt: { confirmedManualUpload: true, accountFingerprint: 'tt', confirmedAt: 'not-a-date' },
  }), /Zeitpunkt/)
  assert.throws(() => buildStagingPlan({
    ...basePlanInput,
    manualTikTokReceipt: { confirmedManualUpload: true, accountFingerprint: 'other-account', confirmedAt: '2026-07-21T08:00:00Z' },
  }), /Zielkonto/)
})

test('a successful retry resolves only the matching active error without losing history', () => {
  const execution = {
    errors: [
      { platform: 'meta', message: 'temporary' },
      { platform: 'youtube', message: 'still active' },
    ],
  }
  resolveExecutionErrors(execution, 'meta', '2026-07-21T09:30:00.000Z')
  assert.deepEqual(execution.errors, [{ platform: 'youtube', message: 'still active' }])
  assert.deepEqual(execution.resolvedErrors, [{
    platform: 'meta', message: 'temporary', resolvedAt: '2026-07-21T09:30:00.000Z',
  }])
})

test('provider payloads cannot accidentally publish', () => {
  assert.equal(assertSafeYouTubeInsert({ status: { privacyStatus: 'private' } }).status.privacyStatus, 'private')
  assert.throws(() => assertSafeYouTubeInsert({ status: { privacyStatus: 'public' } }), /ausschließlich privat/)
  assert.throws(() => assertSafeYouTubeInsert({ status: { privacyStatus: 'private', publishAt: '2026-07-22T10:00:00Z' } }), /Veröffentlichungszeitpunkt/)
  assert.equal(facebookDraftFinishPayload({ videoId: '1', title: 'Quiz', description: 'Caption' }).video_state, 'DRAFT')
  const instagram = instagramContainerPayload({ mediaUrl: 'https://example.com/video.mp4', description: 'Caption' })
  assert.equal(instagram.media_type, 'REELS')
  assert.equal('media_publish' in instagram, false)
})

test('remote receipts reject every visible, scheduled or manual TikTok outcome', () => {
  const safe = {
    platform: 'youtube', workflowState: 'private_uploaded', transportState: 'ready', visibilityState: 'non_public',
    remoteObjectId: 'youtube-private-id', providerStatus: 'private', confirmedAt: '2026-07-21T08:01:00Z',
    publishedAt: null, scheduledFor: null, publicUrl: null,
  }
  assert.equal(assertNonPublishingReceipt(safe), safe)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, visibilityState: 'public' }), /Sichtbarkeit/)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, scheduledFor: '2026-07-22T10:00:00Z' }), /Veröffentlichung/)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, platform: 'tiktok', workflowState: 'manual_uploaded' }), /Unerlaubter/)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, transportState: 'failed' }), /transportState/)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, providerStatus: 'public' }), /Providerstatus/)
  assert.throws(() => assertNonPublishingReceipt({ ...safe, remoteObjectId: null }), /Remote-Objekt-ID/)
})

test('public snapshot reflects receipts, not optimistic plan values', () => {
  const plan = buildStagingPlan(basePlanInput)
  const planOnly = publicStagingSnapshot({ plan, execution: { receipts: [...plan.manualReceipts] } })
  assert.equal(planOnly.publications.find(item => item.platform === 'youtube').status, 'planned')
  assert.equal(planOnly.publications.find(item => item.platform === 'facebook').status, 'planned')
  assert.equal(planOnly.publications.find(item => item.platform === 'tiktok').status, 'manual_uploaded')

  const receipts = [
    ...plan.manualReceipts,
    { platform: 'youtube', workflowState: 'private_uploaded', transportState: 'ready', visibilityState: 'non_public', remoteObjectId: 'yt', providerStatus: 'private', confirmedAt: '2026-07-21T08:01:00Z' },
    { platform: 'instagram', workflowState: 'container_unpublished', transportState: 'ready', visibilityState: 'non_public', remoteObjectId: 'ig', providerStatus: 'FINISHED', confirmedAt: '2026-07-21T08:02:00Z' },
    { platform: 'facebook', workflowState: 'draft', transportState: 'ready', visibilityState: 'non_public', remoteObjectId: 'fb', providerStatus: 'DRAFT', confirmedAt: '2026-07-21T08:03:00Z' },
  ]
  const completed = publicStagingSnapshot({ plan, execution: { receipts, completedAt: '2026-07-21T08:05:00Z' } })
  assert.equal(completed.runs[0].status, 'completed')
  assert.equal(completed.publications.find(item => item.platform === 'youtube').status, 'private')
  assert.equal(completed.publications.find(item => item.platform === 'instagram').status, 'container_unpublished')
  assert.equal(completed.publications.find(item => item.platform === 'facebook').status, 'draft')
  const serialized = JSON.stringify(completed)
  assert.doesNotMatch(serialized, /Brazil|Sweden|\/Users\//)
  assert.ok(completed.publications.every(item => item.publicUrl === null && item.publishedAt === null))
})
