import SwiftUI
import Foundation
import UIKit
import ImageIO

enum AppLayout {
    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
}

private struct AppSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func appSurface(cornerRadius: CGFloat = AppLayout.cardRadius) -> some View {
        modifier(AppSurfaceModifier(cornerRadius: cornerRadius))
    }
}

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

            guard let boundaryData else {
                if let localSnapshot {
                    drawLocalSnapshot(localSnapshot, in: &context, size: size)
                } else {
                    drawFallbackFocus(in: &context, size: size)
                }
                return
            }

            let selectedRings = boundaryData.ringsByCountryCode[country.code] ?? []
            guard let focusBounds = miniGlobeFocusBounds(for: selectedRings, fallbackCenter: boundaryData.centroidsByCountryCode[country.code] ?? fallbackCoordinate) else {
                drawFallbackFocus(in: &context, size: size)
                return
            }

            let contextRings = miniGlobeContextRings(in: focusBounds, boundaryData: boundaryData)
            drawContextRings(contextRings, in: &context, bounds: focusBounds, size: size)

            let selectedPaths = selectedRings.map { mapPath(for: $0, in: focusBounds, size: size) }
            let selectedBounds = selectedPaths.reduce(CGRect.null) { $0.union($1.boundingRect) }

            drawSelectedCountry(selectedPaths, in: &context)

            if shouldDrawFocusBeacon(for: selectedBounds, size: size) {
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
        let contextRings = miniGlobeContextRings(in: focusBounds, boundaryData: boundaryData)
        let snapshot = MiniLocationSnapshot(countryCode: country.code, rings: rings, contextRings: contextRings, bounds: MiniLocationSnapshotBounds(focusBounds))
        MiniLocationSnapshotStore.store(snapshot)
        localSnapshot = snapshot
    }

    private func drawFallbackFocus(in context: inout GraphicsContext, size: CGSize) {
        drawFocusBeacon(in: &context, size: size)
    }

    private func shouldDrawFocusBeacon(for bounds: CGRect, size: CGSize) -> Bool {
        guard !bounds.isNull else { return true }
        let minimumVisibleSide = min(size.width, size.height) * 0.055
        return bounds.width < minimumVisibleSide && bounds.height < minimumVisibleSide
    }

    private func drawFocusBeacon(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(accentColor.opacity(0.24)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(accentColor))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.white.opacity(0.82)), lineWidth: 1.1)
    }

    private func drawLocalSnapshot(_ snapshot: MiniLocationSnapshot, in context: inout GraphicsContext, size: CGSize) {
        let bounds = snapshot.bounds.cgRect
        drawContextRings(snapshot.contextRings ?? [], in: &context, bounds: bounds, size: size)
        let selectedPaths = snapshot.rings.map { mapPath(for: $0, in: bounds, size: size) }
        let selectedBounds = selectedPaths.reduce(CGRect.null) { $0.union($1.boundingRect) }

        drawSelectedCountry(selectedPaths, in: &context)

        if selectedBounds.isNull || min(selectedBounds.width, selectedBounds.height) < min(size.width, size.height) * 0.14 {
            drawFocusBeacon(in: &context, size: size)
        }
    }

    private func drawSelectedCountry(_ paths: [Path], in context: inout GraphicsContext) {
        for path in paths {
            context.fill(path, with: .color(accentColor.opacity(0.92)))
            context.stroke(path, with: .color(Color.white.opacity(0.78)), lineWidth: 0.8)
        }
    }

    private func drawContextRings(_ rings: [[GlobeCoordinate]], in context: inout GraphicsContext, bounds: CGRect, size: CGSize) {
        for ring in rings.prefix(220) {
            let path = mapPath(for: ring, in: bounds, size: size)
            guard !path.boundingRect.isNull else { continue }
            context.fill(path, with: .color(Color.white.opacity(0.18)))
            context.stroke(path, with: .color(Color.white.opacity(0.36)), lineWidth: 0.55)
        }
    }

    private func miniGlobeContextRings(in bounds: CGRect, boundaryData: GlobeBoundaryData) -> [[GlobeCoordinate]] {
        let paddedBounds = bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.08)

        return boundaryData.ringsByCountryCode
            .filter { $0.key != country.code }
            .flatMap { _, rings in rings }
            .filter { ring in
                guard let ringBounds = coordinateBounds(for: ring) else { return false }
                return ringBounds.intersects(paddedBounds)
            }
    }

    private func coordinateBounds(for ring: [GlobeCoordinate]) -> CGRect? {
        guard !ring.isEmpty else { return nil }
        let latitudes = ring.map(\.latitude)
        let longitudes = ring.map(\.longitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(),
              let maximumLongitude = longitudes.max() else { return nil }

        return CGRect(
            x: minimumLongitude,
            y: minimumLatitude,
            width: max(maximumLongitude - minimumLongitude, 0.01),
            height: max(maximumLatitude - minimumLatitude, 0.01)
        )
    }

    private var minimumMiniGlobeSpan: Double {
        switch country.continent {
        case "Europa": return 34
        case "Afrika": return 46
        case "Asien": return 58
        case "Nordamerika": return 58
        case "Südamerika": return 50
        case "Ozeanien": return 64
        default: return 42
        }
    }

    private var maximumMiniGlobeSpan: Double {
        switch country.continent {
        case "Europa": return 80
        case "Ozeanien": return 120
        default: return 105
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
        let centerLatitude = fallbackCenter.latitude
        let centerLongitude = fallbackCenter.longitude
        let latitudeSpan = max(maximumLatitude - minimumLatitude, 0.6)
        let longitudeSpan = max(maximumLongitude - minimumLongitude, 0.6)
        let countrySpan = max(latitudeSpan, longitudeSpan)
        let span = min(max(countrySpan * 2.15, minimumMiniGlobeSpan), maximumMiniGlobeSpan)

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
    var contextRings: [[GlobeCoordinate]]? = nil
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
    private static let legacyStorageKeys = [
        "miniLocationSnapshotsV1",
        "miniLocationSnapshotsV2",
        "miniLocationSnapshotsV3",
        "miniLocationSnapshotsV4"
    ]
    private static let legacyFileName = "miniLocationSnapshotsV4.json"
    private static let snapshotDirectory = "MiniLocationSnapshots"
    private static var memoryCache: [String: MiniLocationSnapshot] = [:]

    static func migrateLegacyIfNeeded() {
        for key in legacyStorageKeys {
            guard let data = UserDefaults.standard.data(forKey: key) else { continue }
            if let decoded = try? JSONDecoder().decode([String: MiniLocationSnapshot].self, from: data) {
                if persist(decoded) {
                    LegacyDefaultsMigration.removeData(forKey: key, migratedData: data)
                }
            } else {
                // These are rebuildable map previews, not user progress. A
                // corrupt legacy cache is therefore safe to discard.
                LegacyDefaultsMigration.removeData(forKey: key, migratedData: data)
            }
        }

        guard let fileData = DataFileStore.read(fileName: legacyFileName) else { return }
        if let decoded = try? JSONDecoder().decode([String: MiniLocationSnapshot].self, from: fileData) {
            if persist(decoded) {
                DataFileStore.remove(fileName: legacyFileName)
            }
        } else {
            DataFileStore.remove(fileName: legacyFileName)
        }
    }

    static func snapshot(for countryCode: String) -> MiniLocationSnapshot? {
        let normalizedCode = normalizedCountryCode(countryCode)
        if let cached = memoryCache[normalizedCode] {
            return cached
        }

        guard let data = DataFileStore.read(fileName: fileName(for: normalizedCode)),
              let snapshot = try? JSONDecoder().decode(MiniLocationSnapshot.self, from: data) else {
            return nil
        }
        memoryCache[normalizedCode] = snapshot
        return snapshot
    }

    static func store(_ snapshot: MiniLocationSnapshot) {
        let code = normalizedCountryCode(snapshot.countryCode)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let targetFileName = fileName(for: code)
        if DataFileStore.read(fileName: targetFileName) != data {
            _ = DataFileStore.write(data, fileName: targetFileName)
        }
        memoryCache[code] = snapshot
    }

    private static func persist(_ snapshots: [String: MiniLocationSnapshot]) -> Bool {
        for (countryCode, snapshot) in snapshots {
            guard let data = try? JSONEncoder().encode(snapshot),
                  DataFileStore.write(data, fileName: fileName(for: normalizedCountryCode(countryCode))) else {
                return false
            }
        }
        return true
    }

    private static func normalizedCountryCode(_ code: String) -> String {
        let safe = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return safe.isEmpty ? "UNKNOWN" : safe
    }

    private static func fileName(for countryCode: String) -> String {
        "\(snapshotDirectory)/\(countryCode).json"
    }
}

struct StartupScreen: View {
    let language: AppLanguage
    let completedItemCount: Int
    let totalItemCount: Int
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

    private var preloadProgress: Double {
        guard totalItemCount > 0 else { return 0 }
        return min(max(Double(completedItemCount) / Double(totalItemCount), 0), 1)
    }

    private var preloadStatusText: String {
        if completedItemCount >= totalItemCount, totalItemCount > 1 {
            return localized("Fast fertig …", "Almost ready …", language: language)
        }
        if totalItemCount > 1 {
            return localized(
                "Flaggen werden vorbereitet (\(min(completedItemCount, totalItemCount))/\(totalItemCount))",
                "Preparing flags (\(min(completedItemCount, totalItemCount))/\(totalItemCount))",
                language: language
            )
        }
        return localized("App wird vorbereitet …", "Preparing app …", language: language)
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
                                : UIColor.systemGroupedBackground
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
                                : UIColor.secondarySystemGroupedBackground
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
                    .font(.system(size: 84, weight: .semibold))
                    .foregroundStyle(tealAccentColor)
                    .frame(width: 132, height: 132)
                    .background(tealAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text("Flaggenbande")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .opacity(logoOpacity)

                VStack(spacing: 8) {
                    ProgressView(value: preloadProgress)
                        .tint(tealAccentColor)
                        .frame(maxWidth: 250)
                    Text(preloadStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .opacity(logoOpacity)
                .animation(.easeInOut(duration: 0.2), value: completedItemCount)
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
            Button {
                onRepeat()
            } label: {
                Text(localized("10 weitere üben", "Practice 10 more", language: language))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

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
    private static var activeOwnerID: ObjectIdentifier?

    static var isPinching: Bool {
        activeOwnerID != nil
    }

    static func begin(owner: AnyObject) {
        activeOwnerID = ObjectIdentifier(owner)
    }

    static func end(owner: AnyObject) {
        guard activeOwnerID == ObjectIdentifier(owner) else { return }
        activeOwnerID = nil
    }
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

    static func dismantleUIView(_ uiView: PinchMarkerView, coordinator: Coordinator) {
        uiView.onMoveToWindow = nil
        coordinator.markerView = nil
        coordinator.detach()
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
        private var returnAnimator: UIViewPropertyAnimator?
        private var zoomSessionID = 0
        private let hitSlop: CGFloat = 24
        private let maximumScale: CGFloat = 4.4

        private lazy var pinchGesture: UIPinchGestureRecognizer = {
            let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            return gesture
        }()

        init(image: UIImage) {
            self.image = image
        }

        func updateImage(_ newImage: UIImage) {
            guard image !== newImage else { return }
            image = newImage
            cancelZoom()
        }

        func attachIfPossible() {
            guard let markerView else { return }
            guard let targetView = markerView.window else {
                attachedView?.removeGestureRecognizer(pinchGesture)
                attachedView = nil
                cancelZoom()
                return
            }
            guard attachedView !== targetView else { return }
            attachedView?.removeGestureRecognizer(pinchGesture)
            cancelZoom()
            targetView.addGestureRecognizer(pinchGesture)
            attachedView = targetView
        }

        func detach() {
            attachedView?.removeGestureRecognizer(pinchGesture)
            attachedView = nil
            cancelZoom()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let markerView, let window = markerView.window else {
                cancelZoom()
                return
            }
            let markerLocation = gesture.location(in: markerView)

            switch gesture.state {
            case .began:
                guard expandedHitRect(for: markerView).contains(markerLocation) else { return }
                cancelZoom()
                zoomSessionID += 1
                isHandlingPinch = true
                FlagZoomInteractionState.begin(owner: self)
                initialPinchLocation = gesture.location(in: window)
                guard beginOverlay(in: window, from: markerView) else {
                    cancelZoom()
                    return
                }
                gesture.scale = 1
            case .changed:
                guard isHandlingPinch, let overlayImageView else { return }
                let scale = rubberBandedScale(gesture.scale)
                let windowLocation = gesture.location(in: window)
                let baseOffset = CGPoint(
                    x: initialOverlayFrame.midX - initialPinchLocation.x,
                    y: initialOverlayFrame.midY - initialPinchLocation.y
                )
                overlayImageView.center = CGPoint(
                    x: windowLocation.x + baseOffset.x * scale,
                    y: windowLocation.y + baseOffset.y * scale
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

        private func cancelZoom() {
            zoomSessionID += 1
            returnAnimator?.stopAnimation(true)
            returnAnimator = nil
            overlayImageView?.layer.removeAllAnimations()
            overlayImageView?.removeFromSuperview()
            overlayImageView = nil
            isHandlingPinch = false
            pinchGesture.scale = 1
            FlagZoomInteractionState.end(owner: self)
        }

        private func beginOverlay(in window: UIView, from markerView: UIView) -> Bool {
            returnAnimator?.stopAnimation(true)
            returnAnimator = nil
            overlayImageView?.removeFromSuperview()
            let markerFrame = markerView.convert(markerView.bounds, to: window)
            initialOverlayFrame = aspectFitRect(imageSize: image.size, in: markerFrame)
            guard initialOverlayFrame.width > 1, initialOverlayFrame.height > 1 else { return false }

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
            return true
        }

        private func endOverlay() {
            guard let overlayImageView else {
                FlagZoomInteractionState.end(owner: self)
                return
            }

            let finishingSessionID = zoomSessionID
            let targetFrame: CGRect
            if let markerView, let window = markerView.window {
                targetFrame = aspectFitRect(
                    imageSize: image.size,
                    in: markerView.convert(markerView.bounds, to: window)
                )
            } else {
                targetFrame = initialOverlayFrame
            }

            let animator = UIViewPropertyAnimator(duration: 0.30, dampingRatio: 0.88) {
                overlayImageView.transform = .identity
                overlayImageView.bounds = CGRect(origin: .zero, size: targetFrame.size)
                overlayImageView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                overlayImageView.layer.shadowOpacity = 0
            }
            animator.addCompletion { [weak self, weak overlayImageView] _ in
                guard let overlayImageView else { return }
                overlayImageView.removeFromSuperview()
                guard let self,
                      self.zoomSessionID == finishingSessionID,
                      self.overlayImageView === overlayImageView else { return }
                self.overlayImageView = nil
                self.returnAnimator = nil
                FlagZoomInteractionState.end(owner: self)
            }
            returnAnimator = animator
            animator.startAnimation()
        }

        private func rubberBandedScale(_ rawScale: CGFloat) -> CGFloat {
            if rawScale < 1 {
                return max(0.92, 1 - (1 - rawScale) * 0.20)
            }
            if rawScale > maximumScale {
                return min(maximumScale + 0.35, maximumScale + (rawScale - maximumScale) * 0.12)
            }
            return rawScale
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
            guard gestureRecognizer === pinchGesture, let markerView, markerView.window != nil else { return false }
            return expandedHitRect(for: markerView).contains(gestureRecognizer.location(in: markerView))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

final class FlagImageCache {
    static let shared = FlagImageCache()

    struct PreloadReport {
        let totalCount: Int
        let cachedCount: Int
        let failedCount: Int

        var isComplete: Bool {
            cachedCount >= totalCount
        }
    }

    private let cache = NSCache<NSURL, UIImage>()
    private var loadingTasks: [URL: Task<UIImage, Error>] = [:]
    private var validatedDiskURLs: Set<URL> = []
    private let diskCacheDirectory: URL

    private init() {
        // A w1280 flag can occupy several MB after decoding. Keep only a small
        // decoded working set in RAM; the complete catalogue is warmed on disk.
        cache.countLimit = 64
        cache.totalCostLimit = 96 * 1_024 * 1_024
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        diskCacheDirectory = cachesDirectory.appendingPathComponent("FlagImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    @MainActor
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    @MainActor
    func loadImage(from url: URL) async throws -> UIImage {
        if let cachedImage = image(for: url) {
            return cachedImage
        }

        if let task = loadingTasks[url] {
            return try await task.value
        }

        let fileURL = diskURL(for: url)
        let task = Task.detached(priority: .userInitiated) {
            try await Self.loadOrDownloadImage(from: url, fileURL: fileURL)
        }

        loadingTasks[url] = task
        do {
            let loadedImage = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            storeInMemory(loadedImage, for: url)
            loadingTasks[url] = nil
            return loadedImage
        } catch {
            loadingTasks[url] = nil
            throw error
        }
    }

    @MainActor
    func preloadToDisk(
        countries: [Country],
        maximumConcurrentDownloads: Int = 6,
        maximumDuration: TimeInterval = 6,
        progress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> PreloadReport {
        var seenURLs: Set<URL> = []
        let urls = countries.compactMap(\.flagImageURL).filter { seenURLs.insert($0).inserted }
        let total = urls.count
        guard total > 0 else {
            progress?(0, 0)
            return PreloadReport(totalCount: 0, cachedCount: 0, failedCount: 0)
        }

        let items = urls.map { (url: $0, fileURL: diskURL(for: $0)) }
        let stillValidatedURLs = Set(items.compactMap { item -> URL? in
            guard validatedDiskURLs.contains(item.fileURL),
                  Self.hasNonemptyCacheFile(at: item.fileURL) else { return nil }
            return item.fileURL
        })
        let validationCandidates = items
            .map(\.fileURL)
            .filter { !stillValidatedURLs.contains($0) && Self.hasNonemptyCacheFile(at: $0) }
        let newlyValidatedURLs = await Self.validatedCacheFileURLs(
            validationCandidates,
            maximumConcurrentValidations: maximumConcurrentDownloads
        )
        let validCachedURLs = stillValidatedURLs.union(newlyValidatedURLs)
        validatedDiskURLs.formUnion(validCachedURLs)

        for invalidURL in validationCandidates where !newlyValidatedURLs.contains(invalidURL) {
            validatedDiskURLs.remove(invalidURL)
            try? FileManager.default.removeItem(at: invalidURL)
        }

        let pendingItems = items.filter { !validCachedURLs.contains($0.fileURL) }
        var completed = validCachedURLs.count
        var failed = 0
        progress?(completed, total)

        let startedAt = Date()
        let batchSize = max(1, min(maximumConcurrentDownloads, 8))

        for batchStart in stride(from: 0, to: pendingItems.count, by: batchSize) {
            guard Date().timeIntervalSince(startedAt) < maximumDuration else { break }
            let batchEnd = min(batchStart + batchSize, pendingItems.count)
            let batch = Array(pendingItems[batchStart..<batchEnd])

            await withTaskGroup(of: URL?.self) { group in
                for item in batch {
                    group.addTask(priority: .utility) {
                        do {
                            try await Self.downloadImageData(
                                from: item.url,
                                to: item.fileURL,
                                timeoutInterval: 4
                            )
                            return item.fileURL
                        } catch {
                            return nil
                        }
                    }
                }

                for await downloadedURL in group {
                    if let downloadedURL {
                        completed += 1
                        validatedDiskURLs.insert(downloadedURL)
                    } else {
                        failed += 1
                    }
                    progress?(completed + failed, total)
                }
            }
        }

        return PreloadReport(totalCount: total, cachedCount: completed, failedCount: failed)
    }

    @MainActor
    func warmInMemory(_ countries: [Country]) async {
        for country in countries {
            guard !Task.isCancelled, let url = country.flagImageURL else { continue }
            _ = try? await loadImage(from: url)
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

    @MainActor
    private func storeInMemory(_ image: UIImage, for url: URL) {
        let pixelWidth = max(Int(image.size.width * image.scale), 1)
        let pixelHeight = max(Int(image.size.height * image.scale), 1)
        cache.setObject(
            image,
            forKey: url as NSURL,
            cost: pixelWidth * pixelHeight * 4
        )
    }

    nonisolated private static func loadOrDownloadImage(from url: URL, fileURL: URL) async throws -> UIImage {
        if let data = try? Data(contentsOf: fileURL), let image = displayReadyImage(from: data) {
            return image
        }

        try? FileManager.default.removeItem(at: fileURL)
        try await downloadImageData(from: url, to: fileURL, timeoutInterval: 6)
        try Task.checkCancellation()

        let data = try Data(contentsOf: fileURL)
        guard let image = displayReadyImage(from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    nonisolated private static func displayReadyImage(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // ImageIO has already decoded the pixels because shouldCacheImmediately
        // is enabled, so SwiftUI does not decompress the image on first render.
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func downloadImageData(
        from url: URL,
        to fileURL: URL,
        timeoutInterval: TimeInterval
    ) async throws {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = timeoutInterval
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              !data.isEmpty,
              isDecodableImageData(data) else {
            throw URLError(.badServerResponse)
        }

        try data.write(to: fileURL, options: [.atomic])
    }

    nonisolated private static func hasNonemptyCacheFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else { return false }
        return fileSize.intValue > 0
    }

    /// Forces ImageIO to decode the image while retaining only a tiny pixel
    /// buffer. This preserves corruption detection without materializing every
    /// cached w1280 flag at full resolution during preload validation.
    nonisolated private static func isDecodableImageData(_ data: Data) -> Bool {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return false }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) != nil
    }

    nonisolated private static func validatedCacheFileURLs(
        _ urls: [URL],
        maximumConcurrentValidations: Int
    ) async -> Set<URL> {
        guard !urls.isEmpty else { return [] }
        let batchSize = max(1, min(maximumConcurrentValidations, 8))
        var validURLs: Set<URL> = []

        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, urls.count)
            let batch = Array(urls[batchStart..<batchEnd])
            await withTaskGroup(of: URL?.self) { group in
                for url in batch {
                    group.addTask(priority: .utility) {
                        autoreleasepool {
                            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                                  isDecodableImageData(data) else { return nil }
                            return url
                        }
                    }
                }
                for await validURL in group {
                    if let validURL {
                        validURLs.insert(validURL)
                    }
                }
            }
        }

        return validURLs
    }
}

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    var isProminent: Bool = true
    var verticalPadding: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: isProminent ? 50 : 44)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(isEnabled ? 0.75 : 0.28), lineWidth: isProminent ? 0 : 1)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.985 : 1)
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
