/// The complete, deterministic state of one playfield.
///
/// Advance it with `step(_:)` exactly 60 times per second. Given the same config,
/// seed and inputs it always produces the same result, and it is `Codable` so a
/// round can be saved mid-play and resumed (or replayed) exactly.
public struct GameState: Codable, Equatable {
    public var config: RoundConfig
    public var board: Board
    public var pip: Pip
    public var fallers: [Faller] = []
    public var phase: PhaseState
    public var rng: SeededRNG
    public var score = 0
    public var tick = 0
    public var status: GameStatus = .playing
    public var nextID = 1
    public var lastChain = 0
    public var maxChain = 0
    public var mitesCleared = 0
    public var trappedTicks = 0
    /// A press that arrived while Pip was busy, kept for `Rules.inputBufferTicks`.
    public var buffered: PipAction?
    public var bufferTicks = 0
    /// Versus: Mites waiting to be dropped on this field.
    public var incomingGarbage = 0
    public var garbageTimer = 0

    /// Events produced by the current `step`; always empty between steps.
    var events: [GameEvent] = []

    enum CodingKeys: String, CodingKey {
        case config, board, pip, fallers, phase, rng, score, tick, status, nextID, lastChain,
             maxChain, mitesCleared, trappedTicks, buffered, bufferTicks, incomingGarbage, garbageTimer
    }

    // MARK: - Setup

    /// A fresh round generated from `config` and `seed`.
    public init(config: RoundConfig, seed: UInt64) {
        self.config = config
        self.rng = SeededRNG(seed: seed &+ UInt64(config.round) &* 0x9E37_79B9_7F4A_7C15)
        self.board = Board(width: config.columns, rows: config.rows)
        self.phase = PhaseState(duration: config.wrenTicks)
        let pipColumn = config.columns / 2
        self.pip = Pip(column: pipColumn, row: 0)
        for _ in 0..<config.initialMites {
            let open = (0..<board.width).filter { board.height($0) < config.maxStartHeight }
            guard !open.isEmpty else { break }
            let c = rng.pick(open)
            board.push(makeMite(), column: c)
        }
        pip.row = board.height(pipColumn)
        pip.fromRow = pip.row
    }

    /// A hand-built position (tests, lessons).
    public init(config: RoundConfig, board: Board, pip: Pip, seed: UInt64 = 1) {
        self.config = config
        self.board = board
        self.pip = pip
        self.phase = PhaseState(duration: config.wrenTicks)
        self.rng = SeededRNG(seed: seed)
        let maxID = board.columns.flatMap { $0 }.map(\.id).max() ?? 0
        self.nextID = maxID + 1
    }

    mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    mutating func makeMite() -> Piece {
        let kind = MiteKind(rawValue: rng.weightedIndex(config.miteWeights)) ?? .common
        let color = PieceColor(rawValue: rng.int(below: PieceColor.allCases.count))!
        return Piece(id: makeID(), kind: .mite, color: color, mite: kind)
    }

    // MARK: - Queries

    public var mitesRemaining: Int {
        board.miteCount + fallers.filter { $0.piece.isMite }.count + pip.carried.filter(\.isMite).count
    }

    public var elapsedSeconds: Double { Double(tick) / Double(Rules.ticksPerSecond) }

    /// Is the cell inside the field, below the Canopy, and not occupied by a settled
    /// or falling piece?
    public func isFree(_ c: Int, _ r: Int, height: Int = 1) -> Bool {
        guard board.contains(column: c), r >= 0, r + height <= board.ceiling else { return false }
        for row in r..<(r + height) {
            if board.piece(c, row) != nil { return false }
            if fallers.contains(where: { $0.overlaps(c, row) }) { return false }
        }
        return true
    }

    public var pipSupported: Bool {
        if pip.row == 0 || board.piece(pip.column, pip.row - 1) != nil { return true }
        return pip.clinging && board.piece(pip.column + pip.facing.rawValue, pip.row) != nil
    }

    // MARK: - Tick

    @discardableResult
    public mutating func step(_ input: InputFrame) -> [GameEvent] {
        guard status == .playing else { return [] }
        tick += 1
        updatePip(input)
        if status == .playing && config.phasesEnabled { updatePhase() }
        if status == .playing { updateGarbage() }
        if status == .playing { updateFallers() }
        if status == .playing { updateTimers() }
        if status == .playing { resolveMatches() }
        if status == .playing { checkEnd() }
        let out = events
        events = []
        return out
    }

