import SwiftUI
import Foundation
import CloudKit

struct OnlineSubjectStats: Codable {
    let totalPracticed: Int
    let known: Int
    let unknown: Int
    let showmasterPlayed: Int
    let learnedThisWeek: Int
    let tierS: Int
    let tierA: Int
    let tierB: Int
    let tierC: Int
    let tierD: Int
    let tierF: Int
    let tiersByCountryCode: [String: MasteryTier]
    let sTierHistory: [Int]

    var accuracy: Double {
        totalPracticed == 0 ? 0 : Double(known) / Double(totalPracticed)
    }
}

struct OnlinePlayerStats: Identifiable, Codable {
    let id: String
    let playerName: String
    let gameCenterPlayerID: String
    let gameCenterAlias: String
    let totalPracticed: Int
    let known: Int
    let unknown: Int
    let showmasterPlayed: Int
    let learnedThisWeek: Int
    let achievementCount: Int
    let tierS: Int
    let tierA: Int
    let tierB: Int
    let tierC: Int
    let tierD: Int
    let tierF: Int
    let tiersByCountryCode: [String: MasteryTier]
    let achievementIDs: Set<String>
    let sTierHistory: [Int]
    let leagueRating: Int
    let leaguePlayed: Int
    let leagueWins: Int
    let leagueBestScore: Int
    let leagueAverageScore: Double
    let leagueAccuracy: Double
    let countryRunPlayed: Int
    let countryRunBestScore: Int
    let countryRunBestScoreDate: Date?
    let capitalRunPlayed: Int
    let capitalRunBestScore: Int
    let capitalRunBestScoreDate: Date?
    let bestLearningStreak: Int
    let countryStats: OnlineSubjectStats
    let capitalStats: OnlineSubjectStats
    let profileSnapshot: UserProfile?
    let updatedAt: Date

    var accuracy: Double {
        totalPracticed == 0 ? 0 : Double(known) / Double(totalPracticed)
    }

    var displayName: String {
        playerName.isEmpty ? gameCenterAlias : playerName
    }

    var friendCode: String {
        String(id.suffix(6)).uppercased()
    }

    func stats(for subject: LearningSubject) -> OnlineSubjectStats {
        subject == .capitals ? capitalStats : countryStats
    }

    func runPlayed(for subject: LearningSubject) -> Int {
        subject == .capitals ? capitalRunPlayed : countryRunPlayed
    }

    func runBestScore(for subject: LearningSubject) -> Int {
        subject == .capitals ? capitalRunBestScore : countryRunBestScore
    }

    func runBestScoreDate(for subject: LearningSubject) -> Date? {
        subject == .capitals ? capitalRunBestScoreDate : countryRunBestScoreDate
    }
}

enum OnlineLeaderboardCache {
    private struct Payload: Codable {
        let fetchedAt: Date
        let players: [OnlinePlayerStats]
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("online-leaderboard-v1.json")
    }

    static func load(maxAge: TimeInterval = 7 * 24 * 60 * 60) -> [OnlinePlayerStats] {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              Date().timeIntervalSince(payload.fetchedAt) <= maxAge else { return [] }
        return payload.players
    }

