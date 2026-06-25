import SwiftUI
import Foundation

extension ContentView {
    var practiceLimitReached: Bool {
        selectedPracticeCardLimit > 0 && practiceSessionCount >= selectedPracticeCardLimit
    }

    var showLimitReached: Bool {
        selectedShowCardLimit > 0 && showSessionCount >= selectedShowCardLimit
    }

    var statisticsCountries: [Country] {
        countries(inContinents: selectedStatisticsContinents)
    }

    var isAllCountriesStatisticsScope: Bool {
        selectedStatisticsContinents.isEmpty || selectedStatisticsContinents.contains(CountryScope.worldwide)
    }

    var duePracticeCountries: [Country] {
        countries(inContinents: selectedPracticeContinents)
    }

    func countryName(for country: Country) -> String {
        localizedCountryName(country, language: appLanguage)
    }

    func capitalName(for country: Country) -> String {
        capitalByCountryCode[country.code] ?? countryName(for: country)
    }

    func stats(for country: Country) -> CountryStats {
        activeProfile.stats(for: country, subject: selectedSubject)
    }

    func tier(for country: Country) -> MasteryTier {
        activeProfile.tier(for: country, subject: selectedSubject)
    }

    var filteredStatisticsCountries: [Country] {
        let scopedCountries = countries(inContinents: selectedStatisticsContinents)
        let trimmedSearch = statisticsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return scopedCountries }

