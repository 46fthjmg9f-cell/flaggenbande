import SwiftUI
import Foundation

// MARK: - Practice And Show Logic

extension ContentView {
    func cardLimitTitle(_ limit: Int) -> String {
        limit == 0 ? L("Endlos", "Endless") : L("\(limit) Karten", "\(limit) cards")
    }

    func cardLimitSelector(selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("Showmaster-Länge", "Showmaster length"), selection: Binding(
                get: { selection.wrappedValue == 0 ? 0 : 1 },
                set: { mode in
                    Haptics.tap()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        selection.wrappedValue = mode == 0 ? 0 : max(selection.wrappedValue, 10)
                    }
                }
            )) {
                Text(L("Endlos", "Endless")).tag(0)
                Text(L("Begrenzt", "Limited")).tag(1)
            }
            .pickerStyle(.segmented)

            if selection.wrappedValue > 0 {
                HStack(spacing: 12) {
                    Picker(L("Karten", "Cards"), selection: selection) {
                        ForEach(1...300, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 92, height: 116)
                    .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(cardLimitTitle(selection.wrappedValue))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tealAccentColor)
                        Text(L("Wische am Rad, um die gewünschte Anzahl zu wählen.", "Spin the wheel to choose the number of cards."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(L("Der Showmaster läuft, bis du ihn beendest.", "Showmaster runs until you stop it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.28), lineWidth: 1)
        )
    }

    func sessionProgressText(current: Int, limit: Int, subject: LearningSubject) -> String {
        let displayedCurrent = max(current, 1)
        let unit = subject == .capitals ? L("Länder", "countries") : L("Flaggen", "flags")
        return limit == 0 ? L("\(displayedCurrent) \(unit) · Endlos", "\(displayedCurrent) \(unit) · endless") : "\(displayedCurrent) / \(limit) \(unit)"
    }

    func showSessionProgressText() -> String {
        let displayedCurrent = selectedShowCardLimit > 0
            ? min(showSessionCount + 1, selectedShowCardLimit)
            : showSessionCount + 1
        let unit = selectedSubject == .capitals ? L("Land", "country") : L("Flagge", "flag")
        let base = L("\(displayedCurrent). \(unit)", "\(displayedCurrent). \(unit)")
        guard selectedShowCardLimit > 0 else { return base }
        return L("\(base) von \(selectedShowCardLimit)", "\(base) of \(selectedShowCardLimit)")
    }

    func nextPracticeCountry() -> Country {
        let candidates = countries(inContinents: selectedPracticeContinents)
        let unseenCandidates = candidates.filter { !practiceSessionSeenCountryCodes.contains($0.code) }
        let availableCandidates = unseenCandidates.isEmpty ? candidates : unseenCandidates

        if allPracticeCandidatesAreS(candidates) {
            return decayRiskSortedCountries(from: availableCandidates).first ?? allCountries[0]
        }

        let weightedCountries = availableCandidates.flatMap { country in
            Array(repeating: country, count: practiceWeight(for: country))
        }

        return (weightedCountries.isEmpty ? availableCandidates : weightedCountries).randomElement() ?? allCountries[0]
    }

    func allPracticeCandidatesAreS(_ candidates: [Country]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { tier(for: $0) == .s }
    }

    func decayRiskSortedCountries(from countries: [Country]) -> [Country] {
        countries.sorted { first, second in
            let firstDaysUntilDecay = stats(for: first).daysUntilNextTierDecay() ?? Int.max
            let secondDaysUntilDecay = stats(for: second).daysUntilNextTierDecay() ?? Int.max
            if firstDaysUntilDecay != secondDaysUntilDecay {
                return firstDaysUntilDecay < secondDaysUntilDecay
            }
            return decayRiskDate(for: first) < decayRiskDate(for: second)
        }
    }

    func decayRiskDate(for country: Country) -> Date {
        let countryStats = stats(for: country)
        return countryStats.lastKnownAt ?? countryStats.lastPracticedAt ?? .distantPast
    }

    func practiceWeight(for country: Country) -> Int {
        let countryStats = stats(for: country)
        let baseWeight: Int
        switch countryStats.tier {
        case .f: return 8
        case .d: baseWeight = 6
        case .c: baseWeight = 4
        case .b: baseWeight = 3
        case .a: baseWeight = 2
        case .s: baseWeight = 1
        }

        return baseWeight + decayRiskWeight(for: countryStats)
    }

    func decayRiskWeight(for stats: CountryStats) -> Int {
        guard let daysUntilDecay = stats.daysUntilNextTierDecay() else { return 0 }
        switch daysUntilDecay {
        case 0: return 12
        case 1: return 8
        case 2: return 4
        default: return 0
        }
    }

    func prepareShowCard() {
        withAnimation(.easeInOut(duration: 0.22)) {
            currentCountry = nextShowCountry()
            cardIsFlipped = false
            resetCurrentCardHint()
        }
    }

    func nextShowCard() {
        guard !showLimitReached else { return }
        showSessionCount += 1
        showSessionEntries.append(ShowSessionEntry(country: currentCountry))
        updateActiveProfile { profile in
            profile.recordShowmasterCard(country: currentCountry, subject: selectedSubject)
            if showSessionCount == 10 {
                profile.recordCompletedTenBlock()
            }
        }
        checkForUnlockedAchievements()

        guard !showLimitReached else { return }
        prepareShowCard()
    }

    func nextShowCountry() -> Country {
        let availableCountries = countries(inContinents: selectedShowContinents)
        let next: Country
        if showAvoidsRecentRepeats {
            next = nextFromShowDeck(from: availableCountries, excluding: currentCountry)
        } else {
            next = nextRandomCountry(excluding: currentCountry, from: availableCountries)
        }
        rememberShowCountry(next)
        return next
    }

    func nextFromShowDeck(from availableCountries: [Country], excluding country: Country) -> Country {
        let availableCodes = Set(availableCountries.map(\.code))
        showDeckCountryCodes.removeAll { !availableCodes.contains($0) }

        if showDeckCountryCodes.isEmpty {
            refillShowDeck(from: availableCountries, excluding: country)
        }

        if
            availableCountries.count > 1,
            showDeckCountryCodes.first == country.code,
            let swapIndex = showDeckCountryCodes.firstIndex(where: { $0 != country.code })
        {
            showDeckCountryCodes.swapAt(0, swapIndex)
        }

        guard let nextCode = showDeckCountryCodes.first else {
            return nextRandomCountry(excluding: country, from: availableCountries)
        }

        showDeckCountryCodes.removeFirst()
        return availableCountries.first { $0.code == nextCode } ?? nextRandomCountry(excluding: country, from: availableCountries)
    }

    func refillShowDeck(from availableCountries: [Country], excluding country: Country) {
        var codes = availableCountries.map(\.code).shuffled()
        if
            availableCountries.count > 1,
            codes.first == country.code,
            let swapIndex = codes.firstIndex(where: { $0 != country.code })
        {
            codes.swapAt(0, swapIndex)
        }
        showDeckCountryCodes = codes
    }

    func rememberShowCountry(_ country: Country) {
        showRecentCountryCodes.append(country.code)
        if showRecentCountryCodes.count > 8 {
            showRecentCountryCodes.removeFirst(showRecentCountryCodes.count - 8)
        }
    }

    func nextRandomCountry(excluding country: Country, in continent: String = CountryScope.worldwide) -> Country {
        nextRandomCountry(excluding: country, from: countries(inContinent: continent))
    }

    func nextRandomCountry(excluding country: Country, from availableCountries: [Country]) -> Country {
        var next = availableCountries.randomElement() ?? allCountries[0]
        if availableCountries.count > 1 {
            while next == country {
                next = availableCountries.randomElement() ?? allCountries[0]
            }
        }
        return next
    }

    var availableCountries: [Country] {
        let countries = includePartiallyRecognizedFlags ? allPracticeCountries : allCountries
        guard fullVersionUnlocked else {
            return countries.filter { $0.continent == "Europa" }
        }
        return countries
    }

    func countries(inContinent continent: String) -> [Country] {
        if continent == CountryScope.worldwide {
            return availableCountries
        }

        return availableCountries.filter { $0.continent == continent }
    }

    func countries(inContinents selectedContinents: Set<String>) -> [Country] {
        if selectedContinents.contains(CountryScope.worldwide) || selectedContinents.isEmpty {
            return availableCountries
        }

        return availableCountries.filter { selectedContinents.contains($0.continent) }
    }

    func countries(in tier: MasteryTier, continent: String) -> [Country] {
        countries(inContinent: continent)
            .filter { self.tier(for: $0) == tier }
            .sorted { countryName(for: $0) < countryName(for: $1) }
    }

    func countries(in tier: MasteryTier, from countries: [Country]) -> [Country] {
        countries
            .filter { self.tier(for: $0) == tier }
            .sorted { countryName(for: $0) < countryName(for: $1) }
    }

    func statisticsCountries(in tier: MasteryTier, from countries: [Country]) -> [Country] {
        countries
            .filter { self.tier(for: $0) == tier }
            .sorted { first, second in
                let firstHasBeenSeen = stats(for: first).cardReviews > 0
                let secondHasBeenSeen = stats(for: second).cardReviews > 0
                if firstHasBeenSeen != secondHasBeenSeen {
                    return firstHasBeenSeen
                }
                return countryName(for: first) < countryName(for: second)
            }
    }

    func totalSeenFlags(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).cardReviews > 0 }.count
    }

    func totalKnownAtLeastOnceFlags(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).cardKnown > 0 }.count
    }

    func totalCardReviews(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardReviews }
    }

    func totalCardKnown(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardKnown }
    }

    func totalCardUnknown(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardUnknown }
    }

    func aOrBetterCount(in countries: [Country]) -> Int {
        countries.filter { [.s, .a].contains(stats(for: $0).tier) }.count
    }

    func sTierCount(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).tier == .s }.count
    }

    func allSTierHeldDays(in countries: [Country], now: Date = Date()) -> Int {
        guard !countries.isEmpty, countries.allSatisfy({ stats(for: $0).tier == .s }) else { return 0 }
        let sStartDates = countries.compactMap { continuousSTierStartDate(for: stats(for: $0)) }
        guard sStartDates.count == countries.count, let allSStartDate = sStartDates.max() else { return 0 }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: allSStartDate)
        let currentDay = calendar.startOfDay(for: now)
        return max(calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0, 0)
    }

    func continuousSTierStartDate(for stats: CountryStats) -> Date? {
        guard stats.tier == .s else { return nil }
        let history = (stats.tierHistory ?? []).sorted { $0.date < $1.date }
        guard !history.isEmpty else {
            return stats.lastKnownAt ?? stats.lastPracticedAt
        }

        if let lastNonSIndex = history.lastIndex(where: { $0.tier != .s }) {
            return history[(lastNonSIndex + 1)...].first(where: { $0.tier == .s })?.date
        }

        return history.first(where: { $0.tier == .s })?.date ?? stats.lastKnownAt ?? stats.lastPracticedAt
    }

    func totalShowmasterPlayed(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).showmasterPlayed }
    }

    func percent(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0.0 %" }
        return String(format: "%.1f %%", Double(value) / Double(total) * 100)
    }

    func activateHint() {
        guard !cardHintIsVisible else { return }
        Haptics.tap(style: .medium)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            cardHintIsVisible = true
            currentCardUsedHint = true
            hintBlockFeedbackIsVisible = false
        }
    }

    func resetCurrentCardHint() {
        cardHintIsVisible = false
        currentCardUsedHint = false
        hintBlockFeedbackIsVisible = false
    }

    func showHintKnownBlockedFeedback() {
        Haptics.notify(.warning)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
            practiceCardDragOffset = 0
            hintBlockFeedbackIsVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            withAnimation(.easeOut(duration: 0.2)) {
                hintBlockFeedbackIsVisible = false
            }
        }
    }

    func hintText(for country: Country) -> String {
        let answer = selectedSubject == .capitals ? capitalName(for: country) : countryName(for: country)
        let firstLetter = answer.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
        let continent = localizedScope(country.continent)

        if selectedSubject == .capitals {
            return L("Die Hauptstadt beginnt mit \(firstLetter). Das Land liegt in \(continent).", "The capital starts with \(firstLetter). The country is in \(continent).")
        }

        return L("Das Land beginnt mit \(firstLetter) und liegt in \(continent).", "The country starts with \(firstLetter) and is in \(continent).")
    }

    func recordPracticeCard(isKnown: Bool) {
        guard practiceSessionActive, !practiceLimitReached, !practiceRecapPromptIsVisible else { return }
        let reviewedCountry = currentCountry
        let tierBefore = tier(for: reviewedCountry)
        let tierAfter = isKnown ? tierBefore.promoted : tierBefore.demoted
        let sessionChange = PracticeSessionChange(
            country: reviewedCountry,
            wasKnown: isKnown,
            fromTier: tierBefore,
            toTier: tierAfter
        )
        practiceUndoSnapshot = PracticeUndoSnapshot(
            appData: appData,
            currentCountry: reviewedCountry,
            practiceSessionCount: practiceSessionCount,
            practiceSessionKnown: practiceSessionKnown,
            practiceSessionUnknown: practiceSessionUnknown,
            practiceSessionImproved: practiceSessionImproved,
            practiceSessionResults: practiceSessionResults,
            practiceSessionChanges: practiceSessionChanges,
            practiceSessionSeenCountryCodes: practiceSessionSeenCountryCodes,
            cardIsFlipped: cardIsFlipped,
            cardHintIsVisible: cardHintIsVisible,
            currentCardUsedHint: currentCardUsedHint,
            recapEndCounts: recapEndCounts
        )
        practiceSessionSeenCountryCodes.insert(reviewedCountry.code)
        updateActiveProfile { profile in
            profile.recordCardReview(country: reviewedCountry, subject: selectedSubject, isKnown: isKnown)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            practiceSessionCount += 1
            practiceSessionResults.append(isKnown)
            practiceSessionChanges.append(sessionChange)

            if isKnown {
                practiceSessionKnown += 1
                if tierBefore.promoted != tierBefore {
                    practiceSessionImproved += 1
                }
            } else {
                practiceSessionUnknown += 1
            }
        }

        checkForUnlockedAchievements()

        if practiceLimitReached {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                practiceCardDragOffset = 0
                practiceCardEntryOffset = 0
                practiceCardEntryOpacity = 1
                isFinishingPracticeSwipe = false
                recapEndCounts = activeProfile.tierCounts(in: availableCountries)
                practiceHistoryGlobeCountry = nil
                practiceHistoryPreview = PracticeHistoryPreview(change: sessionChange, index: max(practiceSessionCount - 1, 0), total: max(selectedPracticeCardLimit, practiceSessionCount))
                practiceRecapPromptIsVisible = true
            }
        } else {
            nextPracticeCard(entryDirection: isKnown ? 1 : -1)
        }
    }
}
