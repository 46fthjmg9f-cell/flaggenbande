import SwiftUI
import Foundation
import UIKit

extension ContentView {
    func accentColorButton(for accent: AppAccent) -> some View {
        let isSelected = appAccent == accent
        let isLocked = !fullVersionUnlocked
        let color = adaptiveColor(light: accent.lightUIColor, dark: accent.darkUIColor)

        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                isShowingFullVersionSheet = true
                return
            }
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appAccentRawValue = accent.rawValue
            }
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                    Text(accent.title(language: appLanguage))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    if isSelected && !isLocked {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                }
                .blur(radius: isLocked ? 3 : 0)
                .opacity(isLocked ? 0.58 : 1)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected && !isLocked ? color : panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(isSelected && !isLocked ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected && !isLocked ? Color.white.opacity(0.22) : color.opacity(0.28), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    func continentButtonGrid(selection: Binding<Set<String>>) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(spacing: 10) {
            categoryButton(for: CountryScope.worldwide, selection: selection, isWide: true)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(continents, id: \.self) { continent in
                    categoryButton(for: continent, selection: selection)
                }
            }
        }
    }

    func categoryButton(for continent: String, selection: Binding<Set<String>>, isWide: Bool = false) -> some View {
        let isSelected = selection.wrappedValue.contains(continent)
        let isLocked = !fullVersionUnlocked && continent != "Europa"

        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                isShowingFullVersionSheet = true
                return
            }
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.18)) {
                togglePracticeContinent(continent, selection: selection)
            }
        } label: {
            HStack(spacing: 10) {
                Text(localizedScope(continent))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 4)
                Text("\(countries(inContinent: continent).count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isSelected ? Color.white : tealAccentColor).opacity(0.16))
                    .clipShape(Capsule())
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isWide ? 50 : 56)
            .padding(.horizontal, 12)
            .background(isSelected ? tealAccentColor : panelBackgroundColor)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.58 : 1)
    }

    func togglePracticeContinent(_ continent: String, selection: Binding<Set<String>>) {
        if continent == CountryScope.worldwide {
            selection.wrappedValue = [CountryScope.worldwide]
            return
        }

        var selectedContinents = selection.wrappedValue
        selectedContinents.remove(CountryScope.worldwide)

        if selectedContinents.contains(continent) {
            selectedContinents.remove(continent)
        } else {
            selectedContinents.insert(continent)
        }

        selection.wrappedValue = selectedContinents.isEmpty ? [CountryScope.worldwide] : selectedContinents
    }

    func addFriend() {
        let trimmedName = newFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        addFriend(named: trimmedName)
        newFriendName = ""
    }

    func addFriend(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        var names = friendNames
        let alreadyExists = names.contains { $0.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
        if !alreadyExists {
            names.append(trimmedName)
            friendNamesRawValue = names.joined(separator: "|")
        }
    }

    func removeFriend(_ friend: String) {
        let names = friendNames.filter { $0 != friend }
        friendNamesRawValue = names.joined(separator: "|")
    }

    #if DEBUG
    @MainActor
    func createTestFriend() async {
        guard onlineFeaturesEnabled else { return }
        guard !isSyncingOnlineStats else { return }
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }

        onlineStatusText = L("Erstelle Testfreund ...", "Creating test friend ...")
        do {
            try await OnlineStatsService.createTestFriend(countries: availableCountries)
            addFriend(named: OnlineStatsService.testFriendName)
            onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
            onlineLeaderboardRefreshID += 1
            selectedOnlineScope = .friends
            onlineStatusText = L("Testfreund FlaggenTest erstellt und hinzugefügt.", "Test friend FlaggenTest created and added.")
            Haptics.notify(.success)
        } catch {
            Haptics.notify(.error)
            onlineStatusText = L("Testfreund nicht erstellt: \(OnlineStatsService.userFacingMessage(for: error))", "Test friend not created: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }

    func debugSetFlaggenrunHighscore(_ highscore: Int) {
        updateActiveProfile { profile in
            var stats = profile.leagueStats ?? LeagueStats()
            stats.bestScore = highscore
            profile.leagueStats = stats
        }
    }

    func debugResetLeagueStats() {
        updateActiveProfile { profile in
            profile.leagueStats = LeagueStats()
        }
        leagueSummaryResult = nil
    }

    func debugSetAllCountryTiers(_ tier: MasteryTier) {
        updateActiveProfile { profile in
            let now = Date()
            for country in availableCountries {
                let key = selectedSubject.statsKey(for: country)
                var stats = profile.byCountry[key] ?? CountryStats()
                stats.storedTier = tier
                stats.lastPracticedAt = now
                if tier != .f {
                    stats.lastKnownAt = now
                }
                stats.appendTierHistory(tier: tier, date: now)
                profile.byCountry[key] = stats
            }
        }
    }
    #endif

    func modeHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.largeTitle)
                .bold()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    func subjectModePickerCard() -> some View {
        HStack(spacing: 10) {
            subjectModeButton(for: .countries)
            subjectModeButton(for: .capitals)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tealAccentColor.opacity(0.24), lineWidth: 1)
        )
    }

    func subjectModeButton(for subject: LearningSubject) -> some View {
        let isSelected = selectedSubject == subject
        let isLocked = subject == .capitals && !fullVersionUnlocked
        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                isShowingFullVersionSheet = true
                return
            }
            guard selectedSubject != subject else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                selectedSubject = subject
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: subject == .countries ? "flag.fill" : "building.columns.fill")
                    .font(.subheadline.weight(.bold))
                Text(subject.displayTitle(language: appLanguage))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 10)
            .background(isSelected && !isLocked ? tealAccentColor : Color.clear)
            .foregroundStyle(isSelected && !isLocked ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected && !isLocked ? Color.white.opacity(0.22) : tealAccentColor.opacity(0.28), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.55 : 1)
    }

    @ViewBuilder
    func subjectGlassSwitcher() -> some View {
        if #available(iOS 26.0, *) {
            subjectGlassSwitcherContent()
                .padding(6)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            subjectGlassSwitcherContent()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
    }

    func subjectGlassSwitcherContent() -> some View {
        GeometryReader { geometry in
            let segmentWidth = max((geometry.size.width - 8) / 2, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))

                Capsule()
                    .fill(tealAccentColor)
                    .frame(width: segmentWidth, height: 46)
                    .offset(x: selectedSubject == .countries ? 4 : segmentWidth + 4)
                    .shadow(color: tealAccentColor.opacity(0.28), radius: 10, y: 4)

                HStack(spacing: 0) {
                    subjectGlassSwitcherButton(for: .countries)
                    subjectGlassSwitcherButton(for: .capitals)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedSubject)
        }
        .frame(maxWidth: 380)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
    }

    func subjectGlassSwitcherButton(for subject: LearningSubject) -> some View {
        let isSelected = selectedSubject == subject
        let isLocked = subject == .capitals && !fullVersionUnlocked
        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                isShowingFullVersionSheet = true
                return
            }
            guard selectedSubject != subject else { return }
            dismissStatisticsSearchKeyboard()
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedSubject = subject
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: subject == .countries ? "flag.fill" : "building.columns.fill")
                    .font(.subheadline.weight(.bold))
                Text(subject.title(language: appLanguage))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isSelected && !isLocked ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.55 : 1)
    }

    @ViewBuilder
    func onlineScopeGlassSwitcher() -> some View {
        if #available(iOS 26.0, *) {
            onlineScopeGlassSwitcherContent()
                .padding(6)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            onlineScopeGlassSwitcherContent()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
    }

    func onlineScopeGlassSwitcherContent() -> some View {
        GeometryReader { geometry in
            let segmentWidth = max((geometry.size.width - 8) / 2, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))

                Capsule()
                    .fill(tealAccentColor)
                    .frame(width: segmentWidth, height: 46)
                    .offset(x: selectedOnlineScope == .friends ? 4 : segmentWidth + 4)
                    .shadow(color: tealAccentColor.opacity(0.28), radius: 10, y: 4)

                HStack(spacing: 0) {
                    onlineScopeButton(for: .friends)
                    onlineScopeButton(for: .global)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedOnlineScope)
        }
        .frame(maxWidth: 380)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
    }

    func onlineScopeButton(for scope: OnlineLeaderboardScope) -> some View {
        let isSelected = selectedOnlineScope == scope
        return Button {
            guard selectedOnlineScope != scope else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedOnlineScope = scope
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scope == .friends ? "person.2.fill" : "globe.europe.africa.fill")
                    .font(.subheadline.weight(.bold))
                Text(scope == .friends ? L("Freunde", "Friends") : L("Global", "Global"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


}
