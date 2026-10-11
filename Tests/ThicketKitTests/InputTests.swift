import ThicketCore
import ThicketKit
import XCTest

final class DPadTests: XCTestCase {
    let pad = DPadGeometry(center: Vec2(100, 100), radius: 50)

    func testCardinalSectors() {
        XCTAssertEqual(pad.buttons(at: Vec2(140, 100)), .right)
        XCTAssertEqual(pad.buttons(at: Vec2(60, 100)), .left)
        XCTAssertEqual(pad.buttons(at: Vec2(100, 60)), .up, "UIKit y grows downward")
        XCTAssertEqual(pad.buttons(at: Vec2(100, 140)), .down)
    }

    func testDiagonalSectors() {
        XCTAssertEqual(pad.buttons(at: Vec2(130, 70)), [.up, .right])
        XCTAssertEqual(pad.buttons(at: Vec2(70, 70)), [.up, .left])
        XCTAssertEqual(pad.buttons(at: Vec2(70, 130)), [.down, .left])
        XCTAssertEqual(pad.buttons(at: Vec2(130, 130)), [.down, .right])
    }

    func testCardinalSectorsAreWiderThanDiagonals() {
        // 25° above horizontal is still plain Right with 60° cardinal sectors.
        let a = 25.0 * .pi / 180
        XCTAssertEqual(pad.buttons(at: Vec2(100 + 40 * cos(a), 100 - 40 * sin(a))), .right)
        let b = 35.0 * .pi / 180
        XCTAssertEqual(pad.buttons(at: Vec2(100 + 40 * cos(b), 100 - 40 * sin(b))), [.up, .right])
    }

    func testDeadZoneAndOutsideRadius() {
        XCTAssertEqual(pad.buttons(at: Vec2(103, 102)), [])
        XCTAssertEqual(pad.buttons(at: Vec2(400, 100)), .right, "direction keeps working outside the pad")
    }
}

final class TouchTrackerTests: XCTestCase {
    func tracker() -> TouchTracker {
        TouchTracker(controls: [
            ResolvedControl(id: .dpad, center: Vec2(100, 300), radius: 60),
            ResolvedControl(id: .a, center: Vec2(700, 280), radius: 30),
            ResolvedControl(id: .b, center: Vec2(630, 320), radius: 30),
            ResolvedControl(id: .ab, center: Vec2(700, 350), radius: 20),
            ResolvedControl(id: .pause, center: Vec2(760, 30), radius: 18),
        ])
    }

    func testDPadAndButtonsSimultaneously() {
        var t = tracker()
        t.began(1, at: Vec2(100, 350)) // down on the pad
        t.began(2, at: Vec2(700, 280)) // A
        XCTAssertEqual(t.held, [.down, .a])
        XCTAssertEqual(t.consumePressed(), [.down, .a])
        XCTAssertEqual(t.consumePressed(), [], "latches are consumed")
        t.ended(2)
        XCTAssertEqual(t.held, .down)
        t.ended(1)
        XCTAssertEqual(t.held, [])
    }

    func testDPadKeepsItsFingerOutsideThePad() {
        var t = tracker()
        t.began(1, at: Vec2(130, 300))
        t.moved(1, to: Vec2(400, 300)) // slid far right, off the pad
        XCTAssertEqual(t.held, .right)
        t.moved(1, to: Vec2(100, 200))
        XCTAssertEqual(t.held, .up)
        // A second finger landing on the pad does not steal it.
        t.began(2, at: Vec2(60, 300))
        XCTAssertEqual(t.held, .up)
    }

    func testFingerRollsBetweenButtons() {
        var t = tracker()
        t.began(5, at: Vec2(630, 320)) // B
        XCTAssertEqual(t.held, .b)
        _ = t.consumePressed()
        t.moved(5, to: Vec2(700, 285)) // rolled onto A
        XCTAssertEqual(t.held, .a)
        XCTAssertEqual(t.consumePressed(), .a, "rolling onto a button presses it")
        t.moved(5, to: Vec2(500, 100)) // off every button
        XCTAssertEqual(t.held, [])
        t.moved(5, to: Vec2(700, 350)) // back on, A+B
        XCTAssertEqual(t.held, [.a, .b])
    }

    func testABButtonPressesBoth() {
        var t = tracker()
        t.began(1, at: Vec2(700, 350))
        XCTAssertEqual(t.held, [.a, .b])
        XCTAssertEqual(t.consumeFeedback(), [.ab])
    }

    func testVeryShortTapIsLatched() {
        var t = tracker()
        t.began(1, at: Vec2(700, 280))
        t.ended(1)
        XCTAssertEqual(t.held, [])
        XCTAssertEqual(t.consumePressed(), .a)
    }

    func testNothingStuckAfterInterruption() {
        var t = tracker()
        t.began(1, at: Vec2(100, 350))
        t.began(2, at: Vec2(700, 280))
        t.reset()
        XCTAssertEqual(t.held, [])
        XCTAssertEqual(t.touchCount, 0)
        XCTAssertEqual(t.consumePressed(), [])
    }

