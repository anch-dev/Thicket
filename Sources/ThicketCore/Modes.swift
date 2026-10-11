/// A Time Trial "trail": a fixed set of rounds played back to back against the clock.
public struct TimeTrial: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var rounds: [Int]

    public static let all: [TimeTrial] = [
        TimeTrial(id: "sapling", name: "Sapling Trail", rounds: [1, 2, 3, 4, 5]),
        TimeTrial(id: "grove", name: "Grove Trail", rounds: [12, 14, 16, 18, 20]),
        TimeTrial(id: "deepwood", name: "Deepwood Trail", rounds: [30, 35, 40, 45, 50]),
    ]
}

/// Seed for a campaign round. Fixed per round so every player sees the same layout.
public func roundSeed(_ round: Int) -> UInt64 {
    0x7417_C4E7 &+ UInt64(round) &* 0x0100_0000_01B3
}

/// Campaign bookkeeping that is independent of any platform.
public struct CampaignProgress: Codable, Equatable {
    /// Highest round the player may start.
    public var unlockedRound: Int = 1
    public var bestScores: [Int: Int] = [:]
    public var totalScore: Int = 0

    public init() {}

    /// Records a finished round. Clearing round N unlocks N+1.
    public mutating func record(round: Int, won: Bool, score: Int) {
        bestScores[round] = max(bestScores[round] ?? 0, score)
        if won {
            unlockedRound = min(RoundConfig.campaignRounds, max(unlockedRound, round + 1))
        }
        totalScore = bestScores.values.reduce(0, +)
    }

    /// The round after `round`, or nil if the campaign is finished.
    public static func next(after round: Int) -> Int? {
        round < RoundConfig.campaignRounds ? round + 1 : nil
    }
}
