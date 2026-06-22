import SwiftUI
import ARKit
import SceneKit

struct ARSceneView: UIViewRepresentable {
    @ObservedObject var gameState: GameState

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        view.scene = SCNScene()
        view.autoenablesDefaultLighting = true
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        context.coordinator.sceneView = view

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.vertical]
        view.session.run(config)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        switch gameState.phase {
        case .scanning, .hiding:
            uiView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        default:
            uiView.debugOptions = []
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(gameState: gameState) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let gameState: GameState
        weak var sceneView: ARSCNView?

        private var switchNode: SCNNode?
        private var switchFamily: Set<ObjectIdentifier> = []
        private var switchPlaced = false
        private var lastCheckTime: TimeInterval = 0

        // Scan progress
        private var planeAreas: [UUID: Float] = [:]
        private let targetArea: Float = 0.5   // m² of wall needed for 100 %

        // Haptics — created once, reused each pulse
        private let lightFX  = UIImpactFeedbackGenerator(style: .light)
        private let mediumFX = UIImpactFeedbackGenerator(style: .medium)
        private let heavyFX  = UIImpactFeedbackGenerator(style: .heavy)
        private var lastHapticTime: TimeInterval = 0

        init(gameState: GameState) {
            self.gameState = gameState
            super.init()
            lightFX.prepare(); mediumFX.prepare(); heavyFX.prepare()
        }

        // MARK: Plane detected

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .vertical else { return }

            let area = plane.planeExtent.width * plane.planeExtent.height
            planeAreas[plane.identifier] = area
            pushScanProgress()
            addPlaneViz(to: node, plane: plane)

            guard !switchPlaced, area > 0.05 else { return }
            switchPlaced = true

            let sw = makeSwitchNode()
            let halfW = min(plane.planeExtent.width / 2, 0.35)
            sw.position = SCNVector3(
                Float.random(in: -halfW...halfW),
                Float.random(in: 0.0...0.6),
                0
            )
            node.addChildNode(sw)
            switchNode = sw

            var fam: Set<ObjectIdentifier> = [ObjectIdentifier(sw)]
            sw.enumerateChildNodes { n, _ in fam.insert(ObjectIdentifier(n)) }
            switchFamily = fam

            DispatchQueue.main.async { self.gameState.switchWasPlaced() }
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .vertical else { return }

            planeAreas[plane.identifier] = plane.planeExtent.width * plane.planeExtent.height
            pushScanProgress()
            updatePlaneViz(on: node, plane: plane)
        }

        private func pushScanProgress() {
            let total = planeAreas.values.reduce(0, +)
            let p = Double(min(total / targetArea, 1.0))
            DispatchQueue.main.async { self.gameState.scanProgress = p }
        }

        // MARK: Per-frame

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard time - lastCheckTime > 0.05 else { return }
            lastCheckTime = time

            guard let sv = sceneView, !switchFamily.isEmpty else { return }
            let ph = gameState.phase
            guard ph == .searching || ph == .found else { return }

            // Binary spotlight hit test (crosshair dead-center)
            let center = CGPoint(x: sv.bounds.midX, y: sv.bounds.midY)
            let hits = sv.hitTest(center, options: nil)
            let inSpot = hits.contains { switchFamily.contains(ObjectIdentifier($0.node)) }

            DispatchQueue.main.async {
                if inSpot { self.gameState.markFound(); self.setGlow(true) }
                else       { self.gameState.markLost();  self.setGlow(false) }
            }

            // Proximity haptics (searching only)
            if ph == .searching, let dist = screenDistance(to: switchNode, in: sv) {
                driveHaptics(screenDist: dist, at: time)
            }
        }

        // Projects switch world position to screen and returns distance from center.
        // Returns nil if the switch is behind the camera.
        private func screenDistance(to node: SCNNode?, in sv: ARSCNView) -> Double? {
            guard let node, let pov = sv.pointOfView else { return nil }

            // Camera forward = -Z column of world transform
            let col2 = pov.simdWorldTransform.columns.2
            let camFwd = simd_float3(-col2.x, -col2.y, -col2.z)
            let toSwitch = node.simdWorldPosition - pov.simdWorldPosition
            guard simd_dot(simd_normalize(toSwitch), camFwd) > 0 else { return nil }

            let p = sv.projectPoint(node.worldPosition)
            guard p.z < 1 else { return nil }   // behind far plane

            return hypot(Double(p.x) - Double(sv.bounds.midX),
                         Double(p.y) - Double(sv.bounds.midY))
        }

        private func driveHaptics(screenDist: Double, at time: TimeInterval) {
            // Map screen distance → pulse interval + generator
            let (interval, gen): (TimeInterval, UIImpactFeedbackGenerator)
            switch screenDist {
            case ..<55:   (interval, gen) = (0.15, heavyFX)
            case ..<110:  (interval, gen) = (0.30, heavyFX)
            case ..<175:  (interval, gen) = (0.60, mediumFX)
            case ..<260:  (interval, gen) = (1.20, lightFX)
            default: return
            }

            guard time - lastHapticTime >= interval else { return }
            lastHapticTime = time
            DispatchQueue.main.async {
                gen.impactOccurred()
                gen.prepare()
            }
        }

        // MARK: Glow

        private func setGlow(_ on: Bool) {
            let color: UIColor = on ? .yellow.withAlphaComponent(0.7) : .clear
            switchNode?.geometry?.firstMaterial?.emission.contents = color
            switchNode?.enumerateChildNodes { n, _ in
                n.geometry?.firstMaterial?.emission.contents = color
            }
        }

        // MARK: Plane visualization

        private func addPlaneViz(to node: SCNNode, plane: ARPlaneAnchor) {
            let geo = SCNPlane(width: CGFloat(plane.planeExtent.width),
                               height: CGFloat(plane.planeExtent.height))
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.cyan.withAlphaComponent(0.22)
            mat.isDoubleSided = true
            geo.materials = [mat]
            let vizNode = SCNNode(geometry: geo)
            vizNode.name = "viz"
            let c = plane.center
            vizNode.position = SCNVector3(c.x, c.y, c.z)
            node.addChildNode(vizNode)
        }

        private func updatePlaneViz(on node: SCNNode, plane: ARPlaneAnchor) {
            guard let viz = node.childNode(withName: "viz", recursively: false),
                  let geo = viz.geometry as? SCNPlane else { return }
            geo.width  = CGFloat(plane.planeExtent.width)
            geo.height = CGFloat(plane.planeExtent.height)
            let c = plane.center
            viz.position = SCNVector3(c.x, c.y, c.z)
        }

        // MARK: Switch geometry

        private func makeSwitchNode() -> SCNNode {
            let root = SCNNode()

            let plate = SCNBox(width: 0.072, height: 0.108, length: 0.009, chamferRadius: 0.005)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = UIColor(white: 0.93, alpha: 1)
            pMat.lightingModel = .physicallyBased
            plate.materials = [pMat]
            let plateNode = SCNNode(geometry: plate)

            let toggle = SCNBox(width: 0.026, height: 0.044, length: 0.013, chamferRadius: 0.003)
            let tMat = SCNMaterial()
            tMat.diffuse.contents = UIColor(white: 0.78, alpha: 1)
            tMat.lightingModel = .physicallyBased
            toggle.materials = [tMat]
            let toggleNode = SCNNode(geometry: toggle)
            toggleNode.position = SCNVector3(0, 0.009, 0.011)

            plateNode.addChildNode(toggleNode)
            root.addChildNode(plateNode)
            return root
        }
    }
}
