import SwiftUI
import Foundation
import UIKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    static var systemDefault: AppLanguage {
        let preferredIdentifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        let languageCode = Locale(identifier: preferredIdentifier).language.languageCode?.identifier ?? preferredIdentifier
        return languageCode.lowercased().hasPrefix("de") ? .german : .english
    }

    var title: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .system: return localized("System", "System", language: language)
        case .light: return localized("Hell", "Light", language: language)
        case .dark: return localized("Dunkel", "Dark", language: language)
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case teal
    case blue
    case purple
    case pink
    case orange
    case green
    case champion

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .teal: return localized("Türkis", "Teal", language: language)
        case .blue: return localized("Blau", "Blue", language: language)
        case .purple: return localized("Lila", "Purple", language: language)
        case .pink: return localized("Pink", "Pink", language: language)
        case .orange: return localized("Orange", "Orange", language: language)
        case .green: return localized("Grün", "Green", language: language)
        case .champion: return localized("Champion", "Champion", language: language)
        }
    }

    var lightUIColor: UIColor {
        switch self {
        case .teal: return UIColor(red: 0.0, green: 0.62, blue: 0.58, alpha: 1)
        case .blue: return UIColor(red: 0.12, green: 0.42, blue: 0.86, alpha: 1)
        case .purple: return UIColor(red: 0.48, green: 0.28, blue: 0.86, alpha: 1)
        case .pink: return UIColor(red: 0.86, green: 0.18, blue: 0.48, alpha: 1)
        case .orange: return UIColor(red: 0.86, green: 0.38, blue: 0.08, alpha: 1)
        case .green: return UIColor(red: 0.13, green: 0.55, blue: 0.25, alpha: 1)
        case .champion: return UIColor(red: 0.98, green: 0.42, blue: 0.20, alpha: 1)
        }
    }

    var darkUIColor: UIColor {
        switch self {
        case .teal: return UIColor(red: 0.23, green: 0.88, blue: 0.86, alpha: 1)
        case .blue: return UIColor(red: 0.36, green: 0.64, blue: 1.0, alpha: 1)
        case .purple: return UIColor(red: 0.72, green: 0.54, blue: 1.0, alpha: 1)
        case .pink: return UIColor(red: 1.0, green: 0.46, blue: 0.70, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1)
        case .green: return UIColor(red: 0.38, green: 0.82, blue: 0.46, alpha: 1)
        case .champion: return UIColor(red: 1.0, green: 0.78, blue: 0.20, alpha: 1)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .champion:
            return [Color(red: 1.0, green: 0.76, blue: 0.18), Color(red: 0.98, green: 0.18, blue: 0.46), Color(red: 0.18, green: 0.68, blue: 1.0)]
        default:
            return [Color(lightUIColor), Color(darkUIColor)]
        }
    }
}

func localized(_ german: String, _ english: String, language: AppLanguage) -> String {
    language == .german ? german : english
}

func localizedCountryName(_ country: Country, language: AppLanguage) -> String {
    language == .english ? (countryEnglishNameByCode[country.code] ?? country.name) : country.name
}

enum FreeVersionLimits {
    static let dailyFlagCards = 50
    static let dailyFlaggenrunRounds = 2
    static let dailyPartyModeRounds = 2
}

func capitalPronunciation(for country: Country, capital: String) -> String {
    capitalPronunciationByCountryCode[country.code] ?? capital
}

enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func tap(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
