#!/usr/bin/env node

import crypto from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

export const BERLIN_TIME_ZONE = 'Europe/Berlin'
export const MODES = ['daily_flaggenrun', 'daily_staedterun']
export const FULL_EVIDENCE_VERSION = 2
export const MAX_ATTEMPTS = 2
export const RUN_DURATION = 60
export const MAINTENANCE_START_DATE = '2026-01-01'

const API_ORIGIN = 'https://api.apple-cloudkit.com'
const UINT64_MASK = (1n << 64n) - 1n
const HASH_OFFSET = 14_695_981_039_346_656_037n
const HASH_PRIME = 1_099_511_628_211n
const RANDOM_INCREMENT = 0x9E37_79B9_7F4A_7C15n
const RANDOM_MULTIPLIER_1 = 0xBF58_476D_1CE4_E5B9n
const RANDOM_MULTIPLIER_2 = 0x94D0_49BB_1331_11EBn
const MAXIMUM_POINTS_PER_CORRECT_ANSWER = 234
const MINIMUM_ELAPSED_SECONDS_PER_TRANSITION = 0.18
const TIMER_TOLERANCE = 1.1
const CLOUD_TIMESTAMP_TOLERANCE_MS = 2_000
const COUNTRY_SOURCE = new URL('../SpassmitFlaggen/FlagCatalog.swift', import.meta.url)

function valueField(value) {
  return { value }
}

export function cloudField(record, key) {
  return record?.fields?.[key]?.value
}

export function serverTimestamp(record, kind) {
  const value = Number(record?.[kind]?.timestamp)
  return Number.isFinite(value) ? value : null
}

export function serverUser(record, kind) {
  const value = record?.[kind]?.userRecordName
  return typeof value === 'string' && value.length > 0 ? value : null
}

function requiredString(record, key) {
  const value = cloudField(record, key)
  return typeof value === 'string' ? value : null
}

function requiredNumber(record, key) {
  const value = Number(cloudField(record, key))
  return Number.isFinite(value) ? value : null
}

function requiredInteger(record, key) {
  const value = requiredNumber(record, key)
  return Number.isSafeInteger(value) ? value : null
}

function requiredBoolean(record, key) {
  const value = cloudField(record, key)
  if (typeof value === 'boolean') return value
  // CKRecord stores Swift Bool values as NSNumber. Depending on the deployed
  // CloudKit schema/Web Services representation this arrives as true/false or
  // as the Int64 values 0/1.
  if (value === 0 || value === 1) return Boolean(value)
  return null
}

function parseDateKey(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!match) return null
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const date = new Date(Date.UTC(year, month - 1, day, 12))
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null
  return { year, month, day }
}

export function addDateKeyDays(dateKey, days) {
  const parts = parseDateKey(dateKey)
  if (!parts || !Number.isInteger(days)) throw new Error(`Invalid date key: ${dateKey}`)
  const date = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days, 12))
  return `${date.getUTCFullYear().toString().padStart(4, '0')}-${(date.getUTCMonth() + 1).toString().padStart(2, '0')}-${date.getUTCDate().toString().padStart(2, '0')}`
}

export function berlinDateKey(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BERLIN_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date)
  const part = type => parts.find(entry => entry.type === type)?.value
  return `${part('year')}-${part('month')}-${part('day')}`
}

function timeZoneOffsetMilliseconds(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date)
  const part = type => Number(parts.find(entry => entry.type === type)?.value)
  let hour = part('hour')
  if (hour === 24) hour = 0
  const representedAsUTC = Date.UTC(part('year'), part('month') - 1, part('day'), hour, part('minute'), part('second'))
  return representedAsUTC - Math.trunc(date.getTime() / 1_000) * 1_000
}

function berlinLocalMidnight(dateKey) {
  const parts = parseDateKey(dateKey)
  if (!parts) throw new Error(`Invalid date key: ${dateKey}`)
  const targetAsUTC = Date.UTC(parts.year, parts.month - 1, parts.day)
  let instant = targetAsUTC
  for (let iteration = 0; iteration < 3; iteration += 1) {
    instant = targetAsUTC - timeZoneOffsetMilliseconds(new Date(instant), BERLIN_TIME_ZONE)
  }
  return instant
}

export function berlinDayBounds(dateKey) {
  const start = berlinLocalMidnight(dateKey)
  const endExclusive = berlinLocalMidnight(addDateKeyDays(dateKey, 1))
  return { start, endExclusive, endsAt: endExclusive - 1_000 }
}

export function submissionDeadline(dateKey) {
  return berlinDayBounds(dateKey).endsAt + 2 * 60 * 60 * 1_000
}

export function winnerAwardEligibleAt(dateKey) {
  return submissionDeadline(dateKey) + 15 * 60 * 1_000
}

export function stableHash(value) {
  let hash = HASH_OFFSET
  for (const byte of Buffer.from(value, 'utf8')) {
    hash ^= BigInt(byte)
    hash = (hash * HASH_PRIME) & UINT64_MASK
  }
  return hash === 0n ? 1n : hash
}

function nextRandom(state) {
  state = (state + RANDOM_INCREMENT) & UINT64_MASK
  let value = state
  value = ((value ^ (value >> 30n)) * RANDOM_MULTIPLIER_1) & UINT64_MASK
  value = ((value ^ (value >> 27n)) * RANDOM_MULTIPLIER_2) & UINT64_MASK
  return { state, value: value ^ (value >> 31n) }
}