    static func save(_ players: [OnlinePlayerStats]) {
        guard let cacheURL else { return }
        let payload = Payload(fetchedAt: Date(), players: players)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

enum OnlineStatsService {
    static let recordType = "PlayerStats"
    static let backupRecordType = "PlayerBackup"
    static let nicknameRecordType = "NicknameClaim"
    static let playerIDKey = "onlinePlayerID"
    #if DEBUG
    static let testFriendName = "FlaggenTest"
    static let testFriendRecordName = "test_friend_flaggenbande"
    #endif
    static let containerIdentifier = "iCloud.de.phil.SpassmitFlaggen"
    static let container = CKContainer(identifier: containerIdentifier)
    static let database = container.publicCloudDatabase
    static let privateDatabase = container.privateCloudDatabase
    private static var cachedAccountStatus: (status: CKAccountStatus, checkedAt: Date)?

    enum OnlineStatsError: LocalizedError {
        case iCloudAccountUnavailable(CKAccountStatus)
        case timeout
        case profileSnapshotEncodingFailed
        case nicknameAlreadyTaken
        case dailyAttemptsExhausted

        var errorDescription: String? {
            switch self {
            case .iCloudAccountUnavailable(.noAccount):
                return "Kein iCloud-Account angemeldet."
            case .iCloudAccountUnavailable(.restricted):
                return "iCloud ist auf diesem Gerät eingeschränkt."
            case .iCloudAccountUnavailable(.couldNotDetermine):
                return "iCloud-Status konnte nicht bestimmt werden."
            case .iCloudAccountUnavailable(.temporarilyUnavailable):
                return "iCloud ist vorübergehend nicht verfügbar."
            case .iCloudAccountUnavailable:
                return "iCloud ist nicht verfügbar."
            case .timeout:
                return "CloudKit hat nicht rechtzeitig geantwortet."
            case .profileSnapshotEncodingFailed:
                return "Die lokale Statistik konnte nicht für iCloud vorbereitet werden."
            case .nicknameAlreadyTaken:
                return "Dieser Spitzname ist schon vergeben."
            case .dailyAttemptsExhausted:
                return "Du hast deine 2 Versuche für heute verbraucht."
            }
        }
    }

    static func playerID(gameCenterPlayerID: String?) -> String {
        if let gameCenterPlayerID, !gameCenterPlayerID.isEmpty {
            return "gc_" + gameCenterPlayerID.map { character in
                character.isLetter || character.isNumber ? String(character) : "_"
            }.joined()
        }

        if let existingID = UserDefaults.standard.string(forKey: playerIDKey) {
            return existingID
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: playerIDKey)
        return newID
    }

    static func upload(
        name: String,
        gameCenterPlayerID: String?,
        gameCenterAlias: String,
        appData: AppData,
        profile: UserProfile,
        countries: [Country],
        subject: LearningSubject,
        achievementIDs: [String]
    ) async throws {
        try await ensureAccountAvailable()
        let playerRecordName = playerID(gameCenterPlayerID: gameCenterPlayerID)
        let recordID = CKRecord.ID(recordName: playerRecordName)
        let record = try await fetchRecord(recordID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        let profileSnapshot = try profileSnapshotData(profile: profile)
        let displayName = normalizedName(name, fallback: gameCenterAlias)
        let countrySubjectStats = subjectStats(profile: profile, countries: countries, subject: .countries)
        let capitalSubjectStats = subjectStats(profile: profile, countries: countries, subject: .capitals)
        let selectedSubjectStats = subject == .capitals ? capitalSubjectStats : countrySubjectStats
        let leagueStats = profile.leagueStats ?? LeagueStats()
        let countryDailyMatches = leagueStats.matches(variant: .daily, subject: .countries).filter { !$0.wasAborted }
        let capitalDailyMatches = leagueStats.matches(variant: .daily, subject: .capitals).filter { !$0.wasAborted }
        let countryBestRun = leagueStats.bestDailyMatch(subject: .countries)
        let capitalBestRun = leagueStats.bestDailyMatch(subject: .capitals)
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await claimNickname(displayName, ownerRecordName: playerRecordName)
        }

        record["playerName"] = displayName as CKRecordValue
        record["gameCenterPlayerID"] = (gameCenterPlayerID ?? "") as CKRecordValue
        record["gameCenterAlias"] = gameCenterAlias as CKRecordValue
        record["totalPracticed"] = selectedSubjectStats.totalPracticed as CKRecordValue
        record["known"] = selectedSubjectStats.known as CKRecordValue
        record["unknown"] = selectedSubjectStats.unknown as CKRecordValue
        record["showmasterPlayed"] = selectedSubjectStats.showmasterPlayed as CKRecordValue
        record["learnedThisWeek"] = selectedSubjectStats.learnedThisWeek as CKRecordValue
        record["achievementCount"] = achievementIDs.count as CKRecordValue
        record["achievementIDs"] = achievementIDs.sorted().joined(separator: "|") as CKRecordValue
        record["leagueRating"] = (profile.leagueStats?.rating ?? 1000) as CKRecordValue
        record["leaguePlayed"] = countryDailyMatches.count as CKRecordValue
        record["leagueWins"] = (profile.leagueStats?.wins ?? 0) as CKRecordValue
        record["leagueBestScore"] = (countryBestRun?.ownScore ?? 0) as CKRecordValue
        record["leagueAverageScore"] = (countryDailyMatches.isEmpty ? 0 : Double(countryDailyMatches.reduce(0) { $0 + $1.ownScore }) / Double(countryDailyMatches.count)) as CKRecordValue
        record["leagueAccuracy"] = leagueStats.dailyAccuracy(subject: .countries) as CKRecordValue
        record["countryRunPlayed"] = countryDailyMatches.count as CKRecordValue
        record["countryRunBestScore"] = (countryBestRun?.ownScore ?? 0) as CKRecordValue
        record["countryRunBestScoreDate"] = countryBestRun?.date as CKRecordValue?
        record["capitalRunPlayed"] = capitalDailyMatches.count as CKRecordValue
        record["capitalRunBestScore"] = (capitalBestRun?.ownScore ?? 0) as CKRecordValue
        record["capitalRunBestScoreDate"] = capitalBestRun?.date as CKRecordValue?
        record["bestLearningStreak"] = (profile.bestLearningStreak ?? 0) as CKRecordValue
        record["tierS"] = selectedSubjectStats.tierS as CKRecordValue
        record["tierA"] = selectedSubjectStats.tierA as CKRecordValue
        record["tierB"] = selectedSubjectStats.tierB as CKRecordValue
        record["tierC"] = selectedSubjectStats.tierC as CKRecordValue
        record["tierD"] = selectedSubjectStats.tierD as CKRecordValue
        record["tierF"] = selectedSubjectStats.tierF as CKRecordValue
        record["tierSnapshot"] = tierSnapshot(from: selectedSubjectStats.tiersByCountryCode) as CKRecordValue
        record["sTierHistory"] = selectedSubjectStats.sTierHistory.map(String.init).joined(separator: "|") as CKRecordValue
        writeSubjectStats(countrySubjectStats, prefix: "country", to: record)
        writeSubjectStats(capitalSubjectStats, prefix: "capital", to: record)
        // Public profiles power friend comparisons, but never expose a local
        // profile PIN. The complete multi-profile backup belongs in the
        // user's private CloudKit database.
        record["profileSnapshot"] = profileSnapshot
        record["profileSnapshotVersion"] = 1 as CKRecordValue
        record["appDataSnapshot"] = nil
        record["appDataSnapshotVersion"] = nil
        record["updatedAt"] = Date() as CKRecordValue

        try await save(record: record)
        try await savePrivateBackup(appData, playerRecordName: playerRecordName)
        try? await deleteLegacyAnonymousRecordIfNeeded(currentRecordName: playerRecordName, gameCenterPlayerID: gameCenterPlayerID)
    }

    static func fetchAppDataSnapshot(gameCenterPlayerID: String?) async throws -> AppData? {
        try await ensureAccountAvailable()
        let playerRecordName = playerID(gameCenterPlayerID: gameCenterPlayerID)
        let backupRecordID = CKRecord.ID(recordName: "current_user_backup")
        if let privateRecord = try await fetchRecord(recordID: backupRecordID, from: privateDatabase),
           let privateSnapshot = decodeAppDataSnapshot(from: privateRecord) {
            return privateSnapshot
        }

        // One-time compatibility path for backups written by older builds to
        // PlayerStats. The next successful upload migrates them to private DB.
        guard let record = try await fetchRecord(recordID: CKRecord.ID(recordName: playerRecordName)) else { return nil }
        if let snapshot = decodeAppDataSnapshot(from: record) { return snapshot }

        if let profileData = record["profileSnapshot"] as? Data,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            return AppData(profiles: [profile], activeProfileID: profile.id)
        }

        if let profileData = record["profileSnapshot"] as? NSData,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData as Data) {
            return AppData(profiles: [profile], activeProfileID: profile.id)
        }

        return nil
    }

