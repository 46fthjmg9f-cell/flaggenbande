import SwiftUI
import Foundation
import UIKit

struct MiniLocationGlobe: View {
    let country: Country
    let accentColor: Color
    @State private var boundaryData: GlobeBoundaryData?
    @State private var localSnapshot: MiniLocationSnapshot?
    @State private var isLoadingBoundaries = false
    @State private var loadingPulse = false

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let globeRect = rect.insetBy(dx: 1, dy: 1)
            let circlePath = Path(ellipseIn: globeRect)

            context.fill(
                circlePath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.05, green: 0.25, blue: 0.42),
                        Color(red: 0.03, green: 0.13, blue: 0.26)
                    ]),
                    startPoint: CGPoint(x: globeRect.minX, y: globeRect.minY),
                    endPoint: CGPoint(x: globeRect.maxX, y: globeRect.maxY)
                )
            )

            context.clip(to: circlePath)
            drawGrid(in: &context, size: size)

            guard let boundaryData else {
                if let localSnapshot {
                    drawLocalSnapshot(localSnapshot, in: &context, size: size)
                } else {
                    drawFallbackFocus(in: &context, size: size)
                }
                return
            }

            let availableCodes = Set(allPracticeCountries.map(\.code))
            let selectedRings = boundaryData.ringsByCountryCode[country.code] ?? []
            guard let focusBounds = miniGlobeFocusBounds(for: selectedRings, fallbackCenter: boundaryData.centroidsByCountryCode[country.code] ?? fallbackCoordinate) else {
                drawFallbackFocus(in: &context, size: size)
                return
            }

            for code in availableCodes where code != country.code {
                guard let rings = boundaryData.ringsByCountryCode[code] else { continue }
                for ring in rings {
                    let path = mapPath(for: ring, in: focusBounds, size: size)
                    guard !path.boundingRect.isNull, path.boundingRect.intersects(rect.insetBy(dx: -8, dy: -8)) else { continue }
                    context.fill(path, with: .color(Color.white.opacity(0.15)))
                    context.stroke(path, with: .color(Color.white.opacity(0.18)), lineWidth: 0.35)
                }
            }

            let selectedPaths = selectedRings.map { mapPath(for: $0, in: focusBounds, size: size) }
            let selectedBounds = selectedPaths.reduce(CGRect.null) { $0.union($1.boundingRect) }

            for path in selectedPaths {
                context.fill(path, with: .color(accentColor.opacity(0.97)))
                context.stroke(path, with: .color(.white), lineWidth: 2.2)
                context.stroke(path, with: .color(accentColor), lineWidth: 0.9)
            }

            if selectedBounds.isNull || min(selectedBounds.width, selectedBounds.height) < min(size.width, size.height) * 0.14 {
                drawFocusBeacon(in: &context, size: size)
            }

            context.stroke(circlePath, with: .color(Color.white.opacity(0.52)), lineWidth: 1)
            context.stroke(circlePath, with: .color(accentColor.opacity(0.36)), lineWidth: 2)
        }
        .overlay {
            if isLoadingBoundaries && boundaryData == nil && localSnapshot == nil {
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(loadingPulse ? 0.18 : 0.52), lineWidth: 2)
                        .scaleEffect(loadingPulse ? 1.18 : 0.82)
                    ProgressView()
                        .scaleEffect(0.62)
                        .tint(.white)
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(country.code)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                )
                .offset(x: 3, y: 3)
        }
        .onAppear {
            startLoadingPulse()
            loadBoundariesIfNeeded()
        }
        .onChange(of: country.code) { _, _ in
            boundaryData = nil
            localSnapshot = nil
            startLoadingPulse()
            loadBoundariesIfNeeded()
        }
    }

    private var fallbackCoordinate: GlobeCoordinate {
        switch country.continent {
        case "Afrika": return GlobeCoordinate(latitude: 2, longitude: 20)
        case "Asien": return GlobeCoordinate(latitude: 32, longitude: 86)
        case "Europa": return GlobeCoordinate(latitude: 52, longitude: 15)
        case "Nordamerika": return GlobeCoordinate(latitude: 46, longitude: -102)
        case "Ozeanien": return GlobeCoordinate(latitude: -25, longitude: 135)
        case "Südamerika": return GlobeCoordinate(latitude: -16, longitude: -60)
        case partiallyRecognizedCategory: return GlobeCoordinate(latitude: 32, longitude: 35)
        default: return GlobeCoordinate(latitude: 20, longitude: 0)
        }
    }

    private func loadBoundariesIfNeeded() {
        localSnapshot = MiniLocationSnapshotStore.snapshot(for: country.code)
        if localSnapshot != nil {
            isLoadingBoundaries = false
        }

        if let cachedData = GlobeBoundaryCache.data, GlobeBoundaryCache.source == globeBoundarySource {
            boundaryData = cachedData
            cacheSnapshot(from: cachedData)
            isLoadingBoundaries = false
            return
        }

        if let localData = GlobeBoundaryCache.loadLocalData(), let parsedData = GlobeBoundaryData.parse(data: localData) {
            GlobeBoundaryCache.source = globeBoundarySource
            GlobeBoundaryCache.data = parsedData
            boundaryData = parsedData
            cacheSnapshot(from: parsedData)
            isLoadingBoundaries = false
            return
        }

        guard boundaryData == nil, let url = URL(string: globeBoundaryURLString) else { return }
        isLoadingBoundaries = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let parsedData = GlobeBoundaryData.parse(data: data) else {
                DispatchQueue.main.async {
                    isLoadingBoundaries = false
                }
                return
            }
            GlobeBoundaryCache.storeLocalData(data)
            DispatchQueue.main.async {
                GlobeBoundaryCache.source = globeBoundarySource
                GlobeBoundaryCache.data = parsedData
                boundaryData = parsedData
                cacheSnapshot(from: parsedData)
                isLoadingBoundaries = false
            }
        }.resume()
    }

    private func startLoadingPulse() {
        guard boundaryData == nil && localSnapshot == nil else { return }
        isLoadingBoundaries = true
        loadingPulse = false
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            loadingPulse = true
        }
    }

    private func cacheSnapshot(from boundaryData: GlobeBoundaryData) {
        let rings = boundaryData.ringsByCountryCode[country.code] ?? []
        guard let focusBounds = miniGlobeFocusBounds(for: rings, fallbackCenter: boundaryData.centroidsByCountryCode[country.code] ?? fallbackCoordinate) else { return }
        let snapshot = MiniLocationSnapshot(countryCode: country.code, rings: rings, bounds: MiniLocationSnapshotBounds(focusBounds))
        MiniLocationSnapshotStore.store(snapshot)
        localSnapshot = snapshot
    }

    private func drawFallbackFocus(in context: inout GraphicsContext, size: CGSize) {
        drawFocusBeacon(in: &context, size: size)
    }

    private func drawFocusBeacon(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(accentColor.opacity(0.28)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(accentColor))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.92)), lineWidth: 1.6)
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)), with: .color(accentColor.opacity(0.5)), lineWidth: 1)
    }

    private func drawLocalSnapshot(_ snapshot: MiniLocationSnapshot, in context: inout GraphicsContext, size: CGSize) {
        let bounds = snapshot.bounds.cgRect
        let selectedPaths = snapshot.rings.map { mapPath(for: $0, in: bounds, size: size) }
        let selectedBounds = selectedPaths.reduce(CGRect.null) { $0.union($1.boundingRect) }

        for path in selectedPaths {
            context.fill(path, with: .color(accentColor.opacity(0.97)))
            context.stroke(path, with: .color(.white), lineWidth: 2.2)
            context.stroke(path, with: .color(accentColor), lineWidth: 0.9)
        }

        if selectedBounds.isNull || min(selectedBounds.width, selectedBounds.height) < min(size.width, size.height) * 0.14 {
            drawFocusBeacon(in: &context, size: size)
        }
    }

    private func miniGlobeFocusBounds(for rings: [[GlobeCoordinate]], fallbackCenter: GlobeCoordinate) -> CGRect? {
        let coordinates = rings.flatMap { $0 }
        guard !coordinates.isEmpty else {
            return CGRect(x: fallbackCenter.longitude - 9, y: fallbackCenter.latitude - 9, width: 18, height: 18)
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? fallbackCenter.latitude
        let maximumLatitude = latitudes.max() ?? fallbackCenter.latitude
        let minimumLongitude = longitudes.min() ?? fallbackCenter.longitude
        let maximumLongitude = longitudes.max() ?? fallbackCenter.longitude
        let centerLatitude = (minimumLatitude + maximumLatitude) / 2
        let centerLongitude = (minimumLongitude + maximumLongitude) / 2
        let latitudeSpan = max(maximumLatitude - minimumLatitude, 0.6)
        let longitudeSpan = max(maximumLongitude - minimumLongitude, 0.6)
        let span = min(max(max(latitudeSpan, longitudeSpan) * 2.45, 16), 130)

        return CGRect(
            x: centerLongitude - span / 2,
            y: centerLatitude - span / 2,
            width: span,
            height: span
        )
    }

    private func mapPath(for ring: [GlobeCoordinate], in bounds: CGRect, size: CGSize) -> Path {
        var path = Path()
        guard bounds.width > 0, bounds.height > 0 else { return path }
        let mapRect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.08)

        for (index, coordinate) in ring.enumerated() {
            let point = CGPoint(
                x: mapRect.minX + CGFloat((coordinate.longitude - bounds.minX) / bounds.width) * mapRect.width,
                y: mapRect.minY + CGFloat((bounds.maxY - coordinate.latitude) / bounds.height) * mapRect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] {
            var latitudePath = Path()
            latitudePath.addEllipse(in: CGRect(
                x: size.width * 0.08,
                y: size.height * fraction - size.height * 0.035,
                width: size.width * 0.84,
                height: size.height * 0.07
            ))
            context.stroke(latitudePath, with: .color(Color.white.opacity(0.14)), lineWidth: 0.6)
        }

        for fraction in [0.32, 0.5, 0.68] {
            var longitudePath = Path()
            longitudePath.addEllipse(in: CGRect(
                x: size.width * fraction - size.width * 0.04,
                y: size.height * 0.08,
                width: size.width * 0.08,
                height: size.height * 0.84
            ))
            context.stroke(longitudePath, with: .color(Color.white.opacity(0.14)), lineWidth: 0.6)
        }
    }

    private func globePath(for ring: [GlobeCoordinate], center: GlobeCoordinate, size: CGSize, focusScale: CGFloat) -> Path {
        var path = Path()
        var isDrawing = false

        for coordinate in ring {
            guard let point = projectedPoint(for: coordinate, center: center, size: size, focusScale: focusScale) else {
                isDrawing = false
                continue
            }

            if isDrawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                isDrawing = true
            }
        }

        path.closeSubpath()
        return path
    }

    private func projectedPoint(for coordinate: GlobeCoordinate, center: GlobeCoordinate, size: CGSize, focusScale: CGFloat) -> CGPoint? {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let centerLatitude = center.latitude * .pi / 180
        let centerLongitude = center.longitude * .pi / 180
        let deltaLongitude = longitude - centerLongitude
        let visible = sin(centerLatitude) * sin(latitude) + cos(centerLatitude) * cos(latitude) * cos(deltaLongitude)

        guard visible >= -0.08 else { return nil }

        let radius = min(size.width, size.height) * 0.43 * focusScale
        let x = radius * cos(latitude) * sin(deltaLongitude)
        let y = -radius * (cos(centerLatitude) * sin(latitude) - sin(centerLatitude) * cos(latitude) * cos(deltaLongitude))

        return CGPoint(x: size.width / 2 + x, y: size.height / 2 + y)
    }
}

