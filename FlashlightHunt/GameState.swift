import Foundation

enum GamePhase: Equatable {
    case scanning
    case hiding       // switch placed, about to go dark
    case searching
    case found
    case won(seconds: Int)
}

class GameState: ObservableObject {
    @Published var phase: GamePhase = .scanning
    @Published var scanMessage = "Walk around slowly to detect walls…"

    private var startTime: Date?

    func switchWasPlaced() {
        phase = .hiding
        scanMessage = "Switch hidden. Lights out in 2…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.phase = .searching
            self?.startTime = Date()
        }
    }

    func markFound() {
        guard phase == .searching else { return }
        phase = .found
    }

    func markLost() {
        guard phase == .found else { return }
        phase = .searching
    }

    func win() {
        guard phase == .found else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        phase = .won(seconds: elapsed)
    }

    func reset() {
        phase = .scanning
        scanMessage = "Walk around slowly to detect walls…"
        startTime = nil
    }
}
