/// Outcome of resolving one set of simultaneous lines.
public struct ResolveResult: Equatable {
    public var lines: [MatchLine] = []
    public var chainLevel: Int = 0
    /// Pieces removed from the board, with where they were.
    public var removed: [Cell] = []
    public var removedPieces: [Piece] = []
    /// Shifter/Flicker Mites that were struck but survived.
    public var hits: [Cell] = []
    public var starseedsCreated: [Cell] = []
    public var starseedColors: [PieceColor] = []
    /// Colors whose Starseed fired (clearing every Mite of that color).
    public var burstColors: [PieceColor] = []
    public var score: Int = 0
    public var newFallers: [Faller] = []

    public var removedMites: Int { removedPieces.filter(\.isMite).count }
}

extension Board {
    /// Convenience for a board with nothing held (tests, tools).
    public mutating func resolve(lines: [MatchLine], nextID: inout Int) -> ResolveResult {
        var overlay: [Cell: Piece] = [:]
        var rng = SeededRNG(seed: UInt64(nextID))
        return resolve(lines: lines, overlay: &overlay, nextID: &nextID, rng: &rng)
    }

    /// Applies the given lines (all found in the same instant).
    ///
    /// Rules (as in the classic game this is modelled on):
    /// * Overlapping lines resolve together; a piece in several lines is hit once.
    /// * Seeds and Starseeds in a line are always removed.
    /// * Common and Slant Mites are removed. A Shifter changes color on its first
    ///   hit and is removed on the second. A Flicker starts flashing on its first
    ///   hit and is removed if hit while flashing.
    /// * A Starseed in a line clears every Mite of its color on the field,
    ///   including any Pip is holding.
    /// * Each line of 5+ creates a Starseed at its first Seed's cell. Its color is
    ///   random – not the color of the line.
    /// * `overlay` holds pieces on the field that are not settled in a column (Pip's
    ///   load). They take part in lines and are updated/removed in place.
    /// * Anything on the board left without support becomes a `Faller` tagged with
    ///   the chain level, so a match it makes on landing is the next chain step.
    public mutating func resolve(lines: [MatchLine], overlay: inout [Cell: Piece], nextID: inout Int,
                                 rng: inout SeededRNG) -> ResolveResult {
        var result = ResolveResult()
        guard !lines.isEmpty else { return result }
        result.lines = lines

        func get(_ c: Cell) -> Piece? { piece(at: c) ?? overlay[c] }
        func modify(_ c: Cell, _ f: (inout Piece) -> Void) {
            if piece(at: c) != nil {
                update(c, f)
            } else if var p = overlay[c] {
                f(&p)
                overlay[c] = p
            }
        }

        let matched = Set(lines.flatMap(\.cells)).sorted()
        let chain = 1 + (matched.compactMap { get($0)?.chainTag }.max() ?? 0)
        result.chainLevel = chain

        // Every piece that has been looked at is no longer "in flight".
        forEachPiece { $0.chainTag = 0 }

        var bursts = Set<PieceColor>()
        for cell in matched {
            if let p = get(cell), p.kind == .starseed { bursts.insert(p.color) }
        }
        result.burstColors = bursts.sorted()

        var remove = Set<Cell>()
        var hitCount = 0
        for cell in matched {
            guard let p = get(cell) else { continue }
            if p.isSeedLike || bursts.contains(p.color) {
                remove.insert(cell)
                continue
            }
            switch p.mite {
            case .common, .slant:
                remove.insert(cell)
            case .shifter:
                if p.shifted {
                    remove.insert(cell)
                } else {
                    modify(cell) {
                        $0.shifted = true
                        $0.color = $0.color.next
                        $0.chainTag = chain
                    }
                    result.hits.append(cell)
                    hitCount += 1
                }
            case .flicker:
                if p.flashTicks > 0 {
                    remove.insert(cell)
                } else {
                    modify(cell) {
                        $0.flashTicks = Rules.flickerFlashTicks
                        $0.chainTag = chain
                    }
                    result.hits.append(cell)
                    hitCount += 1
                }
            }
        }
        // Starseed burst: every Mite of that color on the field.
        if !bursts.isEmpty {
            for cell in allCells + Array(overlay.keys) {
                if let p = get(cell), p.isMite, bursts.contains(p.color) { remove.insert(cell) }
            }
        }

        // New Starseeds from long lines, in a random color.
        var newStars: [Cell: PieceColor] = [:]
        for line in lines where line.length >= Rules.starseedLine {
            if let seedCell = line.cells.first(where: { get($0)?.isSeedLike == true }),
               newStars[seedCell] == nil {
                newStars[seedCell] = PieceColor(rawValue: rng.int(below: PieceColor.allCases.count))!
            }
        }

        // Score.
        var base = 0
        for cell in remove.sorted() {
            let p = get(cell)!
            result.removed.append(cell)
            result.removedPieces.append(p)
            switch p.kind {
            case .mite: base += Rules.miteScore
            case .seed: base += Rules.seedScore
            case .starseed: base += Rules.starseedScore
            }
        }
        base += hitCount * Rules.hitScore
        for line in lines where line.length > Rules.minMatch {
            base += (line.length - Rules.minMatch) * Rules.longLineBonusPerPiece
        }
        result.score = base * Rules.chainMultiplier(chain)

        // Held pieces: remove in place; a new Starseed replaces a held Seed.
        for cell in overlay.keys.sorted() {
            if let color = newStars[cell] {
                overlay[cell] = Piece.starseed(color, id: nextID)
                nextID += 1
                result.starseedsCreated.append(cell)
                result.starseedColors.append(color)
            } else if remove.contains(cell) {
                overlay[cell] = nil
            }
        }

        // Rebuild columns; anything above a gap falls.
        for c in 0..<width {
            var settled: [Piece] = []
            var sawGap = false
            for r in 0..<columns[c].count {
                let cell = Cell(c, r)
                var p: Piece? = remove.contains(cell) ? nil : columns[c][r]
                if let color = newStars[cell] {
                    p = Piece.starseed(color, id: nextID)
                    nextID += 1
                    result.starseedsCreated.append(cell)
                    result.starseedColors.append(color)
                }
                guard var piece = p else {
                    sawGap = true
                    continue
                }
                if sawGap {
                    piece.chainTag = chain
                    result.newFallers.append(Faller(piece: piece, column: c, row: r,
                                                    speed: Rules.gravityFallSpeed,
                                                    hang: Rules.clearHangTicks, origin: .gravity))
                } else {
                    settled.append(piece)
                }
            }
            columns[c] = settled
        }
        return result
    }
}
