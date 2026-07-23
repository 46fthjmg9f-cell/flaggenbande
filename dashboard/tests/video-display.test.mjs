import assert from 'node:assert/strict'
import test from 'node:test'
import { HIDDEN_REFRESH_MS, VISIBLE_REFRESH_MS, adaptiveRefreshDelay } from '../src/useAdaptiveRefresh.ts'
import {
  calendarVisualStatus,
  chooseCalendarSlot,
  displayReleaseLabel,
  displayVideoName,
  mergeCalendarPlatformState,
  mergeReleaseDisplayMetadata,
  stableCalendarIdentity,
} from '../src/videoDisplay.ts'

test('release labels gain exactly one X only after a final approval', () => {
  assert.equal(displayReleaseLabel({ releaseLabel: '2207.07' }), '2207.07')
  assert.equal(displayReleaseLabel({ releaseLabel: '2207.07', videoApproved: true }), '2207.07X')
  assert.equal(displayReleaseLabel({ releaseLabel: '2207.07X', finalReleaseApproved: true }), '2207.07X')
  assert.equal(displayReleaseLabel({ releaseLabel: null, videoApproved: true }), null)
})

test('video display names use the release label without duplicating an existing prefix', () => {
  assert.equal(displayVideoName({ releaseLabel: '2207.07', title: 'Flaggenquiz', videoApproved: true }), '2207.07X · Flaggenquiz')
  assert.equal(displayVideoName({ releaseLabel: '2207.07', title: '2207.07 · Flaggenquiz', videoApproved: true }), '2207.07X · Flaggenquiz')
  assert.equal(displayVideoName({ title: 'Flaggenquiz' }), 'Flaggenquiz')
})

test('known historical releases retain their verified numbering', () => {
  assert.equal(
    displayVideoName({
      runId: 'upload-gameshow-v7-professional-cold-open-experiment',
      contentId: 'flaggenbande-adeebf2787e0b5a8c64b924bc1ff6cb02504520b3af1b195993ada6ce35d95f9',
      title: 'Nur echte Gangster schaffen 3/3',
    }),
    '2107.01X · Nur echte Gangster schaffen 3/3',
  )
  assert.equal(
    displayVideoName({
      runId: 'upload-video-e5866d048c7f5cf134ccaaac-aligned-v3',
      title: 'Video',
    }),
    '2207.05 · Video',
  )
})

test('calendar colors map publication states consistently', () => {
  assert.equal(calendarVisualStatus('published'), 'published')
  for (const status of ['ready', 'scheduled', 'private', 'draft', 'container_unpublished', 'upload_ready', 'manual_uploaded']) {
    assert.equal(calendarVisualStatus(status), 'ready')
  }
  assert.equal(calendarVisualStatus('processing'), 'processing')
  assert.equal(calendarVisualStatus('failed'), 'failed')
  assert.equal(calendarVisualStatus('planned'), 'ready')
})

test('new retry-ready state supersedes only an older failure while publication proof remains final', () => {
  assert.deepEqual(
    mergeCalendarPlatformState(
      { status: 'failed', updatedAt: '2026-07-23T12:00:00Z' },
      { status: 'ready', updatedAt: '2026-07-23T12:05:00Z' },
    ),
    { status: 'ready', updatedAt: '2026-07-23T12:05:00Z' },
  )
  assert.deepEqual(
    mergeCalendarPlatformState(
      { status: 'failed', updatedAt: '2026-07-23T12:05:00Z' },
      { status: 'ready', updatedAt: '2026-07-23T12:00:00Z' },
    ),
    { status: 'failed', updatedAt: '2026-07-23T12:05:00Z' },
  )
  assert.deepEqual(
    mergeCalendarPlatformState(
      { status: 'published', publicUrl: 'https://example.test/video' },
      { status: 'ready', updatedAt: '2026-07-23T12:05:00Z' },
      true,
    ),
    { status: 'published', publicUrl: 'https://example.test/video' },
  )
})

test('calendar merge preserves defined release metadata when a source omits it', () => {
  assert.deepEqual(
    mergeReleaseDisplayMetadata(
      { releaseLabel: '2307.04', videoApproved: true, finalReleaseApproved: true },
      { releaseLabel: undefined, videoApproved: undefined, finalReleaseApproved: undefined },
    ),
    { releaseLabel: '2307.04', videoApproved: true, finalReleaseApproved: true },
  )
  assert.deepEqual(
    mergeReleaseDisplayMetadata(
      { releaseLabel: '2307.04', videoApproved: true, finalReleaseApproved: true },
      { releaseLabel: '2307.05', videoApproved: false, finalReleaseApproved: false },
    ),
    { releaseLabel: '2307.05', videoApproved: false, finalReleaseApproved: false },
  )
})

test('calendar identity is stable across platform timestamps', () => {
  const first = stableCalendarIdentity({ contentId: 'content-1', runId: 'run-1', id: 'platform-a' })
  const second = stableCalendarIdentity({ contentId: 'content-1', runId: 'run-1', id: 'platform-b' })
  assert.equal(first, second)
  assert.notEqual(first, stableCalendarIdentity({ contentId: 'content-1', runId: 'run-2' }))
})

test('a confirmed publication never moves an existing scheduled calendar slot', () => {
  assert.deepEqual(
    chooseCalendarSlot(
      ['2026-07-23T18:00:00.000Z'],
      ['2026-07-23T18:04:11.000Z', '2026-07-23T18:06:02.000Z'],
    ),
    { scheduledAt: '2026-07-23T18:00:00.000Z', slotKind: 'scheduled' },
  )
  assert.deepEqual(
    chooseCalendarSlot([], ['2026-07-23T18:04:11.000Z']),
    { scheduledAt: '2026-07-23T18:04:11.000Z', slotKind: 'published' },
  )
})

test('adaptive refresh uses 15 seconds while visible and 60 seconds while hidden', () => {
  assert.equal(adaptiveRefreshDelay(false), VISIBLE_REFRESH_MS)
  assert.equal(adaptiveRefreshDelay(true), HIDDEN_REFRESH_MS)
})
