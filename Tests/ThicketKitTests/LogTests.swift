import Foundation
import ThicketCore
import ThicketKit
import XCTest

final class LogTests: XCTestCase {
    func testDebugLinesOnlyWhenVerbose() {
        let log = GameLog(capacity: 100)
        log.debug("game", "hidden")
        log.info("game", "shown")
        XCTAssertEqual(log.snapshot.count, 1)
        XCTAssertTrue(log.snapshot[0].contains("INF [game] shown"))
        log.verbose = true
        log.debug("input", "now visible")
        XCTAssertEqual(log.snapshot.count, 2)
        XCTAssertTrue(log.snapshot[1].contains("DBG [input] now visible"))
    }

    func testRingBufferAndSink() {
        let log = GameLog(capacity: 3)
        var mirrored: [String] = []
        log.sink = { _, cat, msg in mirrored.append("\(cat):\(msg)") }
        for i in 0..<5 { log.info("t", "line \(i)") }
        XCTAssertEqual(log.snapshot.count, 3)
        XCTAssertTrue(log.snapshot[0].hasSuffix("line 2"))
        XCTAssertEqual(mirrored.count, 5)
        log.clear()
        XCTAssertTrue(log.snapshot.isEmpty)
    }

    func testFlushWritesOnlyWhenDirty() throws {
        let log = GameLog(capacity: 10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thicket-log-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        log.info("t", "hello")
        XCTAssertTrue(log.flush(to: url))
        XCTAssertFalse(log.flush(to: url), "nothing new")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("hello"))
    }

    func testFormatting() {
        XCTAssertEqual(LogFormat.buttons([.left, .a]), "L+A")
        XCTAssertEqual(LogFormat.buttons([]), "-")
        var s = GameState(config: .lesson(), board: try! Board.parse([". . . T"]), pip: Pip(column: 2, row: 0))
        s.pip.carried = [.seed(.ember, id: 9)]
        let dump = LogFormat.state(s)
        XCTAssertTrue(dump.contains("Pip(2,0)"))
        XCTAssertTrue(dump.contains("carrying=[e]"))
        XCTAssertTrue(dump.contains("| . . . T"))
        XCTAssertEqual(LogFormat.event(.actionRejected(action: .climb, reason: "nothing in front to climb")),
                       "rejected climb: nothing in front to climb")
    }

    func testSettingsKeepNewFieldsAndDefaultThem() throws {
        var s = Settings()
        XCTAssertEqual(s.graphics, .threeD)
        s.graphics = .pixel
        s.verboseLogging = true
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"muted": true}"#.utf8))
        XCTAssertEqual(old.graphics, .threeD)
        XCTAssertFalse(old.verboseLogging)
    }
}