struct MiniLocationSnapshot: Codable {
    let countryCode: String
    let rings: [[GlobeCoordinate]]
    let bounds: MiniLocationSnapshotBounds
}

struct MiniLocationSnapshotBounds: Codable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        minX = Double(rect.minX)
        minY = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

enum MiniLocationSnapshotStore {
    private static let storageKey = "miniLocationSnapshotsV1"

    static func snapshot(for countryCode: String) -> MiniLocationSnapshot? {
        snapshots()[countryCode]
    }

    static func store(_ snapshot: MiniLocationSnapshot) {
        var currentSnapshots = snapshots()
        currentSnapshots[snapshot.countryCode] = snapshot
        guard let data = try? JSONEncoder().encode(currentSnapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func snapshots() -> [String: MiniLocationSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: MiniLocationSnapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

struct StartupScreen: View {
    let language: AppLanguage
    @State private var logoScale: CGFloat = 0.88
    @State private var logoOpacity: Double = 0
    @State private var contentOffset: CGFloat = 24
    @State private var gradientFloatsUp: Bool = false

    var tealAccentColor: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.88, blue: 0.86, alpha: 1)
                : UIColor(red: 0.0, green: 0.62, blue: 0.58, alpha: 1)
        })
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.01, green: 0.10, blue: 0.22, alpha: 1)
                                : UIColor(red: 0.56, green: 0.85, blue: 1.00, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.00, green: 0.24, blue: 0.22, alpha: 1)
                                : UIColor(red: 0.48, green: 0.94, blue: 0.76, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.30, green: 0.13, blue: 0.03, alpha: 1)
                                : UIColor(red: 1.00, green: 0.73, blue: 0.42, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.03, green: 0.07, blue: 0.26, alpha: 1)
                                : UIColor(red: 0.42, green: 0.64, blue: 1.00, alpha: 1)
                        })
                    ],
                    startPoint: gradientFloatsUp ? .bottomLeading : .topLeading,
                    endPoint: gradientFloatsUp ? .topTrailing : .bottomTrailing
                )
                .frame(width: geometry.size.width, height: geometry.size.height * 1.7)
                .offset(y: gradientFloatsUp ? -geometry.size.height * 0.42 : -geometry.size.height * 0.04)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.45), value: gradientFloatsUp)
            }

            VStack(spacing: 18) {
                Image(systemName: "map.fill")
                    .font(.system(size: 104, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: tealAccentColor.opacity(0.35), radius: 22, y: 10)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text("Flaggenbande")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .opacity(logoOpacity)
            }
            .offset(y: contentOffset)
            .padding()
        }
        .onAppear {
            gradientFloatsUp = true
            withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) {
                logoScale = 1
                logoOpacity = 1
                contentOffset = 0
            }
        }
    }
}

