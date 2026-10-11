import Foundation
import ThicketCore
import ThicketKit
import XCTest

final class PersistenceTests: XCTestCase {
    func testSettingsAndSaveRoundTrip() {
        let store = MemoryStore()
        let p = Persistence(store: store)
        XCTAssertEqual(p.loadSettings(), Settings())
        var s = Settings()
        s.musicVolume = 0.25
        s.muted = true
        var layout = ControlLayout.standard
        layout.scale = 1.3
        layout.setCenter(.a, Vec2(0.8, 0.5))
        s.setLayout(layout, for: "phone-667x375")
        p.saveSettings(s)
        var save = SaveData()
        save.campaign.record(round: 3, won: true, score: 1234)
        _ = save.recordTime(trail: "sapling", ticks: 5000)
        save.lessonsCompleted.insert("walk")
        p.saveSave(save)

        let q = Persistence(store: store)
        XCTAssertEqual(q.loadSettings(), s)
        XCTAssertEqual(q.loadSettings().layout(for: "phone-667x375").scale, 1.3)
        XCTAssertEqual(q.loadSettings().layout(for: "pad-1366x1024"), ControlLayout.standard.sanitized(),
                       "layouts are per device")
        XCTAssertEqual(q.loadSave(), save)
        XCTAssertEqual(q.loadSave().campaign.unlockedRound, 4)
    }

    func testCorruptDataFallsBackToDefaults() {
        let store = MemoryStore()
        store.set(Data("not json".utf8), forKey: "thicket.save")
        store.set(Data("{\"version\":99,\"payload\":{}}".utf8), forKey: "thicket.settings")
        let p = Persistence(store: store)
        XCTAssertEqual(p.loadSave(), SaveData())
        XCTAssertEqual(p.loadSettings(), Settings())
        XCTAssertNil(store.data(forKey: "thicket.save"), "bad blob discarded")
    }

    func testSettingsDecodeToleratesMissingAndOutOfRangeFields() throws {
        let json = #"{"musicVolume": 3}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.musicVolume, 1)
        XCTAssertEqual(s.sfxVolume, Settings().sfxVolume)
    }

    func testBestTimesAndEndless() {
        var s = SaveData()
        XCTAssertTrue(s.recordTime(trail: "grove", ticks: 900))
        XCTAssertFalse(s.recordTime(trail: "grove", ticks: 1000))
        XCTAssertTrue(s.recordTime(trail: "grove", ticks: 800))
        XCTAssertEqual(s.bestTimes["grove"], 800)
        XCTAssertTrue(s.recordEndless(score: 50, chain: 3))
        XCTAssertFalse(s.recordEndless(score: 40, chain: 5))
        XCTAssertEqual(s.bestChain, 5)
    }

    func testSuspendedSessionRoundTripThroughFileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thicket-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = Persistence(store: MemoryStore(), snapshotStore: FileStore(directory: dir))
        var session = SessionModel(kind: .campaign(round: 7))
        for i in 0..<500 { session.step([InputFrame(held: i % 50 < 10 ? .right : [])]) }
        p.saveSuspended(session.snapshot)

        let restored = try XCTUnwrap(Persistence(store: MemoryStore(), snapshotStore: FileStore(directory: dir)).loadSuspended())
        XCTAssertEqual(restored.kind, .campaign(round: 7))
        var resumed = SessionModel(resuming: restored)
        XCTAssertEqual(resumed.state, session.state)
        for _ in 0..<300 {
            session.step([.none])
            resumed.step([.none])
        }
        XCTAssertEqual(resumed.state, session.state, "resumed game continues identically")
        p.clearSuspended()
        XCTAssertNil(p.loadSuspended())
    }
}

final class SessionModelTests: XCTestCase {
    func win(_ s: inout SessionModel) {
        // Clear the board by hand to simulate a win.
        var st = s.state
        for c in 0..<st.board.width { st.board.setColumn(c, []) }
        st.fallers = []
        st.pip.carried = []
        s = SessionModel(resuming: SuspendedSession(kind: s.kind, state: st, versus: nil))
        s.step([.none])
    }

