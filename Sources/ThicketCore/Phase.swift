public enum PhaseKind: Int, Codable, Hashable {
    /// Wren drops Seeds while the meter fills.
    case wren
    /// The Gloom drops Mites and slams the Canopy.
    case gloom
}

public struct PhaseState: Codable, Equatable {
    public var kind: PhaseKind = .wren
    public var elapsed: Int = 0
    public var duration: Int
    public var spawnTimer: Int = 0
    public var slamTimer: Int = 0
    /// Completed Wren→Gloom→Wren cycles.
    public var cycles: Int = 0

    public init(duration: Int) {
        self.duration = duration
    }

    /// 0...1 – how full the meter is (Wren) or how much Gloom time remains.
    public var meter: Double {
        let f = duration > 0 ? Double(min(elapsed, duration)) / Double(duration) : 1
        return kind == .wren ? f : 1 - f
    }
}
