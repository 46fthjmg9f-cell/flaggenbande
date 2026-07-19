import SwiftUI
import Foundation

extension ContentView {
    var friendsView: some View {
        List {
            if onlineFeaturesEnabled {
                Section {
                    subjectModePickerCard()
                }

                Section(L("Profil", "Profile")) {
                    HStack(spacing: 10) {
                        Image(systemName: isGameCenterAuthenticated ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(isGameCenterAuthenticated ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isGameCenterAuthenticated ? gameCenterAlias : L("Game Center", "Game Center"))
                                .font(.headline)
                            Text(gameCenterStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L("Spitzname: \(onlineDisplayName)", "Nickname: \(onlineDisplayName)"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        Spacer()
                        Image(systemName: onlineStatusIconName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(onlineStatusColor)
                            .frame(width: 30, height: 30)
                            .background(onlineStatusColor.opacity(0.12), in: Circle())
                            .accessibilityLabel(onlineStatusText)
                        Button {
                            Haptics.tap()
                            isShowingFriendInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(tealAccentColor)
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingFriendInfo) {
                            Text(L("Dein angezeigter Name ist dein Game-Center-Name, außer du gibst dir in den Einstellungen einen Spitznamen, unter dem dich Freunde finden können.", "Your displayed name is your Game Center name unless you set a nickname in Settings that friends can use to find you."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(width: 280, alignment: .leading)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }

                onlineComparisonSection
                    .id(onlineLeaderboardRefreshID)
            } else {
                Section(L("Online ausgeschaltet", "Online off")) {
                    Label(L("Online und Ranglisten sind pausiert", "Online and leaderboards are paused"), systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                    Text(L("Aktiviere die Online-Funktionen in den Optionen, wenn du Game Center verbinden, deine Statistik hochladen, Bestenlisten laden oder fremde Globusse ansehen möchtest.", "Turn on online features in Options when you want to connect Game Center, upload your stats, load leaderboards, or view other players' globes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Online", "Online"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    isShowingFriendList = true
                } label: {
                    Image(systemName: "person.2.fill")
                }
                .disabled(!onlineFeaturesEnabled)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if onlineFeaturesEnabled {
                onlineScopeGlassSwitcher()
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .task {
            guard onlineFeaturesEnabled else { return }
            guard onlineFeaturesEnabled, onlineLeaderboard.isEmpty else { return }
            if !isGameCenterAuthenticated {
                authenticateGameCenter(syncAfterAuthentication: true)
            } else {
                await loadOnlineStats()
            }
        }
    }

    var friendsComparisonSection: some View {
        Section(L("Online-Freunde", "Online friends")) {
            if friendNames.isEmpty && gameCenterFriendIDs.isEmpty {
                Text(L("Füge Freunde unten in diesem Reiter hinzu.", "Add friends below in this tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if friendLeaderboard.isEmpty {
                Text(L("Keine Online-Statistiken für deine Freunde gefunden. Freunde müssen Game Center verbinden und ihre Statistik hochladen.", "No online stats found for your friends. Friends need to connect Game Center and upload their stats."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                onlineLeaderboardRows(
                    players: friendFlaggenscoreLeaderboard,
                    metric: .flaggenscore,
                    sectionID: "friends-comparison-boss"
                )
            }
        }
    }

    var friendListSheet: some View {
        NavigationStack {
            List {
                Section(L("Freund hinzufügen", "Add friend")) {
                    HStack {
                        TextField(L("Spitzname oder Code", "Nickname or code"), text: $newFriendName)
                            .textInputAutocapitalization(.words)
                        Button {
                            Haptics.tap()
                            addFriend()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(newFriendName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text(L("Freunde finden dich über ihren eindeutigen Spitznamen oder den Code aus der Rangliste.", "Friends can be found by their unique nickname or the code from the leaderboard."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    #if DEBUG
                    Button {
                        Haptics.tap()
                        Task { await createTestFriend() }
                    } label: {
                        Label(L("Testfreund erstellen", "Create test friend"), systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(isSyncingOnlineStats)
                    #endif
                }

                Section(L("Meine Freunde", "My friends")) {
                    if friendNames.isEmpty && gameCenterFriendIDs.isEmpty {
                        Text(L("Noch keine Freunde hinzugefügt.", "No friends added yet."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(friendNames, id: \.self) { friend in
                        HStack {
                            if let player = onlinePlayer(forFriend: friend) {
                                Button {
                                    Haptics.tap()
                                    openFriendStatsFromFriendList(player)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.displayName)
                                        Text(L("Freundstatistik öffnen", "Open friend stats"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend)
                                    Text(L("Noch keine Online-Statistik gefunden", "No online stats found yet"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Haptics.tap(style: .medium)
                                friendPendingRemoval = friend
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(gameCenterFriendPlayers) { player in
                        Button {
                            Haptics.tap()
                            openFriendStatsFromFriendList(player)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.displayName)
                                    Text(L("Game-Center-Freund", "Game Center friend"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !gameCenterFriendIDs.isEmpty {
                        Label(L("\(gameCenterFriendIDs.count) Game-Center-Freunde erkannt", "\(gameCenterFriendIDs.count) Game Center friends found"), systemImage: "gamecontroller.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog(
                L("Freund entfernen?", "Remove friend?"),
                isPresented: Binding(
                    get: { friendPendingRemoval != nil },
                    set: { if !$0 { friendPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let friendPendingRemoval {
                    Button(L("\(friendPendingRemoval) entfernen", "Remove \(friendPendingRemoval)"), role: .destructive) {
                        removeFriend(friendPendingRemoval)
                        self.friendPendingRemoval = nil
                    }
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) {
                    friendPendingRemoval = nil
                }
            } message: {
                Text(L("Dieser Freund wird nur aus deiner lokalen Freundesliste entfernt.", "This friend will only be removed from your local friend list."))
            }
            .navigationTitle(L("Freundesliste", "Friend list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        isShowingFriendList = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    var onlineComparisonSection: some View {
        if selectedOnlineScope == .global && !fullVersionUnlocked {
            Section {
                premiumFeatureNotice(feature: L("Globale Bestenlisten", "Global leaderboards"))
            }
        }

        if selectedOnlineScope == .friends {
            Section(bossScoreTitle) {
                if friendFlaggenscoreLeaderboard.isEmpty {
                    Text(L("Keine Freundes-Statistiken gefunden. Füge Freunde oben rechts hinzu oder warte, bis Freunde ihre Statistik hochgeladen haben.", "No friend stats found. Add friends from the top-right button or wait until friends have uploaded their stats."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    onlineLeaderboardRows(
                        players: friendFlaggenscoreLeaderboard,
                        metric: .flaggenscore,
                        sectionID: "friends-boss"
                    )
                }
            }
        }

        if selectedOnlineScope == .global && fullVersionUnlocked {
            globalLeaderboardSection
        } else if selectedOnlineScope == .friends {
            Section(selectedSubject == .capitals ? L("Hauptstädte gelernt - 7 Tage", "Capitals learned - 7 days") : L("Flaggen gelernt - 7 Tage", "Flags learned - 7 days")) {
                onlineLeaderboardRows(
                    players: scopedLearnedThisWeekLeaderboard,
                    metric: .week,
                    sectionID: "week"
                )
            }

            Section(L("Längste Lernstreak", "Longest learning streak")) {
                onlineLeaderboardRows(
                    players: scopedBestLearningStreakLeaderboard,
                    metric: .learningStreak,
                    sectionID: "streak"
                )
            }

            Section(runHighscoreTitle) {
                onlineLeaderboardRows(
                    players: scopedFlaggenrunLeaderboard,
                    metric: .flaggenrun,
                    sectionID: "run"
                )
            }
        }
    }

    var globalLeaderboardSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Eine Rangliste nach der anderen — damit du schnell vergleichen kannst.", "One leaderboard at a time, so comparisons stay clear."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(L("Rangliste", "Leaderboard"), selection: $selectedGlobalLeaderboardMetric) {
                        ForEach([OnlineLeaderboardMetric.week, .learningStreak, .flaggenrun]) { metric in
                            Label(globalLeaderboardMetricTitle(metric), systemImage: globalLeaderboardMetricIcon(metric))
                                .tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }

            Section(globalLeaderboardMetricTitle(selectedGlobalLeaderboardMetric)) {
                globalLeaderboardRows(
                    players: globalLeaderboardPlayers(for: selectedGlobalLeaderboardMetric),
                    metric: selectedGlobalLeaderboardMetric
                )
            }
        }
    }

    func globalLeaderboardPlayers(for metric: OnlineLeaderboardMetric) -> [OnlinePlayerStats] {
        switch metric {
        case .week: return scopedLearnedThisWeekLeaderboard
        case .learningStreak: return scopedBestLearningStreakLeaderboard
        case .flaggenrun: return scopedFlaggenrunLeaderboard
        case .flaggenscore: return deduplicatedOnlineLeaderboard
        }
    }

    func globalLeaderboardMetricTitle(_ metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .week:
            return selectedSubject == .capitals ? L("Diese Woche gelernt", "Learned this week") : L("Diese Woche gelernt", "Learned this week")
        case .learningStreak: return L("Lernstreak", "Learning streak")
        case .flaggenrun: return L("Daily Run", "Daily Run")
        case .flaggenscore: return L("Meisterschaft", "Mastery")
        }
    }

    func globalLeaderboardMetricIcon(_ metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .week: return "chart.line.uptrend.xyaxis"
        case .learningStreak: return "flame.fill"
        case .flaggenrun: return "flag.checkered"
        case .flaggenscore: return "medal.fill"
        }
    }

    @ViewBuilder
    func globalLeaderboardRows(players: [OnlinePlayerStats], metric: OnlineLeaderboardMetric) -> some View {
        let key = "\(selectedSubject.rawValue)-\(metric.rawValue)"
        let visibleCount = globalLeaderboardVisibleRows[key, default: 10]
        let visiblePlayers = Array(players.prefix(visibleCount))

        ForEach(Array(visiblePlayers.enumerated()), id: \.element.id) { index, player in
            onlinePlayerRow(rank: index + 1, player: player, metric: metric)
        }

        if let ownIndex = players.firstIndex(where: isCurrentOnlinePlayer), ownIndex >= visiblePlayers.count {
            Text(L("Deine Platzierung", "Your position"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            onlinePlayerRow(rank: ownIndex + 1, player: players[ownIndex], metric: metric)
        }

        if players.count > visiblePlayers.count {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    globalLeaderboardVisibleRows[key] = min(visiblePlayers.count + 10, players.count)
                }
            } label: {
                Label(
                    L("Weitere 10 anzeigen", "Show 10 more"),
                    systemImage: "chevron.down"
                )
                .frame(maxWidth: .infinity)
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        } else if players.count > 10 {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    globalLeaderboardVisibleRows[key] = 10
                }
            } label: {
                Label(L("Zurück zu Top 10", "Back to top 10"), systemImage: "chevron.up")
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    func onlineLeaderboardRows(players: [OnlinePlayerStats], metric: OnlineLeaderboardMetric, sectionID: String) -> some View {
        let key = "\(selectedOnlineScope.rawValue)-\(selectedSubject.rawValue)-\(sectionID)"
        let isExpanded = expandedOnlineLeaderboardSections.contains(key)
        let visiblePlayers = isExpanded ? players : Array(players.prefix(5))

        ForEach(Array(visiblePlayers.enumerated()), id: \.element.id) { index, player in
            onlinePlayerRow(rank: index + 1, player: player, metric: metric)
        }

        if players.count > 5 {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedOnlineLeaderboardSections.remove(key)
                    } else {
                        expandedOnlineLeaderboardSections.insert(key)
                    }
                }
            } label: {
                HStack {
                    Text(isExpanded ? L("Weniger anzeigen", "Show less") : L("Alle anzeigen", "Show all"))
                    Spacer()
                    Text(isExpanded ? "5" : "+\(players.count - 5)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    func onlinePlayerRow(rank: Int, player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> some View {
        let playerSubjectStats = displayedOnlineSubjectStats(for: player)
        return Button {
            Haptics.tap()
            selectedOnlineGlobePlayer = player
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    rankBadge(rank)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        let subtitle = onlineMetricSubtitle(for: player, metric: metric)
                        if !subtitle.isEmpty || isCurrentOnlinePlayer(player) {
                            HStack(spacing: 5) {
                                if isCurrentOnlinePlayer(player) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(tealAccentColor)
                                        .accessibilityLabel(L("Du", "You"))
                                }
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(onlineMetricValue(for: player, metric: metric))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(rankAccentColor(rank))
                        Text(onlineMetricTitle(metric))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                if metric == .flaggenscore {
                    SLevelBar(value: playerSubjectStats.tierS, total: max(availableCountries.count, 1), accentColor: tealAccentColor)
                        .frame(height: 10)
                        .padding(.leading, 46)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, rank <= 3 ? 8 : 0)
            .background(rankBackground(rank), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rankAccentColor(rank).opacity(rank <= 3 ? 0.35 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(rank <= 3 ? rankAccentColor(rank) : .secondary)
            .frame(width: 30, height: 30)
            .background(rank <= 3 ? rankAccentColor(rank).opacity(0.12) : Color.secondary.opacity(0.08), in: Circle())
    }

    func onlineMetricSubtitle(for player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .week:
            return selectedSubject == .capitals ? L("Hauptstädte gewusst", "Capitals known") : L("Flaggen gewusst", "Flags known")
        case .flaggenrun:
            if let date = player.runBestScoreDate(for: selectedSubject) {
                return L("Bester Daily Run · \(formattedLeagueRunDate(date))", "Best Daily run · \(formattedLeagueRunDate(date))")
            }
            return L("Bester Daily Run", "Best Daily run")
        case .flaggenscore:
            return ""
        case .learningStreak:
            return L("10 Karten pro Tag", "10 cards per day")
        }
    }

    func onlineMetricValue(for player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .week: return "\(displayedOnlineSubjectStats(for: player).learnedThisWeek)"
        case .flaggenrun: return "\(player.runBestScore(for: selectedSubject))"
        case .flaggenscore: return String(format: "%.1f", onlineFlaggenbossScore(for: player) * 100)
        case .learningStreak: return "\(onlineLearningStreak(for: player))"
        }
    }

    func onlineMetricTitle(_ metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .week: return selectedSubject == .capitals ? L("gewusst", "known") : L("gewusst", "known")
        case .flaggenrun: return L("Highscore", "high score")
        case .flaggenscore: return L("Boss", "boss")
        case .learningStreak: return L("Tage", "days")
        }
    }

    var onlineStatusIconName: String {
        if isSyncingOnlineStats { return "icloud.and.arrow.up" }
        return onlineLeaderboard.isEmpty ? "icloud.slash" : "icloud.fill"
    }

    var onlineStatusColor: Color {
        if isSyncingOnlineStats { return .orange }
        return onlineLeaderboard.isEmpty ? .secondary : tealAccentColor
    }

    func rankAccentColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.95, green: 0.66, blue: 0.12)
        case 2: return Color(red: 0.62, green: 0.66, blue: 0.72)
        case 3: return Color(red: 0.72, green: 0.42, blue: 0.20)
        default: return tealAccentColor
        }
    }

    func rankBackground(_ rank: Int) -> Color {
        Color.clear
    }

    func onlineFlaggenbossScore(for player: OnlinePlayerStats) -> Double {
        let playerSubjectStats = player.stats(for: selectedSubject)
        let weightedTotal =
            Double(playerSubjectStats.tierS) * tierScoreValue(for: .s) +
            Double(playerSubjectStats.tierA) * tierScoreValue(for: .a) +
            Double(playerSubjectStats.tierB) * tierScoreValue(for: .b) +
            Double(playerSubjectStats.tierC) * tierScoreValue(for: .c) +
            Double(playerSubjectStats.tierD) * tierScoreValue(for: .d) +
            Double(playerSubjectStats.tierF) * tierScoreValue(for: .f)
        return weightedTotal / Double(max(availableCountries.count, 1))
    }

    func percentText(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }

    var activeProfileTotalPracticed: Int {
        availableCountries.reduce(0) { total, country in
            total + activeProfile.stats(for: country, subject: selectedSubject).cardReviews
        }
    }

    var activeProfileCardAccuracy: Double {
        let subjectStats = availableCountries.map { activeProfile.stats(for: $0, subject: selectedSubject) }
        let known = subjectStats.reduce(0) { $0 + $1.cardKnown }
        let total = subjectStats.reduce(0) { $0 + $1.cardReviews }
        guard total > 0 else { return 0 }
        return Double(known) / Double(total)
    }

    func activeProfileTierCount(_ tier: MasteryTier) -> Int {
        availableCountries.filter { activeProfile.tier(for: $0, subject: selectedSubject) == tier }.count
    }

    func achievementItems(for player: OnlinePlayerStats) -> [AchievementItem] {
        achievementItems.map { item in
            AchievementItem(
                id: item.id,
                title: item.title,
                description: item.description,
                iconName: item.iconName,
                currentValue: self.player(player, hasOnlineAchievement: item.id) ? item.targetValue : 0,
                targetValue: item.targetValue,
                tint: item.tint
            )
        }
    }

    func isCurrentOnlinePlayer(_ player: OnlinePlayerStats) -> Bool {
        if isGameCenterAuthenticated, !gameCenterPlayerID.isEmpty, player.gameCenterPlayerID == gameCenterPlayerID {
            return true
        }

        if let localPlayerID = UserDefaults.standard.string(forKey: OnlineStatsService.playerIDKey), player.id == localPlayerID {
            return true
        }

        return false
    }

}
