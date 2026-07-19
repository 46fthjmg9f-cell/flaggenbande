import SwiftUI
import Foundation
import UIKit

extension ContentView {
    var activeProfile: UserProfile {
        appData.activeProfile ?? UserProfile(id: UUID(), name: "Training", pin: "")
    }

    var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .german
    }

    var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var appAccent: AppAccent {
        AppAccent(rawValue: appAccentRawValue) ?? .teal
    }

    var shouldDisableInteractiveBackSwipe: Bool {
        shouldDisableInteractiveBackSwipe(on: navigationPath.last)
    }

    func shouldDisableInteractiveBackSwipe(on screen: AppScreen?) -> Bool {
        guard let screen else { return false }

        switch screen {
        case .practice:
            return practiceSessionActive
                && !practiceRecapPromptIsVisible
                && practiceHistoryPreview == nil
                && practiceHistoryGlobeCountry == nil
        case .bloodyBeginner:
            return beginnerSessionActive
                && beginnerHistoryPreview == nil
                && practiceHistoryGlobeCountry == nil
        case .showmaster:
            return showSessionActive
                && showHistoryPreview == nil
                && practiceHistoryGlobeCountry == nil
        case .miniWorldCup:
            return miniWorldCupPhase == .question && miniWorldCupAnswerFeedback == nil
        case .league:
            return leagueMatchActive
        default:
            return false
        }
    }

    func shouldRestoreProtectedNavigationPath(from oldPath: [AppScreen], to newPath: [AppScreen]) -> Bool {
        newPath.count < oldPath.count && shouldDisableInteractiveBackSwipe(on: oldPath.last)
    }

    func L(_ german: String, _ english: String) -> String {
        localized(german, english, language: appLanguage)
    }

    func localizedScope(_ scope: String) -> String {
        if scope == CountryScope.worldwide {
            return L("Alle Länder", "All countries")
        }

        switch scope {
        case "Afrika": return L("Afrika", "Africa")
        case "Asien": return L("Asien", "Asia")
        case "Europa": return L("Europa", "Europe")
        case "Nordamerika": return L("Nordamerika", "North America")
        case "Ozeanien": return L("Ozeanien", "Oceania")
        case "Südamerika": return L("Südamerika", "South America")
        case partiallyRecognizedCategory: return L("Teilweise anerkannt", "Partly recognized")
        case dependentTerritoriesCategory: return L("Abhängige Gebiete", "Dependent territories")
        default: return scope
        }
    }

    func scopeTitleWithCount(_ scope: String) -> String {
        "\(localizedScope(scope)) (\(countries(inContinent: scope).count))"
    }

    var continents: [String] {
        Array(Set(availableCountries.map { $0.continent })).sorted()
    }

    var continentOptions: [String] {
        [CountryScope.worldwide] + continents
    }

    var appBackgroundColor: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
                : UIColor.systemGroupedBackground
        })
    }

    var appBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                appBackgroundColor,
                adaptiveColor(
                    light: UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1),
                    dark: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }

    var panelBackgroundColor: Color {
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 0.98)
                : UIColor.secondarySystemGroupedBackground
        })
    }

    var tealAccentColor: Color {
        let accent = appAccent
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? accent.darkUIColor
                : accent.lightUIColor
        })
    }


}
