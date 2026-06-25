import SwiftUI
import Foundation

enum LearningSubject: String, CaseIterable, Identifiable {
    case countries
    case capitals

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .countries: return localized("Länder", "Countries", language: language)
        case .capitals: return localized("Hauptstädte", "Capitals", language: language)
        }
    }

    func displayTitle(language: AppLanguage) -> String {
        switch self {
        case .countries: return localized("Länderflaggen", "Country flags", language: language)
        case .capitals: return localized("Hauptstädte", "Capitals", language: language)
        }
    }

    func statsKey(for country: Country) -> String {
        switch self {
        case .countries: return country.code
        case .capitals: return "capital_\(country.code)"
        }
    }
}

enum MasteryTier: String, CaseIterable, Identifiable, Codable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .s: return "Stufe S"
        case .a: return "Stufe A"
        case .b: return "Stufe B"
        case .c: return "Stufe C"
        case .d: return "Stufe D"
        case .f: return "Stufe F"
        }
    }

    var description: String {
        switch self {
        case .s: return "Perfekt"
        case .a: return "Sehr sicher"
        case .b: return "Sicher"
        case .c: return "Noch wackelig"
        case .d: return "Schwer"
        case .f: return "Noch nie gekonnt"
        }
    }

    var color: Color {
        switch self {
        case .s: return .blue
        case .a: return .green
        case .b: return .mint
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }

    var promoted: MasteryTier {
        switch self {
        case .s: return .s
        case .a: return .s
        case .b: return .a
        case .c: return .b
        case .d: return .c
        case .f: return .d
        }
    }

    var demoted: MasteryTier {
        switch self {
        case .s: return .a
        case .a: return .b
        case .b: return .c
        case .c: return .d
        case .d: return .f
        case .f: return .f
        }
    }
}

struct TierDecayChange: Identifiable {
    var statsKey: String = ""
    let from: MasteryTier
    let to: MasteryTier
    let daysSinceLastPractice: Int

    var id: String {
        "\(statsKey)-\(from.rawValue)-\(to.rawValue)-\(daysSinceLastPractice)"
    }
}

struct TierDecayPopup: Identifiable {
    let id = UUID()
    let changes: [TierDecayChange]

    var maxDaysSinceLastPractice: Int {
        changes.map(\.daysSinceLastPractice).max() ?? 0
    }

    var groupedChanges: [(from: MasteryTier, to: MasteryTier, count: Int)] {
        let grouped = Dictionary(grouping: changes) { "\($0.from.rawValue)-\($0.to.rawValue)" }
        return grouped.compactMap { _, changes in
            guard let first = changes.first else { return nil }
            return (from: first.from, to: first.to, count: changes.count)
        }
        .sorted { lhs, rhs in
            if lhs.from.rawValue == rhs.from.rawValue {
                return lhs.to.rawValue < rhs.to.rawValue
            }
            return lhs.from.rawValue < rhs.from.rawValue
        }
    }
}

struct TierHistoryEntry: Codable, Identifiable {
    let date: Date
    let tier: MasteryTier

    var id: String { "\(date.timeIntervalSince1970)-\(tier.rawValue)" }
}

struct LeagueAnswerRecord: Identifiable, Codable {
    let id: UUID
    let countryCode: String
    let countryName: String
    let submittedAnswer: String
    let detectedCountryName: String
    let wasCorrect: Bool
    let responseTime: Double
    let pointsAwarded: Int
}

struct LeagueMatchResult: Identifiable, Codable {
    let id: UUID
    let date: Date
    let opponentName: String
    let ownScore: Int
    let opponentScore: Int
    let correct: Int
    let wrong: Int
    let duration: Int
    let answerDetails: [LeagueAnswerRecord]?
    let ratingBefore: Int?
    let ratingAfter: Int?
    let ratingDelta: Int?

    var totalAnswers: Int {
        correct + wrong
    }

    var accuracy: Double {
        totalAnswers == 0 ? 0 : Double(correct) / Double(totalAnswers)
    }

    var didWin: Bool {
        ownScore >= opponentScore
    }
}

struct LeagueStats: Codable {
    var rating: Int = 1000
    var played: Int = 0
    var wins: Int = 0
    var draws: Int = 0
    var losses: Int = 0
    var bestScore: Int = 0
    var totalScore: Int = 0
    var totalCorrect: Int = 0
    var totalWrong: Int = 0
    var currentWinStreak: Int = 0
    var bestWinStreak: Int = 0
    var recentMatches: [LeagueMatchResult] = []