    func testCampaignWinUnlocksAndAdvances() {
        var s = SessionModel(kind: .campaign(round: 4))
        win(&s)
        XCTAssertEqual(s.outcome, .roundWon(round: 4))
        var save = SaveData()
        s.record(into: &save)
        s.record(into: &save) // recorded only once
        XCTAssertEqual(save.campaign.unlockedRound, 5)
        XCTAssertEqual(s.next, .campaign(round: 5))
    }

    func testCampaignLossRetriesSameRound() {
        // Drop a Mite right onto Pip.
        var t = SessionModel(kind: .campaign(round: 4))
        var lost = t.state
        lost.fallers.append(Faller(piece: .mite(.ember, id: 999), column: lost.pip.column,
                                   row: lost.pip.row + 1, speed: 8, origin: .spawn))
        t = SessionModel(resuming: SuspendedSession(kind: .campaign(round: 4), state: lost, versus: nil))
        for _ in 0..<10 { t.step([.none]) }
        XCTAssertEqual(t.outcome, .roundLost(.crushed))
        XCTAssertEqual(t.next, .campaign(round: 4))
    }

    func testCampaignCompleteAtRound99() {
        var s = SessionModel(kind: .campaign(round: 99))
        win(&s)
        XCTAssertEqual(s.outcome, .campaignComplete)
        XCTAssertNil(s.next)
    }

    func testTimeTrialAccumulatesAndRecordsBest() {
        let trail = TimeTrial.all[0]
        var kind = SessionKind.timeTrial(trail: trail.id, index: 0, elapsedTicks: 0)
        var save = SaveData()
        for i in 0..<trail.rounds.count {
            var s = SessionModel(kind: kind)
            XCTAssertEqual(s.state.config.round, trail.rounds[i])
            for _ in 0..<100 { s.step([.none]) }
            win(&s)
            if i < trail.rounds.count - 1 {
                XCTAssertEqual(s.outcome, .roundWon(round: trail.rounds[i]))
                kind = s.next!
            } else {
                guard case let .trialComplete(ticks) = s.outcome else { return XCTFail("\(s.outcome)") }
                XCTAssertEqual(ticks, 101 * trail.rounds.count)
                XCTAssertTrue(s.record(into: &save))
                XCTAssertEqual(save.bestTimes[trail.id], ticks)
            }
        }
    }

    func testLessonsChainAndRecord() {
        var s = SessionModel(kind: .lesson(id: "lift"))
        s.step([.tap(.a)])
        XCTAssertEqual(s.outcome, .lessonComplete)
        var save = SaveData()
        s.record(into: &save)
        XCTAssertTrue(save.lessonsCompleted.contains("lift"))
        XCTAssertEqual(s.next, .lesson(id: "drop"))
    }

    func testVersusSession() {
        var s = SessionModel(kind: .versus, seed: 4)
        XCTAssertEqual(s.versus?.players.count, 2)
        XCTAssertEqual(s.state.board.width, Rules.versusColumns)
        for _ in 0..<60 { s.step([.none, .none]) }
        XCTAssertEqual(s.versus?.players[1].tick, 60)
        let snap = s.snapshot
        XCTAssertNil(snap.state)
        XCTAssertEqual(SessionModel(resuming: snap).versus, s.versus)
    }
}

final class AudioSynthTests: XCTestCase {
    func testNoteParsing() throws {
        XCTAssertEqual(NoteParser.midi("A4"), 69)
        XCTAssertEqual(NoteParser.midi("C4"), 60)
        XCTAssertEqual(NoteParser.midi("C#4"), 61)
        XCTAssertEqual(NoteParser.midi("Bb3"), 58)
        let p = try NoteParser.parse("C5:2 -:2 k h:3")
        XCTAssertEqual(p.steps, 8)
        XCTAssertEqual(p.events.map(\.step), [0, 4, 5])
        XCTAssertThrowsError(try NoteParser.parse("Q9"))
        XCTAssertThrowsError(try NoteParser.parse("C4:0"))
        XCTAssertEqual(midiFrequency(69), 440, accuracy: 0.001)
    }

