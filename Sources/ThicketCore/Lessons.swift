/// Interactive tutorial steps. Each lesson is a small frozen board (no drops, no
/// Canopy) plus a goal checked every tick.
public struct Lesson: Identifiable, Equatable {
    public enum Goal: Equatable {
        case reachColumn(Int)
        case standOn(column: Int, row: Int)
        case carry(atLeast: Int)
        case placeSomething
        case kickSomething
        case clearAllMites
        case makeStarseed
    }

    public var id: String
    public var title: String
    public var text: String
    /// Board notation, top row first (see `Board.parse`).
    public var board: [String]
    public var pipColumn: Int
    public var pipFacing: Facing
    /// Tokens Pip starts out carrying, bottom first.
    public var carrying: [String]
    public var goal: Goal

    public func makeState() -> GameState {
        var config = RoundConfig.lesson()
        config.endless = goal != .clearAllMites
        // Lesson boards are authored by hand; a parse failure is a programming error.
        let b = try! Board.parse(board)
        var pip = Pip(column: pipColumn, row: b.height(pipColumn))
        pip.facing = pipFacing
        var id = 1000
        pip.carried = carrying.compactMap { try? Board.parseToken($0, id: &id) }
        return GameState(config: config, board: b, pip: pip)
    }

    /// `events` are the events of the latest tick.
    public func isComplete(_ s: GameState, events: [GameEvent]) -> Bool {
        switch goal {
        case let .reachColumn(c):
            return s.pip.column == c && s.pip.busy == 0 && s.pipSupported
        case let .standOn(column, row):
            return s.pip.column == column && s.pip.row == row && !s.pip.clinging && s.pip.busy == 0
        case let .carry(n):
            return s.pip.carried.count >= n
        case .placeSomething:
            return events.contains { if case .placed = $0 { return true } else { return false } }
        case .kickSomething:
            return events.contains { if case .kicked = $0 { return true } else { return false } }
        case .clearAllMites:
            return s.status == .won
        case .makeStarseed:
            return events.contains { if case .starseedCreated = $0 { return true } else { return false } }
        }
    }

    public static let all: [Lesson] = [
        Lesson(id: "walk", title: "Walking",
               text: "Use Left and Right to walk. Tapping the other direction turns Pip around first. Walk to the far right.",
               board: [], pipColumn: 0, pipFacing: .right, carrying: [], goal: .reachColumn(6)),
        Lesson(id: "climb", title: "Climbing",
               text: "Face a stack and press Up to climb its side one cell at a time. Keep pressing Up to clamber onto the top. Walking off an edge steps down.",
               board: [". . . . E", ". . . . T", ". . . . B"], pipColumn: 2, pipFacing: .right,
               carrying: [], goal: .standOn(column: 4, row: 3)),
        Lesson(id: "lift", title: "Lifting",
               text: "Pip can only reach the piece right in front of him. Press A to lift it together with everything above it. (B pulls out just that one piece.)",
               board: [". . . . T", ". . . . E"], pipColumn: 3, pipFacing: .right,
               carrying: [], goal: .carry(atLeast: 2)),
        Lesson(id: "drop", title: "Dropping",
               text: "While carrying, press Up, A+B, A or B to set the load down in the column you are facing. It drops until it lands.",
               board: [], pipColumn: 3, pipFacing: .right, carrying: ["E", "T"], goal: .placeSomething),
        Lesson(id: "kick", title: "Kicking",
               text: "Hold Down and press A to kick the piece in front of you. It slides along until it hits something, then falls.",
               board: [". . T"], pipColumn: 1, pipFacing: .right, carrying: [], goal: .kickSomething),
        Lesson(id: "match", title: "Matching",
               text: "Line up 3 or more of one color - across, up or diagonally - and include at least one Seed. Three Mites alone never match. Drop the Seed next to the two Mites.",
               board: ["E E"], pipColumn: 3, pipFacing: .left, carrying: ["e"], goal: .clearAllMites),
        Lesson(id: "vertical", title: "Stacking",
               text: "Lines count vertically too. Face the two Mites and drop the Seed on top of them.",
               board: [". . . b E", ". . . t E"], pipColumn: 3, pipFacing: .right,
               carrying: ["e"], goal: .clearAllMites),
        Lesson(id: "starseed", title: "Starseeds",
               text: "Clearing 5 or more in one line grows a Starseed. Fill the gap to make a line of five. Match a Starseed later to clear every Mite of its color!",
               board: ["E E . E E . T"], pipColumn: 1, pipFacing: .right, carrying: ["e"], goal: .makeStarseed),
    ]
}