    var averageScore: Double { 0 }

    var accuracy: Double {
        let total = totalCorrect + totalWrong
        return total == 0 ? 0 : Double(totalCorrect) / Double(total)
    }

    var leagueName: String {
        switch rating {
        case ..<800: return "Bronze"
        case 800..<1100: return "Silber"
        case 1100..<1400: return "Gold"
        case 1400..<1700: return "Platin"
        case 1700..<2000: return "Meister"
        default: return "Legende"
        }
    }

    var division: String {
        let clampedRating = max(rating, 100)
        let positionInLeague = clampedRating % 300
        switch positionInLeague {
        case 0..<100: return "III"
        case 100..<200: return "II"
        default: return "I"
        }
    }

    var leagueTitle: String {
        "\(leagueName) \(division)"
    }

    var nextDivisionRating: Int {
        let clampedRating = max(rating, 100)
        return ((clampedRating / 100) + 1) * 100
    }

    mutating func recordMatch(_ result: LeagueMatchResult, opponentRating: Int) {
        played += 1
        bestScore = max(bestScore, result.ownScore)
        totalCorrect += result.correct
        totalWrong += result.wrong
        currentWinStreak = result.ownScore > 0 ? currentWinStreak + 1 : 0
        bestWinStreak = max(bestWinStreak, currentWinStreak)

        recentMatches.insert(result, at: 0)
        recentMatches = Array(recentMatches.prefix(12))
    }
}

struct LeagueAnswerMatch {
    let country: Country
    let matchedName: String
    let normalizedAnswer: String
    let normalizedMatchedName: String
    let confidence: Double
    let runnerUpConfidence: Double

    var isCertain: Bool {
        normalizedAnswer.count >= 3
            && confidence >= 0.84
            && confidence - runnerUpConfidence >= 0.07
    }

    var isAcceptable: Bool {
        normalizedAnswer.count >= 3
            && confidence >= 0.72
            && confidence - runnerUpConfidence >= 0.04
    }
}

enum LeagueMatchPhase {
    case loading
    case countdown
    case playing
    case feedback
}

struct CountryStats: Codable {
    private static let tierDecayIntervalDays = 3

    var attempts: Int = 0
    var correct: Int = 0
    var wrong: Int = 0
    var cardReviews: Int = 0
    var cardKnown: Int = 0
    var cardUnknown: Int = 0
    var showmasterPlayed: Int = 0
    var storedTier: MasteryTier = .f
    var totalResponseTime: Double = 0
    var fastestResponseTime: Double?
    var slowestResponseTime: Double?
    var lastPracticedAt: Date?
    var lastKnownAt: Date?
    var lastTierDecayAt: Date?
    var tierHistory: [TierHistoryEntry]?

    var accuracy: Double {
        attempts == 0 ? 0 : Double(correct) / Double(attempts)
    }

    var cardAccuracy: Double {
        cardReviews == 0 ? 0 : Double(cardKnown) / Double(cardReviews)
    }

    var averageResponseTime: Double? {
        attempts == 0 ? nil : totalResponseTime / Double(attempts)
    }

    var tier: MasteryTier {
        storedTier
    }

    mutating func recordQuizAnswer(isCorrect: Bool, responseTime: Double) {
        attempts += 1
        totalResponseTime += responseTime
        fastestResponseTime = minOptional(fastestResponseTime, responseTime)
        slowestResponseTime = maxOptional(slowestResponseTime, responseTime)

        if isCorrect {
            correct += 1
        } else {
            wrong += 1
        }
    }

    mutating func recordCardReview(isKnown: Bool, now: Date = Date()) {
        cardReviews += 1
        lastPracticedAt = now
        lastTierDecayAt = nil

        if isKnown {
            cardKnown += 1
            lastKnownAt = now
            storedTier = storedTier.promoted
        } else {
            cardUnknown += 1
            storedTier = storedTier.demoted
        }
        appendTierHistory(tier: storedTier, date: now)
    }

    mutating func recordShowmasterCard() {
        showmasterPlayed += 1
    }

