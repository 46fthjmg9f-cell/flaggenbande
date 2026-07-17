import Foundation
import CloudKit

struct SeededRandomGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else { return 0 }
        return next() % upperBound
    }
}

struct DailyChallenge: Identifiable {
    let id: String
    let dateKey: String
    let mode: String
    let seed: String
    let flagOrder: [String]
    let startsAt: Date
    let endsAt: Date
}

struct DailyUserStatus {
    var dateKey: String
    var mode: String
    var attemptsUsed: Int
    var bestScore: Int
    var bestAttemptNumber: Int
    var trophies: Int

    var attemptsRemaining: Int {
        max(0, 2 - attemptsUsed)
    }
}

struct DailyLeaderboardEntry: Identifiable {
    let id: String
    let dateKey: String
    let mode: String
    let userId: String
    let displayName: String
    let bestScore: Int
    let bestAttemptNumber: Int
    let correctCount: Int
    let wrongCount: Int
    let duration: Double
    let remainingTime: Double
    let completedAt: Date
    let updatedAt: Date

    var playedRounds: Int { correctCount + wrongCount }
}

struct TrophyLeaderboardEntry: Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let flagRunTrophies: Int
    let cityRunTrophies: Int
    let updatedAt: Date

    var totalTrophies: Int {
        flagRunTrophies + cityRunTrophies
    }
}

struct DailyAttemptReservation: Codable {
    let recordName: String
    let attemptNumber: Int
    let dateKey: String
    let mode: String
    let flagOrder: [String]
    let userId: String
    let subject: LearningSubject
}

struct DailyAttemptSummary: Identifiable {
    let id: String
    let resultID: UUID
    let dateKey: String
    let mode: String
    let attemptNumber: Int
    let score: Int
    let correctCount: Int
    let wrongCount: Int
    let duration: Double
    let remainingTime: Double
    let completed: Bool
    let aborted: Bool
    let answerRecords: [LeagueAnswerRecord]
    let updatedAt: Date

    var result: LeagueMatchResult {
        LeagueMatchResult(
            id: resultID,
            date: updatedAt,
            opponentName: aborted ? "Abgebrochen" : "Daily",
            ownScore: score,
            opponentScore: 0,
            correct: correctCount,
            wrong: wrongCount,
            duration: Int(duration),
            answerDetails: answerRecords,
            ratingBefore: nil,
            ratingAfter: nil,
            ratingDelta: nil,
            runVariant: .daily,
            dailyAttemptNumber: attemptNumber,
            dailyDateKey: dateKey,
            subject: mode == DailyFlaggenrunService.mode(for: .capitals) ? .capitals : .countries,
            wasAborted: aborted
        )
    }
}

struct DailyRunCompletion: Codable, Identifiable {
    let reservation: DailyAttemptReservation
    let displayName: String
    let score: Int
    let correctCount: Int
    let wrongCount: Int
    let duration: Double
    let remainingTime: Double
    let completed: Bool
    let aborted: Bool
    let answerRecords: [LeagueAnswerRecord]
    let completedAt: Date

    var id: String { reservation.recordName }
}

enum DailyCompletionQueue {
    private static let storageKey = "pendingDailyRunCompletionsV1"
    private static let fileName = "pendingDailyRunCompletionsV1.json"

    static func migrateLegacyIfNeeded() {
        if let fileData = DataFileStore.read(fileName: fileName),
           (try? JSONDecoder().decode([DailyRunCompletion].self, from: fileData)) != nil {
            LegacyDefaultsMigration.removeData(forKey: storageKey)
            return
        }

        guard let defaultsData = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard (try? JSONDecoder().decode([DailyRunCompletion].self, from: defaultsData)) != nil else {
            preserveCorruptData(defaultsData)
            LegacyDefaultsMigration.removeData(forKey: storageKey, migratedData: defaultsData)
            return
        }
        if DataFileStore.write(defaultsData, fileName: fileName) {
            LegacyDefaultsMigration.removeData(forKey: storageKey, migratedData: defaultsData)
        }
    }

    static func load() -> [DailyRunCompletion] {
        migrateLegacyIfNeeded()
        guard let data = DataFileStore.read(fileName: fileName) else { return [] }
        guard let decoded = try? JSONDecoder().decode([DailyRunCompletion].self, from: data) else {
            preserveCorruptData(data)
            DataFileStore.remove(fileName: fileName)
            return []
        }
        return decoded
    }