    mutating func lose(_ reason: LossReason) {
        guard status == .playing else { return }
        status = .lost(reason)
        events.append(.gameOver(reason))
    }

    // MARK: - Pip

    func decode(_ input: InputFrame) -> PipAction? {
        let p = input.pressed
        let down = input.held.contains(.down) || p.contains(.down)
        if pip.isCarrying {
            // Down (alone or with A/B) puts the load under Pip; A, B, A+B or Up put it in front.
            if p.contains(.down) || (down && !p.intersection([.a, .b]).isEmpty) { return .placeBelow }
            if !p.intersection([.a, .b, .up]).isEmpty { return .place }
        } else {
            if p.contains(.a) { return down ? .kick : .liftStack }
            if p.contains(.b) { return .pull }
            if p.contains(.up) { return .climb }
            if p.contains(.down) { return pip.clinging ? .climbDown : nil }
        }
        let l = p.contains(.left), r = p.contains(.right)
        if l != r { return l ? .walkLeft : .walkRight }
        return nil
    }

    mutating func updatePip(_ input: InputFrame) {
        if pip.busy > 0 {
            pip.busy -= 1
            if pip.busy == 0 { pip.motion = .idle }
        }
        if bufferTicks > 0 {
            bufferTicks -= 1
            if bufferTicks == 0 { buffered = nil }
        }

        let heldL = input.held.contains(.left), heldR = input.held.contains(.right)
        let heldDir: Facing? = heldL == heldR ? nil : (heldL ? .left : .right)
        if let d = heldDir {
            let button: Buttons = d == .left ? .left : .right
            pip.holdTicks = input.pressed.contains(button) ? 0 : pip.holdTicks + 1
        } else {
            pip.holdTicks = 0
        }

        let action = decode(input)
        if pip.clinging && board.piece(pip.column + pip.facing.rawValue, pip.row) == nil {
            pip.clinging = false
        }

        // Gravity on Pip.
        if pip.busy == 0 && !pipSupported {
            if isFree(pip.column, pip.row - 1) {
                let from = pip.cell
                pip.row -= 1
                pip.falling = true
                pip.begin(.fall, ticks: Rules.pipFallTicks, from: from)
            }
            if let a = action { buffer(a) }
            return
        }
        if pip.falling && pip.busy == 0 {
            pip.falling = false
            events.append(.pipLanded)
        }

        if pip.busy > 0 || pip.falling {
            if let a = action { buffer(a) }
            return
        }
        if let a = action {
            buffered = nil
            bufferTicks = 0
            perform(a)
            return
        }
        if let b = buffered {
            buffered = nil
            bufferTicks = 0
            perform(b)
            return
        }
        if let d = heldDir, pip.holdTicks >= Rules.turnHoldTicks, d == pip.facing {
            perform(d == .left ? .walkLeft : .walkRight)
        }
    }

    mutating func buffer(_ a: PipAction) {
        buffered = a
        bufferTicks = Rules.inputBufferTicks
    }

    /// Attempts an action; returns false (and changes nothing) if it is not legal.
    /// A rejected action emits `.actionRejected` with the reason (useful for logs).
    @discardableResult
    public mutating func perform(_ action: PipAction) -> Bool {
        let failure: String?
        switch action {
        case .walkLeft: failure = move(.left)
        case .walkRight: failure = move(.right)
        case .climb: failure = climb()
        case .climbDown: failure = climbDown()
        case .liftStack: failure = lift(whole: true)
        case .pull: failure = lift(whole: false)
        case .kick: failure = kick()
        case .place: failure = place()
        case .placeBelow: failure = placeBelow()
        }
        guard let reason = failure else { return true }
        events.append(.actionRejected(action: action, reason: reason))
        if [.liftStack, .pull, .kick, .place, .placeBelow].contains(action) {
            events.append(.bump)
        }
        return false
    }

    /// Cells Pip plus his load would occupy standing at (c, r).
    func roomForPip(_ c: Int, _ r: Int) -> Bool {
        isFree(c, r, height: pip.carried.count + 1)
    }