export function deterministicCountryOrder(codes, seed) {
  const shuffled = [...codes]
  let state = stableHash(seed)
  for (let index = shuffled.length - 1; index >= 1; index -= 1) {
    const generated = nextRandom(state)
    state = generated.state
    const swapIndex = Number(generated.value % BigInt(index + 1))
    ;[shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]]
  }
  return shuffled
}

export async function readCanonicalCountryCodes(sourceURL = COUNTRY_SOURCE) {
  const source = await readFile(sourceURL, 'utf8')
  const start = source.indexOf('let allCountries: [Country] = [')
  const end = source.indexOf('\n]\n\nlet partiallyRecognizedCategory', start)
  if (start < 0 || end < 0) throw new Error('Could not locate allCountries in FlagCatalog.swift')
  const codes = [...source.slice(start, end).matchAll(/Country\(code:\s*"([^"]+)"/g)].map(match => match[1])
  if (codes.length !== 193 || new Set(codes).size !== codes.length) {
    throw new Error(`Expected 193 unique canonical countries, found ${codes.length}`)
  }
  return codes
}

export function canonicalChallenge(mode, dateKey, codes) {
  if (!MODES.includes(mode) || !parseDateKey(dateKey) || codes.length === 0 || new Set(codes).size !== codes.length) {
    throw new Error('Invalid canonical challenge input')
  }
  const seed = `${mode}_${dateKey}`
  const bounds = berlinDayBounds(dateKey)
  return {
    recordName: seed,
    mode,
    dateKey,
    seed,
    flagOrder: deterministicCountryOrder(codes, seed),
    startsAt: bounds.start,
    endsAt: bounds.endsAt,
  }
}

export function challengeRecord(challenge) {
  return {
    recordName: challenge.recordName,
    recordType: 'DailyChallenge',
    fields: {
      dateKey: valueField(challenge.dateKey),
      mode: valueField(challenge.mode),
      seed: valueField(challenge.seed),
      flagOrder: valueField(challenge.flagOrder.join(',')),
      startsAt: valueField(challenge.startsAt),
      endsAt: valueField(challenge.endsAt),
    },
  }
}

export function challengeRecordMatches(record, challenge, trustedServerUser = null) {
  if (!record || record.recordType !== 'DailyChallenge' || record.recordName !== challenge.recordName) return false
  if (trustedServerUser && serverUser(record, 'created') !== trustedServerUser) return false
  const startsAt = requiredNumber(record, 'startsAt')
  const endsAt = requiredNumber(record, 'endsAt')
  return requiredString(record, 'dateKey') === challenge.dateKey
    && requiredString(record, 'mode') === challenge.mode
    && requiredString(record, 'seed') === challenge.seed
    && requiredString(record, 'flagOrder') === challenge.flagOrder.join(',')
    && startsAt !== null && Math.abs(startsAt - challenge.startsAt) <= 1_000
    && endsAt !== null && Math.abs(endsAt - challenge.endsAt) <= 1_000
}

export function safeRecordComponent(value) {
  return [...value].map(character => /[\p{L}\p{N}_-]/u.test(character) ? character : '_').join('')
}

function normalizedOnlineName(name, fallback = 'Spieler') {
  const clean = value => [...String(value ?? '').normalize('NFC')]
    .filter(character => character !== '|' && !/\p{Cc}/u.test(character))
    .slice(0, 24)
    .join('')
    .trim()
    .split(/\s+/u)
    .filter(Boolean)
    .join(' ')
  return clean(name) || clean(fallback) || 'Spieler'
}

export function nicknameKeyCandidates(nickname) {
  const folded = String(nickname ?? '').trim().normalize('NFD').replace(/\p{M}/gu, '')
  const lowercased = new Set([
    folded.toLowerCase(),
    folded.toLocaleLowerCase('de-DE'),
    folded.toLocaleLowerCase('en-US'),
    // Swift uses Locale.current. Turkish/Azeri are the material special-case
    // for Latin I, so include both deterministic alternatives for legacy
    // claims created on devices using those locales.
    folded.toLocaleLowerCase('tr-TR'),
    folded.toLocaleLowerCase('az-Latn-AZ'),
  ])
  return [...lowercased]
    .map(value => [...value].map(character => /[\p{L}\p{N}]/u.test(character) ? character : '_').join(''))
    .filter(Boolean)
    .filter((value, index, values) => values.indexOf(value) === index)
}

function gameCenterPlayerRecordName(gameCenterPlayerID) {
  return `gc_${[...gameCenterPlayerID].map(character => /[\p{L}\p{N}]/u.test(character) ? character : '_').join('')}`
}

export function attemptRecordName(mode, dateKey, userId, attemptNumber) {
  return `${mode}_${dateKey}_${safeRecordComponent(userId)}_attempt_${attemptNumber}`
}

export function immutableLeaderboardRecordName(mode, dateKey, userId, attemptNumber) {
  return `${mode}_${dateKey}_${safeRecordComponent(userId)}_leaderboard_attempt_${attemptNumber}`
}

function decodeAnswerHistory(record) {
  const encoded = cloudField(record, 'inputHistoryData')
  if (typeof encoded !== 'string') return null
  try {
    const decoded = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'))
    return Array.isArray(decoded) ? decoded : null
  } catch {
    return null
  }
}

function finiteNonNegative(value) {
  return Number.isFinite(value) && value >= 0
}

export function validateMetricsAndEvidence(metrics, answers, challenge) {
  const {
    score, correctCount, wrongCount, duration, remainingTime, completed, aborted,
  } = metrics
  if (![score, correctCount, wrongCount].every(Number.isSafeInteger)
      || ![score, correctCount, wrongCount, duration, remainingTime].every(finiteNonNegative)) return 'invalid-numeric-values'
  if (completed === aborted) return 'invalid-run-state'
  if (duration > RUN_DURATION + TIMER_TOLERANCE
      || remainingTime > RUN_DURATION + TIMER_TOLERANCE
      || Math.abs(duration + remainingTime - RUN_DURATION) > TIMER_TOLERANCE) return 'invalid-timer'
  if (completed && (duration < RUN_DURATION - TIMER_TOLERANCE || remainingTime > TIMER_TOLERANCE)) return 'incomplete-timed-run'
  const totalAnswers = correctCount + wrongCount
  if (!Number.isSafeInteger(totalAnswers)) return 'answer-count-overflow'
  const maximumTransitions = Math.trunc((duration + 1) / MINIMUM_ELAPSED_SECONDS_PER_TRANSITION)
  if (totalAnswers > maximumTransitions + 1) return 'impossible-answer-rate'
  if (score > correctCount * MAXIMUM_POINTS_PER_CORRECT_ANSWER || (correctCount === 0 && score !== 0)) return 'impossible-score'
  if (!Array.isArray(answers) || answers.length !== totalAnswers) return 'incomplete-answer-evidence'
  if (new Set(answers.map(answer => answer.id)).size !== answers.length) return 'duplicate-answer-evidence'
  if (!challenge?.flagOrder?.length) return 'missing-challenge-order'

  let evidencedCorrect = 0
  let evidencedWrong = 0
  let reconstructedScore = 0
  let totalResponseTime = 0
  for (const [index, answer] of answers.entries()) {
    if (typeof answer?.id !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(answer.id)
        || typeof answer?.countryCode !== 'string' || answer.countryCode.length === 0
        || typeof answer?.countryName !== 'string' || typeof answer?.submittedAnswer !== 'string'
        || !(answer?.detectedCountryName === null || answer?.detectedCountryName === undefined || typeof answer.detectedCountryName === 'string')
        || typeof answer?.wasCorrect !== 'boolean' || !finiteNonNegative(answer?.responseTime)
        || answer.responseTime > RUN_DURATION + TIMER_TOLERANCE || !Number.isSafeInteger(answer?.pointsAwarded)
        || answer.pointsAwarded < 0) return 'invalid-answer-evidence'
    if (answer.countryCode !== challenge.flagOrder[index % challenge.flagOrder.length]) return 'invalid-daily-order'
    totalResponseTime += answer.responseTime
    if (answer.wasCorrect) {
      evidencedCorrect += 1
      const speedPoints = 100 + Math.max(0, Math.trunc((8 - Math.min(answer.responseTime, 8)) * 16))
      if (answer.pointsAwarded < speedPoints || answer.pointsAwarded > speedPoints + 6) return 'impossible-answer-score'
      reconstructedScore += answer.pointsAwarded
    } else {
      evidencedWrong += 1
      if (answer.pointsAwarded !== 0) return 'wrong-answer-points'
      reconstructedScore = Math.max(0, reconstructedScore - 25)
    }
  }
  const transitionTime = Math.max(0, answers.length - 1) * MINIMUM_ELAPSED_SECONDS_PER_TRANSITION
  if (totalResponseTime + transitionTime > duration + 1.5) return 'overlapping-response-times'
  if (evidencedCorrect !== correctCount || evidencedWrong !== wrongCount) return 'inconsistent-answer-counts'
  if (reconstructedScore !== score) return 'inconsistent-score'
  return null
}

function parseLeaderboardEntry(record) {
  const entry = {
    recordName: record?.recordName,
    dateKey: requiredString(record, 'dateKey'),
    mode: requiredString(record, 'mode'),
    userId: requiredString(record, 'userId'),
    displayName: requiredString(record, 'displayName'),
    bestScore: requiredInteger(record, 'bestScore'),
    bestAttemptNumber: requiredInteger(record, 'bestAttemptNumber'),
    correctCount: requiredInteger(record, 'correctCount'),
    wrongCount: requiredInteger(record, 'wrongCount'),
    duration: requiredNumber(record, 'duration'),
    remainingTime: requiredNumber(record, 'remainingTime'),
    completedAt: requiredNumber(record, 'completedAt'),
  }
  return Object.values(entry).some(value => value === null || value === undefined) ? null : entry
}

export function validateAttemptAndLeaderboard({ attempt, leaderboardRecord, playerRecord, nicknameClaims = [], challenge }) {
  const entry = parseLeaderboardEntry(leaderboardRecord)
  if (!entry || leaderboardRecord.recordType !== 'DailyLeaderboardEntry') return { valid: false, reason: 'invalid-leaderboard-fields' }
  if (entry.mode !== challenge.mode || entry.dateKey !== challenge.dateKey || !MODES.includes(entry.mode)
      || !entry.userId.trim() || !entry.displayName.trim() || !(entry.bestAttemptNumber >= 1 && entry.bestAttemptNumber <= MAX_ATTEMPTS)) {
    return { valid: false, reason: 'invalid-leaderboard-identity' }
  }
  if (entry.recordName !== immutableLeaderboardRecordName(entry.mode, entry.dateKey, entry.userId, entry.bestAttemptNumber)) {
    return { valid: false, reason: 'mutable-or-mismatched-leaderboard-id' }
  }
  if (!attempt || attempt.recordType !== 'DailyAttempt'
      || attempt.recordName !== attemptRecordName(entry.mode, entry.dateKey, entry.userId, entry.bestAttemptNumber)) {
    return { valid: false, reason: 'missing-or-mismatched-attempt' }
  }
  if (!playerRecord || playerRecord.recordType !== 'PlayerStats' || playerRecord.recordName !== entry.userId) {
    return { valid: false, reason: 'missing-player-record' }
  }
  const attemptOwner = serverUser(attempt, 'created')
  if (!attemptOwner || serverUser(leaderboardRecord, 'created') !== attemptOwner || serverUser(playerRecord, 'created') !== attemptOwner) {
    return { valid: false, reason: 'cloudkit-owner-mismatch' }
  }
  const playerName = requiredString(playerRecord, 'playerName')
  if (!playerName || normalizedOnlineName(playerName, '') !== playerName) {
    return { valid: false, reason: 'display-name-profile-mismatch' }
  }
  const matchingClaim = nicknameClaims.find(claim => (
    claim?.recordType === 'NicknameClaim'
      && requiredString(claim, 'nickname') === playerName
      && requiredString(claim, 'ownerRecordName') === entry.userId
      && serverUser(claim, 'created') === attemptOwner
      && nicknameKeyCandidates(playerName).some(key => claim.recordName === `nickname_${key}`)
  ))
  const gameCenterPlayerID = requiredString(playerRecord, 'gameCenterPlayerID') ?? ''
  const gameCenterAlias = requiredString(playerRecord, 'gameCenterAlias') ?? ''
  if ((entry.userId.startsWith('gc_') && (!gameCenterPlayerID || gameCenterPlayerRecordName(gameCenterPlayerID) !== entry.userId))
      || (!entry.userId.startsWith('gc_') && gameCenterPlayerID.length > 0)) {
    return { valid: false, reason: 'game-center-profile-mismatch' }
  }
  const isUnclaimedFallback = playerName === 'Spieler'
    || (gameCenterPlayerID.length > 0 && normalizedOnlineName('', gameCenterAlias) === playerName)
  if (!matchingClaim && !isUnclaimedFallback) {
    return { valid: false, reason: nicknameClaims.length > 0 ? 'nickname-claim-owner-mismatch' : 'missing-nickname-claim' }
  }
  const integrityVersion = requiredInteger(attempt, 'integrityVersion')
  if (integrityVersion === null || integrityVersion < FULL_EVIDENCE_VERSION) return { valid: false, reason: 'legacy-or-missing-full-evidence' }

  const metrics = {
    score: requiredInteger(attempt, 'score'),
    correctCount: requiredInteger(attempt, 'correctCount'),
    wrongCount: requiredInteger(attempt, 'wrongCount'),
    duration: requiredNumber(attempt, 'duration'),
    remainingTime: requiredNumber(attempt, 'remainingTime'),
    completed: requiredBoolean(attempt, 'completed'),
    aborted: requiredBoolean(attempt, 'aborted'),
  }
  if (Object.values(metrics).some(value => value === null)) return { valid: false, reason: 'invalid-attempt-fields' }
  if (metrics.completed !== true || metrics.aborted !== false) return { valid: false, reason: 'attempt-not-completed' }
  if (requiredString(attempt, 'dateKey') !== entry.dateKey || requiredString(attempt, 'mode') !== entry.mode
      || requiredString(attempt, 'userId') !== entry.userId || requiredString(attempt, 'displayName') !== entry.displayName
      || requiredInteger(attempt, 'attemptNumber') !== entry.bestAttemptNumber
      || requiredInteger(attempt, 'playedRounds') !== metrics.correctCount + metrics.wrongCount) {
    return { valid: false, reason: 'attempt-reservation-mismatch' }
  }
  const answers = decodeAnswerHistory(attempt)
  const evidenceFailure = validateMetricsAndEvidence(metrics, answers, challenge)
  if (evidenceFailure) return { valid: false, reason: evidenceFailure }

  if (entry.bestScore !== metrics.score || entry.correctCount !== metrics.correctCount || entry.wrongCount !== metrics.wrongCount
      || entry.duration !== metrics.duration || entry.remainingTime !== metrics.remainingTime) {
    return { valid: false, reason: 'leaderboard-attempt-metrics-mismatch' }
  }
  const createdAt = serverTimestamp(attempt, 'created')
  const modifiedAt = serverTimestamp(attempt, 'modified')
  const leaderboardCreatedAt = serverTimestamp(leaderboardRecord, 'created')
  const leaderboardModifiedAt = serverTimestamp(leaderboardRecord, 'modified')
  const bounds = berlinDayBounds(entry.dateKey)
  if (createdAt === null || modifiedAt === null || leaderboardCreatedAt === null || leaderboardModifiedAt === null
      || createdAt < bounds.start - 2 * 60 * 1_000 || createdAt > bounds.endExclusive + 2 * 60 * 1_000
      || modifiedAt - createdAt < Math.max(0, metrics.duration - 2) * 1_000
      || leaderboardCreatedAt < modifiedAt - CLOUD_TIMESTAMP_TOLERANCE_MS
      || leaderboardModifiedAt < leaderboardCreatedAt - CLOUD_TIMESTAMP_TOLERANCE_MS
      || modifiedAt > submissionDeadline(entry.dateKey) || leaderboardModifiedAt > submissionDeadline(entry.dateKey)) {
    return { valid: false, reason: 'invalid-server-timestamps' }
  }
  const authoritativeCompletedAt = Math.min(Math.max(createdAt + metrics.duration * 1_000, bounds.start), bounds.endExclusive - 1)
  if (Math.abs(entry.completedAt - authoritativeCompletedAt) > 100) return { valid: false, reason: 'forged-completion-time' }
  // The immutable result remains bound to the original run, while the winner
  // uses the currently claimed profile name. A legitimate rename between the
  // run and the 02:15 award therefore does not forfeit the result or preserve
  // a released nickname in the winner record.
  return { valid: true, entry: { ...entry, displayName: playerName }, attempt, playerRecord }
}

export function isHigherRanked(lhs, rhs) {
  if (lhs.bestScore !== rhs.bestScore) return lhs.bestScore > rhs.bestScore
  if (lhs.correctCount !== rhs.correctCount) return lhs.correctCount > rhs.correctCount
  if (lhs.remainingTime !== rhs.remainingTime) return lhs.remainingTime > rhs.remainingTime
  if (lhs.duration !== rhs.duration) return lhs.duration < rhs.duration
  return lhs.userId < rhs.userId
}

export function rankLeaderboardEntries(entries) {
  const bestByUser = new Map()
  for (const entry of entries) {
    const existing = bestByUser.get(entry.userId)
    if (!existing || isHigherRanked(entry, existing)) bestByUser.set(entry.userId, entry)
  }
  return [...bestByUser.values()].sort((lhs, rhs) => isHigherRanked(lhs, rhs) ? -1 : (isHigherRanked(rhs, lhs) ? 1 : 0))
}

function sanitizeCloudKitFailure(operation, response, status) {
  const code = response?.serverErrorCode ?? response?.records?.find(record => record?.serverErrorCode)?.serverErrorCode ?? 'UNKNOWN'
  return new Error(`${operation} failed (HTTP ${status}, ${code})`)
}

async function fetchWithRetry(url, options, retries = 3) {
  let lastError
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      const response = await fetch(url, options)
      if (response.ok) return response
      let body
      try { body = await response.json() } catch { body = null }
      if (![429, 500, 502, 503, 504].includes(response.status) || attempt === retries) {
        throw sanitizeCloudKitFailure('CloudKit request', body, response.status)
      }
      await new Promise(resolve => setTimeout(resolve, 500 * 2 ** attempt))
    } catch (error) {
      lastError = error
      if (attempt === retries) throw error
    }
  }
  throw lastError
}

