import SwiftUI
import Foundation

// MARK: - Mini World Cup Logic

extension ContentView {
    var miniWorldCupCurrentPlayer: MiniWorldCupPlayer? {
        guard !miniWorldCupActivePlayers.isEmpty else { return nil }
        let index = min(max(miniWorldCupCurrentPlayerIndex, 0), miniWorldCupActivePlayers.count - 1)
        return miniWorldCupActivePlayers[index]
    }

    var miniWorldCupHasHandoffOutcome: Bool {
        miniWorldCupAdvancePopupText != nil || miniWorldCupEliminationPopupText != nil
    }

    var miniWorldCupHandoffTint: Color {
        if miniWorldCupAdvancePopupText != nil { return .green }
        if miniWorldCupEliminationPopupText != nil { return .red }
        return tealAccentColor
    }

    var miniWorldCupHandoffTitle: String {
        miniWorldCupAdvancePopupText ?? miniWorldCupEliminationPopupText ?? L("Handy weitergeben", "Pass the phone")
    }

    var miniWorldCupHandoffSubtitle: String {
        miniWorldCupHasHandoffOutcome ? L("Handy weitergeben an", "Pass the phone to") : L("Gib das Handy an", "Give the phone to")
    }

    var miniWorldCupIsInSuddenDeathRange: Bool {
        miniWorldCupSuddenDeathEnabled && miniWorldCupActivePlayers.count <= miniWorldCupSuddenDeathThreshold
    }

    var miniWorldCupEffectiveFlagCount: Int {
        miniWorldCupIsInSuddenDeathRange ? 1 : miniWorldCupFlagsPerPlayer
    }

    var miniWorldCupEffectiveRequiredCorrect: Int {
        min(miniWorldCupRequiredCorrect, miniWorldCupEffectiveFlagCount)
    }

    var miniWorldCupTurnRuleText: String {
        let rule = L("\(miniWorldCupEffectiveFlagCount) Flagge(n), \(miniWorldCupEffectiveRequiredCorrect) richtig zum Weiterkommen", "\(miniWorldCupEffectiveFlagCount) flag(s), \(miniWorldCupEffectiveRequiredCorrect) correct to advance")
        return miniWorldCupIsInSuddenDeathRange ? "Sudden Death · \(rule)" : rule
    }

    var miniWorldCupQuestionProgressText: String {
        L("Flagge \(miniWorldCupCurrentAttempt)/\(miniWorldCupEffectiveFlagCount) · \(miniWorldCupCurrentCorrect) richtig", "Flag \(miniWorldCupCurrentAttempt)/\(miniWorldCupEffectiveFlagCount) · \(miniWorldCupCurrentCorrect) correct")
    }

    var miniWorldCupCorrectNeeded: Int {
        max(miniWorldCupEffectiveRequiredCorrect - miniWorldCupCurrentCorrect, 0)
    }

    var miniWorldCupRemainingAttemptsIncludingCurrent: Int {
        max(miniWorldCupEffectiveFlagCount - miniWorldCupCurrentAttempt + 1, 0)
    }

    var miniWorldCupMustKnowNextFlag: Bool {
        miniWorldCupCorrectNeeded > 0 && miniWorldCupCorrectNeeded == miniWorldCupRemainingAttemptsIncludingCurrent
    }

    var miniWorldCupTurnStatusColor: Color {
        if miniWorldCupMustKnowNextFlag { return .orange }
        if miniWorldCupCorrectNeeded == 0 { return .green }
        return tealAccentColor
    }

    var miniWorldCupTurnStatusTitle: String {
        if miniWorldCupCorrectNeeded == 0 {
            return L("Weiterkommen gesichert", "Advance secured")
        }
        if miniWorldCupMustKnowNextFlag {
            return L("Nächste Flagge muss sitzen", "Next flag must be correct")
        }
        return L("Noch alles drin", "Still possible")
    }

    var miniWorldCupTurnStatusSubtitle: String {
        if miniWorldCupCorrectNeeded == 0 {
            return L("Du kannst diese Runde nicht mehr rausfliegen.", "You cannot be eliminated this turn anymore.")
        }
        return L("Noch \(miniWorldCupCorrectNeeded) richtige bei \(miniWorldCupRemainingAttemptsIncludingCurrent) Flagge(n).", "Need \(miniWorldCupCorrectNeeded) more correct with \(miniWorldCupRemainingAttemptsIncludingCurrent) flag(s).")
    }