    /// Walking. Walking into a stack climbs it: a 1-high step is stepped onto,
    /// a taller one is climbed one cell up its side (keep holding to go higher).
    mutating func move(_ d: Facing) -> String? {
        let from = pip.cell
        if pip.clinging {
            if d == pip.facing { return climb() }
            pip.facing = d
            pip.clinging = false
            events.append(.pipTurned)
            return nil
        }
        if pip.facing != d {
            pip.facing = d
            pip.begin(.turn, ticks: 2, from: from)
            events.append(.pipTurned)
            return nil
        }
        let t = pip.column + d.rawValue
        guard board.contains(column: t) else { return "edge of the field" }
        if roomForPip(t, pip.row) {
            pip.column = t
            pip.begin(.walk, ticks: Rules.pipWalkTicks, from: from)
            events.append(.pipWalked)
            return nil
        }
        if board.piece(t, pip.row) != nil {
            return climb()
        }
        return "a falling piece is in the way"
    }

    /// Up (not carrying), or walking into a stack: climb the stack in front one
    /// cell, or clamber onto its top. Works while carrying if the load fits.
    mutating func climb() -> String? {
        let f = pip.column + pip.facing.rawValue
        let r = pip.row
        guard board.contains(column: f) else { return "edge of the field" }
        guard board.piece(f, r) != nil else { return "nothing in front to climb" }
        let from = pip.cell
        if board.piece(f, r + 1) != nil {
            // Climb one cell up the side of the stack.
            guard roomForPip(pip.column, r + 1) else {
                return r + 1 + pip.carried.count >= board.ceiling ? "the Canopy is too low to climb"
                    : "no room above Pip"
            }
            pip.row += 1
            pip.clinging = true
        } else {
            // Clamber onto the top of the stack.
            guard roomForPip(f, r + 1), roomForPip(pip.column, r + 1) else {
                return "no room on top of the stack (Canopy or falling piece)"
            }
            pip.column = f
            pip.row += 1
            pip.clinging = false
        }
        pip.begin(.climb, ticks: Rules.pipClimbTicks, from: from)
        events.append(.pipClimbed)
        return nil
    }

    mutating func climbDown() -> String? {
        guard pip.clinging else { return "not clinging" }
        guard pip.row > 0, roomForPip(pip.column, pip.row - 1) else { return "something below" }
        let from = pip.cell
        pip.row -= 1
        let grounded = pip.row == 0 || board.piece(pip.column, pip.row - 1) != nil
        pip.clinging = !grounded && board.piece(pip.column + pip.facing.rawValue, pip.row) != nil
        pip.begin(.climb, ticks: Rules.pipClimbTicks, from: from)
        events.append(.pipClimbed)
        return nil
    }

    /// Pieces above `row` in column `c` were detached; let them drop.
    mutating func dropDetached(_ pieces: [Piece], column c: Int, fromRow row: Int) {
        for (i, p) in pieces.enumerated() {
            var piece = p
            piece.chainTag = 0
            fallers.append(Faller(piece: piece, column: c, row: row + i,
                                  speed: Rules.gravityFallSpeed, hang: 2, origin: .gravity))
        }
    }

    mutating func lift(whole: Bool) -> String? {
        guard !pip.isCarrying else { return "already carrying" }
        let f = pip.column + pip.facing.rawValue
        let r = pip.row
        guard board.piece(f, r) != nil else { return "no piece in front at Pip's height" }
        let n = whole ? board.height(f) - r : 1
        guard isFree(pip.column, r + 1, height: n) else { return "no room above Pip for \(n) piece(s)" }
        var taken = board.removeFrom(column: f, row: r)
        if whole {
            pip.carried = taken
        } else {
            pip.carried = [taken.removeFirst()]
            dropDetached(taken, column: f, fromRow: r + 1)
        }
        for i in pip.carried.indices { pip.carried[i].chainTag = 0 }
        if pip.clinging && board.piece(f, r) == nil { pip.clinging = false }
        pip.begin(whole ? .lift : .pull, ticks: Rules.pipActionTicks, from: pip.cell)
        events.append(whole ? .lifted(count: n) : .pulled)
        return nil
    }