    private static func savePrivateBackup(_ appData: AppData, playerRecordName: String) async throws {
        let recordID = CKRecord.ID(recordName: "current_user_backup")
        let record = try await fetchRecord(recordID: recordID, from: privateDatabase)
            ?? CKRecord(recordType: backupRecordType, recordID: recordID)
        record["ownerRecordName"] = playerRecordName as CKRecordValue
        record["appDataSnapshot"] = try appDataSnapshotData(appData)
        record["appDataSnapshotVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record, policy: .changedKeys, in: privateDatabase)
    }

    private static func decodeAppDataSnapshot(from record: CKRecord) -> AppData? {
        if let data = record["appDataSnapshot"] as? Data {
            return try? JSONDecoder().decode(AppData.self, from: data)
        }
        if let data = record["appDataSnapshot"] as? NSData {
            return try? JSONDecoder().decode(AppData.self, from: data as Data)
        }
        return nil
    }

    static func fetchLeaderboard() async throws -> [OnlinePlayerStats] {
        try await ensureAccountAvailable()
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let records = try await queryRecords(query, desiredKeys: leaderboardDesiredKeys)
        return records
            .compactMap(OnlinePlayerStats.init(record:))
            .sorted {
                if $0.totalPracticed == $1.totalPracticed {
                    return $0.accuracy > $1.accuracy
                }
                return $0.totalPracticed > $1.totalPracticed
            }
    }

    static func fetchPlayerStats(recordName: String) async throws -> OnlinePlayerStats? {
        try await ensureAccountAvailable()
        guard let record = try await fetchRecord(recordID: CKRecord.ID(recordName: recordName)) else {
            return nil
        }
        return OnlinePlayerStats(record: record)
    }

    #if DEBUG
    static func createTestFriend(countries: [Country]) async throws {
        try await ensureAccountAvailable()
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: testFriendRecordName))
        let tiers = countries.enumerated().map { index, country in
            let tier: MasteryTier
            switch index % 6 {
            case 0: tier = .s
            case 1: tier = .a
            case 2: tier = .b
            case 3: tier = .c
            case 4: tier = .d
            default: tier = .f
            }
            return (country.code, tier)
        }
        let capitalTiers = countries.enumerated().map { index, country in
            let tier: MasteryTier
            switch (index + 2) % 6 {
            case 0: tier = .s
            case 1: tier = .a
            case 2: tier = .b
            case 3: tier = .c
            case 4: tier = .d
            default: tier = .f
            }
            return (country.code, tier)
        }
        let tierCounts = Dictionary(grouping: tiers.map(\.1), by: { $0 }).mapValues(\.count)
        let capitalTierCounts = Dictionary(grouping: capitalTiers.map(\.1), by: { $0 }).mapValues(\.count)
        let countryStats = OnlineSubjectStats(
            totalPracticed: 418,
            known: 337,
            unknown: 81,
            showmasterPlayed: 12,
            learnedThisWeek: 73,
            tierS: tierCounts[.s] ?? 0,
            tierA: tierCounts[.a] ?? 0,
            tierB: tierCounts[.b] ?? 0,
            tierC: tierCounts[.c] ?? 0,
            tierD: tierCounts[.d] ?? 0,
            tierF: tierCounts[.f] ?? 0,
            tiersByCountryCode: Dictionary(uniqueKeysWithValues: tiers),
            sTierHistory: [19, 21, 23, 24, 26, 28, 29, 31, 33, 34, 35, 37, 38, tierCounts[.s] ?? 0]
        )
        let capitalStats = OnlineSubjectStats(
            totalPracticed: 266,
            known: 198,
            unknown: 68,
            showmasterPlayed: 7,
            learnedThisWeek: 41,
            tierS: capitalTierCounts[.s] ?? 0,
            tierA: capitalTierCounts[.a] ?? 0,
            tierB: capitalTierCounts[.b] ?? 0,
            tierC: capitalTierCounts[.c] ?? 0,
            tierD: capitalTierCounts[.d] ?? 0,
            tierF: capitalTierCounts[.f] ?? 0,
            tiersByCountryCode: Dictionary(uniqueKeysWithValues: capitalTiers),
            sTierHistory: [11, 12, 13, 15, 16, 17, 17, 18, 20, 21, 21, 22, 23, capitalTierCounts[.s] ?? 0]
        )