    func testLostTouchEndIsDroppedOnSync() {
        var t = tracker()
        t.began(1, at: Vec2(100, 350))
        t.began(2, at: Vec2(700, 280))
        t.sync(activeTouches: [2]) // the system never sent touch 1's end
        XCTAssertEqual(t.held, .a)
        t.sync(activeTouches: [])
        XCTAssertEqual(t.held, [])
    }

    func testTouchOutsideControlsDoesNothing() {
        var t = tracker()
        t.began(1, at: Vec2(400, 200))
        XCTAssertEqual(t.held, [])
        XCTAssertEqual(t.consumePressed(), [])
    }
}

final class MergeTests: XCTestCase {
    func testEdgeDetectorFindsPressesAndKeepsTapsBetweenPolls() {
        var e = EdgeDetector()
        XCTAssertEqual(e.frame(held: .a).pressed, .a)
        XCTAssertEqual(e.frame(held: .a).pressed, [], "held, not newly pressed")
        e.notePress(.b) // pressed and released between polls
        let f = e.frame(held: .a)
        XCTAssertEqual(f.pressed, .b)
        XCTAssertEqual(f.held, .a)
        e.reset()
        XCTAssertEqual(e.frame(held: []).pressed, [])
    }

    func testMergerUnionsSourcesAndCarriesPresses() {
        var m = InputMerger()
        let f = m.merge([SourceState(held: .left, pressed: .left), SourceState(held: .a, pressed: [])])
        XCTAssertEqual(f.held, [.left, .a])
        XCTAssertEqual(f.pressed, .left)
        m.carryOver(InputFrame(held: [], pressed: .b))
        XCTAssertEqual(m.merge([]).pressed, .b)
        XCTAssertEqual(m.merge([]).pressed, [])
    }

    func testKeyboardMaps() {
        let k = KeyMap.HID.self
        XCTAssertEqual(KeyMap.buttons(forPressedKeys: [k.left, k.letter("x")], map: KeyMap.solo), [.left, .a])
        XCTAssertEqual(KeyMap.buttons(forPressedKeys: [k.space], map: KeyMap.solo), [.a, .b])
        XCTAssertEqual(KeyMap.buttons(forPressedKeys: [k.letter("w"), k.letter("f")], map: KeyMap.versusP1), [.up, .a])
        XCTAssertEqual(KeyMap.buttons(forPressedKeys: [k.letter("w")], map: KeyMap.versusP2), [])
        XCTAssertEqual(k.letter("a"), 0x04)
        XCTAssertEqual(k.letter("z"), 0x1D)
    }
}

final class LayoutTests: XCTestCase {
    let safe = Rect2(x: 44, y: 0, width: 724, height: 390)

    func testControlsStayInsideSafeAreaAndOffThePlayfield() {
        let resolved = ControlLayout.standard.resolve(in: safe)
        XCTAssertEqual(Set(resolved.map(\.id)), Set(ControlID.allCases))
        for c in resolved {
            XCTAssertGreaterThanOrEqual(c.center.x - c.radius, safe.minX - 0.001)
            XCTAssertLessThanOrEqual(c.center.x + c.radius, safe.maxX + 0.001)
            XCTAssertGreaterThanOrEqual(c.center.y - c.radius, safe.minY - 0.001)
            XCTAssertLessThanOrEqual(c.center.y + c.radius, safe.maxY + 0.001)
        }
        // The middle third (where the playfield is drawn) stays clear of the D-pad and A/B.
        let middle = Rect2(x: safe.minX + safe.width / 3, y: safe.minY, width: safe.width / 3, height: safe.height)
        for c in resolved where [.dpad, .a, .b, .ab].contains(c.id) {
            XCTAssertFalse(c.frame.intersects(middle), "\(c.id) overlaps the playfield")
        }
    }

    func testEditingClampsAndSanitizes() {
        var l = ControlLayout.standard
        l.setCenter(.a, Vec2(1.7, -3))
        XCTAssertEqual(l.placement(.a)?.center, Vec2(1, 0))
        l.scale = 9
        l.opacity = 0
        l.placements.removeAll { $0.id == .b }
        let s = l.sanitized()
        XCTAssertEqual(s.scale, ControlLayout.scaleRange.upperBound)
        XCTAssertEqual(s.opacity, ControlLayout.opacityRange.lowerBound)
        XCTAssertNotNil(s.placement(.b), "missing controls come back")
    }

    func testDeviceKey() {
        XCTAssertEqual(ControlLayout.deviceKey(idiom: "phone", screenWidth: 375, screenHeight: 667), "phone-667x375")
        XCTAssertEqual(ControlLayout.deviceKey(idiom: "pad", screenWidth: 1366, screenHeight: 1024), "pad-1366x1024")
    }
}