    mutating func kick() -> String? {
        guard !pip.isCarrying else { return "can't kick while carrying" }
        let d = pip.facing.rawValue
        let f = pip.column + d
        let r = pip.row
        guard board.piece(f, r) != nil else { return "no piece in front to kick" }
        var x = f
        while board.contains(column: x + d), board.piece(x + d, r) == nil,
              !fallers.contains(where: { $0.overlaps(x + d, r) }) {
            x += d
        }
        guard x != f else { return "the piece has nowhere to slide" }
        var taken = board.removeFrom(column: f, row: r)
        var kicked = taken.removeFirst()
        kicked.chainTag = 0
        dropDetached(taken, column: f, fromRow: r + 1)
        fallers.append(Faller(piece: kicked, column: x, row: r, speed: Rules.gravityFallSpeed,
                              hang: abs(x - f) * Rules.kickSlideTicksPerCell, origin: .kicked,
                              slideFrom: f))
        if pip.clinging && board.piece(f, r) == nil { pip.clinging = false }
        pip.begin(.kick, ticks: Rules.pipActionTicks, from: pip.cell)
        events.append(.kicked(from: Cell(f, r), to: Cell(x, r)))
        return nil
    }

    /// Put the load down in the column in front, at Pip's height (it then falls).
    mutating func place() -> String? {
        guard pip.isCarrying else { return "not carrying anything" }
        let f = pip.column + pip.facing.rawValue
        let n = pip.carried.count
        guard board.contains(column: f) else { return "edge of the field" }
        guard isFree(f, pip.row, height: n) else {
            return "front column is blocked at Pip's height (try Down to put it under Pip)"
        }
        for (i, p) in pip.carried.enumerated() {
            fallers.append(Faller(piece: p, column: f, row: pip.row + i,
                                  speed: Rules.placeFallSpeed, origin: .placed))
        }
        pip.carried = []
        pip.begin(.place, ticks: Rules.pipActionTicks, from: pip.cell)
        events.append(.placed(count: n))
        return nil
    }

    /// Down while carrying: set the load down in Pip's own column and stand on top of it.
    mutating func placeBelow() -> String? {
        guard pip.isCarrying else { return "not carrying anything" }
        let grounded = pip.row == 0 || board.piece(pip.column, pip.row - 1) != nil
        guard grounded else { return "Pip must be standing on something" }
        let n = pip.carried.count
        // The load moves down into Pip's cell and Pip rises on top of it, so the
        // total height is unchanged; only the cell above the load must be free.
        guard roomForPip(pip.column, pip.row) else { return "no room" }
        let from = pip.cell
        for p in pip.carried { board.push(p, column: pip.column) }
        pip.carried = []
        pip.row += n
        pip.clinging = false
        pip.begin(.place, ticks: Rules.pipActionTicks, from: from)
        events.append(.placed(count: n))
        events.append(.placedBelow(count: n))
        return nil
    }

    /// Whether Pip has anything at all he could do (used for the "trapped" loss).
    public var pipHasLegalMove: Bool {
        if pip.clinging { return true }
        if isFree(pip.column - 1, pip.row, height: pip.carried.count + 1)
            || isFree(pip.column + 1, pip.row, height: pip.carried.count + 1) {
            return true
        }
        let actions: [PipAction] = [.climb, .liftStack, .pull, .kick, .place, .placeBelow]
        for facing in [Facing.left, Facing.right] {
            var probe = self
            probe.pip.facing = facing
            if probe.move(facing) == nil { return true }
            for a in actions {
                var p = self
                p.pip.facing = facing
                if p.perform(a) { return true }
            }
        }
        return false
    }

    // MARK: - Phases

    var effectiveSeedInterval: Int { max(30, config.seedInterval - endlessLevel * 4) }
    var effectiveMiteInterval: Int { max(30, config.miteInterval - endlessLevel * 6) }

    /// Endless mode gets harder every 45 seconds.
    public var endlessLevel: Int { config.endless ? tick / (45 * Rules.ticksPerSecond) : 0 }