export class CloudKitClient {
  constructor({
    container = process.env.CLOUDKIT_CONTAINER || 'iCloud.de.phil.SpassmitFlaggen',
    keyId = process.env.CLOUDKIT_KEY_ID,
    privateKey = process.env.CLOUDKIT_PRIVATE_KEY,
    environment = 'production',
  } = {}) {
    if (!container.startsWith('iCloud.')) throw new Error('Invalid CLOUDKIT_CONTAINER')
    if (!['development', 'production'].includes(environment)) throw new Error('CloudKit environment must be development or production')
    if (!keyId || !privateKey) throw new Error('CLOUDKIT_KEY_ID and CLOUDKIT_PRIVATE_KEY are required')
    this.container = container
    this.keyId = keyId
    this.privateKey = privateKey.replace(/\\n/g, '\n')
    this.environment = environment
  }

  path(operation) {
    return `/database/1/${this.container}/${this.environment}/public/${operation}`
  }

  headers(path, body) {
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
    const bodyHash = crypto.createHash('sha256').update(body).digest('base64')
    const signature = crypto.sign('sha256', Buffer.from(`${date}:${bodyHash}:${path}`), { key: this.privateKey }).toString('base64')
    return {
      'content-type': 'application/json',
      'X-Apple-CloudKit-Request-KeyID': this.keyId,
      'X-Apple-CloudKit-Request-ISO8601Date': date,
      'X-Apple-CloudKit-Request-SignatureV1': signature,
    }
  }

