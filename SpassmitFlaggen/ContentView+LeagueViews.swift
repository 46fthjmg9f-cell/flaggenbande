import SwiftUI
import Foundation

extension ContentView {
    var leagueView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            if leagueMatchActive {
                leagueMatchCard
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        modeHeader(
                            title: runTitleWithBeta,
                            subtitle: leagueShowsStartMenu
                                ? L("Daily-Highscore auf Zeit", "Timed Daily high score")
                                : L("Unbegrenztes Training ohne Highscore", "Unlimited practice without a high score")
                        )

                        if leagueShowsStartMenu {
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
        }
        .navigationTitle(runTitleWithBeta)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(leagueMatchActive ? .hidden : .visible, for: .navigationBar)
        .sheet(item: $selectedLeagueHistoryMatch) { match in
            leagueHistoryDetailSheet(match)
        }
        .task(id: "\(selectedSubject.rawValue)|\(leaguePracticeAssetSignature(for: availableCountries))|\(leagueMatchActive)") {
            guard !leagueMatchActive else { return }
            _ = await prepareLeaguePracticeAssetsIfNeeded()
            guard onlineFeaturesEnabled else { return }
            if !isGameCenterAuthenticated {
                authenticateGameCenter(syncAfterAuthentication: false)
            } else if gameCenterFriendIDs.isEmpty {
                await loadGameCenterFriends()
            }
            if onlineLeaderboard.isEmpty {
                await loadOnlineStats()
            }
            if dailyLeagueChallenge?.mode != DailyFlaggenrunService.mode(for: selectedSubject)
                || dailyLeagueChallenge?.dateKey != DailyFlaggenrunService.dateKey() {
                await refreshDailyLeagueStatus()
            }
            await prepareDailyLeagueOpeningAssetsIfAvailable()
            await refreshTrophyLeaderboard()
        }
    }

