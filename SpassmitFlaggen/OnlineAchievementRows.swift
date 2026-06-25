import SwiftUI
import Foundation

struct OnlinePlayerStatsRow: View {
    let rank: Int
    let stats: OnlinePlayerStats
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(rank)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(stats.playerName)
                    .font(.headline)
                Spacer()
                Text(percent(stats.accuracy))
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                Text(localized("Geübt: \(stats.totalPracticed)", "Practiced: \(stats.totalPracticed)", language: language))
                Text(localized("Gewusst: \(stats.known)", "Known: \(stats.known)", language: language))
                Text("Showmaster: \(stats.showmasterPlayed)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("S \(stats.tierS) · A \(stats.tierA) · B \(stats.tierB) · C \(stats.tierC) · D \(stats.tierD) · F \(stats.tierF)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}

struct LeagueLeaderboardRow: View {
    let rank: Int
    let player: OnlinePlayerStats
    let isCurrentPlayer: Bool
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(rank <= 3 ? .white : (isCurrentPlayer ? .green : .secondary))
                .frame(width: 30, height: 28)
                .background(rank <= 3 ? rankAccentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(localized("\(player.leaguePlayed) Runden", "\(player.leaguePlayed) rounds", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.leagueBestScore)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(rankAccentColor)
                Text(localized("Bestscore", "Best score", language: language))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, rank <= 3 ? 8 : 0)
        .background(rank <= 3 ? rankAccentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rankAccentColor.opacity(rank <= 3 ? 0.35 : 0), lineWidth: 1)
        )
    }

    var rankAccentColor: Color {
        switch rank {
        case 1: return Color(red: 0.95, green: 0.66, blue: 0.12)
        case 2: return Color(red: 0.62, green: 0.66, blue: 0.72)
        case 3: return Color(red: 0.72, green: 0.42, blue: 0.20)
        default: return .green
        }
    }
}

struct AchievementPopup: View {
    let item: AchievementItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.headline)
                .foregroundStyle(item.tint)
                .frame(width: 30, height: 30)
                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Achievement erreicht", "Achievement unlocked", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

struct AchievementRow: View {
    let item: AchievementItem
    let language: AppLanguage
    var achievedAt: Date? = nil
    var globalUnlockCount: Int? = nil
    var globalPlayerCount: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isUnlocked ? "checkmark.seal.fill" : item.iconName)
                .font(.title3)
                .foregroundStyle(item.isUnlocked ? item.tint : .secondary)
                .frame(width: 34, height: 34)
                .background((item.isUnlocked ? item.tint : Color.secondary).opacity(0.14), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    Text("\(min(item.currentValue, item.targetValue))/\(item.targetValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.isUnlocked ? item.tint : .secondary)
                }

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.isUnlocked, let achievedAt {
                    Label(
                        localized("Erreicht: \(achievementDateText(achievedAt))", "Unlocked: \(achievementDateText(achievedAt))", language: language),
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.tint)
                }

                if let globalUnlockCount, let globalPlayerCount, globalPlayerCount > 0 {
                    Label(
                        localized("Weltweit: \(globalUnlockPercent(globalUnlockCount, globalPlayerCount))", "Worldwide: \(globalUnlockPercent(globalUnlockCount, globalPlayerCount))", language: language),
                        systemImage: "globe.europe.africa.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.16))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.tint.opacity(item.isUnlocked ? 0.85 : 0.58))
                            .frame(width: max(geometry.size.width * item.progress, item.currentValue == 0 ? 0 : 8))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 6)
        .opacity(item.isUnlocked ? 1 : 0.72)
    }

    func globalUnlockPercent(_ count: Int, _ total: Int) -> String {
        guard total > 0 else { return "0 %" }
        return String(format: "%.0f %%", min(max(Double(count) / Double(total), 0), 1) * 100)
    }

    func achievementDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .german ? "de_DE" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct CompactStatTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
