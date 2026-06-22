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
            if case .found = gameState.phase { gameState.win() }
        }
    }

    // MARK: - Scanning overlay

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                        .frame(width: 130, height: 130)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: gameState.scanProgress)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: gameState.scanProgress)

                    ringCenter
                }

                VStack(spacing: 6) {
                    Text(scanStatusText)
                        .foregroundColor(.white)
                        .font(.headline)
                        .animation(.default, value: gameState.phase)

                    if case .scanning = gameState.phase {
                        Text("Move your phone slowly around the room")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(40)
        }
    }

    @ViewBuilder
    private var ringCenter: some View {
        switch gameState.phase {
        case .hiding:
            Image(systemName: "lightswitch.off")
                .font(.system(size: 30))
                .foregroundColor(.white)
        default:
            VStack(spacing: 2) {
                Text("\(Int(gameState.scanProgress * 100))%")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text("walls")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var scanStatusText: String {
        switch gameState.phase {
        case .hiding: return "Hiding the switch…"
        default:
            switch gameState.scanProgress {
            case ..<0.3: return "Scanning walls…"
            case ..<0.6: return "Getting there…"
            case ..<0.9: return "Almost ready…"
            default:     return "Looking good!"
            }
        }
    }

    // MARK: - Gameplay overlays

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