        record["playerName"] = testFriendName as CKRecordValue
        record["gameCenterPlayerID"] = "test.friend.flaggenbande" as CKRecordValue
        record["gameCenterAlias"] = testFriendName as CKRecordValue
        record["totalPracticed"] = 418 as CKRecordValue
        record["known"] = 337 as CKRecordValue
        record["unknown"] = 81 as CKRecordValue
        record["showmasterPlayed"] = 12 as CKRecordValue
        record["learnedThisWeek"] = 73 as CKRecordValue
        record["achievementCount"] = 9 as CKRecordValue
        record["achievementIDs"] = [
            "first-card",
            "ten-known",
            "fifty-known",
            "fifty-reviews",
            "two-hundred-fifty-reviews",
            "three-day-streak",
            "a-tier-five",
            "first-s-tier",
            "showmaster-ten"
        ].joined(separator: "|") as CKRecordValue
        record["leagueRating"] = 1138 as CKRecordValue
        record["leaguePlayed"] = 18 as CKRecordValue
        record["leagueWins"] = 11 as CKRecordValue
        record["leagueBestScore"] = 1240 as CKRecordValue
        record["leagueAverageScore"] = 840.0 as CKRecordValue
        record["leagueAccuracy"] = 0.82 as CKRecordValue
        record["countryRunPlayed"] = 12 as CKRecordValue
        record["countryRunBestScore"] = 1240 as CKRecordValue
        record["countryRunBestScoreDate"] = Date().addingTimeInterval(-86_400) as CKRecordValue
        record["capitalRunPlayed"] = 6 as CKRecordValue
        record["capitalRunBestScore"] = 880 as CKRecordValue
        record["capitalRunBestScoreDate"] = Date().addingTimeInterval(-172_800) as CKRecordValue
        record["bestLearningStreak"] = 14 as CKRecordValue
        record["tierS"] = (tierCounts[.s] ?? 0) as CKRecordValue
        record["tierA"] = (tierCounts[.a] ?? 0) as CKRecordValue
        record["tierB"] = (tierCounts[.b] ?? 0) as CKRecordValue
        record["tierC"] = (tierCounts[.c] ?? 0) as CKRecordValue
        record["tierD"] = (tierCounts[.d] ?? 0) as CKRecordValue
        record["tierF"] = (tierCounts[.f] ?? 0) as CKRecordValue
        record["tierSnapshot"] = tiers.map { "\($0.0):\($0.1.rawValue)" }.joined(separator: "|") as CKRecordValue
        record["sTierHistory"] = [19, 21, 23, 24, 26, 28, 29, 31, 33, 34, 35, 37, 38, tierCounts[.s] ?? 0].map(String.init).joined(separator: "|") as CKRecordValue
        writeSubjectStats(countryStats, prefix: "country", to: record)
        writeSubjectStats(capitalStats, prefix: "capital", to: record)
        record["profileSnapshotVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
    }
    #endif

