import SpriteKit
@testable import Thicket
import ThicketCore
import ThicketKit
import XCTest

/// Tests for the iOS layer (run on the simulator).
final class AppTests: XCTestCase {
    func testUserDefaultsStoreRoundTrip() throws {
        let suite = "thicket.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = Persistence(store: UserDefaultsStore(defaults: defaults))
        var s = Settings()
        s.sfxVolume = 0.3
        s.setLayout(ControlLayout.standard, for: "phone-667x375")
        p.saveSettings(s)
        XCTAssertEqual(Persistence(store: UserDefaultsStore(defaults: defaults)).loadSettings(), s)
    }

    func testTexturesAreNearestFilteredAndSized() {
        let t = TextureCache.shared.sprite("mite_tide", color: .tide)
        XCTAssertEqual(t.filteringMode, .nearest)
        XCTAssertEqual(t.size(), CGSize(width: 16, height: 16))
        XCTAssertNotNil(PixelImages.cgImage(PixelArt.text("123")))
    }

    func testSceneUsesWholePixelScale() {
        let scene = GameScene(size: CGSize(width: 667, height: 375))
        scene.configure(columns: 7, rows: 13, players: 1)
        scene.layout(safeInsets: .zero, screenScale: 2)
        XCTAssertEqual(scene.pixelScale, scene.pixelScale.rounded())
        XCTAssertGreaterThanOrEqual(scene.pixelScale, 2)
        scene.render(SessionModel(kind: .campaign(round: 1)))
    }

    func testTouchControlsViewTracksMultitouch() {
        let v = TouchControlsView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        v.layoutIfNeeded()
        v.relayout()
        XCTAssertEqual(v.tracker.controls.count, ControlID.allCases.count)
        XCTAssertEqual(v.consume(), SourceState())
    }

    func testAudioMixerProducesSamples() {
        let audio = AudioEngine()
        var buf = [Float](repeating: 0, count: 2048)
        audio.mixer.play(.clear)
        buf.withUnsafeMutableBufferPointer { audio.mixer.render(into: $0.baseAddress!, count: 2048) }
        XCTAssertGreaterThan(buf.map(abs).max() ?? 0, 0)
    }
}
