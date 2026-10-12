import SwiftUI
import ThicketCore
import ThicketKit
import UIKit

/// App-wide state: navigation, settings, save data, audio, the running game.
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case title, rounds, trials, lessons, settings, controls, game
    }

    @Published var screen: Screen = .title
    @Published var settings: Settings {
        didSet {
            persistence.saveSettings(settings)
            audio.apply(settings)
            haptics.enabled = settings.haptics
        }
    }

    @Published private(set) var save: SaveData
    @Published private(set) var suspended: SuspendedSession?
    @Published private(set) var runner: GameRunner? = nil

    let persistence: Persistence
    let audio = AudioEngine()
    let haptics = Haptics()
    let deviceKey: String
    let isPad: Bool
    weak var gameController: GameViewController?

    init(persistence: Persistence = AppModel.makePersistence()) {
        self.persistence = persistence
        settings = persistence.loadSettings()
        save = persistence.loadSave()
        suspended = persistence.loadSuspended()
        isPad = UIDevice.current.userInterfaceIdiom == .pad
        let bounds = UIScreen.main.bounds
        deviceKey = ControlLayout.deviceKey(idiom: isPad ? "pad" : "phone",
                                            screenWidth: Double(bounds.width), screenHeight: Double(bounds.height))
        audio.apply(settings)
        haptics.enabled = settings.haptics
        audio.play(song: SongLibrary.menu)
    }

    static func makePersistence() -> Persistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Persistence(store: UserDefaultsStore(),
                           snapshotStore: FileStore(directory: base.appendingPathComponent("Thicket", isDirectory: true)))
    }

    // MARK: Navigation

    func go(_ s: Screen) {
        audio.play(.menuMove)
        screen = s
    }

    func start(_ kind: SessionKind) {
        persistence.clearSuspended()
        suspended = nil
        let session = SessionModel(kind: kind, seed: UInt64.random(in: 1...UInt64.max))
        runner = GameRunner(session: session, app: self)
        screen = .game
        audio.play(.menuSelect)
        audio.play(song: songFor(session))
        haptics.prepare()
    }

    func resumeSuspended() {
        guard let s = suspended else { return }
        let session = SessionModel(resuming: s)
        let r = GameRunner(session: session, app: self)
        r.paused = true
        runner = r
        suspended = nil
        persistence.clearSuspended()
        screen = .game
        audio.play(song: songFor(session))
    }

    func songFor(_ session: SessionModel) -> Song {
        if session.lesson != nil { return SongLibrary.menu }
        return session.state.phase.kind == .gloom ? SongLibrary.gloom : SongLibrary.wren
    }

    func restart() {
        guard let r = runner else { return }
        switch r.session.kind {
        case let .timeTrial(trail, _, _):
            start(.timeTrial(trail: trail, index: 0, elapsedTicks: 0))
        default:
            start(r.session.kind)
        }
    }

    func continueAfterOutcome() {
        if let next = runner?.session.next {
            start(next)
        } else {
            quitToMenu()
        }
    }

    func quitToMenu() {
        runner = nil
        persistence.clearSuspended()
        screen = .title
        audio.play(song: SongLibrary.menu)
    }

    func resume() {
        runner?.paused = false
        gameController?.releaseInputs()
    }

    /// Called once when a session finishes. Returns true for a new record.
    func recordOutcome(_ session: inout SessionModel) -> Bool {
        var s = save
        let isRecord = session.record(into: &s)
        save = s
        persistence.saveSave(s)
        persistence.clearSuspended()
        return isRecord
    }

    func resetProgress() {
        save = SaveData()
        persistence.saveSave(save)
    }

    func updateLayout(_ layout: ControlLayout) {
        settings.setLayout(layout, for: deviceKey)
        gameController?.applySettings()
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            audio.resume()
        case .inactive:
            runner?.pause()
            gameController?.releaseInputs()
        case .background:
            runner?.pause()
            gameController?.releaseInputs()
            saveSnapshot()
            audio.suspend()
        @unknown default:
            break
        }
    }

    /// Persists an unfinished game so it can be resumed even if iOS terminates the app.
    func saveSnapshot() {
        guard let r = runner, !r.session.isFinished else { return }
        persistence.saveSuspended(r.session.snapshot)
    }
}