    func testSongTracksHaveMatchingLengths() {
        for song in SongLibrary.all {
            let lengths = Set(song.tracks.map(\.steps))
            XCTAssertEqual(lengths.count, 1, "\(song.name) tracks \(song.tracks.map(\.steps))")
            XCTAssertEqual(song.steps % 16, 0, "\(song.name) is whole bars")
        }
    }

    func testEveryEffectRendersAudibleBoundedSound() {
        for fx in SoundEffect.allCases {
            let s = SFXSynth.render(fx, sampleRate: 22_050)
            XCTAssertGreaterThan(s.count, 100, "\(fx)")
            XCTAssertLessThan(s.count, 22_050 * 2, "\(fx) is short")
            let peak = s.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.01, "\(fx) is audible")
            XCTAssertLessThan(peak, 2)
        }
        XCTAssertEqual(SoundEffect.chain(1), .clear)
        XCTAssertEqual(SoundEffect.chain(9), .chain5)
    }

    func testMixerRendersMusicAndRespectsMute() {
        let mixer = ChipMixer(sampleRate: 22_050)
        mixer.play(song: SongLibrary.wren)
        mixer.play(.clear)
        var buf = [Float](repeating: 0, count: 4096)
        buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 4096) }
        XCTAssertGreaterThan(buf.map(abs).max() ?? 0, 0.01)
        XCTAssertTrue(buf.allSatisfy { abs($0) <= 1 }, "soft-clipped")
        mixer.muted = true
        buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 4096) }
        XCTAssertEqual(buf.map(abs).max(), 0)
        mixer.muted = false
        mixer.silence()
        buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 4096) }
        XCTAssertEqual(buf.map(abs).max(), 0, "silence stops the song")
    }

    func testMixerLoopsSongs() {
        let mixer = ChipMixer(sampleRate: 8_000)
        mixer.play(song: SongLibrary.menu)
        // Longer than one pass through the song.
        let n = 8_000 * 12
        var buf = [Float](repeating: 0, count: n)
        buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: n) }
        XCTAssertGreaterThan(buf[(n - 4000)...].map(abs).max() ?? 0, 0.01, "still playing after looping")
    }
}

final class PixelArtTests: XCTestCase {
    func testSpritesHaveExpectedSizes() {
        for (name, rows) in SpriteData.sprites {
            let widths = Set(rows.map(\.count))
            XCTAssertEqual(widths.count, 1, "\(name) rows are not equal width")
            let allowed: Set<Character> = Set(".K123WPGgLSBbYROCcDE")
            for r in rows { XCTAssertTrue(Set(r).isSubset(of: allowed), "\(name) has unknown keys") }
        }
        for c in PieceColor.allCases {
            for kind in [PieceKind.mite, .seed, .starseed] {
                let p = Piece(id: 1, kind: kind, color: c)
                let img = PixelArt.sprite(PixelArt.spriteName(for: p), color: c)
                XCTAssertEqual(img?.width, 16)
                XCTAssertEqual(img?.height, 16)
            }
        }
        for m in MiteKind.allCases {
            if let o = PixelArt.overlayName(for: m) { XCTAssertNotNil(SpriteData.sprites[o]) }
        }
        XCTAssertEqual(PixelArt.sprite("gloom_1")?.width, 32)
    }

    func testPieceColorsAreDistinct() {
        let mains = PieceColor.allCases.map { SpriteData.pieceColors[PixelArt.colorName($0)]?["1"] }
        XCTAssertEqual(Set(mains.compactMap { $0 }).count, 3)
        // Each color uses a different body silhouette, so color is never the only cue.
        let shapes = PieceColor.allCases.map { c in
            SpriteData.sprites["mite_" + PixelArt.colorName(c)]!.map { String($0.map { $0 == "." ? "." : "#" }) }
        }
        XCTAssertEqual(Set(shapes.map { $0.joined() }).count, 3)
    }

    func testTextRendering() {
        let img = PixelArt.text("x2 chain!")
        XCTAssertEqual(img.width, 9 * 6 - 1)
        XCTAssertEqual(img.height, 7)
        XCTAssertEqual(img.rgba.count, img.width * img.height * 4)
        XCTAssertTrue(img.rgba.contains(255))
    }
}
