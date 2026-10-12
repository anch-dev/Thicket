import Combine
import SpriteKit
import ThicketCore
import ThicketKit
import UIKit

/// Owns a running session. Publishes only coarse state (pause, outcome) so
/// SwiftUI is not re-rendered every tick.
final class GameRunner: ObservableObject, Identifiable {
    let id = UUID()
    private(set) var session: SessionModel
    @Published var paused = false
    @Published private(set) var outcome: SessionOutcome = .none
    @Published private(set) var newRecord = false
    weak var app: AppModel?

    init(session: SessionModel, app: AppModel?) {
        self.session = session
        self.app = app
        outcome = session.outcome
    }

    var isVersus: Bool { session.versus != nil }

    func step(_ inputs: [InputFrame]) -> [[GameEvent]] {
        let events = session.step(inputs)
        if session.outcome != outcome {
            outcome = session.outcome
            if let app {
                newRecord = app.recordOutcome(&session)
            }
        }
        return events
    }

    func pause() {
        guard outcome == .none, !paused else { return }
        paused = true
    }
}

/// Hosts the SpriteKit view and the touch controls, and runs the fixed-step loop.
final class GameViewController: UIViewController {
    let runner: GameRunner
    private var renderer: GameRenderer!
    private let touchView = TouchControlsView()
    private let hardware = HardwareInput()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var accumulator: Double = 0
    private var mergers = [InputMerger(), InputMerger()]
    private var pauseWasHeld = false
    private var lastHardwareActivity: CFTimeInterval = -100
    private var lastLoggedFrame = InputFrame.none
    private let log = GameLog.shared

    private static let tick = 1.0 / Double(Rules.ticksPerSecond)

    init(runner: GameRunner) {
        self.runner = runner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersStatusBarHidden: Bool { true }

    private var app: AppModel? { runner.app }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let players = runner.isVersus ? 2 : 1
        let st = runner.session.state
        let mode = app?.settings.graphics ?? .threeD
        switch mode {
        case .threeD: renderer = Renderer3D(columns: st.board.width, rows: st.board.rows, players: players)
        case .pixel: renderer = PixelRenderer(columns: st.board.width, rows: st.board.rows, players: players)
        }
        view.addSubview(renderer.view)
        view.addSubview(touchView)
        log.info("game", "start \(runner.session.title) kind=\(runner.session.kind) renderer=\(renderer.name) players=\(players)")
        log.info("game", "initial state\n" + LogFormat.state(st))

        touchView.isHidden = runner.isVersus
        touchView.onPress = { [weak self] id in
            self?.app?.haptics.tap()
            if id == .pause || id == .start {
                self?.togglePause()
            }
        }
        hardware.onActivity = { [weak self] in
            self?.lastHardwareActivity = CACurrentMediaTime()
        }
        hardware.log = log
        applySettings()
        renderer.render(runner.session)
    }

    func applySettings() {
        guard let app else { return }
        touchView.layout = app.settings.layout(for: app.deviceKey)
        updateTouchVisibility()
    }