  async request(operation, payload = null, method = 'POST') {
    const path = this.path(operation)
    const body = payload === null ? '' : JSON.stringify(payload)
    const response = await fetchWithRetry(`${API_ORIGIN}${path}`, {
      method,
      headers: this.headers(path, body),
      ...(method === 'GET' ? {} : { body }),
    })
    const data = await response.json()
    if (data?.serverErrorCode) throw sanitizeCloudKitFailure('CloudKit request', data, response.status)
    return data
  }

  async callerRecordName() {
    const response = await this.request('users/caller', null, 'GET')
    const name = response?.users?.[0]?.userRecordName
    if (typeof name !== 'string' || !name) throw new Error('CloudKit server caller identity is unavailable')
    return name
  }

  async lookupRecords(recordNames, desiredKeys = undefined) {
    const result = new Map()
    for (let offset = 0; offset < recordNames.length; offset += 200) {
      const records = recordNames.slice(offset, offset + 200).map(recordName => ({ recordName }))
      const response = await this.request('records/lookup', { records, desiredKeys })
      for (const record of response.records ?? []) {
        if (record.recordName && !record.serverErrorCode) result.set(record.recordName, record)
      }
    }
    return result
  }

  async queryRecords(recordType, filterBy, desiredKeys) {
    const all = []
    let continuationMarker
    do {
      const payload = {
        query: { recordType, filterBy },
        desiredKeys,
        resultsLimit: 200,
        ...(continuationMarker ? { continuationMarker } : {}),
      }
      const response = await this.request('records/query', payload)
      all.push(...(response.records ?? []).filter(record => !record.serverErrorCode))
      continuationMarker = response.continuationMarker
    } while (continuationMarker)
    return all
  }

