import SwiftUI
import Foundation
import UIKit

struct ContentView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase

    // MARK: - Persisted Settings

    @AppStorage("onlinePlayerName") var onlinePlayerName: String = ""
    @AppStorage("appLanguage") var appLanguageRawValue: String = AppLanguage.systemDefault.rawValue
    @AppStorage("appTheme") var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("appAccent") var appAccentRawValue: String = AppAccent.teal.rawValue
    @AppStorage("friendNames") var friendNamesRawValue: String = ""
    @AppStorage("tierDecayPopupLastShownSignature") var tierDecayPopupLastShownSignature: String = ""
    @AppStorage("includePartiallyRecognizedFlags") var includePartiallyRecognizedFlags: Bool = false
    @AppStorage("excludedPartiallyRecognizedCountryCodes") var excludedPartiallyRecognizedCountryCodesRawValue: String = ""
    @AppStorage("includeDependentTerritories") var includeDependentTerritories: Bool = false
    @AppStorage("excludedDependentTerritoryCodes") var excludedDependentTerritoryCodesRawValue: String = ""
    @AppStorage("onlineFeaturesEnabled") var onlineFeaturesEnabled: Bool = true
    @AppStorage("didEnableOnlineByDefault") var didEnableOnlineByDefault: Bool = false
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true
    @AppStorage("selectedPracticeContinents") var selectedPracticeContinentsRawValue: String = CountryScope.worldwide
    #if DEBUG
    @AppStorage("debugToolsEnabled") var debugToolsEnabled: Bool = false
    @AppStorage("debugShowTierDecayInfoOnNextLaunchV2") var debugShowTierDecayInfoOnNextLaunch: Bool = true
    #endif

    // MARK: - App State

    @StateObject var storeKit = StoreKitManager()
    @State var fullVersionUnlocked: Bool = false
    @State var appData: AppData = AppStorageService.load()
    @State var onlineLeaderboard: [OnlinePlayerStats] = OnlineLeaderboardCache.load()
    @State var onlineLeaderboardRefreshID: Int = 0
    @State var onlineStatusText: String = "Online-Rangliste noch nicht geladen"
    @State var isSyncingOnlineStats: Bool = false
    @State var isLoadingOnlinePlayerDetail: Bool = false
    @State var isRestoringCloudBackup: Bool = false
    @State var cloudBackupRestoreAttemptedPlayerID: String = ""
    @State var pendingOnlineSyncTask: Task<Void, Never>?
    @State var pendingLocalSaveTask: Task<Void, Never>?
    @State var isGameCenterAuthenticated: Bool = false
    @State var gameCenterPlayerID: String = ""
    @State var gameCenterAlias: String = ""
    @State var gameCenterStatusText: String = "Game Center noch nicht verbunden"
    @State var gameCenterAuthPresentation: GameCenterAuthPresentation?
    @State var gameCenterFriendIDs: Set<String> = []
    @State var didConfigureGameCenterAuthentication: Bool = false
    @State var selectedOnlineGlobePlayer: OnlinePlayerStats?
    @State var selectedOnlineScope: OnlineLeaderboardScope = .friends
    @State var selectedGlobalLeaderboardMetric: OnlineLeaderboardMetric = .week
    @State var globalLeaderboardVisibleRows: [String: Int] = [:]
    @State var isShowingFriendInfo: Bool = false
    @State var isShowingOnlineInfo: Bool = false
    @State var isShowingNicknameInfo: Bool = false
    @State var isShowingFriendList: Bool = false
    @State var friendPendingRemoval: String?
    @State var selectedSubject: LearningSubject = .countries
    @State var selectedPracticeContinents: Set<String> = [CountryScope.worldwide]
    @State var selectedBeginnerContinents: Set<String> = [CountryScope.worldwide]
    @State var selectedBeginnerDirection: BeginnerDirection = .countryToFlag
    @State var selectedBeginnerQuestionLimit: Int = 10
    @State var beginnerSessionActive: Bool = false
    @State var beginnerQuestionCountry: Country = allCountries[0]
    @State var beginnerAnswerOptions: [Country] = []
    @State var beginnerSelectedCountry: Country?
    @State var beginnerIsAdvancing: Bool = false
    @State var beginnerDisplayedQuestionNumber: Int = 1
    @State var beginnerSessionResults: [BeginnerRoundResult] = []
    @State var beginnerHistoryPreview: BeginnerRoundResult?
    @State var beginnerSessionCorrect: Int = 0
    @State var beginnerSessionWrong: Int = 0
    @State var showBeginnerSummary: Bool = false
    @State var beginnerEasterEggTapDates: [Date] = []
    @State var showBeginnerEasterEgg: Bool = false
    @State var beginnerEasterEggPulse: Bool = false
    @State var selectedShowContinents: Set<String> = [CountryScope.worldwide]
    @State var selectedStatisticsContinents: Set<String> = [CountryScope.worldwide]
    @State var selectedStatisticsTier: MasteryTier?
    @State var isTierExplanationExpanded: Bool = false
    @State var isMasteryScoreInfoExpanded: Bool = false
    @State var isDisputedTerritoriesInfoExpanded: Bool = false
    @State var isDependentTerritoriesInfoExpanded: Bool = false
    @State var statisticsGraphHintIsVisible: Bool = false
    @State var scoreHistoryPageOffset: Int = 0
    @State var selectedScoreHistoryPoint: ScoreHistoryPoint?
    @State var learnedHistoryPageOffset: Int = 0
    @State var selectedLearnedHistoryPoint: PracticeBalanceHistoryPoint?
    @State var selectedPracticeBalanceRange: PracticeBalanceRange = .lastWeek
    @State var practiceBalancePageOffset: Int = 0
    @State var selectedPracticeBalancePoint: PracticeBalanceHistoryPoint?
    @State var expandedStatisticsCountryCodes: Set<String> = []
    @State var statisticsSearchText: String = ""
    @FocusState var isStatisticsSearchFocused: Bool
    @State var newFriendName: String = ""
    @State var selectedPracticeCardLimit: Int = 10
    @State var selectedShowCardLimit: Int = 0
    @State var showAvoidsRecentRepeats: Bool = true
    @State var leagueShowsStartMenu: Bool = true
    @State var leaguePracticeHistoryIsExpanded: Bool = false
    @State var leagueRunVariant: LeagueRunVariant = .practice
    @State var leagueMatchActive: Bool = false
    @State var leagueSecondsRemaining: Int = 60
    @State var leagueCurrentCountry: Country = allCountries[0]
    @State var leagueAnswerText: String = ""
    @State var leagueAnswerCandidates: [Country] = []
    @State var selectedLeagueHistoryMatch: LeagueMatchResult?
    @State var leagueCorrect: Int = 0
    @State var leagueWrong: Int = 0
    @State var leagueScore: Int = 0
    @State var leagueRecentCountryCodes: [String] = []
    @State var leagueAnswerRecords: [LeagueAnswerRecord] = []
    @State var leagueSummaryResult: LeagueMatchResult?
    @State var leagueAnswerMatch: LeagueAnswerMatch?
    @State var leagueAutoSubmitTask: Task<Void, Never>?
    @State var leagueFocusTask: Task<Void, Never>?
    @State var leagueTimerIsRunning: Bool = false
    @State var leagueTimerStartTask: Task<Void, Never>?
    @State var leagueCountdownTask: Task<Void, Never>?
    @State var leagueTimerEndDate: Date?
    @State var leagueAdvanceTask: Task<Void, Never>?
    @State var leagueFeedbackClearTask: Task<Void, Never>?
    @State var leagueCandidateAttentionTask: Task<Void, Never>?
    @State var leagueCandidateAttentionPulse: Bool = false
    @State var leagueInputIsLocked: Bool = false
    @State var leagueLockedAnswerText: String = ""
    @State var leagueAnswerFeedback: Bool?
    @State var leagueRevealedCountryName: String = ""
    @State var leagueMatchPhase: LeagueMatchPhase = .loading
    @State var leagueStartCountdown: Int = 3
    @State var leagueFirstFlagIsReady: Bool = false
    @State var leaguePreloadedFlagImage: UIImage?
    @State var isPreparingLeagueAssets: Bool = false
    @State var leagueAssetPreloadCompleted: Int = 0
    @State var leagueAssetPreloadTotal: Int = 0
    @State var leagueAssetPreloadError: String?
    @State var leaguePreparedPracticeOrder: [Country] = []
    @State var leaguePreparedPracticeAssetSignature: String = ""
    @State var leaguePreparedDailyAssetSignature: String = ""
    @State var leagueLookaheadWarmTask: Task<Void, Never>?
    @State var leagueTypingLockedUntil: Date = .distantPast
    @State var leagueCurrentQuestionStartedAt: Date = Date()
    @State var leagueNotificationsAuthorized: Bool = false
    @State var dailyLeagueChallenge: DailyChallenge?
    @State var dailyLeagueStatus: DailyUserStatus?
    @State var dailyLeagueLeaderboard: [DailyLeaderboardEntry] = []
    @State var trophyLeaderboard: [TrophyLeaderboardEntry] = []
    @State var isLoadingTrophyLeaderboard: Bool = false
    @State var trophyLeaderboardMessage: String?
    @State var dailyLeagueAttempts: [DailyAttemptSummary] = []
    @State var dailyLeagueReservation: DailyAttemptReservation?
    @State var dailyLeagueFlagOrder: [Country] = []
    @State var dailyLeagueFlagIndex: Int = 0
    @State var dailyLeagueStatusMessage: String?
    @State var isLoadingDailyLeague: Bool = false
    @State var dailyLeagueRefreshID: Int = 0
    @State var isRetryingPendingDailyCompletions: Bool = false
    @State var lastDailyLeagueResultWasBest: Bool?
    @FocusState var isLeagueAnswerFocused: Bool
    @FocusState var isMiniWorldCupNameFocused: Bool
    @State var practiceSessionSeenCountryCodes: Set<String> = []
    @State var showRecentCountryCodes: [String] = []
    @State var showDeckCountryCodes: [String] = []
    @State var practiceSessionCount: Int = 0
    @State var practiceSessionKnown: Int = 0
    @State var practiceSessionUnknown: Int = 0
    @State var practiceSessionImproved: Int = 0
    @State var practiceSessionResults: [Bool] = []
    @State var practiceSessionChanges: [PracticeSessionChange] = []
    @State var practiceHistoryPreview: PracticeHistoryPreview?
    @State var practiceHistoryGlobeCountry: Country?
    @State var practiceHistoryBarMinY: CGFloat = 150
    @State var selectedHistoryPillFrame: CGRect?
    @State var practiceForcedNextCountry: Country?
    @State var preloadedFirstPracticeCountry: Country?
    @State var practiceUndoSnapshot: PracticeUndoSnapshot?
    @State var showUndoSnapshot: ShowUndoSnapshot?
    @State var practiceSessionActive: Bool = false
    @State var showSessionActive: Bool = false
    @State var showSessionCount: Int = 0
    @State var showSessionEntries: [PracticeSessionChange] = []
    @State var showHistoryPreview: PracticeHistoryPreview?
    @State var showHistoryBarMinY: CGFloat = 150
    @State var miniWorldCupPlayers: [MiniWorldCupPlayer] = []
    @State var miniWorldCupNewPlayerName: String = ""
    @State var miniWorldCupActivePlayers: [MiniWorldCupPlayer] = []
    @State var miniWorldCupEliminations: [MiniWorldCupElimination] = []
    @State var miniWorldCupRoundResults: [MiniWorldCupRoundResult] = []
    @State var miniWorldCupCompletedPlayerIDsInRound: Set<UUID> = []
    @State var miniWorldCupPhase: MiniWorldCupPhase = .setup
    @State var miniWorldCupCurrentPlayerIndex: Int = 0
    @State var miniWorldCupCurrentCountry: Country = allCountries[0]
    @State var miniWorldCupRound: Int = 1
    @State var miniWorldCupFlagsPerPlayer: Int = 2
    @State var miniWorldCupRequiredCorrect: Int = 1
    @State var miniWorldCupSuddenDeathEnabled: Bool = true
    @State var miniWorldCupSuddenDeathThreshold: Int = 4
    @State var miniWorldCupSuddenDeathIsActive: Bool = false
    @State var miniWorldCupCurrentAttempt: Int = 1
    @State var miniWorldCupCurrentCorrect: Int = 0
    @State var miniWorldCupCurrentAttemptResults: [Bool] = []
    @State var miniWorldCupAdvancePopupText: String?
    @State var miniWorldCupMustKnowPulse: Bool = false
    @State var miniWorldCupCardIsFlipped: Bool = false
    @State var miniWorldCupCardWasRevealed: Bool = false
    @State var miniWorldCupCardEntryOffset: CGFloat = 0
    @State var miniWorldCupCardEntryOpacity: Double = 1
    @State var miniWorldCupCardDragOffset: CGSize = .zero
    @State var miniWorldCupAnswerFeedback: Bool?
    @State var miniWorldCupAnswerTask: Task<Void, Never>?
    @State var miniWorldCupRecentCountryCodes: [String] = []
    @State var miniWorldCupDeckCountryCodes: [String] = []
    @State var miniWorldCupUndoSnapshot: MiniWorldCupUndoSnapshot?
    @State var miniWorldCupSuddenDeathAnnouncementVisible: Bool = false
    @State var miniWorldCupEliminationPopupText: String?
    @State var miniWorldCupDangerShakeTrigger: Int = 0
    @State var currentCountry: Country = allCountries[0]
    @State var cardIsFlipped: Bool = false
    @State var cardHintIsVisible: Bool = false
    @State var currentCardUsedHint: Bool = false
    @State var hintBlockFeedbackIsVisible: Bool = false
    @State var practiceCardDragOffset: CGFloat = 0
    @State var practiceCardEntryOffset: CGFloat = 0
    @State var practiceCardEntryOpacity: Double = 1
    @State var isFinishingPracticeSwipe: Bool = false
    @State var showCardDragOffset: CGFloat = 0
    @State var showCardEntryOffset: CGFloat = 0
    @State var showCardEntryOpacity: Double = 1
    @State var isFinishingShowSwipe: Bool = false
    @State var recapStartCounts: [MasteryTier: Int] = [:]
    @State var recapEndCounts: [MasteryTier: Int] = [:]
    @State var showRecap: Bool = false
    @State var practiceRecapPromptIsVisible: Bool = false
    @State var isShowingStartupScreen: Bool = true
    @State var startupPreloadCompleted: Int = 0
    @State var startupPreloadTotal: Int = 1
    @State var selectedGlobeCountry: Country?
    @State var globeResetToken: Int = 0
    @State var globeSearchText: String = ""
    @State var globeFocusCountryCode: String?
    @State var tierDecayPopup: TierDecayPopup?
    @State var tierDecayInfoPopup: TierDecayPopup?
    @State var selectedTierDecayChangeID: String?
    @State var tierDecayShowsAllChanges: Bool = false
    @State var tierDecayInfoIsExpanded: Bool = false
    @State var tierDecayInfoPulse: Bool = false
    @State var tierDecayInfoWiggle: Bool = false
    @State var achievementPopupItem: AchievementItem?
    @State var achievementPopupDragOffset: CGFloat = 0
    @State var expandedOnlineLeaderboardSections: Set<String> = []
    @State var achievementSortMode: AchievementSortMode = .category
    @State var selectedMenuInfoScreen: AppScreen?
    @State var isShowingResetConfirmation: Bool = false
    @State var isShowingPracticeCancelConfirmation: Bool = false
    @State var isShowingShowCancelConfirmation: Bool = false
    @State var isShowingBeginnerCancelConfirmation: Bool = false
    @State var isShowingLeagueCancelConfirmation: Bool = false
    @State var isShowingFullVersionSheet: Bool = false
    @State var navigationPath: [AppScreen] = []
    @State var allowsProtectedBackNavigation: Bool = false

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                startView
                    .navigationDestination(for: AppScreen.self) { screen in
                        Group {
                            switch screen {
                            case .games:
                                gameModesView
                            case .practice:
                                practiceView
                            case .bloodyBeginner:
                                beginnerView
                            case .showmaster:
                                showView
                            case .miniWorldCup:
                                miniWorldCupView
                            case .league:
                                leagueView
                            case .statistics:
                                statisticsView
                            case .globe:
                                fullVersionUnlocked ? AnyView(globeView) : AnyView(fullVersionLockedView(feature: L("Globus", "Globe")))
                            case .achievements:
                                achievementsView
                            case .friends:
                                friendsView
                            case .options:
                                optionsView
                            }
                        }
                        .navigationBarBackButtonHidden(shouldDisableInteractiveBackSwipe)
                        .toolbar {
                            if shouldDisableInteractiveBackSwipe {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        Haptics.tap()
                                        guard !navigationPath.isEmpty else { return }
                                        allowsProtectedBackNavigation = true
                                        navigationPath.removeLast()
                                        DispatchQueue.main.async {
                                            allowsProtectedBackNavigation = false
                                        }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.headline.weight(.semibold))
                                    }
                                    .accessibilityLabel(L("Zurück", "Back"))
                                }
                            }
                        }
                        .background(
                            BackSwipeGestureController(isDisabled: shouldDisableInteractiveBackSwipe)
                                .frame(width: 0, height: 0)
                        )
                    }
            }
            .scaleEffect(isShowingStartupScreen ? 0.96 : 1)
            .opacity(isShowingStartupScreen ? 0.72 : 1)
            .blur(radius: isShowingStartupScreen ? 10 : 0)
            .animation(.spring(response: 0.58, dampingFraction: 0.86), value: isShowingStartupScreen)

            if isShowingStartupScreen {
                StartupScreen(
                    language: appLanguage,
                    completedItemCount: startupPreloadCompleted,
                    totalItemCount: startupPreloadTotal
                )
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                    .zIndex(1)
            }

            if tierDecayInfoIsExpanded, let tierDecayInfoPopup {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tierDecayInfoIsExpanded = false
                            self.tierDecayInfoPopup = nil
                        }
                    }
                    .zIndex(2)

                tierDecayInfoFloatingPopup(tierDecayInfoPopup)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 118)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(3)
            }

            if showBeginnerEasterEgg {
                beginnerEasterEggOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(4)
            }

            if let achievementPopupItem {
                AchievementPopup(item: achievementPopupItem, language: appLanguage)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                    .offset(y: achievementPopupDragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                achievementPopupDragOffset = min(max(value.translation.height, -120), 80)
                            }
                            .onEnded { value in
                                if value.translation.height < -34 || value.predictedEndTranslation.height < -70 {
                                    Haptics.tap()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        achievementPopupDragOffset = -140
                                        self.achievementPopupItem = nil
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        achievementPopupDragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
            }
        }
        .task {
            await runStartupWorkAfterFirstRender()
        }
        .sheet(item: $gameCenterAuthPresentation) { presentation in
            GameCenterAuthView(viewController: presentation.viewController)
        }
        .sheet(item: $selectedOnlineGlobePlayer) { player in
            onlineGlobeSheet(for: player)
        }
        .sheet(item: $selectedMenuInfoScreen) { screen in
            menuInfoSheet(for: screen)
        }
        .sheet(isPresented: $isShowingFullVersionSheet) {
            fullVersionUpsellSheet
        }
        .sheet(isPresented: $isShowingFriendList) {
            friendListSheet
        }
        .alert(L("Statistik zurücksetzen?", "Reset statistics?"), isPresented: $isShowingResetConfirmation) {
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            Button(L("Zurücksetzen", "Reset"), role: .destructive) {
                Haptics.notify(.warning)
                resetAllLocalData()
            }
        } message: {
            Text(L("Möchtest du wirklich deine komplette Statistik zurücksetzen? Dadurch wird dein gesamter Fortschritt gelöscht.", "Do you really want to reset your complete statistics? This will delete all of your progress."))
        }
        .alert(L("Üben abbrechen?", "Cancel Practice?"), isPresented: $isShowingPracticeCancelConfirmation) {
            Button(L("Weiter", "Continue"), role: .cancel) {}
            Button(L("Abbrechen", "Cancel"), role: .destructive) {
                Haptics.notify(.warning)
                finishPracticeSession(showSummary: practiceSessionCount > 0)
            }
        } message: {
            Text(L("Möchtest du diese Übungs-Session wirklich abbrechen?", "Do you really want to cancel this practice session?"))
        }
        .alert(L("Showmaster abbrechen?", "Cancel Showmaster?"), isPresented: $isShowingShowCancelConfirmation) {
            Button(L("Weiter", "Continue"), role: .cancel) {}
            Button(L("Abbrechen", "Cancel"), role: .destructive) {
                Haptics.notify(.warning)
                resetShowSession()
            }
        } message: {
            Text(L("Möchtest du diese Showmaster-Runde wirklich abbrechen?", "Do you really want to cancel this Showmaster round?"))
        }
        .alert(L("Anfänger beenden?", "End Beginner?"), isPresented: $isShowingBeginnerCancelConfirmation) {
            Button(L("Weiter", "Continue"), role: .cancel) {}
            Button(L("Beenden", "End"), role: .destructive) {
                Haptics.notify(.warning)
                finishBeginnerSession(showSummary: true)
            }
        } message: {
            Text(L("Möchtest du diese Anfänger-Session wirklich beenden?", "Do you really want to end this Beginner session?"))
        }
        .alert(L("\(runTitle) verlassen?", "Leave \(runTitle)?"), isPresented: $isShowingLeagueCancelConfirmation) {
            Button(L("Weiter", "Continue"), role: .cancel) {
                focusLeagueAnswerInputAfterLayout(delay: 0.15)
            }
            Button(L("Verlassen", "Leave"), role: .destructive) {
                Haptics.notify(.warning)
                finishLeagueMatch(aborted: true)
            }
        } message: {
            Text(L("Möchtest du diese Session wirklich beenden? Dein aktueller Stand wird als Ergebnis gespeichert.", "Do you really want to end this session? Your current score will be saved as the result."))
        }
        .tint(tealAccentColor)
        .preferredColorScheme(appTheme.colorScheme)
        .onChange(of: navigationPath) { oldPath, newPath in
            guard !allowsProtectedBackNavigation,
                  shouldRestoreProtectedNavigationPath(from: oldPath, to: newPath) else { return }
            DispatchQueue.main.async {
                navigationPath = oldPath
            }
        }
        .onChange(of: selectedSubject) { _, _ in
            abortActiveDailyLeagueMatchIfNeeded()
            dailyLeagueRefreshID += 1
            dailyLeagueChallenge = nil
            dailyLeagueStatus = nil
            dailyLeagueLeaderboard = []
            dailyLeagueAttempts = []
            dailyLeagueReservation = nil
            dailyLeagueStatusMessage = nil
            practiceSessionActive = false
            beginnerSessionActive = false
            beginnerSelectedCountry = nil
            beginnerSessionResults = []
            beginnerHistoryPreview = nil
            showBeginnerSummary = false
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
            showRecentCountryCodes = []
            showDeckCountryCodes = []
            showRecap = false
            practiceRecapPromptIsVisible = false
            statisticsSearchText = ""
            expandedOnlineLeaderboardSections = []
            cardIsFlipped = false
            resetCurrentCardHint()
            currentCountry = nextRandomCountry(excluding: currentCountry)
        }
        .onChange(of: includePartiallyRecognizedFlags) { _, _ in
            resetCountryPoolDependentState()
        }
        .onChange(of: includeDependentTerritories) { _, _ in
            resetCountryPoolDependentState()
        }
        .onChange(of: onlineFeaturesEnabled) { _, isEnabled in
            if isEnabled {
                onlineStatusText = L("Online-Rangliste noch nicht geladen", "Online leaderboard not loaded yet")
                gameCenterStatusText = L("Game Center noch nicht verbunden", "Game Center not connected")
                authenticateGameCenter(syncAfterAuthentication: true)
            } else {
                disableOnlineRuntimeState()
            }
        }
        .onChange(of: storeKit.purchasedFullVersion) { _, isUnlocked in
            fullVersionUnlocked = isUnlocked
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Keep an active Daily's absolute deadline. On return we use
                // the elapsed wall-clock time, so backgrounding cannot pause
                // the run or create extra time.
                flushLocalCache()
                return
            }

            guard phase == .active else { return }
            resumeLeagueCountdownIfNeeded()
            Task {
                await storeKit.refreshPurchasedProducts()
                fullVersionUnlocked = storeKit.purchasedFullVersion
                await retryPendingDailyCompletions()
                if onlineFeaturesEnabled,
                   dailyLeagueStatus?.dateKey != DailyFlaggenrunService.dateKey() {
                    dailyLeagueChallenge = nil
                    await refreshDailyLeagueStatus()
                }
            }
        }
        .onChange(of: fullVersionUnlocked) { _, isUnlocked in
            if !isUnlocked {
                if appAccent != .champion || !allAchievementsUnlocked {
                    appAccentRawValue = AppAccent.teal.rawValue
                }
                selectedStatisticsTier = nil
                expandedStatisticsCountryCodes = []
                statisticsSearchText = ""
            }
        }
    }
}
