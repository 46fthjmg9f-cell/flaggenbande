import SwiftUI

// MARK: - Mini World Cup Views

extension ContentView {
    var miniWorldCupView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    modeHeader(title: L("Partymodus Beta", "Party Mode Beta"), subtitle: L("Handy weitergeben, Flagge wischen, bis nur noch eine Person übrig ist.", "Pass the phone, swipe the flag, until one person remains."))

                    switch miniWorldCupPhase {
                    case .setup:
                        miniWorldCupSetupView
                    case .handoff:
                        miniWorldCupControlsView
                        miniWorldCupIntermediateResultsView
                        miniWorldCupHandoffView
                    case .question:
                        miniWorldCupControlsView
                        miniWorldCupIntermediateResultsView
                        miniWorldCupQuestionView
                    case .finished:
                        miniWorldCupResultView
                    }
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.vertical, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }

            if miniWorldCupSuddenDeathAnnouncementVisible {
                miniWorldCupToast(icon: "bolt.fill", title: "Sudden Death", tint: .orange)
                    .padding(.horizontal, 22)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                    .zIndex(2)
            }

        }
        .navigationTitle(L("Partymodus Beta", "Party Mode Beta"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if miniWorldCupPhase == .handoff || miniWorldCupPhase == .question {
                miniWorldCupCurrentPlayerBottomBar
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
        }
    }

    var miniWorldCupCurrentPlayerBottomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(miniWorldCupHandoffTint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Dran", "Turn"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(miniWorldCupCurrentPlayer?.name ?? "-")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            Text("\(miniWorldCupActivePlayers.count)")
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(miniWorldCupHandoffTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(miniWorldCupHandoffTint.opacity(0.28), lineWidth: 1)
        )
    }

    func miniWorldCupToast(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 420)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.18), radius: 18, y: 8)
    }

    var miniWorldCupSetupView: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label(L("Spieler im Uhrzeigersinn", "Players clockwise"), systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline)

                HStack(spacing: 10) {
                    TextField(L("Name", "Name"), text: $miniWorldCupNewPlayerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($isMiniWorldCupNameFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .onSubmit { addMiniWorldCupPlayer() }

                    Button {
                        Haptics.tap()
                        addMiniWorldCupPlayer()
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tealAccentColor)
                }

                if miniWorldCupPlayers.isEmpty {
                    Text(L("Füge mindestens zwei Personen in Sitzreihenfolge hinzu.", "Add at least two people in seating order."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(miniWorldCupPlayers.enumerated()), id: \.element.id) { index, player in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(tealAccentColor, in: Circle())
                                Text(player.name)
                                    .font(.headline)
                                Spacer()
                                Button {
                                    Haptics.tap()
                                    miniWorldCupPlayers.removeAll { $0.id == player.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: AppLayout.controlRadius, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .appSurface()

            miniWorldCupRulesView

            if !fullVersionUnlocked {
                freeDailyGameModeLimitInfo(title: L("Partymodus", "Party Mode"), remaining: freeDailyPartyModeRunsRemaining, total: FreeVersionLimits.dailyPartyModeRounds)
            }

            Button {
                Haptics.tap()
                startMiniWorldCup()
            } label: {
                Label(L("Partymodus starten", "Start party mode"), systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            .disabled(miniWorldCupPlayers.count < 2)
        }
    }

    var miniWorldCupRulesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Rundenregeln", "Round rules"), systemImage: "slider.horizontal.3")
                .font(.headline)

            Stepper(value: $miniWorldCupFlagsPerPlayer, in: 1...5) {
                HStack {
                    Text(L("Flaggen pro Person", "Flags per person"))
                    Spacer()
                    Text("\(miniWorldCupFlagsPerPlayer)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(tealAccentColor)
                }
            }
            .onChange(of: miniWorldCupFlagsPerPlayer) { _, newValue in
                miniWorldCupRequiredCorrect = min(miniWorldCupRequiredCorrect, newValue)
            }

            Stepper(value: $miniWorldCupRequiredCorrect, in: 1...miniWorldCupFlagsPerPlayer) {
                HStack {
                    Text(L("Muss richtig sein", "Needed correct"))
                    Spacer()
                    Text("\(miniWorldCupRequiredCorrect)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(tealAccentColor)
                }
            }

            Toggle(isOn: $miniWorldCupSuddenDeathEnabled) {
                Text("Sudden Death")
            }
            .toggleStyle(.switch)

            if miniWorldCupSuddenDeathEnabled {
                Stepper(value: $miniWorldCupSuddenDeathThreshold, in: 2...12) {
                    HStack {
                        Text(L("Sudden Death ab", "Sudden Death at"))
                        Spacer()
                        Text("\(miniWorldCupSuddenDeathThreshold)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tealAccentColor)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .appSurface()
    }

    var miniWorldCupTurnStatusView: some View {
        HStack(spacing: 10) {
            Image(systemName: miniWorldCupMustKnowNextFlag ? "exclamationmark.triangle.fill" : "scope")
                .font(.headline.weight(.bold))
                .foregroundStyle(miniWorldCupTurnStatusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(miniWorldCupTurnStatusTitle)
                    .font(.subheadline.weight(.bold))
                Text(miniWorldCupTurnStatusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(miniWorldCupTurnStatusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(miniWorldCupTurnStatusColor.opacity(miniWorldCupMustKnowNextFlag ? 0.55 : 0.24), lineWidth: miniWorldCupMustKnowNextFlag ? 2 : 1)
        )
        .scaleEffect(miniWorldCupMustKnowNextFlag && miniWorldCupMustKnowPulse ? 1.018 : 1)
        .animation(.easeInOut(duration: 0.48), value: miniWorldCupMustKnowPulse)
        .onChange(of: miniWorldCupMustKnowNextFlag) { _, mustKnow in
            guard mustKnow else {
                miniWorldCupMustKnowPulse = false
                return
            }
            withAnimation(.easeInOut(duration: 0.48).repeatForever(autoreverses: true)) {
                miniWorldCupMustKnowPulse.toggle()
            }
        }
    }

    var miniWorldCupAttemptReviewView: some View {
        HStack(spacing: 7) {
            ForEach(0..<miniWorldCupEffectiveFlagCount, id: \.self) { index in
                let mark = miniWorldCupHistoryMark(for: index)
                PracticeHistoryPill(
                    mark: mark,
                    accentColor: miniWorldCupMustKnowNextFlag ? .orange : tealAccentColor,
                    isSelected: false,
                    animationTrigger: mark == .current ? miniWorldCupCurrentAttemptResults.count : 0
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((miniWorldCupMustKnowNextFlag ? Color.orange : tealAccentColor).opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.44, dampingFraction: 0.76), value: miniWorldCupCurrentAttemptResults)
    }

    var miniWorldCupIntermediateResultsView: some View {
        Group {
            if !miniWorldCupRoundResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Zwischenergebnis", "Interim result"), systemImage: "list.bullet.rectangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(miniWorldCupRoundResults.suffix(4)) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.didAdvance ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.didAdvance ? .green : .red)
                            Text(result.playerName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(result.didAdvance ? L("weiter", "next") : L("raus", "out"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(result.didAdvance ? .green : .red)
                        }
                    }
                }
                .padding(12)
                .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    var miniWorldCupControlsView: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                resetMiniWorldCupToSetup(keepPlayers: true)
            } label: {
                Label(L("Abbrechen", "Cancel"), systemImage: "xmark")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(ActionButtonStyle(color: .secondary))

            Button {
                Haptics.tap()
                undoMiniWorldCupTurn()
            } label: {
                Label(L("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            .disabled(miniWorldCupUndoSnapshot == nil)
        }
    }

    var miniWorldCupHandoffView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(tealAccentColor)
                .padding(.top, 4)

            Text(miniWorldCupHandoffTitle)
                .font(.title.bold())
                .foregroundStyle(miniWorldCupHandoffTint)

            Text(miniWorldCupHandoffSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(miniWorldCupCurrentPlayer?.name ?? "-")
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            VStack(spacing: 4) {
                Text(L("Die Flagge wird erst nach OK angezeigt.", "The flag appears only after OK."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(miniWorldCupTurnRuleText)
                    .font(.caption)
                    .foregroundStyle(tealAccentColor)
            }

            Button {
                Haptics.tap()
                presentMiniWorldCupQuestion()
            } label: {
                Label(L("OK, ich habe das Handy", "OK, I have the phone"), systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
        .padding(18)
        .background(miniWorldCupHandoffTint.opacity(miniWorldCupHasHandoffOutcome ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 12))
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(miniWorldCupHandoffTint.opacity(miniWorldCupHasHandoffOutcome ? 0.38 : 0.16), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    var miniWorldCupQuestionView: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(miniWorldCupCurrentPlayer?.name ?? "-")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Text("\(miniWorldCupActivePlayers.count)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tealAccentColor, in: Circle())
            }

            miniWorldCupAttemptReviewView

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(miniWorldCupSwipeColor.opacity(min(abs(miniWorldCupCardDragOffset.width) / 130, 0.24)))
                    .frame(height: 260)
                    .overlay(alignment: miniWorldCupCardDragOffset.width >= 0 ? .leading : .trailing) {
                        Image(systemName: miniWorldCupCardDragOffset.width >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(miniWorldCupCardDragOffset.width >= 0 ? .green : .red)
                            .opacity(min(abs(miniWorldCupCardDragOffset.width) / 130, 1))
                            .padding(.horizontal, 26)
                    }

                FlipCard(
                    country: miniWorldCupCurrentCountry,
                    isFlipped: miniWorldCupCardIsFlipped,
                    hasGoldAura: false,
                    language: appLanguage,
                    subject: selectedSubject,
                    capital: capitalName(for: miniWorldCupCurrentCountry)
                )
                .id(miniWorldCupCurrentCountry.id)
                .offset(
                    x: miniWorldCupCardDragOffset.width + miniWorldCupDangerShakeOffset,
                    y: miniWorldCupCardEntryOffset + miniWorldCupCardDragOffset.height * 0.15
                )
                .opacity((miniWorldCupAnswerFeedback == nil ? 1 : 0.82) * miniWorldCupCardEntryOpacity)
                .scaleEffect((miniWorldCupCardEntryOpacity < 1 ? 0.985 : 1) * (miniWorldCupMustKnowNextFlag && miniWorldCupMustKnowPulse ? 1.035 : 1))
                .rotationEffect(.degrees(Double(miniWorldCupCardDragOffset.width / 18)))
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: miniWorldCupCurrentCountry.id)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: miniWorldCupCardEntryOffset)
                .animation(.easeOut(duration: 0.2), value: miniWorldCupCardEntryOpacity)
                .animation(.interpolatingSpring(stiffness: 360, damping: 8), value: miniWorldCupDangerShakeTrigger)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard miniWorldCupAnswerFeedback == nil else { return }
                            guard !FlagZoomInteractionState.isPinching else {
                                miniWorldCupCardDragOffset = .zero
                                return
                            }
                            miniWorldCupCardDragOffset = value.translation
                        }
                        .onEnded { value in
                            guard miniWorldCupAnswerFeedback == nil && !FlagZoomInteractionState.isPinching else {
                                miniWorldCupCardDragOffset = .zero
                                return
                            }
                            finishMiniWorldCupSwipe(width: value.predictedEndTranslation.width)
                        }
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                guard !FlagZoomInteractionState.isPinching else { return }
                revealMiniWorldCupCard()
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(miniWorldCupSwipeColor.opacity(0.42), lineWidth: abs(miniWorldCupCardDragOffset.width) > 8 ? 3 : 1)
            )

            Text(L("Wischen!", "Swipe!"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onChange(of: miniWorldCupMustKnowNextFlag) { _, mustKnow in
            guard mustKnow else {
                miniWorldCupMustKnowPulse = false
                return
            }
            withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                miniWorldCupMustKnowPulse.toggle()
            }
        }
        .onAppear {
            if miniWorldCupMustKnowNextFlag {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                    miniWorldCupMustKnowPulse.toggle()
                }
            }
        }
    }

    var miniWorldCupResultView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(L("Gewinner", "Winner"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(miniWorldCupActivePlayers.first?.name ?? "-")
                    .font(.largeTitle.weight(.black))
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))

            miniWorldCupBracketView

            Button {
                Haptics.tap()
                resetMiniWorldCupToSetup(keepPlayers: true)
            } label: {
                Label(L("Neuer Partymodus", "New party mode"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
    }

    var miniWorldCupBracketView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Turnierbaum", "Tournament bracket"), systemImage: "list.bullet.rectangle.fill")
                .font(.headline)

            ForEach(miniWorldCupResultRoundKeys, id: \.self) { round in
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Runde \(round)", "Round \(round)"))
                        .font(.subheadline.weight(.bold))

                    ForEach(miniWorldCupResults(forRound: round)) { result in
                        miniWorldCupResultRow(result)
                    }
                }
                .padding(10)
                .background(tealAccentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if let winner = miniWorldCupActivePlayers.first {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(winner.name)
                            .font(.headline)
                        Text(L("Gewinner", "Winner"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }

    func miniWorldCupResultRow(_ result: MiniWorldCupRoundResult) -> some View {
        let tint: Color = result.didAdvance ? .green : .red
        return HStack(spacing: 10) {
            Image(systemName: result.didAdvance ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.playerName)
                    .font(.headline)
                Text(L("\(result.correctCount)/\(result.flagCount) richtig", "\(result.correctCount)/\(result.flagCount) correct"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(localizedCountryName(result.country, language: appLanguage))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Spacer()
            FlagImage(country: result.country, width: 42, height: 28)
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    var miniWorldCupResultRoundKeys: [Int] {
        Array(Set(miniWorldCupRoundResults.map(\.round))).sorted()
    }

    func miniWorldCupResults(forRound round: Int) -> [MiniWorldCupRoundResult] {
        miniWorldCupRoundResults.filter { $0.round == round }
    }
}