    private func updateTouchVisibility() {
        guard !runner.isVersus else {
            touchView.isHidden = true
            return
        }
        let always = app?.settings.alwaysShowTouchControls ?? false
        // Hide the on-screen pad while a controller/keyboard is actively used.
        let usingHardware = (hardware.hasController || hardware.hasKeyboard)
            && CACurrentMediaTime() - lastHardwareActivity < 20
        let hide = !always && usingHardware
        if hide != touchView.isHidden {
            touchView.isHidden = hide
            touchView.releaseAll()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        renderer.view.frame = view.bounds
        touchView.frame = view.bounds
        let scale = view.window?.screen.scale ?? traitCollection.displayScale
        renderer.layout(size: view.bounds.size, safeInsets: view.safeAreaInsets, screenScale: scale)
        log.info("ui", "layout \(Int(view.bounds.width))x\(Int(view.bounds.height))pt @\(scale)x insets=\(view.safeAreaInsets)")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        startLoop()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopLoop()
    }

    func startLoop() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        accumulator = 0
        let link = CADisplayLink(target: self, selector: #selector(displayTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Clears every held input (used on pause, interruption and backgrounding).
    func releaseInputs() {
        touchView.releaseAll()
        hardware.reset()
        mergers = [InputMerger(), InputMerger()]
    }

    func togglePause() {
        log.info("game", runner.paused ? "resume" : "pause")
        if runner.paused {
            runner.paused = false
        } else {
            runner.pause()
        }
        releaseInputs()
    }

    @objc private func displayTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? Self.tick : min(0.25, now - lastTimestamp)
        lastTimestamp = now
        updateTouchVisibility()

        let versus = runner.isVersus
        let hw = hardware.poll(versus: versus)
        let touch = touchView.isHidden ? SourceState() : touchView.consume()
        let frames = [mergers[0].merge([hw[0], touch]), mergers[1].merge([hw[1]])]

        // Start / Pause toggle pausing; they never reach the simulation.
        let pausePressed = frames.contains { !$0.pressed.intersection([.pause, .start]).isEmpty }
        if pausePressed && runner.outcome == .none {
            togglePause()
            return
        }

        if runner.paused || runner.outcome != .none {
            accumulator = 0
            renderer.render(runner.session)
            return
        }

        if frames[0] != lastLoggedFrame && log.verbose {
            log.debug("input", "P1 " + LogFormat.frame(frames[0]) + (touch.held.isEmpty && touch.pressed.isEmpty ? "" : " (touch)"))
            lastLoggedFrame = frames[0]
        }

        accumulator += dt
        var ticked = false
        while accumulator >= Self.tick {
            accumulator -= Self.tick
            let inputs = ticked ? frames.map { InputFrame(held: $0.held) } : frames
            let events = runner.step(inputs)
            ticked = true
            renderer.apply(events, session: runner.session)
            handleSound(events)
            if runner.outcome != .none { break }
        }
        if !ticked {
            // No tick this display frame: keep the presses for the next one.
            for i in 0..<2 { mergers[i].carryOver(frames[i]) }
        }
        renderer.render(runner.session)
    }

    private func logEvents(_ events: [[GameEvent]]) {
        let session = runner.session
        for (player, list) in events.enumerated() {
            for e in list {
                switch e {
                case .actionRejected:
                    // Always logged: explains "why didn't Pip do that?".
                    log.info("pip", "P\(player + 1) " + LogFormat.event(e) + " | " + LogFormat.pip(session.versus?.players[player].pip ?? session.state.pip))
                case .gameOver, .roundCleared, .chain, .canopySlam, .phaseChanged, .starseedBurst:
                    log.info("game", "P\(player + 1) " + LogFormat.event(e))
                    if case .gameOver = e {
                        log.info("game", "state at game over\n" + LogFormat.state(session.versus?.players[player] ?? session.state))
                    }
                default:
                    if log.verbose { log.debug("event", "P\(player + 1) t=\(session.state.tick) " + LogFormat.event(e)) }
                }
            }
        }
    }

    private func handleSound(_ events: [[GameEvent]]) {
        logEvents(events)
        guard let app else { return }
        let audio = app.audio
        for (player, list) in events.enumerated() {
            for e in list {
                switch e {
                case .pipWalked: if player == 0 { audio.play(.step) }
                case .pipTurned: break
                case .pipClimbed: audio.play(.step)
                case .lifted: audio.play(.lift)
                case .pulled: audio.play(.pull)
                case .placed: audio.play(.place)
                case .kicked: audio.play(.kick)
                case .bump: audio.play(.bump); app.haptics.bump()
                case .caught: audio.play(.caught)
                case .landed: audio.play(.land)
                case let .cleared(_, _, chain, _): audio.play(SoundEffect.chain(chain))
                case .hit: audio.play(.hit)
                case .starseedCreated: audio.play(.starseed)
                case .starseedBurst: audio.play(.burst); app.haptics.slam()
                case let .spawned(_, kind): audio.play(kind == .mite ? .spawnMite : .spawnSeed)
                case .phaseChanged(.gloom):
                    audio.play(.phaseGloom)
                    audio.play(song: SongLibrary.gloom)
                case .phaseChanged(.wren):
                    audio.play(.phaseWren)
                    audio.play(song: SongLibrary.wren)
                case .canopySlam: audio.play(.slam); app.haptics.slam()
                case .canopyLift: audio.play(.canopyLift)
                case .gameOver:
                    audio.play(song: nil)
                    audio.play(.gameOver)
                    app.haptics.failure()
                case .roundCleared:
                    if runner.session.state.config.endless {
                        audio.play(.roundClear)
                    } else {
                        audio.play(song: nil)
                        audio.play(.roundClear)
                        app.haptics.success()
                    }
                case .placedBelow, .actionRejected, .pipLanded, .attack, .chain:
                    break
                }
            }
        }
        if runner.outcome == .lessonComplete {
            audio.play(.roundClear)
        }
    }
}
