import SwiftUI
import Foundation
import UIKit
import SceneKit
import simd

struct GlobeSceneView: UIViewRepresentable {
    let countries: [Country]
    let tiersByCountryCode: [String: MasteryTier]
    let resetToken: Int
    let focusCountryCode: String?
    let onSelectCountryCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectCountryCode: onSelectCountryCode)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.allowsCameraControl = false
        context.coordinator.configure(sceneView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        tapGesture.require(toFail: panGesture)
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(panGesture)
        sceneView.addGestureRecognizer(pinchGesture)
        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.onSelectCountryCode = onSelectCountryCode
        context.coordinator.resetIfNeeded(token: resetToken)
        context.coordinator.updateCountries(countries, tiersByCountryCode: tiersByCountryCode)
        context.coordinator.focusIfNeeded(countryCode: focusCountryCode)
    }

    final class Coordinator: NSObject {
        var onSelectCountryCode: (String) -> Void
        private weak var sceneView: SCNView?
        private let globeNode = SCNNode()
        private let borderNode = SCNNode()
        private let globeMaterial = SCNMaterial()
        private let cameraNode = SCNNode()
        private var boundaryData: GlobeBoundaryData?
        private var currentCountries: [Country] = []
        private var currentTiersByCountryCode: [String: MasteryTier] = [:]
        private var currentTextureSignature: String = ""
        private var didStartLoadingBoundaries = false
        private var cameraDistance: Float = 3.2
        private var lastResetToken: Int = 0
        private var lastFocusedCountryCode: String?
        private var pendingFocusCountryCode: String?
        private let minimumCameraDistance: Float = 1.65
        private let maximumCameraDistance: Float = 4.8
        private var globeOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        private var previousTrackballVector: SIMD3<Float>?
        private var inertiaAxis = SIMD3<Float>(0, 1, 0)
        private var inertiaAngularVelocity: Float = 0
        private var lastPanTimestamp: TimeInterval?
        private var inertiaDisplayLink: CADisplayLink?

        init(onSelectCountryCode: @escaping (String) -> Void) {
            self.onSelectCountryCode = onSelectCountryCode
        }

        func configure(_ sceneView: SCNView) {
            self.sceneView = sceneView

            let scene = SCNScene()
            sceneView.scene = scene

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zNear = 0.01
            cameraNode.camera?.zFar = 100
            scene.rootNode.addChildNode(cameraNode)
            sceneView.pointOfView = cameraNode
            applyGermanyFocus(animated: false)

            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 650
            scene.rootNode.addChildNode(ambientLight)

            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light?.type = .directional
            directionalLight.light?.intensity = 500
            directionalLight.eulerAngles = SCNVector3(-0.6, 0.5, 0)
            scene.rootNode.addChildNode(directionalLight)

            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 160
            globeMaterial.diffuse.contents = UIColor(red: 0.03, green: 0.19, blue: 0.32, alpha: 1)
            globeMaterial.emission.contents = UIColor(red: 0.0, green: 0.07, blue: 0.11, alpha: 1)
            globeMaterial.specular.contents = UIColor.white.withAlphaComponent(0.34)
            globeMaterial.shininess = 0.55
            sphere.firstMaterial = globeMaterial

            globeNode.geometry = sphere
            globeNode.addChildNode(borderNode)
            globeNode.addChildNode(makeAtmosphereNode())
            scene.rootNode.addChildNode(globeNode)

            loadBoundariesIfNeeded()
        }

        func updateCountries(_ countries: [Country], tiersByCountryCode: [String: MasteryTier]) {
            let textureSignature = countries.map(\.code).joined(separator: ",") + "|" + tiersByCountryCode.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.rawValue)" }.joined(separator: ",")
            guard textureSignature != currentTextureSignature else { return }
            currentTextureSignature = textureSignature
            currentCountries = countries
            currentTiersByCountryCode = tiersByCountryCode
            rebuildGlobeTexture()
        }

        private func makeAtmosphereNode() -> SCNNode {
            let atmosphere = SCNSphere(radius: 1.018)
            atmosphere.segmentCount = 160
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.28, green: 0.86, blue: 0.92, alpha: 0.16)
            material.emission.contents = UIColor(red: 0.10, green: 0.42, blue: 0.52, alpha: 0.20)
            material.transparency = 0.32
            material.blendMode = .add
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            atmosphere.firstMaterial = material
            return SCNNode(geometry: atmosphere)
        }

        func resetIfNeeded(token: Int) {
            guard token != lastResetToken else { return }
            lastResetToken = token
            lastFocusedCountryCode = nil
            stopInertia()
            inertiaAngularVelocity = 0
            previousTrackballVector = nil
            cameraDistance = 3.2
            applyGermanyFocus(animated: true)
        }

        func focusIfNeeded(countryCode: String?) {
            guard let countryCode, countryCode != lastFocusedCountryCode else { return }
            guard let coordinate = globeMainlandFocusByCountryCode[countryCode] ?? boundaryData?.centroidsByCountryCode[countryCode] else {
                pendingFocusCountryCode = countryCode
                return
            }
            pendingFocusCountryCode = nil
            lastFocusedCountryCode = countryCode
            stopInertia()
            cameraDistance = min(cameraDistance, 3.0)
            applyFocus(on: coordinate, animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])

            for result in hitResults {
                guard result.node == globeNode || result.node.parent == globeNode else { continue }
                let coordinate = coordinate(from: result.localCoordinates)
                if let countryCode = countryCode(containing: coordinate) {
                    onSelectCountryCode(countryCode)
                    return
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let timestamp = CACurrentMediaTime()
            let currentVector = trackballVector(for: gesture.location(in: view), in: view.bounds.size)

            switch gesture.state {
            case .began:
                stopInertia()
                inertiaAngularVelocity = 0
                previousTrackballVector = currentVector
                lastPanTimestamp = timestamp
            case .changed:
                guard let previousTrackballVector else { return }
                let deltaTime = max(Float(timestamp - (lastPanTimestamp ?? timestamp)), 0.001)
                if let rotation = rotation(from: previousTrackballVector, to: currentVector) {
                    apply(rotation: rotation, animated: false)
                    inertiaAxis = rotation.axis
                    inertiaAngularVelocity = min(rotation.angle / deltaTime, 12)
                }
                self.previousTrackballVector = currentVector
                lastPanTimestamp = timestamp
            case .ended, .cancelled, .failed:
                previousTrackballVector = nil
                lastPanTimestamp = nil
                startInertiaIfNeeded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            stopInertia()
            let scale = max(Float(gesture.scale), 0.01)
            cameraDistance = min(max(cameraDistance / scale, minimumCameraDistance), maximumCameraDistance)
            cameraNode.position = SCNVector3(0, 0, cameraDistance)
            gesture.scale = 1
        }

        @objc private func handleInertiaFrame(_ displayLink: CADisplayLink) {
            let deltaTime = Float(displayLink.targetTimestamp - displayLink.timestamp)
            let angle = inertiaAngularVelocity * deltaTime
            if angle > 0.0001 {
                apply(rotation: simd_quatf(angle: angle, axis: inertiaAxis), animated: false)
            }

            inertiaAngularVelocity *= pow(0.92, deltaTime * 60)
            if inertiaAngularVelocity < 0.08 {
                stopInertia()
            }
        }

        private func startInertiaIfNeeded() {
            guard inertiaAngularVelocity > 1.2 else { return }
            stopInertia()
            let displayLink = CADisplayLink(target: self, selector: #selector(handleInertiaFrame(_:)))
            displayLink.add(to: .main, forMode: .common)
            inertiaDisplayLink = displayLink
        }

        private func stopInertia() {
            inertiaDisplayLink?.invalidate()
            inertiaDisplayLink = nil
        }

        private func apply(rotation: simd_quatf, animated: Bool) {
            globeOrientation = rotation * globeOrientation
            let changes = {
                self.globeNode.simdOrientation = self.globeOrientation
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.28
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
                SCNTransaction.commit()
            } else {
                changes()
            }
        }

        private func trackballVector(for point: CGPoint, in size: CGSize) -> SIMD3<Float> {
            let dimension = max(Float(min(size.width, size.height)), 1)
            var x = Float((2 * point.x - size.width) / CGFloat(dimension))
            var y = Float((size.height - 2 * point.y) / CGFloat(dimension))
            let lengthSquared = x * x + y * y
            if lengthSquared > 1 {
                let length = sqrt(lengthSquared)
                x /= length
                y /= length
                return SIMD3<Float>(x, y, 0)
            }
            return SIMD3<Float>(x, y, sqrt(1 - lengthSquared))
        }

        private func rotation(from start: SIMD3<Float>, to end: SIMD3<Float>) -> simd_quatf? {
            let axis = simd_cross(start, end)
            let axisLength = simd_length(axis)
            let clampedDot = min(max(simd_dot(start, end), -1), 1)
            guard axisLength > 0.0001 else {
                return clampedDot < -0.999 ? simd_quatf(angle: .pi, axis: fallbackAxis(for: start)) : nil
            }
            return simd_quatf(angle: acos(clampedDot), axis: axis / axisLength)
        }

        private func fallbackAxis(for vector: SIMD3<Float>) -> SIMD3<Float> {
            let reference = abs(vector.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            return simd_normalize(simd_cross(vector, reference))
        }

        private func applyGermanyFocus(animated: Bool) {
            let europeLatitude = Float(52.0 * .pi / 180)
            let europeLongitude = Float(12.0 * .pi / 180)
            applyFocus(latitude: europeLatitude, longitude: europeLongitude, animated: animated)
        }

        private func applyFocus(on coordinate: GlobeCoordinate, animated: Bool) {
            applyFocus(
                latitude: Float(coordinate.latitude * .pi / 180),
                longitude: Float(coordinate.longitude * .pi / 180),
                animated: animated
            )
        }

        private func applyFocus(latitude: Float, longitude: Float, animated: Bool) {
            let longitudeRotation = simd_quatf(angle: -longitude, axis: SIMD3<Float>(0, 1, 0))
            let latitudeRotation = simd_quatf(angle: latitude, axis: SIMD3<Float>(1, 0, 0))
            globeOrientation = latitudeRotation * longitudeRotation

            let changes = {
                self.globeNode.simdOrientation = self.globeOrientation
                self.cameraNode.position = SCNVector3(0, 0, self.cameraDistance)
                self.cameraNode.eulerAngles = SCNVector3Zero
                self.sceneView?.pointOfView = self.cameraNode
            }

            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.32
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
                SCNTransaction.commit()
            } else {
                changes()
            }
        }

        private func loadBoundariesIfNeeded() {
            guard !didStartLoadingBoundaries else { return }
            didStartLoadingBoundaries = true

            if let cachedData = GlobeBoundaryCache.data, GlobeBoundaryCache.source == globeBoundarySource {
                boundaryData = cachedData
                rebuildGlobeTexture()
                rebuildBoundaries()
                focusIfNeeded(countryCode: pendingFocusCountryCode)
                return
            }

            guard let url = URL(string: globeBoundaryURLString) else { return }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let boundaryData = GlobeBoundaryData.parse(data: data) else { return }
                DispatchQueue.main.async {
                    GlobeBoundaryCache.source = globeBoundarySource
                    GlobeBoundaryCache.data = boundaryData
                    self.boundaryData = boundaryData
                    self.rebuildGlobeTexture()
                    self.rebuildBoundaries()
                    self.focusIfNeeded(countryCode: self.pendingFocusCountryCode)
                }
            }.resume()
        }

        private func rebuildBoundaries() {
            borderNode.childNodes.forEach { $0.removeFromParentNode() }
            guard let boundaryData else { return }

            let borderMaterial = SCNMaterial()
            borderMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.78)
            borderMaterial.emission.contents = UIColor.white.withAlphaComponent(0.28)
            borderMaterial.lightingModel = .constant

            for ring in boundaryData.rings {
                guard ring.count > 1 else { continue }
                let vertices = ring.map { position(for: $0, radius: 1.006) }
                let source = SCNGeometrySource(vertices: vertices)
                var indices: [Int32] = []
                for index in 0..<(vertices.count - 1) {
                    indices.append(Int32(index))
                    indices.append(Int32(index + 1))
                }
                let element = SCNGeometryElement(indices: indices, primitiveType: .line)
                let geometry = SCNGeometry(sources: [source], elements: [element])
                geometry.materials = [borderMaterial]
                borderNode.addChildNode(SCNNode(geometry: geometry))
            }
        }

        private func rebuildGlobeTexture() {
            guard let boundaryData else { return }
            let size = CGSize(width: 4096, height: 2048)
            let renderer = UIGraphicsImageRenderer(size: size)

            let image = renderer.image { context in
                UIColor(red: 0.03, green: 0.19, blue: 0.32, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))

                for country in currentCountries {
                    guard let countryRings = boundaryData.ringsByCountryCode[country.code] else { continue }
                    let tier = currentTiersByCountryCode[country.code] ?? .f
                    tier.globeUIColor.setFill()

                    for ring in countryRings {
                        let path = texturePath(for: ring, in: size)
                        path.fill()
                    }
                }
            }

            globeMaterial.diffuse.contents = image
        }

        private func texturePath(for ring: [GlobeCoordinate], in size: CGSize) -> UIBezierPath {
            let path = UIBezierPath()
            for (index, coordinate) in ring.enumerated() {
                let point = texturePoint(for: coordinate, in: size)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.close()
            return path
        }

        private func texturePoint(for coordinate: GlobeCoordinate, in size: CGSize) -> CGPoint {
            let x = (coordinate.longitude + 180) / 360 * size.width
            let y = (90 - coordinate.latitude) / 180 * size.height
            return CGPoint(x: x, y: y)
        }

        private func position(for coordinate: GlobeCoordinate, radius: Double) -> SCNVector3 {
            let latitude = coordinate.latitude * .pi / 180
            let longitude = coordinate.longitude * .pi / 180
            let x = radius * cos(latitude) * sin(longitude)
            let y = radius * sin(latitude)
            let z = radius * cos(latitude) * cos(longitude)
            return SCNVector3(Float(x), Float(y), Float(z))
        }

        private func coordinate(from position: SCNVector3) -> GlobeCoordinate {
            let x = Double(position.x)
            let y = Double(position.y)
            let z = Double(position.z)
            let radius = max(sqrt(x * x + y * y + z * z), 0.0001)
            let latitude = asin(y / radius) * 180 / .pi
            let longitude = atan2(x, z) * 180 / .pi
            return GlobeCoordinate(latitude: latitude, longitude: longitude)
        }

        private func countryCode(containing coordinate: GlobeCoordinate) -> String? {
            guard let boundaryData else { return nil }
            let availableCodes = Set(currentCountries.map(\.code))

            for countryCode in availableCodes {
                guard let rings = boundaryData.ringsByCountryCode[countryCode] else { continue }
                if rings.contains(where: { ringContains(coordinate, ring: $0) }) {
                    return countryCode
                }
            }

            return nil
        }

        private func ringContains(_ coordinate: GlobeCoordinate, ring: [GlobeCoordinate]) -> Bool {
            guard ring.count > 2 else { return false }
            var isInside = false
            var previous = ring[ring.count - 1]

            for current in ring {
                let crossesLatitude = (current.latitude > coordinate.latitude) != (previous.latitude > coordinate.latitude)
                if crossesLatitude {
                    let longitudeAtLatitude = (previous.longitude - current.longitude) * (coordinate.latitude - current.latitude) / (previous.latitude - current.latitude) + current.longitude
                    if coordinate.longitude < longitudeAtLatitude {
                        isInside.toggle()
                    }
                }
                previous = current
            }

            return isInside
        }
    }
}