    static func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        try await fetchRecord(recordID: recordID, from: database)
    }

    static func fetchRecord(recordID: CKRecord.ID, from targetDatabase: CKDatabase) async throws -> CKRecord? {
        try await withTimeout {
            let operation = CKFetchRecordsOperation(recordIDs: [recordID])
            operation.qualityOfService = .userInitiated
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let lock = NSLock()
                    var matchedResult: Result<CKRecord, Error>?
                    operation.perRecordResultBlock = { _, result in
                        lock.lock()
                        matchedResult = result
                        lock.unlock()
                    }
                    operation.fetchRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            lock.lock()
                            let finalResult = matchedResult
                            lock.unlock()
                            switch finalResult {
                            case .success(let record):
                                continuation.resume(returning: record)
                            case .failure(let error as CKError) where error.code == .unknownItem:
                                continuation.resume(returning: nil)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            case nil:
                                continuation.resume(returning: nil)
                            }
                        case .failure(let error as CKError) where error.code == .unknownItem:
                            continuation.resume(returning: nil)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    targetDatabase.add(operation)
                }
            } onCancel: {
                operation.cancel()
            }
        }
    }

    static func save(record: CKRecord) async throws {
        try await save(record: record, policy: .changedKeys)
    }

    static func saveNew(record: CKRecord) async throws {
        try await save(record: record, policy: .ifServerRecordUnchanged)
    }

    static func saveIfUnchanged(record: CKRecord) async throws {
        try await save(record: record, policy: .ifServerRecordUnchanged)
    }

    private static func save(
        record: CKRecord,
        policy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws {
        try await save(record: record, policy: policy, in: database)
    }

    private static func save(
        record: CKRecord,
        policy: CKModifyRecordsOperation.RecordSavePolicy,
        in targetDatabase: CKDatabase
    ) async throws {
        try await withTimeout {
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = policy
            operation.qualityOfService = .userInitiated
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    targetDatabase.add(operation)
                }
            } onCancel: {
                operation.cancel()
            }
        }
    }

    static func delete(recordID: CKRecord.ID) async throws {
        try await withTimeout {
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
            operation.qualityOfService = .utility
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    database.add(operation)
                }
            } onCancel: {
                operation.cancel()
            }
        }
    }

    static func deleteLegacyAnonymousRecordIfNeeded(currentRecordName: String, gameCenterPlayerID: String?) async throws {
        guard let gameCenterPlayerID, !gameCenterPlayerID.isEmpty else { return }
        guard let legacyRecordName = UserDefaults.standard.string(forKey: playerIDKey) else { return }
        guard legacyRecordName != currentRecordName else { return }

        try await delete(recordID: CKRecord.ID(recordName: legacyRecordName))
    }

    static func queryRecords(_ query: CKQuery, desiredKeys: [String]? = nil) async throws -> [CKRecord] {
        do {
            return try await withTimeout {
                var allRecords: [CKRecord] = []
                var cursor: CKQueryOperation.Cursor?

                repeat {
                    let page = try await queryRecordPage(query: query, cursor: cursor, desiredKeys: desiredKeys)
                    allRecords.append(contentsOf: page.records)
                    cursor = page.cursor
                } while cursor != nil

                return allRecords
            }
        } catch let cloudError as CKError where cloudError.code == .unknownItem {
            return []
        }
    }

    static func queryRecordPage(query: CKQuery, cursor: CKQueryOperation.Cursor?, desiredKeys: [String]? = nil) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        let operation = cursor.map(CKQueryOperation.init(cursor:)) ?? CKQueryOperation(query: query)
        operation.resultsLimit = 100
        operation.desiredKeys = desiredKeys
        operation.qualityOfService = .userInitiated
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var records: [CKRecord] = []
                let lock = NSLock()
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        lock.lock()
                        records.append(record)
                        lock.unlock()
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let cursor):
                        continuation.resume(returning: (records, cursor))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    static func normalizedName(_ name: String, fallback: String = "Spieler") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (fallbackName.isEmpty ? "Spieler" : fallbackName) : trimmed
    }

    static let leaderboardDesiredKeys: [String] = [
        "playerName",
        "gameCenterPlayerID",
        "gameCenterAlias",
        "totalPracticed",
        "known",
        "unknown",
        "showmasterPlayed",
        "learnedThisWeek",
        "achievementCount",
        "achievementIDs",
        "leagueRating",
        "leaguePlayed",
        "leagueWins",
        "leagueBestScore",
        "leagueAverageScore",
        "leagueAccuracy",
        "countryRunPlayed",
        "countryRunBestScore",
        "countryRunBestScoreDate",
        "capitalRunPlayed",
        "capitalRunBestScore",
        "capitalRunBestScoreDate",
        "bestLearningStreak",
        "tierS",
        "tierA",
        "tierB",
        "tierC",
        "tierD",
        "tierF",
        "tierSnapshot",
        "sTierHistory",
        "countryTotalPracticed",
        "countryKnown",
        "countryUnknown",
        "countryShowmasterPlayed",
        "countryLearnedThisWeek",
        "countryTierS",
        "countryTierA",
        "countryTierB",
        "countryTierC",
        "countryTierD",
        "countryTierF",
        "countryTierSnapshot",
        "countrySTierHistory",
        "capitalTotalPracticed",
        "capitalKnown",
        "capitalUnknown",
        "capitalShowmasterPlayed",
        "capitalLearnedThisWeek",
        "capitalTierS",
        "capitalTierA",
        "capitalTierB",
        "capitalTierC",
        "capitalTierD",
        "capitalTierF",
        "capitalTierSnapshot",
        "capitalSTierHistory",
        "updatedAt"
    ]

    static func claimNickname(_ nickname: String, ownerRecordName: String) async throws {
        let key = nicknameKey(for: nickname)
        guard !key.isEmpty else { return }

        let recordID = CKRecord.ID(recordName: "nickname_\(key)")
        if let existingRecord = try await fetchRecord(recordID: recordID) {
            let owner = existingRecord["ownerRecordName"] as? String ?? ""
            if owner != ownerRecordName {
                let legacyOwner = UserDefaults.standard.string(forKey: playerIDKey) ?? ""
                guard !legacyOwner.isEmpty, owner == legacyOwner, ownerRecordName.hasPrefix("gc_") else {
                    throw OnlineStatsError.nicknameAlreadyTaken
                }
                existingRecord["ownerRecordName"] = ownerRecordName as CKRecordValue
                existingRecord["updatedAt"] = Date() as CKRecordValue
                try await save(record: existingRecord)
            }
            return
        }

        let record = CKRecord(recordType: nicknameRecordType, recordID: recordID)
        record["nickname"] = nickname as CKRecordValue
        record["ownerRecordName"] = ownerRecordName as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        do {
            try await saveNew(record: record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let existing = try await fetchRecord(recordID: recordID),
                  existing["ownerRecordName"] as? String == ownerRecordName else {
                throw OnlineStatsError.nicknameAlreadyTaken
            }
        }
    }

    static func nicknameKey(for nickname: String) -> String {
        nickname
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? String(character) : "_"
            }
            .joined()
    }

    static func userFacingMessage(for error: Error) -> String {
        if let onlineError = error as? OnlineStatsError {
            return onlineError.localizedDescription
        }

        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }

        let detail = cloudError.errorUserInfo[NSLocalizedDescriptionKey] as? String ?? cloudError.localizedDescription
        switch cloudError.code {
        case .notAuthenticated:
            return "iCloud ist nicht angemeldet. Melde dich in den iOS-Einstellungen bei iCloud an."
        case .permissionFailure:
            return "CloudKit hat keine Berechtigung für diesen Container. Prüfe iCloud/CloudKit in Signing & Capabilities."
        case .networkUnavailable, .networkFailure:
            return "Keine stabile Netzwerkverbindung zu iCloud."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud ist gerade ausgelastet. Bitte später erneut versuchen."
        case .invalidArguments:
            return "CloudKit lehnt die Datenstruktur ab: \(detail)"
        case .serverRecordChanged:
            return "Der iCloud-Datensatz wurde gleichzeitig geändert. Bitte erneut synchronisieren."
        case .unknownItem:
            return "Der CloudKit-Datensatz existiert noch nicht."
        default:
            return "CloudKit-Fehler \(cloudError.code.rawValue): \(detail)"
        }
    }

    static func tierSnapshot(profile: UserProfile, countries: [Country], subject: LearningSubject) -> String {
        countries
            .map { "\($0.code):\(profile.tier(for: $0, subject: subject).rawValue)" }
            .joined(separator: "|")
    }

    static func tierSnapshot(from tiersByCountryCode: [String: MasteryTier]) -> String {
        tiersByCountryCode
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.rawValue)" }
            .joined(separator: "|")
    }

    static func subjectStats(profile: UserProfile, countries: [Country], subject: LearningSubject) -> OnlineSubjectStats {
        let stats = countries.map { profile.stats(for: $0, subject: subject) }
        let counts = Dictionary(grouping: stats.map(\.tier), by: { $0 }).mapValues(\.count)
        let tiersByCountryCode = Dictionary(uniqueKeysWithValues: countries.map { country in
            (country.code, profile.tier(for: country, subject: subject))
        })

        return OnlineSubjectStats(
            totalPracticed: stats.reduce(0) { $0 + $1.cardReviews },
            known: stats.reduce(0) { $0 + $1.cardKnown },
            unknown: stats.reduce(0) { $0 + $1.cardUnknown },
            showmasterPlayed: stats.reduce(0) { $0 + $1.showmasterPlayed },
            learnedThisWeek: profile.practiceCardsInLastSevenDays(subject: subject),
            tierS: counts[.s] ?? 0,
            tierA: counts[.a] ?? 0,
            tierB: counts[.b] ?? 0,
            tierC: counts[.c] ?? 0,
            tierD: counts[.d] ?? 0,
            tierF: counts[.f] ?? 0,
            tiersByCountryCode: tiersByCountryCode,
            sTierHistory: sTierHistoryValues(profile: profile, countries: countries, subject: subject)
        )
    }

    static func writeSubjectStats(_ stats: OnlineSubjectStats, prefix: String, to record: CKRecord) {
        record["\(prefix)TotalPracticed"] = stats.totalPracticed as CKRecordValue
        record["\(prefix)Known"] = stats.known as CKRecordValue
        record["\(prefix)Unknown"] = stats.unknown as CKRecordValue
        record["\(prefix)ShowmasterPlayed"] = stats.showmasterPlayed as CKRecordValue
        record["\(prefix)LearnedThisWeek"] = stats.learnedThisWeek as CKRecordValue
        record["\(prefix)TierS"] = stats.tierS as CKRecordValue
        record["\(prefix)TierA"] = stats.tierA as CKRecordValue
        record["\(prefix)TierB"] = stats.tierB as CKRecordValue
        record["\(prefix)TierC"] = stats.tierC as CKRecordValue
        record["\(prefix)TierD"] = stats.tierD as CKRecordValue
        record["\(prefix)TierF"] = stats.tierF as CKRecordValue
        record["\(prefix)TierSnapshot"] = tierSnapshot(from: stats.tiersByCountryCode) as CKRecordValue
        record["\(prefix)STierHistory"] = stats.sTierHistory.map(String.init).joined(separator: "|") as CKRecordValue
    }

    static func sTierHistorySnapshot(profile: UserProfile, countries: [Country], subject: LearningSubject, days: Int = 14) -> String {
        sTierHistoryValues(profile: profile, countries: countries, subject: subject, days: days)
            .map(String.init)
            .joined(separator: "|")
    }

    static func sTierHistoryValues(profile: UserProfile, countries: [Country], subject: LearningSubject, days: Int = 14) -> [Int] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day) ?? day
            return countries.reduce(0) { count, country in
                let stats = profile.stats(for: country, subject: subject)
                let historyTier = stats.tierHistory?
                    .filter { $0.date <= endOfDay }
                    .sorted { $0.date < $1.date }
                    .last?
                    .tier
                return count + ((historyTier ?? stats.tier) == .s ? 1 : 0)
            }
        }
    }

    static func profileSnapshotData(profile: UserProfile) throws -> CKRecordValue {
        var publicProfile = profile
        publicProfile.pin = ""
        guard let data = try? JSONEncoder().encode(publicProfile) else {
            throw OnlineStatsError.profileSnapshotEncodingFailed
        }
        return data as NSData
    }

    static func appDataSnapshotData(_ appData: AppData) throws -> CKRecordValue {
        guard let data = try? JSONEncoder().encode(appData) else {
            throw OnlineStatsError.profileSnapshotEncodingFailed
        }
        return data as NSData
    }

    static func ensureAccountAvailable() async throws {
        if let cachedAccountStatus,
           Date().timeIntervalSince(cachedAccountStatus.checkedAt) < 60 {
            guard cachedAccountStatus.status == .available else {
                throw OnlineStatsError.iCloudAccountUnavailable(cachedAccountStatus.status)
            }
            return
        }

        let status: CKAccountStatus = try await withTimeout(seconds: 8) {
            try await withCheckedThrowingContinuation { continuation in
                container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        }

        cachedAccountStatus = (status, Date())

        guard status == .available else {
            throw OnlineStatsError.iCloudAccountUnavailable(status)
        }
    }

    static func withTimeout<T>(seconds: Double = 15, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw OnlineStatsError.timeout
            }

            guard let result = try await group.next() else {
                throw OnlineStatsError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

extension OnlinePlayerStats {
    init?(record: CKRecord) {
        guard let playerName = record["playerName"] as? String else { return nil }
        id = record.recordID.recordName
        self.playerName = playerName
        gameCenterPlayerID = record["gameCenterPlayerID"] as? String ?? ""
        gameCenterAlias = record["gameCenterAlias"] as? String ?? ""
        totalPracticed = (record["totalPracticed"] as? NSNumber)?.intValue ?? 0
        known = (record["known"] as? NSNumber)?.intValue ?? 0
        unknown = (record["unknown"] as? NSNumber)?.intValue ?? 0
        showmasterPlayed = (record["showmasterPlayed"] as? NSNumber)?.intValue ?? 0
        learnedThisWeek = (record["learnedThisWeek"] as? NSNumber)?.intValue ?? 0
        achievementCount = (record["achievementCount"] as? NSNumber)?.intValue ?? 0
        tierS = (record["tierS"] as? NSNumber)?.intValue ?? 0
        tierA = (record["tierA"] as? NSNumber)?.intValue ?? 0
        tierB = (record["tierB"] as? NSNumber)?.intValue ?? 0
        tierC = (record["tierC"] as? NSNumber)?.intValue ?? 0
        tierD = (record["tierD"] as? NSNumber)?.intValue ?? 0
        tierF = (record["tierF"] as? NSNumber)?.intValue ?? 0
        tiersByCountryCode = Self.parseTierSnapshot(record["tierSnapshot"] as? String)
        achievementIDs = Set((record["achievementIDs"] as? String ?? "").split(separator: "|").map(String.init))
        sTierHistory = Self.parseIntSnapshot(record["sTierHistory"] as? String, fallback: tierS)
        leagueRating = (record["leagueRating"] as? NSNumber)?.intValue ?? 1000
        leaguePlayed = (record["leaguePlayed"] as? NSNumber)?.intValue ?? 0
        leagueWins = (record["leagueWins"] as? NSNumber)?.intValue ?? 0
        leagueBestScore = (record["leagueBestScore"] as? NSNumber)?.intValue ?? 0
        leagueAverageScore = (record["leagueAverageScore"] as? NSNumber)?.doubleValue ?? 0
        leagueAccuracy = (record["leagueAccuracy"] as? NSNumber)?.doubleValue ?? 0
        countryRunPlayed = (record["countryRunPlayed"] as? NSNumber)?.intValue ?? 0
        countryRunBestScore = (record["countryRunBestScore"] as? NSNumber)?.intValue ?? 0
        countryRunBestScoreDate = record["countryRunBestScoreDate"] as? Date
        capitalRunPlayed = (record["capitalRunPlayed"] as? NSNumber)?.intValue ?? 0
        capitalRunBestScore = (record["capitalRunBestScore"] as? NSNumber)?.intValue ?? 0
        capitalRunBestScoreDate = record["capitalRunBestScoreDate"] as? Date
        bestLearningStreak = (record["bestLearningStreak"] as? NSNumber)?.intValue ?? 0
        let legacyStats = OnlineSubjectStats(
            totalPracticed: totalPracticed,
            known: known,
            unknown: unknown,
            showmasterPlayed: showmasterPlayed,
            learnedThisWeek: learnedThisWeek,
            tierS: tierS,
            tierA: tierA,
            tierB: tierB,
            tierC: tierC,
            tierD: tierD,
            tierF: tierF,
            tiersByCountryCode: tiersByCountryCode,
            sTierHistory: sTierHistory
        )
        countryStats = Self.parseSubjectStats(record: record, prefix: "country", fallback: legacyStats)
        capitalStats = Self.parseSubjectStats(record: record, prefix: "capital", fallback: legacyStats)
        profileSnapshot = Self.decodeProfileSnapshot(from: record)
        updatedAt = (record["updatedAt"] as? Date) ?? .distantPast
    }

    private static func decodeProfileSnapshot(from record: CKRecord) -> UserProfile? {
        if let profileData = record["profileSnapshot"] as? Data,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            return profile
        }

        if let profileData = record["profileSnapshot"] as? NSData,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData as Data) {
            return profile
        }

        if let appData = record["appDataSnapshot"] as? Data,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: appData) {
            return snapshot.activeProfile
        }

        if let appData = record["appDataSnapshot"] as? NSData,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: appData as Data) {
            return snapshot.activeProfile
        }

        return nil
    }

    private static func parseTierSnapshot(_ snapshot: String?) -> [String: MasteryTier] {
        guard let snapshot else { return [:] }
        return snapshot.split(separator: "|").reduce(into: [String: MasteryTier]()) { result, entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let tier = MasteryTier(rawValue: String(parts[1])) else { return }
            result[String(parts[0])] = tier
        }
    }

    private static func parseIntSnapshot(_ snapshot: String?, fallback: Int) -> [Int] {
        let values = snapshot?.split(separator: "|").compactMap { Int($0) } ?? []
        return values.isEmpty ? [fallback] : values
    }

    private static func parseSubjectStats(record: CKRecord, prefix: String, fallback: OnlineSubjectStats) -> OnlineSubjectStats {
        guard record["\(prefix)TotalPracticed"] != nil ||
              record["\(prefix)Known"] != nil ||
              record["\(prefix)TierSnapshot"] != nil else {
            return fallback
        }

        let tierS = (record["\(prefix)TierS"] as? NSNumber)?.intValue ?? fallback.tierS
        return OnlineSubjectStats(
            totalPracticed: (record["\(prefix)TotalPracticed"] as? NSNumber)?.intValue ?? fallback.totalPracticed,
            known: (record["\(prefix)Known"] as? NSNumber)?.intValue ?? fallback.known,
            unknown: (record["\(prefix)Unknown"] as? NSNumber)?.intValue ?? fallback.unknown,
            showmasterPlayed: (record["\(prefix)ShowmasterPlayed"] as? NSNumber)?.intValue ?? fallback.showmasterPlayed,
            learnedThisWeek: (record["\(prefix)LearnedThisWeek"] as? NSNumber)?.intValue ?? fallback.learnedThisWeek,
            tierS: tierS,
            tierA: (record["\(prefix)TierA"] as? NSNumber)?.intValue ?? fallback.tierA,
            tierB: (record["\(prefix)TierB"] as? NSNumber)?.intValue ?? fallback.tierB,
            tierC: (record["\(prefix)TierC"] as? NSNumber)?.intValue ?? fallback.tierC,
            tierD: (record["\(prefix)TierD"] as? NSNumber)?.intValue ?? fallback.tierD,
            tierF: (record["\(prefix)TierF"] as? NSNumber)?.intValue ?? fallback.tierF,
            tiersByCountryCode: parseTierSnapshot(record["\(prefix)TierSnapshot"] as? String).isEmpty ? fallback.tiersByCountryCode : parseTierSnapshot(record["\(prefix)TierSnapshot"] as? String),
            sTierHistory: parseIntSnapshot(record["\(prefix)STierHistory"] as? String, fallback: tierS)
        )
    }
}
