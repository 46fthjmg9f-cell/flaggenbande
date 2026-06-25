import SwiftUI
import Foundation

extension ContentView {
    var currentLearningStreak: Int {
        guard let lastDate = activeProfile.lastLearningStreakDate else { return 0 }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastDate) {
            return activeProfile.learningStreak ?? 0
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(lastDate, inSameDayAs: yesterday) {
            return activeProfile.learningStreak ?? 0
        }
        return 0
    }

    var subjectName: String {
        selectedSubject == .capitals ? L("Hauptstädte", "capitals") : L("Flaggen", "flags")
    }

    var practiceAchievementItems: [AchievementItem] {
        let countries = availableCountries
        let total = max(countries.count, 1)
        let seen = totalSeenFlags(in: countries)
        let knownOnce = totalKnownAtLeastOnceFlags(in: countries)
        let reviewed = totalCardReviews(in: countries)
        let sTierCount = countries.filter { stats(for: $0).tier == .s }.count
        let aOrBetterCount = countries.filter { [.s, .a].contains(stats(for: $0).tier) }.count
        let bestLearningStreak = max(activeProfile.bestLearningStreak ?? 0, currentLearningStreak)
        let allSHeldDays = allSTierHeldDays(in: countries)

        return [
            AchievementItem(
                id: "first-card",
                title: L("Erste Karte", "First card"),
                description: L("Eine \(subjectName)-Karte gelernt", "Study one \(subjectName) card"),
                iconName: "sparkle.magnifyingglass",
                currentValue: seen,
                targetValue: 1,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "ten-known",
                title: L("Zehn sicher", "Ten known"),
                description: L("10 verschiedene \(subjectName) mindestens einmal gewusst", "Know 10 different \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: 10,
                tint: .green
            ),
            AchievementItem(
                id: "fifty-known",
                title: L("50 sicher", "50 known"),
                description: L("50 verschiedene \(subjectName) mindestens einmal gewusst", "Know 50 different \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: 50,
                tint: .green
            ),
            AchievementItem(
                id: "all-known-once",
                title: L("Einmal alles gekonnt", "Known all once"),
                description: L("Alle verfügbaren \(subjectName) mindestens einmal gewusst", "Know every available \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "perfect-full-session",
                title: L("Perfekte Session", "Perfect session"),
                description: selectedSubject == .capitals
                    ? L("In einer Session alle Hauptstädte als gewusst geloggt", "Log every capital as known in one session")
                    : L("In einer Session alle Flaggen als gewusst geloggt", "Log every flag as known in one session"),
                iconName: "checkmark.circle.badge.star",
                currentValue: activeProfile.hasPerfectFullPracticeSession(subject: selectedSubject) ? 1 : 0,
                targetValue: 1,
                tint: .green
            ),
            AchievementItem(
                id: "fifty-reviews",
                title: L("Dranbleiben", "Keep going"),
                description: L("50 Karten im Üben-Modus bearbeitet", "Review 50 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 50,
                tint: .orange
            ),
            AchievementItem(
                id: "two-hundred-fifty-reviews",
                title: L("Routine", "Routine"),
                description: L("250 Karten im Üben-Modus bearbeitet", "Review 250 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 250,
                tint: .orange
            ),
            AchievementItem(
                id: "thousand-reviews",
                title: L("Trainingsmaschine", "Training machine"),
                description: L("1000 Karten im Üben-Modus bearbeitet", "Review 1000 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 1000,
                tint: .orange
            ),
            AchievementItem(
                id: "daily-500-practice",
                title: L("500 an einem Tag", "500 in one day"),
                description: selectedSubject == .capitals ? L("Über 500 Hauptstädte an einem Tag im Üben-Modus gelernt", "Study more than 500 capitals in one day in practice mode") : L("Über 500 Flaggen an einem Tag im Üben-Modus gelernt", "Study more than 500 flags in one day in practice mode"),
                iconName: "calendar.badge.clock",
                currentValue: activeProfile.maxPracticeCardsInOneDay(subject: selectedSubject),
                targetValue: 501,
                tint: .orange
            ),
            AchievementItem(
                id: "three-day-streak",
                title: L("Drei-Tage-Serie", "Three-day streak"),
                description: L("An 3 Tagen in Folge einen 10er-Block abgeschlossen", "Complete a block of 10 on 3 days in a row"),
                iconName: "flame.fill",
                currentValue: bestLearningStreak,
                targetValue: 3,
                tint: .red
            ),
            AchievementItem(
                id: "seven-day-streak",
                title: L("Wochenserie", "Weekly streak"),
                description: L("An 7 Tagen in Folge einen 10er-Block abgeschlossen", "Complete a block of 10 on 7 days in a row"),
                iconName: "flame.fill",
                currentValue: bestLearningStreak,
                targetValue: 7,
                tint: .red
            ),
            AchievementItem(
                id: "a-tier-five",
                title: L("A-Team", "A team"),
                description: L("5 Länder auf Stufe A oder S bringen", "Bring 5 countries to level A or S"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: 5,
                tint: .green
            ),
            AchievementItem(
                id: "a-tier-half",
                title: L("Halbes A-Feld", "Half A field"),
                description: L("Die Hälfte aller verfügbaren Länder mindestens auf Stufe A bringen", "Bring half of all available countries to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: max((total + 1) / 2, 1),
                tint: .green
            ),
            AchievementItem(
                id: "all-a-tier",
                title: L("Alle auf A", "All on A"),
                description: L("Alle verfügbaren Länder mindestens auf Stufe A bringen", "Bring every available country to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "first-s-tier",
                title: L("S-Stufe", "S level"),
                description: L("Ein Land auf Stufe S bringen", "Bring one country to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: 1,
                tint: .blue
            ),
            AchievementItem(
                id: "s-tier-twenty-five",
                title: L("S-Block", "S block"),
                description: L("25 Länder auf Stufe S bringen", "Bring 25 countries to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: 25,
                tint: .blue
            ),
            AchievementItem(
                id: "all-s-tier",
                title: L("Alle auf S", "All on S"),
                description: L("Alle verfügbaren Länder auf Stufe S bringen", "Bring every available country to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: total,
                tint: .blue
            ),
            AchievementItem(
                id: "all-s-two-weeks",
                title: L("S zwei Wochen gehalten", "Held S for two weeks"),
                description: L("Alle verfügbaren Karten 14 Tage lang auf Stufe S halten", "Keep every available card on level S for 14 days"),
                iconName: "calendar.badge.checkmark",
                currentValue: allSHeldDays,
                targetValue: 14,
                tint: .blue
            ),
            AchievementItem(
                id: "all-seen",
                title: L("Alles gesehen", "Seen everything"),
                description: L("Alle verfügbaren Länder einmal gesehen", "See every available country once"),
                iconName: "globe.europe.africa.fill",
                currentValue: seen,
                targetValue: total,
                tint: .purple
            )
        ]
    }

    var regionAchievementItems: [AchievementItem] {
        let continentItems = continents.flatMap { continent in
            continentAchievementItems(for: continent, countries: allCountries.filter { $0.continent == continent })
        }
        return continentItems + worldCupAchievementItems + partiallyRecognizedAchievementItems
    }

    var worldCupAchievementItems: [AchievementItem] {
        let countries = allCountries.filter { worldCupWinnerCountryCodes.contains($0.code) }
        let total = max(countries.count, 1)

        return [
            AchievementItem(
                id: "world-cup-heroes-known",
                title: L("WM-Held", "World Cup hero"),
                description: L("Alle Länder, die eine Fußball-WM gewonnen haben, mindestens einmal richtig erkannt", "Correctly recognize every country that has won a FIFA World Cup at least once"),
                iconName: "soccerball",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .orange
            )
        ]
    }

    var partiallyRecognizedAchievementItems: [AchievementItem] {
        let countries = partiallyRecognizedCountries
        let total = max(countries.count, 1)
        let groupTitle = L("umkämpfte Gebiete", "contested territories")

        return [
            AchievementItem(
                id: "contested-seen",
                title: L("Umkämpfte Gebiete gesehen", "Contested territories seen"),
                description: L("Alle \(groupTitle) einmal gesehen", "See all \(groupTitle) once"),
                iconName: "flag.filled.and.flag.crossed",
                currentValue: totalSeenFlags(in: countries),
                targetValue: total,
                tint: .indigo
            ),
            AchievementItem(
                id: "contested-known",
                title: L("Umkämpfte Gebiete sicher", "Contested territories known"),
                description: L("Alle \(groupTitle) mindestens einmal gewusst", "Know all \(groupTitle) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "contested-a-tier",
                title: L("Diplomaten-A", "Diplomat A"),
                description: L("Alle \(groupTitle) mindestens auf Stufe A bringen", "Bring all \(groupTitle) to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "contested-s-tier",
                title: L("Diplomaten-S", "Diplomat S"),
                description: L("Alle \(groupTitle) auf Stufe S bringen", "Bring all \(groupTitle) to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount(in: countries),
                targetValue: total,
                tint: .blue
            )
        ]
    }

    func continentAchievementItems(for continent: String, countries: [Country]) -> [AchievementItem] {
        let total = max(countries.count, 1)
        let name = localizedScope(continent)
        let idPrefix = continent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return [
            AchievementItem(
                id: "\(idPrefix)-seen",
                title: L("\(name) gesehen", "\(name) seen"),
                description: L("Alle \(subjectName) aus \(name) einmal gesehen", "See every \(subjectName) from \(name) once"),
                iconName: "globe.europe.africa.fill",
                currentValue: totalSeenFlags(in: countries),
                targetValue: total,
                tint: .purple
            ),
            AchievementItem(
                id: "\(idPrefix)-known",
                title: L("\(name) sicher", "\(name) known"),
                description: L("Alle \(subjectName) aus \(name) mindestens einmal gewusst", "Know every \(subjectName) from \(name) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "\(idPrefix)-a-tier",
                title: "\(name) A",
                description: L("Alle Länder aus \(name) mindestens auf Stufe A bringen", "Bring every country from \(name) to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount(in: countries),
                targetValue: total,
                tint: .green
            )
        ]
    }

    var showmasterAchievementItems: [AchievementItem] {
        let countries = availableCountries
        let showmasterPlayed = totalShowmasterPlayed(in: countries)
        let showmasterCountries = countries.filter { stats(for: $0).showmasterPlayed > 0 }.count

        return [
            AchievementItem(
                id: "showmaster-ten",
                title: "Showmaster 10",
                description: L("10 Karten im Showmaster gespielt", "Play 10 cards in Showmaster"),
                iconName: "rectangle.on.rectangle.angled",
                currentValue: showmasterPlayed,
                targetValue: 10,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "showmaster-hundred",
                title: "Showmaster 100",
                description: L("100 Karten im Showmaster gespielt", "Play 100 cards in Showmaster"),
                iconName: "sparkles.rectangle.stack.fill",
                currentValue: showmasterPlayed,
                targetValue: 100,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "showmaster-all-seen",
                title: L("Showmaster-Rundblick", "Showmaster overview"),
                description: L("Jedes verfügbare Land mindestens einmal im Showmaster gespielt", "Play every available country at least once in Showmaster"),
                iconName: "eye.fill",
                currentValue: showmasterCountries,
                targetValue: max(countries.count, 1),
                tint: .purple
            )
        ]
    }

    var achievementItems: [AchievementItem] {
        practiceAchievementItems + regionAchievementItems + showmasterAchievementItems
    }

    var unlockedAchievementCount: Int {
        achievementItems.filter(\.isUnlocked).count
    }

    var bossScoreTitle: String {
        selectedSubject == .capitals ? L("Städteboss-Score", "City boss score") : L("Flaggenboss-Score", "Flaggenboss score")
    }

    var bossTitle: String {
        selectedSubject == .capitals ? L("Städteboss", "City boss") : L("Flaggenboss", "Flaggenboss")
    }

    var runTitle: String {
        selectedSubject == .capitals ? L("Städterun", "City Run") : L("Flaggenrun", "Flag Run")
    }

    var runTitleWithBeta: String {
        "\(runTitle) Beta"
    }

    var runHighscoreTitle: String {
        selectedSubject == .capitals ? L("Städterun Highscore", "City Run high score") : L("Flaggenrun Highscore", "Flag Run high score")
    }

    func screenTitle(_ screen: AppScreen) -> String {
        screen == .league ? runTitleWithBeta : screen.title(language: appLanguage)
    }

    func screenInfoText(_ screen: AppScreen) -> String {
        if screen == .games, selectedSubject == .capitals {
            return L("Hier liegen alle aktiven Spielmodi. Üben ist für deinen Lernfortschritt, Showmaster für schnelles Abfragen, Partymodus für mehrere Personen an einem Handy und Städterun für Punkte auf Zeit.", "All active game modes are here. Practice is for learning progress, Showmaster is for quick self-check rounds, Party Mode is for several people on one phone, and City Run is for timed scoring.")
        }
        if screen == .league, selectedSubject == .capitals {
            return L("Beta-Modus für deinen besten Städterun. Du siehst eine Flagge, gibst die passende Hauptstadt ein und bekommst automatisch Punkte, wenn die Eingabe nah genug erkannt wird. Schnelle richtige Antworten bringen mehr Punkte.", "Beta mode for your best City Run. You see a flag, type the matching capital, and automatically score when the input is close enough. Faster correct answers give more points.")
        }
        return screen.infoText(language: appLanguage)
    }

    func achievementSectionTitle(_ title: String, items: [AchievementItem]) -> String {
        "\(title) \(items.filter(\.isUnlocked).count)/\(items.count)"
    }

    func achievementsSortedInsideCategory(_ items: [AchievementItem]) -> [AchievementItem] {
        items.sorted { first, second in
            if first.isUnlocked != second.isUnlocked {
                return first.isUnlocked
            }
            if first.progress != second.progress {
                return first.progress > second.progress
            }
            return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }

    var activeAchievementIDs: Set<String> {
        Set(achievementItems.filter(\.isUnlocked).map(\.id))
    }

    var globalAchievementPlayerCount: Int {
        max(deduplicatedOnlineLeaderboard.count, activeAchievementIDs.isEmpty ? 0 : 1)
    }

    func globalUnlockCount(for achievementID: String) -> Int {
        var count = deduplicatedOnlineLeaderboard.filter { $0.achievementIDs.contains(achievementID) }.count
        if activeAchievementIDs.contains(achievementID) && !deduplicatedOnlineLeaderboard.contains(where: { isCurrentOnlinePlayer($0) }) {
            count += 1
        }
        return count
    }

    func achievementsSortedByGlobalUnlocks(_ items: [AchievementItem]) -> [AchievementItem] {
        items.sorted {
            let firstCount = globalUnlockCount(for: $0.id)
            let secondCount = globalUnlockCount(for: $1.id)
            if firstCount == secondCount {
                if $0.isUnlocked == $1.isUnlocked {
                    return $0.title < $1.title
                }
                return $0.isUnlocked && !$1.isUnlocked
            }
            return firstCount < secondCount
        }
    }

    func achievementsSortedByDate(_ items: [AchievementItem]) -> [AchievementItem] {
        items.sorted {
            let firstDate = achievedDate(for: $0)
            let secondDate = achievedDate(for: $1)
            switch (firstDate, secondDate) {
            case let (first?, second?):
                if first == second { return $0.title < $1.title }
                return first > second
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if $0.isUnlocked == $1.isUnlocked {
                    return $0.progress > $1.progress
                }
                return $0.isUnlocked && !$1.isUnlocked
            }
        }
    }

    func achievedDate(for item: AchievementItem) -> Date? {
        activeProfile.achievedAchievementDates?[achievementAnnouncementID(for: item)]
    }

    func achievementDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == .german ? "de_DE" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }


}