    mutating func updatePhase() {
        phase.elapsed += 1
        phase.spawnTimer += 1
        switch phase.kind {
        case .wren:
            if phase.spawnTimer >= effectiveSeedInterval {
                phase.spawnTimer = 0
                spawn(seed: true)
            }
            if phase.elapsed >= phase.duration { enterGloom() }
        case .gloom:
            phase.slamTimer += 1
            if phase.spawnTimer >= effectiveMiteInterval {
                phase.spawnTimer = 0
                spawn(seed: false)
            }
            if phase.slamTimer >= config.slamInterval {
                phase.slamTimer = 0
                slamCanopy()
            }
            if status == .playing && phase.elapsed >= phase.duration { enterWren() }
        }
    }

    mutating func enterGloom() {
        phase.kind = .gloom
        phase.elapsed = 0
        phase.duration = config.gloomTicks
        phase.spawnTimer = 0
        phase.slamTimer = 0
        events.append(.phaseChanged(.gloom))
    }

    mutating func enterWren() {
        phase.kind = .wren
        phase.elapsed = 0
        phase.duration = config.wrenTicks
        phase.spawnTimer = 0
        phase.cycles += 1
        events.append(.phaseChanged(.wren))
        // Wren pushes the Canopy back up a row.
        if board.ceiling < board.rows {
            board.ceiling += 1
            events.append(.canopyLift(ceiling: board.ceiling))
        }
    }

    /// The Canopy drops one row. Anything now touching it ends the round.
    public mutating func slamCanopy() {
        guard board.ceiling > 1 else { return }
        board.ceiling -= 1
        events.append(.canopySlam(ceiling: board.ceiling))
        let top = (board.ceiling - 1) * Rules.sub
        for i in fallers.indices where fallers[i].y > top { fallers[i].y = top }
        if board.isOverflowing {
            lose(.overflow)
        } else if pip.row + pip.carried.count >= board.ceiling {
            lose(.crushed)
        }
    }

    /// Wren drops a Seed (avoiding Pip's column when she can); the Gloom drops a Mite.
    mutating func spawn(seed: Bool) {
        let ceiling = board.ceiling
        func open(_ c: Int) -> Bool {
            board.height(c) < ceiling - 1 &&
                !fallers.contains { $0.column == c && $0.y + Rules.sub > (ceiling - 2) * Rules.sub }
        }
        var candidates = (0..<board.width).filter(open)
        if seed {
            let away = candidates.filter { $0 != pip.column }
            if !away.isEmpty { candidates = away }
        } else if candidates.isEmpty && (0..<board.width).allSatisfy({ board.height($0) >= ceiling - 1 }) {
            // The field is full: the Gloom's Mite tops it out.
            candidates = Array(0..<board.width)
        }
        guard !candidates.isEmpty else { return }
        let c = rng.pick(candidates)
        let piece: Piece
        if seed {
            piece = Piece(id: makeID(), kind: .seed, color: seedColor())
        } else {
            piece = makeMite()
        }
        fallers.append(Faller(piece: piece, column: c, row: ceiling - 1, speed: config.dropSpeed,
                              origin: .spawn))
        events.append(.spawned(column: c, kind: piece.kind))
    }

    /// Seeds favor colors that still have Mites so every round stays winnable.
    mutating func seedColor() -> PieceColor {
        var colors: [PieceColor] = board.columns.flatMap { $0 }.filter(\.isMite).map(\.color)
        colors += fallers.map(\.piece).filter(\.isMite).map(\.color)
        colors += pip.carried.filter(\.isMite).map(\.color)
        if !colors.isEmpty && rng.chance(3, in: 4) { return rng.pick(colors) }
        return PieceColor(rawValue: rng.int(below: PieceColor.allCases.count))!
    }

    mutating func updateGarbage() {
        guard incomingGarbage > 0 else {
            garbageTimer = 0
            return
        }
        garbageTimer += 1
        if garbageTimer >= 12 {
            garbageTimer = 0
            incomingGarbage -= 1
            spawn(seed: false)
        }
    }

    // MARK: - Falling pieces

