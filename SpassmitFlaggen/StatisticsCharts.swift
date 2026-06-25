import SwiftUI
import Foundation

struct TierScoreRow: Identifiable {
    var id: String { tier.rawValue }
    let tier: MasteryTier
    let count: Int
    let value: Double
}

struct ScopeScoreRow: Identifiable {
    var id: String { title }
    let title: String
    let score: Double
    let practiced: Int
    let total: Int
}

struct PracticeBalanceRow: Identifiable {
    var id: String { title }
    let title: String
    let count: Int
    let color: Color
}

struct ScoreHistoryPoint: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(score)" }
    let date: Date
    let score: Double
}

struct PracticeBalanceHistoryPoint: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(known)-\(unknown)" }
    let date: Date
    let known: Int
    let unknown: Int
}

struct MasteryScoreCard: View {
    let title: String
    let score: Double
    let rows: [TierScoreRow]
    let language: AppLanguage
    let accentColor: Color
    let isComplete: Bool
    @Binding var isInfoPresented: Bool

    private var scoreColor: Color {
        isComplete ? Color(red: 0.96, green: 0.68, blue: 0.10) : accentColor
    }

    var body: some View {
        HStack(spacing: 16) {
            ScoreRingView(score: score, color: scoreColor)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Button {
                        isInfoPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isInfoPresented) {
                        scoreInfoView
                    }
                }

                Text(String(format: "%.1f", score * 100))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(scoreColor)
                if isComplete {
                    Label(localized("Alles auf S", "All S-ranked", language: language), systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    var scoreInfoView: some View {
        let totalCards = rows.reduce(0) { $0 + $1.count }
        let weightedPoints = rows.reduce(0.0) { $0 + ($1.value * 100 * Double($1.count)) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "function")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(scoreColor)
                    .frame(width: 32, height: 32)
                    .background(scoreColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Berechnung", "Calculation", language: language))
                        .font(.headline)
                    Text(localized("Stufenpunkte geteilt durch alle Karten", "Tier points divided by all cards", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Formel", "Formula", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("S x 100 + A x 80 + B x 60 + C x 40 + D x 20 + F x 0")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("/ \(max(totalCards, 1))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(scoreColor)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.tier.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 22)
                            .background(row.tier.color, in: RoundedRectangle(cornerRadius: 5))

                        Text(row.tier.description)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 8)

                        Text(String(format: "%.0f x %d", row.value * 100, row.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text(localized("Ergebnis", "Result", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f / %d = %.1f", weightedPoints, max(totalCards, 1), score * 100))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(scoreColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 420, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

struct ScoreRingView: View {
    let score: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(score, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

        }
    }
}

struct TierValueBreakdownChart: View {
    let rows: [TierScoreRow]
    let totalCards: Int
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Stufenwert-Verteilung", "Tier value distribution", language: language))
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                let share = totalCards == 0 ? 0 : Double(row.count) / Double(totalCards)
                HStack(spacing: 10) {
                    Text(row.tier.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 24)
                        .background(row.tier.color, in: RoundedRectangle(cornerRadius: 5))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(row.tier.color.opacity(0.12))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(row.tier.color.opacity(0.68))
                                .frame(width: max(geometry.size.width * share, row.count == 0 ? 0 : 8))
                        }
                    }
                    .frame(height: 12)
                    Text("\(row.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    Text(String(format: "%.2f", row.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ScopeScoreBarChart: View {
    let rows: [ScopeScoreRow]
    let language: AppLanguage
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Score nach Bereich", "Score by scope", language: language))
                .font(.subheadline.weight(.semibold))
            if rows.isEmpty {
                Text(localized("Keine Bereiche im aktuellen Filter.", "No scopes in the current filter.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.1f %%", row.score * 100))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(accentColor)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.12))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(accentColor.opacity(0.70))
                                    .frame(width: geometry.size.width * min(max(row.score, 0), 1))
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PracticeBalanceChart: View {
    var title: String? = nil
    var primaryLabel: String? = nil
    var showsUnknown: Bool = true
    let previousPoints: [PracticeBalanceHistoryPoint]
    let points: [PracticeBalanceHistoryPoint]
    let nextPoints: [PracticeBalanceHistoryPoint]
    let range: PracticeBalanceRange
    let maxValue: Int
    @Binding var pageOffset: Int
    @Binding var selectedPoint: PracticeBalanceHistoryPoint?
    let language: AppLanguage
    @State private var dragOffset: CGFloat = 0
    @State private var residualDragOffset: CGFloat = 0
    @State private var measuredChartWidth: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title ?? localized("Trainings-Balance", "Practice balance", language: language))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if points.isEmpty {
                Text(localized("Noch keine Trainingsdaten.", "No practice data yet.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else {
                GeometryReader { geometry in
                    let width = max(geometry.size.width, 1)
                    ZStack {
                        Canvas { context, size in
                            let plotRect = CGRect(x: 34, y: 10, width: max(size.width - 46, 1), height: max(size.height - 44, 1))
                            drawCountGrid(in: plotRect, context: &context)
                        }
                        .frame(height: 178)

                        ZStack(alignment: .topLeading) {
                            balanceTimeline(size: geometry.size)
                            balanceDateLabels(size: geometry.size)
                            selectedBalanceInfo(size: geometry.size)
                                .allowsHitTesting(false)
                            let plotRect = CGRect(x: 34, y: 10, width: max(width - 46, 1), height: max(geometry.size.height - 44, 1))
                            ForEach(Array(points.indices), id: \.self) { index in
                                Button {
                                    selectedPoint = points[index]
                                } label: {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(plotRect.width / CGFloat(max(points.count, 1)), 30), height: 178)
                                .position(x: xPosition(for: points[index].date, segmentWidth: width), y: 89)
                                .accessibilityLabel(pointAccessibilityLabel(points[index]))
                            }
                        }
                        .frame(width: width * 3, height: 178, alignment: .topLeading)
                        .offset(x: -width + residualDragOffset + dragOffset)
                        .animation(nil, value: dragOffset)
                        .clipped()
                    }
                    .clipped()
                    .onAppear {
                        measuredChartWidth = width
                    }
                    .onChange(of: width) { _, newValue in
                        measuredChartWidth = newValue
                    }
                }
                .frame(height: 178)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            dragOffset = displayDragOffset(for: value, chartWidth: measuredChartWidth) - residualDragOffset
                        }
                        .onEnded { value in
                            selectedPoint = nil
                            finishDrag(with: value, chartWidth: measuredChartWidth)
                        }
                )

                HStack(spacing: 10) {
                    Label(primaryLabel ?? localized("Gewusst", "Known", language: language), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if showsUnknown {
                        Label(localized("Nicht gewusst", "Not known", language: language), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2.weight(.semibold))

            }
        }
        .padding(.vertical, 6)
    }

    func balanceTimeline(size: CGSize) -> some View {
        Canvas { context, size in
            let segmentWidth = max(size.width / 3, 1)
            let segmentHeight = size.height
            let allPoints = previousPoints + points + nextPoints
            let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
            let knownPoints = allPoints.map { point in
                CGPoint(
                    x: xPosition(for: point.date, segmentWidth: segmentWidth),
                    y: plotRect.maxY - plotRect.height * CGFloat(point.known) / CGFloat(max(maxValue, 1))
                )
            }
            let unknownPoints = allPoints.map { point in
                CGPoint(
                    x: xPosition(for: point.date, segmentWidth: segmentWidth),
                    y: plotRect.maxY - plotRect.height * CGFloat(point.unknown) / CGFloat(max(maxValue, 1))
                )
            }

            if knownPoints.count > 1 {
                context.stroke(smoothPath(for: knownPoints), with: .color(.green), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if showsUnknown, unknownPoints.count > 1 {
                context.stroke(smoothPath(for: unknownPoints), with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            for (index, point) in knownPoints.enumerated() {
                let isSelected = allPoints.indices.contains(index) && allPoints[index].id == selectedPoint?.id
                drawDot(at: point, color: isSelected ? .primary : .green, context: &context)
            }
            if showsUnknown {
                for (index, point) in unknownPoints.enumerated() {
                    let isSelected = allPoints.indices.contains(index) && allPoints[index].id == selectedPoint?.id
                    drawDot(at: point, color: isSelected ? .primary : .red, context: &context)
                }
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func selectedBalanceInfo(size: CGSize) -> some View {
        let segmentWidth = max(size.width, 1)
        let segmentHeight = size.height

        return ZStack(alignment: .topLeading) {
            if let selectedPoint,
               let marker = balanceMarker(for: selectedPoint, segmentWidth: segmentWidth, segmentHeight: segmentHeight) {
                Text(selectedBalanceInfoText(for: selectedPoint))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .position(x: marker.x, y: max(marker.y - 28, 18))
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func balanceMarker(
        for selectedPoint: PracticeBalanceHistoryPoint,
        segmentWidth: CGFloat,
        segmentHeight: CGFloat
    ) -> CGPoint? {
        let allPoints = previousPoints + points + nextPoints
        guard allPoints.contains(where: { $0.id == selectedPoint.id }) else { return nil }
        let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
        let value = max(selectedPoint.known, selectedPoint.unknown)
        let y = plotRect.maxY - plotRect.height * CGFloat(value) / CGFloat(max(maxValue, 1))
        return CGPoint(x: xPosition(for: selectedPoint.date, segmentWidth: segmentWidth), y: y)
    }

    func selectedBalanceInfoText(for point: PracticeBalanceHistoryPoint) -> String {
        if showsUnknown {
            return "\(localized("Gewusst", "Known", language: language)) \(point.known) · \(localized("Nicht gewusst", "Not known", language: language)) \(point.unknown)"
        }
        return "\(primaryLabel ?? localized("Gelernt", "Learned", language: language)) \(point.known)"
    }

    func balanceDateLabels(size: CGSize) -> some View {
        let segmentWidth = max(size.width, 1)
        let segmentHeight = size.height
        return ZStack(alignment: .topLeading) {
            let allPoints = previousPoints + points + nextPoints
            let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
            let labelWidth = max(chartStepWidth(chartWidth: segmentWidth) * 0.95, 22)
            ForEach(Array(allPoints.enumerated()), id: \.element.id) { index, point in
                Button {
                    selectedPoint = point
                } label: {
                    Text(label(for: point.date))
                        .font(.system(size: 9, weight: point.id == selectedPoint?.id ? .semibold : .regular))
                        .foregroundStyle(point.id == selectedPoint?.id ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .frame(width: labelWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: xPosition(for: point.date, segmentWidth: segmentWidth), y: plotRect.maxY + 20)
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func balancePoints(for segmentIndex: Int) -> [PracticeBalanceHistoryPoint] {
        switch segmentIndex {
        case 0: return previousPoints
        case 1: return points
        default: return nextPoints
        }
    }

    func chartPoints(in rect: CGRect, values: [Int]) -> [CGPoint] {
        shiftedChartPoints(in: rect, values: values)
    }

    func shiftedChartPoints(in rect: CGRect, values: [Int]) -> [CGPoint] {
        let xs = xPositions(in: rect, count: values.count)
        return values.enumerated().map { index, value in
            CGPoint(
                x: xs[index],
                y: rect.maxY - rect.height * CGFloat(value) / CGFloat(maxValue)
            )
        }
    }

    func xPositions(in rect: CGRect, count: Int) -> [CGFloat] {
        guard count > 1 else { return [rect.minX] }
        let denominator = max(range.days - 1, count - 1, 1)
        return (0..<count).map { index in
            rect.minX + rect.width * CGFloat(index) / CGFloat(denominator)
        }
    }

    func xPosition(for date: Date, segmentWidth: CGFloat) -> CGFloat {
        guard let firstDate = points.first?.date else { return segmentWidth + 34 }
        let calendar = Calendar.current
        let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: calendar.startOfDay(for: date)).day ?? 0
        return segmentWidth + 34 + CGFloat(dayOffset) * chartStepWidth(chartWidth: segmentWidth)
    }

    func drawCountGrid(in rect: CGRect, context: inout GraphicsContext) {
        for fraction in [0.0, 0.5, 1.0] {
            let y = rect.maxY - rect.height * fraction
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: rect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(gridPath, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
        }
        var axisPath = Path()
        axisPath.move(to: CGPoint(x: rect.minX, y: rect.minY))
        axisPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        axisPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.stroke(axisPath, with: .color(.secondary.opacity(0.24)), lineWidth: 1)
        context.draw(Text("\(maxValue)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: 10, y: rect.minY - 6), anchor: .leading)
        context.draw(Text("0").font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: 24, y: rect.maxY - 10), anchor: .leading)
    }

    func drawDot(at point: CGPoint, color: Color, context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    func smoothPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlDistance = (current.x - previous.x) * 0.42
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + controlDistance, y: previous.y),
                control2: CGPoint(x: current.x - controlDistance, y: current.y)
            )
        }
        return path
    }

    func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .german ? "de_DE" : "en_US")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    func pointAccessibilityLabel(_ point: PracticeBalanceHistoryPoint) -> String {
        "\(label(for: point.date)), \(point.known), \(point.unknown)"
    }

    func shouldShowDateLabel(at index: Int, totalCount: Int) -> Bool {
        guard totalCount > 10 else { return true }
        let stride = max(totalCount / 6, 1)
        return index == 0 || index == totalCount - 1 || index.isMultiple(of: stride)
    }

    func displayDragOffset(for value: DragGesture.Value, chartWidth: CGFloat) -> CGFloat {
        let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.35
        guard horizontal else { return residualDragOffset }
        return boundedViewportOffset(residualDragOffset + value.translation.width, chartWidth: chartWidth)
    }

    func boundedViewportOffset(_ offset: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let stepWidth = chartStepWidth(chartWidth: chartWidth)
        let futureLimit = CGFloat(pageOffset) * stepWidth
        return max(offset, futureLimit)
    }

    func finishDrag(with value: DragGesture.Value, chartWidth: CGFloat) {
        let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.35
        guard horizontal, abs(value.translation.width) > 18 else {
            dragOffset = 0
            return
        }
        let stepWidth = chartStepWidth(chartWidth: chartWidth)
        let totalOffset = boundedViewportOffset(residualDragOffset + value.translation.width, chartWidth: chartWidth)
        let wholeSteps = Int((totalOffset / stepWidth).rounded(.towardZero))
        let proposedOffset = pageOffset - wholeSteps
        let finalOffset = min(proposedOffset, 0)
        let effectiveSteps = pageOffset - finalOffset
        let newResidualOffset = totalOffset - CGFloat(effectiveSteps) * stepWidth

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageOffset = finalOffset
            residualDragOffset = newResidualOffset
            dragOffset = 0
        }
    }

    func chartStepWidth(chartWidth: CGFloat) -> CGFloat {
        max((chartWidth - 46) / CGFloat(max(range.days - 1, 1)), 8)
    }
}

struct FlaggenbossScoreChart: View {
    let title: String
    let previousPoints: [ScoreHistoryPoint]
    let points: [ScoreHistoryPoint]
    let nextPoints: [ScoreHistoryPoint]
    let range: PracticeBalanceRange
    @Binding var pageOffset: Int
    @Binding var selectedPoint: ScoreHistoryPoint?
    let language: AppLanguage
    let accentColor: Color
    @State private var dragOffset: CGFloat = 0
    @State private var residualDragOffset: CGFloat = 0
    @State private var measuredChartWidth: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            if points.isEmpty {
                Text(localized("Noch keine Verlaufspunkte.", "No history points yet.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else {
                GeometryReader { geometry in
                    let width = max(geometry.size.width, 1)
                    ZStack {
                        Canvas { context, size in
                            let plotRect = CGRect(x: 34, y: 10, width: max(size.width - 46, 1), height: max(size.height - 44, 1))
                            drawScoreGrid(in: plotRect, context: &context)
                        }
                        .frame(height: 178)

                        ZStack(alignment: .topLeading) {
                            scoreTimeline(size: geometry.size)
                            scoreDateLabels(size: geometry.size)
                            selectedScoreInfo(size: geometry.size)
                                .allowsHitTesting(false)
                            let plotRect = CGRect(x: 34, y: 10, width: max(width - 46, 1), height: max(geometry.size.height - 44, 1))
                            ForEach(Array(zip(points.indices, chartPoints(in: plotRect, points: points, segmentWidth: width))), id: \.0) { index, point in
                                Button {
                                    selectedPoint = points[index]
                                } label: {
                                    Circle()
                                        .fill(Color.clear)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: 34, height: 34)
                                .position(x: point.x, y: point.y)
                                .accessibilityLabel(pointAccessibilityLabel(points[index]))
                            }
                        }
                        .frame(width: width * 3, height: 178, alignment: .topLeading)
                        .offset(x: -width + residualDragOffset + dragOffset)
                        .animation(nil, value: dragOffset)
                        .clipped()
                    }
                    .clipped()
                    .onAppear {
                        measuredChartWidth = width
                    }
                    .onChange(of: width) { _, newValue in
                        measuredChartWidth = newValue
                    }
                }
                .frame(height: 178)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            dragOffset = displayDragOffset(for: value, chartWidth: measuredChartWidth) - residualDragOffset
                        }
                        .onEnded { value in
                            selectedPoint = nil
                            finishDrag(with: value, chartWidth: measuredChartWidth)
                        }
                )
            }
        }
        .padding(.vertical, 6)
    }

    func scoreTimeline(size: CGSize) -> some View {
        Canvas { context, size in
            let segmentWidth = max(size.width / 3, 1)
            let segmentHeight = size.height
            let allPoints = previousPoints + points + nextPoints
            let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
            let resolvedPoints = chartPoints(in: plotRect, points: allPoints, segmentWidth: segmentWidth)
            guard let first = resolvedPoints.first, let last = resolvedPoints.last else { return }
            let smoothLine = smoothPath(for: resolvedPoints)
            let timelineRect = CGRect(x: 34, y: 10, width: max(size.width - 46, 1), height: max(size.height - 44, 1))

            var areaPath = smoothLine
            areaPath.addLine(to: CGPoint(x: last.x, y: timelineRect.maxY))
            areaPath.addLine(to: CGPoint(x: first.x, y: timelineRect.maxY))
            areaPath.closeSubpath()
            context.fill(areaPath, with: .linearGradient(
                Gradient(colors: [accentColor.opacity(0.34), accentColor.opacity(0.07)]),
                startPoint: CGPoint(x: timelineRect.midX, y: timelineRect.minY),
                endPoint: CGPoint(x: timelineRect.midX, y: timelineRect.maxY)
            ))
            context.stroke(smoothLine, with: .color(accentColor), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

            for (index, point) in resolvedPoints.enumerated() {
                let isSelected = allPoints.indices.contains(index) && allPoints[index].id == selectedPoint?.id
                let radius: CGFloat = isSelected ? 5 : 3.5
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(isSelected ? .primary : accentColor))
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func selectedScoreInfo(size: CGSize) -> some View {
        let segmentWidth = max(size.width, 1)
        let segmentHeight = size.height

        return ZStack(alignment: .topLeading) {
            if let selectedPoint,
               let marker = scoreMarker(for: selectedPoint, segmentWidth: segmentWidth, segmentHeight: segmentHeight) {
                Text(String(format: "%.1f", selectedPoint.score * 100))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(accentColor.opacity(0.24), lineWidth: 1)
                    )
                    .position(x: marker.x, y: max(marker.y - 28, 18))
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func scoreMarker(
        for selectedPoint: ScoreHistoryPoint,
        segmentWidth: CGFloat,
        segmentHeight: CGFloat
    ) -> CGPoint? {
        let allPoints = previousPoints + points + nextPoints
        guard allPoints.contains(where: { $0.id == selectedPoint.id }) else { return nil }
        let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
        return chartPoint(in: plotRect, point: selectedPoint, segmentWidth: segmentWidth)
    }

    func scoreDateLabels(size: CGSize) -> some View {
        let segmentWidth = max(size.width, 1)
        let segmentHeight = size.height
        return ZStack(alignment: .topLeading) {
            let allPoints = previousPoints + points + nextPoints
            let plotRect = CGRect(x: 34, y: 10, width: max(segmentWidth - 46, 1), height: max(segmentHeight - 44, 1))
            let labelWidth = max(chartStepWidth(chartWidth: segmentWidth) * 0.95, 22)
            ForEach(Array(zip(allPoints.indices, chartPoints(in: plotRect, points: allPoints, segmentWidth: segmentWidth))), id: \.0) { index, point in
                Button {
                    selectedPoint = allPoints[index]
                } label: {
                    Text(label(for: allPoints[index].date))
                        .font(.system(size: 9, weight: allPoints[index].id == selectedPoint?.id ? .semibold : .regular))
                        .foregroundStyle(allPoints[index].id == selectedPoint?.id ? accentColor : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .frame(width: labelWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: point.x, y: plotRect.maxY + 20)
            }
        }
        .frame(width: size.width * 3, height: 178)
    }

    func scorePoints(for segmentIndex: Int) -> [ScoreHistoryPoint] {
        switch segmentIndex {
        case 0: return previousPoints
        case 1: return points
        default: return nextPoints
        }
    }

    func chartPoints(in rect: CGRect, points bandPoints: [ScoreHistoryPoint], segmentWidth: CGFloat) -> [CGPoint] {
        guard !bandPoints.isEmpty else { return [] }
        return bandPoints.map { chartPoint(in: rect, point: $0, segmentWidth: segmentWidth) }
    }

    func chartPoint(in rect: CGRect, point: ScoreHistoryPoint, segmentWidth: CGFloat) -> CGPoint {
        let yFraction = min(max(point.score, 0), 1)
        return CGPoint(
            x: xPosition(for: point.date, segmentWidth: segmentWidth),
            y: rect.maxY - rect.height * yFraction
        )
    }

    func xPosition(for date: Date, segmentWidth: CGFloat) -> CGFloat {
        guard let firstDate = points.first?.date else { return segmentWidth + 34 }
        let calendar = Calendar.current
        let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: calendar.startOfDay(for: date)).day ?? 0
        return segmentWidth + 34 + CGFloat(dayOffset) * chartStepWidth(chartWidth: segmentWidth)
    }

    func drawScoreGrid(in rect: CGRect, context: inout GraphicsContext) {
        let axisColor = Color.secondary.opacity(0.24)
        let gridColor = Color.secondary.opacity(0.10)

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let y = rect.maxY - rect.height * fraction
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: rect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(gridPath, with: .color(gridColor), lineWidth: 1)
        }

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: rect.minX, y: rect.minY))
        axisPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        axisPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)

        drawAxisLabel("100", at: CGPoint(x: 13, y: rect.minY - 6), context: &context)
        drawAxisLabel("50", at: CGPoint(x: 18, y: rect.midY - 6), context: &context)
        drawAxisLabel("0", at: CGPoint(x: 24, y: rect.maxY - 10), context: &context)
    }

    func smoothPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlDistance = (current.x - previous.x) * 0.42
            let control1 = CGPoint(x: previous.x + controlDistance, y: previous.y)
            let control2 = CGPoint(x: current.x - controlDistance, y: current.y)
            path.addCurve(to: current, control1: control1, control2: control2)
        }
        return path
    }

    func drawAxisLabel(_ text: String, at point: CGPoint, context: inout GraphicsContext) {
        context.draw(
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary),
            at: point,
            anchor: .leading
        )
    }

    func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .german ? "de_DE" : "en_US")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    func pointAccessibilityLabel(_ point: ScoreHistoryPoint) -> String {
        "\(label(for: point.date)), \(String(format: "%.1f", point.score * 100))"
    }

    func shouldShowDateLabel(at index: Int, totalCount: Int) -> Bool {
        guard totalCount > 10 else { return true }
        let stride = max(totalCount / 6, 1)
        return index == 0 || index == totalCount - 1 || index.isMultiple(of: stride)
    }

    func displayDragOffset(for value: DragGesture.Value, chartWidth: CGFloat) -> CGFloat {
        let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.35
        guard horizontal else { return residualDragOffset }
        return boundedViewportOffset(residualDragOffset + value.translation.width, chartWidth: chartWidth)
    }

    func boundedViewportOffset(_ offset: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let stepWidth = chartStepWidth(chartWidth: chartWidth)
        let futureLimit = CGFloat(pageOffset) * stepWidth
        return max(offset, futureLimit)
    }

    func finishDrag(with value: DragGesture.Value, chartWidth: CGFloat) {
        let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.35
        guard horizontal, abs(value.translation.width) > 18 else {
            dragOffset = 0
            return
        }
        let stepWidth = chartStepWidth(chartWidth: chartWidth)
        let totalOffset = boundedViewportOffset(residualDragOffset + value.translation.width, chartWidth: chartWidth)
        let wholeSteps = Int((totalOffset / stepWidth).rounded(.towardZero))
        let proposedOffset = pageOffset - wholeSteps
        let finalOffset = min(proposedOffset, 0)
        let effectiveSteps = pageOffset - finalOffset
        let newResidualOffset = totalOffset - CGFloat(effectiveSteps) * stepWidth

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageOffset = finalOffset
            residualDragOffset = newResidualOffset
            dragOffset = 0
        }
    }

    func chartStepWidth(chartWidth: CGFloat) -> CGFloat {
        max((chartWidth - 46) / CGFloat(max(range.days - 1, 1)), 8)
    }
}

struct TierSummaryGrid: View {
    let profile: UserProfile
    let countries: [Country]
    let subject: LearningSubject
    var selectedTier: MasteryTier? = nil
    var onSelectTier: ((MasteryTier) -> Void)? = nil

    var body: some View {
        let counts = tierCounts()
        VStack(spacing: 10) {
            ForEach(MasteryTier.allCases) { tier in
                if let onSelectTier {
                    Button {
                        onSelectTier(tier)
                    } label: {
                        tierBar(tier: tier, count: counts[tier] ?? 0)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                } else {
                    tierBar(tier: tier, count: counts[tier] ?? 0)
                }
            }
        }
        .padding(.vertical, 6)
    }

    func tierCounts() -> [MasteryTier: Int] {
        Dictionary(uniqueKeysWithValues: MasteryTier.allCases.map { tier in
            (tier, countries.filter { profile.tier(for: $0, subject: subject) == tier }.count)
        })
    }

    func tierBar(tier: MasteryTier, count: Int) -> some View {
        let percentage = countries.isEmpty ? 0 : Double(count) / Double(countries.count)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(tier.rawValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 30)
                    .background(tier.color, in: RoundedRectangle(cornerRadius: 7))

                Text("Stufe \(tier.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text("\(count) · \(percent(percentage))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tier.color.opacity(0.10 + percentage * 0.18))

                    RoundedRectangle(cornerRadius: 7)
                        .fill(tier.color.opacity(0.58))
                        .frame(width: max(geometry.size.width * percentage, count == 0 ? 0 : 8))
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selectedTier == tier ? tier.color.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedTier == tier ? tier.color.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}
