import SwiftUI
import Foundation

struct FreeTierCountryRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FlagImage(country: country, width: 32, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedCountryName(country, language: language))
                        .font(.headline)
                    if subject == .capitals {
                        Text(capital)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(localized("Stufe \(stats.tier.rawValue)", "Level \(stats.tier.rawValue)", language: language))

                    .font(.headline)
                    .foregroundStyle(stats.tier.color)
            }

            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subject == .capitals ? localized("Hauptstadt gesehen: \(stats.cardReviews)", "Capital seen: \(stats.cardReviews)", language: language) : localized("Gesehen: \(stats.cardReviews)", "Seen: \(stats.cardReviews)", language: language))
                    Text(subject == .capitals ? localized("Hauptstadt gewusst: \(stats.cardKnown)", "Capital known: \(stats.cardKnown)", language: language) : localized("Gewusst: \(stats.cardKnown)", "Known: \(stats.cardKnown)", language: language))
                    Text(localized("Verlauf und Detailwerte", "History and detailed values", language: language))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .blur(radius: 4)
                .opacity(0.48)

                Label(localized("Details", "Details", language: language), systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

struct STierHistorySparkline: View {
    let values: [Int]
    let maxValue: Int
    let accentColor: Color

    var body: some View {
        Canvas { context, size in
            let samples = values.isEmpty ? [0] : values
            let maxY = max(maxValue, samples.max() ?? 1, 1)
            let stepX = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
            let points = samples.enumerated().map { index, value in
                let x = CGFloat(index) * stepX
                let normalized = CGFloat(value) / CGFloat(maxY)
                let y = size.height - (normalized * max(size.height - 4, 1)) - 2
                return CGPoint(x: x, y: y)
            }

            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for point in points {
                fillPath.addLine(to: point)
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(accentColor.opacity(0.12)))

            var linePath = Path()
            if let first = points.first {
                linePath.move(to: first)
                for point in points.dropFirst() {
                    linePath.addLine(to: point)
                }
            }
            context.stroke(linePath, with: .color(accentColor.opacity(0.85)), lineWidth: 2)
        }
        .overlay(alignment: .topLeading) {
            Text("S")
                .font(.caption2.weight(.bold))
                .foregroundStyle(accentColor)
        }
        .accessibilityHidden(true)
    }
}

struct SLevelBar: View {
    let value: Int
    let total: Int
    let accentColor: Color

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(accentColor.opacity(0.82))
                    .frame(width: max(geometry.size.width * progress, value == 0 ? 0 : 8))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ComparisonStatRow: View {
    let title: String
    let ownValue: String
    let otherValue: String
    let otherName: String
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Du", "You", language: language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ownValue)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(otherName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(otherValue)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TierHistoryView: View {
    let stats: CountryStats
    let language: AppLanguage

    private let tierOrder: [MasteryTier] = [.s, .a, .b, .c, .d, .f]

    var visibleHistory: [TierHistoryEntry] {
        let storedHistory = stats.tierHistory ?? []
        let history = storedHistory.isEmpty ? [TierHistoryEntry(date: stats.lastPracticedAt ?? Date(), tier: stats.tier)] : storedHistory
        return Array(oneEntryPerDay(from: history).suffix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("Verlauf", "History", language: language))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Canvas { context, size in
                let leftPadding: CGFloat = 26
                let rightPadding: CGFloat = 6
                let topPadding: CGFloat = 8
                let bottomPadding: CGFloat = 20
                let graphWidth = max(size.width - leftPadding - rightPadding, 1)
                let graphHeight = max(size.height - topPadding - bottomPadding, 1)
                let entries = visibleHistory

                for (index, tier) in tierOrder.enumerated() {
                    let y = yPosition(for: tier, top: topPadding, height: graphHeight)
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: leftPadding, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width - rightPadding, y: y))
                    context.stroke(gridPath, with: .color(.secondary.opacity(0.16)), lineWidth: 1)

                    let label = Text(tier.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tier.color)
                    context.draw(label, at: CGPoint(x: 9, y: y), anchor: .center)

                    if index == tierOrder.count - 1 {
                        var axisPath = Path()
                        axisPath.move(to: CGPoint(x: leftPadding, y: topPadding))
                        axisPath.addLine(to: CGPoint(x: leftPadding, y: topPadding + graphHeight))
                        axisPath.addLine(to: CGPoint(x: size.width - rightPadding, y: topPadding + graphHeight))
                        context.stroke(axisPath, with: .color(.secondary.opacity(0.32)), lineWidth: 1)
                    }
                }

                let points = entries.enumerated().map { index, entry in
                    CGPoint(
                        x: xPosition(for: index, count: entries.count, left: leftPadding, width: graphWidth),
                        y: yPosition(for: entry.tier, top: topPadding, height: graphHeight)
                    )
                }

                if points.count > 1 {
                    var linePath = Path()
                    linePath.move(to: points[0])
                    for point in points.dropFirst() {
                        linePath.addLine(to: point)
                    }
                    context.stroke(linePath, with: .color(.primary.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                for (index, entry) in entries.enumerated() {
                    let point = points[index]
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(entry.tier.color))

                    if index == 0 || index == entries.count - 1 || entries.count <= 4 {
                        let dateLabel = Text(shortDate(entry.date))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        context.draw(dateLabel, at: CGPoint(x: point.x, y: size.height - 6), anchor: .center)
                    }
                }
            }
            .frame(height: 118)
            .padding(.vertical, 4)
        }
        .padding(.top, 2)
    }

    func xPosition(for index: Int, count: Int, left: CGFloat, width: CGFloat) -> CGFloat {
        guard count > 1 else { return left + width / 2 }
        return left + width * CGFloat(index) / CGFloat(count - 1)
    }

    func yPosition(for tier: MasteryTier, top: CGFloat, height: CGFloat) -> CGFloat {
        let index = tierOrder.firstIndex(of: tier) ?? tierOrder.count - 1
        return top + height * CGFloat(index) / CGFloat(max(tierOrder.count - 1, 1))
    }

    func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .german ? Locale(identifier: "de_DE") : Locale(identifier: "en_US")
        formatter.dateFormat = "d.M."
        return formatter.string(from: date)
    }

    func oneEntryPerDay(from history: [TierHistoryEntry]) -> [TierHistoryEntry] {
        let calendar = Calendar.current
        let sortedHistory = history.sorted { $0.date < $1.date }
        var entriesByDay: [String: TierHistoryEntry] = [:]

        for entry in sortedHistory {
            let components = calendar.dateComponents([.year, .month, .day], from: entry.date)
            let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            entriesByDay[dayKey] = entry
        }

        return entriesByDay.values.sorted { $0.date < $1.date }
    }
}