        return scopedCountries.filter {
            countryName(for: $0).localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.name.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.continent.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.code.localizedCaseInsensitiveContains(trimmedSearch) ||
            localizedScope($0.continent).localizedCaseInsensitiveContains(trimmedSearch) ||
            capitalName(for: $0).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var hasStatisticsSearch: Bool {
        !statisticsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func masteryScore(in countries: [Country]) -> Double {
        guard !countries.isEmpty else { return 0 }
        let total = countries.reduce(0) { partialResult, country in
            partialResult + tierScoreValue(for: stats(for: country).tier)
        }
        return total / Double(countries.count)
    }

    func tierScoreValue(for tier: MasteryTier) -> Double {
        switch tier {
        case .f: return 0.0
        case .d: return 0.2
        case .c: return 0.4
        case .b: return 0.6
        case .a: return 0.8
        case .s: return 1.0
        }
    }

    func tierScoreRows(in countries: [Country]) -> [TierScoreRow] {
        MasteryTier.allCases.map { tier in
            let count = countries.filter { stats(for: $0).tier == tier }.count
            return TierScoreRow(tier: tier, count: count, value: tierScoreValue(for: tier))
        }
    }

    func scopeScoreRows(in countries: [Country]) -> [ScopeScoreRow] {
        let visibleContinents = continents.filter { continent in
            countries.contains { $0.continent == continent }
        }
        return visibleContinents.map { continent in
            let continentCountries = countries.filter { $0.continent == continent }
            return ScopeScoreRow(
                title: localizedScope(continent),
                score: masteryScore(in: continentCountries),
                practiced: totalCardReviews(in: continentCountries),
                total: continentCountries.count
            )
        }
        .sorted { $0.score > $1.score }
    }

    func practiceBalanceRows(in countries: [Country], range: PracticeBalanceRange) -> [PracticeBalanceRow] {
        let knownCount = practiceCountByDay(profile: activeProfile.practiceKnownCardsByDay, subject: selectedSubject, days: range.days)
        let unknownCount = practiceCountByDay(profile: activeProfile.practiceUnknownCardsByDay, subject: selectedSubject, days: range.days)
        return [
            PracticeBalanceRow(title: L("Gewusst", "Known"), count: knownCount, color: .green),
            PracticeBalanceRow(title: L("Nicht gewusst", "Not known"), count: unknownCount, color: .red)
        ]
    }

    func practiceBalancePoints(profile: UserProfile? = nil, range: PracticeBalanceRange, pageOffset: Int) -> [PracticeBalanceHistoryPoint] {
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return analysisPeriodStarts(range: range, pageOffset: pageOffset, today: today, calendar: calendar).map { day in
            PracticeBalanceHistoryPoint(
                date: day,
                known: practiceCount(on: day, countsByDay: sourceProfile.practiceKnownCardsByDay, subject: selectedSubject, calendar: calendar),
                unknown: practiceCount(on: day, countsByDay: sourceProfile.practiceUnknownCardsByDay, subject: selectedSubject, calendar: calendar)
            )
        }
    }

    func practiceBalanceMaxValue(profile: UserProfile? = nil) -> Int {
        let sourceProfile = profile ?? activeProfile
        let prefix = "\(selectedSubject.rawValue)|"
        let knownMax = sourceProfile.practiceKnownCardsByDay?
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .max() ?? 0
        let unknownMax = sourceProfile.practiceUnknownCardsByDay?
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .max() ?? 0
        return max(knownMax, unknownMax, 1)
    }

    func learnedPracticeMaxValue(profile: UserProfile? = nil) -> Int {
        let sourceProfile = profile ?? activeProfile
        let prefix = "\(selectedSubject.rawValue)|"
        return max(
            sourceProfile.practiceKnownCardsByDay?
                .filter { $0.key.hasPrefix(prefix) }
                .map(\.value)
                .max() ?? 0,
            1
        )
    }

    func learnedPracticePoints(profile: UserProfile? = nil, range: PracticeBalanceRange, pageOffset: Int) -> [PracticeBalanceHistoryPoint] {
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return analysisPeriodStarts(range: range, pageOffset: pageOffset, today: today, calendar: calendar).map { day in
            PracticeBalanceHistoryPoint(
                date: day,
                known: practiceCount(on: day, countsByDay: sourceProfile.practiceKnownCardsByDay, subject: selectedSubject, calendar: calendar),
                unknown: 0
            )
        }
    }

    func nextLearnedPracticePoints(profile: UserProfile? = nil, range: PracticeBalanceRange, pageOffset: Int) -> [PracticeBalanceHistoryPoint] {
        guard pageOffset < 0 else { return [] }
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOffset = pageOffset + 1
        let endOffset = min(pageOffset + range.days, 0)
        guard startOffset <= endOffset else { return [] }

        return (startOffset...endOffset).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return PracticeBalanceHistoryPoint(
                date: day,
                known: practiceCount(on: day, countsByDay: sourceProfile.practiceKnownCardsByDay, subject: selectedSubject, calendar: calendar),
                unknown: 0
            )
        }
    }

    func nextPracticeBalancePoints(profile: UserProfile? = nil, range: PracticeBalanceRange, pageOffset: Int) -> [PracticeBalanceHistoryPoint] {
        guard pageOffset < 0 else { return [] }
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOffset = pageOffset + 1
        let endOffset = min(pageOffset + range.days, 0)
        guard startOffset <= endOffset else { return [] }

        return (startOffset...endOffset).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return PracticeBalanceHistoryPoint(
                date: day,
                known: practiceCount(on: day, countsByDay: sourceProfile.practiceKnownCardsByDay, subject: selectedSubject, calendar: calendar),
                unknown: practiceCount(on: day, countsByDay: sourceProfile.practiceUnknownCardsByDay, subject: selectedSubject, calendar: calendar)
            )
        }
    }