  async createRecord(record) {
    const response = await this.request('records/modify', { operations: [{ operationType: 'create', record }] })
    const result = response.records?.[0]
    if (!result || result.serverErrorCode) throw sanitizeCloudKitFailure('CloudKit create', response, 200)
    return result
  }

  async forceReplaceRecords(records) {
    for (let offset = 0; offset < records.length; offset += 200) {
      const operations = records.slice(offset, offset + 200).map(record => ({ operationType: 'forceReplace', record }))
      const response = await this.request('records/modify', { operations, atomic: false })
      const failure = response.records?.find(record => record.serverErrorCode)
      if (failure || response.records?.length !== operations.length) throw sanitizeCloudKitFailure('CloudKit forceReplace', response, 200)
    }
  }
}

const stringEqualsFilter = (fieldName, value) => ({
  fieldName,
  comparator: 'EQUALS',
  fieldValue: { value, type: 'STRING' },
})

async function verifiedLeaderboard(client, challenge) {
  const records = await client.queryRecords(
    'DailyLeaderboardEntry',
    [stringEqualsFilter('mode', challenge.mode), stringEqualsFilter('dateKey', challenge.dateKey)],
    ['dateKey', 'mode', 'userId', 'displayName', 'bestScore', 'bestAttemptNumber', 'correctCount', 'wrongCount', 'duration', 'remainingTime', 'completedAt'],
  )
  const parsed = records.map(record => ({ record, entry: parseLeaderboardEntry(record) })).filter(item => item.entry)
  const attemptNames = parsed.map(({ entry }) => attemptRecordName(entry.mode, entry.dateKey, entry.userId, entry.bestAttemptNumber))
  const playerNames = parsed.map(({ entry }) => entry.userId)
  const [attempts, players] = await Promise.all([
    client.lookupRecords([...new Set(attemptNames)]),
    client.lookupRecords([...new Set(playerNames)], ['playerName', 'gameCenterPlayerID', 'gameCenterAlias']),
  ])
  const claimNames = [...players.values()].flatMap(player => nicknameKeyCandidates(requiredString(player, 'playerName') ?? '').map(key => `nickname_${key}`))
  const claims = await client.lookupRecords([...new Set(claimNames)], ['nickname', 'ownerRecordName'])
  const valid = []
  const rejectionCounts = new Map()
  for (const { record, entry } of parsed) {
    const result = validateAttemptAndLeaderboard({
      attempt: attempts.get(attemptRecordName(entry.mode, entry.dateKey, entry.userId, entry.bestAttemptNumber)),
      leaderboardRecord: record,
      playerRecord: players.get(entry.userId),
      nicknameClaims: nicknameKeyCandidates(requiredString(players.get(entry.userId), 'playerName') ?? '')
        .map(key => claims.get(`nickname_${key}`))
        .filter(Boolean),
      challenge,
    })
    if (result.valid) valid.push(result.entry)
    else rejectionCounts.set(result.reason, (rejectionCounts.get(result.reason) ?? 0) + 1)
  }
  return { entries: rankLeaderboardEntries(valid), rejectionCounts: Object.fromEntries(rejectionCounts) }
}

