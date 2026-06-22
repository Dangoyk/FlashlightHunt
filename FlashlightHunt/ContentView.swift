import SwiftUI

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @State private var gameID = 0

    var body: some View {
        ZStack {
            ARSceneView(gameState: gameState)
                .ignoresSafeArea()

            switch gameState.phase {
            case .scanning, .hiding:
                scanningOverlay

            case .searching:
                SpotlightOverlay(glowing: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                searchHint

            case .found:
                SpotlightOverlay(glowing: true)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                tapPrompt

            case .won(let seconds):
                wonView(seconds: seconds)
            }
        }
        .id(gameID)
        .onTapGesture {
            if case .found = gameState.phase {
                gameState.win()
            }
        }
    }

    // MARK: - Overlays

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.3)
                Text(gameState.scanMessage)
                    .foregroundColor(.white)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
        }
    }

    private var searchHint: some View {
        VStack {
            Text("Find the light switch")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 64)
            Spacer()
        }
    }

    private var tapPrompt: some View {
        VStack {
            Spacer()
            Text("TAP IT!")
                .font(.system(size: 44, weight: .black))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.8), radius: 20)
                .padding(.bottom, 90)
        }
    }

    private func wonView(seconds: Int) -> some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text("💡")
                    .font(.system(size: 90))
                Text("LIGHTS ON")
                    .font(.largeTitle)
                    .fontWeight(.black)
                Text("Found in \(seconds)s")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Button("Play Again") {
                    gameState.reset()
                    gameID += 1
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
                Spacer()
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }
}
