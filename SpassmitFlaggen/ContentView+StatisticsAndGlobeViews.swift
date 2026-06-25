import SwiftUI
import Foundation

// MARK: - Statistics And Globe Views

extension ContentView {
    var achievementsView: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(tealAccentColor)
                        .frame(width: 38, height: 38)
                        .background(tealAccentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(unlockedAchievementCount)/\(achievementItems.count)")
                            .font(.headline)
                        Text(L("Erreichte Achievements", "Unlocked achievements"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L("Sortieren", "Sort")) {
                Picker(L("Sortieren", "Sort"), selection: $achievementSortMode) {
                    ForEach(AchievementSortMode.allCases) { mode in
                        Text(mode.title(language: appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch achievementSortMode {
            case .category:
                Section(achievementSectionTitle(L("Üben", "Practice"), items: practiceAchievementItems)) {
                    ForEach(achievementsSortedInsideCategory(practiceAchievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }

                Section(achievementSectionTitle(L("Regionen & Spezialsets", "Regions & special sets"), items: regionAchievementItems)) {
                    ForEach(achievementsSortedInsideCategory(regionAchievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }

                Section(achievementSectionTitle("Showmaster", items: showmasterAchievementItems)) {
                    ForEach(achievementsSortedInsideCategory(showmasterAchievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            case .date:
                Section(L("Datum", "Date")) {
                    ForEach(achievementsSortedByDate(achievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            case .worldwide:
                Section(L("Weltweit", "Worldwide")) {
                    ForEach(achievementsSortedByGlobalUnlocks(achievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Achievements", "Achievements"))
        .onAppear {
            checkForUnlockedAchievements()
        }
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
    }

    var statisticsView: some View {
        List {
            if fullVersionUnlocked {
                Section(L("Bereich", "Scope")) {
                    continentButtonGrid(selection: $selectedStatisticsContinents)
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }
            }

            if isAllCountriesStatisticsScope {
                Section(bossTitle) {
                    MasteryScoreCard(
                        title: bossScoreTitle,
                        score: masteryScore(in: availableCountries),
                        rows: tierScoreRows(in: availableCountries),
                        language: appLanguage,
                        accentColor: tealAccentColor,
                        isComplete: activeProfileTierCount(.s) == availableCountries.count && !availableCountries.isEmpty,
                        isInfoPresented: $isMasteryScoreInfoExpanded
                    )
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }
            }

            Section(L("Allgemein", "General")) {
                let seenFlags = totalSeenFlags(in: filteredStatisticsCountries)
                let knownOnceFlags = totalKnownAtLeastOnceFlags(in: filteredStatisticsCountries)
                let knownAnswers = totalCardKnown(in: filteredStatisticsCountries)
                let totalFlags = filteredStatisticsCountries.count
                let firstLearned = firstLearnedCountry(in: filteredStatisticsCountries)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    CompactStatTile(title: selectedSubject == .capitals ? L("Gesehen", "Seen") : L("Gesehen", "Seen"), value: "\(seenFlags)/\(totalFlags)", subtitle: percent(seenFlags, of: totalFlags))
                    CompactStatTile(title: L("Mind. 1x gewusst", "Known once"), value: "\(knownOnceFlags)/\(totalFlags)", subtitle: percent(knownOnceFlags, of: totalFlags))
                    CompactStatTile(title: selectedSubject == .capitals ? L("Erste Stadt gelernt", "First city learned") : L("Erste Flagge gelernt", "First flag learned"), value: firstLearned.map { countryName(for: $0.country) } ?? "-", subtitle: firstLearned.map { compactDateText($0.date) } ?? L("noch offen", "open"))
                    CompactStatTile(title: selectedSubject == .capitals ? L("Meiste Städte/Tag", "Most cities/day") : L("Meiste Flaggen/Tag", "Most flags/day"), value: "\(maxKnownCardsInOneDay(subject: selectedSubject))", subtitle: L("gelernt", "learned"))
                    CompactStatTile(title: L("Gewusst", "Known"), value: "\(knownAnswers)", subtitle: L("gesamt", "total"))
                    CompactStatTile(title: L("Geübt", "Practiced"), value: "\(totalCardReviews(in: filteredStatisticsCountries))", subtitle: selectedSubject == .capitals ? L("Länder", "countries") : L("Flaggen", "flags"))
                    CompactStatTile(title: L("Nicht gewusst", "Not known"), value: "\(totalCardUnknown(in: filteredStatisticsCountries))", subtitle: "")
                    CompactStatTile(title: "Showmaster", value: "\(activeProfile.showmasterCards)", subtitle: L("Karten", "cards"))
                    CompactStatTile(title: runTitle, value: "\((activeProfile.leagueStats?.played ?? 0))", subtitle: L("Runs", "runs"))
                    CompactStatTile(title: L("Party-Runden", "Party rounds"), value: "\((activeProfile.partyRoundsPlayed ?? 0))", subtitle: L("Runden", "rounds"))
                    CompactStatTile(title: L("Beste Streak", "Best streak"), value: "\((activeProfile.bestLearningStreak ?? 0))", subtitle: L("Tage", "days"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        dismissStatisticsSearchKeyboard()
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTierExplanationExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Label(L("Erklärung der Stufenstruktur", "Level structure explained"), systemImage: "info.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isTierExplanationExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isTierExplanationExpanded {
                        Text(selectedSubject == .capitals ? L("Die Stufen gehen von F bis S. F bedeutet neu oder unsicher, S bedeutet sehr sicher. Wenn du eine Hauptstadt nach rechts wischst, steigt sie eine Stufe. Nach links fällt sie eine Stufe. Hohe Stufen kommen seltener, werden aber weiterhin abgefragt. Wenn du die Hauptstadt eines Landes 3 Tage lang nicht als gewusst loggst, fällt sie wegen Inaktivität eine Stufe ab.", "Levels go from F to S. F means new or unsure, S means very confident. Swiping a capital to the right moves it up one level. Swiping left moves it down one level. Higher levels appear less often, but still come up. If you do not log a country's capital as known for 3 days, it drops one level due to inactivity.") : L("Die Stufen gehen von F bis S. F bedeutet neu oder unsicher, S bedeutet sehr sicher. Wenn du eine Flagge nach rechts wischst, steigt sie eine Stufe. Nach links fällt sie eine Stufe. Hohe Stufen kommen seltener, werden aber weiterhin abgefragt. Wenn du eine Flagge 3 Tage lang nicht als gewusst loggst, fällt sie wegen Inaktivität eine Stufe ab.", "Levels go from F to S. F means new or unsure, S means very confident. Swiping a flag to the right moves it up one level. Swiping left moves it down one level. Higher levels appear less often, but still come up. If you do not log a flag as known for 3 days, it drops one level due to inactivity."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .onTapGesture { dismissStatisticsSearchKeyboard() }

            if !fullVersionUnlocked {
                Section(selectedSubject == .capitals ? L("Städteboss-Stufen", "City boss levels") : L("Flaggenboss-Stufen", "Flaggenboss levels")) {
                    TierSummaryGrid(profile: activeProfile, countries: availableCountries, subject: selectedSubject, selectedTier: selectedStatisticsTier) { tier in
                        dismissStatisticsSearchKeyboard()
                        Haptics.tap()
                        selectedStatisticsTier = selectedStatisticsTier == tier ? nil : tier
                    }
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }

                if let selectedStatisticsTier {
                    Section("\(bossTitle)-Stufe \(selectedStatisticsTier.rawValue)") {
                        ForEach(statisticsCountries(in: selectedStatisticsTier, from: availableCountries)) { country in
                            FreeTierCountryRow(
                                country: country,
                                stats: stats(for: country),
                                language: appLanguage,
                                subject: selectedSubject,
                                capital: capitalName(for: country),
                                accentColor: tealAccentColor
                            )
                        }
                    }
                }
            }

            if isAllCountriesStatisticsScope {
                Section(L("Auswertung", "Analysis")) {
                if fullVersionUnlocked {
                    ScopeScoreBarChart(
                        rows: scopeScoreRows(in: availableCountries),
                        language: appLanguage,
                        accentColor: tealAccentColor
                    )

                    Picker(L("Zeitraum", "Range"), selection: $selectedPracticeBalanceRange) {
                        ForEach(PracticeBalanceRange.allCases) { range in
                            Text(range.title(language: appLanguage)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPracticeBalanceRange) { _, _ in
                        scoreHistoryPageOffset = 0
                        practiceBalancePageOffset = 0
                        selectedScoreHistoryPoint = nil
                        selectedPracticeBalancePoint = nil
                    }

                    PracticeBalanceChart(
                        previousPoints: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: min(practiceBalancePageOffset + 1, 0)),
                        points: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset),
                        nextPoints: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset - 1),
                        range: selectedPracticeBalanceRange,
                        pageOffset: $practiceBalancePageOffset,
                        selectedPoint: $selectedPracticeBalancePoint,
                        language: appLanguage
                    )

                    FlaggenbossScoreChart(
                        title: bossTitle,
                        previousPoints: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: min(scoreHistoryPageOffset + 1, 0)),
                        points: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset),
                        nextPoints: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset - 1),
                        range: selectedPracticeBalanceRange,
                        pageOffset: $scoreHistoryPageOffset,
                        selectedPoint: $selectedScoreHistoryPoint,
                        language: appLanguage,
                        accentColor: tealAccentColor
                    )
                } else {
                    premiumFeatureNotice(feature: L("Premium-Statistiken", "Premium statistics"))
                    ZStack {
                        VStack(alignment: .leading, spacing: 12) {
                            ScopeScoreBarChart(
                                rows: scopeScoreRows(in: availableCountries),
                                language: appLanguage,
                                accentColor: tealAccentColor
                            )
                            Picker(L("Zeitraum", "Range"), selection: $selectedPracticeBalanceRange) {
                                ForEach(PracticeBalanceRange.allCases) { range in
                                    Text(range.title(language: appLanguage)).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            PracticeBalanceChart(
                                previousPoints: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: min(practiceBalancePageOffset + 1, 0)),
                                points: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset),
                                nextPoints: practiceBalancePoints(range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset - 1),
                                range: selectedPracticeBalanceRange,
                                pageOffset: $practiceBalancePageOffset,
                                selectedPoint: $selectedPracticeBalancePoint,
                                language: appLanguage
                            )
                            FlaggenbossScoreChart(
                                title: bossTitle,
                                previousPoints: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: min(scoreHistoryPageOffset + 1, 0)),
                                points: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset),
                                nextPoints: flaggenbossPoints(in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset - 1),
                                range: selectedPracticeBalanceRange,
                                pageOffset: $scoreHistoryPageOffset,
                                selectedPoint: $selectedScoreHistoryPoint,
                                language: appLanguage,
                                accentColor: tealAccentColor
                            )
                        }
                        .blur(radius: 4)
                        .saturation(0.72)
                        .opacity(0.48)
                        .allowsHitTesting(false)

                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(tealAccentColor)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .onTapGesture { dismissStatisticsSearchKeyboard() }
            }

            if fullVersionUnlocked {
                Section(selectedSubject == .capitals ? L("Länder", "Countries") : L("Flaggen", "Flags")) {
                    TextField(selectedSubject == .capitals ? L("Land, Hauptstadt, Kontinent oder Code suchen", "Search country, capital, continent, or code") : L("Land, Kontinent oder Code suchen", "Search country, continent, or code"), text: $statisticsSearchText)
                        .focused($isStatisticsSearchFocused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.subheadline)

                    if !hasStatisticsSearch {
                        TierSummaryGrid(profile: activeProfile, countries: filteredStatisticsCountries, subject: selectedSubject, selectedTier: selectedStatisticsTier) { tier in
                            dismissStatisticsSearchKeyboard()
                            Haptics.tap()
                            expandedStatisticsCountryCodes = []
                            selectedStatisticsTier = selectedStatisticsTier == tier ? nil : tier
                        }
                    }
                }

                if hasStatisticsSearch {
                    Section(L("Suchergebnisse", "Search results")) {
                        if filteredStatisticsCountries.isEmpty {
                            Text(selectedSubject == .capitals ? L("Kein Land oder keine Hauptstadt gefunden", "No country or capital found") : L("Keine Flagge gefunden", "No flag found"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredStatisticsCountries.sorted { countryName(for: $0) < countryName(for: $1) }) { country in
                                CountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                                    .contentShape(Rectangle())
                                    .onTapGesture { dismissStatisticsSearchKeyboard() }
                            }
                        }
                    }
                } else if let selectedStatisticsTier {
                    Section("Stufe \(selectedStatisticsTier.rawValue)") {
                        let countries = statisticsCountries(in: selectedStatisticsTier, from: filteredStatisticsCountries)
                        if countries.isEmpty {
                            Text(selectedSubject == .capitals ? L("Keine Länder in dieser Stufe gefunden", "No countries found in this tier") : L("Keine Flaggen in dieser Stufe gefunden", "No flags found in this tier"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(countries) { country in
                                let isExpanded = expandedStatisticsCountryCodes.contains(country.code)
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        dismissStatisticsSearchKeyboard()
                                        Haptics.tap()
                                        if isExpanded {
                                            expandedStatisticsCountryCodes.remove(country.code)
                                        } else {
                                            expandedStatisticsCountryCodes.insert(country.code)
                                        }
                                    } label: {
                                        CompactCountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if isExpanded {
                                        CountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country), showsHeader: false)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Statistik", "Statistics"))
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .onChange(of: selectedStatisticsContinents) { _, _ in
            selectedStatisticsTier = nil
            expandedStatisticsCountryCodes = []
        }
        .onChange(of: selectedSubject) { _, _ in
            selectedStatisticsTier = nil
            expandedStatisticsCountryCodes = []
        }
        .onChange(of: statisticsSearchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStatisticsTier = nil
                expandedStatisticsCountryCodes = []
            }
        }
    }

    func dismissStatisticsSearchKeyboard() {
        isStatisticsSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var globeCountries: [Country] {
        availableCountries
    }

    var globeTierByCountryCode: [String: MasteryTier] {
        Dictionary(uniqueKeysWithValues: globeCountries.map { country in
            (country.code, activeProfile.tier(for: country, subject: selectedSubject))
        })
    }

    func focusGlobeSearchResult() {
        guard let country = bestGlobeSearchMatch(for: globeSearchText) else { return }
        Haptics.tap()
        focusGlobe(on: country)
    }

    func focusGlobe(on country: Country) {
        withAnimation(.easeInOut(duration: 0.2)) {
            globeFocusCountryCode = country.code
        }
    }

    func bestGlobeSearchMatch(for query: String) -> Country? {
        globeSearchMatches(for: query, minimumScore: 0.62).first?.country
    }

    func globeSearchSuggestions(for query: String) -> [Country] {
        globeSearchMatches(for: query, minimumScore: 0.38).prefix(5).map { $0.country }
    }

    func globeSearchMatches(for query: String, minimumScore: Double) -> [(country: Country, score: Double)] {
        let normalizedQuery = normalizedLeagueAnswer(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let ranked = globeCountries.compactMap { country -> (country: Country, score: Double)? in
            let names = [
                country.name,
                countryEnglishNameByCode[country.code] ?? country.name,
                country.code
            ].map { normalizedLeagueAnswer($0) }

            let score = names.map { name -> Double in
                if name == normalizedQuery { return 1 }
                if name.hasPrefix(normalizedQuery) { return 0.92 }
                if name.contains(normalizedQuery) { return 0.82 }
                let distance = levenshteinDistance(normalizedQuery, name, maxDistance: max(2, normalizedQuery.count / 3))
                let length = max(normalizedQuery.count, name.count, 1)
                return max(0, 1 - Double(distance) / Double(length))
            }.max() ?? 0

            return score >= minimumScore ? (country, score) : nil
        }

        return ranked.sorted { first, second in
            if first.score != second.score {
                return first.score > second.score
            }
            return countryName(for: first.country).localizedStandardCompare(countryName(for: second.country)) == .orderedAscending
        }
    }

    var globeView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    modeHeader(title: L("Globus", "Globe"), subtitle: "")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(L("Land suchen", "Search country"), text: $globeSearchText)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.search)
                                .onSubmit {
                                    focusGlobeSearchResult()
                                }
                            if !globeSearchText.isEmpty {
                                Button {
                                    globeSearchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        let suggestions = globeSearchSuggestions(for: globeSearchText)
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestions) { country in
                                        Button {
                                            Haptics.tap()
                                            globeSearchText = countryName(for: country)
                                            focusGlobe(on: country)
                                        } label: {
                                            Text(countryName(for: country))
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(tealAccentColor.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.secondary.opacity(0.14), lineWidth: 1)
                    )

                    GlobeSceneView(
                        countries: globeCountries,
                        tiersByCountryCode: globeTierByCountryCode,
                        resetToken: globeResetToken,
                        focusCountryCode: globeFocusCountryCode,
                        onSelectCountryCode: { code in
                            selectedGlobeCountry = globeCountries.first { $0.code == code }
                            Haptics.tap()
                        }
                    )
                    .frame(height: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        Button {
                            Haptics.tap()
                            globeResetToken += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.headline)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }

                    TierSummaryGrid(profile: activeProfile, countries: globeCountries, subject: selectedSubject)
                        .padding(12)
                        .background(panelBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                }
                .padding()
            }
        }
        .navigationTitle(L("Globus", "Globe"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .sheet(item: $selectedGlobeCountry) { country in
            NavigationStack {
                List {
                    Section {
                        CountryStatsRow(country: country, stats: activeProfile.stats(for: country, subject: selectedSubject), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                    }
                }
                .navigationTitle(countryName(for: country))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
}