struct CompactCountryStatsRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String

    var hasBeenSeen: Bool { stats.cardReviews > 0 }

    var body: some View {
        HStack(spacing: 10) {
            FlagImage(country: country, width: 34, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(localizedCountryName(country, language: language))
                    .font(.headline)
                if subject == .capitals {
                    Text(capital)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(stats.tier.rawValue)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 28)
                .background(stats.tier.color, in: RoundedRectangle(cornerRadius: 7))

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(hasBeenSeen ? 1 : 0.46)
    }
}

struct CountryStatsRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    var showsHeader: Bool = true

    var hasBeenSeen: Bool { stats.cardReviews > 0 }
    var cardAccuracyText: String { hasBeenSeen ? percent(stats.cardAccuracy) : "-" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack {
                    FlagImage(country: country, width: 32, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedCountryName(country, language: language))
                            .font(.headline)
                        if subject == .capitals {
                            Text(capital)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(localized("Stufe \(stats.tier.rawValue)", "Level \(stats.tier.rawValue)", language: language))
                        .font(.headline)
                        .foregroundStyle(stats.tier.color)
                }

                Text(localizedContinent(country.continent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                if subject == .capitals {
                    Text(localized("Hauptstadt gesehen: \(stats.cardReviews)", "Capital seen: \(stats.cardReviews)", language: language))
                    Text(localized("Hauptstadt gewusst: \(stats.cardKnown)", "Capital known: \(stats.cardKnown)", language: language))
                    Text(localized("Hauptstadt nicht gewusst: \(stats.cardUnknown)", "Capital not known: \(stats.cardUnknown)", language: language))
                    Text(localized("Im Showmaster gespielt: \(stats.showmasterPlayed)", "Played in Showmaster: \(stats.showmasterPlayed)", language: language))
                    Text(localized("Hauptstadt-Quote: \(cardAccuracyText)", "Capital known rate: \(cardAccuracyText)", language: language))
                } else {
                    Text(localized("Gesehen: \(stats.cardReviews)", "Seen: \(stats.cardReviews)", language: language))
                    Text(localized("Gewusst: \(stats.cardKnown)", "Known: \(stats.cardKnown)", language: language))
                    Text(localized("Nicht gewusst: \(stats.cardUnknown)", "Not known: \(stats.cardUnknown)", language: language))
                    Text(localized("Im Showmaster gespielt: \(stats.showmasterPlayed)", "Played in Showmaster: \(stats.showmasterPlayed)", language: language))
                    Text(localized("Gewusst-Quote: \(cardAccuracyText)", "Known rate: \(cardAccuracyText)", language: language))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            TierHistoryView(stats: stats, language: language)
        }
        .padding(.vertical, 4)
        .opacity(hasBeenSeen ? 1 : 0.46)
    }

    func localizedContinent(_ continent: String) -> String {
        switch continent {
        case "Afrika": return localized("Afrika", "Africa", language: language)
        case "Asien": return localized("Asien", "Asia", language: language)
        case "Europa": return localized("Europa", "Europe", language: language)
        case "Nordamerika": return localized("Nordamerika", "North America", language: language)
        case "Ozeanien": return localized("Ozeanien", "Oceania", language: language)
        case "Südamerika": return localized("Südamerika", "South America", language: language)
        default: return continent
        }
    }

    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
    func seconds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f s", value)
    }
}
