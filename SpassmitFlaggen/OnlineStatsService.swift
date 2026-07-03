import SwiftUI
import Foundation
import CloudKit

struct OnlineSubjectStats {
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

struct OnlinePlayerStats: Identifiable {
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
}

enum OnlineStatsService {
    static let recordType = "PlayerStats"
    static let nicknameRecordType = "NicknameClaim"
    static let playerIDKey = "onlinePlayerID"
    #if DEBUG
    static let testFriendName = "FlaggenTest"
    static let testFriendRecordName = "test_friend_flaggenbande"
    #endif
    static let containerIdentifier = "iCloud.de.phil.SpassmitFlaggen"
    static let container = CKContainer(identifier: containerIdentifier)
    static let database = container.publicCloudDatabase

    enum OnlineStatsError: LocalizedError {
        case iCloudAccountUnavailable(CKAccountStatus)
        case timeout
        case profileSnapshotEncodingFailed
        case nicknameAlreadyTaken

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
        record["leaguePlayed"] = (profile.leagueStats?.played ?? 0) as CKRecordValue
        record["leagueWins"] = (profile.leagueStats?.wins ?? 0) as CKRecordValue
        record["leagueBestScore"] = (profile.leagueStats?.bestScore ?? 0) as CKRecordValue
        record["leagueAverageScore"] = (profile.leagueStats?.averageScore ?? 0) as CKRecordValue
        record["leagueAccuracy"] = (profile.leagueStats?.accuracy ?? 0) as CKRecordValue
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
        record["profileSnapshot"] = profileSnapshot
        record["profileSnapshotVersion"] = 1 as CKRecordValue
        record["appDataSnapshot"] = try appDataSnapshotData(appData)
        record["appDataSnapshotVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        try await save(record: record)
        try? await deleteLegacyAnonymousRecordIfNeeded(currentRecordName: playerRecordName, gameCenterPlayerID: gameCenterPlayerID)
    }

    static func fetchAppDataSnapshot(gameCenterPlayerID: String?) async throws -> AppData? {
        try await ensureAccountAvailable()
        let playerRecordName = playerID(gameCenterPlayerID: gameCenterPlayerID)
        guard let record = try await fetchRecord(recordID: CKRecord.ID(recordName: playerRecordName)) else {
            return nil
        }

        if let snapshotData = record["appDataSnapshot"] as? Data,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: snapshotData) {
            return snapshot
        }

        if let snapshotData = record["appDataSnapshot"] as? NSData,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: snapshotData as Data) {
            return snapshot
        }

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

    static func fetchLeaderboard() async throws -> [OnlinePlayerStats] {
        try await ensureAccountAvailable()
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let records = try await queryRecords(query)
        return records
            .compactMap(OnlinePlayerStats.init(record:))
            .sorted {
                if $0.totalPracticed == $1.totalPracticed {
                    return $0.accuracy > $1.accuracy
                }
                return $0.totalPracticed > $1.totalPracticed
            }
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
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: recordID) { record, error in
                    if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                        continuation.resume(returning: nil)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: record)
                    }
                }
            }
        }
    }

    static func save(record: CKRecord) async throws {
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .userInitiated
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        }
    }

    static func delete(recordID: CKRecord.ID) async throws {
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
                operation.qualityOfService = .utility
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
        }
    }

    static func deleteLegacyAnonymousRecordIfNeeded(currentRecordName: String, gameCenterPlayerID: String?) async throws {
        guard let gameCenterPlayerID, !gameCenterPlayerID.isEmpty else { return }
        guard let legacyRecordName = UserDefaults.standard.string(forKey: playerIDKey) else { return }
        guard legacyRecordName != currentRecordName else { return }

        try await delete(recordID: CKRecord.ID(recordName: legacyRecordName))
    }

    static func queryRecords(_ query: CKQuery) async throws -> [CKRecord] {
        try await withTimeout {
            var allRecords: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?

            repeat {
                let page = try await queryRecordPage(query: query, cursor: cursor)
                allRecords.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil

            return allRecords
        }
    }

    static func queryRecordPage(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let lock = NSLock()
            let operation = cursor.map(CKQueryOperation.init(cursor:)) ?? CKQueryOperation(query: query)
            operation.resultsLimit = 100
            operation.qualityOfService = .userInitiated
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
    }

    static func normalizedName(_ name: String, fallback: String = "Spieler") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (fallbackName.isEmpty ? "Spieler" : fallbackName) : trimmed
    }

    static func claimNickname(_ nickname: String, ownerRecordName: String) async throws {
        let key = nicknameKey(for: nickname)
        guard !key.isEmpty else { return }

        let recordID = CKRecord.ID(recordName: "nickname_\(key)")
        if let existingRecord = try await fetchRecord(recordID: recordID) {
            let owner = existingRecord["ownerRecordName"] as? String ?? ""
            if owner != ownerRecordName {
                throw OnlineStatsError.nicknameAlreadyTaken
            }
            return
        }

        let record = CKRecord(recordType: nicknameRecordType, recordID: recordID)
        record["nickname"] = nickname as CKRecordValue
        record["ownerRecordName"] = ownerRecordName as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
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
        guard let data = try? JSONEncoder().encode(profile) else {
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
        return Dictionary(uniqueKeysWithValues: snapshot.split(separator: "|").compactMap { entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let tier = MasteryTier(rawValue: String(parts[1])) else { return nil }
            return (String(parts[0]), tier)
        })
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