    var leagueStartMenuView: some View {
        VStack(spacing: 14) {
            leaguePracticeModeCard
            if leaguePracticeHistoryIsExpanded {
                leaguePracticeHistoryCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            leagueDailyModeCard
            DisclosureGroup {
                VStack(spacing: 12) {
                    leagueStatsCard
                    leagueBestRunsCard
                    leagueMatchHistoryCard
                    flaggenrunLeaderboardCard
                    trophyLeaderboardCard
                }
                .padding(.top, 10)
            } label: {
                Label(L("Statistik und Ranglisten", "Stats and leaderboards"), systemImage: "chart.bar.xaxis")
                    .font(.headline)
            }
            .tint(tealAccentColor)
            .padding(14)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    var leaguePracticeModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("\(runTitle) Üben", "\(runTitle) Practice"), systemImage: "bolt.circle.fill")
                .font(.headline)
                .foregroundStyle(tealAccentColor)
            Text(L("Unbegrenzt trainieren.", "Train without limits."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        leaguePracticeHistoryIsExpanded = false
                        leagueShowsStartMenu = false
                    }
                } label: {
                    Label(L("Üben öffnen", "Open practice"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ActionButtonStyle(color: tealAccentColor))

                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        leaguePracticeHistoryIsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.headline.weight(.bold))
                        .frame(width: 20, height: 48)
                }
                .buttonStyle(ActionButtonStyle(color: tealAccentColor, isProminent: false, verticalPadding: 0))
                .frame(width: 54)
                .accessibilityLabel(L("Übungs-History", "Practice history"))
                .accessibilityValue(leaguePracticeHistoryIsExpanded ? L("Geöffnet", "Expanded") : L("Geschlossen", "Collapsed"))
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var leagueDailyModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(dailyRunTitle, systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(tealAccentColor)
                Spacer()
                if isLoadingDailyLeague {
                    ProgressView()
                        .tint(tealAccentColor)
                }
            }
            Text(L("2 Versuche pro Tag. Gleiche Flaggen für alle. Wer am Tagesende Platz 1 ist, bekommt einen Pokal.", "2 attempts per day. Same flags for everyone. Whoever finishes the day in 1st place gets a trophy."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                leagueMetricTile(title: L("Heute", "Today"), value: dailyLeagueDisplayDate)
                leagueMetricTile(title: L("Versuche", "Attempts"), value: "\(dailyLeagueStatus?.attemptsRemaining ?? 0)/2")
                leagueMetricTile(title: L("Pokale", "Trophies"), value: "\(dailyLeagueStatus?.trophies ?? 0)")
            }

            if let dailyLeagueStatusMessage {
                Text(dailyLeagueStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            leagueAssetPreparationStatusView

            Button {
                Haptics.tap()
                Task { await startDailyLeagueMatch() }
            } label: {
                Label(dailyLeagueStatus?.attemptsUsed == 1 ? L("Zweiten Versuch starten", "Start second attempt") : L("Daily starten", "Start daily"), systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            .disabled(isLoadingDailyLeague || isPreparingLeagueAssets || dailyLeagueStatus == nil || (dailyLeagueStatus?.attemptsRemaining ?? 0) <= 0 || dailyLeagueStatusMessage != nil)

            if (dailyLeagueStatus?.attemptsRemaining ?? 0) <= 0 {
                Text(L("Du hast deine 2 Versuche für heute verbraucht.", "You have used your 2 attempts for today."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            if debugToolsEnabled {
                Button {
                    Haptics.notify(.warning)
                    Task { await debugResetDailyLeagueLimit() }
                } label: {
                    Label(L("Daily-Versuche zurücksetzen", "Reset daily attempts"), systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(ActionButtonStyle(color: .red, isProminent: false))
                .disabled(isLoadingDailyLeague)
            }
            #endif

            dailyLeagueLeaderboardCard
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var dailyRunTitle: String {
        selectedSubject == .capitals ? L("Täglicher Städterun", "Daily City Run") : L("Täglicher Flaggenrun", "Daily Flag Run")
    }

    var dailyLeagueDisplayDate: String {
        let dateKey = dailyLeagueStatus?.dateKey ?? DailyFlaggenrunService.dateKey()
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3 else { return dateKey }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    var dailyLeagueLeaderboardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("Tagesbestenliste", "Daily leaderboard"), systemImage: "list.number")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(dailyLeagueDisplayDate)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if dailyLeagueLeaderboard.isEmpty {
                Text(L("Heute noch keine Daily-Ergebnisse.", "No daily results yet today."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(dailyLeagueLeaderboard.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(index == 0 ? .yellow : .secondary)
                                .frame(width: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(entry.correctCount) \(L("richtig", "correct")) · \(L("Versuch", "attempt")) \(entry.bestAttemptNumber) · \(formattedDailyDateKey(entry.dateKey))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.bestScore)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(tealAccentColor)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
                if result.runVariant == .daily {
                    leagueMetricTile(title: L("Daily-Bestscore", "Daily best score"), value: "\(dailyBestMatch?.ownScore ?? result.ownScore)")
                } else {
                    leagueMetricTile(title: L("Quote", "Rate"), value: percentText(result.accuracy))
                }
            }

            Text(selectedSubject == .capitals ? L("\(result.correct) richtig · \(result.wrong) falsch · \(result.answerDetails?.count ?? result.totalAnswers) Hauptstädte", "\(result.correct) correct · \(result.wrong) wrong · \(result.answerDetails?.count ?? result.totalAnswers) capitals") : L("\(result.correct) richtig · \(result.wrong) falsch · \(result.answerDetails?.count ?? result.totalAnswers) Flaggen", "\(result.correct) correct · \(result.wrong) wrong · \(result.answerDetails?.count ?? result.totalAnswers) flags"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if result.runVariant == .daily {
                VStack(alignment: .leading, spacing: 6) {
                    if let lastDailyLeagueResultWasBest {
                        Text(lastDailyLeagueResultWasBest ? L("Neuer bester Daily-Versuch für heute.", "New best daily attempt for today.") : L("Dein bisher bester Daily-Versuch bleibt vorne.", "Your previous best daily attempt stays ahead."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(lastDailyLeagueResultWasBest ? tealAccentColor : .secondary)
                    }
                    Text(L("Verbleibende Versuche: \(dailyLeagueStatus?.attemptsRemaining ?? 0)/2", "Attempts remaining: \(dailyLeagueStatus?.attemptsRemaining ?? 0)/2"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

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
            leagueAssetPreparationStatusView
            leaguePracticeStatsCard
            leaguePracticeHistoryCard
        }
    }

    var leagueStartMatchButton: some View {
        Button {
            Haptics.tap()
            Task { await startLeagueMatch() }
        } label: {
            Label(isPreparingLeagueAssets ? L("Flaggen werden vorbereitet …", "Preparing flags …") : L("Übung starten", "Start practice"), systemImage: isPreparingLeagueAssets ? "arrow.down.circle" : "play.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        .disabled(isPreparingLeagueAssets)
    }

    @ViewBuilder
    var leagueAssetPreparationStatusView: some View {
        if isPreparingLeagueAssets, leagueAssetPreloadTotal > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(
                    value: Double(leagueAssetPreloadCompleted),
                    total: Double(max(leagueAssetPreloadTotal, 1))
                )
                .tint(tealAccentColor)
                Text(L(
                    "Bereite Flaggen vor (\(min(leagueAssetPreloadCompleted, leagueAssetPreloadTotal))/\(leagueAssetPreloadTotal))",
                    "Preparing flags (\(min(leagueAssetPreloadCompleted, leagueAssetPreloadTotal))/\(leagueAssetPreloadTotal))"
                ))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        } else if let leagueAssetPreloadError {
            Label(leagueAssetPreloadError, systemImage: "wifi.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    func leagueUnknownButton(minHeight: CGFloat = 48) -> some View {
        let isEnabled = leagueTimerIsRunning && !leagueInputIsLocked
        return Button {
            guard isEnabled else { return }
            Haptics.notify(.warning)
            submitLeagueAnswer(forcedCorrectness: false, keepsTypedAnswer: false)
        } label: {
            Label(L("Weiß ich nicht", "I don't know"), systemImage: "questionmark.circle.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(ActionButtonStyle(color: .orange, isProminent: false, verticalPadding: 0))
        .disabled(!isEnabled)
    }

    var practiceHistoryMatches: [LeagueMatchResult] {
        (activeProfile.leagueStats?.matches(variant: .practice, subject: selectedSubject) ?? [])
            .sorted { $0.date > $1.date }
    }

    var dailyHistoryMatches: [LeagueMatchResult] {
        var matches = activeProfile.leagueStats?.matches(variant: .daily, subject: selectedSubject) ?? []
        var knownKeys = Set(matches.map(dailyHistoryKey))

        for attempt in dailyLeagueAttempts {
            let result = attempt.result
            guard result.subject == selectedSubject else { continue }
            let key = dailyHistoryKey(result)
            if knownKeys.insert(key).inserted {
                matches.append(result)
            }
        }

        return matches.sorted { $0.date > $1.date }
    }

    var dailyBestRuns: [LeagueMatchResult] {
        dailyHistoryMatches.filter { !$0.wasAborted }.sorted {
            if $0.ownScore == $1.ownScore { return $0.date > $1.date }
            return $0.ownScore > $1.ownScore
        }
    }

    var dailyBestMatch: LeagueMatchResult? {
        dailyBestRuns.first
    }

    func dailyHistoryKey(_ match: LeagueMatchResult) -> String {
        if let dateKey = match.dailyDateKey, let attempt = match.dailyAttemptNumber {
            return "\(match.subject.rawValue)|\(dateKey)|\(attempt)"
        }
        return match.id.uuidString
    }

    func leagueAccuracy(for matches: [LeagueMatchResult]) -> Double {
        let correct = matches.reduce(0) { $0 + $1.correct }
        let total = correct + matches.reduce(0) { $0 + $1.wrong }
        return total == 0 ? 0 : Double(correct) / Double(total)
    }

    func formattedDailyDateKey(_ dateKey: String) -> String {
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3 else { return dateKey }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    func formattedLeagueRunDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
    }

    func leagueRelativeTimeText(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let value: Int
        let germanUnit: String
        let englishUnit: String

        switch seconds {
        case ..<60:
            return L("vor weniger als 1 Minute", "less than 1 minute ago")
        case ..<3_600:
            value = max(1, Int(seconds / 60))
            germanUnit = value == 1 ? "Minute" : "Minuten"
            englishUnit = value == 1 ? "minute" : "minutes"
        case ..<86_400:
            value = max(1, Int(seconds / 3_600))
            germanUnit = value == 1 ? "Stunde" : "Stunden"
            englishUnit = value == 1 ? "hour" : "hours"
        case ..<604_800:
            value = max(1, Int(seconds / 86_400))
            germanUnit = value == 1 ? "Tag" : "Tagen"
            englishUnit = value == 1 ? "day" : "days"
        case ..<2_629_800:
            value = max(1, Int(seconds / 604_800))
            germanUnit = value == 1 ? "Woche" : "Wochen"
            englishUnit = value == 1 ? "week" : "weeks"
        default:
            value = max(1, Int(seconds / 2_629_800))
            germanUnit = value == 1 ? "Monat" : "Monaten"
            englishUnit = value == 1 ? "month" : "months"
        }

        return L("vor \(value) \(germanUnit)", "\(value) \(englishUnit) ago")
    }

    var leagueStatsCard: some View {
        let matches = dailyHistoryMatches
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("Daily-Statistik", "Daily statistics"), systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Daily-Highscore", "Daily high score"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tealAccentColor)
                    Text("\(dailyBestMatch?.ownScore ?? 0) \(L("Punkte", "points"))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                leagueMetricTile(title: L("Daily Runs", "Daily runs"), value: "\(matches.count)")
                leagueMetricTile(title: L("Bestscore", "Best score"), value: "\(dailyBestMatch?.ownScore ?? 0)")
                leagueMetricTile(title: L("Quote", "Rate"), value: percentText(leagueAccuracy(for: matches)))
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var leaguePracticeStatsCard: some View {
        let matches = practiceHistoryMatches
        return VStack(alignment: .leading, spacing: 12) {
            Label(L("Übungsstatistik", "Practice statistics"), systemImage: "bolt.circle")
                .font(.headline)
            Text(L("Übungsrunden werden getrennt geführt und zählen nicht für Highscores.", "Practice rounds are kept separate and do not count toward high scores."))
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                leagueMetricTile(title: L("Übungen", "Practice runs"), value: "\(matches.count)")
                leagueMetricTile(title: L("Quote", "Rate"), value: percentText(leagueAccuracy(for: matches)))
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
        leagueHistoryCard(
            matches: dailyHistoryMatches,
            title: L("Daily Match-History", "Daily match history"),
            emptyText: selectedSubject == .capitals ? L("Noch keine Daily-Städteruns gespielt.", "No Daily City Runs played yet.") : L("Noch keine Daily-Flaggenruns gespielt.", "No Daily Flag Runs played yet.")
        )
    }

    var leaguePracticeHistoryCard: some View {
        leagueHistoryCard(
            matches: practiceHistoryMatches,
            title: L("Übungs-History", "Practice history"),
            emptyText: L("Noch keine Übungsrunden gespielt.", "No practice runs played yet.")
        )
    }

    func leagueHistoryCard(matches: [LeagueMatchResult], title: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(matches.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if matches.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(matches.prefix(20)) { match in
                        Button {
                            Haptics.tap()
                            selectedLeagueHistoryMatch = match
                        } label: {
                            leagueHistoryRow(match)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var leagueBestRunsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Beste Daily Runs", "Best Daily runs"), systemImage: "trophy.fill")
                .font(.headline)

            if dailyBestRuns.isEmpty {
                Text(L("Noch keine Daily Runs für eine Bestenliste.", "No Daily runs for a best-runs list yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(dailyBestRuns.prefix(5).enumerated()), id: \.element.id) { index, match in
                        Button {
                            Haptics.tap()
                            selectedLeagueHistoryMatch = match
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(index + 1)")
                                    .font(.caption.monospacedDigit().weight(.black))
                                    .foregroundStyle(index == 0 ? .yellow : .secondary)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(match.ownScore) \(L("Punkte", "points"))")
                                        .font(.subheadline.monospacedDigit().weight(.bold))
                                    Text("\(formattedLeagueRunDate(match.date)) · \(leagueRelativeTimeText(since: match.date))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let attempt = match.dailyAttemptNumber {
                                    Text("\(L("Versuch", "Attempt")) \(attempt)")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(tealAccentColor)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
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
                Label(selectedSubject == .capitals ? L("Globale Daily-Städterun-Bestenliste", "Global Daily City Run leaderboard") : L("Globale Daily-Flaggenrun-Bestenliste", "Global Daily Flag Run leaderboard"), systemImage: "globe.europe.africa.fill")
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
                        LeagueLeaderboardRow(rank: index + 1, player: player, isCurrentPlayer: isCurrentOnlinePlayer(player), language: appLanguage, subject: selectedSubject)
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

    var trophyLeaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Pokale-Bestenliste", "Trophy leaderboard"), systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Spacer()
                if isLoadingTrophyLeaderboard {
                    ProgressView()
                        .tint(tealAccentColor)
                } else {
                    Button {
                        Haptics.tap()
                        Task { await refreshTrophyLeaderboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .disabled(!onlineFeaturesEnabled)
                }
            }

            Text(L("Länder- und Städte-Pokale zusammen", "Flag and city trophies combined"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let trophyLeaderboardMessage {
                Text(trophyLeaderboardMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !onlineFeaturesEnabled {
                Text(L("Onlinefunktionen sind ausgeschaltet.", "Online features are turned off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if trophyLeaderboard.isEmpty && isLoadingTrophyLeaderboard {
                Text(L("Pokale werden geladen …", "Loading trophies …"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if trophyLeaderboard.isEmpty {
                Text(L("Noch wurden keine Pokale vergeben.", "No trophies have been awarded yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(trophyLeaderboard.prefix(10).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 9) {
                            Text("#\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(index == 0 ? .yellow : .secondary)
                                .frame(width: 34, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(L("Flaggen \(entry.flagRunTrophies) · Städte \(entry.cityRunTrophies)", "Flags \(entry.flagRunTrophies) · Cities \(entry.cityRunTrophies)"))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Label("\(entry.totalTrophies)", systemImage: "trophy.fill")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(8)
                        .background(
                            entry.userId == DailyFlaggenrunService.userRecordName(gameCenterPlayerID: gameCenterPlayerID)
                                ? tealAccentColor.opacity(0.12)
                                : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .task {
            guard onlineFeaturesEnabled, trophyLeaderboard.isEmpty else { return }
            await refreshTrophyLeaderboard()
        }
    }

    func leagueHistoryDetailSheet(_ match: LeagueMatchResult) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        leagueMetricTile(title: L("Score", "Score"), value: "\(match.ownScore)")
                        leagueMetricTile(title: L("Quote", "Rate"), value: percentText(match.accuracy))
                    }

                    Text("\(match.correct) \(L("richtig", "correct")) · \(match.wrong) \(L("falsch", "wrong")) · \(leagueResponseTimeText(Double(match.duration)))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Label(formattedLeagueRunDate(match.date), systemImage: "calendar")
                        Text("·")
                        Text(leagueRelativeTimeText(since: match.date))
                        if let attempt = match.dailyAttemptNumber {
                            Text("·")
                            Text("\(L("Versuch", "Attempt")) \(attempt)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let details = match.answerDetails, !details.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(details) { answer in
                                leagueAnswerDetailRow(answer)
                            }
                        }
                    } else {
                        Text(L("Für dieses Match sind keine Einzeldetails gespeichert.", "No answer details were stored for this match."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Matchdetails", "Match details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        selectedLeagueHistoryMatch = nil
                    }
                }
            }
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

            VStack(alignment: .trailing, spacing: 3) {
                if let attempt = match.dailyAttemptNumber {
                    Text("\(L("Versuch", "Attempt")) \(attempt)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(tealAccentColor)
                }
                Text(leagueRelativeTimeText(since: match.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    var leagueMatchCard: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 540
            let contentPadding: CGFloat = compactHeight ? 8 : 12
            let showsPreparation = leagueMatchPhase == .loading || leagueMatchPhase == .countdown
            ZStack {
                leaguePlayableView(
                    compactHeight: compactHeight,
                    availableHeight: max(0, geometry.size.height - contentPadding * 2)
                )
                .opacity(showsPreparation ? 0.001 : 1)
                .allowsHitTesting(!showsPreparation)

                if showsPreparation {
                    leagueMatchPreparationView
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .padding(contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                if leagueMatchPhase == .loading || leagueMatchPhase == .countdown {
                    leagueLeaveMatchButton
                        .padding(10)
                }
            }
        }
        .onAppear {
            prepareLeagueTimerAfterLayout()
        }
        .onDisappear {
            leagueTimerStartTask?.cancel()
        }
    }

    var leagueMatchPreparationView: some View {
        VStack(spacing: 18) {
            Text(L("Run wird vorbereitet …", "Preparing run …"))
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

    func leaguePlayableView(compactHeight: Bool, availableHeight: CGFloat) -> some View {
        let spacing: CGFloat = compactHeight ? 6 : 8
        // Keep the interactive controls comfortably tappable even in the compact
        // layout. The flag area yields the few points necessary, rather than
        // making an active game harder to operate on smaller iPhones.
        let topBarHeight: CGFloat = 44
        let fieldHeight: CGFloat = compactHeight ? 44 : 48
        let choiceHeight: CGFloat = 44
        let unknownHeight: CGFloat = 44
        let feedbackHeight: CGFloat = compactHeight ? 26 : 32
        let reservedControlsHeight = topBarHeight + fieldHeight + choiceHeight + unknownHeight + spacing * 5
        let availableFlagHeight = max(96, availableHeight - reservedControlsHeight)
        let flagContainerHeight = min(max(availableFlagHeight, compactHeight ? 130 : 170), compactHeight ? 230 : 290)
        let flagPadding: CGFloat = compactHeight ? 6 : 10
        let flagHeight = max(96, flagContainerHeight - flagPadding * 2)
        let flagWidth = min(flagHeight * 1.62, compactHeight ? 330 : 390)

        return VStack(spacing: spacing) {
            HStack(spacing: 10) {
                leagueLeaveMatchButton

                Label(leagueTimerIsRunning ? "\(leagueSecondsRemaining)s" : L("Bereit", "Ready"), systemImage: "timer")
                    .font((compactHeight ? Font.headline : Font.title2).monospacedDigit().weight(.bold))
                    .foregroundStyle(leagueSecondsRemaining <= 10 ? .red : tealAccentColor)
                Spacer()
                Text("\(leagueScore)")
                    .font((compactHeight ? Font.headline : Font.title2).monospacedDigit().weight(.bold))
                Text("\(leagueCorrect)/\(leagueWrong)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: topBarHeight)

            ZStack {
                Group {
                    if let leaguePreloadedFlagImage {
                        ZoomableFlagImageView(image: leaguePreloadedFlagImage)
                            .frame(width: flagWidth, height: flagHeight)
                    } else {
                        FlagImage(country: leagueCurrentCountry, width: flagWidth, height: flagHeight)
                    }
                }
                .padding(flagPadding)
                .frame(maxWidth: .infinity)
                .opacity(leagueInputIsLocked ? 0.55 : 1)

                VStack {
                    Spacer(minLength: 0)
                    if let leagueAnswerFeedback {
                        leagueFeedbackField(isCorrect: leagueAnswerFeedback, height: feedbackHeight)
                            .padding(.horizontal, compactHeight ? 8 : 12)
                            .padding(.bottom, compactHeight ? 6 : 8)
                    }
                }
            }
            .frame(height: flagContainerHeight)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .layoutPriority(1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: leagueAnswerFeedback)
            .animation(.easeOut(duration: 0.16), value: leagueInputIsLocked)

            Spacer(minLength: 0)

            VStack(spacing: spacing) {
                leagueAnswerTextField(height: fieldHeight, compactHeight: compactHeight)

                ZStack {
                    if leagueAnswerCandidates.count >= 2 && leagueTimerIsRunning && !leagueInputIsLocked {
                        leagueCountryChoiceView(leagueAnswerCandidates, minHeight: choiceHeight)
                            .scaleEffect(leagueCandidateAttentionPulse ? 1.025 : 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(height: choiceHeight)
                .animation(.spring(response: 0.22, dampingFraction: 0.86), value: leagueAnswerCandidates.map(\.code).joined())

                leagueUnknownButton(minHeight: unknownHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    var leagueLeaveMatchButton: some View {
        Button {
            Haptics.tap()
            isLeagueAnswerFocused = false
            isShowingLeagueCancelConfirmation = true
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.bold))
                .frame(width: 44, height: 44)
                .foregroundStyle(tealAccentColor)
                .background(panelBackgroundColor.opacity(0.92), in: Circle())
                .overlay(
                    Circle()
                        .stroke(tealAccentColor.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Session verlassen", "Leave session"))
    }

    func leagueAnswerTextField(height: CGFloat, compactHeight: Bool) -> some View {
        TextField(selectedSubject == .capitals ? L("Name der Hauptstadt", "Capital name") : L("Name der Flagge", "Flag name"), text: $leagueAnswerText)
            .focused($isLeagueAnswerFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit { submitLeagueAnswer() }
            .font((compactHeight ? Font.body : Font.title3).weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: height)
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
    }

    @ViewBuilder
    func leagueCountryChoiceView(_ candidates: [Country], minHeight: CGFloat = 44) -> some View {
        if candidates.count == 2 {
            HStack(spacing: 8) {
                ForEach(candidates, id: \.code) { country in
                    leagueCandidateButton(country, minHeight: minHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: minHeight)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(candidates, id: \.code) { country in
                        leagueCandidateButton(country, minHeight: minHeight)
                            .frame(minWidth: 132)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: minHeight)
        }
    }

    func leagueCandidateButton(_ country: Country, minHeight: CGFloat) -> some View {
        Button {
            chooseLeagueCandidate(country)
        } label: {
            Text(leagueExpectedAnswerName(for: country))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
                .padding(.horizontal, 8)
                .foregroundStyle(tealAccentColor)
                .background(
                    tealAccentColor.opacity(leagueCandidateAttentionPulse ? 0.24 : 0.10),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            tealAccentColor.opacity(leagueCandidateAttentionPulse ? 1 : 0.55),
                            lineWidth: leagueCandidateAttentionPulse ? 2.2 : 1
                        )
                )
                .shadow(
                    color: tealAccentColor.opacity(leagueCandidateAttentionPulse ? 0.32 : 0),
                    radius: leagueCandidateAttentionPulse ? 6 : 0
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.20, dampingFraction: 0.62), value: leagueCandidateAttentionPulse)
    }

    func leagueFeedbackField(isCorrect: Bool, height: CGFloat = 34) -> some View {
        Label(
            isCorrect ? L("Richtig: \(leagueRevealedCountryName)", "Correct: \(leagueRevealedCountryName)") : L("Falsch: \(leagueRevealedCountryName)", "Wrong: \(leagueRevealedCountryName)"),
            systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .font(.subheadline.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(isCorrect ? .green : .red)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(panelBackgroundColor.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isCorrect ? Color.green : Color.red).opacity(0.35), lineWidth: 1)
        )
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