    static func enqueue(_ completion: DailyRunCompletion) {
        var pending = load().filter { $0.id != completion.id }
        pending.append(completion)
        persist(pending)
    }

    static func remove(id: String) {
        persist(load().filter { $0.id != id })
    }

    private static func persist(_ completions: [DailyRunCompletion]) {
        if completions.isEmpty {
            LegacyDefaultsMigration.removeData(forKey: storageKey)
            DataFileStore.remove(fileName: fileName)
        } else if let data = try? JSONEncoder().encode(completions) {
            if DataFileStore.write(data, fileName: fileName) {
                LegacyDefaultsMigration.removeData(forKey: storageKey)
            }
        }
    }

    private static func preserveCorruptData(_ data: Data) {
        let name = "CorruptBackups/pendingDailyRunCompletions-\(Int(Date().timeIntervalSince1970)).json"
        _ = DataFileStore.write(data, fileName: name)
    }
}

enum DailyFlaggenrunService {
    static let challengeRecordType = "DailyChallenge"
    static let attemptRecordType = "DailyAttempt"
    static let leaderboardRecordType = "DailyLeaderboardEntry"
    static let userStatsRecordType = "UserStats"
    static let winnerRecordType = "DailyWinner"
    static let maxAttemptsPerDay = 2
    static let berlinTimeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    static func mode(for subject: LearningSubject) -> String {
        subject == .capitals ? "daily_staedterun" : "daily_flaggenrun"
    }