function winnerRecordName(mode, dateKey) {
  return `${mode}_${dateKey}_winner`
}

function winnerRecord(entry, eligibleAt) {
  return {
    recordName: winnerRecordName(entry.mode, entry.dateKey),
    recordType: 'DailyWinner',
    fields: {
      mode: valueField(entry.mode),
      dateKey: valueField(entry.dateKey),
      userId: valueField(entry.userId),
      displayName: valueField(entry.displayName),
      rank: valueField(1),
      score: valueField(entry.bestScore),
      awardedAt: valueField(eligibleAt),
      trophyGranted: valueField(1),
    },
  }
}

function existingWinnerMatches(record, entry, caller, eligibleAt) {
  const createdAt = serverTimestamp(record, 'created')
  const modifiedAt = serverTimestamp(record, 'modified')
  return record?.recordType === 'DailyWinner'
    && record.recordName === winnerRecordName(entry.mode, entry.dateKey)
    && requiredString(record, 'mode') === entry.mode
    && requiredString(record, 'dateKey') === entry.dateKey
    && requiredString(record, 'userId') === entry.userId
    && requiredString(record, 'displayName') === entry.displayName
    && requiredInteger(record, 'rank') === 1
    && requiredInteger(record, 'score') === entry.bestScore
    && requiredBoolean(record, 'trophyGranted') === true
    && serverUser(record, 'created') === caller
    && createdAt !== null && modifiedAt !== null
    && createdAt >= eligibleAt - CLOUD_TIMESTAMP_TOLERANCE_MS
    && modifiedAt >= createdAt - CLOUD_TIMESTAMP_TOLERANCE_MS
}

export function trustedWinnerEvent(record, caller) {
  if (!record || record.recordType !== 'DailyWinner' || serverUser(record, 'created') !== caller) return null
  const match = /^(daily_flaggenrun|daily_staedterun)_(\d{4}-\d{2}-\d{2})_winner$/.exec(record.recordName ?? '')
  if (!match || !parseDateKey(match[2])) return null
  const [recordName, mode, dateKey] = match
  const userId = requiredString(record, 'userId')?.trim()
  const displayName = requiredString(record, 'displayName')?.trim()
  const score = requiredInteger(record, 'score')
  const createdAt = serverTimestamp(record, 'created')
  const modifiedAt = serverTimestamp(record, 'modified')
  if (!userId || !displayName || requiredString(record, 'mode') !== mode || requiredString(record, 'dateKey') !== dateKey
      || requiredInteger(record, 'rank') !== 1 || score === null || score < 0
      || requiredBoolean(record, 'trophyGranted') !== true || createdAt === null || modifiedAt === null
      || createdAt < winnerAwardEligibleAt(dateKey) - CLOUD_TIMESTAMP_TOLERANCE_MS
      || modifiedAt < createdAt - CLOUD_TIMESTAMP_TOLERANCE_MS) return null
  return { recordName, mode, dateKey, userId, displayName, createdAt }
}

