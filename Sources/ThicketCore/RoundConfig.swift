/// Everything that defines how a round plays. Pure data, so rounds are reproducible.
public struct RoundConfig: Codable, Equatable {
    public var round: Int
    public var columns: Int
    public var rows: Int
    public var initialMites: Int
    /// Tallest column in the starting layout.
    public var maxStartHeight: Int
    /// Relative odds of [common, slant, shifter, flicker] Mites.
    public var miteWeights: [Int]
    /// Length of Wren's phase (ticks) – the meter fills over this time.
    public var wrenTicks: Int
    /// Length of the Gloom's phase (ticks).
    public var gloomTicks: Int
    public var seedInterval: Int
    public var miteInterval: Int
    /// The Canopy slams down one row this often during the Gloom phase.
    public var slamInterval: Int
    /// Fall speed of dropped pieces, sub-units per tick.
    public var dropSpeed: Int
    /// Each chain step removes this many ticks from the Gloom phase.
    public var gloomChainBonus: Int
    /// Endless / Versus: the round never ends by clearing Mites.
    public var endless: Bool
    /// Lessons freeze the Wren/Gloom cycle and drop nothing.
    public var phasesEnabled: Bool

    public static let campaignRounds = 99

    public init(round: Int, columns: Int, rows: Int, initialMites: Int, maxStartHeight: Int,
                miteWeights: [Int], wrenTicks: Int, gloomTicks: Int, seedInterval: Int,
                miteInterval: Int, slamInterval: Int, dropSpeed: Int, gloomChainBonus: Int,
                endless: Bool, phasesEnabled: Bool) {
        self.round = round
        self.columns = columns
        self.rows = rows
        self.initialMites = initialMites
        self.maxStartHeight = maxStartHeight
        self.miteWeights = miteWeights
        self.wrenTicks = wrenTicks
        self.gloomTicks = gloomTicks
        self.seedInterval = seedInterval
        self.miteInterval = miteInterval
        self.slamInterval = slamInterval
        self.dropSpeed = dropSpeed
        self.gloomChainBonus = gloomChainBonus
        self.endless = endless
        self.phasesEnabled = phasesEnabled
    }

    /// Linear interpolation over the campaign, rounded to the nearest integer.
    static func lerp(_ a: Int, _ b: Int, _ round: Int) -> Int {
        let t = max(0, min(campaignRounds - 1, round - 1))
        return a + ((b - a) * t * 2 + (campaignRounds - 1)) / (2 * (campaignRounds - 1))
    }

    /// Campaign round 1...99: more Mites, taller starts, faster drops, new Mite types.
    public static func campaign(_ round: Int) -> RoundConfig {
        let r = max(1, min(campaignRounds, round))
        let slant = r >= 8 ? lerp(0, 3, r) + 1 : 0
        let shifter = r >= 16 ? lerp(0, 3, r) + 1 : 0
        let flicker = r >= 24 ? lerp(0, 3, r) + 1 : 0
        return RoundConfig(
            round: r,
            columns: Rules.soloColumns,
            rows: Rules.soloRows,
            initialMites: lerp(6, 40, r),
            maxStartHeight: min(8, 3 + (r - 1) / 14),
            miteWeights: [8, slant, shifter, flicker],
            wrenTicks: lerp(20 * 60, 12 * 60, r),
            gloomTicks: lerp(6 * 60, 12 * 60, r),
            seedInterval: lerp(150, 60, r),
            miteInterval: lerp(170, 50, r),
            slamInterval: lerp(330, 170, r),
            dropSpeed: lerp(2, 5, r),
            gloomChainBonus: 90,
            endless: false,
            phasesEnabled: true
        )
    }

    /// Endless mode: starts like round `startRound` and never ends by clearing.
    public static func endless(startRound: Int = 5) -> RoundConfig {
        var c = campaign(startRound)
        c.endless = true
        return c
    }

    /// One side of a local 2-player match.
    public static func versus(level: Int = 10) -> RoundConfig {
        var c = campaign(level)
        c.columns = Rules.versusColumns
        c.initialMites = min(c.initialMites, 14)
        c.endless = true
        return c
    }

    /// A frozen sandbox for lessons.
    public static func lesson() -> RoundConfig {
        var c = campaign(1)
        c.initialMites = 0
        c.phasesEnabled = false
        return c
    }
}