    static func trophyField(for subject: LearningSubject) -> String {
        subject == .capitals ? "dailyStaedterunTrophies" : "dailyFlaggenrunTrophies"
    }

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = berlinTimeZone
        return calendar
    }

    static func dateKey(for date: Date = Date()) -> String {
        let components = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func previousDateKey(from date: Date = Date()) -> String? {
        calendar().date(byAdding: .day, value: -1, to: date).map { dateKey(for: $0) }
    }

    static func dayBounds(for dateKey: String) -> (startsAt: Date, endsAt: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = berlinTimeZone
        let start = formatter.date(from: dateKey) ?? calendar().startOfDay(for: Date())
        let end = calendar().date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
        return (start, end)
    }

    static func challengeRecordName(mode: String, dateKey: String) -> String {
        "\(mode)_\(dateKey)"
    }

    static func userRecordName(gameCenterPlayerID: String?) -> String {
        OnlineStatsService.playerID(gameCenterPlayerID: gameCenterPlayerID)
    }

    static func status(subject: LearningSubject, gameCenterPlayerID: String?, countries: [Country]) async throws -> (challenge: DailyChallenge, status: DailyUserStatus, leaderboard: [DailyLeaderboardEntry], attempts: [DailyAttemptSummary]) {
        try await OnlineStatsService.ensureAccountAvailable()
        let mode = mode(for: subject)
        let todayKey = dateKey()
        let userId = userRecordName(gameCenterPlayerID: gameCenterPlayerID)

        // Awarding yesterday's winner is maintenance work and must not delay
        // today's screen. The independent reads below can share the same wait.
        Task {
            try? await awardWinnerIfNeeded(subject: subject, dateKey: previousDateKey() ?? todayKey)
        }
        async let challengeLoad = ensureChallenge(mode: mode, dateKey: todayKey, countries: countries)
        async let attemptsLoad = fetchAttemptRecords(mode: mode, dateKey: todayKey, userId: userId)
        async let leaderboardLoad = fetchLeaderboard(mode: mode, dateKey: todayKey)
        async let trophiesLoad = fetchTrophyCount(subject: subject, userId: userId)

        let (challenge, attempts, leaderboard, trophies) = try await (
            challengeLoad,
            attemptsLoad,
            leaderboardLoad,
            trophiesLoad
        )
        let ownEntry = leaderboard.first { $0.userId == userId }
        let status = DailyUserStatus(
            dateKey: todayKey,
            mode: mode,
            attemptsUsed: attempts.count,
            bestScore: ownEntry?.bestScore ?? 0,
            bestAttemptNumber: ownEntry?.bestAttemptNumber ?? 0,
            trophies: trophies
        )
        return (challenge, status, leaderboard, attempts.compactMap(DailyAttemptSummary.init(record:)).sorted { $0.attemptNumber < $1.attemptNumber })
    }

    static func reserveAttempt(subject: LearningSubject, gameCenterPlayerID: String?, displayName: String, countries: [Country]) async throws -> DailyAttemptReservation {
        try await OnlineStatsService.ensureAccountAvailable()
        let mode = mode(for: subject)
        let todayKey = dateKey()
        let challenge = try await ensureChallenge(mode: mode, dateKey: todayKey, countries: countries)
        let userId = userRecordName(gameCenterPlayerID: gameCenterPlayerID)
        let attempts = try await fetchAttemptRecords(mode: mode, dateKey: todayKey, userId: userId)
        guard attempts.count < maxAttemptsPerDay else {
            throw OnlineStatsService.OnlineStatsError.dailyAttemptsExhausted
        }

        for attemptNumber in 1...maxAttemptsPerDay {
            let recordName = attemptRecordName(mode: mode, dateKey: todayKey, userId: userId, attemptNumber: attemptNumber)
            if attempts.contains(where: { $0.recordID.recordName == recordName }) { continue }
            let record = CKRecord(recordType: attemptRecordType, recordID: CKRecord.ID(recordName: recordName))
            record["dateKey"] = todayKey as CKRecordValue
            record["mode"] = mode as CKRecordValue
            record["userId"] = userId as CKRecordValue
            record["displayName"] = displayName as CKRecordValue
            record["attemptNumber"] = attemptNumber as CKRecordValue
            record["score"] = 0 as CKRecordValue
            record["correctCount"] = 0 as CKRecordValue
            record["wrongCount"] = 0 as CKRecordValue
            record["playedRounds"] = 0 as CKRecordValue
            record["duration"] = 0.0 as CKRecordValue
            record["remainingTime"] = 60.0 as CKRecordValue
            record["completed"] = false as CKRecordValue
            record["aborted"] = true as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            do {
                try await OnlineStatsService.saveNew(record: record)
                return DailyAttemptReservation(
                    recordName: recordName,
                    attemptNumber: attemptNumber,
                    dateKey: todayKey,
                    mode: mode,
                    flagOrder: challenge.flagOrder,
                    userId: userId,
                    subject: subject
                )
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }

        throw OnlineStatsService.OnlineStatsError.dailyAttemptsExhausted
    }

    static func completeAttempt(_ completion: DailyRunCompletion, gameCenterPlayerID: String?) async throws -> [DailyLeaderboardEntry] {
        try await OnlineStatsService.ensureAccountAvailable()
        let recordID = CKRecord.ID(recordName: completion.reservation.recordName)
        let record = try await OnlineStatsService.fetchRecord(recordID: recordID) ?? CKRecord(recordType: attemptRecordType, recordID: recordID)
        let userId = completion.reservation.userId
        record["dateKey"] = completion.reservation.dateKey as CKRecordValue
        record["mode"] = completion.reservation.mode as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["displayName"] = completion.displayName as CKRecordValue
        record["attemptNumber"] = completion.reservation.attemptNumber as CKRecordValue
        record["score"] = completion.score as CKRecordValue
        record["correctCount"] = completion.correctCount as CKRecordValue
        record["wrongCount"] = completion.wrongCount as CKRecordValue
        record["playedRounds"] = (completion.correctCount + completion.wrongCount) as CKRecordValue
        record["duration"] = completion.duration as CKRecordValue
        record["remainingTime"] = completion.remainingTime as CKRecordValue
        record["completed"] = completion.completed as CKRecordValue
        record["aborted"] = completion.aborted as CKRecordValue
        record["inputHistoryData"] = encodedAnswerHistory(completion.answerRecords) as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await OnlineStatsService.save(record: record)

        if completion.completed {
            try await updateLeaderboardIfNeeded(completion, userId: userId)
        }
        return try await fetchLeaderboard(mode: completion.reservation.mode, dateKey: completion.reservation.dateKey)
    }

    static func fetchLeaderboard(mode: String, dateKey: String) async throws -> [DailyLeaderboardEntry] {
        let predicate = NSPredicate(format: "mode == %@ AND dateKey == %@", mode, dateKey)
        let query = CKQuery(recordType: leaderboardRecordType, predicate: predicate)
        let records = try await OnlineStatsService.queryRecords(query)
        return records.compactMap(DailyLeaderboardEntry.init(record:)).sorted(by: isHigherRanked)
    }

    static func fetchTrophyLeaderboard() async throws -> [TrophyLeaderboardEntry] {
        try await OnlineStatsService.ensureAccountAvailable()
        let query = CKQuery(recordType: userStatsRecordType, predicate: NSPredicate(value: true))
        let records = try await OnlineStatsService.queryRecords(
            query,
            desiredKeys: [
                "userId",
                "displayName",
                "dailyFlaggenrunTrophies",
                "dailyStaedterunTrophies",
                "updatedAt"
            ]
        )
        return records
            .compactMap(TrophyLeaderboardEntry.init(record:))
            .filter { $0.totalTrophies > 0 }
            .sorted {
                if $0.totalTrophies != $1.totalTrophies {
                    return $0.totalTrophies > $1.totalTrophies
                }
                if $0.flagRunTrophies != $1.flagRunTrophies {
                    return $0.flagRunTrophies > $1.flagRunTrophies
                }
                if $0.cityRunTrophies != $1.cityRunTrophies {
                    return $0.cityRunTrophies > $1.cityRunTrophies
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    #if DEBUG
    static func resetTodayForCurrentUser(subject: LearningSubject, gameCenterPlayerID: String?) async throws {
        try await OnlineStatsService.ensureAccountAvailable()
        let mode = mode(for: subject)
        let todayKey = dateKey()
        let userId = userRecordName(gameCenterPlayerID: gameCenterPlayerID)

        for attemptNumber in 1...maxAttemptsPerDay {
            let recordID = CKRecord.ID(recordName: attemptRecordName(mode: mode, dateKey: todayKey, userId: userId, attemptNumber: attemptNumber))
            try await OnlineStatsService.delete(recordID: recordID)
        }

        let leaderboardID = CKRecord.ID(recordName: leaderboardRecordName(mode: mode, dateKey: todayKey, userId: userId))
        try await OnlineStatsService.delete(recordID: leaderboardID)
    }
    #endif

    static func ensureChallenge(mode: String, dateKey: String, countries: [Country]) async throws -> DailyChallenge {
        let recordID = CKRecord.ID(recordName: challengeRecordName(mode: mode, dateKey: dateKey))
        if let existing = try await OnlineStatsService.fetchRecord(recordID: recordID), let challenge = DailyChallenge(record: existing) {
            return challenge
        }

        let seed = "\(mode)_\(dateKey)"
        let order = deterministicCountryOrder(countries.map(\.code), seed: seed)
        let bounds = dayBounds(for: dateKey)
        let record = CKRecord(recordType: challengeRecordType, recordID: recordID)
        record["dateKey"] = dateKey as CKRecordValue
        record["mode"] = mode as CKRecordValue
        record["seed"] = seed as CKRecordValue
        record["flagOrder"] = order.joined(separator: ",") as CKRecordValue
        record["startsAt"] = bounds.startsAt as CKRecordValue
        record["endsAt"] = bounds.endsAt as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        do {
            try await OnlineStatsService.saveNew(record: record)
            return DailyChallenge(record: record) ?? DailyChallenge(id: recordID.recordName, dateKey: dateKey, mode: mode, seed: seed, flagOrder: order, startsAt: bounds.startsAt, endsAt: bounds.endsAt)
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .unknownItem {
            if let existing = try await OnlineStatsService.fetchRecord(recordID: recordID), let challenge = DailyChallenge(record: existing) {
                return challenge
            }
            throw error
        }
    }

    static func awardWinnerIfNeeded(subject: LearningSubject, dateKey: String) async throws {
        let mode = mode(for: subject)
        let winnerID = CKRecord.ID(recordName: "\(mode)_\(dateKey)_winner")
        let awardEligibleAt = dayBounds(for: dateKey).endsAt.addingTimeInterval(2 * 60 * 60)
        guard Date() >= awardEligibleAt else { return }

        if let existingWinner = try await OnlineStatsService.fetchRecord(recordID: winnerID) {
            // Records from older releases had no grant marker and already ran
            // through the legacy increment path. Treat them as completed to
            // avoid ever issuing a duplicate trophy.
            guard let wasGranted = (existingWinner["trophyGranted"] as? NSNumber)?.boolValue,
                  !wasGranted else { return }
            try await finalizeTrophyGrant(for: existingWinner, subject: subject)
            return
        }
        let leaderboard = try await fetchLeaderboard(mode: mode, dateKey: dateKey)
        guard let winner = leaderboard.first else { return }
        let record = CKRecord(recordType: winnerRecordType, recordID: winnerID)
        record["mode"] = mode as CKRecordValue
        record["dateKey"] = dateKey as CKRecordValue
        record["userId"] = winner.userId as CKRecordValue
        record["displayName"] = winner.displayName as CKRecordValue
        record["rank"] = 1 as CKRecordValue
        record["score"] = winner.bestScore as CKRecordValue
        record["awardedAt"] = Date() as CKRecordValue
        record["trophyGranted"] = false as CKRecordValue
        do {
            try await OnlineStatsService.saveNew(record: record)
            try await finalizeTrophyGrant(for: record, subject: subject)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let existingWinner = try await OnlineStatsService.fetchRecord(recordID: winnerID),
                  (existingWinner["trophyGranted"] as? NSNumber)?.boolValue == false else { return }
            try await finalizeTrophyGrant(for: existingWinner, subject: subject)
        }
    }

    static func performWinnerMaintenance(daysBack: Int = 7) async {
        let safeDaysBack = max(1, min(daysBack, 31))
        for subject in LearningSubject.allCases {
            for dayOffset in 1...safeDaysBack {
                guard let date = calendar().date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                try? await awardWinnerIfNeeded(subject: subject, dateKey: dateKey(for: date))
            }
        }
    }

    private static func fetchAttemptRecords(mode: String, dateKey: String, userId: String) async throws -> [CKRecord] {
        let firstID = CKRecord.ID(recordName: attemptRecordName(mode: mode, dateKey: dateKey, userId: userId, attemptNumber: 1))
        let secondID = CKRecord.ID(recordName: attemptRecordName(mode: mode, dateKey: dateKey, userId: userId, attemptNumber: 2))
        async let firstRecord = OnlineStatsService.fetchRecord(recordID: firstID)
        async let secondRecord = OnlineStatsService.fetchRecord(recordID: secondID)
        return try await [firstRecord, secondRecord].compactMap { $0 }
    }

    private static func attemptRecordName(mode: String, dateKey: String, userId: String, attemptNumber: Int) -> String {
        "\(mode)_\(dateKey)_\(safeRecordComponent(userId))_attempt_\(attemptNumber)"
    }

    private static func leaderboardRecordName(mode: String, dateKey: String, userId: String) -> String {
        "\(mode)_\(dateKey)_\(safeRecordComponent(userId))"
    }

    private static func updateLeaderboardIfNeeded(_ completion: DailyRunCompletion, userId: String) async throws {
        let recordID = CKRecord.ID(recordName: leaderboardRecordName(mode: completion.reservation.mode, dateKey: completion.reservation.dateKey, userId: userId))
        let candidate = DailyLeaderboardEntry(
            id: recordID.recordName,
            dateKey: completion.reservation.dateKey,
            mode: completion.reservation.mode,
            userId: userId,
            displayName: completion.displayName,
            bestScore: completion.score,
            bestAttemptNumber: completion.reservation.attemptNumber,
            correctCount: completion.correctCount,
            wrongCount: completion.wrongCount,
            duration: completion.duration,
            remainingTime: completion.remainingTime,
            completedAt: completion.completedAt,
            updatedAt: Date()
        )

        if let existingRecord = try await OnlineStatsService.fetchRecord(recordID: recordID), let existing = DailyLeaderboardEntry(record: existingRecord), isHigherRanked(existing, candidate) {
            return
        }

        let record = try await OnlineStatsService.fetchRecord(recordID: recordID) ?? CKRecord(recordType: leaderboardRecordType, recordID: recordID)
        write(candidate, to: record)
        try await OnlineStatsService.save(record: record)
    }

    private static func fetchTrophyCount(subject: LearningSubject, userId: String) async throws -> Int {
        let recordID = CKRecord.ID(recordName: "userstats_\(safeRecordComponent(userId))")
        guard let record = try await OnlineStatsService.fetchRecord(recordID: recordID) else { return 0 }
        return (record[trophyField(for: subject)] as? NSNumber)?.intValue ?? 0
    }

    private static func finalizeTrophyGrant(for winnerRecord: CKRecord, subject: LearningSubject) async throws {
        guard let userId = winnerRecord["userId"] as? String else { return }
        let displayName = winnerRecord["displayName"] as? String ?? "Spieler"
        try await incrementTrophy(
            subject: subject,
            userId: userId,
            displayName: displayName,
            awardID: winnerRecord.recordID.recordName
        )
        winnerRecord["trophyGranted"] = true as CKRecordValue
        winnerRecord["grantUpdatedAt"] = Date() as CKRecordValue
        do {
            try await OnlineStatsService.saveIfUnchanged(record: winnerRecord)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let latest = try await OnlineStatsService.fetchRecord(recordID: winnerRecord.recordID),
                  (latest["trophyGranted"] as? NSNumber)?.boolValue != true else { return }
            latest["trophyGranted"] = true as CKRecordValue
            latest["grantUpdatedAt"] = Date() as CKRecordValue
            try await OnlineStatsService.saveIfUnchanged(record: latest)
        }
    }

    private static func incrementTrophy(
        subject: LearningSubject,
        userId: String,
        displayName: String,
        awardID: String,
        retryCount: Int = 0
    ) async throws {
        let recordID = CKRecord.ID(recordName: "userstats_\(safeRecordComponent(userId))")
        let record = try await OnlineStatsService.fetchRecord(recordID: recordID) ?? CKRecord(recordType: userStatsRecordType, recordID: recordID)
        var awardedIDs = Set((record["awardedTrophyIDs"] as? String ?? "").split(separator: "|").map(String.init))
        guard awardedIDs.insert(awardID).inserted else { return }
        let field = trophyField(for: subject)
        let current = (record[field] as? NSNumber)?.intValue ?? 0
        record["userId"] = userId as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record[field] = (current + 1) as CKRecordValue
        let flagTrophies = field == "dailyFlaggenrunTrophies" ? current + 1 : ((record["dailyFlaggenrunTrophies"] as? NSNumber)?.intValue ?? 0)
        let cityTrophies = field == "dailyStaedterunTrophies" ? current + 1 : ((record["dailyStaedterunTrophies"] as? NSNumber)?.intValue ?? 0)
        record["totalTrophies"] = (flagTrophies + cityTrophies) as CKRecordValue
        record["awardedTrophyIDs"] = awardedIDs.sorted().joined(separator: "|") as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        do {
            try await OnlineStatsService.saveIfUnchanged(record: record)
        } catch let error as CKError where error.code == .serverRecordChanged && retryCount < 4 {
            try await incrementTrophy(
                subject: subject,
                userId: userId,
                displayName: displayName,
                awardID: awardID,
                retryCount: retryCount + 1
            )
        }
    }

    private static func write(_ entry: DailyLeaderboardEntry, to record: CKRecord) {
        record["dateKey"] = entry.dateKey as CKRecordValue
        record["mode"] = entry.mode as CKRecordValue
        record["userId"] = entry.userId as CKRecordValue
        record["displayName"] = entry.displayName as CKRecordValue
        record["bestScore"] = entry.bestScore as CKRecordValue
        record["bestAttemptNumber"] = entry.bestAttemptNumber as CKRecordValue
        record["correctCount"] = entry.correctCount as CKRecordValue
        record["wrongCount"] = entry.wrongCount as CKRecordValue
        record["duration"] = entry.duration as CKRecordValue
        record["remainingTime"] = entry.remainingTime as CKRecordValue
        record["completedAt"] = entry.completedAt as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
    }

    private static func encodedAnswerHistory(_ records: [LeagueAnswerRecord]) -> NSData {
        (try? JSONEncoder().encode(Array(records.prefix(20)))) as NSData? ?? NSData()
    }

    private static func deterministicCountryOrder(_ codes: [String], seed: String) -> [String] {
        var shuffled = codes
        var generator = SeededRandomGenerator(seed: stableHash(seed))
        guard shuffled.count > 1 else { return shuffled }

        for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
            let swapIndex = Int(generator.next(upperBound: UInt64(index + 1)))
            shuffled.swapAt(index, swapIndex)
        }

        return shuffled
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private static func safeRecordComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" ? String(character) : "_"
        }.joined()
    }

    static func isHigherRanked(_ lhs: DailyLeaderboardEntry, _ rhs: DailyLeaderboardEntry) -> Bool {
        if lhs.bestScore != rhs.bestScore { return lhs.bestScore > rhs.bestScore }
        if lhs.correctCount != rhs.correctCount { return lhs.correctCount > rhs.correctCount }
        if lhs.remainingTime != rhs.remainingTime { return lhs.remainingTime > rhs.remainingTime }
        if lhs.duration != rhs.duration { return lhs.duration < rhs.duration }
        return lhs.completedAt < rhs.completedAt
    }
}

extension DailyChallenge {
    init?(record: CKRecord) {
        guard let dateKey = record["dateKey"] as? String,
              let mode = record["mode"] as? String,
              let seed = record["seed"] as? String else { return nil }
        id = record.recordID.recordName
        self.dateKey = dateKey
        self.mode = mode
        self.seed = seed
        flagOrder = (record["flagOrder"] as? String ?? "").split(separator: ",").map(String.init)
        startsAt = (record["startsAt"] as? Date) ?? .distantPast
        endsAt = (record["endsAt"] as? Date) ?? .distantFuture
    }
}

extension DailyAttemptSummary {
    init?(record: CKRecord) {
        id = record.recordID.recordName
        dateKey = record["dateKey"] as? String ?? DailyFlaggenrunService.dateKey()
        mode = record["mode"] as? String ?? DailyFlaggenrunService.mode(for: .countries)
        attemptNumber = (record["attemptNumber"] as? NSNumber)?.intValue ?? 0
        score = (record["score"] as? NSNumber)?.intValue ?? 0
        correctCount = (record["correctCount"] as? NSNumber)?.intValue ?? 0
        wrongCount = (record["wrongCount"] as? NSNumber)?.intValue ?? 0
        duration = (record["duration"] as? NSNumber)?.doubleValue ?? 0
        remainingTime = (record["remainingTime"] as? NSNumber)?.doubleValue ?? 0
        completed = (record["completed"] as? NSNumber)?.boolValue ?? false
        aborted = (record["aborted"] as? NSNumber)?.boolValue ?? false
        updatedAt = (record["updatedAt"] as? Date) ?? .distantPast
        let decodedAnswerRecords: [LeagueAnswerRecord]
        if let data = record["inputHistoryData"] as? Data {
            decodedAnswerRecords = (try? JSONDecoder().decode([LeagueAnswerRecord].self, from: data)) ?? []
        } else if let data = record["inputHistoryData"] as? NSData {
            decodedAnswerRecords = (try? JSONDecoder().decode([LeagueAnswerRecord].self, from: data as Data)) ?? []
        } else {
            decodedAnswerRecords = []
        }
        answerRecords = decodedAnswerRecords
        resultID = decodedAnswerRecords.first?.id ?? UUID()
    }
}

extension DailyLeaderboardEntry {
    init?(record: CKRecord) {
        guard let dateKey = record["dateKey"] as? String,
              let mode = record["mode"] as? String,
              let userId = record["userId"] as? String else { return nil }
        id = record.recordID.recordName
        self.dateKey = dateKey
        self.mode = mode
        self.userId = userId
        displayName = record["displayName"] as? String ?? "Spieler"
        bestScore = (record["bestScore"] as? NSNumber)?.intValue ?? 0
        bestAttemptNumber = (record["bestAttemptNumber"] as? NSNumber)?.intValue ?? 0
        correctCount = (record["correctCount"] as? NSNumber)?.intValue ?? 0
        wrongCount = (record["wrongCount"] as? NSNumber)?.intValue ?? 0
        duration = (record["duration"] as? NSNumber)?.doubleValue ?? 0
        remainingTime = (record["remainingTime"] as? NSNumber)?.doubleValue ?? 0
        completedAt = (record["completedAt"] as? Date) ?? .distantFuture
        updatedAt = (record["updatedAt"] as? Date) ?? .distantPast
    }
}

extension TrophyLeaderboardEntry {
    init?(record: CKRecord) {
        guard let userId = record["userId"] as? String else { return nil }
        id = record.recordID.recordName
        self.userId = userId
        displayName = record["displayName"] as? String ?? "Spieler"
        flagRunTrophies = (record["dailyFlaggenrunTrophies"] as? NSNumber)?.intValue ?? 0
        cityRunTrophies = (record["dailyStaedterunTrophies"] as? NSNumber)?.intValue ?? 0
        updatedAt = (record["updatedAt"] as? Date) ?? .distantPast
    }
}