    mutating func applyWeeklyDecay(now: Date = Date(), calendar: Calendar = .current) -> TierDecayChange? {
        guard storedTier != .f else { return nil }
        let knownReferenceDate = lastKnownAt ?? lastPracticedAt
        guard let knownReferenceDate else { return nil }
        let decayReferenceDate = lastTierDecayAt ?? knownReferenceDate
        guard let daysSinceReference = daysSinceDecayReference(now: now, calendar: calendar),
              daysSinceReference >= Self.tierDecayIntervalDays else { return nil }

        let decaySteps = min(daysSinceReference / Self.tierDecayIntervalDays, decayDistanceToF)
        guard decaySteps > 0 else { return nil }

        let tierBeforeDecay = storedTier
        for _ in 0..<decaySteps {
            storedTier = storedTier.demoted
        }
        lastTierDecayAt = calendar.date(byAdding: .day, value: decaySteps * Self.tierDecayIntervalDays, to: decayReferenceDate) ?? now
        appendTierHistory(tier: storedTier, date: lastTierDecayAt ?? now)

        let daysSinceLastKnown = calendar.dateComponents([.day], from: knownReferenceDate, to: now).day ?? daysSinceReference
        return TierDecayChange(from: tierBeforeDecay, to: storedTier, daysSinceLastPractice: daysSinceLastKnown)
    }

    func daysUntilNextTierDecay(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard storedTier != .f, let daysSinceReference = daysSinceDecayReference(now: now, calendar: calendar) else { return nil }
        return max(Self.tierDecayIntervalDays - daysSinceReference, 0)
    }

    private var decayDistanceToF: Int {
        switch storedTier {
        case .s: return 5
        case .a: return 4
        case .b: return 3
        case .c: return 2
        case .d: return 1
        case .f: return 0
        }
    }

    private func daysSinceDecayReference(now: Date, calendar: Calendar) -> Int? {
        let knownReferenceDate = lastKnownAt ?? lastPracticedAt
        guard let knownReferenceDate else { return nil }
        let decayReferenceDate = lastTierDecayAt ?? knownReferenceDate
        return calendar.dateComponents([.day], from: decayReferenceDate, to: now).day
    }

    mutating func appendTierHistory(tier: MasteryTier, date: Date) {
        var history = tierHistory ?? []
        if let last = history.last, Calendar.current.isDate(last.date, inSameDayAs: date), last.tier == tier {
            return
        }
        history.append(TierHistoryEntry(date: date, tier: tier))
        tierHistory = Array(history.suffix(21))
    }

    private func minOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return min(current, newValue)
    }

    private func maxOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return max(current, newValue)
    }
}

