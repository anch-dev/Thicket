// Tunable constants shared by the whole simulation. Everything is integer based so
// the simulation is bit-for-bit deterministic on every platform.

public enum Rules {
    /// The simulation always advances at a fixed 60 Hz.
    public static let ticksPerSecond = 60
    /// Sub-cell resolution used for falling pieces (1 cell = `sub` units).
    public static let sub = 16

    public static let soloColumns = 7
    public static let soloRows = 13
    public static let versusColumns = 6

    public static let minMatch = 3
    /// A single line of this many pieces creates a Starseed.
    public static let starseedLine = 5

    /// Fall speeds, in sub-units per tick.
    public static let gravityFallSpeed = 4
    public static let placeFallSpeed = 8
    /// Pieces above a clear hang briefly so the player can see what happened.
    public static let clearHangTicks = 14
    /// A struck Flicker Mite stays vulnerable for this long.
    public static let flickerFlashTicks = 240

    // Pip timings (ticks).
    public static let pipWalkTicks = 7
    public static let pipClimbTicks = 9
    public static let pipFallTicks = 3
    public static let pipActionTicks = 8
    /// Holding the opposite direction this long after turning starts walking.
    public static let turnHoldTicks = 6
    /// A press made while Pip is busy is remembered for this many ticks.
    public static let inputBufferTicks = 8
    /// Pip must be without a legal move for this long before the round is lost.
    public static let trappedGraceTicks = 90
    /// Visual slide time of a kicked piece per cell travelled.
    public static let kickSlideTicksPerCell = 2

    /// Chain multipliers, indexed by chain level - 1 (clamped to the last entry).
    public static let chainMultipliers = [1, 2, 3, 5, 8, 12, 16]

    public static func chainMultiplier(_ level: Int) -> Int {
        let i = max(0, min(level - 1, chainMultipliers.count - 1))
        return chainMultipliers[i]
    }

    // Base scores.
    public static let miteScore = 50
    public static let seedScore = 10
    public static let starseedScore = 100
    public static let hitScore = 20
    public static let longLineBonusPerPiece = 30
    public static let roundClearBonus = 1000
}
