import assert from 'node:assert/strict'
import { afterEach, describe, test } from 'node:test'

import {
  addDateKeyDays,
  berlinDateKey,
  berlinDayBounds,
  buildUserStatsRecords,
  canonicalChallenge,
  challengeRecord,
  challengeRecordMatches,
  CloudKitClient,
  deterministicCountryOrder,
  deriveTrophyStandings,
  immutableLeaderboardRecordName,
  maintainChallenges,
  maintainWinners,
  nicknameKeyCandidates,
  parseArguments,
  rankLeaderboardEntries,
  readCanonicalCountryCodes,
  stableHash,
  trustedWinnerEvent,
  validateAttemptAndLeaderboard,
  winnerAwardEligibleAt,
} from './cloudkit-daily-maintenance.mjs'

const originalWriteGate = process.env.CLOUDKIT_DAILY_WRITES_ENABLED

afterEach(() => {
  if (originalWriteGate === undefined) delete process.env.CLOUDKIT_DAILY_WRITES_ENABLED
  else process.env.CLOUDKIT_DAILY_WRITES_ENABLED = originalWriteGate
})

function fields(values) {
  return Object.fromEntries(Object.entries(values).map(([key, value]) => [key, { value }]))
}

describe('CloudKit server identity', () => {
  test('accepts the privacy-preserving lookupInfo response from users/caller', async () => {
    const client = new CloudKitClient({ keyId: 'test', privateKey: 'unused' })
    client.request = async () => ({ users: [{ lookupInfo: { userRecordName: '_developer' } }] })
    assert.equal(await client.callerRecordName(), '_developer')
  })

  test('falls back to users/current when a server key has no caller identity', async () => {
    const client = new CloudKitClient({ keyId: 'test', privateKey: 'unused' })
    const operations = []
    client.request = async operation => {
      operations.push(operation)
      return operation === 'users/caller' ? { users: [{}] } : { userRecordName: '_developer' }
    }
    assert.equal(await client.callerRecordName(), '_developer')
    assert.deepEqual(operations, ['users/caller', 'users/current'])
  })
})

function serverRecord(record, owner, createdAt, modifiedAt = createdAt) {
  return {
    ...record,
    created: { timestamp: createdAt, userRecordName: owner },
    modified: { timestamp: modifiedAt, userRecordName: owner },
  }
}

function validDailyFixture({ dateKey = '2026-07-20', mode = 'daily_flaggenrun', owner = 'cloud_owner' } = {}) {
  const challenge = { mode, dateKey, flagOrder: ['DE', 'FR'] }
  const userId = 'gc_player_123'
  const displayName = 'Spieler'
  const createdAt = berlinDayBounds(dateKey).start + 12 * 60 * 60 * 1_000
  const modifiedAt = createdAt + 60 * 1_000
  const answers = [
    {
      id: '11111111-1111-1111-1111-111111111111',
      countryCode: 'DE',
      countryName: 'Deutschland',
      submittedAnswer: 'Deutschland',
      detectedCountryName: 'Deutschland',
      wasCorrect: true,
      responseTime: 1,
      pointsAwarded: 212,
    },
    {
      id: '22222222-2222-2222-2222-222222222222',
      countryCode: 'FR',
      countryName: 'Frankreich',
      submittedAnswer: 'x',
      detectedCountryName: null,
      wasCorrect: false,
      responseTime: 1,
      pointsAwarded: 0,
    },
  ]
  const attempt = serverRecord({
    recordName: `${mode}_${dateKey}_${userId}_attempt_1`,
    recordType: 'DailyAttempt',
    fields: fields({
      dateKey,
      mode,
      userId,
      displayName,
      attemptNumber: 1,
      score: 187,
      correctCount: 1,
      wrongCount: 1,
      playedRounds: 2,
      duration: 60,
      remainingTime: 0,
      completed: true,
      aborted: false,
      integrityVersion: 2,
      inputHistoryData: Buffer.from(JSON.stringify(answers)).toString('base64'),
    }),
  }, owner, createdAt, modifiedAt)
  const leaderboardRecord = serverRecord({
    recordName: immutableLeaderboardRecordName(mode, dateKey, userId, 1),
    recordType: 'DailyLeaderboardEntry',
    fields: fields({
      dateKey,
      mode,
      userId,
      displayName,
      bestScore: 187,
      bestAttemptNumber: 1,
      correctCount: 1,
      wrongCount: 1,
      duration: 60,
      remainingTime: 0,
      completedAt: modifiedAt,
    }),
  }, owner, modifiedAt, modifiedAt + 1_000)
  const playerRecord = serverRecord({
    recordName: userId,
    recordType: 'PlayerStats',
    fields: fields({ playerName: displayName, gameCenterPlayerID: 'player:123', gameCenterAlias: displayName }),
  }, owner, createdAt - 1_000)
  return { challenge, attempt, leaderboardRecord, playerRecord, userId, displayName, createdAt, modifiedAt }
}

