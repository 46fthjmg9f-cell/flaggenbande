import SwiftUI
import Foundation

extension ContentView {
    var leagueView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    modeHeader(title: runTitleWithBeta, subtitle: L("Highscore auf Zeit", "Timed high score"))

                    if leagueMatchActive {
                        leagueMatchCard
                    } else if leagueShowsStartMenu {
                        leagueStartMenuView
                    } else {
                        leagueSetupView
                    }
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(runTitleWithBeta)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if leagueMatchActive && leagueMatchPhase == .playing {
                leagueUnknownButton
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            guard onlineFeaturesEnabled else { return }
            try? await Task.sleep(for: .milliseconds(350))
            if !isGameCenterAuthenticated {
                authenticateGameCenter(syncAfterAuthentication: false)
            } else if gameCenterFriendIDs.isEmpty {
                await loadGameCenterFriends()
            }
            if onlineLeaderboard.isEmpty {
                await loadOnlineStats()
            }
        }
    }

    var leagueStartMenuView: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    leagueShowsStartMenu = false
                }
            } label: {
                Label(L("\(runTitle) starten", "Start \(runTitle)"), systemImage: "trophy.circle.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))

            leagueStatsCard

            flaggenrunLeaderboardCard

            leagueMatchHistoryCard
        }
    }

    func leagueSummaryOverlay(_ result: LeagueMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("Runde beendet", "Round complete"), systemImage: "flag.checkered")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(tealAccentColor)
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        leagueSummaryResult = nil
                        leagueShowsStartMenu = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                leagueMetricTile(title: L("Score", "Score"), value: "\(result.ownScore)")
                leagueMetricTile(title: L("Bestscore", "Best score"), value: "\(activeProfile.leagueStats?.bestScore ?? result.ownScore)")
            }

            Text(selectedSubject == .capitals ? L("\(result.correct) richtig · \(result.wrong) falsch · \(result.answerDetails?.count ?? result.totalAnswers) Hauptstädte", "\(result.correct) correct · \(result.wrong) wrong · \(result.answerDetails?.count ?? result.totalAnswers) capitals") : L("\(result.correct) richtig · \(result.wrong) falsch · \(result.answerDetails?.count ?? result.totalAnswers) Flaggen", "\(result.correct) correct · \(result.wrong) wrong · \(result.answerDetails?.count ?? result.totalAnswers) flags"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    leagueSummaryResult = nil
                    leagueShowsStartMenu = true
                }
            } label: {
                Label(L("Zurück zu \(runTitle)", "Back to \(runTitle)"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
        .padding(16)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var leagueSetupView: some View {
        VStack(spacing: 14) {
            leagueStartMatchButton
            leagueStatsCard
            leagueMatchHistoryCard
        }
    }

    var leagueStartMatchButton: some View {
        Button {
            Haptics.tap()
            Task { await startLeagueMatch() }
        } label: {
            Label(L("Match starten", "Start match"), systemImage: "play.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
    }

    var leagueUnknownButton: some View {
        let isEnabled = leagueTimerIsRunning && !leagueInputIsLocked
        return Button {
            guard isEnabled else { return }
            Haptics.notify(.warning)
            submitLeagueAnswer(forcedCorrectness: false, keepsTypedAnswer: false)
        } label: {
            Label(L("Weiß ich nicht", "I don't know"), systemImage: "questionmark.circle.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ActionButtonStyle(color: .orange, isProminent: false))
        .disabled(!isEnabled)
    }

    var leagueStatsCard: some View {
        let stats = activeProfile.leagueStats ?? LeagueStats()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(runTitle, systemImage: "bolt.trophy.fill")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Highscore", "High score"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tealAccentColor)
                    Text("\(stats.bestScore) \(L("Punkte", "points"))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                leagueMetricTile(title: L("Runden", "Rounds"), value: "\(stats.played)")
                leagueMetricTile(title: L("Bestscore", "Best score"), value: "\(stats.bestScore)")
                leagueMetricTile(title: L("Quote", "Rate"), value: percentText(stats.accuracy))
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    func leagueMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    var leagueMatchHistoryCard: some View {
        let matches = activeProfile.leagueStats?.recentMatches ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Match-History", "Match history"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(matches.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if matches.isEmpty {
                Text(selectedSubject == .capitals ? L("Noch keine Städteruns gespielt.", "No City Runs played yet.") : L("Noch keine Flaggenruns gespielt.", "No Flag Runs played yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(matches.prefix(5)) { match in
                        leagueHistoryRow(match)
                    }
                }
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var flaggenrunLeaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(selectedSubject == .capitals ? L("Globale Städterun-Bestenliste", "Global City Run leaderboard") : L("Globale Flaggenrun-Bestenliste", "Global Flag Run leaderboard"), systemImage: "globe.europe.africa.fill")
                    .font(.headline)
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await syncOnlineStats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!onlineFeaturesEnabled || isSyncingOnlineStats)
            }

            if !onlineFeaturesEnabled {
                Text(L("Onlinefunktionen sind ausgeschaltet.", "Online features are turned off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if onlineLeagueLeaderboard.isEmpty {
                Text(L("Noch keine globalen Highscores geladen.", "No global high scores loaded yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(onlineLeagueLeaderboard.prefix(8).enumerated()), id: \.element.id) { index, player in
                        LeagueLeaderboardRow(rank: index + 1, player: player, isCurrentPlayer: isCurrentOnlinePlayer(player), language: appLanguage)
                    }
                }
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .task {
            guard onlineFeaturesEnabled, onlineLeaderboard.isEmpty else { return }
            await loadOnlineStats()
        }
    }

    func leagueHistoryRow(_ match: LeagueMatchResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .foregroundStyle(tealAccentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Score \(match.ownScore)", "Score \(match.ownScore)"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(match.correct) \(L("richtig", "correct")) · \(match.wrong) \(L("falsch", "wrong"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    var leagueMatchCard: some View {
        VStack(spacing: 16) {
            if leagueMatchPhase == .loading || leagueMatchPhase == .countdown {
                leagueMatchPreparationView
            } else {
                leaguePlayableView
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            prepareLeagueTimerAfterLayout()
        }
        .onDisappear {
            leagueTimerStartTask?.cancel()
        }
    }

    var leagueMatchPreparationView: some View {
        VStack(spacing: 18) {
            Text(L("Lädt", "Loading"))
                .font(.headline)
                .foregroundStyle(.secondary)

            if leagueMatchPhase == .loading {
                ProgressView()
                    .tint(tealAccentColor)
            } else {
                Text("\(leagueStartCountdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tealAccentColor)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: leagueMatchPhase)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: leagueStartCountdown)
    }

    var leaguePlayableView: some View {
        VStack(spacing: 16) {
            HStack {
                Label(leagueTimerIsRunning ? "\(leagueSecondsRemaining)s" : L("Bereit", "Ready"), systemImage: "timer")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(leagueSecondsRemaining <= 10 ? .red : tealAccentColor)
                Spacer()
                Text("\(leagueScore)")
                    .font(.title2.monospacedDigit().weight(.bold))
            }

            ZStack {
                Group {
                    if let leaguePreloadedFlagImage {
                        Image(uiImage: leaguePreloadedFlagImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 170)
                    } else {
                        FlagImage(country: leagueCurrentCountry, width: 280, height: 170)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .opacity(leagueInputIsLocked ? 0.55 : 1)
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: leagueAnswerFeedback)
            .animation(.easeOut(duration: 0.16), value: leagueInputIsLocked)

            TextField(selectedSubject == .capitals ? L("Name der Hauptstadt", "Capital name") : L("Name der Flagge", "Flag name"), text: $leagueAnswerText)
                .focused($isLeagueAnswerFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { submitLeagueAnswer() }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tealAccentColor.opacity(0.32), lineWidth: 1)
                )
                .onChange(of: leagueAnswerText) { _, newValue in
                    guard !leagueInputIsLocked && Date() >= leagueTypingLockedUntil else {
                        if newValue != leagueLockedAnswerText {
                            leagueAnswerText = leagueLockedAnswerText
                        }
                        return
                    }
                    evaluateLeagueAnswer(newValue)
                }
                .allowsHitTesting(leagueTimerIsRunning && !leagueInputIsLocked)
                .opacity(leagueInputIsLocked ? 0.82 : 1)

            if let leagueAnswerFeedback {
                leagueFeedbackField(isCorrect: leagueAnswerFeedback)
            }

            HStack(spacing: 10) {
                leagueMetricTile(title: L("Richtig", "Correct"), value: "\(leagueCorrect)")
                leagueMetricTile(title: L("Falsch", "Wrong"), value: "\(leagueWrong)")
            }

            Button(role: .destructive) {
                Haptics.notify(.warning)
                finishLeagueMatch()
            } label: {
                Text(L("Runde beenden", "Finish round"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ActionButtonStyle(color: .red, isProminent: false))
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    func leagueFeedbackField(isCorrect: Bool) -> some View {
        Label(
            isCorrect ? L("Richtig: \(leagueRevealedCountryName)", "Correct: \(leagueRevealedCountryName)") : L("Falsch: \(leagueRevealedCountryName)", "Wrong: \(leagueRevealedCountryName)"),
            systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .font(.subheadline.weight(.bold))
        .foregroundStyle(isCorrect ? .green : .red)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background((isCorrect ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    var leagueRecognitionView: some View {
        HStack(spacing: 10) {
            if let match = leagueAnswerMatch {
                let isCurrentCountry = match.country == leagueCurrentCountry
                Image(systemName: isCurrentCountry ? (match.isCertain ? "checkmark.circle.fill" : "scope") : (match.isCertain ? "xmark.circle.fill" : "questionmark.circle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrentCountry ? tealAccentColor : (match.isCertain ? .red : .orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentCountry ? L("Erkannt: \(leagueExpectedAnswerName(for: match.country))", "Recognized: \(leagueExpectedAnswerName(for: match.country))") : L("Meintest du \(leagueExpectedAnswerName(for: match.country))?", "Did you mean \(leagueExpectedAnswerName(for: match.country))?"))
                        .font(.caption.weight(.semibold))
                    Text(match.isCertain ? (isCurrentCountry ? L("Wird automatisch richtig gewertet", "Will be marked correct automatically") : L("Wird automatisch falsch gewertet", "Will be marked wrong automatically")) : L("Weiter tippen oder Enter drücken", "Keep typing or press Return"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedSubject == .capitals ? L("Tippe die Hauptstadt. Kleine Fehler sind okay.", "Type the capital. Small typos are okay.") : L("Tippe den Ländernamen. Kleine Fehler sind okay.", "Type the country name. Small typos are okay."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    func leagueAnswerDetailRow(_ answer: LeagueAnswerRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: answer.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(answer.wasCorrect ? .green : .red)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(answer.countryName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(answer.wasCorrect ? L("gewusst", "known") : L("nicht gewusst", "missed"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(answer.wasCorrect ? .green : .red)
                        .background((answer.wasCorrect ? Color.green : Color.red).opacity(0.12), in: Capsule())
                }

                Text(L("Eingabe: \(answer.submittedAnswer) · Erkannt: \(answer.detectedCountryName)", "Input: \(answer.submittedAnswer) · Detected: \(answer.detectedCountryName)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(L("\(leagueResponseTimeText(answer.responseTime)) · +\(answer.pointsAwarded) Punkte", "\(leagueResponseTimeText(answer.responseTime)) · +\(answer.pointsAwarded) points"))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(answer.wasCorrect ? tealAccentColor : .secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    func leagueResponseTimeText(_ seconds: Double) -> String {
        String(format: "%.1f s", max(seconds, 0))
    }
}
