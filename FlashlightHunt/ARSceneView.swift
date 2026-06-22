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
        context.coordinator.setupScratchSphere(in: view.scene)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.vertical]
        view.session.run(config)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        switch gameState.phase {
        case .scanning, .hiding:
            uiView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        case .searching, .found:
            context.coordinator.revealRoom()     // fade sphere away, show camera
            uiView.debugOptions = []
        case .gaveUp:
            uiView.debugOptions = []
            context.coordinator.revealSwitch()
        default:
            uiView.debugOptions = []
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(gameState: gameState) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let gameState: GameState
        weak var sceneView: ARSCNView?

        // Switch state
        private var switchNode: SCNNode?
        private var switchFamily: Set<ObjectIdentifier> = []
        private var switchPlaced = false
        private var lastCheckTime: TimeInterval = 0
        var isRevealingSwitch = false

        // Wall-area tracking (for the scan-progress bar only, no visible planes)
        private var planeAreas: [UUID: Float] = [:]
        private let targetArea: Float = 0.5

        // Scratch-sphere
        private static let texW = 512
        private static let texH = 256
        private var scratchCtx: CGContext?
        private var sphereNode: SCNNode?
        private var sphereGeo: SCNSphere?
        private var sphereRevealed = false
        private var lastScratchTime: TimeInterval = 0

        // Haptics
        private let lightFX  = UIImpactFeedbackGenerator(style: .light)
        private let mediumFX = UIImpactFeedbackGenerator(style: .medium)
        private let heavyFX  = UIImpactFeedbackGenerator(style: .heavy)
        private var lastHapticTime: TimeInterval = 0

        init(gameState: GameState) {
            self.gameState = gameState
            super.init()
            lightFX.prepare(); mediumFX.prepare(); heavyFX.prepare()
        }

        // MARK: Scratch-sphere setup

        func setupScratchSphere(in scene: SCNScene) {
            let w = Self.texW, h = Self.texH
            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            // Start fully opaque black — the "no depth" paint layer the player scratches through
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            scratchCtx = ctx

            let geo = SCNSphere(radius: 8)
            geo.segmentCount = 72
            let mat = SCNMaterial()
            mat.diffuse.contents = sphereImage()
            mat.transparencyMode  = .aOne          // alpha=0 → transparent, alpha=1 → opaque
            mat.lightingModel     = .constant       // flat black — reads as a 2D sheet, not a sphere
            mat.cullMode          = .front          // camera is inside; render the inner surface
            mat.isDoubleSided     = false
            geo.materials = [mat]

            let node = SCNNode(geometry: geo)
            scene.rootNode.addChildNode(node)
            sphereNode = node
            sphereGeo  = geo
        }

        // Fade the sphere out and remove it when gameplay starts
        func revealRoom() {
            guard !sphereRevealed, let node = sphereNode else { return }
            sphereRevealed = true
            node.runAction(.sequence([
                .fadeOut(duration: 0.6),
                .removeFromParentNode()
            ]))
        }

        // Convert camera forward direction → UV on the sphere, then punch a transparent hole.
        private func scratchSphere(cameraForward fwd: simd_float3) {
            guard let ctx = scratchCtx else { return }

            let n = simd_normalize(fwd)

            // Standard equirectangular UV for the sphere's surface normal
            // atan2(x, -z): 0 when looking in -Z (SceneKit "into scene"), seam at +Z
            let az = atan2f(n.x, -n.z)                           // −π … +π
            let el = asinf(max(-1, min(1, n.y)))                  // −π/2 … +π/2

            let tx = CGFloat(Double(az) / (2 * .pi) + 0.5) * CGFloat(Self.texW)
            // CGContext origin is bottom-left; sphere UV v=0 = north pole (up) = bottom of CGContext ✓
            let ty = CGFloat(0.5 - Double(el) / .pi) * CGFloat(Self.texH)

            punchHole(ctx: ctx, at: CGPoint(x: tx, y: ty))

            // Wrap seam horizontally so the scratch doesn't cut off at the texture edge
            let r = CGFloat(18)
            if tx < r        { punchHole(ctx: ctx, at: CGPoint(x: tx + CGFloat(Self.texW), y: ty)) }
            if tx > CGFloat(Self.texW) - r { punchHole(ctx: ctx, at: CGPoint(x: tx - CGFloat(Self.texW), y: ty)) }

            sphereGeo?.firstMaterial?.diffuse.contents = sphereImage()
        }

        // Draw a soft transparent hole using CGContext .clear blend mode.
        // .clear erases destination pixels proportional to the source alpha.
        private func punchHole(ctx: CGContext, at center: CGPoint) {
            let cs = CGColorSpaceCreateDeviceRGB()
            // Gradient: opaque white at center (fully erases) → transparent at edge (erases nothing).
            // Small radius (18 px ≈ 13° of arc) so the player must sweep deliberately to reveal the room.
            let colors: [CGColor] = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.85).cgColor,
                UIColor.white.withAlphaComponent(0.3).cgColor,
                UIColor.clear.cgColor,
            ]
            let locs: [CGFloat] = [0, 0.4, 0.75, 1.0]
            guard let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)
            else { return }

            ctx.setBlendMode(.clear)
            ctx.drawRadialGradient(grad,
                                   startCenter: center, startRadius: 0,
                                   endCenter:   center, endRadius:   18,
                                   options: [.drawsAfterEndLocation])
            ctx.setBlendMode(.normal)
        }

        private func sphereImage() -> UIImage? {
            guard let ctx = scratchCtx, let cgImg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cgImg)
        }

        // MARK: Plane detection (tracking area for progress bar only — no visible planes)

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .vertical else { return }

            let area = plane.planeExtent.width * plane.planeExtent.height
            planeAreas[plane.identifier] = area
            pushScanProgress()

            guard !switchPlaced, area > 0.05,
                  let sv = sceneView, let pov = sv.pointOfView else { return }
            switchPlaced = true

            let sw = makeSwitchNode()

            // Explicit world-space transform: always upright, face toward camera.
            let col3 = plane.transform.columns.3
            let planeWorldPos = simd_float3(col3.x, col3.y, col3.z)
            let camPos = pov.simdWorldPosition

            var toCamera = camPos - planeWorldPos
            toCamera.y = 0
            let len = simd_length(toCamera)
            let fwd: simd_float3 = len > 0.01 ? toCamera / len : simd_float3(0, 0, 1)

            let worldUp = simd_float3(0, 1, 0)
            let right = simd_normalize(simd_cross(worldUp, fwd))

            let halfW = min(plane.planeExtent.width / 2, 0.35)
            let switchPos = simd_float3(
                planeWorldPos.x + right.x * Float.random(in: -halfW...halfW) + fwd.x * 0.01,
                planeWorldPos.y + Float.random(in: 0.05...0.7),
                planeWorldPos.z + right.z * Float.random(in: -halfW...halfW) + fwd.z * 0.01
            )

            sw.simdTransform = simd_float4x4(columns: (
                simd_float4(right.x,    right.y,    right.z,    0),
                simd_float4(worldUp.x,  worldUp.y,  worldUp.z,  0),
                simd_float4(fwd.x,      fwd.y,      fwd.z,      0),
                simd_float4(switchPos.x, switchPos.y, switchPos.z, 1)
            ))
            sv.scene.rootNode.addChildNode(sw)

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
        }

        private func pushScanProgress() {
            let total = planeAreas.values.reduce(0, +)
            let p = Double(min(total / targetArea, 1.0))
            DispatchQueue.main.async { self.gameState.scanProgress = p }
        }

        // MARK: Per-frame

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let ph = gameState.phase

            // Scratch the sphere ~20 fps during scanning
            if (ph == .scanning || ph == .hiding),
               time - lastScratchTime > 0.05,
               let frame = sceneView?.session.currentFrame {
                lastScratchTime = time
                let c2 = frame.camera.transform.columns.2
                scratchSphere(cameraForward: simd_float3(-c2.x, -c2.y, -c2.z))
            }

            guard time - lastCheckTime > 0.05 else { return }
            lastCheckTime = time

            guard let sv = sceneView, !switchFamily.isEmpty else { return }
            guard ph == .searching || ph == .found else { return }

            let center = CGPoint(x: sv.bounds.midX, y: sv.bounds.midY)
            let hits = sv.hitTest(center, options: nil)
            let inSpot = hits.contains { switchFamily.contains(ObjectIdentifier($0.node)) }

            DispatchQueue.main.async {
                if inSpot { self.gameState.markFound(); self.setGlow(true) }
                else       { self.gameState.markLost();  self.setGlow(false) }
            }

            if ph == .searching, let dist = screenDistance(to: switchNode, in: sv) {
                driveHaptics(screenDist: dist, at: time)
            }
        }

        private func screenDistance(to node: SCNNode?, in sv: ARSCNView) -> Double? {
            guard let node, let pov = sv.pointOfView else { return nil }
            let col2 = pov.simdWorldTransform.columns.2
            let camFwd = simd_float3(-col2.x, -col2.y, -col2.z)
            let toSwitch = node.simdWorldPosition - pov.simdWorldPosition
            guard simd_dot(simd_normalize(toSwitch), camFwd) > 0 else { return nil }
            let p = sv.projectPoint(node.worldPosition)
            guard p.z < 1 else { return nil }
            return hypot(Double(p.x) - Double(sv.bounds.midX),
                         Double(p.y) - Double(sv.bounds.midY))
        }

        private func driveHaptics(screenDist: Double, at time: TimeInterval) {
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
            DispatchQueue.main.async { gen.impactOccurred(); gen.prepare() }
        }

        // MARK: Give-up reveal

        func revealSwitch() {
            guard !isRevealingSwitch, let sw = switchNode else { return }
            isRevealingSwitch = true
            setGlow(true)

            let grow   = SCNAction.scale(to: 1.5, duration: 0.35)
            let shrink = SCNAction.scale(to: 1.0, duration: 0.35)
            sw.runAction(.repeatForever(.sequence([grow, shrink])), forKey: "reveal")

            let light = SCNLight()
            light.type = .omni
            light.color = UIColor.yellow
            light.intensity = 1500
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(0, 0, 0.15)
            sw.addChildNode(lightNode)
        }

        // MARK: Glow

        private func setGlow(_ on: Bool) {
            let color: UIColor = on ? .yellow.withAlphaComponent(0.7) : .clear
            switchNode?.geometry?.firstMaterial?.emission.contents = color
            switchNode?.enumerateChildNodes { n, _ in
                guard n.light == nil else { return }
                n.geometry?.firstMaterial?.emission.contents = color
            }
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