    var miniWorldCupCanStillAdvanceText: String {
        if miniWorldCupCorrectNeeded == 0 { return L("geschafft", "secured") }
        if miniWorldCupMustKnowNextFlag { return L("Pflichttreffer", "must hit") }
        return L("machbar", "possible")
    }

    func miniWorldCupHistoryMark(for index: Int) -> PracticeHistoryMark {
        if index < miniWorldCupCurrentAttemptResults.count {
            return miniWorldCupCurrentAttemptResults[index] ? .known : .unknown
        }
        return .pending
    }

    var miniWorldCupDangerShakeOffset: CGFloat {
        if miniWorldCupMustKnowNextFlag && miniWorldCupAnswerFeedback == nil {
            return miniWorldCupMustKnowPulse ? 14 : -14
        }
        return miniWorldCupDangerShakeTrigger.isMultiple(of: 2) ? 0 : -9
    }

    var miniWorldCupSwipeColor: Color {
        if miniWorldCupCardDragOffset.width > 24 { return .green }
        if miniWorldCupCardDragOffset.width < -24 { return .red }
        if miniWorldCupMustKnowNextFlag { return .orange }
        return tealAccentColor
    }

    func addMiniWorldCupPlayer() {
        let name = miniWorldCupNewPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !miniWorldCupPlayers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            miniWorldCupNewPlayerName = ""
            return
        }
        miniWorldCupPlayers.append(MiniWorldCupPlayer(name: name))
        miniWorldCupNewPlayerName = ""
        Task { @MainActor in
            isMiniWorldCupNameFocused = true
        }
    }

    func startMiniWorldCup() {
        guard miniWorldCupPlayers.count >= 2 else { return }
        guard consumeFreeDailyPartyModeRunIfAllowed() else { return }

        miniWorldCupAnswerTask?.cancel()
        miniWorldCupAnswerTask = nil
        miniWorldCupActivePlayers = miniWorldCupPlayers
        miniWorldCupEliminations = []
        miniWorldCupRoundResults = []
        miniWorldCupCompletedPlayerIDsInRound = []
        miniWorldCupCurrentPlayerIndex = 0
        miniWorldCupRound = 1
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCurrentAttemptResults = []
        miniWorldCupRecentCountryCodes = []
        miniWorldCupDeckCountryCodes = []
        miniWorldCupUndoSnapshot = nil
        miniWorldCupSuddenDeathIsActive = miniWorldCupIsInSuddenDeathRange
        miniWorldCupSuddenDeathAnnouncementVisible = false
        miniWorldCupAdvancePopupText = nil
        miniWorldCupEliminationPopupText = nil
        resetMiniWorldCupCardState()
        miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .handoff
        }
    }

    func resetMiniWorldCupToSetup(keepPlayers: Bool) {
        miniWorldCupAnswerTask?.cancel()
        miniWorldCupAnswerTask = nil
        if !keepPlayers {
            miniWorldCupPlayers = []
        }
        miniWorldCupActivePlayers = []
        miniWorldCupEliminations = []
        miniWorldCupRoundResults = []
        miniWorldCupCompletedPlayerIDsInRound = []
        miniWorldCupCurrentPlayerIndex = 0
        miniWorldCupRound = 1
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCurrentAttemptResults = []
        miniWorldCupRecentCountryCodes = []
        miniWorldCupDeckCountryCodes = []
        miniWorldCupUndoSnapshot = nil
        miniWorldCupSuddenDeathIsActive = false
        miniWorldCupSuddenDeathAnnouncementVisible = false
        miniWorldCupAdvancePopupText = nil
        miniWorldCupEliminationPopupText = nil
        resetMiniWorldCupCardState()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .setup
        }
    }

    func nextMiniWorldCupCountry() -> Country {
        let countries = availableCountries.isEmpty ? allCountries : availableCountries
        if miniWorldCupDeckCountryCodes.isEmpty {
            miniWorldCupDeckCountryCodes = countries.map(\.code).shuffled()
        }

        let recentLimit = min(6, max(2, countries.count / 4))
        let recentCodes = Set(miniWorldCupRecentCountryCodes.suffix(recentLimit))
        let nextCode = miniWorldCupDeckCountryCodes.first { !recentCodes.contains($0) }
            ?? miniWorldCupDeckCountryCodes.first
            ?? countries.randomElement()?.code
        guard let nextCode, let country = countries.first(where: { $0.code == nextCode }) ?? allCountries.first(where: { $0.code == nextCode }) else {
            return allCountries[0]
        }

        miniWorldCupDeckCountryCodes.removeAll { $0 == nextCode }
        miniWorldCupRecentCountryCodes.append(nextCode)
        if miniWorldCupRecentCountryCodes.count > 12 {
            miniWorldCupRecentCountryCodes.removeFirst(miniWorldCupRecentCountryCodes.count - 12)
        }
        return country
    }

    func resetMiniWorldCupCardState() {
        miniWorldCupCardIsFlipped = false
        miniWorldCupCardWasRevealed = false
        miniWorldCupCardEntryOffset = 0
        miniWorldCupCardEntryOpacity = 1
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
    }

    func presentMiniWorldCupQuestion() {
        miniWorldCupAdvancePopupText = nil
        miniWorldCupEliminationPopupText = nil
        miniWorldCupCardIsFlipped = false
        miniWorldCupCardWasRevealed = false
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
        miniWorldCupCardEntryOffset = -34
        miniWorldCupCardEntryOpacity = 0

        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .question
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                miniWorldCupCardEntryOffset = 0
                miniWorldCupCardEntryOpacity = 1
            }
        }
    }

    func revealMiniWorldCupCard() {
        guard miniWorldCupPhase == .question, miniWorldCupAnswerFeedback == nil else { return }
        Haptics.tap()
        miniWorldCupCardWasRevealed = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            miniWorldCupCardIsFlipped.toggle()
        }
    }

    func saveMiniWorldCupUndoSnapshotIfNeeded() {
        guard miniWorldCupCurrentAttempt == 1 else { return }
        miniWorldCupUndoSnapshot = MiniWorldCupUndoSnapshot(
            appData: appData,
            activePlayers: miniWorldCupActivePlayers,
            completedPlayerIDsInRound: miniWorldCupCompletedPlayerIDsInRound,
            eliminations: miniWorldCupEliminations,
            roundResults: miniWorldCupRoundResults,
            phase: miniWorldCupPhase,
            currentPlayerIndex: miniWorldCupCurrentPlayerIndex,
            currentCountry: miniWorldCupCurrentCountry,
            round: miniWorldCupRound,
            currentAttempt: miniWorldCupCurrentAttempt,
            currentCorrect: miniWorldCupCurrentCorrect,
            currentAttemptResults: miniWorldCupCurrentAttemptResults,
            cardIsFlipped: miniWorldCupCardIsFlipped,
            cardWasRevealed: miniWorldCupCardWasRevealed,
            recentCountryCodes: miniWorldCupRecentCountryCodes,
            deckCountryCodes: miniWorldCupDeckCountryCodes,
            suddenDeathIsActive: miniWorldCupSuddenDeathIsActive
        )
    }

    func undoMiniWorldCupTurn() {
        guard let snapshot = miniWorldCupUndoSnapshot else { return }
        appData = snapshot.appData
        saveLocalCache()
        miniWorldCupActivePlayers = snapshot.activePlayers
        miniWorldCupCompletedPlayerIDsInRound = snapshot.completedPlayerIDsInRound
        miniWorldCupEliminations = snapshot.eliminations
        miniWorldCupRoundResults = snapshot.roundResults
        miniWorldCupPhase = snapshot.phase
        miniWorldCupCurrentPlayerIndex = snapshot.currentPlayerIndex
        miniWorldCupCurrentCountry = snapshot.currentCountry
        miniWorldCupRound = snapshot.round
        miniWorldCupCurrentAttempt = snapshot.currentAttempt
        miniWorldCupCurrentCorrect = snapshot.currentCorrect
        miniWorldCupCurrentAttemptResults = snapshot.currentAttemptResults
        miniWorldCupCardIsFlipped = snapshot.cardIsFlipped
        miniWorldCupCardWasRevealed = snapshot.cardWasRevealed
        miniWorldCupRecentCountryCodes = snapshot.recentCountryCodes
        miniWorldCupDeckCountryCodes = snapshot.deckCountryCodes
        miniWorldCupSuddenDeathIsActive = snapshot.suddenDeathIsActive
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
        miniWorldCupAdvancePopupText = nil
        miniWorldCupEliminationPopupText = nil
        miniWorldCupSuddenDeathAnnouncementVisible = false
        miniWorldCupUndoSnapshot = nil
    }

    func finishMiniWorldCupSwipe(width: CGFloat) {
        let threshold: CGFloat = 82
        guard abs(width) >= threshold else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                miniWorldCupCardDragOffset = .zero
            }
            return
        }

        handleMiniWorldCupAnswer(known: width > 0)
    }

    func handleMiniWorldCupAnswer(known: Bool) {
        guard miniWorldCupPhase == .question, !miniWorldCupActivePlayers.isEmpty, miniWorldCupAnswerFeedback == nil else { return }
        saveMiniWorldCupUndoSnapshotIfNeeded()
        let countsAsKnown = known && !miniWorldCupCardWasRevealed
        Haptics.tap(style: countsAsKnown ? .medium : .light)
        miniWorldCupAnswerFeedback = countsAsKnown
        if !countsAsKnown {
            miniWorldCupDangerShakeTrigger += 1
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            miniWorldCupCardDragOffset = CGSize(width: countsAsKnown ? 620 : -620, height: 0)
        }

        miniWorldCupAnswerTask?.cancel()
        miniWorldCupAnswerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  miniWorldCupPhase == .question,
                  miniWorldCupAnswerFeedback == countsAsKnown else { return }
            finishMiniWorldCupAttempt(known: countsAsKnown)
            miniWorldCupAnswerTask = nil
        }
    }

    func finishMiniWorldCupAttempt(known: Bool) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        let updatedCorrect = miniWorldCupCurrentCorrect + (known ? 1 : 0)
        let updatedAttemptResults = miniWorldCupCurrentAttemptResults + [known]
        let flagCount = miniWorldCupEffectiveFlagCount
        let requiredCorrect = miniWorldCupEffectiveRequiredCorrect
        let remainingAfterThisAttempt = max(flagCount - miniWorldCupCurrentAttempt, 0)
        let canStillAdvance = updatedCorrect + remainingAfterThisAttempt >= requiredCorrect
        miniWorldCupCurrentAttemptResults = updatedAttemptResults

        if !canStillAdvance {
            showMiniWorldCupEliminationPopup(correctCount: updatedCorrect, flagCount: flagCount)
            return
        }

        if miniWorldCupCurrentAttempt >= flagCount {
            if updatedCorrect >= requiredCorrect {
                advanceMiniWorldCupCurrentPlayer(correctCount: updatedCorrect, flagCount: flagCount)
            } else {
                showMiniWorldCupEliminationPopup(correctCount: updatedCorrect, flagCount: flagCount)
            }
        } else {
            miniWorldCupCurrentCorrect = updatedCorrect
            miniWorldCupCurrentAttempt += 1
            miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
            miniWorldCupCardIsFlipped = false
            miniWorldCupCardWasRevealed = false
            miniWorldCupCardDragOffset = .zero
            miniWorldCupAnswerFeedback = nil
            miniWorldCupCardEntryOffset = -34
            miniWorldCupCardEntryOpacity = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    miniWorldCupCardEntryOffset = 0
                    miniWorldCupCardEntryOpacity = 1
                }
            }
        }
    }

    func advanceMiniWorldCupCurrentPlayer(correctCount: Int, flagCount: Int) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        let safeIndex = min(max(miniWorldCupCurrentPlayerIndex, 0), miniWorldCupActivePlayers.count - 1)
        let player = miniWorldCupActivePlayers[safeIndex]
        miniWorldCupRoundResults.append(
            MiniWorldCupRoundResult(
                playerName: player.name,
                country: miniWorldCupCurrentCountry,
                round: miniWorldCupRound,
                correctCount: correctCount,
                flagCount: flagCount,
                didAdvance: true
            )
        )
        miniWorldCupCurrentCorrect = correctCount
        miniWorldCupAdvancePopupText = L("\(player.name) ist weiter", "\(player.name) advances")
        miniWorldCupEliminationPopupText = nil
        miniWorldCupCompletedPlayerIDsInRound.insert(player.id)
        miniWorldCupCurrentPlayerIndex = (safeIndex + 1) % miniWorldCupActivePlayers.count
        prepareNextMiniWorldCupTurn()
    }

    func showMiniWorldCupEliminationPopup(correctCount: Int, flagCount: Int) {
        miniWorldCupEliminationPopupText = L("\(miniWorldCupCurrentPlayer?.name ?? "-") ist raus", "\(miniWorldCupCurrentPlayer?.name ?? "-") is out")
        miniWorldCupAdvancePopupText = nil
        eliminateMiniWorldCupCurrentPlayer(correctCount: correctCount, flagCount: flagCount)
    }

    func eliminateMiniWorldCupCurrentPlayer(correctCount: Int, flagCount: Int) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        let safeIndex = min(max(miniWorldCupCurrentPlayerIndex, 0), miniWorldCupActivePlayers.count - 1)
        let eliminated = miniWorldCupActivePlayers.remove(at: safeIndex)
        miniWorldCupRoundResults.append(
            MiniWorldCupRoundResult(
                playerName: eliminated.name,
                country: miniWorldCupCurrentCountry,
                round: miniWorldCupRound,
                correctCount: correctCount,
                flagCount: flagCount,
                didAdvance: false
            )
        )
        miniWorldCupEliminations.insert(
            MiniWorldCupElimination(
                playerName: eliminated.name,
                country: miniWorldCupCurrentCountry,
                round: miniWorldCupRound,
                correctCount: correctCount,
                flagCount: flagCount
            ),
            at: 0
        )
        miniWorldCupCompletedPlayerIDsInRound.insert(eliminated.id)

        if miniWorldCupActivePlayers.count <= 1 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                miniWorldCupPhase = .finished
                miniWorldCupCardDragOffset = .zero
            }
            return
        }

        miniWorldCupCurrentPlayerIndex = safeIndex % miniWorldCupActivePlayers.count
        prepareNextMiniWorldCupTurn()
    }

    func prepareNextMiniWorldCupTurn() {
        updateActiveProfile { profile in
            profile.recordPartyRound()
        }
        // An eliminated first player also makes the next player index zero.
        // Track completed turns by player identity, not by the array index, so
        // a round advances only after every remaining player had their turn.
        if miniWorldCupActivePlayers.allSatisfy({ miniWorldCupCompletedPlayerIDsInRound.contains($0.id) }) {
            miniWorldCupRound += 1
            miniWorldCupCompletedPlayerIDsInRound.removeAll()
        }
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCurrentAttemptResults = []
        let shouldEnterSuddenDeath = miniWorldCupIsInSuddenDeathRange && !miniWorldCupSuddenDeathIsActive
        miniWorldCupSuddenDeathIsActive = miniWorldCupIsInSuddenDeathRange
        miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
        resetMiniWorldCupCardState()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .handoff
        }
        if shouldEnterSuddenDeath {
            showMiniWorldCupSuddenDeathAnnouncement()
        }
    }

    func showMiniWorldCupSuddenDeathAnnouncement() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            miniWorldCupSuddenDeathAnnouncementVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeOut(duration: 0.2)) {
                miniWorldCupSuddenDeathAnnouncementVisible = false
            }
        }
    }

    func finishStudyCardSwipe(
        translation: CGSize,
        predictedTranslation: CGSize,
        dragOffset: Binding<CGFloat>,
        isFinishingSwipe: Binding<Bool>,
        knownSwipeIsBlocked: Bool,
        onKnownBlocked: @escaping () -> Void,
        onComplete: @escaping (Bool) -> Void
    ) {
        guard !isFinishingSwipe.wrappedValue else { return }
        let threshold: CGFloat = 72
        let committedWidth = abs(predictedTranslation.width) > abs(translation.width) ? predictedTranslation.width : translation.width
        let isMostlyHorizontal = abs(committedWidth) > abs(translation.height) * 1.15

        guard isMostlyHorizontal, abs(committedWidth) >= threshold else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                dragOffset.wrappedValue = 0
            }
            return
        }

        let isKnown = committedWidth > 0
        if isKnown && knownSwipeIsBlocked {
            onKnownBlocked()
            return
        }

        Haptics.tap(style: .medium)
        isFinishingSwipe.wrappedValue = true
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 24)) {
            dragOffset.wrappedValue = isKnown ? 620 : -620
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onComplete(isKnown)
        }
    }

    func finishPracticeSwipe(translation: CGSize, predictedTranslation: CGSize) {
        finishStudyCardSwipe(
            translation: translation,
            predictedTranslation: predictedTranslation,
            dragOffset: $practiceCardDragOffset,
            isFinishingSwipe: $isFinishingPracticeSwipe,
            knownSwipeIsBlocked: currentCardUsedHint,
            onKnownBlocked: showHintKnownBlockedFeedback,
            onComplete: { isKnown in recordPracticeCard(isKnown: isKnown) }
        )
    }

    func finishShowSwipe(translation: CGSize, predictedTranslation: CGSize) {
        finishStudyCardSwipe(
            translation: translation,
            predictedTranslation: predictedTranslation,
            dragOffset: $showCardDragOffset,
            isFinishingSwipe: $isFinishingShowSwipe,
            knownSwipeIsBlocked: currentCardUsedHint,
            onKnownBlocked: { showHintKnownBlockedFeedback(dragOffset: $showCardDragOffset) },
            onComplete: { isKnown in recordShowCard(isKnown: isKnown) }
        )
    }
}
