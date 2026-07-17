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

struct SelectedHistoryPillFrameKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct PracticeHistoryBarEntry: Identifiable {
    let index: Int
    let mark: PracticeHistoryMark
    let change: PracticeSessionChange?

    var id: Int { index }
}

struct PracticeHistoryBar: View {
    let results: [Bool]
    let changes: [PracticeSessionChange]
    let limit: Int
    let accentColor: Color
    let selectedChangeID: UUID?
    let onSelectChange: (PracticeHistoryPreview) -> Void

    private let maximumVisibleEntries = 10

    private var allEntries: [PracticeHistoryBarEntry] {
        if limit == 0 {
            let completed = changes.enumerated().map { index, change in
                PracticeHistoryBarEntry(index: index, mark: change.wasKnown ? .known : .unknown, change: change)
            }
            return completed + [PracticeHistoryBarEntry(index: completed.count, mark: .current, change: nil)]
        }

        let total = max(limit, results.count)
        return (0..<total).map { index in
            if index < results.count {
                return PracticeHistoryBarEntry(index: index, mark: results[index] ? .known : .unknown, change: index < changes.count ? changes[index] : nil)
            }
            if index == results.count && results.count < total {
                return PracticeHistoryBarEntry(index: index, mark: .current, change: nil)
            }
            return PracticeHistoryBarEntry(index: index, mark: .pending, change: nil)
        }
    }

    private var entries: [PracticeHistoryBarEntry] {
        let completeEntries = allEntries
        guard completeEntries.count > maximumVisibleEntries else { return completeEntries }

        let focusedIndex = min(results.count, completeEntries.count - 1)
        let startIndex = min(
            max(focusedIndex - (maximumVisibleEntries - 1), 0),
            completeEntries.count - maximumVisibleEntries
        )
        return Array(completeEntries[startIndex..<(startIndex + maximumVisibleEntries)])
    }

    var body: some View {
        ScaledHistoryBarContainer(entryCount: entries.count) { pillSize, spacing in
            HStack(spacing: spacing) {
                ForEach(entries) { entry in
                    Group {
                        if let change = entry.change {
                            Button {
                                onSelectChange(PracticeHistoryPreview(change: change, index: entry.index, total: allEntries.count))
                            } label: {
                                PracticeHistoryPill(mark: entry.mark, accentColor: accentColor, isSelected: selectedChangeID == change.id, size: pillSize)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: SelectedHistoryPillFrameKey.self,
                                                value: selectedChangeID == change.id ? proxy.frame(in: .named("historyPreviewSpace")) : nil
                                            )
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Circle())
                        } else {
                            PracticeHistoryPill(
                                mark: entry.mark,
                                accentColor: accentColor,
                                isSelected: false,
                                size: pillSize,
                                animationTrigger: entry.mark == .current ? results.count : 0
                            )
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: pillSize + spacing)
                                .combined(with: .scale(scale: 0.72))
                                .combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.76), value: results.count)
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
            let isOverflowing = idealWidth > availableWidth
            let spacing = isOverflowing ? 4 : maxSpacing
            let pillSize = min(maxPillSize, max(22, (availableWidth - spacing * CGFloat(max(count - 1, 0))) / CGFloat(count)))

            content(pillSize, spacing)
                // Once the pills reach their minimum size, keep the newest
                // entries anchored on the right. The growing history then
                // leaves the bar on the left instead of hiding new entries.
                .fixedSize(horizontal: true, vertical: false)
                .frame(
                    minWidth: availableWidth,
                    maxWidth: availableWidth,
                    minHeight: maxPillSize,
                    alignment: isOverflowing ? .trailing : .center
                )
                .padding(.horizontal, horizontalPadding / 2)
                .padding(.vertical, 8)
                // Clip overflowing history horizontally only after there is
                // enough vertical room for the slightly enlarged current pill.
                .clipped()
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
    var animationTrigger: Int = 0

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
            .scaleEffect(isSelected ? 1.12 : (mark == .current ? 1.04 : 1))
            .id(mark.systemImage)
            .transition(.scale(scale: 0.72).combined(with: .opacity))
            .symbolEffect(.bounce, options: .nonRepeating, value: animationTrigger)
            .animation(.spring(response: 0.26, dampingFraction: 0.58), value: mark)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isSelected)
    }
}
