import SwiftUI
import Foundation
import UIKit

enum CountryScope {
    static let worldwide = "Alle Länder"
}

enum AppScreen: String, CaseIterable, Hashable, Identifiable {
    case games = "games"
    case practice = "practice"
    case showmaster = "showmaster"
    case miniWorldCup = "miniWorldCup"
    case league = "league"
    case statistics = "statistics"
    case globe = "globe"
    case achievements = "achievements"
    case friends = "friends"
    case options = "options"

    func title(language: AppLanguage) -> String {
        switch self {
        case .games: return localized("Spielen", "Play", language: language)
        case .practice: return localized("Üben", "Practice", language: language)
        case .showmaster: return "Showmaster"
        case .miniWorldCup: return localized("Partymodus Beta", "Party Mode Beta", language: language)
        case .league: return localized("Flaggenrun Beta", "Flag Run Beta", language: language)
        case .statistics: return localized("Statistik", "Statistics", language: language)
        case .globe: return localized("Globus", "Globe", language: language)
        case .achievements: return localized("Achievements", "Achievements", language: language)
        case .friends: return localized("Online", "Online", language: language)
        case .options: return localized("Optionen", "Options", language: language)
        }
    }

    var iconName: String {
        switch self {
        case .games: return "play.rectangle.fill"
        case .practice: return "rectangle.stack.fill"
        case .showmaster: return "rectangle.on.rectangle"
        case .miniWorldCup: return "person.3.fill"
        case .league: return "trophy.circle.fill"
        case .statistics: return "chart.bar.fill"
        case .globe: return "globe.europe.africa.fill"
        case .achievements: return "trophy.fill"
        case .friends: return "person.2.fill"
        case .options: return "gearshape.fill"
        }
    }

    var id: String { rawValue }

    func infoText(language: AppLanguage) -> String {
        switch self {
        case .games:
            return localized("Hier liegen alle aktiven Spielmodi. Üben ist für deinen Lernfortschritt, Showmaster für schnelles Abfragen, Partymodus für mehrere Personen an einem Handy und Flaggenrun für Punkte auf Zeit.", "All active game modes are here. Practice is for learning progress, Showmaster is for quick self-check rounds, Party Mode is for several people on one phone, and Flag Run is for timed scoring.", language: language)
        case .practice:
            return localized("Trainiere Flaggen oder Hauptstädte mit Karten. Wische nach rechts, wenn du es wusstest, und nach links, wenn nicht. Die App passt daraus die Stufen an, fragt unsichere Länder häufiger ab und zählt deinen Fortschritt für Statistik und Achievements.", "Train flags or capitals with cards. Swipe right when you knew it and left when you did not. The app adjusts levels from that, repeats uncertain countries more often, and counts progress for statistics and achievements.", language: language)
        case .showmaster:
            return localized("Showmaster ist der schnelle Abfrage-Modus. Du bekommst eine feste Anzahl Karten, sagst die Antwort laut oder im Kopf und deckst danach auf. Dann markierst du selbst, ob es richtig war. Gut für kurze Tests, aber entspannter als Flaggenrun, weil kein Timer Druck macht.", "Showmaster is the fast self-check mode. You get a fixed number of cards, say the answer out loud or in your head, then reveal it. After that you mark whether it was correct. Good for quick tests, but calmer than Flag Run because there is no timer pressure.", language: language)
        case .miniWorldCup:
            return localized("Party-Modus für mehrere Spieler an einem Handy. Jede Person bekommt ihre Flaggen, danach wird weitergegeben. Wer zu wenig richtig hat, fliegt raus. Am Ende siehst du, wer in welcher Runde weiterkam oder ausgeschieden ist.", "Party mode for multiple players on one phone. Each person gets their flags, then passes the phone on. Whoever gets too few correct is eliminated. At the end you see who advanced or dropped out in each round.", language: language)
        case .league:
            return localized("Beta-Modus für deinen besten Flaggenrun. Du spielst gegen die Zeit, bekommst Punkte für richtige Antworten und mehr Punkte, wenn du schnell bist. Der beste Highscore kann online verglichen werden.", "Beta mode for your best Flag Run. You play against the clock, get points for correct answers, and more points when you are fast. Your best high score can be compared online.", language: language)
        case .statistics:
            return localized("Hier siehst du deinen Lernstand kompakt: Stufen von F bis S, Trefferquoten, Streaks, Verläufe und einzelne Länder. So erkennst du schnell, was sicher sitzt und was wiederholt werden sollte.", "This shows your learning state compactly: F to S levels, accuracy, streaks, history, and individual countries. It helps you see what is solid and what should be repeated.", language: language)
        case .globe:
            return localized("Der Globus zeigt deinen Fortschritt räumlich. Farben stehen für die Lernstufen der Länder. Du kannst drehen, zoomen, Länder suchen und einzelne Länder antippen, um Details zu sehen.", "The globe shows your progress spatially. Colors represent country mastery levels. You can rotate, zoom, search for countries, and tap individual countries for details.", language: language)
        case .achievements:
            return localized("Achievements sammeln besondere Ziele aus Üben, Showmaster und Regionen. Du siehst pro Kategorie, wie viel geschafft ist, was bereits freigeschaltet wurde und welche Ziele als Nächstes erreichbar sind.", "Achievements collect special goals from Practice, Showmaster, and regions. You see per category how much is done, what is unlocked, and which goals are closest next.", language: language)
        case .friends:
            return localized("Online bündelt Cloud-Sync, Bestenlisten und Vergleiche. Du kannst deinen Spitznamen nutzen, Highscores vergleichen und sehen, wie andere bei Flaggen oder Hauptstädten stehen.", "Online collects cloud sync, leaderboards, and comparisons. You can use your nickname, compare high scores, and see how others are doing with flags or capitals.", language: language)
        case .options:
            return localized("In den Optionen stellst du Sprache, Design, Vibration, Spitznamen, Daten und Vollversion ein.", "Options control language, design, haptics, nickname, data, and full version.", language: language)
        }
    }
}

