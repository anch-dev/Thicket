import Foundation
import ThicketCore
import XCTest

final class GameTests: XCTestCase {
    // MARK: Chains and scoring

    func testChainTriggeredByFallingPiece() {
        var s = sandbox([
            ". . . e",
            ". . . t",
            ". . . T",
            ". E E T",
        ])
        let ev = s.settle()
        let clears = ev.clears
        XCTAssertEqual(clears.map(\.chain), [1, 2])
        XCTAssertEqual(ev.chainLevels, [2])
        let base = 2 * Rules.miteScore + Rules.seedScore
        XCTAssertEqual(clears[0].score, base * Rules.chainMultiplier(1))
        XCTAssertEqual(clears[1].score, base * Rules.chainMultiplier(2))
        XCTAssertEqual(s.score, base * 3)
        XCTAssertEqual(s.maxChain, 2)
        XCTAssertEqual(s.board.pieceCount, 0)
    }

    func testPlayerMadeMatchIsNotAChain() {
        // Pieces dropped by Pip carry no chain tag.
        var s = sandbox(["E E"], pip: 3, facing: .left, carrying: [.seed(.ember, id: 90)])
        let ev = s.tap(.up)
        XCTAssertEqual(ev.clears.map(\.chain), [1])
        XCTAssertTrue(ev.chainLevels.isEmpty)
    }

    func testChainMultiplierTable() {
        XCTAssertEqual((1...9).map(Rules.chainMultiplier), [1, 2, 3, 5, 8, 12, 16, 16, 16])
        XCTAssertEqual(Rules.chainMultiplier(0), 1)
    }

    func testThreeStepChain() {
        // Clear 1: vertical tide in column 4. The ember seed above drops into a
        // horizontal ember line (clear 2), which lets the bloom seed on column 2
        // fall into a diagonal bloom line (clear 3).
        var s = sandbox([
            ". . . . e",
            ". . . . t",
            ". . b . T",
            "B B E E T",
        ])
        let ev = s.settle()
        XCTAssertEqual(ev.clears.map(\.chain), [1, 2, 3])
        XCTAssertEqual(ev.chainLevels, [2, 3])
    }

    // MARK: Carrying while the board resolves

    func testCarriedPiecesAreOutOfPlay() {
        // Pip holds an ember Mite and an ember Seed while a Starseed fires.
        var s = sandbox([". . . . . . T", "E E e* . . . T"], pip: 4, facing: .right,
                        carrying: [.mite(.ember, id: 90), .seed(.ember, id: 91)])
        let ev = s.settle()
        XCTAssertTrue(ev.has { $0 == .starseedBurst(color: .ember) })
        XCTAssertEqual(s.pip.carried.count, 2, "carried Mite survives the burst")
        XCTAssertEqual(s.mitesRemaining, 3)
    }

    func testBoardResolvesUnderneathACarriedLoad() {
        // Pip is carrying and stands on a column that clears out from under him.
        var s = sandbox([". . . e", ". . . E", ". . . E"], pip: 3, facing: .left,
                        carrying: [.mite(.bloom, id: 90)])
        XCTAssertEqual(s.pip.row, 3)
        s.settle()
        XCTAssertEqual(s.board.pieceCount, 0)
        XCTAssertEqual(s.pip.row, 0, "Pip drops with his load")
        XCTAssertEqual(s.pip.carried.map(\.color), [.bloom])
    }

    // MARK: Falling pieces and Pip

    func testPieceLandingOnPipIsCaught() {
        var s = sandbox([], pip: 3)
        s.fallers.append(Faller(piece: .mite(.tide, id: 90), column: 3, row: 5, speed: 4, origin: .spawn))
        let ev = s.run(60)
        XCTAssertEqual(s.status, .playing)
        XCTAssertTrue(ev.has { $0 == .caught })
        XCTAssertEqual(s.pip.carried.map(\.id), [90])
    }

    func testWalkingIntoAFallingPieceIsBlocked() {
        var s = sandbox([], pip: 3)
        s.fallers.append(Faller(piece: .mite(.tide, id: 90), column: 4, row: 0, speed: 0, hang: 100, origin: .spawn))
        XCTAssertFalse(s.perform(.walkRight))
    }

    // MARK: Canopy

    func testCanopySlamLowersCeiling() {
        var s = sandbox(["E"], pip: 3)
        let before = s.board.ceiling
        s.slamCanopy()
        XCTAssertEqual(s.board.ceiling, before - 1)
        XCTAssertEqual(s.status, .playing)
    }

