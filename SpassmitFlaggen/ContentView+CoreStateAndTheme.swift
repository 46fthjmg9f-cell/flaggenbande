import SwiftUI
import Foundation
import UIKit

extension ContentView {
    var activeProfile: UserProfile {
        appData.activeProfile ?? UserProfile(id: UUID(), name: "Training", pin: "")
    }

    var appLanguage: AppLanguage {
        #if DEBUG
        return .german
        #else
        return AppLanguage(rawValue: appLanguageRawValue) ?? .german
        #endif
    }

    var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var appAccent: AppAccent {
        AppAccent(rawValue: appAccentRawValue) ?? .teal
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
        if selectedSubject == .capitals {
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.05, green: 0.11, blue: 0.13, alpha: 1)
                    : UIColor(red: 0.91, green: 0.97, blue: 0.96, alpha: 1)
            })
        }
        return Color(.systemGroupedBackground)
    }

    var appBackgroundGradient: LinearGradient {
        if appAccent == .champion {
            return LinearGradient(colors: appAccent.gradientColors.map { $0.opacity(0.72) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        let colors: [Color]
        if selectedSubject == .capitals {
            colors = [
                adaptiveColor(light: UIColor(red: 0.53, green: 0.94, blue: 0.78, alpha: 1), dark: UIColor(red: 0.01, green: 0.15, blue: 0.16, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.93, green: 1.00, blue: 0.74, alpha: 1), dark: UIColor(red: 0.05, green: 0.24, blue: 0.22, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.52, green: 0.72, blue: 1.00, alpha: 1), dark: UIColor(red: 0.04, green: 0.08, blue: 0.28, alpha: 1))
            ]
        } else {
            colors = [
                adaptiveColor(light: UIColor(red: 0.55, green: 0.83, blue: 1.00, alpha: 1), dark: UIColor(red: 0.02, green: 0.07, blue: 0.24, alpha: 1)),
                adaptiveColor(light: UIColor(red: 1.00, green: 0.74, blue: 0.45, alpha: 1), dark: UIColor(red: 0.24, green: 0.12, blue: 0.03, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.48, green: 0.91, blue: 0.70, alpha: 1), dark: UIColor(red: 0.02, green: 0.20, blue: 0.16, alpha: 1))
            ]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }

    var panelBackgroundColor: Color {
        if selectedSubject == .capitals {
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.08, green: 0.20, blue: 0.22, alpha: 0.96)
                    : UIColor(red: 0.95, green: 1.0, blue: 0.96, alpha: 0.94)
            })
        }
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 0.96)
                : UIColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 0.94)
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