struct AchievementItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let currentValue: Int
    let targetValue: Int
    let tint: Color

    var isUnlocked: Bool {
        currentValue >= targetValue
    }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1)
    }
}

struct PracticeSessionChange: Identifiable {
    let id = UUID()
    let country: Country
    let wasKnown: Bool
    let fromTier: MasteryTier
    let toTier: MasteryTier
}

struct PracticeHistoryPreview: Identifiable, Equatable {
    let change: PracticeSessionChange
    let index: Int
    let total: Int

    var id: UUID { change.id }

    static func == (lhs: PracticeHistoryPreview, rhs: PracticeHistoryPreview) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index && lhs.total == rhs.total
    }
}

struct GameCenterAuthPresentation: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

struct GameCenterAuthView: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

enum OnlineLeaderboardMetric {
    case week
    case flaggenrun
    case flaggenscore
    case learningStreak
}

enum ScoreHistoryGranularity: String, CaseIterable, Identifiable {
    case days
    case weeks
    case months

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .days: return localized("Tage", "Days", language: language)
        case .weeks: return localized("Wochen", "Weeks", language: language)
        case .months: return localized("Monate", "Months", language: language)
        }
    }

    var visiblePointCount: Int {
        switch self {
        case .days: return 7
        case .weeks: return 8
        case .months: return 6
        }
    }
}

enum PracticeBalanceRange: String, CaseIterable, Identifiable {
    case lastWeek
    case lastMonth
    case lastYear

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .lastWeek: return localized("Letzte 7 Tage", "Last 7 days", language: language)
        case .lastMonth: return localized("Letzte 30 Tage", "Last 30 days", language: language)
        case .lastYear: return localized("Letzte 365 Tage", "Last 365 days", language: language)
        }
    }

    var days: Int {
        switch self {
        case .lastWeek: return 7
        case .lastMonth: return 30
        case .lastYear: return 365
        }
    }
}

enum OnlineLeaderboardScope: String, CaseIterable, Identifiable {
    case friends
    case global

    var id: String { rawValue }
}

enum AchievementSortMode: String, CaseIterable, Identifiable {
    case category
    case date
    case worldwide

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .category: return localized("Kategorie", "Category", language: language)
        case .date: return localized("Datum", "Date", language: language)
        case .worldwide: return localized("Weltweit", "Worldwide", language: language)
        }
    }
}

struct ShowSessionEntry: Identifiable {
    let id = UUID()
    let country: Country
}

struct ShowHistoryPreview: Identifiable, Equatable {
    let entry: ShowSessionEntry
    let index: Int
    let total: Int

    var id: UUID { entry.id }

    static func == (lhs: ShowHistoryPreview, rhs: ShowHistoryPreview) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index && lhs.total == rhs.total
    }
}

struct MiniWorldCupPlayer: Identifiable, Equatable {
    let id = UUID()
    var name: String
}

struct MiniWorldCupElimination: Identifiable, Equatable {
    let id = UUID()
    let playerName: String
    let country: Country
    let round: Int
    let correctCount: Int
    let flagCount: Int
}

struct MiniWorldCupRoundResult: Identifiable, Equatable {
    let id = UUID()
    let playerName: String
    let country: Country
    let round: Int
    let correctCount: Int
    let flagCount: Int
    let didAdvance: Bool
}

struct MiniWorldCupBracketRow: Identifiable {
    let place: Int
    let elimination: MiniWorldCupElimination

    var id: UUID { elimination.id }
}

struct MiniWorldCupUndoSnapshot {
    let appData: AppData
    let activePlayers: [MiniWorldCupPlayer]
    let eliminations: [MiniWorldCupElimination]
    let roundResults: [MiniWorldCupRoundResult]
    let phase: MiniWorldCupPhase
    let currentPlayerIndex: Int
    let currentCountry: Country
    let round: Int
    let currentAttempt: Int
    let currentCorrect: Int
    let currentAttemptResults: [Bool]
    let cardIsFlipped: Bool
    let cardWasRevealed: Bool
    let recentCountryCodes: [String]
    let deckCountryCodes: [String]
    let suddenDeathIsActive: Bool
}

enum MiniWorldCupPhase {
    case setup
    case handoff
    case question
    case finished
}

struct PracticeUndoSnapshot {
    let appData: AppData
    let currentCountry: Country
    let practiceSessionCount: Int
    let practiceSessionKnown: Int
    let practiceSessionUnknown: Int
    let practiceSessionImproved: Int
    let practiceSessionResults: [Bool]
    let practiceSessionChanges: [PracticeSessionChange]
    let practiceSessionSeenCountryCodes: Set<String>
    let cardIsFlipped: Bool
    let cardHintIsVisible: Bool
    let currentCardUsedHint: Bool
    let recapEndCounts: [MasteryTier: Int]
}

enum StoreProductID: String, CaseIterable {
    case fullVersion = "de.phil.SpassmitFlaggen.fullversion"
    case donationSmall = "de.phil.SpassmitFlaggen.donation.small"
    case donationMedium = "de.phil.SpassmitFlaggen.donation.medium"
    case donationLarge = "de.phil.SpassmitFlaggen.donation.large"

    static var allIDs: [String] {
        allCases.map(\.rawValue)
    }

    static var donationIDs: Set<String> {
        [donationSmall.rawValue, donationMedium.rawValue, donationLarge.rawValue]
    }
}
