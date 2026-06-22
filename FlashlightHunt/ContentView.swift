import SwiftUI

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @State private var gameID = 0

    var body: some View {
        ZStack {
            // AR scene runs during all phases except the menu
            if gameState.phase != .menu {
                ARSceneView(gameState: gameState)
                    .ignoresSafeArea()
                    .id(gameID)
            }

            switch gameState.phase {
            case .menu:
                menuView

            case .scanning, .hiding:
                scanningOverlay

            case .searching:
                SpotlightOverlay(glowing: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                searchHint
                giveUpButton

            case .found:
                SpotlightOverlay(glowing: true)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                tapPrompt
                giveUpButton

            case .gaveUp:
                gaveUpOverlay

            case .won(let seconds):
                wonView(seconds: seconds)
            }
        }
        .onTapGesture {
            if case .found = gameState.phase { gameState.win() }
        }
    }

    // MARK: - Menu

    private var menuView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "flashlight.on.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.6), radius: 24)
                    .padding(.bottom, 28)

                Text("FLASHLIGHT\nHUNT")
                    .font(.system(size: 46, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Find the hidden switch in the dark")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 52)

                if let best = gameState.bestTime {
                    VStack(spacing: 4) {
                        Text("BEST TIME")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(3)
                        Text("\(best)s")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.bottom, 44)
                }

                Button(action: {
                    gameState.startGame()
                    gameID += 1
                }) {
                    Text("Start Game")
                        .font(.headline)
                        .frame(width: 220)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                }

                Spacer()

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Scanning

    private var scanningOverlay: some View {
        ZStack {
            // Vignette: the "edge of paint" the user described.
            // Transparent center reveals the sphere (and through its holes, the real room).
            // Solid black at edges — always, regardless of what the sphere shows there —
            // so the player always sees a crisp paint boundary around the camera view.
            GeometryReader { geo in
                let endRadius = min(geo.size.width, geo.size.height) * 0.62
                RadialGradient(
                    stops: [
                        .init(color: .clear,              location: 0),
                        .init(color: .clear,              location: 0.48),
                        .init(color: .black.opacity(0.6), location: 0.72),
                        .init(color: .black,              location: 1.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: endRadius
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Crosshair so the player knows exactly what they're scratching
            scanReticle

            // Minimal HUD
            VStack {
                Text(scanStatusText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.top, 60)

                Spacer()

                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.7))
                                .frame(width: geo.size.width * gameState.scanProgress)
                                .animation(.easeOut(duration: 0.3), value: gameState.scanProgress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 40)

                    Text("\(Int(gameState.scanProgress * 100))% walls detected")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))

                    Text("v\(appVersion)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.bottom, 44)
            }
        }
    }

    private var scanReticle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                .frame(width: 22, height: 22)
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 12, height: 1)
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 1, height: 12)
        }
    }

    private var scanStatusText: String {
        switch gameState.phase {
        case .hiding: return "Hiding the switch…"
        default:
            switch gameState.scanProgress {
            case ..<0.25: return "Sweep your phone around to reveal the room"
            case ..<0.6:  return "Look in all directions"
            case ..<0.9:  return "Almost there…"
            default:      return "Looking good!"
            }
        }
    }

    // MARK: - Gameplay

    private var searchHint: some View {
        VStack {
            Text("Find the light switch")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
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
                .padding(.bottom, 120)
        }
    }

    private var giveUpButton: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: { gameState.giveUp() }) {
                    Label("I give up", systemImage: "flag.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                }
                .padding(.leading, 20)
                .padding(.bottom, 44)
                Spacer()
            }
        }
    }

    // MARK: - Give Up reveal

    private var gaveUpOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Text("😬")
                    .font(.system(size: 52))
                Text("It was right there!")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                Text("Look around — the switch is glowing")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    Button("Try Again") {
                        gameState.reset()
                        gameID += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)

                    Button("Main Menu") {
                        gameState.resetToMenu()
                        gameID += 1
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundColor(.white)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(20)
        }
    }

    // MARK: - Won

    private func wonView(seconds: Int) -> some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text("💡")
                    .font(.system(size: 90))
                Text("LIGHTS ON")
                    .font(.largeTitle).fontWeight(.black)
                Text("Found in \(seconds)s")
                    .font(.title2)
                    .foregroundColor(.secondary)
                if let best = gameState.bestTime, seconds == best {
                    Text("New best!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                }
                HStack(spacing: 14) {
                    Button("Play Again") {
                        gameState.reset()
                        gameID += 1
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Main Menu") {
                        gameState.resetToMenu()
                        gameID += 1
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
                Spacer()
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
            }
        }
    }
}
