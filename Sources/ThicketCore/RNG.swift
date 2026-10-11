/// SplitMix64: tiny, fast, fully deterministic and Codable so a game can be
/// snapshotted and resumed (or replayed) exactly.
public struct SeededRNG: RandomNumberGenerator, Codable, Equatable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound`. Uses rejection sampling so results do
    /// not depend on the standard library's (unspecified) algorithms.
    public mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let limit = UInt64.max - (UInt64.max % bound)
        while true {
            let v = next()
            if v < limit { return Int(v % bound) }
        }
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(below: range.upperBound - range.lowerBound + 1)
    }

    public mutating func chance(_ numerator: Int, in denominator: Int) -> Bool {
        int(below: denominator) < numerator
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[int(below: items.count)]
    }

    /// Index chosen with probability proportional to its weight. Zero weights are skipped.
    public mutating func weightedIndex(_ weights: [Int]) -> Int {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        precondition(total > 0)
        var roll = int(below: total)
        for (i, w) in weights.enumerated() where w > 0 {
            if roll < w { return i }
            roll -= w
        }
        return weights.count - 1
    }
}