    func testCanopySlamOntoStackEndsRound() {
        var s = sandbox(["T", "E", "B"], pip: 3, ceiling: 4)
        s.slamCanopy()
        XCTAssertEqual(s.status, .lost(.overflow))
    }

    func testCanopySlamOntoPipCrushesHim() {
        var s = sandbox([". . . T", ". . . E", ". . . B"], pip: 3, ceiling: 4)
        XCTAssertEqual(s.pip.row, 3)
        s.slamCanopy()
        // Column 3 is 3 tall = new ceiling → it overflows too; either way the round is lost.
        XCTAssertTrue(s.status.isOver)
        var t = sandbox([". . . E", ". . . B"], pip: 3, carrying: [.mite(.tide, id: 90)], ceiling: 4)
        XCTAssertEqual(t.pip.row + t.pip.carried.count, 3)
        t.slamCanopy()
        XCTAssertEqual(t.status, .lost(.crushed))
    }

    func testGloomSlamsCanopyOnSchedule() {
        var s = sandbox([". . . . . . E"], pip: 3)
        s.config.phasesEnabled = true
        s.config.wrenTicks = 10
        s.config.gloomTicks = 100
        s.config.slamInterval = 20
        s.config.miteInterval = 1000
        s.config.seedInterval = 1000
        s.phase = PhaseState(duration: 10)
        let ev = s.run(10)
        XCTAssertTrue(ev.has { $0 == .phaseChanged(.gloom) })
        let ceiling = s.board.ceiling
        let ev2 = s.run(20)
        XCTAssertTrue(ev2.has { $0 == .canopySlam(ceiling: ceiling - 1) })
        XCTAssertEqual(s.board.ceiling, ceiling - 1)
        // When Wren returns she pushes the Canopy back up a row.
        let ev3 = s.run(80)
        XCTAssertTrue(ev3.has { $0 == .phaseChanged(.wren) })
        // Slams at gloom ticks 20, 40, 60, 80, 100, then Wren lifts it one row.
        XCTAssertEqual(s.board.ceiling, ceiling - 4)
    }

    // MARK: Phases

    func testWrenDropsSeedsThenGloomDropsMites() {
        var s = sandbox([". . . . . . E"], pip: 3)
        s.config.phasesEnabled = true
        s.config.wrenTicks = 120
        s.config.gloomTicks = 120
        s.config.seedInterval = 30
        s.config.miteInterval = 30
        s.config.slamInterval = 10_000
        s.phase = PhaseState(duration: 120)
        let wren = s.run(119)
        let wrenSpawns = wren.compactMap { e -> PieceKind? in
            if case let .spawned(c, k) = e { XCTAssertNotEqual(c, 3, "Wren avoids Pip"); return k }
            return nil
        }
        XCTAssertEqual(wrenSpawns, [.seed, .seed, .seed])
        let gloomRun = s.run(121)
        let start = gloomRun.firstIndex { $0 == .phaseChanged(.gloom) } ?? 0
        let gloom = Array(gloomRun[start...])
        let gloomSpawns = gloom.compactMap { e -> PieceKind? in
            if case let .spawned(_, k) = e { return k } else { return nil }
        }
        XCTAssertTrue(gloom.has { $0 == .phaseChanged(.gloom) })
        XCTAssertFalse(gloomSpawns.isEmpty)
        XCTAssertTrue(gloomSpawns.allSatisfy { $0 == .mite })
        XCTAssertEqual(s.phase.kind, .wren)
        XCTAssertEqual(s.phase.cycles, 1)
    }

    func testChainsShortenTheGloomPhase() {
        let rows = [
            ". . . e",
            ". . . t",
            ". . . T",
            ". E E T . . B",
        ]
        func gloomElapsed(chaining: Bool) -> Int {
            var s = sandbox(chaining ? rows : [". . . . . . B"])
            s.config.phasesEnabled = true
            s.config.seedInterval = 100_000
            s.config.miteInterval = 100_000
            s.config.slamInterval = 100_000
            s.config.gloomTicks = 10_000
            s.phase.kind = .gloom
            s.phase.duration = 10_000
            s.run(120)
            return s.phase.elapsed
        }
        XCTAssertEqual(gloomElapsed(chaining: true) - gloomElapsed(chaining: false), 90)
    }

    // MARK: Trapped

    func testTrappedWithNoLegalMoveEndsRound() {
        // Pip is boxed in by pieces hanging in the air on both sides and above him.
        var s = sandbox([], pip: 1, ceiling: 2)
        for (c, r) in [(0, 0), (2, 0), (1, 1)] {
            s.fallers.append(Faller(piece: .mite(.tide, id: 90 + c * 10 + r), column: c, row: r,
                                    speed: 0, hang: 100_000, origin: .spawn))
        }
        XCTAssertFalse(s.pipHasLegalMove)
        s.run(Rules.trappedGraceTicks - 1)
        XCTAssertEqual(s.status, .playing, "grace period")
        let ev = s.run(2)
        XCTAssertEqual(s.status, .lost(.trapped))
        XCTAssertTrue(ev.has { $0 == .gameOver(.trapped) })
    }

