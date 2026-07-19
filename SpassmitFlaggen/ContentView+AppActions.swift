import SwiftUI
import Foundation
import GameKit

// MARK: - App Actions

extension ContentView {
    @MainActor
    func runStartupWorkAfterFirstRender() async {
        let startupStartedAt = Date()
        await Task.yield()
        AppStorageService.removeLegacyLocalPremiumFlagIfNeeded()
        restorePersistedPracticeContinents()
        migrateLegacyForcedGermanLanguageIfNeeded()

        #if targetEnvironment(simulator)
        // Simulator app bundles do not carry the real Game Center/CloudKit
        // entitlements. Keep the local UI testable instead of attempting an
        // online handshake that iOS will reject before the first screen.
        onlineFeaturesEnabled = false
        #endif

        fullVersionUnlocked = storeKit.purchasedFullVersion
        ensureTrainerProfile()
        if !availableCountries.contains(currentCountry) {
            currentCountry = nextRandomCountry(excluding: currentCountry, from: availableCountries)
            leagueCurrentCountry = currentCountry
            miniWorldCupCurrentCountry = currentCountry
        }
        preloadedFirstPracticeCountry = nextPracticeCountry()
        if !didEnableOnlineByDefault {
            didEnableOnlineByDefault = true
        }
        if !onlineLeaderboard.isEmpty {
            onlineStatusText = L("Gespeicherte Rangliste geladen", "Saved leaderboard loaded")
        }

        #if DEBUG
        applyWeeklyTierDecay(showPopup: false)
        showDebugTierDecayInfoOnNextLaunchIfNeeded()
        #else
        applyWeeklyTierDecay(showPopup: true)
        #endif

        if onlineFeaturesEnabled {
            authenticateGameCenter(syncAfterAuthentication: true)
        } else {
            disableOnlineRuntimeState()
        }

        // Store metadata is useful but not required for using the app. Keep the
        // locally verified purchase state and refresh StoreKit in parallel.
        Task { @MainActor in
            await storeKit.loadProducts()
            fullVersionUnlocked = storeKit.purchasedFullVersion
        }

        let countriesToPreload = availableCountries
        startupPreloadCompleted = 0
        startupPreloadTotal = max(countriesToPreload.compactMap(\.flagImageURL).count, 1)

        let flagPreloadTask = Task { @MainActor in
            await FlagImageCache.shared.preloadToDisk(
                countries: countriesToPreload,
                maximumConcurrentDownloads: 6,
                maximumDuration: 5.5
            ) { completed, total in
                startupPreloadCompleted = completed
                startupPreloadTotal = max(total, 1)
            }
        }
        let globePreloadTask = Task { @MainActor in
            await GlobeBoundaryCache.preload()
        }

        _ = await flagPreloadTask.value
        await globePreloadTask.value

        if let preloadedFirstPracticeCountry {
            await FlagImageCache.shared.warmInMemory([preloadedFirstPracticeCountry])
        }

        startupPreloadCompleted = startupPreloadTotal
        await hideStartupScreenAfterDelay(startedAt: startupStartedAt)

        // On a slow connection the splash remains bounded. Continue quietly and
        // also cache optional territories for users who enable them later.
        Task(priority: .utility) { @MainActor in
            _ = await FlagImageCache.shared.preloadToDisk(
                countries: allPracticeCountries,
                maximumConcurrentDownloads: 3,
                maximumDuration: 45
            )
        }
    }

    func migrateLegacyForcedGermanLanguageIfNeeded() {
        let migrationKey = "didMigrateLanguageDefaultToSystemV2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let wasForcedByLegacyDefault = UserDefaults.standard.bool(forKey: "didApplyGermanDefaultLanguage")
        let storedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        if wasForcedByLegacyDefault,
           storedLanguage == AppLanguage.german.rawValue,
           AppLanguage.systemDefault != .german {
            appLanguageRawValue = AppLanguage.systemDefault.rawValue
        }
    }