    mutating func updateFallers() {
        guard !fallers.isEmpty else { return }
        fallers.sort { a, b in
            if a.column != b.column { return a.column < b.column }
            if a.y != b.y { return a.y < b.y }
            return a.piece.id < b.piece.id
        }
        var kept: [Faller] = []
        var column = -1
        var blockTop: Int?
        for var f in fallers {
            if f.column != column {
                column = f.column
                blockTop = nil
            }
            if f.hang > 0 {
                f.hang -= 1
                blockTop = f.y + Rules.sub
                kept.append(f)
                continue
            }
            var ny = f.y - f.speed
            if let bt = blockTop, ny < bt { ny = bt }
            // Coming down on Pip (or on what he carries)? He catches it, unless
            // that would push the pile into the Canopy.
            if pip.column == f.column && f.y >= pip.topY && ny <= pip.topY {
                if pip.row + pip.carried.count + 1 >= board.ceiling {
                    lose(.crushed)
                    kept.append(f)
                    continue
                }
                var caught = f.piece
                caught.chainTag = 0
                pip.carried.append(caught)
                events.append(.caught)
                continue
            }
            let stackTop = board.height(f.column) * Rules.sub
            if ny <= stackTop {
                let row = board.height(f.column)
                board.push(f.piece, column: f.column)
                events.append(.landed(cell: Cell(f.column, row), kind: f.piece.kind))
                continue
            }
            f.y = ny
            blockTop = ny + Rules.sub
            kept.append(f)
        }
        fallers = kept
    }

    mutating func updateTimers() {
        board.forEachPiece { if $0.flashTicks > 0 { $0.flashTicks -= 1 } }
        for i in fallers.indices where fallers[i].piece.flashTicks > 0 { fallers[i].piece.flashTicks -= 1 }
        for i in pip.carried.indices where pip.carried[i].flashTicks > 0 { pip.carried[i].flashTicks -= 1 }
    }

    // MARK: - Matches

    mutating func resolveMatches() {
        let lines = MatchFinder.findLines(in: board)
        guard !lines.isEmpty else {
            board.forEachPiece { $0.chainTag = 0 }
            return
        }
        var result = board.resolve(lines: lines, nextID: &nextID)
        if !result.burstColors.isEmpty {
            let burst = Set(result.burstColors)
            let hitFallers = fallers.filter { $0.piece.isMite && burst.contains($0.piece.color) }
            fallers.removeAll { $0.piece.isMite && burst.contains($0.piece.color) }
            result.removedPieces += hitFallers.map(\.piece)
            result.score += hitFallers.count * Rules.miteScore * Rules.chainMultiplier(result.chainLevel)
        }
        fallers += result.newFallers
        score += result.score
        mitesCleared += result.removedMites
        lastChain = result.chainLevel
        maxChain = max(maxChain, result.chainLevel)

        events.append(.cleared(cells: result.removed, pieces: result.removedPieces,
                               chain: result.chainLevel, score: result.score))
        for c in result.hits { events.append(.hit(cell: c)) }
        for c in result.starseedsCreated {
            events.append(.starseedCreated(cell: c, color: board.piece(at: c)?.color ?? lines[0].color))
        }
        for color in result.burstColors { events.append(.starseedBurst(color: color)) }
        if result.chainLevel >= 2 {
            events.append(.chain(level: result.chainLevel))
            if phase.kind == .gloom {
                phase.elapsed += config.gloomChainBonus * (result.chainLevel - 1)
            }
        }
        let longLine = lines.contains { $0.length >= Rules.starseedLine }
        let attack = (result.chainLevel - 1) + (longLine ? 1 : 0) + (result.burstColors.isEmpty ? 0 : 2)
        if attack > 0 { events.append(.attack(mites: attack)) }
    }

    // MARK: - End of round

    mutating func checkEnd() {
        if board.isOverflowing {
            lose(.overflow)
            return
        }
        if mitesRemaining == 0 {
            if !config.endless {
                status = .won
                let bonus = Rules.roundClearBonus + config.round * 100
                score += bonus
                events.append(.roundCleared(bonus: bonus))
                return
            }
            if config.phasesEnabled && phase.kind == .wren && fallers.isEmpty {
                // Endless: a cleared field brings the Gloom straight back.
                score += Rules.roundClearBonus
                events.append(.roundCleared(bonus: Rules.roundClearBonus))
                enterGloom()
            }
        }
        if pip.busy == 0 && pipSupported && !pipHasLegalMove {
            trappedTicks += 1
            if trappedTicks >= Rules.trappedGraceTicks { lose(.trapped) }
        } else {
            trappedTicks = 0
        }
    }
}