let globeBoundarySource = "ne_50m_admin_0_map_units"
let globeBoundaryURLString = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_map_units.geojson"
let globeMainlandFocusByCountryCode: [String: GlobeCoordinate] = [
    "FR": GlobeCoordinate(latitude: 46.6, longitude: 2.4),
    "GB": GlobeCoordinate(latitude: 54.6, longitude: -2.5),
    "NL": GlobeCoordinate(latitude: 52.2, longitude: 5.3),
    "DK": GlobeCoordinate(latitude: 56.1, longitude: 10.0),
    "NO": GlobeCoordinate(latitude: 61.3, longitude: 8.2),
    "ES": GlobeCoordinate(latitude: 40.3, longitude: -3.7),
    "PT": GlobeCoordinate(latitude: 39.6, longitude: -8.0),
    "US": GlobeCoordinate(latitude: 39.8, longitude: -98.6),
    "CA": GlobeCoordinate(latitude: 56.1, longitude: -106.3),
    "AU": GlobeCoordinate(latitude: -25.3, longitude: 134.8),
    "NZ": GlobeCoordinate(latitude: -41.3, longitude: 174.8)
]

enum GlobeBoundaryCache {
    static var source: String?
    static var data: GlobeBoundaryData?
}

struct GlobeCoordinate {
    let latitude: Double
    let longitude: Double
}

