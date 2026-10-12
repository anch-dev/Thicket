public enum LossReason: Int, Codable, Hashable {
    /// A stack reached the Canopy.
    case overflow
    /// Pip (with his load) was pinned against the Canopy.
    case crushed
    /// Pip was boxed in with no legal move.
    case trapped
}

public enum GameStatus: Codable, Equatable, Hashable {
    case playing
    case won
    case lost(LossReason)

    public var isOver: Bool { self != .playing }
}

/// Things that happened during a tick, for rendering, audio and haptics.
/// They carry no state the simulation depends on.
public enum GameEvent: Equatable {
    case pipWalked
    case pipTurned
    case pipClimbed
    case pipLanded
    case lifted(count: Int)
    case pulled
    case placed(count: Int)
    case kicked(from: Cell, to: Cell)
    case placedBelow(count: Int)
    case actionRejected(action: PipAction, reason: String)
    case bump
    case caught
    case landed(cell: Cell, kind: PieceKind)
    case cleared(cells: [Cell], pieces: [Piece], chain: Int, score: Int)
    case hit(cell: Cell)
    case starseedCreated(cell: Cell, color: PieceColor)
    case starseedBurst(color: PieceColor)
    case chain(level: Int)
    case spawned(column: Int, kind: PieceKind)
    case phaseChanged(PhaseKind)
    case canopySlam(ceiling: Int)
    case canopyLift(ceiling: Int)
    case attack(mites: Int)
    case gameOver(LossReason)
    case roundCleared(bonus: Int)
}
