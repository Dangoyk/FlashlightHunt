import SwiftUI
import UIKit

// UIViewRepresentable wrapper so we get full CGContext control for the cutout effect.
struct SpotlightOverlay: UIViewRepresentable {
    var glowing: Bool

    func makeUIView(context: Context) -> SpotlightUIView {
        SpotlightUIView()
    }

    func updateUIView(_ uiView: SpotlightUIView, context: Context) {
        uiView.glowing = glowing
    }
}

final class SpotlightUIView: UIView {
    var glowing = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cs = CGColorSpaceCreateDeviceRGB()

        // 1. Black overlay
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.96).cgColor)
        ctx.fill(rect)

        // 2. Cut a soft circular hole using destinationOut
        // Gradient: opaque white at center → transparent at radius 110
        // With destinationOut, opaque = fully erased, transparent = not erased
        let holeColors: [CGColor] = [
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.5).cgColor,
            UIColor.clear.cgColor,
        ]
        let holeLocs: [CGFloat] = [0, 0.4, 0.72, 1.0]
        guard let holeGrad = CGGradient(colorsSpace: cs, colors: holeColors as CFArray, locations: holeLocs) else { return }

        ctx.setBlendMode(.destinationOut)
        ctx.drawRadialGradient(holeGrad,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: 110,
                               options: [])

        // 3. Yellow glow ring when switch is in spotlight
        if glowing {
            let glowColors: [CGColor] = [
                UIColor.yellow.withAlphaComponent(0).cgColor,
                UIColor.yellow.withAlphaComponent(0).cgColor,
                UIColor.yellow.withAlphaComponent(0.45).cgColor,
                UIColor.yellow.withAlphaComponent(0.12).cgColor,
                UIColor.yellow.withAlphaComponent(0).cgColor,
            ]
            let glowLocs: [CGFloat] = [0, 0.35, 0.6, 0.8, 1.0]
            guard let glowGrad = CGGradient(colorsSpace: cs, colors: glowColors as CFArray, locations: glowLocs) else { return }

            ctx.setBlendMode(.normal)
            ctx.drawRadialGradient(glowGrad,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: 180,
                                   options: [])
        }
    }
}