struct GlobeBoundaryData {
    let rings: [[GlobeCoordinate]]
    let ringsByCountryCode: [String: [[GlobeCoordinate]]]
    let centroidsByCountryCode: [String: GlobeCoordinate]

    static func parse(data: Data) -> GlobeBoundaryData? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else {
            return nil
        }

        var rings: [[GlobeCoordinate]] = []
        var ringsByCountryCode: [String: [[GlobeCoordinate]]] = [:]
        var centroidsByCountryCode: [String: GlobeCoordinate] = [:]

        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any] else { continue }
            let featureRings = parseRings(from: geometry)
            rings.append(contentsOf: featureRings)

            if
                let properties = feature["properties"] as? [String: Any],
                let countryCode = normalizedCountryCode(from: properties),
                let centroid = centroid(from: featureRings)
            {
                ringsByCountryCode[countryCode, default: []].append(contentsOf: featureRings)
                centroidsByCountryCode[countryCode] = centroid
            }
        }

        return GlobeBoundaryData(rings: rings, ringsByCountryCode: ringsByCountryCode, centroidsByCountryCode: centroidsByCountryCode)
    }

    private static func parseRings(from geometry: [String: Any]) -> [[GlobeCoordinate]] {
        guard let type = geometry["type"] as? String else { return [] }

        if type == "Polygon", let polygons = geometry["coordinates"] as? [[[Double]]] {
            return polygons.map { parseRing($0) }.filter { !$0.isEmpty }
        }

        if type == "MultiPolygon", let multiPolygons = geometry["coordinates"] as? [[[[Double]]]] {
            return multiPolygons.flatMap { polygon in
                polygon.map { parseRing($0) }.filter { !$0.isEmpty }
            }
        }

        return []
    }

    private static func parseRing(_ rawRing: [[Double]]) -> [GlobeCoordinate] {
        rawRing.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return GlobeCoordinate(latitude: pair[1], longitude: pair[0])
        }
    }

    static func centroid(from rings: [[GlobeCoordinate]]) -> GlobeCoordinate? {
        let allCoordinates = rings.flatMap { $0 }
        guard !allCoordinates.isEmpty else { return nil }
        let latitude = allCoordinates.reduce(0) { $0 + $1.latitude } / Double(allCoordinates.count)
        let longitude = allCoordinates.reduce(0) { $0 + $1.longitude } / Double(allCoordinates.count)
        return GlobeCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func normalizedCountryCode(from properties: [String: Any]) -> String? {
        let codeCandidates = [
            properties["ISO_A2"] as? String,
            properties["iso_a2"] as? String,
            properties["ISO_A2_EH"] as? String,
            properties["iso_a2_eh"] as? String,
            properties["WB_A2"] as? String,
            properties["ADM0_A3"] as? String,
            properties["adm0_a3"] as? String,
            properties["ADM0_ISO"] as? String,
            properties["adm0_iso"] as? String,
            properties["GU_A3"] as? String,
            properties["gu_a3"] as? String,
            properties["SU_A3"] as? String,
            properties["su_a3"] as? String,
            properties["SOV_A3"] as? String,
            properties["sov_a3"] as? String
        ].compactMap { $0?.uppercased() }

        if let rawCode = codeCandidates.first(where: { !$0.isEmpty && $0 != "-99" }) {
            switch rawCode {
            case "XK", "XKX": return "XK"
            case "GBR", "ENG", "SCT", "WLS", "NIR": return "GB"
            case "FRA": return "FR"
            case "NOR": return "NO"
            case "GRL": return "GL"
            case "FRO": return "FO"
            case "COK": return "CK"
            case "NIU": return "NU"
            case "ABK": return "AB"
            case "SOO": return "OS"
            case "CYN": return "NC"
            case "SOL": return "SLD"
            default:
                if rawCode.count == 2 { return rawCode }
            }
        }

        let nameCandidates = [
            properties["NAME"] as? String,
            properties["name"] as? String,
            properties["NAME_LONG"] as? String,
            properties["name_long"] as? String,
            properties["ADMIN"] as? String,
            properties["admin"] as? String
        ].compactMap { $0?.lowercased() }

        if nameCandidates.contains(where: { $0.contains("united kingdom") || $0 == "england" || $0 == "scotland" || $0 == "wales" || $0.contains("northern ireland") }) { return "GB" }
        if nameCandidates.contains(where: { $0.contains("france") }) { return "FR" }
        if nameCandidates.contains(where: { $0.contains("norway") }) { return "NO" }
        if nameCandidates.contains(where: { $0.contains("greenland") }) { return "GL" }
        if nameCandidates.contains(where: { $0.contains("faroe") }) { return "FO" }
        if nameCandidates.contains(where: { $0.contains("cook islands") }) { return "CK" }
        if nameCandidates.contains(where: { $0.contains("niue") }) { return "NU" }
        if nameCandidates.contains(where: { $0.contains("abkhazia") }) { return "AB" }
        if nameCandidates.contains(where: { $0.contains("south ossetia") }) { return "OS" }
        if nameCandidates.contains(where: { $0.contains("northern cyprus") || $0.contains("n. cyprus") }) { return "NC" }
        if nameCandidates.contains(where: { $0.contains("somaliland") }) { return "SLD" }

        return nil
    }
}

private extension MasteryTier {
    var globeUIColor: UIColor {
        switch self {
        case .s: return UIColor(red: 0.18, green: 0.42, blue: 0.95, alpha: 1)
        case .a: return UIColor(red: 0.18, green: 0.78, blue: 0.32, alpha: 1)
        case .b: return UIColor(red: 0.0, green: 0.78, blue: 0.62, alpha: 1)
        case .c: return UIColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1)
        case .d: return UIColor(red: 0.95, green: 0.45, blue: 0.14, alpha: 1)
        case .f: return UIColor(red: 0.9, green: 0.18, blue: 0.22, alpha: 1)
        }
    }
}

