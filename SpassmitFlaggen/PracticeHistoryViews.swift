import SwiftUI
import Foundation

enum PracticeHistoryMark: Equatable {
    case known
    case unknown
    case current
    case pending
    case seen

    var systemImage: String {
        switch self {
        case .known: return "checkmark"
        case .unknown: return "xmark"
        case .current: return "questionmark"
        case .pending: return "circle"
        case .seen: return "eye.fill"
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PracticeHistoryBarMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ShowHistoryBarMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PracticeHistoryBar: View {
    let results: [Bool]
    let changes: [PracticeSessionChange]
    let limit: Int
    let accentColor: Color
    let selectedChangeID: UUID?
    let onSelectChange: (PracticeHistoryPreview) -> Void

    private var entries: [(mark: PracticeHistoryMark, change: PracticeSessionChange?)] {
        if limit == 0 {
            return changes.suffix(9).map { change in
                (change.wasKnown ? .known : .unknown, change)
            } + [(.current, nil)]
        }

        let total = max(limit, results.count)
        return (0..<total).map { index in
            if index < results.count {
                return (results[index] ? .known : .unknown, index < changes.count ? changes[index] : nil)
            }
            if index == results.count && results.count < total {
                return (.current, nil)
            }
            return (.pending, nil)
        }
    }

    var body: some View {
        ScaledHistoryBarContainer(entryCount: entries.count) { pillSize, spacing in
            HStack(spacing: spacing) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if let change = entry.change {
                        Button {
                            onSelectChange(PracticeHistoryPreview(change: change, index: index, total: entries.count))
                        } label: {
                            PracticeHistoryPill(mark: entry.mark, accentColor: accentColor, isSelected: selectedChangeID == change.id, size: pillSize)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    } else {
                        PracticeHistoryPill(mark: entry.mark, accentColor: accentColor, isSelected: false, size: pillSize)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: results)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Üben Verlauf")
    }
}

struct ScaledHistoryBarContainer<Content: View>: View {
    let entryCount: Int
    @ViewBuilder let content: (CGFloat, CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 20
            let maxSpacing: CGFloat = 7
            let maxPillSize: CGFloat = 28
            let count = max(entryCount, 1)
            let availableWidth = max(geometry.size.width - horizontalPadding, 1)
            let idealWidth = maxPillSize * CGFloat(count) + maxSpacing * CGFloat(max(count - 1, 0))
            let spacing = idealWidth > availableWidth ? 4 : maxSpacing
            let pillSize = min(maxPillSize, max(20, (availableWidth - spacing * CGFloat(max(count - 1, 0))) / CGFloat(count)))

            content(pillSize, spacing)
                .frame(maxWidth: .infinity, minHeight: maxPillSize)
                .padding(.horizontal, horizontalPadding / 2)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .frame(height: 44)
    }
}

struct PracticeHistoryPill: View {
    let mark: PracticeHistoryMark
    let accentColor: Color
    let isSelected: Bool
    var size: CGFloat = 28

    private var fillColor: Color {
        switch mark {
        case .known: return .green
        case .unknown: return .red
        case .current: return accentColor
        case .pending: return Color(.tertiarySystemFill)
        case .seen: return accentColor.opacity(0.78)
        }
    }

    private var iconColor: Color {
        mark == .pending ? .secondary : .white
    }

    var body: some View {
        Image(systemName: mark.systemImage)
            .font(.system(size: max(size * 0.46, 10), weight: .bold))
            .foregroundStyle(iconColor)
            .frame(width: size, height: size)
            .background(fillColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isSelected ? accentColor : (mark == .pending ? Color.secondary.opacity(0.18) : Color.white.opacity(0.2)), lineWidth: isSelected ? 3 : 1)
            )
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                        .padding(3)
                }
            }
            .shadow(color: isSelected ? accentColor.opacity(0.48) : .clear, radius: 8, y: 2)
            .scaleEffect(isSelected ? 1.18 : (mark == .current ? 1.08 : 1))
            .id(mark.systemImage)
            .transition(.scale(scale: 0.72).combined(with: .opacity))
            .animation(.spring(response: 0.26, dampingFraction: 0.58), value: mark)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isSelected)
    }
}

struct ShowHistoryBar: View {
    let entries: [ShowSessionEntry]
    let limit: Int
    let accentColor: Color
    let selectedEntryID: UUID?
    let onSelectEntry: (ShowHistoryPreview) -> Void

    private var visibleEntries: [ShowSessionEntry] {
        limit == 0 ? Array(entries.suffix(9)) : entries
    }

    private var totalSlots: Int {
        limit == 0 ? max(visibleEntries.count + 1, 1) : max(limit, entries.count)
    }

    var body: some View {
        ScaledHistoryBarContainer(entryCount: totalSlots) { pillSize, spacing in
            HStack(spacing: spacing) {
                ForEach(0..<totalSlots, id: \.self) { index in
                    if index < visibleEntries.count {
                        let entry = visibleEntries[index]
                        Button {
                            onSelectEntry(ShowHistoryPreview(entry: entry, index: index, total: totalSlots))
                        } label: {
                            PracticeHistoryPill(mark: .seen, accentColor: accentColor, isSelected: selectedEntryID == entry.id, size: pillSize)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    } else if limit == 0 || index == entries.count {
                        PracticeHistoryPill(mark: .current, accentColor: accentColor, isSelected: false, size: pillSize)
                    } else {
                        PracticeHistoryPill(mark: .pending, accentColor: accentColor, isSelected: false, size: pillSize)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: entries.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Showmaster Verlauf")
    }
}

