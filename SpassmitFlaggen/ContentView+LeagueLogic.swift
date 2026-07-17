import SwiftUI
import Foundation
import UIKit
import UserNotifications
import AudioToolbox

extension ContentView {
    func leaguePointsForAnswer(responseTime: Double) -> Int {
        let basePoints = 100
        let speedBonus = max(0, Int((8.0 - min(responseTime, 8.0)) * 16.0))
        let timePressureBonus = max(0, leagueSecondsRemaining / 10)
        return basePoints + speedBonus + timePressureBonus
    }

    @MainActor
    func requestLeagueNotificationPermissionIfNeeded() async {
        guard !leagueNotificationsAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            leagueNotificationsAuthorized = true
            return
        }
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            leagueNotificationsAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            leagueNotificationsAuthorized = false
        }
    }

    func playLeagueSound(success: Bool) {
        AudioServicesPlaySystemSound(success ? 1057 : 1053)
    }

    func scheduleLeagueNotification(title: String, body: String) {
        guard leagueNotificationsAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "league-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    var onlineLeagueLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            if $0.runBestScore(for: selectedSubject) == $1.runBestScore(for: selectedSubject) {
                return $0.runPlayed(for: selectedSubject) > $1.runPlayed(for: selectedSubject)
            }
            return $0.runBestScore(for: selectedSubject) > $1.runBestScore(for: selectedSubject)
        }
    }

    @MainActor
    func startLeagueMatch() async {
        guard let practiceOrder = await prepareLeaguePracticeAssetsIfNeeded() else { return }
        isPreparingLeagueAssets = true
        defer { isPreparingLeagueAssets = false }
        await warmLeagueOpeningWindow(for: practiceOrder)
        startLeagueMatch(variant: .practice, reservation: nil, flagOrder: practiceOrder)
    }

    @MainActor
    func warmLeagueOpeningWindow(for countries: [Country]) async {
        // Decode the farther images first so the immediately upcoming flags are
        // the newest entries in the bounded cache and are least likely to evict.
        let openingWindow = Array(countries.prefix(20).reversed())
        await FlagImageCache.shared.warmInMemory(openingWindow)
    }

    func leaguePracticeAssetSignature(for countries: [Country]) -> String {
        countries.map(\.code).sorted().joined(separator: "|")
    }

    @MainActor
    func prepareLeaguePracticeAssetsIfNeeded() async -> [Country]? {
        let countries = availableCountries
        let signature = leaguePracticeAssetSignature(for: countries)
        if signature == leaguePreparedPracticeAssetSignature,
           leaguePreparedPracticeOrder.count == countries.count,
           !leaguePreparedPracticeOrder.isEmpty {
            return leaguePreparedPracticeOrder
        }

        guard !isPreparingLeagueAssets else { return nil }
        isPreparingLeagueAssets = true
        leagueAssetPreloadError = nil
        defer { isPreparingLeagueAssets = false }

        let practiceOrder = countries.shuffled()
        guard await prepareLeagueAssets(for: practiceOrder) else { return nil }
        leaguePreparedPracticeOrder = practiceOrder
        leaguePreparedPracticeAssetSignature = signature
        return practiceOrder
    }

    @MainActor
    func prepareDailyLeagueOpeningAssetsIfAvailable() async {
        guard let dailyLeagueChallenge else { return }
        let order = countries(forDailyOrder: dailyLeagueChallenge.flagOrder)
        guard !order.isEmpty, !isPreparingLeagueAssets else { return }

        let signature = leagueDailyAssetSignature(for: dailyLeagueChallenge)
        guard signature != leaguePreparedDailyAssetSignature else { return }

        isPreparingLeagueAssets = true
        defer { isPreparingLeagueAssets = false }
        guard await prepareLeagueAssets(for: order) else { return }
        leaguePreparedDailyAssetSignature = signature
    }

    func leagueDailyAssetSignature(for challenge: DailyChallenge) -> String {
        "\(challenge.dateKey)|\(challenge.mode)|\(challenge.flagOrder.joined(separator: "|"))"
    }

    @MainActor
    func startDailyLeagueMatch() async {
        guard !isPreparingLeagueAssets else { return }
        isLoadingDailyLeague = true
        isPreparingLeagueAssets = true
        dailyLeagueStatusMessage = nil
        leagueAssetPreloadError = nil
        defer {
            isLoadingDailyLeague = false
            isPreparingLeagueAssets = false
        }

        let expectedMode = DailyFlaggenrunService.mode(for: selectedSubject)
        let expectedDateKey = DailyFlaggenrunService.dateKey()
        if dailyLeagueChallenge?.mode != expectedMode || dailyLeagueChallenge?.dateKey != expectedDateKey {
            await refreshDailyLeagueStatus()
        }
        guard let dailyLeagueChallenge,
              dailyLeagueChallenge.mode == expectedMode,
              dailyLeagueChallenge.dateKey == expectedDateKey else {
            leagueAssetPreloadError = L("Der Daily Run konnte nicht vorbereitet werden. Bitte versuche es erneut.", "The Daily Run could not be prepared. Please try again.")
            return
        }

        let plannedOrder = countries(forDailyOrder: dailyLeagueChallenge.flagOrder)
        let plannedSignature = leagueDailyAssetSignature(for: dailyLeagueChallenge)
        if plannedSignature != leaguePreparedDailyAssetSignature {
            guard await prepareLeagueAssets(for: plannedOrder) else { return }
            leaguePreparedDailyAssetSignature = plannedSignature
        }
        await warmLeagueOpeningWindow(for: plannedOrder)
        await requestLeagueNotificationPermissionIfNeeded()

        do {
            let reservation = try await DailyFlaggenrunService.reserveAttempt(
                subject: selectedSubject,
                gameCenterPlayerID: gameCenterPlayerID,
                displayName: onlineDisplayName,
                countries: dailyLeagueCountries
            )
            let orderedCountries = countries(forDailyOrder: reservation.flagOrder)
            if orderedCountries.map(\.code) != plannedOrder.map(\.code) {
                guard await prepareLeagueAssets(for: orderedCountries) else { return }
            }
            dailyLeagueReservation = reservation
            dailyLeagueStatus?.attemptsUsed += 1
            startLeagueMatch(variant: .daily, reservation: reservation, flagOrder: orderedCountries)
        } catch {
            dailyLeagueStatusMessage = OnlineStatsService.userFacingMessage(for: error)
        }
    }

    @MainActor
    func prepareLeagueAssets(for countries: [Country]) async -> Bool {
        guard !countries.isEmpty else {
            leagueAssetPreloadError = L("Keine Flaggen für diesen Run gefunden.", "No flags were found for this run.")
            return false
        }

        leagueAssetPreloadCompleted = 0
        leagueAssetPreloadTotal = countries.count
        let report = await FlagImageCache.shared.preloadToDisk(
            countries: countries,
            maximumConcurrentDownloads: 6,
            maximumDuration: 30
        ) { completed, total in
            leagueAssetPreloadCompleted = completed
            leagueAssetPreloadTotal = total
        }

        guard report.isComplete else {
            leagueAssetPreloadError = L(
                "Nicht alle Flaggen konnten geladen werden (\(report.cachedCount)/\(report.totalCount)). Prüfe bitte deine Verbindung und versuche es erneut.",
                "Not all flags could be loaded (\(report.cachedCount)/\(report.totalCount)). Please check your connection and try again."
            )
            return false
        }

        // Keep the opening stretch decoded in memory. The complete run remains
        // available on disk, while a rolling look-ahead warms later flags.
        await warmLeagueOpeningWindow(for: countries)
        leagueAssetPreloadCompleted = leagueAssetPreloadTotal
        return true
    }

    @MainActor
    func startLeagueMatch(variant: LeagueRunVariant, reservation: DailyAttemptReservation?, flagOrder: [Country]) {
        leagueRunVariant = variant
        dailyLeagueReservation = reservation
        dailyLeagueFlagOrder = flagOrder
        dailyLeagueFlagIndex = 0
        lastDailyLeagueResultWasBest = nil
        leagueCorrect = 0
        leagueWrong = 0
        leagueScore = 0
        leagueSecondsRemaining = 60
        leagueRecentCountryCodes = []
        leagueAnswerRecords = []
        leagueAnswerText = ""
        leagueAnswerCandidates = []
        leagueAnswerMatch = nil
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueFocusTask?.cancel()
        leagueFocusTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueCandidateAttentionTask?.cancel()
        leagueCandidateAttentionTask = nil
        leagueCandidateAttentionPulse = false
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueTimerIsRunning = false
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueCurrentQuestionStartedAt = Date()
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueAnswerCandidates = []
        leagueStartCountdown = 3
        leagueFirstFlagIsReady = false
        leaguePreloadedFlagImage = nil
        leagueLookaheadWarmTask?.cancel()
        leagueLookaheadWarmTask = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        leagueCurrentCountry = nextLeagueCountry()
        if let flagURL = leagueCurrentCountry.flagImageURL {
            leaguePreloadedFlagImage = FlagImageCache.shared.image(for: flagURL)
        }
        // Always show the short preparation phase. It gives iOS time to create
        // the keyboard even when the first flag was already decoded.
        leagueMatchPhase = .loading
        leagueMatchActive = true
    }

    func focusLeagueAnswerInputAfterLayout(delay: Double = 0.30) {
        leagueFocusTask?.cancel()
        leagueFocusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard leagueMatchActive, leagueMatchPhase == .playing, !leagueInputIsLocked else { return }
            if !isLeagueAnswerFocused {
                isLeagueAnswerFocused = true
            }
            leagueFocusTask = nil
        }
    }

    func prepareLeagueTimerAfterLayout() {
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = Task { @MainActor in
            await Task.yield()
            if leaguePreloadedFlagImage == nil {
                leagueMatchPhase = .loading
                await prepareFirstLeagueFlag()
            } else {
                scheduleLeagueLookaheadWarmup()
            }
            guard leagueMatchActive else { return }
            leagueFirstFlagIsReady = true

            // The real input field stays mounted behind the preparation layer.
            // Focus it before the countdown so keyboard creation and its layout
            // animation are complete well before the timed round begins.
            isLeagueAnswerFocused = true
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(320))
            guard leagueMatchActive else { return }

            leagueMatchPhase = .countdown
            for value in stride(from: 3, through: 1, by: -1) {
                leagueStartCountdown = value
                try? await Task.sleep(for: .seconds(1))
                guard leagueMatchActive else { return }
            }

            leagueAnswerText = ""
            leagueAnswerCandidates = []
            leagueAnswerMatch = nil
            leagueMatchPhase = .playing
            leagueCurrentQuestionStartedAt = Date()
            await Task.yield()
            // Allow the real input field to inherit the already warm keyboard
            // and finish its first layout before starting the fair-play timer.
            try? await Task.sleep(for: .milliseconds(320))
            guard leagueMatchActive else { return }
            leagueTimerIsRunning = true
            startLeagueCountdown()
        }
    }

    func prepareFirstLeagueFlag() async {
        guard leagueMatchActive else { return }
        leaguePreloadedFlagImage = await preloadedLeagueFlagImage(for: leagueCurrentCountry)
        scheduleLeagueLookaheadWarmup()
    }

    func preloadedLeagueFlagImage(for country: Country) async -> UIImage? {
        guard let url = country.flagImageURL else { return nil }
        return try? await FlagImageCache.shared.loadImage(from: url)
    }

    func scheduleLeagueLookaheadWarmup() {
        guard leagueLookaheadWarmTask == nil, !dailyLeagueFlagOrder.isEmpty else { return }
        let startIndex = dailyLeagueFlagIndex % dailyLeagueFlagOrder.count
        let orderedLookahead = (0..<20).map { offset in
            dailyLeagueFlagOrder[(startIndex + offset) % dailyLeagueFlagOrder.count]
        }
        leagueLookaheadWarmTask = Task { @MainActor in
            await FlagImageCache.shared.warmInMemory(Array(orderedLookahead.reversed()))
            guard !Task.isCancelled else { return }
            leagueLookaheadWarmTask = nil

            // If the player advanced while this window was being decoded,
            // immediately warm a new window from the latest position.
            if leagueMatchActive,
               !dailyLeagueFlagOrder.isEmpty,
               dailyLeagueFlagIndex % dailyLeagueFlagOrder.count != startIndex {
                scheduleLeagueLookaheadWarmup()
            }
        }
    }

    func startLeagueCountdown() {
        leagueCountdownTask?.cancel()
        let endDate = Date().addingTimeInterval(Double(leagueSecondsRemaining))
        leagueCountdownTask = Task { @MainActor in
            while leagueMatchActive && leagueTimerIsRunning {
                let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
                leagueSecondsRemaining = remaining
                if remaining == 0 {
                    finishLeagueMatch()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func submitLeagueAnswer() {
        // Return only submits a sufficiently clear recognition. Ambiguous or
        // unusable input keeps the keyboard open instead of recording a guess.
        guard leagueAnswerCandidates.count < 2 else {
            keepLeagueKeyboardOpen(highlightCandidates: true)
            return
        }
        guard let match = leagueAnswerMatch ?? bestLeagueAnswerMatch(for: leagueAnswerText),
              match.isAcceptable || match.isCertain else {
            keepLeagueKeyboardOpen(highlightCandidates: false)
            return
        }
        submitLeagueAnswer(forcedCorrectness: nil, keepsTypedAnswer: true)
    }

    func keepLeagueKeyboardOpen(highlightCandidates: Bool) {
        guard leagueMatchActive, leagueTimerIsRunning, !leagueInputIsLocked else { return }
        if !isLeagueAnswerFocused {
            focusLeagueAnswerInputAfterLayout(delay: 0.01)
        }

        leagueCandidateAttentionTask?.cancel()
        leagueCandidateAttentionTask = nil
        guard highlightCandidates, leagueAnswerCandidates.count >= 2 else {
            leagueCandidateAttentionPulse = false
            return
        }

        leagueCandidateAttentionPulse = false
        leagueCandidateAttentionTask = Task { @MainActor in
            await Task.yield()
            guard leagueMatchActive, leagueAnswerCandidates.count >= 2 else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.58)) {
                leagueCandidateAttentionPulse = true
            }
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                leagueCandidateAttentionPulse = false
            }
        }
    }

    func submitLeagueAnswer(forcedCorrectness: Bool?, keepsTypedAnswer: Bool) {
        guard leagueMatchActive, leagueTimerIsRunning, !leagueInputIsLocked else { return }
        let answer = normalizedLeagueAnswer(leagueAnswerText)
        guard !answer.isEmpty || forcedCorrectness != nil else { return }
        let match = leagueAnswerMatch ?? bestLeagueAnswerMatch(for: leagueAnswerText)
        let isCorrect = forcedCorrectness ?? (match?.country == leagueCurrentCountry && (match?.isAcceptable == true || match?.isCertain == true))
        let correctCountryName = leagueExpectedAnswerName(for: leagueCurrentCountry)
        let submittedAnswer = leagueAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleSubmittedAnswer = submittedAnswer.isEmpty ? L("Weiß ich nicht", "I don't know") : submittedAnswer
        let detectedCountryName = match.map { leagueExpectedAnswerName(for: $0.country) } ?? L("Keine eindeutige Erkennung", "No clear detection")
        let responseTime = Date().timeIntervalSince(leagueCurrentQuestionStartedAt)
        let pointsAwarded = isCorrect ? leaguePointsForAnswer(responseTime: responseTime) : 0

        leagueLockedAnswerText = keepsTypedAnswer ? leagueAnswerText : ""
        leagueAnswerCandidates = []
        leagueInputIsLocked = true
        leagueTypingLockedUntil = .distantFuture
        leagueMatchPhase = .feedback
        leagueAnswerFeedback = isCorrect
        leagueRevealedCountryName = correctCountryName
        leagueAnswerRecords.append(
            LeagueAnswerRecord(
                id: UUID(),
                countryCode: leagueCurrentCountry.code,
                countryName: correctCountryName,
                submittedAnswer: visibleSubmittedAnswer,
                detectedCountryName: detectedCountryName,
                wasCorrect: isCorrect,
                responseTime: responseTime,
                pointsAwarded: pointsAwarded
            )
        )

        if isCorrect {
            leagueCorrect += 1
            leagueScore += pointsAwarded
            Haptics.tap(style: .heavy)
            Haptics.notify(.success)
            playLeagueSound(success: true)
        } else {
            leagueWrong += 1
            leagueScore = max(0, leagueScore - 25)
            Haptics.tap(style: .light)
            playLeagueSound(success: false)
        }

        leagueRecentCountryCodes.append(leagueCurrentCountry.code)
        leagueRecentCountryCodes = Array(leagueRecentCountryCodes.suffix(12))
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard leagueMatchActive else { return }
            leagueAnswerFeedback = nil
            leagueRevealedCountryName = ""
        }
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = Task { @MainActor in
            guard leagueMatchActive else { return }
            let nextCountry = nextLeagueCountry()
            let nextImage = await preloadedLeagueFlagImage(for: nextCountry)
            leagueAnswerText = ""
            leagueLockedAnswerText = ""
            leagueAnswerCandidates = []
            leagueCandidateAttentionTask?.cancel()
            leagueCandidateAttentionTask = nil
            leagueCandidateAttentionPulse = false
            leagueAnswerMatch = nil
            leagueCurrentCountry = nextCountry
            leaguePreloadedFlagImage = nextImage
            scheduleLeagueLookaheadWarmup()
            leagueMatchPhase = .playing
            leagueTypingLockedUntil = Date().addingTimeInterval(0.32)
            try? await Task.sleep(for: .milliseconds(320))
            guard leagueMatchActive, leagueCurrentCountry == nextCountry else { return }
            leagueInputIsLocked = false
            leagueTypingLockedUntil = .distantPast
            leagueCurrentQuestionStartedAt = Date()
        }
    }

    func finishLeagueMatch(aborted: Bool = false) {
        guard leagueMatchActive else { return }
        let finishedVariant = leagueRunVariant
        let finishedReservation = dailyLeagueReservation
        let finishedScore = leagueScore
        let finishedCorrect = leagueCorrect
        let finishedWrong = leagueWrong
        let finishedRemainingTime = Double(leagueSecondsRemaining)
        let finishedAnswerRecords = leagueAnswerRecords
        leagueMatchActive = false
        leagueTimerIsRunning = false
        isLeagueAnswerFocused = false
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueFocusTask?.cancel()
        leagueFocusTask = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueCandidateAttentionTask?.cancel()
        leagueCandidateAttentionTask = nil
        leagueCandidateAttentionPulse = false
        leagueLookaheadWarmTask?.cancel()
        leagueLookaheadWarmTask = nil
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueMatchPhase = .loading

        let result = LeagueMatchResult(
            id: UUID(),
            date: Date(),
            opponentName: finishedVariant == .daily ? dailyRunTitle : L("Übung", "Practice"),
            ownScore: finishedScore,
            opponentScore: 0,
            correct: finishedCorrect,
            wrong: finishedWrong,
            duration: 60,
            answerDetails: finishedAnswerRecords,
            ratingBefore: nil,
            ratingAfter: nil,
            ratingDelta: nil,
            runVariant: finishedVariant,
            dailyAttemptNumber: finishedReservation?.attemptNumber,
            dailyDateKey: finishedReservation?.dateKey,
            subject: finishedReservation?.subject ?? selectedSubject,
            wasAborted: aborted
        )

        leagueSummaryResult = result
        leagueShowsStartMenu = true
        updateActiveProfile { profile in
            profile.recordLeagueMatch(result)
        }
        if finishedVariant == .daily, let finishedReservation {
            let completion = DailyRunCompletion(
                reservation: finishedReservation,
                displayName: onlineDisplayName,
                score: finishedScore,
                correctCount: finishedCorrect,
                wrongCount: finishedWrong,
                duration: max(0, 60 - finishedRemainingTime),
                remainingTime: finishedRemainingTime,
                completed: !aborted,
                aborted: aborted,
                // The upload retry queue is durable and may contain several
                // offline runs. The service only submits the first 20 answers,
                // so retaining a small safety margin avoids needless growth.
                answerRecords: Array(finishedAnswerRecords.prefix(40)),
                completedAt: result.date
            )
            DailyCompletionQueue.enqueue(completion)
            Task { @MainActor in
                await completeDailyLeagueMatch(completion)
            }
        }
        Haptics.notify(.success)
        playLeagueSound(success: true)
    }

    func abortActiveDailyLeagueMatchIfNeeded() {
        guard leagueMatchActive, leagueRunVariant == .daily else { return }
        finishLeagueMatch(aborted: true)
    }

    @MainActor
    func completeDailyLeagueMatch(_ completion: DailyRunCompletion) async {
        do {
            let leaderboard = try await DailyFlaggenrunService.completeAttempt(
                completion,
                gameCenterPlayerID: gameCenterPlayerID
            )
            DailyCompletionQueue.remove(id: completion.id)
            if completion.reservation.subject == selectedSubject {
                dailyLeagueLeaderboard = leaderboard
                lastDailyLeagueResultWasBest = leaderboard.first(where: { $0.userId == completion.reservation.userId })?.bestAttemptNumber == completion.reservation.attemptNumber
                await refreshDailyLeagueStatus()
            }
        } catch {
            dailyLeagueStatusMessage = OnlineStatsService.userFacingMessage(for: error)
        }
        dailyLeagueReservation = nil
        dailyLeagueFlagOrder = []
        dailyLeagueFlagIndex = 0
    }

    @MainActor
    func retryPendingDailyCompletions() async {
        guard onlineFeaturesEnabled, !isRetryingPendingDailyCompletions else { return }
        let pending = DailyCompletionQueue.load()
        guard !pending.isEmpty else { return }
        isRetryingPendingDailyCompletions = true
        defer { isRetryingPendingDailyCompletions = false }

        for completion in pending {
            do {
                let leaderboard = try await DailyFlaggenrunService.completeAttempt(
                    completion,
                    gameCenterPlayerID: gameCenterPlayerID
                )
                DailyCompletionQueue.remove(id: completion.id)
                if completion.reservation.subject == selectedSubject,
                   completion.reservation.dateKey == DailyFlaggenrunService.dateKey() {
                    dailyLeagueLeaderboard = leaderboard
                }
            } catch {
                dailyLeagueStatusMessage = OnlineStatsService.userFacingMessage(for: error)
                break
            }
        }
    }

    @MainActor
    func refreshDailyLeagueStatus() async {
        dailyLeagueRefreshID += 1
        let refreshID = dailyLeagueRefreshID
        let requestedSubject = selectedSubject
        isLoadingDailyLeague = true
        defer {
            if dailyLeagueRefreshID == refreshID {
                isLoadingDailyLeague = false
            }
        }
        do {
            let daily = try await DailyFlaggenrunService.status(subject: requestedSubject, gameCenterPlayerID: gameCenterPlayerID, countries: dailyLeagueCountries)
            guard dailyLeagueRefreshID == refreshID,
                  selectedSubject == requestedSubject,
                  daily.status.dateKey == DailyFlaggenrunService.dateKey(),
                  daily.status.mode == DailyFlaggenrunService.mode(for: requestedSubject) else { return }
            dailyLeagueChallenge = daily.challenge
            dailyLeagueStatus = daily.status
            dailyLeagueLeaderboard = daily.leaderboard
            dailyLeagueAttempts = daily.attempts
            dailyLeagueStatusMessage = nil
        } catch {
            guard dailyLeagueRefreshID == refreshID, selectedSubject == requestedSubject else { return }
            dailyLeagueStatusMessage = OnlineStatsService.userFacingMessage(for: error)
        }
    }

    @MainActor
    func refreshTrophyLeaderboard() async {
        guard onlineFeaturesEnabled, !isLoadingTrophyLeaderboard else { return }
        isLoadingTrophyLeaderboard = true
        defer { isLoadingTrophyLeaderboard = false }
        do {
            trophyLeaderboard = try await DailyFlaggenrunService.fetchTrophyLeaderboard()
            trophyLeaderboardMessage = nil
        } catch {
            trophyLeaderboardMessage = OnlineStatsService.userFacingMessage(for: error)
        }
    }

    var dailyLeagueCountries: [Country] {
        allCountries
    }

    func countries(forDailyOrder order: [String]) -> [Country] {
        let byCode = Dictionary(uniqueKeysWithValues: dailyLeagueCountries.map { ($0.code, $0) })
        let ordered = order.compactMap { byCode[$0] }
        return ordered.isEmpty ? dailyLeagueCountries : ordered
    }

    func nextLeagueCountry() -> Country {
        if !dailyLeagueFlagOrder.isEmpty {
            let country = dailyLeagueFlagOrder[dailyLeagueFlagIndex % dailyLeagueFlagOrder.count]
            dailyLeagueFlagIndex += 1
            return country
        }

        let candidates = availableCountries.filter { !leagueRecentCountryCodes.contains($0.code) }
        return (candidates.isEmpty ? availableCountries : candidates).randomElement() ?? allCountries[0]
    }

    func evaluateLeagueAnswer(_ value: String) {
        leagueAutoSubmitTask?.cancel()
        leagueCandidateAttentionTask?.cancel()
        leagueCandidateAttentionTask = nil
        leagueCandidateAttentionPulse = false
        let match = bestLeagueAnswerMatch(for: value)
        leagueAnswerMatch = match
        let candidates = leagueCandidateCountries(for: value)
        leagueAnswerCandidates = candidates

        guard
            leagueMatchActive,
            let match,
            !leagueInputIsLocked,
            candidates.isEmpty,
            match.isCertain
        else {
            return
        }

        let submittedText = value
        leagueAutoSubmitTask = Task { @MainActor in
            await Task.yield()
            guard leagueMatchActive,
                  leagueAnswerText == submittedText,
                  leagueAnswerCandidates.isEmpty,
                  leagueAnswerMatch?.isCertain == true else { return }
            submitLeagueAnswer()
        }
    }

    func chooseLeagueCandidate(_ country: Country) {
        guard leagueMatchActive, leagueTimerIsRunning, !leagueInputIsLocked else { return }
        Haptics.tap()
        let answerName = leagueExpectedAnswerName(for: country)
        leagueAnswerText = answerName
        leagueAnswerMatch = bestLeagueAnswerMatch(for: answerName)
        leagueAnswerCandidates = []
        submitLeagueAnswer(forcedCorrectness: nil, keepsTypedAnswer: true)
    }

    func leagueCandidateCountries(for rawAnswer: String) -> [Country] {
        let answer = normalizedLeagueAnswer(rawAnswer)
        guard answer.count >= 2 else { return [] }

        let prefixCandidates = availableCountries
            .filter { country in
                leagueAnswerAliases(for: country).contains { alias in
                    alias.normalizedName.hasPrefix(answer)
                }
            }
            .sorted { first, second in
                leagueExpectedAnswerName(for: first) < leagueExpectedAnswerName(for: second)
            }

        let exactCountryCodes = Set(prefixCandidates.compactMap { country -> String? in
            leagueAnswerAliases(for: country).contains { $0.normalizedName == answer } ? country.code : nil
        })
        if !exactCountryCodes.isEmpty {
            let longerPrefixCandidates = prefixCandidates.filter { !exactCountryCodes.contains($0.code) }
            return longerPrefixCandidates.isEmpty ? [] : Array(prefixCandidates.prefix(4))
        }

        if prefixCandidates.count >= 2 {
            return Array(prefixCandidates.prefix(4))
        }

        let rankedMatches = scoredLeagueAnswerMatches(for: answer)
        guard let bestMatch = rankedMatches.first else { return [] }

        if let prefixCountry = prefixCandidates.first {
            let plausibleAlternative = rankedMatches.first { match in
                match.country.code != prefixCountry.code
                    && match.confidence >= 0.82
                    && bestMatch.confidence - match.confidence <= 0.12
            }
            guard let plausibleAlternative else { return [] }
            return [prefixCountry, plausibleAlternative.country]
                .sorted { leagueExpectedAnswerName(for: $0) < leagueExpectedAnswerName(for: $1) }
        }

        let plausibleMatches = rankedMatches.prefix(while: { match in
            match.confidence >= 0.80
                && bestMatch.confidence - match.confidence <= 0.10
        })
        let candidates = plausibleMatches.prefix(4).map(\.country)
        return candidates.count >= 2 ? candidates : []
    }

    func bestLeagueAnswerMatch(for rawAnswer: String) -> LeagueAnswerMatch? {
        let answer = normalizedLeagueAnswer(rawAnswer)
        guard answer.count >= 2 else { return nil }

        // An exact country/capital name must always win, even when another name
        // shares the same prefix (for example Niger and Nigeria).
        if let exactCountry = availableCountries.first(where: { country in
            leagueAnswerAliases(for: country).contains { $0.normalizedName == answer }
        }), let exactAlias = leagueAnswerAliases(for: exactCountry).first(where: { $0.normalizedName == answer }) {
            let hasLongerPrefixCollision = availableCountries.contains { country in
                guard country.code != exactCountry.code else { return false }
                return leagueAnswerAliases(for: country).contains { alias in
                    alias.normalizedName.count > answer.count && alias.normalizedName.hasPrefix(answer)
                }
            }
            return LeagueAnswerMatch(
                country: exactCountry,
                matchedName: exactAlias.displayName,
                normalizedAnswer: answer,
                normalizedMatchedName: exactAlias.normalizedName,
                confidence: 1,
                // Keep the exact answer valid when it is selected, but do not
                // auto-submit while a longer country name is still possible
                // (Niger/Nigeria, Guinea/Guinea-Bissau, etc.).
                runnerUpConfidence: hasLongerPrefixCollision ? 0.95 : 0
            )
        }

        let scoredMatches = scoredLeagueAnswerMatches(for: answer)

        guard let best = scoredMatches.first else { return nil }
        let runnerUp = scoredMatches.dropFirst().first?.confidence ?? 0
        return LeagueAnswerMatch(
            country: best.country,
            matchedName: best.matchedName,
            normalizedAnswer: best.normalizedAnswer,
            normalizedMatchedName: best.normalizedMatchedName,
            confidence: best.confidence,
            runnerUpConfidence: runnerUp
        )
    }

    func scoredLeagueAnswerMatches(for answer: String) -> [LeagueAnswerMatch] {
        availableCountries.compactMap { country -> LeagueAnswerMatch? in
            let aliases = leagueAnswerAliases(for: country)
            guard let bestAlias = aliases
                .map({ alias in (name: alias.displayName, normalizedName: alias.normalizedName, score: leagueSimilarity(answer: answer, candidate: alias.normalizedName)) })
                .max(by: { $0.score < $1.score })
            else {
                return nil
            }

            guard bestAlias.score >= 0.45 else { return nil }
            return LeagueAnswerMatch(
                country: country,
                matchedName: bestAlias.name,
                normalizedAnswer: answer,
                normalizedMatchedName: bestAlias.normalizedName,
                confidence: bestAlias.score,
                runnerUpConfidence: 0
            )
        }
        .sorted { first, second in
            if first.confidence == second.confidence {
                return localizedCountryName(first.country, language: appLanguage).count < localizedCountryName(second.country, language: appLanguage).count
            }
            return first.confidence > second.confidence
        }
    }

    func leagueExpectedAnswerName(for country: Country) -> String {
        selectedSubject == .capitals ? capitalName(for: country) : localizedCountryName(country, language: appLanguage)
    }

    func leagueAnswerAliases(for country: Country) -> [(displayName: String, normalizedName: String)] {
        if selectedSubject == .capitals {
            let rawAliases = [
                capitalName(for: country),
                capitalPronunciationByCountryCode[country.code]
            ].compactMap { $0 } + leagueCapitalExtraAliases(for: country)

            return Set(rawAliases).map { alias in
                (displayName: alias, normalizedName: normalizedLeagueAnswer(alias))
            }
            .filter { !$0.normalizedName.isEmpty }
        }

        let rawAliases = [
            localizedCountryName(country, language: appLanguage),
            country.name,
            countryEnglishNameByCode[country.code]
        ].compactMap { $0 } + leagueExtraAliases(for: country)

        let aliases = Set(rawAliases.flatMap { name -> [String] in
            let normalized = normalizedLeagueAnswer(name)
            var values = [name]
            if normalized.hasPrefix("vereinigte ") {
                values.append(normalized.replacingOccurrences(of: "vereinigte ", with: ""))
            }
            if normalized.hasPrefix("demokratische republik ") {
                values.append(normalized.replacingOccurrences(of: "demokratische republik ", with: ""))
            }
            if name.contains("("), let prefix = name.split(separator: "(").first {
                values.append(String(prefix))
            }
            return values.flatMap { leagueCountrySpellingVariants(for: $0) }
        })

        return aliases.map { alias in
            (displayName: alias, normalizedName: normalizedLeagueAnswer(alias))
        }
        .filter { !$0.normalizedName.isEmpty }
    }

    func leagueCountrySpellingVariants(for rawName: String) -> [String] {
        let normalized = normalizedLeagueAnswer(rawName)
        guard !normalized.isEmpty else { return [] }

        var connectorVariants: Set<String> = [normalized]
        if normalized.contains(" and ") {
            connectorVariants.insert(normalized.replacingOccurrences(of: " and ", with: " und "))
        }
        if normalized.contains(" und ") {
            connectorVariants.insert(normalized.replacingOccurrences(of: " und ", with: " and "))
        }

        var variants = connectorVariants
        for value in connectorVariants {
            let remainder: String?
            if value.hasPrefix("st ") {
                remainder = String(value.dropFirst(3))
            } else if value.hasPrefix("saint ") {
                remainder = String(value.dropFirst(6))
            } else if value.hasPrefix("sankt ") {
                remainder = String(value.dropFirst(6))
            } else {
                remainder = nil
            }

            if let remainder, !remainder.isEmpty {
                variants.insert("st \(remainder)")
                variants.insert("saint \(remainder)")
                variants.insert("sankt \(remainder)")
            }
        }

        return Array(variants)
    }

    func leagueCapitalExtraAliases(for country: Country) -> [String] {
        switch country.code {
        case "AT": return ["Vienna"]
        case "BE": return ["Brussels"]
        case "BG": return ["Sofia"]
        case "BY": return ["Minsk"]
        case "CH": return ["Berne"]
        case "CN": return ["Beijing"]
        case "CZ": return ["Prague"]
        case "DK": return ["Copenhagen"]
        case "EG": return ["Cairo"]
        case "FI": return ["Helsinki"]
        case "GB": return ["London"]
        case "GR": return ["Athens"]
        case "HU": return ["Budapest"]
        case "IS": return ["Reykjavik"]
        case "IT": return ["Rome"]
        case "JP": return ["Tokyo"]
        case "KP": return ["Pyongyang"]
        case "NO": return ["Oslo"]
        case "PL": return ["Warsaw"]
        case "RO": return ["Bucharest"]
        case "RU": return ["Moscow"]
        case "SE": return ["Stockholm"]
        case "TR": return ["Ankara"]
        case "UA": return ["Kyiv", "Kiev"]
        case "US": return ["Washington DC", "Washington D C", "Washington"]
        case "MX": return ["Mexico City", "Mexiko City"]
        case "VA": return ["Vatikanstadt", "Vatican City"]
        case "ZA": return ["Pretoria", "Kapstadt", "Cape Town", "Bloemfontein"]
        case "LK": return ["Colombo", "Sri Jayawardenepura"]
        case "BO": return ["La Paz", "Sucre"]
        case "NL": return ["Den Haag", "The Hague", "Amsterdam"]
        default: return []
        }
    }

    func leagueExtraAliases(for country: Country) -> [String] {
        switch country.code {
        case "CH": return ["Swiss", "Suisse", "Svizzera", "Schweizerische Eidgenossenschaft"]
        case "US": return ["USA", "U.S.A.", "America", "United States of America", "Vereinigte Staaten von Amerika"]
        case "GB": return ["UK", "U.K.", "Great Britain", "Britain", "England", "Großbritannien", "Grossbritannien"]
        case "AE": return ["UAE", "Emirates", "VAE"]
        case "BA": return ["Bosnien", "Bosnia"]
        case "BO": return ["Bolivia"]
        case "BN": return ["Brunei Darussalam"]
        case "BY": return ["Weissrussland", "Weißrussland"]
        case "CD": return ["DR Kongo", "Demokratische Republik Kongo", "Kongo Kinshasa", "Congo Kinshasa", "DR Congo"]
        case "CG": return ["Republik Kongo", "Kongo Brazzaville", "Congo Brazzaville"]
        case "CI": return ["Elfenbeinkueste", "Elfenbeinkuste", "Ivory Coast", "Cote d Ivoire", "Côte d'Ivoire"]
        case "CZ": return ["Tschechische Republik", "Czech Republic"]
        case "DO": return ["Dominikanische Rep", "Dominican Rep"]
        case "FM": return ["Micronesia"]
        case "GQ": return ["Equatorial Guinea"]
        case "GW": return ["Guinea Bissau"]
        case "KR": return ["Korea Sued", "Korea Sud", "South Korea", "Republic of Korea"]
        case "KP": return ["Korea Nord", "North Korea"]
        case "LA": return ["Lao", "Laos"]
        case "MD": return ["Moldova"]
        case "MK": return ["Mazedonien", "Macedonia"]
        case "MM": return ["Burma", "Birma"]
        case "PS": return ["Palestine"]
        case "RU": return ["Russian Federation"]
        case "ST": return ["Sao Tome", "São Tomé"]
        case "SZ": return ["Eswatini", "Swasiland", "Swaziland"]
        case "TL": return ["Timor Leste", "East Timor"]
        case "TR": return ["Turkey"]
        case "TZ": return ["Tanzania"]
        case "VA": return ["Vatican", "Vatikan"]
        case "VN": return ["Viet Nam"]
        case "ZA": return ["South Africa"]
        default: return []
        }
    }

    func leagueSimilarity(answer: String, candidate: String) -> Double {
        guard !answer.isEmpty, !candidate.isEmpty else { return 0 }
        if answer == candidate { return 1 }
        if let tokenScore = leagueTokenPrefixSimilarity(answer: answer, candidate: candidate) {
            return tokenScore
        }

        let shorterCount = min(answer.count, candidate.count)
        let longerCount = max(answer.count, candidate.count)
        let prefixLength = commonPrefixLength(answer, candidate)

        if candidate.hasPrefix(answer), answer.count >= 3 {
            let completeness = Double(answer.count) / Double(candidate.count)
            return min(0.97, 0.80 + completeness * 0.18)
        }

        // Prefer an almost complete country name with one or two mistakes over
        // a merely similar beginning of a different, longer name. This covers
        // inputs such as "dischi" for "Fidschi" without hard-coded countries.
        if abs(answer.count - candidate.count) <= 1, longerCount >= 5 {
            let nearCompleteDistance = levenshteinDistance(answer, candidate, maxDistance: 2)
            if nearCompleteDistance <= 2 {
                let nearCompleteSimilarity = 1 - (Double(nearCompleteDistance) / Double(longerCount))
                return min(0.96, 0.76 + nearCompleteSimilarity * 0.16)
            }
        }

        if answer.count < candidate.count, answer.count >= 3 {
            let candidatePrefix = String(candidate.prefix(answer.count))
            let prefixDistance = levenshteinDistance(answer, candidatePrefix, maxDistance: 2)
            if prefixDistance <= 2 {
                let prefixSimilarity = 1 - (Double(prefixDistance) / Double(max(answer.count, candidatePrefix.count)))
                let completeness = Double(answer.count) / Double(candidate.count)
                if prefixSimilarity >= 0.58 {
                    return min(0.94, 0.62 + prefixSimilarity * 0.20 + completeness * 0.12)
                }
            }
        }

        if answer.hasPrefix(candidate), candidate.count >= 3 {
            let extraPenalty = Double(answer.count - candidate.count) / Double(max(answer.count, 1))
            return max(0.72, 0.92 - extraPenalty * 0.35)
        }

        let maxDistance: Int
        switch longerCount {
        case 0...4:
            maxDistance = 1
        case 5...8:
            maxDistance = 2
        default:
            maxDistance = 3
        }

        let distance = levenshteinDistance(answer, candidate, maxDistance: maxDistance)
        guard distance <= maxDistance else { return 0 }
        let similarity = 1 - (Double(distance) / Double(longerCount))
        let prefixBonus = min(Double(prefixLength) / Double(max(shorterCount, 1)), 1) * 0.08
        return min(similarity + prefixBonus, 0.99)
    }

    func leagueTokenPrefixSimilarity(answer: String, candidate: String) -> Double? {
        let answerTokens = answer.split(separator: " ").map(String.init)
        let candidateTokens = candidate.split(separator: " ").map(String.init)
        guard answerTokens.count > 1, candidateTokens.count >= answerTokens.count else { return nil }

        guard answerTokens.first == candidateTokens.first else { return nil }

        var tokenScores: [Double] = []
        for index in answerTokens.indices {
            let answerToken = answerTokens[index]
            let candidateToken = candidateTokens[index]

            if candidateToken.hasPrefix(answerToken) {
                tokenScores.append(1)
                continue
            }

            guard answerToken.count >= 3 else { return 0 }
            let candidatePrefix = String(candidateToken.prefix(answerToken.count))
            let allowedDistance = answerToken.count >= 4 ? 2 : 1
            let distance = levenshteinDistance(answerToken, candidatePrefix, maxDistance: allowedDistance)
            guard distance <= allowedDistance || hasSameLetters(answerToken, candidatePrefix) else { return 0 }

            let score = hasSameLetters(answerToken, candidatePrefix)
                ? 0.78
                : 1 - (Double(distance) / Double(max(answerToken.count, candidatePrefix.count)))
            guard score >= 0.62 else { return 0 }
            tokenScores.append(score)
        }

        let averageTokenScore = tokenScores.reduce(0, +) / Double(tokenScores.count)
        let completeness = Double(answer.count) / Double(candidate.count)
        return min(0.98, 0.84 + averageTokenScore * 0.08 + completeness * 0.08)
    }

    func hasSameLetters(_ first: String, _ second: String) -> Bool {
        first.count == second.count && first.sorted() == second.sorted()
    }

    func commonPrefixLength(_ first: String, _ second: String) -> Int {
        var count = 0
        for (left, right) in zip(first, second) {
            guard left == right else { break }
            count += 1
        }
        return count
    }

    func levenshteinDistance(_ first: String, _ second: String, maxDistance: Int) -> Int {
        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        guard !firstCharacters.isEmpty else { return secondCharacters.count }
        guard !secondCharacters.isEmpty else { return firstCharacters.count }
        if abs(firstCharacters.count - secondCharacters.count) > maxDistance {
            return maxDistance + 1
        }

        var previous = Array(0...secondCharacters.count)
        var current = Array(repeating: 0, count: secondCharacters.count + 1)

        for firstIndex in 1...firstCharacters.count {
            current[0] = firstIndex
            var rowMinimum = current[0]

            for secondIndex in 1...secondCharacters.count {
                let cost = firstCharacters[firstIndex - 1] == secondCharacters[secondIndex - 1] ? 0 : 1
                current[secondIndex] = min(
                    previous[secondIndex] + 1,
                    current[secondIndex - 1] + 1,
                    previous[secondIndex - 1] + cost
                )
                rowMinimum = min(rowMinimum, current[secondIndex])
            }

            if rowMinimum > maxDistance {
                return maxDistance + 1
            }

            swap(&previous, &current)
        }

        return previous[secondCharacters.count]
    }

    func normalizedLeagueAnswer(_ value: String) -> String {
        let stableLocale = Locale(identifier: "en_US_POSIX")
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: stableLocale)
            .lowercased(with: stableLocale)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "ʻ", with: "")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

}