function dateKeysBetween(first, last) {
  const keys = []
  for (let key = first; key <= last; key = addDateKeyDays(key, 1)) keys.push(key)
  return keys
}

async function loadTrustedWinnerEvents(client, caller, lastCompletedDateKey) {
  const names = dateKeysBetween(MAINTENANCE_START_DATE, lastCompletedDateKey)
    .flatMap(dateKey => MODES.map(mode => winnerRecordName(mode, dateKey)))
  const records = await client.lookupRecords(names)
  return [...records.values()].map(record => trustedWinnerEvent(record, caller)).filter(Boolean)
}

export function deriveTrophyStandings(events) {
  const byUser = new Map()
  const sortedEvents = [...events].sort((lhs, rhs) => lhs.dateKey.localeCompare(rhs.dateKey) || lhs.recordName.localeCompare(rhs.recordName))
  const eventsByDate = new Map()
  for (const event of sortedEvents) {
    const dailyEvents = eventsByDate.get(event.dateKey) ?? []
    dailyEvents.push(event)
    eventsByDate.set(event.dateKey, dailyEvents)
  }

  const rank = () => [...byUser.entries()]
    .map(([userId, totals]) => ({ userId, ...totals, total: totals.flag + totals.city }))
    .sort((lhs, rhs) => {
      if (lhs.total !== rhs.total) return rhs.total - lhs.total
      if (lhs.lastTrophyDate !== rhs.lastTrophyDate) return lhs.lastTrophyDate - rhs.lastTrophyDate
      return lhs.userId < rhs.userId ? -1 : (lhs.userId > rhs.userId ? 1 : 0)
    })

  const dailyLeaders = []
  for (const [dateKey, dailyEvents] of [...eventsByDate.entries()].sort(([lhs], [rhs]) => lhs.localeCompare(rhs))) {
    const trophyDate = berlinDayBounds(dateKey).start
    for (const event of dailyEvents) {
      const totals = byUser.get(event.userId) ?? { displayName: event.displayName, flag: 0, city: 0, ids: [], lastTrophyDate: trophyDate }
      totals.displayName = event.displayName
      if (event.mode === 'daily_staedterun') totals.city += 1
      else totals.flag += 1
      totals.ids.push(event.recordName)
      totals.lastTrophyDate = trophyDate
      byUser.set(event.userId, totals)
    }
    const leader = rank()[0]
    if (leader) dailyLeaders.push({ dateKey, userId: leader.userId })
  }

  const finalStandings = rank()
  const currentLeader = finalStandings[0]
  let rankOneSinceDate = null
  if (currentLeader) {
    for (let index = dailyLeaders.length - 1; index >= 0; index -= 1) {
      if (dailyLeaders[index].userId !== currentLeader.userId) break
      rankOneSinceDate = berlinDayBounds(dailyLeaders[index].dateKey).start
    }
  }
  return finalStandings.map((standing, index) => ({
    ...standing,
    rank: index + 1,
    rankOneSinceDate: index === 0 ? rankOneSinceDate : null,
  }))
}

export function buildUserStatsRecords(events, timestamp) {
  return deriveTrophyStandings(events).map(standing => ({
    recordName: `userstats_${safeRecordComponent(standing.userId)}`,
    recordType: 'UserStats',
    fields: {
      userId: valueField(standing.userId),
      displayName: valueField(standing.displayName),
      dailyFlaggenrunTrophies: valueField(standing.flag),
      dailyStaedterunTrophies: valueField(standing.city),
      totalTrophies: valueField(standing.total),
      trophyRank: valueField(standing.rank),
      lastTrophyDate: valueField(standing.lastTrophyDate),
      ...(standing.rankOneSinceDate === null ? {} : { rankOneSinceDate: valueField(standing.rankOneSinceDate) }),
      awardedTrophyIDs: valueField(standing.ids.sort().join('|')),
      updatedAt: valueField(timestamp),
    },
  }))
}

export async function maintainChallenges({ client, apply, dateKeys, countryCodes, caller }) {
  const challenges = dateKeys.flatMap(dateKey => MODES.map(mode => canonicalChallenge(mode, dateKey, countryCodes)))
  const existing = await client.lookupRecords(challenges.map(challenge => challenge.recordName))
  const summary = { checked: challenges.length, created: 0, planned: 0, unchanged: 0, rejected: 0 }
  for (const challenge of challenges) {
    const record = existing.get(challenge.recordName)
    if (record) {
      if (challengeRecordMatches(record, challenge, caller)) summary.unchanged += 1
      else summary.rejected += 1
      continue
    }
    if (!apply) {
      summary.planned += 1
      continue
    }
    try {
      await client.createRecord(challengeRecord(challenge))
    } catch {
      const afterRace = await client.lookupRecords([challenge.recordName])
      if (!challengeRecordMatches(afterRace.get(challenge.recordName), challenge, caller)) throw new Error('DailyChallenge create conflict did not resolve to the trusted canonical record')
    }
    const verified = await client.lookupRecords([challenge.recordName])
    if (!challengeRecordMatches(verified.get(challenge.recordName), challenge, caller)) throw new Error('Created DailyChallenge failed read-back verification')
    summary.created += 1
  }
  if (apply && summary.rejected > 0) {
    throw new Error(`Refusing writes because ${summary.rejected} existing DailyChallenge record(s) are not trusted and canonical`)
  }
  return summary
}