    func resetCountryPoolDependentState() {
        practiceSessionActive = false
        showSessionActive = false
        showRecap = false
        practiceRecapPromptIsVisible = false
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showUndoSnapshot = nil
        practiceHistoryGlobeCountry = nil
        selectedHistoryPillFrame = nil
        showCardDragOffset = 0
        showCardEntryOffset = 0
        showCardEntryOpacity = 1
        isFinishingShowSwipe = false
        showRecentCountryCodes = []
        showDeckCountryCodes = []
        statisticsSearchText = ""
        cardIsFlipped = false
        resetCurrentCardHint()
        currentCountry = nextRandomCountry(excluding: currentCountry)
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
        let previousAchievedDates = achievedDates
        let unlockedItems = achievementItems.filter(\.isUnlocked)

        for item in unlockedItems {
            let key = achievementAnnouncementID(for: item)
            if achievedDates[key] == nil {
                achievedDates[key] = now
            }
        }

        guard let unlockedItem = unlockedItems.first(where: { !alreadyAnnounced.contains(achievementAnnouncementID(for: $0)) }) else {
            if achievedDates != previousAchievedDates {
                appData.profiles[index].achievedAchievementDates = achievedDates
                saveLocalCache()
            }
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
            achievementPopupDragOffset = 0
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

        if didConfigureGameCenterAuthentication {
            if GKLocalPlayer.local.isAuthenticated, !isGameCenterAuthenticated {
                finishGameCenterAuthentication(syncAfterAuthentication: syncAfterAuthentication)
            }
            return
        }

        didConfigureGameCenterAuthentication = true

        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            guard onlineFeaturesEnabled else { return }

            if let viewController {
                gameCenterAuthPresentation = GameCenterAuthPresentation(viewController: viewController)
                return
            }

            if GKLocalPlayer.local.isAuthenticated {
                finishGameCenterAuthentication(syncAfterAuthentication: syncAfterAuthentication)
            } else {
                didConfigureGameCenterAuthentication = false
                isGameCenterAuthenticated = false
                gameCenterPlayerID = ""
                gameCenterAlias = ""
                cloudBackupRestoreAttemptedPlayerID = ""
                gameCenterFriendIDs = []
                gameCenterStatusText = error?.localizedDescription ?? L("Game Center nicht verbunden", "Game Center not connected")
                Task { @MainActor in
                    await retryPendingDailyCompletions()
                    await loadOnlineStats(forceRefresh: true)
                    if dailyLeagueChallenge == nil {
                        await refreshDailyLeagueStatus()
                    }
                }
            }
        }
    }