class MemoryCloudKitClient {
  constructor(records, caller, now) {
    this.records = new Map(records.map(record => [record.recordName, record]))
    this.caller = caller
    this.now = now
    this.replacements = []
  }

  async lookupRecords(names) {
    return new Map(names.filter(name => this.records.has(name)).map(name => [name, this.records.get(name)]))
  }

  async queryRecords(recordType, filterBy) {
    return [...this.records.values()].filter(record => record.recordType === recordType && filterBy.every(filter => record.fields?.[filter.fieldName]?.value === filter.fieldValue.value))
  }

  async createRecord(record) {
    if (this.records.has(record.recordName)) throw new Error('record exists')
    const saved = serverRecord(structuredClone(record), this.caller, this.now, this.now)
    this.records.set(saved.recordName, saved)
    return saved
  }

  async forceReplaceRecords(records) {
    for (const record of records) {
      const existing = this.records.get(record.recordName)
      const saved = serverRecord(structuredClone(record), existing?.created?.userRecordName ?? this.caller, existing?.created?.timestamp ?? this.now, this.now)
      this.records.set(saved.recordName, saved)
      this.replacements.push(saved)
    }
  }
}

describe('Europe/Berlin calendar and deterministic challenge', () => {
  test('handles winter, summer, and both DST transition days', () => {
    assert.equal(berlinDateKey(new Date('2026-07-21T22:00:00Z')), '2026-07-22')
    assert.equal(berlinDayBounds('2026-07-22').endExclusive - berlinDayBounds('2026-07-22').start, 24 * 60 * 60 * 1_000)
    assert.equal(berlinDayBounds('2026-03-29').endExclusive - berlinDayBounds('2026-03-29').start, 23 * 60 * 60 * 1_000)
    assert.equal(berlinDayBounds('2026-10-25').endExclusive - berlinDayBounds('2026-10-25').start, 25 * 60 * 60 * 1_000)
    assert.equal(addDateKeyDays('2026-03-29', 1), '2026-03-30')
  })

  test('matches the Swift SplitMix64/FNV challenge order', async () => {
    const codes = await readCanonicalCountryCodes()
    assert.equal(codes.length, 193)
    assert.equal(stableHash('daily_flaggenrun_2026-07-22'), 209031892737460368n)
    assert.deepEqual(
      deterministicCountryOrder(codes, 'daily_flaggenrun_2026-07-22').slice(0, 12),
      ['CL', 'IL', 'SK', 'JM', 'PL', 'SO', 'MX', 'GH', 'CO', 'FR', 'NI', 'FM'],
    )
  })
})

