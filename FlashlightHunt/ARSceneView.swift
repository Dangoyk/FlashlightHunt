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
        context.coordinator.sceneView = view

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.vertical]
        view.session.run(config)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(gameState: gameState)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let gameState: GameState
        weak var sceneView: ARSCNView?

        private var switchNode: SCNNode?
        private var switchFamily: Set<ObjectIdentifier> = []  // ObjectIdentifiers of all switch nodes
        private var switchPlaced = false
        private var lastCheckTime: TimeInterval = 0

        init(gameState: GameState) {
            self.gameState = gameState
        }

        // ARKit found a new surface anchor
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard !switchPlaced,
                  let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .vertical else { return }

            switchPlaced = true

            let sw = makeSwitchNode()

            // Random position within the detected wall extent (capped so it stays findable)
            let halfW = min(plane.planeExtent.width / 2, 0.35)
            sw.position = SCNVector3(
                Float.random(in: -halfW...halfW),
                Float.random(in: 0.0...0.6),   // 0–60 cm above plane center
                0
            )
            node.addChildNode(sw)
            switchNode = sw

            // Cache all node identifiers in the switch hierarchy for fast hit-test lookup
            var family: Set<ObjectIdentifier> = [ObjectIdentifier(sw)]
            sw.enumerateChildNodes { child, _ in family.insert(ObjectIdentifier(child)) }
            switchFamily = family

            DispatchQueue.main.async { self.gameState.switchWasPlaced() }
        }

        // Called every frame on the render thread (~60 fps)
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard time - lastCheckTime > 0.05 else { return }   // throttle to ~20 checks/s
            lastCheckTime = time

            guard let sv = sceneView, !switchFamily.isEmpty else { return }
            let ph = gameState.phase
            guard ph == .searching || ph == .found else { return }

            // Hit-test the exact center of the screen (the spotlight crosshair)
            let center = CGPoint(x: sv.bounds.midX, y: sv.bounds.midY)
            let hits = sv.hitTest(center, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            let inSpot = hits.contains { switchFamily.contains(ObjectIdentifier($0.node)) }

            DispatchQueue.main.async {
                if inSpot {
                    self.gameState.markFound()
                    self.setGlow(true)
                } else {
                    self.gameState.markLost()
                    self.setGlow(false)
                }
            }
        }

        // MARK: - Helpers

        private func setGlow(_ on: Bool) {
            let color: UIColor = on ? UIColor.yellow.withAlphaComponent(0.7) : .clear
            switchNode?.enumerateHierarchy { node, _ in
                node.geometry?.firstMaterial?.emission.contents = color
            }
        }

        private func makeSwitchNode() -> SCNNode {
            let root = SCNNode()

            // Face plate
            let plate = SCNBox(width: 0.072, height: 0.108, length: 0.009, chamferRadius: 0.005)
            let plateMat = SCNMaterial()
            plateMat.diffuse.contents = UIColor(white: 0.93, alpha: 1)
            plateMat.lightingModel = .physicallyBased
            plate.materials = [plateMat]
            let plateNode = SCNNode(geometry: plate)

            // Toggle lever
            let toggle = SCNBox(width: 0.026, height: 0.044, length: 0.013, chamferRadius: 0.003)
            let toggleMat = SCNMaterial()
            toggleMat.diffuse.contents = UIColor(white: 0.78, alpha: 1)
            toggleMat.lightingModel = .physicallyBased
            toggle.materials = [toggleMat]
            let toggleNode = SCNNode(geometry: toggle)
            toggleNode.position = SCNVector3(0, 0.009, 0.011)

            plateNode.addChildNode(toggleNode)
            root.addChildNode(plateNode)
            return root
        }
    }
}