    func finishGameCenterAuthentication(syncAfterAuthentication: Bool) {
        let authenticatedPlayerID = GKLocalPlayer.local.gamePlayerID
        let shouldPreloadOnlineData = !isGameCenterAuthenticated || gameCenterPlayerID != authenticatedPlayerID
        isGameCenterAuthenticated = true
        gameCenterPlayerID = authenticatedPlayerID
        gameCenterAlias = GKLocalPlayer.local.alias
        gameCenterStatusText = L("Verbunden als \(GKLocalPlayer.local.alias)", "Connected as \(GKLocalPlayer.local.alias)")
        guard shouldPreloadOnlineData else { return }

        Task { @MainActor in
            async let friendsLoad: Void = loadGameCenterFriends()
            await restoreCloudBackupIfNeeded()
            await retryPendingDailyCompletions()
            _ = await friendsLoad

            if syncAfterAuthentication {
                await syncOnlineStats(showFeedback: false)
            } else if onlineLeaderboard.isEmpty {
                await loadOnlineStats()
            }

            if dailyLeagueChallenge == nil {
                await refreshDailyLeagueStatus()
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
        ensureTrainerProfile()
        guard let activeProfileID = appData.activeProfileID,
              let profileIndex = appData.profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }

        let decayChanges = appData.profiles[profileIndex].applyWeeklyTierDecay()
        if !decayChanges.isEmpty {
            saveLocalCache()
        }

        if showPopup, !decayChanges.isEmpty {
            let signature = tierDecayPopupSignature(for: decayChanges)
            guard tierDecayPopupLastShownSignature != signature else { return }
            tierDecayPopupLastShownSignature = signature
            selectedTierDecayChangeID = decayChanges.first?.id
            tierDecayShowsAllChanges = false
            tierDecayInfoIsExpanded = false
            tierDecayInfoPulse = false
            tierDecayInfoWiggle = false
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

    #if DEBUG
    func showDebugTierDecayInfoOnNextLaunchIfNeeded() {
        guard debugShowTierDecayInfoOnNextLaunch else { return }
        debugShowTierDecayInfoOnNextLaunch = false

        var change = TierDecayChange(from: .a, to: .b, daysSinceLastPractice: 4)
        change.statsKey = allCountries.first?.code ?? "DE"
        selectedTierDecayChangeID = change.id
        tierDecayShowsAllChanges = false
        tierDecayInfoIsExpanded = false
        tierDecayInfoPulse = false
        tierDecayInfoWiggle = false

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            tierDecayPopup = TierDecayPopup(changes: [change])
        }
    }
    #endif

    func saveLocalCache() {
        scheduleOnlineStatsSync()
        pendingLocalSaveTask?.cancel()
        pendingLocalSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            AppStorageService.save(appData)
            pendingLocalSaveTask = nil
        }
    }

    func flushLocalCache() {
        pendingLocalSaveTask?.cancel()
        pendingLocalSaveTask = nil
        AppStorageService.saveSynchronously(appData)
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
    func hideStartupScreenAfterDelay(startedAt: Date) async {
        let minimumVisibleDuration: TimeInterval = 1.45
        let remainingDuration = max(0, minimumVisibleDuration - Date().timeIntervalSince(startedAt))
        if remainingDuration > 0 {
            try? await Task.sleep(for: .seconds(remainingDuration))
        }
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
                achievementIDs: achievementItems
                    .filter(\.isUnlocked)
                    .map { onlineAchievementID(for: $0.id) }
            )
            onlineStatusText = L("Statistik hochgeladen. Lade Rangliste ...", "Stats uploaded. Loading leaderboard ...")

            do {
                onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
                OnlineLeaderboardCache.save(onlineLeaderboard)
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
            OnlineLeaderboardCache.save(onlineLeaderboard)
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
        practiceHistoryGlobeCountry = nil
        practiceHistoryPreview = nil
        selectedHistoryPillFrame = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionActive = false
        practiceCardDragOffset = 0
        practiceCardEntryOffset = 0
        practiceCardEntryOpacity = 1
        isFinishingPracticeSwipe = false
        showSessionActive = false
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showUndoSnapshot = nil
        practiceHistoryGlobeCountry = nil
        selectedHistoryPillFrame = nil
        showCardDragOffset = 0
        showCardEntryOffset = 0
        showCardEntryOpacity = 1
        isFinishingShowSwipe = false
        showRecap = false
        practiceRecapPromptIsVisible = false
        achievementPopupItem = nil
        tierDecayPopup = nil
        tierDecayInfoPopup = nil
        selectedTierDecayChangeID = nil
        tierDecayShowsAllChanges = false
        tierDecayInfoIsExpanded = false
        tierDecayInfoPulse = false
        tierDecayInfoWiggle = false
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
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = nil
            selectedHistoryPillFrame = nil
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
        guard !freeDailyFlagLimitReached else {
            showFreeDailyFlagLimitUpsell()
            return
        }

        applyWeeklyTierDecay()
        showRecap = false
        practiceRecapPromptIsVisible = false
        practiceSessionCount = 0
        practiceSessionKnown = 0
        practiceSessionUnknown = 0
        practiceSessionImproved = 0
        practiceSessionResults = []
        practiceSessionChanges = []
        practiceHistoryGlobeCountry = nil
        practiceHistoryPreview = nil
        selectedHistoryPillFrame = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionSeenCountryCodes = []
        selectedPracticeCardLimit = min(10, freeDailyFlagCardsRemaining)
        recapStartCounts = activeProfile.tierCounts(in: availableCountries)
        recapEndCounts = recapStartCounts
        let practiceCandidates = countries(inContinents: selectedPracticeContinents)
        if let preloadedFirstPracticeCountry,
           practiceCandidates.contains(preloadedFirstPracticeCountry) {
            currentCountry = preloadedFirstPracticeCountry
        } else {
            currentCountry = nextPracticeCountry()
        }
        preloadedFirstPracticeCountry = nil
        cardIsFlipped = false
        resetCurrentCardHint()
        practiceHistoryGlobeCountry = nil
        practiceHistoryPreview = nil
        selectedHistoryPillFrame = nil
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
            #if DEBUG
            showRecap = showSummary && practiceSessionCount > 0 && practiceRecapPromptIsVisible
            #else
            showRecap = showSummary && practiceSessionCount > 0
            #endif
            practiceRecapPromptIsVisible = false
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = nil
            selectedHistoryPillFrame = nil
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
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = nil
            selectedHistoryPillFrame = nil
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
            practiceRecapPromptIsVisible = false
            practiceSessionActive = true
            practiceUndoSnapshot = nil
        }
    }

    func undoLastShowSwipe() {
        guard let snapshot = showUndoSnapshot else { return }
        appData = snapshot.appData
        saveLocalCache()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            currentCountry = snapshot.currentCountry
            showSessionCount = snapshot.showSessionCount
            showSessionEntries = snapshot.showSessionEntries
            showHistoryPreview = nil
            showUndoSnapshot = nil
            practiceHistoryGlobeCountry = nil
            selectedHistoryPillFrame = nil
            showRecentCountryCodes = snapshot.showRecentCountryCodes
            showDeckCountryCodes = snapshot.showDeckCountryCodes
            cardIsFlipped = snapshot.cardIsFlipped
            cardHintIsVisible = snapshot.cardHintIsVisible
            currentCardUsedHint = snapshot.currentCardUsedHint
            hintBlockFeedbackIsVisible = false
            showCardDragOffset = 0
            showCardEntryOffset = 0
            showCardEntryOpacity = 1
            isFinishingShowSwipe = false
            showSessionActive = true
        }
    }

    func resetShowSession(clearDeck: Bool = false) {
        showSessionActive = false
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showUndoSnapshot = nil
        practiceHistoryGlobeCountry = nil
        selectedHistoryPillFrame = nil
        showCardDragOffset = 0
        showCardEntryOffset = 0
        showCardEntryOpacity = 1
        isFinishingShowSwipe = false
        if clearDeck {
            showRecentCountryCodes = []
            showDeckCountryCodes = []
        }
        cardIsFlipped = false
        resetCurrentCardHint()
    }

    func startShowSession() {
        guard !freeDailyFlagLimitReached else {
            showFreeDailyFlagLimitUpsell()
            return
        }

        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showUndoSnapshot = nil
        practiceHistoryGlobeCountry = nil
        selectedHistoryPillFrame = nil
        showCardDragOffset = 0
        showCardEntryOffset = 0
        showCardEntryOpacity = 1
        isFinishingShowSwipe = false
        resetCurrentCardHint()
        prepareShowCard()
        showSessionActive = true
    }
}