describe('attempt and leaderboard verification', () => {
  test('accepts a complete version-2 run with matching CloudKit ownership', () => {
    const fixture = validDailyFixture()
    assert.equal(validateAttemptAndLeaderboard(fixture).valid, true)
  })

  test('rejects legacy evidence, owner mismatch, mutable IDs, and forged order', () => {
    const legacy = validDailyFixture()
    legacy.attempt.fields.integrityVersion.value = 1
    assert.equal(validateAttemptAndLeaderboard(legacy).reason, 'legacy-or-missing-full-evidence')

    const wrongOwner = validDailyFixture()
    wrongOwner.playerRecord.created.userRecordName = 'someone_else'
    assert.equal(validateAttemptAndLeaderboard(wrongOwner).reason, 'cloudkit-owner-mismatch')

    const mutable = validDailyFixture()
    mutable.leaderboardRecord.recordName = `${mutable.challenge.mode}_${mutable.challenge.dateKey}_${mutable.userId}`
    assert.equal(validateAttemptAndLeaderboard(mutable).reason, 'mutable-or-mismatched-leaderboard-id')

    const wrongOrder = validDailyFixture()
    const decoded = JSON.parse(Buffer.from(wrongOrder.attempt.fields.inputHistoryData.value, 'base64').toString('utf8'))
    decoded[0].countryCode = 'FR'
    wrongOrder.attempt.fields.inputHistoryData.value = Buffer.from(JSON.stringify(decoded)).toString('base64')
    assert.equal(validateAttemptAndLeaderboard(wrongOrder).reason, 'invalid-daily-order')
  })

  test('binds custom display names to PlayerStats and a same-owner NicknameClaim', () => {
    const fixture = validDailyFixture()
    const customName = 'Änne Test'
    fixture.attempt.fields.displayName.value = customName
    fixture.leaderboardRecord.fields.displayName.value = customName
    fixture.playerRecord.fields.playerName.value = customName
    assert.deepEqual(nicknameKeyCandidates(customName), ['anne_test'])

    const claim = serverRecord({
      recordName: 'nickname_anne_test',
      recordType: 'NicknameClaim',
      fields: fields({ nickname: customName, ownerRecordName: fixture.userId }),
    }, 'cloud_owner', fixture.createdAt - 2_000)
    assert.equal(validateAttemptAndLeaderboard({ ...fixture, nicknameClaims: [claim] }).valid, true)

    claim.fields.ownerRecordName.value = 'gc_other_player'
    assert.equal(validateAttemptAndLeaderboard({ ...fixture, nicknameClaims: [claim] }).reason, 'nickname-claim-owner-mismatch')
    assert.equal(validateAttemptAndLeaderboard(fixture).reason, 'missing-nickname-claim')
  })

  test('allows the legacy Game Center alias fallback but still requires the same PlayerStats owner', () => {
    const fixture = validDailyFixture()
    const alias = 'Game Center Hero'
    fixture.attempt.fields.displayName.value = alias
    fixture.leaderboardRecord.fields.displayName.value = alias
    fixture.playerRecord.fields.playerName.value = alias
    fixture.playerRecord.fields.gameCenterPlayerID = { value: 'player:123' }
    fixture.playerRecord.fields.gameCenterAlias = { value: alias }
    assert.equal(validateAttemptAndLeaderboard(fixture).valid, true)

    fixture.playerRecord.fields.gameCenterPlayerID.value = 'someone:else'
    assert.equal(validateAttemptAndLeaderboard(fixture).reason, 'game-center-profile-mismatch')
    fixture.playerRecord.fields.gameCenterPlayerID.value = 'player:123'
    fixture.playerRecord.created.userRecordName = 'other_cloud_owner'
    assert.equal(validateAttemptAndLeaderboard(fixture).reason, 'cloudkit-owner-mismatch')
  })

  test('uses a newly claimed PlayerStats name when a player renames after the run', () => {
    const fixture = validDailyFixture()
    const currentName = 'Neue Änne'
    fixture.playerRecord.fields.playerName.value = currentName
    const claim = serverRecord({
      recordName: 'nickname_neue_anne',
      recordType: 'NicknameClaim',
      fields: fields({ nickname: currentName, ownerRecordName: fixture.userId }),
    }, 'cloud_owner', fixture.createdAt + 1_000)
    const result = validateAttemptAndLeaderboard({ ...fixture, nicknameClaims: [claim] })
    assert.equal(result.valid, true)
    assert.equal(result.entry.displayName, currentName)
    assert.equal(fixture.leaderboardRecord.fields.displayName.value, 'Spieler')
  })

  test('uses the same stable tie-break order as the app', () => {
    const base = { bestScore: 100, correctCount: 1, remainingTime: 0, duration: 60 }
    const ranked = rankLeaderboardEntries([
      { ...base, userId: 'b' },
      { ...base, userId: 'a' },
      { ...base, userId: 'c', bestScore: 101 },
    ])
    assert.deepEqual(ranked.map(entry => entry.userId), ['c', 'a', 'b'])
  })
})