    func testNotTrappedWhileAMoveExists() {
        var s = sandbox(["E . B"], pip: 1)
        XCTAssertTrue(s.pipHasLegalMove, "can lift or climb")
        s.run(Rules.trappedGraceTicks * 2)
        XCTAssertEqual(s.status, .playing)
    }

    // MARK: Rounds

    func testRoundWonWhenLastMiteCleared() {
        var s = sandbox(["E E"], pip: 3, facing: .left, carrying: [.seed(.ember, id: 90)], winOnClear: true)
        let ev = s.tap(.up)
        XCTAssertEqual(s.status, .won)
        XCTAssertTrue(ev.has { if case .roundCleared = $0 { return true } else { return false } })
    }

    func testRoundNotWonWhileAMiteIsCarried() {
        var s = sandbox(["E E e"], pip: 4, carrying: [.mite(.tide, id: 90)], winOnClear: true)
        s.settle()
        XCTAssertEqual(s.status, .playing)
        XCTAssertEqual(s.mitesRemaining, 1)
    }

    func testRoundProgressionGetsHarder() {
        let first = RoundConfig.campaign(1)
        let last = RoundConfig.campaign(99)
        XCTAssertEqual(first.initialMites, 6)
        XCTAssertEqual(last.initialMites, 40)
        XCTAssertLessThan(last.seedInterval, first.seedInterval)
        XCTAssertLessThan(last.miteInterval, first.miteInterval)
        XCTAssertGreaterThan(last.dropSpeed, first.dropSpeed)
        XCTAssertEqual(first.miteWeights[1...].reduce(0, +), 0, "round 1 has only common Mites")
        XCTAssertTrue(last.miteWeights.allSatisfy { $0 > 0 })
        var previous = first
        for r in 2...99 {
            let c = RoundConfig.campaign(r)
            XCTAssertGreaterThanOrEqual(c.initialMites, previous.initialMites)
            XCTAssertLessThanOrEqual(c.miteInterval, previous.miteInterval)
            XCTAssertLessThan(c.maxStartHeight, c.rows - 3)
            previous = c
        }
        for r in [1, 25, 50, 99] {
            let s = GameState(config: .campaign(r), seed: roundSeed(r))
            XCTAssertEqual(s.board.miteCount, RoundConfig.campaign(r).initialMites)
            XCTAssertTrue(MatchFinder.findLines(in: s.board).isEmpty)
            XCTAssertEqual(s.pip.row, s.board.height(s.pip.column))
        }
    }

    func testCampaignProgressUnlocksNextRound() {
        var p = CampaignProgress()
        p.record(round: 1, won: false, score: 500)
        XCTAssertEqual(p.unlockedRound, 1)
        p.record(round: 1, won: true, score: 2000)
        XCTAssertEqual(p.unlockedRound, 2)
        XCTAssertEqual(p.bestScores[1], 2000)
        p.record(round: 1, won: true, score: 100)
        XCTAssertEqual(p.bestScores[1], 2000)
        p.record(round: 99, won: true, score: 1)
        XCTAssertEqual(p.unlockedRound, 99)
        XCTAssertNil(CampaignProgress.next(after: 99))
    }

    func testEndlessRefillsInsteadOfWinning() {
        var config = RoundConfig.endless()
        config.initialMites = 0
        var s = GameState(config: config, seed: 3)
        let ev = s.run(2)
        XCTAssertEqual(s.status, .playing)
        XCTAssertEqual(s.phase.kind, .gloom)
        XCTAssertTrue(ev.has { if case .roundCleared = $0 { return true } else { return false } })
    }

    // MARK: Determinism

    func randomInputs(_ n: Int, seed: UInt64) -> [InputFrame] {
        var rng = SeededRNG(seed: seed)
        var held: Buttons = []
        var out: [InputFrame] = []
        let all: [Buttons] = [.up, .down, .left, .right, .a, .b]
        for _ in 0..<n {
            var pressed: Buttons = []
            for b in all where rng.chance(1, in: 20) {
                if held.contains(b) {
                    held.remove(b)
                } else {
                    held.insert(b)
                    pressed.insert(b)
                }
            }
            out.append(InputFrame(held: held, pressed: pressed))
        }
        return out
    }

