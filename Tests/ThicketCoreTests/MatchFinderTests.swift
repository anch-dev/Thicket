import ThicketCore
import XCTest

final class MatchFinderTests: XCTestCase {
    func lines(_ rows: [String]) throws -> [MatchLine] {
        MatchFinder.findLines(in: try Board.parse(rows))
    }

    func testHorizontalMatch() throws {
        let l = try lines(["E E e"])
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].direction, .horizontal)
        XCTAssertEqual(l[0].cells, [Cell(0, 0), Cell(1, 0), Cell(2, 0)])
        XCTAssertEqual(l[0].color, .ember)
    }

    func testVerticalMatch() throws {
        let l = try lines(["t", "T", "T"])
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].direction, .vertical)
        XCTAssertEqual(l[0].cells, [Cell(0, 0), Cell(0, 1), Cell(0, 2)])
    }

    func testDiagonalUpMatch() throws {
        let l = try lines([
            ". . e",
            ". E T",
            "E T B",
        ])
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].direction, .diagonalUp)
        XCTAssertEqual(l[0].cells, [Cell(0, 0), Cell(1, 1), Cell(2, 2)])
    }

    func testDiagonalDownMatch() throws {
        let l = try lines([
            "e . .",
            "T E .",
            "B T E",
        ])
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].direction, .diagonalDown)
        XCTAssertEqual(l[0].cells, [Cell(0, 2), Cell(1, 1), Cell(2, 0)])
    }

    func testThreeMitesNeverMatch() throws {
        XCTAssertTrue(try lines(["E E E"]).isEmpty)
        XCTAssertTrue(try lines(["E E E E E"]).isEmpty)
        XCTAssertTrue(try lines(["B", "B", "B"]).isEmpty)
        XCTAssertTrue(try lines([". . T", ". T B", "T B E"]).isEmpty)
    }

    func testSeedRequiredAndValidCombos() throws {
        XCTAssertEqual(try lines(["e E E"]).count, 1, "Seed+Mite+Mite")
        XCTAssertEqual(try lines(["e e E"]).count, 1, "Seed+Seed+Mite")
        XCTAssertEqual(try lines(["E e E"]).count, 1, "seed in the middle")
        XCTAssertEqual(try lines(["e e e"]).count, 1, "three Seeds")
        XCTAssertTrue(try lines(["e E"]).isEmpty, "too short")
    }

    func testColorBreaksLine() throws {
        XCTAssertTrue(try lines(["E T e"]).isEmpty)
        XCTAssertTrue(try lines(["E E t"]).isEmpty)
    }

    func testMaximalRunReportedOnce() throws {
        let l = try lines(["E E E e"])
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].length, 4)
    }

    func testOverlappingLinesBothFound() throws {
        let l = try lines([
            "E e E",
            "T E B",
            "B E T",
        ])
        XCTAssertEqual(Set(l.map(\.direction)), [.horizontal, .vertical])
        XCTAssertEqual(Set(l.flatMap(\.cells)).count, 5)
    }

    func testSlantOnlyJoinsDiagonals() throws {
        XCTAssertTrue(try lines(["Es E e"]).isEmpty, "slant breaks a horizontal line")
        XCTAssertTrue(try lines(["e", "E", "Es"]).isEmpty, "slant breaks a vertical line")
        let d = try lines([
            ". . e",
            ". E T",
            "Es T B",
        ])
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].direction, .diagonalUp)
    }

    func testStarseedCountsAsSeed() throws {
        XCTAssertEqual(try lines(["E E e*"]).count, 1)
    }

    func testNotationRoundTrip() throws {
        let rows = [". e*", "Es Tx Bf", "E t b"]
        let b = try Board.parse(rows)
        XCTAssertEqual(b.notation, rows)
        XCTAssertThrowsError(try Board.parse(["E", ". "]).notation) { e in
            XCTAssertEqual(e as? BoardNotationError, .floatingPiece(Cell(0, 1)))
        }
        XCTAssertThrowsError(try Board.parse(["Q"]))
    }
}