struct UserProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var pin: String
    var totalAnswers: Int = 0
    var correctAnswers: Int = 0
    var wrongAnswers: Int = 0
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var totalResponseTime: Double = 0
    var fastestResponseTime: Double?
    var slowestResponseTime: Double?
    var showmasterCards: Int = 0
    var byCountry: [String: CountryStats] = [:]
    var learningStreak: Int?
    var bestLearningStreak: Int?
    var lastLearningStreakDate: Date?
    var practiceCardsByDay: [String: Int]?
    var practiceKnownCardsByDay: [String: Int]?
    var practiceUnknownCardsByDay: [String: Int]?
    var perfectFullPracticeSessionSubjects: [String]?
    var announcedAchievementIDs: [String]?
    var achievedAchievementDates: [String: Date]?
    var leagueStats: LeagueStats?
    var partyRoundsPlayed: Int?

    var accuracy: Double {
        totalAnswers == 0 ? 0 : Double(correctAnswers) / Double(totalAnswers)
    }

    var averageResponseTime: Double? {
        totalAnswers == 0 ? nil : totalResponseTime / Double(totalAnswers)
    }

    mutating func recordQuizAnswer(country: Country, isCorrect: Bool, responseTime: Double) {
        totalAnswers += 1
        totalResponseTime += responseTime
        fastestResponseTime = minOptional(fastestResponseTime, responseTime)
        slowestResponseTime = maxOptional(slowestResponseTime, responseTime)

        if isCorrect {
            correctAnswers += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            wrongAnswers += 1
            currentStreak = 0
        }

        var countryStats = byCountry[country.code] ?? CountryStats()
        countryStats.recordQuizAnswer(isCorrect: isCorrect, responseTime: responseTime)
        byCountry[country.code] = countryStats
    }

    mutating func recordCardReview(country: Country, subject: LearningSubject = .countries, isKnown: Bool, now: Date = Date(), calendar: Calendar = .current) {
        let key = subject.statsKey(for: country)
        var countryStats = byCountry[key] ?? CountryStats()
        countryStats.recordCardReview(isKnown: isKnown, now: now)
        byCountry[key] = countryStats

        let dayKey = Self.practiceDayKey(for: now, subject: subject, calendar: calendar)
        var cardsByDay = practiceCardsByDay ?? [:]
        cardsByDay[dayKey, default: 0] += 1
        practiceCardsByDay = cardsByDay

        if isKnown {
            var knownCardsByDay = practiceKnownCardsByDay ?? [:]
            knownCardsByDay[dayKey, default: 0] += 1
            practiceKnownCardsByDay = knownCardsByDay
        } else {
            var unknownCardsByDay = practiceUnknownCardsByDay ?? [:]
            unknownCardsByDay[dayKey, default: 0] += 1
            practiceUnknownCardsByDay = unknownCardsByDay
        }
    }

    func maxPracticeCardsInOneDay(subject: LearningSubject) -> Int {
        let prefix = "\(subject.rawValue)|"
        return practiceCardsByDay?
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .max() ?? 0
    }

    func practiceCardsInLastSevenDays(subject: LearningSubject, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let prefix = "\(subject.rawValue)|"
        let validDayKeys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map {
                "\(prefix)\(Self.dayKey(for: $0, calendar: calendar))"
            }
        })

        return practiceCardsByDay?
            .filter { validDayKeys.contains($0.key) }
            .map(\.value)
            .reduce(0, +) ?? 0
    }

    mutating func recordPerfectFullPracticeSession(subject: LearningSubject) {
        var subjects = Set(perfectFullPracticeSessionSubjects ?? [])
        subjects.insert(subject.rawValue)
        perfectFullPracticeSessionSubjects = Array(subjects).sorted()
    }

    func hasPerfectFullPracticeSession(subject: LearningSubject) -> Bool {
        Set(perfectFullPracticeSessionSubjects ?? []).contains(subject.rawValue)
    }

    static func practiceDayKey(for date: Date, subject: LearningSubject, calendar: Calendar = .current) -> String {
        "\(subject.rawValue)|\(dayKey(for: date, calendar: calendar))"
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    mutating func recordCompletedTenBlock(on date: Date = Date(), calendar: Calendar = .current) {
        if let lastLearningStreakDate, calendar.isDate(lastLearningStreakDate, inSameDayAs: date) {
            return
        }

        if
            let lastLearningStreakDate,
            let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
            calendar.isDate(lastLearningStreakDate, inSameDayAs: yesterday)
        {
            learningStreak = (learningStreak ?? 0) + 1
        } else {
            learningStreak = 1
        }

        bestLearningStreak = max(bestLearningStreak ?? 0, learningStreak ?? 0)
        lastLearningStreakDate = date
    }

    mutating func applyWeeklyTierDecay(now: Date = Date()) -> [TierDecayChange] {
        var changes: [TierDecayChange] = []
        for key in Array(byCountry.keys) {
            guard var countryStats = byCountry[key] else { continue }
            if var change = countryStats.applyWeeklyDecay(now: now) {
                byCountry[key] = countryStats
                change.statsKey = key
                changes.append(change)
            }
        }
        return changes
    }

    mutating func recordShowmasterCard(country: Country, subject: LearningSubject = .countries) {
        showmasterCards += 1
        let key = subject.statsKey(for: country)
        var countryStats = byCountry[key] ?? CountryStats()
        countryStats.recordShowmasterCard()
        byCountry[key] = countryStats
    }

    mutating func recordLeagueMatch(_ result: LeagueMatchResult, opponentRating: Int = 1000) {
        var stats = leagueStats ?? LeagueStats()
        stats.recordMatch(result, opponentRating: opponentRating)
        leagueStats = stats
    }

    mutating func recordPartyRound() {
        partyRoundsPlayed = (partyRoundsPlayed ?? 0) + 1
    }

    func stats(for country: Country, subject: LearningSubject = .countries) -> CountryStats {
        byCountry[subject.statsKey(for: country)] ?? CountryStats()
    }

    func tier(for country: Country, subject: LearningSubject = .countries) -> MasteryTier {
        stats(for: country, subject: subject).tier
    }

    func countries(in tier: MasteryTier, from countries: [Country] = allCountries) -> [Country] {
        countries.filter { self.tier(for: $0) == tier }.sorted { $0.name < $1.name }
    }

    func tierCounts(in countries: [Country] = allCountries) -> [MasteryTier: Int] {
        Dictionary(uniqueKeysWithValues: MasteryTier.allCases.map { tier in
            (tier, self.countries(in: tier, from: countries).count)
        })
    }

    private func minOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return min(current, newValue)
    }

    private func maxOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return max(current, newValue)
    }
}

struct AppData: Codable {
    var profiles: [UserProfile] = []
    var activeProfileID: UUID?

    var activeProfile: UserProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }
}
