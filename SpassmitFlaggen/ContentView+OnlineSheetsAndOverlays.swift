import SwiftUI
import Foundation

extension ContentView {
    func onlineGlobeSheet(for player: OnlinePlayerStats) -> some View {
        NavigationStack {
            let playerSubjectStats = player.stats(for: selectedSubject)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(player.displayName)
                            .font(.title2.bold())
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("\(playerSubjectStats.totalPracticed) gelernt · \(player.achievementCount) Achievements · Code \(player.friendCode)", "\(playerSubjectStats.totalPracticed) learned · \(player.achievementCount) achievements · Code \(player.friendCode)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section(L("Direkter Vergleich", "Direct comparison")) {
                    ComparisonStatRow(title: L("Gelernt", "Learned"), ownValue: "\(activeProfileTotalPracticed)", otherValue: "\(playerSubjectStats.totalPracticed)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Letzte 7 Tage", "Last 7 days"), ownValue: "\(activeProfile.practiceCardsInLastSevenDays(subject: selectedSubject))", otherValue: "\(playerSubjectStats.learnedThisWeek)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Quote", "Rate"), ownValue: percentText(activeProfileCardAccuracy), otherValue: percentText(playerSubjectStats.accuracy), otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Achievements", "Achievements"), ownValue: "\(unlockedAchievementCount)", otherValue: "\(player.achievementCount)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: "S", ownValue: "\(activeProfileTierCount(.s)) (\(percent(activeProfileTierCount(.s), of: availableCountries.count)))", otherValue: "\(playerSubjectStats.tierS) (\(percent(playerSubjectStats.tierS, of: availableCountries.count)))", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: "A", ownValue: "\(activeProfileTierCount(.a))", otherValue: "\(playerSubjectStats.tierA)", otherName: player.displayName, language: appLanguage)
                }


                if let onlineProfile = player.profileSnapshot {
                    Section(L("Online-Verlauf", "Online history")) {
                        Picker(L("Zeitraum", "Range"), selection: $selectedPracticeBalanceRange) {
                            ForEach(PracticeBalanceRange.allCases) { range in
                                Text(range.title(language: appLanguage)).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedPracticeBalanceRange) { _, _ in
                            scoreHistoryPageOffset = 0
                            practiceBalancePageOffset = 0
                            learnedHistoryPageOffset = 0
                            selectedScoreHistoryPoint = nil
                            selectedPracticeBalancePoint = nil
                            selectedLearnedHistoryPoint = nil
                        }

                        PracticeBalanceChart(
                            title: selectedSubject == .capitals ? L("Gelernte Städte", "Learned cities") : L("Gelernte Flaggen", "Learned flags"),
                            primaryLabel: L("Gelernt", "Learned"),
                            showsUnknown: false,
                            previousPoints: learnedPracticePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: learnedHistoryPageOffset - selectedPracticeBalanceRange.days),
                            points: learnedPracticePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: learnedHistoryPageOffset),
                            nextPoints: nextLearnedPracticePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: learnedHistoryPageOffset),
                            range: selectedPracticeBalanceRange,
                            maxValue: learnedPracticeMaxValue(profile: onlineProfile),
                            pageOffset: $learnedHistoryPageOffset,
                            selectedPoint: $selectedLearnedHistoryPoint,
                            language: appLanguage
                        )

