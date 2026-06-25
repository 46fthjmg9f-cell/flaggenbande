import SwiftUI

extension ContentView {
    var decayPopupIsPresented: Binding<Bool> {
        Binding(
            get: { tierDecayPopup != nil },
            set: { isPresented in
                if !isPresented {
                    tierDecayPopup = nil
                }
            }
        )
    }

    var decayPopupTitle: String {
        L("Stufen angepasst", "Levels adjusted")
    }

    var decayPopupMessage: String {
        guard let tierDecayPopup else { return "" }
        let dayText = tierDecayPopup.maxDaysSinceLastPractice == 1 ? L("Tag", "day") : L("Tagen", "days")
        let intro = L("Zuletzt gelernt vor \(tierDecayPopup.maxDaysSinceLastPractice) \(dayText).", "Last practiced \(tierDecayPopup.maxDaysSinceLastPractice) \(dayText) ago.")
        let lines = tierDecayPopup.groupedChanges.map { group in
            L("\(group.count) von \(group.from.rawValue) auf \(group.to.rawValue)", "\(group.count) from \(group.from.rawValue) to \(group.to.rawValue)")
        }
        .joined(separator: "\n")

        return "\(intro)\n\(lines)"
    }
}
