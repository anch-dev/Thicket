/// Local two-player match: two 6-column fields; chains and big clears send Mites
/// across. The first player whose field fails loses.
public struct VersusMatch: Codable, Equatable {
    public var players: [GameState]
    public var winner: Int?

    public init(seed: UInt64, level: Int = 10) {
        let config = RoundConfig.versus(level: level)
        // Both players get the same starting layout and the same drop sequence.
        players = [GameState(config: config, seed: seed), GameState(config: config, seed: seed)]
    }

    public var isOver: Bool { winner != nil || players.allSatisfy { $0.status.isOver } }

    /// Advances both fields one tick. Returns each player's events.
    @discardableResult
    public mutating func step(_ inputs: [InputFrame]) -> [[GameEvent]] {
        guard !isOver else { return [[], []] }
        var out: [[GameEvent]] = []
        for i in 0..<2 {
            out.append(players[i].step(i < inputs.count ? inputs[i] : .none))
        }
        for i in 0..<2 {
            for e in out[i] {
                if case let .attack(mites) = e { players[1 - i].incomingGarbage += mites }
            }
        }
        let lost = players.map { $0.status.isOver }
        if lost[0] && lost[1] {
            // Simultaneous knock-out: higher score takes it, player 1 on a tie.
            winner = players[1].score > players[0].score ? 1 : 0
        } else if lost[0] {
            winner = 1
        } else if lost[1] {
            winner = 0
        }
        return out
    }
}