                        PracticeBalanceChart(
                            previousPoints: practiceBalancePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset - selectedPracticeBalanceRange.days),
                            points: practiceBalancePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset),
                            nextPoints: nextPracticeBalancePoints(profile: onlineProfile, range: selectedPracticeBalanceRange, pageOffset: practiceBalancePageOffset),
                            range: selectedPracticeBalanceRange,
                            maxValue: practiceBalanceMaxValue(profile: onlineProfile),
                            pageOffset: $practiceBalancePageOffset,
                            selectedPoint: $selectedPracticeBalancePoint,
                            language: appLanguage
                        )

                        FlaggenbossScoreChart(
                            title: bossTitle,
                            previousPoints: flaggenbossPoints(profile: onlineProfile, in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset - selectedPracticeBalanceRange.days),
                            points: flaggenbossPoints(profile: onlineProfile, in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset),
                            nextPoints: nextFlaggenbossPoints(profile: onlineProfile, in: availableCountries, range: selectedPracticeBalanceRange, pageOffset: scoreHistoryPageOffset),
                            range: selectedPracticeBalanceRange,
                            pageOffset: $scoreHistoryPageOffset,
                            selectedPoint: $selectedScoreHistoryPoint,
                            language: appLanguage,
                            accentColor: tealAccentColor
                        )
                    }
                }

                if fullVersionUnlocked {
                    Section(L("Globus", "Globe")) {
                        GlobeSceneView(
                            countries: availableCountries,
                            tiersByCountryCode: playerSubjectStats.tiersByCountryCode,
                            resetToken: globeResetToken,
                            focusCountryCode: nil
                        ) { countryCode in
                            selectedGlobeCountry = availableCountries.first { $0.code == countryCode }
                        }
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Section(L("Globus", "Globe")) {
                        lockedGlobePreview(tiersByCountryCode: playerSubjectStats.tiersByCountryCode)
                    }
                }

                Section(L("Stufen", "Levels")) {
                    TierSummaryGrid(
                        profile: virtualProfile(for: player),
                        countries: availableCountries,
                        subject: selectedSubject
                    )
                    .padding(.vertical, 6)
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
                    Section(achievementSectionTitle(L("Üben", "Practice"), items: onlineAchievementItems(for: player, matching: practiceAchievementItems))) {
                        ForEach(achievementsSortedInsideCategory(onlineAchievementItems(for: player, matching: practiceAchievementItems))) { item in
                            onlineAchievementRow(item)
                        }
                    }

                    Section(achievementSectionTitle(L("Regionen & Spezialsets", "Regions & special sets"), items: onlineAchievementItems(for: player, matching: regionAchievementItems))) {
                        ForEach(achievementsSortedInsideCategory(onlineAchievementItems(for: player, matching: regionAchievementItems))) { item in
                            onlineAchievementRow(item)
                        }
                    }

                    Section(achievementSectionTitle("Showmaster", items: onlineAchievementItems(for: player, matching: showmasterAchievementItems))) {
                        ForEach(achievementsSortedInsideCategory(onlineAchievementItems(for: player, matching: showmasterAchievementItems))) { item in
                            onlineAchievementRow(item)
                        }
                    }
                case .date:
                    Section(L("Datum", "Date")) {
                        ForEach(onlineAchievementsSortedByDate(for: player)) { item in
                            onlineAchievementRow(item)
                        }
                    }
                case .worldwide:
                    Section(L("Weltweit", "Worldwide")) {
                        ForEach(achievementsSortedByGlobalUnlocks(achievementItems(for: player))) { item in
                            onlineAchievementRow(item)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(L("Freund-Statistik", "Friend stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        selectedOnlineGlobePlayer = nil
                    }
                }
            }
        }
    }

    func virtualProfile(for player: OnlinePlayerStats) -> UserProfile {
        let subjectStats = player.stats(for: selectedSubject)
        var profile = UserProfile(id: UUID(), name: player.displayName, pin: "")
        for country in availableCountries {
            var stats = CountryStats()
            stats.storedTier = subjectStats.tiersByCountryCode[country.code] ?? .f
            profile.byCountry[selectedSubject.statsKey(for: country)] = stats
        }
        return profile
    }

    func onlineAchievementItems(for player: OnlinePlayerStats, matching sourceItems: [AchievementItem]) -> [AchievementItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: achievementItems(for: player).map { ($0.id, $0) })
        return sourceItems.compactMap { itemsByID[$0.id] }
    }

    func onlineAchievementsSortedByDate(for player: OnlinePlayerStats) -> [AchievementItem] {
        achievementsSortedInsideCategory(achievementItems(for: player))
    }

    func onlineAchievementRow(_ item: AchievementItem) -> some View {
        AchievementRow(
            item: item,
            language: appLanguage,
            globalUnlockCount: globalUnlockCount(for: item.id),
            globalPlayerCount: globalAchievementPlayerCount
        )
    }

    func fullVersionLockedView(feature: String) -> some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            VStack(spacing: 14) {
                lockedGlobePreview(tiersByCountryCode: globeTierByCountryCode)
                    .frame(height: 280)

                Text(feature)
                    .font(.title2.bold())

                NavigationLink(value: AppScreen.options) {
                    Label(L("Vollversion ansehen", "View full version"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 420)
        }
        .navigationTitle(feature)
        .navigationBarTitleDisplayMode(.inline)
    }

    func lockedGlobePreview(tiersByCountryCode: [String: MasteryTier]) -> some View {
        ZStack {
            GlobeSceneView(
                countries: availableCountries,
                tiersByCountryCode: tiersByCountryCode,
                resetToken: globeResetToken,
                focusCountryCode: nil,
                onSelectCountryCode: { _ in }
            )
            .blur(radius: 6)
            .saturation(0.72)
            .opacity(0.72)

            Image(systemName: "lock.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(tealAccentColor)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.22), lineWidth: 1)
        )
    }

    func premiumFeatureNotice(feature: String) -> some View {
        Label(L("\(feature) ist Teil der Vollversion.", "\(feature) is part of the full version."), systemImage: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    func infoButton<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            Haptics.tap()
            isPresented.wrappedValue = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(tealAccentColor)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented) {
            content()
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 280, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }

    func tierDecayPopupView(_ popup: TierDecayPopup) -> some View {
        let selectedChange = popup.changes.first { $0.id == selectedTierDecayChangeID } ?? popup.changes.first
        let visibleChanges = tierDecayShowsAllChanges ? popup.changes : Array(popup.changes.prefix(4))
        let hiddenChangeCount = max(popup.changes.count - visibleChanges.count, 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
                    .frame(width: 42, height: 42)
                    .background(tealAccentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Stufen angepasst", "Levels adjusted"))
                        .font(.title3.bold())
                    Text(L("Keine Sorge, das bekommst du schnell wieder hin!", "No worries, you will get this back quickly!"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                    Text(L("Tippe auf ein Land, um zu sehen, was sich verändert hat.", "Tap a country to see what changed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        tierDecayPopup = nil
                        selectedTierDecayChangeID = nil
                        tierDecayShowsAllChanges = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(visibleChanges) { change in
                        tierDecayChangeButton(change)
                    }

                    if hiddenChangeCount > 0 {
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                tierDecayShowsAllChanges = true
                            }
                        } label: {
                            Label(L("Alle \(popup.changes.count) anzeigen", "Show all \(popup.changes.count)"), systemImage: "chevron.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor, isProminent: false))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: tierDecayShowsAllChanges ? 260 : 190)

            if let selectedChange {
                tierDecayDetailView(selectedChange)
            }
        }
        .padding(18)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tealAccentColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    func tierDecayChangeButton(_ change: TierDecayChange) -> some View {
        let isSelected = selectedTierDecayChangeID == change.id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                selectedTierDecayChangeID = change.id
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierDecayCountryTitle(for: change))
                        .font(.subheadline.weight(.semibold))
                    Text(tierDecaySubjectTitle(for: change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(change.from.rawValue)
                        .foregroundStyle(change.from.color)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(change.to.rawValue)
                        .foregroundStyle(change.to.color)
                }
                .font(.headline.weight(.bold))
            }
            .padding(12)
            .background(isSelected ? tealAccentColor.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tealAccentColor.opacity(0.42) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    func tierDecayDetailView(_ change: TierDecayChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tierDecayCountryTitle(for: change))
                .font(.headline)
            HStack(spacing: 8) {
                Label(L("Vorher: \(change.from.rawValue)", "Before: \(change.from.rawValue)"), systemImage: "arrow.up.circle")
                    .foregroundStyle(change.from.color)
                Spacer()
                Label(L("Jetzt: \(change.to.rawValue)", "Now: \(change.to.rawValue)"), systemImage: "arrow.down.circle")
                    .foregroundStyle(change.to.color)
            }
            .font(.caption.weight(.semibold))
            Text(L("Zuletzt gewusst vor \(change.daysSinceLastPractice) Tagen.", "Last known \(change.daysSinceLastPractice) days ago."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    func tierDecayCountryTitle(for change: TierDecayChange) -> String {
        let code = normalizedCountryCode(fromStatsKey: change.statsKey)
        guard let country = allCountries.first(where: { $0.code == code }) else { return change.statsKey }
        return localizedCountryName(country, language: appLanguage)
    }

    func normalizedCountryCode(fromStatsKey statsKey: String) -> String {
        var key = statsKey
            .replacingOccurrences(of: "capital_", with: "")
            .replacingOccurrences(of: "country_", with: "")
            .replacingOccurrences(of: "flag_", with: "")

        if let lastUnderscore = key.split(separator: "_").last {
            key = String(lastUnderscore)
        }
        if let lastColon = key.split(separator: ":").last {
            key = String(lastColon)
        }

        let uppercasedKey = key.uppercased()
        if allCountries.contains(where: { $0.code == uppercasedKey }) {
            return uppercasedKey
        }

        return allCountries.first { country in
            uppercasedKey.hasSuffix(country.code)
        }?.code ?? uppercasedKey
    }

    func tierDecaySubjectTitle(for change: TierDecayChange) -> String {
        change.statsKey.hasPrefix("capital_") ? L("Hauptstadt", "Capital") : L("Flagge", "Flag")
    }

}