describe('idempotent maintenance', () => {
  test('derives stable trophy ranks and uninterrupted rankOneSinceDate snapshots', () => {
    const event = (dateKey, mode, userId) => ({
      dateKey,
      mode,
      userId,
      displayName: userId,
      recordName: `${mode}_${dateKey}_winner`,
    })
    const throughDayFour = [
      event('2026-07-01', 'daily_flaggenrun', 'a'),
      event('2026-07-02', 'daily_flaggenrun', 'b'),
      event('2026-07-03', 'daily_staedterun', 'b'),
      // A ties B on trophies, but B reached the total a day earlier and stays
      // number one without resetting its uninterrupted lead.
      event('2026-07-04', 'daily_staedterun', 'a'),
    ]
    const first = deriveTrophyStandings(throughDayFour)
    assert.deepEqual(first.map(standing => [standing.userId, standing.rank]), [['b', 1], ['a', 2]])
    assert.equal(first[0].rankOneSinceDate, berlinDayBounds('2026-07-03').start)
    assert.equal(first[1].rankOneSinceDate, null)
    const firstRecords = buildUserStatsRecords(throughDayFour, Date.parse('2026-07-05T00:00:00Z'))
    assert.equal(firstRecords.find(record => record.fields.userId.value === 'b').fields.rankOneSinceDate.value, berlinDayBounds('2026-07-03').start)
    assert.equal('rankOneSinceDate' in firstRecords.find(record => record.fields.userId.value === 'a').fields, false)

    const afterTakeover = deriveTrophyStandings([
      ...throughDayFour,
      // A takes over after a calendar gap. Days without a winner never break
      // or fabricate a lead snapshot.
      event('2026-07-06', 'daily_flaggenrun', 'a'),
    ])
    assert.deepEqual(afterTakeover.map(standing => [standing.userId, standing.rank]), [['a', 1], ['b', 2]])
    assert.equal(afterTakeover[0].rankOneSinceDate, berlinDayBounds('2026-07-06').start)
    assert.equal(afterTakeover[0].lastTrophyDate, berlinDayBounds('2026-07-06').start)
    const takeoverRecords = buildUserStatsRecords([...throughDayFour, event('2026-07-06', 'daily_flaggenrun', 'a')], Date.parse('2026-07-07T00:00:00Z'))
    assert.equal('rankOneSinceDate' in takeoverRecords.find(record => record.fields.userId.value === 'b').fields, false)
    assert.equal(takeoverRecords.find(record => record.fields.userId.value === 'a').fields.rankOneSinceDate.value, berlinDayBounds('2026-07-06').start)
  })

  test('creates canonical challenges once and rejects non-server records', async () => {
    const caller = 'server_user'
    const now = Date.parse('2026-07-22T13:00:00Z')
    const client = new MemoryCloudKitClient([], caller, now)
    const countryCodes = await readCanonicalCountryCodes()
    const dateKeys = ['2026-07-23']
    const first = await maintainChallenges({ client, apply: true, dateKeys, countryCodes, caller })
    const second = await maintainChallenges({ client, apply: true, dateKeys, countryCodes, caller })
    assert.equal(first.created, 2)
    assert.equal(second.unchanged, 2)

    const challenge = canonicalChallenge('daily_flaggenrun', dateKeys[0], countryCodes)
    assert.equal(challengeRecordMatches(client.records.get(challenge.recordName), challenge, caller), true)
    const forged = serverRecord(challengeRecord(challenge), 'app_user', now)
    assert.equal(challengeRecordMatches(forged, challenge, caller), false)
  })

  test('creates one trusted winner, then rebuilds UserStats without double-awarding', async () => {
    const caller = 'server_user'
    const now = Date.parse('2026-07-22T13:00:00Z')
    const fixture = validDailyFixture()
    const client = new MemoryCloudKitClient([fixture.attempt, fixture.leaderboardRecord, fixture.playerRecord], caller, now)
    const countryCodes = await readCanonicalCountryCodes()
    // Use the fixture order for this run while retaining the production
    // catalogue for every other mode/date in the maintenance function.
    const productionChallenge = canonicalChallenge(fixture.challenge.mode, fixture.challenge.dateKey, countryCodes)
    const answers = JSON.parse(Buffer.from(fixture.attempt.fields.inputHistoryData.value, 'base64').toString('utf8'))
    answers[0].countryCode = productionChallenge.flagOrder[0]
    answers[1].countryCode = productionChallenge.flagOrder[1]
    fixture.attempt.fields.inputHistoryData.value = Buffer.from(JSON.stringify(answers)).toString('base64')

    const first = await maintainWinners({ client, apply: true, dateKeys: [fixture.challenge.dateKey], countryCodes, caller, now })
    const second = await maintainWinners({ client, apply: true, dateKeys: [fixture.challenge.dateKey], countryCodes, caller, now })
    assert.equal(first.created, 1)
    assert.equal(second.unchanged, 1)
    assert.equal(second.created, 0)
    const winner = client.records.get(`${fixture.challenge.mode}_${fixture.challenge.dateKey}_winner`)
    assert.ok(trustedWinnerEvent(winner, caller))
    const stats = client.records.get(`userstats_${fixture.userId}`)
    assert.equal(stats.fields.dailyFlaggenrunTrophies.value, 1)
    assert.equal(stats.fields.totalTrophies.value, 1)
    assert.equal(stats.fields.trophyRank.value, 1)
    assert.equal(stats.fields.lastTrophyDate.value, berlinDayBounds(fixture.challenge.dateKey).start)
    assert.equal(stats.fields.rankOneSinceDate.value, berlinDayBounds(fixture.challenge.dateKey).start)
    assert.equal(stats.fields.awardedTrophyIDs.value, winner.recordName)
  })
})

describe('write gate', () => {
  test('defaults to dry-run and requires an explicit security acknowledgement for writes', () => {
    delete process.env.CLOUDKIT_DAILY_WRITES_ENABLED
    assert.equal(parseArguments([]).apply, false)
    assert.throws(() => parseArguments(['--apply']), /CLOUDKIT_DAILY_WRITES_ENABLED=true/)
    process.env.CLOUDKIT_DAILY_WRITES_ENABLED = 'true'
    assert.equal(parseArguments(['--apply', '--environment=development']).apply, true)
  })

  test('winner eligibility includes the two-hour submission window and index delay', () => {
    const key = '2026-07-20'
    assert.equal(winnerAwardEligibleAt(key), berlinDayBounds(key).endsAt + 2 * 60 * 60 * 1_000 + 15 * 60 * 1_000)
  })
})