    func practiceCountByDay(profile countsByDay: [String: Int]?, subject: LearningSubject, days: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let prefix = "\(subject.rawValue)|"
        let today = calendar.startOfDay(for: now)
        let validDayKeys = Set((0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                "\(prefix)\(UserProfile.dayKey(for: $0, calendar: calendar))"
            }
        })
        return countsByDay?
            .filter { validDayKeys.contains($0.key) }
            .map(\.value)
            .reduce(0, +) ?? 0
    }

    func practiceCount(on day: Date, countsByDay: [String: Int]?, subject: LearningSubject, calendar: Calendar = .current) -> Int {
        countsByDay?["\(subject.rawValue)|\(UserProfile.dayKey(for: day, calendar: calendar))"] ?? 0
    }

    func maxKnownCardsInOneDay(subject: LearningSubject) -> Int {
        let prefix = "\(subject.rawValue)|"
        return activeProfile.practiceKnownCardsByDay?
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .max() ?? 0
    }

    func firstLearnedCountry(in countries: [Country]) -> (country: Country, date: Date)? {
        countries.compactMap { country -> (Country, Date)? in
            guard let date = stats(for: country).lastKnownAt else { return nil }
            return (country, date)
        }
        .sorted { $0.1 < $1.1 }
        .first
    }

    func compactDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == .german ? "de_DE" : "en_US")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func flaggenbossPoints(profile: UserProfile? = nil, in countries: [Country], range: PracticeBalanceRange, pageOffset: Int) -> [ScoreHistoryPoint] {
        guard !countries.isEmpty else { return [] }
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let periodStarts = analysisPeriodStarts(range: range, pageOffset: pageOffset, today: today, calendar: calendar)

        return periodStarts.map { periodStart in
            let periodEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: periodStart) ?? periodStart
            let total = countries.reduce(0.0) { partialResult, country in
                let countryStats = sourceProfile.stats(for: country, subject: selectedSubject)
                return partialResult + tierScoreValue(for: tier(for: countryStats, at: periodEnd))
            }
            return ScoreHistoryPoint(date: periodStart, score: total / Double(countries.count))
        }
    }

    func nextFlaggenbossPoints(profile: UserProfile? = nil, in countries: [Country], range: PracticeBalanceRange, pageOffset: Int) -> [ScoreHistoryPoint] {
        guard !countries.isEmpty, pageOffset < 0 else { return [] }
        let sourceProfile = profile ?? activeProfile
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOffset = pageOffset + 1
        let endOffset = min(pageOffset + range.days, 0)
        guard startOffset <= endOffset else { return [] }

        return (startOffset...endOffset).compactMap { offset in
            guard let periodStart = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let periodEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: periodStart) ?? periodStart
            let total = countries.reduce(0.0) { partialResult, country in
                let countryStats = sourceProfile.stats(for: country, subject: selectedSubject)
                return partialResult + tierScoreValue(for: tier(for: countryStats, at: periodEnd))
            }
            return ScoreHistoryPoint(date: periodStart, score: total / Double(countries.count))
        }
    }

    func analysisPeriodStarts(range: PracticeBalanceRange, pageOffset: Int, today: Date, calendar: Calendar) -> [Date] {
        let count = range.days
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: pageOffset - (count - 1 - index), to: today)
        }
    }

    func periodStart(for granularity: ScoreHistoryGranularity, index: Int, count: Int, pageOffset: Int, today: Date, calendar: Calendar) -> Date? {
        switch granularity {
        case .days:
            return calendar.date(byAdding: .day, value: pageOffset * count - (count - 1 - index), to: today)
        case .weeks:
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return calendar.date(byAdding: .weekOfYear, value: pageOffset * count - (count - 1 - index), to: currentWeek)
        case .months:
            let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            return calendar.date(byAdding: .month, value: pageOffset * count - (count - 1 - index), to: currentMonth)
        }
    }

    func periodEnd(for granularity: ScoreHistoryGranularity, periodStart: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component
        switch granularity {
        case .days: component = .day
        case .weeks: component = .weekOfYear
        case .months: component = .month
        }
        return calendar.date(byAdding: DateComponents(calendar: calendar, timeZone: calendar.timeZone, second: -1), to: calendar.date(byAdding: component, value: 1, to: periodStart) ?? periodStart) ?? periodStart
    }

    func tier(for stats: CountryStats, at date: Date) -> MasteryTier {
        guard let history = stats.tierHistory, !history.isEmpty else {
            return (stats.lastPracticedAt ?? .distantPast) <= date ? stats.tier : .f
        }
        return history
            .filter { $0.date <= date }
            .sorted { $0.date < $1.date }
            .last?
            .tier ?? .f
    }


}