export async function maintainWinners({ client, apply, dateKeys, countryCodes, caller, now = Date.now() }) {
  const summary = { checked: 0, created: 0, planned: 0, unchanged: 0, noEligibleEntry: 0, notYetEligible: 0, rejectedExisting: 0, rejectedEntries: {} }
  for (const dateKey of dateKeys) {
    for (const mode of MODES) {
      summary.checked += 1
      const eligibleAt = winnerAwardEligibleAt(dateKey)
      if (now < eligibleAt) {
        summary.notYetEligible += 1
        continue
      }
      const challenge = canonicalChallenge(mode, dateKey, countryCodes)
      const verified = await verifiedLeaderboard(client, challenge)
      for (const [reason, count] of Object.entries(verified.rejectionCounts)) {
        summary.rejectedEntries[reason] = (summary.rejectedEntries[reason] ?? 0) + count
      }
      const winner = verified.entries[0]
      if (!winner) {
        summary.noEligibleEntry += 1
        continue
      }
      const name = winnerRecordName(mode, dateKey)
      const existing = (await client.lookupRecords([name])).get(name)
      if (existing) {
        if (existingWinnerMatches(existing, winner, caller, eligibleAt)) summary.unchanged += 1
        else summary.rejectedExisting += 1
        continue
      }
      if (!apply) {
        summary.planned += 1
        continue
      }
      try {
        await client.createRecord(winnerRecord(winner, eligibleAt))
      } catch {
        // Deterministic IDs make concurrent scheduled/manual runs harmless.
      }
      const readBack = (await client.lookupRecords([name])).get(name)
      if (!existingWinnerMatches(readBack, winner, caller, eligibleAt)) throw new Error('DailyWinner failed trusted read-back verification')
      summary.created += 1
    }
  }

  if (apply && summary.rejectedExisting > 0) {
    throw new Error(`Refusing trophy rebuild because ${summary.rejectedExisting} existing DailyWinner record(s) are not trusted and canonical`)
  }

  if (apply) {
    const lastCompleted = addDateKeyDays(berlinDateKey(new Date(now)), -1)
    const events = await loadTrustedWinnerEvents(client, caller, lastCompleted)
    await client.forceReplaceRecords(buildUserStatsRecords(events, now))
    summary.rebuiltUserStats = new Set(events.map(event => event.userId)).size
    summary.trustedWinnerRecords = events.length
  }
  return summary
}

function argumentValue(args, name, fallback) {
  const prefix = `--${name}=`
  return args.find(argument => argument.startsWith(prefix))?.slice(prefix.length) ?? fallback
}

function integerArgument(args, name, fallback, minimum, maximum) {
  const value = Number(argumentValue(args, name, fallback))
  if (!Number.isInteger(value) || value < minimum || value > maximum) throw new Error(`--${name} must be between ${minimum} and ${maximum}`)
  return value
}

export function parseArguments(args) {
  const task = argumentValue(args, 'task', 'both')
  const environment = argumentValue(args, 'environment', 'production')
  const apply = args.includes('--apply')
  if (!['challenge', 'winner', 'both'].includes(task)) throw new Error('--task must be challenge, winner, or both')
  if (!['development', 'production'].includes(environment)) throw new Error('--environment must be development or production')
  if (apply && process.env.CLOUDKIT_DAILY_WRITES_ENABLED !== 'true') {
    throw new Error('--apply requires CLOUDKIT_DAILY_WRITES_ENABLED=true after schema/security verification')
  }
  return {
    task,
    environment,
    apply,
    daysBack: integerArgument(args, 'days-back', 7, 1, 31),
    daysForward: integerArgument(args, 'days-forward', 1, 0, 7),
  }
}

export async function main(args = process.argv.slice(2)) {
  const options = parseArguments(args)
  const client = new CloudKitClient({ environment: options.environment })
  const [countryCodes, caller] = await Promise.all([readCanonicalCountryCodes(), client.callerRecordName()])
  const today = berlinDateKey()
  const output = {
    environment: options.environment,
    mode: options.apply ? 'apply' : 'dry-run',
    generatedAt: new Date().toISOString(),
  }
  if (options.task === 'challenge' || options.task === 'both') {
    const dateKeys = Array.from({ length: options.daysForward + 1 }, (_, index) => addDateKeyDays(today, index))
    output.challenges = await maintainChallenges({ client, apply: options.apply, dateKeys, countryCodes, caller })
  }
  if (options.task === 'winner' || options.task === 'both') {
    const dateKeys = Array.from({ length: options.daysBack }, (_, index) => addDateKeyDays(today, -(index + 1)))
    output.winners = await maintainWinners({ client, apply: options.apply, dateKeys, countryCodes, caller })
  }
  // Output contains counts and dates only; never keys, signatures, player IDs,
  // display names, record names, answer data, or raw CloudKit responses.
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    process.stderr.write(`CloudKit Daily maintenance failed: ${error.message}\n`)
    process.exitCode = 1
  })
}