    func testDeterministicReplayFromSeed() {
        let inputs = randomInputs(4000, seed: 7)
        func play() -> (GameState, Int) {
            var s = GameState(config: .campaign(30), seed: 42)
            var events = 0
            for i in inputs { events += s.step(i).count }
            return (s, events)
        }
        let (a, ea) = play()
        let (b, eb) = play()
        XCTAssertEqual(a, b)
        XCTAssertEqual(ea, eb)
        XCTAssertGreaterThan(a.tick, 10)

        let other = GameState(config: .campaign(30), seed: 43)
        XCTAssertNotEqual(other.board, GameState(config: .campaign(30), seed: 42).board)
    }

    func testSnapshotResumeMatchesUninterruptedRun() throws {
        let inputs = randomInputs(3000, seed: 11)
        var straight = GameState(config: .campaign(12), seed: 5)
        var resumed = straight
        for i in inputs[..<1500] {
            straight.step(i)
            resumed.step(i)
        }
        let data = try JSONEncoder().encode(resumed)
        resumed = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(resumed, straight)
        for i in inputs[1500...] {
            straight.step(i)
            resumed.step(i)
        }
        XCTAssertEqual(resumed, straight)
    }

    func testRNGIsStable() {
        var r = SeededRNG(seed: 1)
        // Fixed reference values guard against accidental algorithm changes.
        let v = (0..<3).map { _ in r.next() }
        var r2 = SeededRNG(seed: 1)
        XCTAssertEqual(v, (0..<3).map { _ in r2.next() })
        var r3 = SeededRNG(seed: 99)
        for _ in 0..<1000 {
            let x = r3.int(below: 7)
            XCTAssertTrue((0..<7).contains(x))
        }
        XCTAssertEqual(v[0], 0x910A_2DEC_8902_5CC1)
    }

    func testOverflowWhenStackTouchesCanopy() {
        var s = sandbox([". . . . . . T", ". . . . . . E"], pip: 3, ceiling: 3)
        s.fallers.append(Faller(piece: .mite(.bloom, id: 90), column: 6, row: 2, speed: 4, origin: .spawn))
        s.run(10)
        XCTAssertEqual(s.status, .lost(.overflow))
    }

    // MARK: Lessons

    func testEveryLessonCanBeCompleted() {
        let scripts: [String: [(Buttons, Buttons)]] = [
            "walk": [(.right, []), (.right, []), (.right, []), (.right, []), (.right, []), (.right, [])],
            "climb": [(.right, []), (.up, []), (.up, []), (.up, [])],
            "lift": [(.a, [])],
            "drop": [(.up, [])],
            "kick": [(.a, .down)],
            "match": [(.up, [])],
            "vertical": [(.up, [])],
            "starseed": [(.up, [])],
        ]
        XCTAssertEqual(Set(scripts.keys), Set(Lesson.all.map(\.id)))
        for lesson in Lesson.all {
            var s = lesson.makeState()
            var done = lesson.isComplete(s, events: [])
            XCTAssertFalse(done, "\(lesson.id) starts incomplete")
            for (press, held) in scripts[lesson.id] ?? [] {
                var ev = s.step(InputFrame(held: press.union(held), pressed: press))
                done = done || lesson.isComplete(s, events: ev)
                for _ in 0..<40 {
                    ev = s.step(.none)
                    done = done || lesson.isComplete(s, events: ev)
                }
            }
            XCTAssertTrue(done, "lesson \(lesson.id) completes with its script")
            XCTAssertNotEqual(s.status, .lost(.crushed))
        }
    }

    // MARK: Versus

    func testVersusChainsSendMites() {
        var m = VersusMatch(seed: 9)
        m.players[0] = sandbox([
            ". . . e",
            ". . . t",
            ". . . T",
            ". E E T",
        ], pip: 5)
        m.players[0].board = {
            var b = Board(width: 6, rows: 13)
            for c in 0..<6 { b.setColumn(c, m.players[0].board.columns[c]) }
            return b
        }()
        m.players[0].config.columns = 6
        var sent = 0
        for _ in 0..<200 {
            for e in m.step([.none, .none])[0] {
                if case let .attack(n) = e { sent += n }
            }
        }
        XCTAssertEqual(sent, 1, "a 2-chain sends one Mite")
        XCTAssertEqual(m.players[1].config.columns, 6)
        XCTAssertNil(m.winner)
    }

    func testVersusWinnerWhenOpponentLoses() {
        var m = VersusMatch(seed: 9)
        m.players[1].status = .lost(.overflow)
        m.step([.none, .none])
        XCTAssertEqual(m.winner, 0)
        XCTAssertTrue(m.isOver)
    }
}
