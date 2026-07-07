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
            if $0.leagueBestScore == $1.leagueBestScore {
                return $0.leaguePlayed > $1.leaguePlayed
            }
            return $0.leagueBestScore > $1.leagueBestScore
        }
    }

    @MainActor
    func startLeagueMatch() async {
        guard consumeFreeDailyLeagueRunIfAllowed() else { return }

        leagueCorrect = 0
        leagueWrong = 0
        leagueScore = 0
        leagueSecondsRemaining = 60
        leagueRecentCountryCodes = []
        leagueAnswerRecords = []
        leagueAnswerText = ""
        leagueAnswerMatch = nil
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueTimerIsRunning = false
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueCurrentQuestionStartedAt = Date()
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueMatchPhase = .loading
        leagueStartCountdown = 3
        leagueFirstFlagIsReady = false
        leaguePreloadedFlagImage = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        leagueCurrentCountry = nextLeagueCountry()
        leagueMatchActive = true
    }

    func prepareLeagueTimerAfterLayout() {
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = Task { @MainActor in
            await Task.yield()
            leagueMatchPhase = .loading
            await prepareFirstLeagueFlag()
            guard leagueMatchActive else { return }
            leagueFirstFlagIsReady = true

            leagueMatchPhase = .countdown
            for value in stride(from: 3, through: 1, by: -1) {
                leagueStartCountdown = value
                try? await Task.sleep(for: .seconds(1))
                guard leagueMatchActive else { return }
            }

            leagueMatchPhase = .playing
            leagueCurrentQuestionStartedAt = Date()
            await Task.yield()
            isLeagueAnswerFocused = true
            try? await Task.sleep(for: .milliseconds(180))
            guard leagueMatchActive else { return }
            leagueTimerIsRunning = true
            startLeagueCountdown()
        }
    }

    func prepareFirstLeagueFlag() async {
        for _ in 0..<8 {
            guard leagueMatchActive else { return }
            if let image = await preloadedLeagueFlagImage(for: leagueCurrentCountry) {
                leaguePreloadedFlagImage = image
                return
            }
            leagueCurrentCountry = nextLeagueCountry()
        }

        leaguePreloadedFlagImage = nil
    }

    func preloadedLeagueFlagImage(for country: Country) async -> UIImage? {
        guard let url = country.flagImageURL else { return nil }
        do {
            let result = try await OnlineStatsService.withTimeout(seconds: 4) {
                try await FlagImageCache.shared.loadImage(from: url)
            }
            return result
        } catch {
            return nil
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
        submitLeagueAnswer(forcedCorrectness: nil, keepsTypedAnswer: true)
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
            leagueAnswerMatch = nil
            leagueCurrentCountry = nextCountry
            leaguePreloadedFlagImage = nextImage
            leagueMatchPhase = .playing
            leagueTypingLockedUntil = Date().addingTimeInterval(0.32)
            try? await Task.sleep(for: .milliseconds(320))
            guard leagueMatchActive, leagueCurrentCountry == nextCountry else { return }
            leagueInputIsLocked = false
            leagueTypingLockedUntil = .distantPast
            leagueCurrentQuestionStartedAt = Date()
            isLeagueAnswerFocused = true
        }
    }

    func finishLeagueMatch() {
        guard leagueMatchActive else { return }
        leagueMatchActive = false
        leagueTimerIsRunning = false
        isLeagueAnswerFocused = false
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueMatchPhase = .loading

        let result = LeagueMatchResult(
            id: UUID(),
            date: Date(),
            opponentName: L("Highscore", "High score"),
            ownScore: leagueScore,
            opponentScore: 0,
            correct: leagueCorrect,
            wrong: leagueWrong,
            duration: 60,
            answerDetails: leagueAnswerRecords,
            ratingBefore: nil,
            ratingAfter: nil,
            ratingDelta: nil
        )

        leagueSummaryResult = result
        leagueShowsStartMenu = true
        updateActiveProfile { profile in
            profile.recordLeagueMatch(result)
        }
        scheduleOnlineStatsSync()
        Haptics.notify(.success)
        playLeagueSound(success: true)
    }

    func nextLeagueCountry() -> Country {
        let candidates = availableCountries.filter { !leagueRecentCountryCodes.contains($0.code) }
        return (candidates.isEmpty ? availableCountries : candidates).randomElement() ?? allCountries[0]
    }

    func evaluateLeagueAnswer(_ value: String) {
        leagueAutoSubmitTask?.cancel()
        let match = bestLeagueAnswerMatch(for: value)
        leagueAnswerMatch = match

        guard
            leagueMatchActive,
            let match,
            !leagueInputIsLocked,
            match.isCertain
        else {
            return
        }

        let submittedText = value
        leagueAutoSubmitTask = Task { @MainActor in
            await Task.yield()
            guard leagueMatchActive, leagueAnswerText == submittedText, leagueAnswerMatch?.isCertain == true else { return }
            submitLeagueAnswer()
        }
    }

    func bestLeagueAnswerMatch(for rawAnswer: String) -> LeagueAnswerMatch? {
        let answer = normalizedLeagueAnswer(rawAnswer)
        guard answer.count >= 2 else { return nil }

        let scoredMatches = availableCountries.compactMap { country -> LeagueAnswerMatch? in
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
            return values
        })

        return aliases.map { alias in
            (displayName: alias, normalizedName: normalizedLeagueAnswer(alias))
        }
        .filter { !$0.normalizedName.isEmpty }
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

        if answer.count < candidate.count, answer.count >= 3 {
            let candidatePrefix = String(candidate.prefix(answer.count))
            let prefixDistance = levenshteinDistance(answer, candidatePrefix, maxDistance: 2)
            if prefixDistance <= 2 {
                let prefixSimilarity = 1 - (Double(prefixDistance) / Double(max(answer.count, candidatePrefix.count)))
                let completeness = Double(answer.count) / Double(candidate.count)
                if prefixSimilarity >= 0.58 {
                    return min(0.96, 0.72 + prefixSimilarity * 0.20 + completeness * 0.08)
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
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

}
