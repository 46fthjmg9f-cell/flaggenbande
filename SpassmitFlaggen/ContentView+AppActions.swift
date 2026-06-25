import SwiftUI
import Foundation
import GameKit

// MARK: - App Actions

extension ContentView {
    func runStartupWorkAfterFirstRender() async {
        await Task.yield()
        ensureTrainerProfile()
        if !didEnableOnlineByDefault {
            didEnableOnlineByDefault = true
        }
        if !onlineFeaturesEnabled {
            disableOnlineRuntimeState()
        }
        await hideStartupScreenAfterDelay()
        applyWeeklyTierDecay(showPopup: true)
    }

    func ensureTrainerProfile() {
        if appData.profiles.isEmpty {
            let profile = UserProfile(id: UUID(), name: "Training", pin: "")
            appData.profiles = [profile]
            appData.activeProfileID = profile.id
            saveLocalCache()
        } else if appData.activeProfileID == nil {
            appData.activeProfileID = appData.profiles[0].id
            saveLocalCache()
        }
    }

    func updateActiveProfile(_ update: (inout UserProfile) -> Void) {
        ensureTrainerProfile()
        guard let activeProfileID = appData.activeProfileID,
              let index = appData.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }

        update(&appData.profiles[index])
        saveLocalCache()
    }

    func checkForUnlockedAchievements() {
        ensureTrainerProfile()
        guard let activeProfileID = appData.activeProfileID,
              let index = appData.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }

        let now = Date()
        var alreadyAnnounced = Set(appData.profiles[index].announcedAchievementIDs ?? [])
        var achievedDates = appData.profiles[index].achievedAchievementDates ?? [:]
        let unlockedItems = achievementItems.filter(\.isUnlocked)

        for item in unlockedItems {
            let key = achievementAnnouncementID(for: item)
            if achievedDates[key] == nil {
                achievedDates[key] = now
            }
        }

        guard let unlockedItem = unlockedItems.first(where: { !alreadyAnnounced.contains(achievementAnnouncementID(for: $0)) }) else {
            appData.profiles[index].achievedAchievementDates = achievedDates
            saveLocalCache()
            return
        }

        alreadyAnnounced.insert(achievementAnnouncementID(for: unlockedItem))
        appData.profiles[index].announcedAchievementIDs = Array(alreadyAnnounced).sorted()
        appData.profiles[index].achievedAchievementDates = achievedDates
        saveLocalCache()
        showAchievementPopup(unlockedItem)
    }

    func achievementAnnouncementID(for item: AchievementItem) -> String {
        "\(selectedSubject.rawValue)|\(item.id)"
    }

    func showAchievementPopup(_ item: AchievementItem) {
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            achievementPopupItem = item
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard achievementPopupItem?.id == item.id else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                achievementPopupItem = nil
            }
        }
    }

    func authenticateGameCenter(syncAfterAuthentication: Bool = false) {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }

        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            guard onlineFeaturesEnabled else { return }

            if let viewController {
                gameCenterAuthPresentation = GameCenterAuthPresentation(viewController: viewController)
                return
            }

            if GKLocalPlayer.local.isAuthenticated {
                isGameCenterAuthenticated = true
                gameCenterPlayerID = GKLocalPlayer.local.gamePlayerID
                gameCenterAlias = GKLocalPlayer.local.alias
                gameCenterStatusText = L("Verbunden als \(GKLocalPlayer.local.alias)", "Connected as \(GKLocalPlayer.local.alias)")
                Task {
                    await restoreCloudBackupIfNeeded()
                    await loadGameCenterFriends()
                    if syncAfterAuthentication {
                        await syncOnlineStats()
                    }
                }
            } else {
                isGameCenterAuthenticated = false
                gameCenterPlayerID = ""
                gameCenterAlias = ""
                cloudBackupRestoreAttemptedPlayerID = ""
                gameCenterFriendIDs = []
                gameCenterStatusText = error?.localizedDescription ?? L("Game Center nicht verbunden", "Game Center not connected")
            }
        }
    }

    @MainActor
    func loadGameCenterFriends() async {
        guard onlineFeaturesEnabled else {
            gameCenterFriendIDs = []
            return
        }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            let friends = try await GKLocalPlayer.local.loadFriends()
            gameCenterFriendIDs = Set(friends.map(\.gamePlayerID))
        } catch {
            gameCenterFriendIDs = []
        }
    }

    func disableOnlineRuntimeState() {
        isSyncingOnlineStats = false
        isGameCenterAuthenticated = false
        gameCenterPlayerID = ""
        gameCenterAlias = ""
        gameCenterFriendIDs = []
        onlineLeaderboard = []
        selectedOnlineGlobePlayer = nil
        gameCenterAuthPresentation = nil
        gameCenterStatusText = L("Online-Funktionen sind ausgeschaltet", "Online features are turned off")
        onlineStatusText = L("Online-Funktionen sind ausgeschaltet", "Online features are turned off")
    }

    func normalizedFriendToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func applyWeeklyTierDecay(showPopup: Bool = false) {
        var decayChanges: [TierDecayChange] = []
        updateActiveProfile { profile in
            decayChanges = profile.applyWeeklyTierDecay()
        }

        if showPopup, !decayChanges.isEmpty {
            let signature = tierDecayPopupSignature(for: decayChanges)
            guard tierDecayPopupLastShownSignature != signature else { return }
            tierDecayPopupLastShownSignature = signature
            selectedTierDecayChangeID = decayChanges.first?.id
            tierDecayShowsAllChanges = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                tierDecayPopup = TierDecayPopup(changes: decayChanges)
            }
        }
    }

    func tierDecayPopupSignature(for changes: [TierDecayChange]) -> String {
        changes
            .map(\.id)
            .sorted()
            .joined(separator: "|")
    }

    func saveLocalCache() {
        AppStorageService.save(appData)
        scheduleOnlineStatsSync()
    }

    @MainActor
    func restoreCloudBackupIfNeeded() async {
        guard onlineFeaturesEnabled, isGameCenterAuthenticated, !gameCenterPlayerID.isEmpty else { return }
        guard cloudBackupRestoreAttemptedPlayerID != gameCenterPlayerID else { return }
        cloudBackupRestoreAttemptedPlayerID = gameCenterPlayerID

        do {
            guard let cloudData = try await OnlineStatsService.fetchAppDataSnapshot(gameCenterPlayerID: gameCenterPlayerID) else { return }
            let cloudProgress = backupProgressScore(for: cloudData)
            let localProgress = backupProgressScore(for: appData)
            guard cloudProgress > localProgress else { return }

            isRestoringCloudBackup = true
            pendingOnlineSyncTask?.cancel()
            appData = cloudData
            AppStorageService.save(appData)
            ensureTrainerProfile()
            recapStartCounts = activeProfile.tierCounts(in: availableCountries)
            recapEndCounts = recapStartCounts
            onlineStatusText = L("Cloud-Statistik wiederhergestellt.", "Cloud stats restored.")
            isRestoringCloudBackup = false
        } catch {
            onlineStatusText = L("Cloud-Backup nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Cloud backup not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
            isRestoringCloudBackup = false
        }
    }

    func backupProgressScore(for data: AppData) -> Int {
        var total = 0
        for profile in data.profiles {
            var countryProgress = 0
            for stats in profile.byCountry.values {
                var tierBonus = 0
                switch stats.tier {
                case .s: tierBonus = 30
                case .a: tierBonus = 18
                case .b: tierBonus = 10
                case .c, .d, .f: tierBonus = 0
                }
                countryProgress += stats.attempts
                countryProgress += stats.cardReviews
                countryProgress += stats.showmasterPlayed
                countryProgress += tierBonus
            }

            let leaguePlayed = profile.leagueStats?.played ?? 0
            let leagueRating = profile.leagueStats?.rating ?? 1000
            let leagueProgress = leaguePlayed * 25 + max(leagueRating - 1000, 0)
            let practiceProgress = profile.practiceCardsByDay?.values.reduce(0, +) ?? 0
            let achievementProgress = (profile.achievedAchievementDates?.count ?? 0) * 40

            total += profile.totalAnswers
            total += practiceProgress
            total += profile.showmasterCards
            total += countryProgress
            total += leagueProgress
            total += achievementProgress
        }
        return total
    }

    func scheduleOnlineStatsSync() {
        guard onlineFeaturesEnabled, isGameCenterAuthenticated, !isRestoringCloudBackup else { return }
        pendingOnlineSyncTask?.cancel()
        pendingOnlineSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await syncOnlineStats(showFeedback: false)
        }
    }

    @MainActor
    func hideStartupScreenAfterDelay() async {
        try? await Task.sleep(for: .seconds(1.45))
        withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) {
            isShowingStartupScreen = false
        }
        try? await Task.sleep(for: .milliseconds(360))
    }

    @MainActor
    func syncOnlineStats(showFeedback: Bool = true) async {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }
        guard !isSyncingOnlineStats else { return }

        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }

        onlineStatusText = L("Synchronisiere ...", "Syncing ...")
        do {
            onlineStatusText = L("Lade Statistik hoch ...", "Uploading stats ...")
            try await OnlineStatsService.upload(
                name: onlinePlayerName,
                gameCenterPlayerID: isGameCenterAuthenticated ? gameCenterPlayerID : nil,
                gameCenterAlias: gameCenterAlias,
                appData: appData,
                profile: activeProfile,
                countries: availableCountries,
                subject: selectedSubject,
                achievementIDs: achievementItems.filter(\.isUnlocked).map(\.id)
            )
            onlineStatusText = L("Statistik hochgeladen. Lade Rangliste ...", "Stats uploaded. Loading leaderboard ...")

            do {
                onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
                onlineLeaderboardRefreshID += 1
                onlineStatusText = L("Statistik hochgeladen. Rangliste geladen: \(deduplicatedOnlineLeaderboard.count) Spieler", "Stats uploaded. Leaderboard loaded: \(deduplicatedOnlineLeaderboard.count) players")
            } catch {
                onlineStatusText = L("Statistik hochgeladen. Rangliste nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Stats uploaded. Leaderboard not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
            }

            Task { await loadGameCenterFriends() }
            if showFeedback {
                Haptics.notify(.success)
            }
        } catch {
            if showFeedback {
                Haptics.notify(.error)
            }
            onlineStatusText = L("Upload fehlgeschlagen: \(OnlineStatsService.userFacingMessage(for: error))", "Upload failed: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }

    @MainActor
    func loadOnlineStats(forceRefresh: Bool = false) async {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }
        guard (forceRefresh || onlineLeaderboard.isEmpty), !isSyncingOnlineStats else { return }
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }

        do {
            onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
            onlineLeaderboardRefreshID += 1
            onlineStatusText = L("Online-Rangliste geladen: \(deduplicatedOnlineLeaderboard.count) Spieler", "Online leaderboard loaded: \(deduplicatedOnlineLeaderboard.count) players")
        } catch {
            onlineStatusText = L("Online-Rangliste nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Online leaderboard not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }

    func resetAllLocalData() {
        appData = AppData()
        AppStorageService.reset()
        ensureTrainerProfile()
        recapStartCounts = activeProfile.tierCounts(in: availableCountries)
        recapEndCounts = recapStartCounts
        practiceSessionCount = 0
        practiceSessionKnown = 0
        practiceSessionUnknown = 0
        practiceSessionImproved = 0
        practiceSessionResults = []
        practiceSessionChanges = []
        practiceHistoryPreview = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionActive = false
        practiceCardDragOffset = 0
        practiceCardEntryOffset = 0
        practiceCardEntryOpacity = 1
        isFinishingPracticeSwipe = false
        showSessionActive = false
        showSessionCount = 0
        showRecap = false
        achievementPopupItem = nil
        tierDecayPopup = nil
        selectedTierDecayChangeID = nil
        tierDecayShowsAllChanges = false
        tierDecayPopupLastShownSignature = ""
        resetCurrentCardHint()
    }

    func nextPracticeCard(entryDirection: CGFloat = 0) {
        let nextCountry = practiceForcedNextCountry ?? nextPracticeCountry()
        practiceForcedNextCountry = nil
        if entryDirection != 0 {
            practiceCardEntryOffset = -58
            practiceCardEntryOpacity = 0
        } else {
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            currentCountry = nextCountry
            cardIsFlipped = false
            resetCurrentCardHint()
            practiceHistoryPreview = nil
            practiceCardDragOffset = 0
            isFinishingPracticeSwipe = false
        }

        guard entryDirection != 0 else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                practiceCardEntryOffset = 0
                practiceCardEntryOpacity = 1
            }
        }
    }

    func startPracticeSession() {
        applyWeeklyTierDecay()
        showRecap = false
        practiceSessionCount = 0
        practiceSessionKnown = 0
        practiceSessionUnknown = 0
        practiceSessionImproved = 0
        practiceSessionResults = []
        practiceSessionChanges = []
        practiceHistoryPreview = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionSeenCountryCodes = []
        selectedPracticeCardLimit = 10
        recapStartCounts = activeProfile.tierCounts(in: availableCountries)
        recapEndCounts = recapStartCounts
        currentCountry = nextPracticeCountry()
        cardIsFlipped = false
        resetCurrentCardHint()
        practiceHistoryPreview = nil
        practiceCardDragOffset = 0
        practiceCardEntryOffset = 0
        practiceCardEntryOpacity = 1
        isFinishingPracticeSwipe = false

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            practiceSessionActive = true
        }
    }

    func finishPracticeSession(showSummary: Bool) {
        let availableCodes = Set(availableCountries.map(\.code))
        let completedPerfectFullSession = practiceSessionActive
            && showSummary
            && !availableCodes.isEmpty
            && availableCodes.isSubset(of: practiceSessionSeenCountryCodes)
            && practiceSessionUnknown == 0
            && practiceSessionKnown >= availableCodes.count
        if completedPerfectFullSession {
            updateActiveProfile { profile in
                profile.recordPerfectFullPracticeSession(subject: selectedSubject)
            }
            checkForUnlockedAchievements()
        }

        let completedTenBlock = practiceSessionActive && showSummary && selectedPracticeCardLimit == 10 && practiceSessionCount >= 10
        if completedTenBlock {
            updateActiveProfile { profile in
                profile.recordCompletedTenBlock()
            }
            checkForUnlockedAchievements()
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            practiceSessionActive = false
            practiceCardDragOffset = 0
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
            isFinishingPracticeSwipe = false
            recapEndCounts = activeProfile.tierCounts(in: availableCountries)
            showRecap = showSummary && practiceSessionCount > 0
            practiceHistoryPreview = nil
        }
    }

    func undoLastPracticeSwipe() {
        guard let snapshot = practiceUndoSnapshot else { return }
        let nextCountryAfterUndo = currentCountry
        appData = snapshot.appData
        saveLocalCache()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            currentCountry = snapshot.currentCountry
            practiceSessionCount = snapshot.practiceSessionCount
            practiceSessionKnown = snapshot.practiceSessionKnown
            practiceSessionUnknown = snapshot.practiceSessionUnknown
            practiceSessionImproved = snapshot.practiceSessionImproved
            practiceSessionResults = snapshot.practiceSessionResults
            practiceSessionChanges = snapshot.practiceSessionChanges
            practiceHistoryPreview = nil
            practiceSessionSeenCountryCodes = snapshot.practiceSessionSeenCountryCodes
            practiceForcedNextCountry = nextCountryAfterUndo
            cardIsFlipped = snapshot.cardIsFlipped
            cardHintIsVisible = snapshot.cardHintIsVisible
            currentCardUsedHint = snapshot.currentCardUsedHint
            hintBlockFeedbackIsVisible = false
            recapEndCounts = snapshot.recapEndCounts
            practiceCardDragOffset = 0
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
            isFinishingPracticeSwipe = false
            showRecap = false
            practiceSessionActive = true
            practiceUndoSnapshot = nil
        }
    }

    func resetShowSession(clearDeck: Bool = false) {
        showSessionActive = false
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        if clearDeck {
            showRecentCountryCodes = []
            showDeckCountryCodes = []
        }
        cardIsFlipped = false
        resetCurrentCardHint()
    }

    func startShowSession() {
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        resetCurrentCardHint()
        prepareShowCard()
        showSessionActive = true
    }
}
