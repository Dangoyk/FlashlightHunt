import Foundation

enum GamePhase: Equatable {
    case scanning
    case hiding
    case searching
    case found
    case won(seconds: Int)
}

class GameState: ObservableObject {
    @Published var phase: GamePhase = .scanning
    @Published var scanProgress: Double = 0

    private var startTime: Date?

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

    func win() {
        guard phase == .found else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        phase = .won(seconds: elapsed)
    }

    func reset() {
        phase = .scanning
        scanProgress = 0
        startTime = nil
    }
}
