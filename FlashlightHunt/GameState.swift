import Foundation

enum GamePhase: Equatable {
    case menu
    case scanning
    case hiding
    case searching
    case found
    case gaveUp
    case won(seconds: Int)
}

class GameState: ObservableObject {
    @Published var phase: GamePhase = .menu
    @Published var scanProgress: Double = 0
    @Published var bestTime: Int? = {
        let t = UserDefaults.standard.integer(forKey: "bestTime")
        return t > 0 ? t : nil
    }()

    private var startTime: Date?

    func startGame() {
        phase = .scanning
    }

    func switchWasPlaced() {
        phase = .hiding
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

    func giveUp() {
        guard phase == .searching || phase == .found else { return }
        phase = .gaveUp
    }

    func win() {
        guard phase == .found else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        if bestTime == nil || elapsed < bestTime! {
            bestTime = elapsed
            UserDefaults.standard.set(elapsed, forKey: "bestTime")
        }
        phase = .won(seconds: elapsed)
    }

    func reset() {
        phase = .scanning
        scanProgress = 0
        startTime = nil
    }

    func resetToMenu() {
        phase = .menu
        scanProgress = 0
        startTime = nil
    }
}