struct PracticeRecapView: View {
    let startCounts: [MasteryTier: Int]
    let endCounts: [MasteryTier: Int]
    let known: Int
    let unknown: Int
    let improved: Int
    let changes: [PracticeSessionChange]
    let language: AppLanguage
    let accentColor: Color
    let onRepeat: () -> Void
    let onDismiss: () -> Void
    @State private var showsAllChanges: Bool = false

    var total: Int { known + unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Zusammenfassung", "Summary", language: language))
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                recapStat(title: localized("Gewusst", "Known", language: language), value: known, color: .green)
                recapStat(title: localized("Nicht gewusst", "Not known", language: language), value: unknown, color: .red)
                recapStat(title: localized("Verbessert", "Improved", language: language), value: improved, color: accentColor)
            }

            Text(localized("Unten findest du die Sessionstatistiken und alle Stufenwechsel.", "Below you can see the session stats and every level change.", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onRepeat()
            } label: {
                Text(localized("Weitere 10 üben", "Practice 10 more", language: language))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            sessionDetails
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var sessionDetails: some View {
        let visibleChanges = showsAllChanges ? changes : Array(changes.prefix(5))
        let hiddenChangeCount = max(changes.count - visibleChanges.count, 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text(localized("Sessionstatistiken", "Session stats", language: language))
                .font(.subheadline.weight(.bold))

            if changes.isEmpty {
                Text(localized("Keine Stufenwechsel in dieser Session.", "No level changes in this session.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleChanges) { change in
                    let didImprove = isImprovement(change)
                    HStack(spacing: 10) {
                        Image(systemName: change.wasKnown ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(change.wasKnown ? .green : .red)
                            .frame(width: 20)
                        Text(localizedCountryName(change.country, language: language))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 6)
                        HStack(spacing: 6) {
                            tierBadge(change.fromTier)
                            Image(systemName: didImprove ? "arrow.up.right" : "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(didImprove ? .green : .secondary)
                            tierBadge(change.toTier)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(recapChangeBackground(for: change), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(didImprove ? Color.green.opacity(0.42) : Color.clear, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if hiddenChangeCount > 0 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showsAllChanges = true
                        }
                    } label: {
                        Label(localized("Alle \(changes.count) anzeigen", "Show all \(changes.count)", language: language), systemImage: "chevron.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(accentColor)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func tierBadge(_ tier: MasteryTier) -> some View {
        Text(tier.rawValue)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 26, height: 24)
            .background(tier.color, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }

    func recapChangeBackground(for change: PracticeSessionChange) -> Color {
        if isImprovement(change) {
            return Color.green.opacity(0.16)
        }
        if isDecline(change) {
            return Color.red.opacity(0.08)
        }
        return Color(.tertiarySystemFill)
    }

    func isImprovement(_ change: PracticeSessionChange) -> Bool {
        tierScore(change.toTier) > tierScore(change.fromTier)
    }

    func isDecline(_ change: PracticeSessionChange) -> Bool {
        tierScore(change.toTier) < tierScore(change.fromTier)
    }

    func tierScore(_ tier: MasteryTier) -> Int {
        switch tier {
        case .f: return 0
        case .d: return 1
        case .c: return 2
        case .b: return 3
        case .a: return 4
        case .s: return 5
        }
    }

    func recapStat(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FlipCard: View {
    let country: Country
    let isFlipped: Bool
    let hasGoldAura: Bool
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    @State private var auraPulse: Bool = false

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

    var body: some View {
        ZStack {
            if hasGoldAura {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(auraPulse ? 0.34 : 0.14))
                    .blur(radius: auraPulse ? 22 : 10)
                    .scaleEffect(auraPulse ? 1.04 : 0.96)
            }

            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: hasGoldAura ? .yellow.opacity(0.45) : .black.opacity(0.12), radius: hasGoldAura ? 16 : 10, y: 4)

            if isFlipped {
                VStack(spacing: 10) {
                    Text(subject == .countries ? localizedCountryName(country, language: language) : capital)
                        .font(.title)
                        .bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                    if subject == .capitals {
                        Text("[\(capitalPronunciation(for: country, capital: capital))]")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    if subject == .countries {
                        Text(localizedContinent(country.continent))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        FlagImage(
                            country: country,
                            width: geometry.size.width,
                            height: subject == .capitals ? 198 : 240
                        )
                        if subject == .capitals {
                            Text(localizedCountryName(country, language: language))
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .onAppear {
            auraPulse = false
            if hasGoldAura {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    auraPulse = true
                }
            }
        }
        .onChange(of: hasGoldAura) { _, newValue in
            auraPulse = false
            if newValue {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    auraPulse = true
                }
            }
        }
    }
}

struct FlagImage: View {
    let country: Country
    let width: CGFloat
    let height: CGFloat
    var isZoomEnabled: Bool = true
    @State private var image: UIImage?
    @State private var didFailLoading = false

    var body: some View {
        Group {
            if let image {
                if isZoomEnabled {
                    ZoomableFlagImageView(image: image)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipped()
                }
            } else if didFailLoading {
                Image(systemName: "flag.slash")
                    .font(.system(size: min(width, height) * 0.45))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .task(id: country.code) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url = country.flagImageURL else {
            image = nil
            didFailLoading = true
            return
        }

        if let cachedImage = FlagImageCache.shared.image(for: url) {
            image = cachedImage
            didFailLoading = false
            return
        }

        image = nil
        didFailLoading = false
        do {
            let loadedImage = try await FlagImageCache.shared.loadImage(from: url)
            guard !Task.isCancelled else { return }
            image = loadedImage
        } catch {
            guard !Task.isCancelled else { return }
            didFailLoading = true
        }
    }
}

enum FlagZoomInteractionState {
    static var isPinching = false
}

struct ZoomableFlagImageView: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .background {
                WindowPinchGestureReader(image: image)
            }
    }
}

private struct WindowPinchGestureReader: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }

    func makeUIView(context: Context) -> PinchMarkerView {
        let view = PinchMarkerView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onMoveToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.attachIfPossible()
        }
        context.coordinator.markerView = view
        return view
    }

    func updateUIView(_ uiView: PinchMarkerView, context: Context) {
        context.coordinator.markerView = uiView
        context.coordinator.updateImage(image)
        uiView.onMoveToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.attachIfPossible()
        }
        context.coordinator.attachIfPossible()
    }

    final class PinchMarkerView: UIView {
        var onMoveToWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var image: UIImage
        weak var markerView: UIView?
        private weak var attachedView: UIView?
        private var overlayImageView: UIImageView?
        private var initialOverlayFrame: CGRect = .zero
        private var initialPinchLocation: CGPoint = .zero
        private var isHandlingPinch = false
        private let hitSlop: CGFloat = 24

        private lazy var pinchGesture: UIPinchGestureRecognizer = {
            let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = true
            gesture.delaysTouchesEnded = true
            gesture.delegate = self
            return gesture
        }()

        init(image: UIImage) {
            self.image = image
        }

        func updateImage(_ newImage: UIImage) {
            guard image !== newImage else { return }
            image = newImage
            overlayImageView?.removeFromSuperview()
            overlayImageView = nil
            isHandlingPinch = false
            FlagZoomInteractionState.isPinching = false
        }

        func attachIfPossible() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let markerView = self.markerView, let targetView = markerView.window else { return }
                guard self.attachedView !== targetView else { return }
                self.attachedView?.removeGestureRecognizer(self.pinchGesture)
                targetView.addGestureRecognizer(self.pinchGesture)
                self.attachedView = targetView
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let markerView, let window = markerView.window else { return }
            let markerLocation = gesture.location(in: markerView)

            switch gesture.state {
            case .began:
                guard expandedHitRect(for: markerView).contains(markerLocation) else { return }
                isHandlingPinch = true
                FlagZoomInteractionState.isPinching = true
                initialPinchLocation = gesture.location(in: window)
                beginOverlay(in: window, from: markerView)
                gesture.scale = 1
            case .changed:
                guard isHandlingPinch, let overlayImageView else { return }
                let scale = min(max(gesture.scale, 1), 4.8)
                let windowLocation = gesture.location(in: window)
                overlayImageView.center = CGPoint(
                    x: initialOverlayFrame.midX + (windowLocation.x - initialPinchLocation.x),
                    y: initialOverlayFrame.midY + (windowLocation.y - initialPinchLocation.y)
                )
                overlayImageView.transform = CGAffineTransform(scaleX: scale, y: scale)
            case .ended, .cancelled, .failed:
                guard isHandlingPinch else { return }
                endOverlay()
                isHandlingPinch = false
                gesture.scale = 1
            default:
                break
            }
        }

        private func beginOverlay(in window: UIView, from markerView: UIView) {
            overlayImageView?.removeFromSuperview()
            let markerFrame = markerView.convert(markerView.bounds, to: window)
            initialOverlayFrame = aspectFitRect(imageSize: image.size, in: markerFrame)

            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.frame = initialOverlayFrame
            imageView.clipsToBounds = false
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.18
            imageView.layer.shadowRadius = 14
            imageView.layer.shadowOffset = CGSize(width: 0, height: 6)
            window.addSubview(imageView)
            overlayImageView = imageView
        }

        private func endOverlay() {
            guard let overlayImageView else {
                FlagZoomInteractionState.isPinching = false
                return
            }

            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.94,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                overlayImageView.transform = .identity
                overlayImageView.center = CGPoint(x: self.initialOverlayFrame.midX, y: self.initialOverlayFrame.midY)
            } completion: { _ in
                overlayImageView.removeFromSuperview()
                self.overlayImageView = nil
                FlagZoomInteractionState.isPinching = false
            }
        }

        private func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else { return rect }
            let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
            let width = imageSize.width * scale
            let height = imageSize.height * scale
            return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }

        private func expandedHitRect(for markerView: UIView) -> CGRect {
            markerView.bounds.insetBy(dx: -hitSlop, dy: -hitSlop)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pinchGesture, let markerView else { return true }
            let shouldBegin = expandedHitRect(for: markerView).contains(gestureRecognizer.location(in: markerView))
            if shouldBegin {
                FlagZoomInteractionState.isPinching = true
            }
            return shouldBegin
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

final class FlagImageCache {
    static let shared = FlagImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private var loadingTasks: [URL: Task<UIImage, Error>] = [:]
    private let diskCacheDirectory: URL

    private init() {
        cache.countLimit = 220
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        diskCacheDirectory = cachesDirectory.appendingPathComponent("FlagImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    @MainActor
    func image(for url: URL) -> UIImage? {
        if let cachedImage = cache.object(forKey: url as NSURL) {
            return cachedImage
        }
        guard let diskImage = loadImageFromDisk(for: url) else { return nil }
        cache.setObject(diskImage, forKey: url as NSURL)
        return diskImage
    }

    @MainActor
    func loadImage(from url: URL) async throws -> UIImage {
        if let cachedImage = image(for: url) {
            return cachedImage
        }

        if let task = loadingTasks[url] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }

        loadingTasks[url] = task
        do {
            let loadedImage = try await task.value
            cache.setObject(loadedImage, forKey: url as NSURL)
            saveImageToDisk(loadedImage, for: url)
            loadingTasks[url] = nil
            return loadedImage
        } catch {
            loadingTasks[url] = nil
            throw error
        }
    }

    private func diskURL(for url: URL) -> URL {
        let encoded = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return diskCacheDirectory.appendingPathComponent(encoded).appendingPathExtension("png")
    }

    private func loadImageFromDisk(for url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(for: url)) else { return nil }
        return UIImage(data: data)
    }

    private func saveImageToDisk(_ image: UIImage, for url: URL) {
        guard let data = image.pngData() else { return }
        try? data.write(to: diskURL(for: url), options: [.atomic])
    }
}

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    var isProminent: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(isEnabled ? 0.95 : 0.35), lineWidth: isProminent ? 0 : 1.4)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color(.tertiarySystemFill)
        }
        return isProminent ? color.opacity(isPressed ? 0.82 : 1) : color.opacity(isPressed ? 0.18 : 0.10)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .secondary
        }
        return isProminent ? .white : color
    }
}

