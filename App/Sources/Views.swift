import SwiftUI
import ThicketCore
import ThicketKit

// MARK: - Style

enum Palette {
    static let background = Color(red: 0.07, green: 0.12, blue: 0.09)
    static let panel = Color(red: 0.11, green: 0.17, blue: 0.13)
    static let leaf = Color(red: 0.61, green: 0.86, blue: 0.43)
    static let ember = Color(red: 0.90, green: 0.62, blue: 0.0)
    static let tide = Color(red: 0.24, green: 0.61, blue: 0.88)
    static let bloom = Color(red: 0.85, green: 0.49, blue: 0.71)
}

func pixelFont(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// Crisp pixel-art text rendered with the game's own bitmap font.
struct PixelText: View {
    let text: String
    var color: UInt32 = 0xFFFF_FFFF
    var scale: CGFloat = 3

    var body: some View {
        let img = PixelArt.text(text, color: color)
        Image(uiImage: PixelImages.uiImage(img))
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(img.width) * scale, height: CGFloat(img.height) * scale)
            .accessibilityLabel(text)
    }
}

struct SpriteImage: View {
    let name: String
    var color: PieceColor?
    var scale: CGFloat = 3

    var body: some View {
        if let img = PixelArt.sprite(name, color: color) {
            Image(uiImage: PixelImages.uiImage(img))
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(img.width) * scale, height: CGFloat(img.height) * scale)
        }
    }
}

struct MenuButtonStyle: ButtonStyle {
    var tint: Color = Palette.leaf

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pixelFont(17))
            .foregroundColor(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(configuration.isPressed ? 0.55 : 0.28))
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint, lineWidth: 2))
    }
}

struct ScreenHeader: View {
    @EnvironmentObject var model: AppModel
    let title: String

    var body: some View {
        HStack {
            Button("< BACK") { model.go(.title) }
                .font(pixelFont(15))
                .foregroundColor(Palette.leaf)
            Spacer()
            PixelText(text: title, color: 0x9CDB_6EFF, scale: 3)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch model.screen {
            case .title: TitleView()
            case .rounds: RoundSelectView()
            case .trials: TrialsView()
            case .lessons: LessonsView()
            case .settings: SettingsView()
            case .controls: ControlsEditorView()
            case .log: LogView()
            case .game:
                if let runner = model.runner {
                    GameScreen(runner: runner).id(runner.id)
                } else {
                    TitleView()
                }
            }
        }
    }
}

// MARK: - Title

struct TitleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 14) {
                PixelText(text: "THICKET", color: 0x9CDB_6EFF, scale: 7)
                Text("A forest puzzle")
                    .font(pixelFont(14))
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 6) {
                    SpriteImage(name: "mite_ember", color: .ember)
                    SpriteImage(name: "seed_tide", color: .tide)
                    SpriteImage(name: "pip_idle")
                    SpriteImage(name: "mite_bloom", color: .bloom)
                    SpriteImage(name: "starseed", color: .ember)
                }
                SpriteImage(name: "wren_1", scale: 3)
            }
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(spacing: 9) {
                    if model.suspended != nil {
                        Button("CONTINUE") { model.resumeSuspended() }
                            .buttonStyle(MenuButtonStyle(tint: Palette.ember))
                    }
                    Button("ROUNDS") { model.go(.rounds) }.buttonStyle(MenuButtonStyle())
                    Button("ENDLESS") { model.start(.endless) }.buttonStyle(MenuButtonStyle())
                    Button("TIME TRIAL") { model.go(.trials) }.buttonStyle(MenuButtonStyle())
                    Button("LESSONS") { model.go(.lessons) }.buttonStyle(MenuButtonStyle(tint: Palette.tide))
                    if model.isPad {
                        Button("2P VERSUS") { model.start(.versus) }.buttonStyle(MenuButtonStyle(tint: Palette.bloom))
                    }
                    Button("SETTINGS") { model.go(.settings) }.buttonStyle(MenuButtonStyle(tint: .gray))
                }
                .padding(.vertical, 16)
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Rounds

struct RoundSelectView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "ROUNDS")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                    ForEach(1...RoundConfig.campaignRounds, id: \.self) { round in
                        let unlocked = round <= model.save.campaign.unlockedRound
                        Button {
                            model.start(.campaign(round: round))
                        } label: {
                            VStack(spacing: 2) {
                                Text(unlocked ? "\(round)" : "--").font(pixelFont(18))
                                Text(model.save.campaign.bestScores[round].map { "\($0)" } ?? " ")
                                    .font(pixelFont(9))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .frame(width: 62, height: 48)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(unlocked ? Palette.leaf.opacity(0.25) : Color.black.opacity(0.3)))
                            .foregroundColor(unlocked ? .white : .gray)
                        }
                        .disabled(!unlocked)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Time trials

struct TrialsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "TIME TRIAL")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(TimeTrial.all) { trail in
                        Button {
                            model.start(.timeTrial(trail: trail.id, index: 0, elapsedTicks: 0))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trail.name.uppercased()).font(pixelFont(17))
                                    Text("Rounds " + trail.rounds.map(String.init).joined(separator: ", "))
                                        .font(pixelFont(11)).foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Text(model.save.bestTimes[trail.id].map { "BEST " + GameScene.clock($0) } ?? "NO TIME")
                                    .font(pixelFont(15))
                                    .foregroundColor(Palette.ember)
                            }
                        }
                        .buttonStyle(MenuButtonStyle())
                    }
                    Text("Clear every round of a trail as fast as you can. Losing a round restarts the trail.")
                        .font(pixelFont(12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Lessons

struct LessonsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "LESSONS")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Lesson.all) { lesson in
                        Button {
                            model.start(.lesson(id: lesson.id))
                        } label: {
                            HStack {
                                Text(lesson.title.uppercased())
                                Spacer()
                                Text(model.save.lessonsCompleted.contains(lesson.id) ? "OK" : "")
                                    .foregroundColor(Palette.leaf)
                            }
                        }
                        .buttonStyle(MenuButtonStyle(tint: Palette.tide))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "SETTINGS")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("MUSIC").frame(width: 90, alignment: .leading)
                        Slider(value: $model.settings.musicVolume, in: 0...1)
                    }
                    HStack {
                        Text("SOUND").frame(width: 90, alignment: .leading)
                        Slider(value: $model.settings.sfxVolume, in: 0...1, onEditingChanged: { done in
                            if !done { model.audio.play(.clear) }
                        })
                    }
                    HStack {
                        Text("GRAPHICS").frame(width: 90, alignment: .leading)
                        Picker("Graphics", selection: $model.settings.graphics) {
                            Text("3D").tag(GraphicsMode.threeD)
                            Text("PIXEL 2D").tag(GraphicsMode.pixel)
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("MUTE ALL", isOn: $model.settings.muted)
                    Toggle("HAPTICS", isOn: $model.settings.haptics)
                    Toggle("ALWAYS SHOW TOUCH CONTROLS", isOn: $model.settings.alwaysShowTouchControls)
                    Text("Audio follows the ring/silent switch.")
                        .font(pixelFont(11)).foregroundColor(.white.opacity(0.5))
                    Button("EDIT TOUCH CONTROLS") { model.go(.controls) }
                        .buttonStyle(MenuButtonStyle(tint: Palette.tide))
                    Toggle("VERBOSE LOGGING", isOn: $model.settings.verboseLogging)
                    Button("VIEW / SHARE LOG") { model.go(.log) }
                        .buttonStyle(MenuButtonStyle(tint: .gray))
                    Button("RESET PROGRESS") { confirmReset = true }
                        .buttonStyle(MenuButtonStyle(tint: .red))
                    Text(controlsHelp)
                        .font(pixelFont(11)).foregroundColor(.white.opacity(0.6))
                }
                .font(pixelFont(14))
                .tint(Palette.leaf)
                .padding(.horizontal, 60)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog("Erase all rounds, times and lessons?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { model.resetProgress() }
        }
    }

    var controlsHelp: String {
        """
        CONTROLLER: D-pad/stick move - A lift stack - B lift one - X/Y = A+B - Menu pauses.
        KEYBOARD: Arrows/WASD move - X/K = A - Z/J = B - C/L/Space = A+B - Return start - Esc/P pause.
        Down+A or Down+B kicks. Walk into a stack to climb it.
        While carrying: A puts the whole load down in front, B puts down only the bottom piece,
        Up / Down / A+B drop it where you stand and you hop on top.
        What Pip holds above his head is part of the field and counts toward lines.
        """
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var model: AppModel
    @State private var lines: [String] = []

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("< BACK") { model.go(.settings) }
                    .font(pixelFont(15))
                    .foregroundColor(Palette.leaf)
                Spacer()
                Text("\(lines.count) LINES\(model.settings.verboseLogging ? " - VERBOSE" : "")")
                    .font(pixelFont(12)).foregroundColor(.white.opacity(0.6))
                Spacer()
                Button("REFRESH") { reload() }.font(pixelFont(13))
                Button("CLEAR") {
                    GameLog.shared.clear()
                    reload()
                }
                .font(pixelFont(13))
                ShareLink(item: AppLogging.fileURL) {
                    Text("SHARE").font(pixelFont(13))
                }
                .simultaneousGesture(TapGesture().onEnded { AppLogging.flush(force: true) })
            }
            .foregroundColor(Palette.leaf)
            .padding(.horizontal)
            .padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(line.contains(" ERR ") || line.contains(" WRN ") ? .orange : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(.horizontal)
                    .textSelection(.enabled)
                }
                .onAppear {
                    reload()
                    if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private func reload() {
        AppLogging.flush(force: true)
        lines = Array(GameLog.shared.snapshot.suffix(1500))
    }
}

// MARK: - Touch control editor

struct ControlsEditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var layout: ControlLayout = .standard

    var body: some View {
        ZStack {
            TouchControlsEditor(layout: $layout)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text("DRAG CONTROLS TO MOVE THEM")
                    .font(pixelFont(14))
                    .foregroundColor(Palette.leaf)
                HStack {
                    Text("SIZE").frame(width: 70, alignment: .leading)
                    Slider(value: $layout.scale, in: ControlLayout.scaleRange)
                }
                HStack {
                    Text("OPACITY").frame(width: 70, alignment: .leading)
                    Slider(value: $layout.opacity, in: ControlLayout.opacityRange)
                }
                HStack {
                    Button("RESET") { layout = .standard }.buttonStyle(MenuButtonStyle(tint: .gray))
                    Button("DONE") {
                        model.updateLayout(layout)
                        model.go(.settings)
                    }
                    .buttonStyle(MenuButtonStyle())
                }
            }
            .font(pixelFont(12))
            .tint(Palette.leaf)
            .frame(width: 260)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel.opacity(0.9)))
        }
        .onAppear { layout = model.settings.layout(for: model.deviceKey) }
    }
}

struct TouchControlsEditor: UIViewRepresentable {
    @Binding var layout: ControlLayout

    func makeUIView(context: Context) -> TouchControlsView {
        let v = TouchControlsView()
        v.editing = true
        v.layout = layout
        v.onLayoutChange = { newLayout in
            DispatchQueue.main.async { layout = newLayout }
        }
        return v
    }

    func updateUIView(_ v: TouchControlsView, context: Context) {
        if v.layout != layout { v.layout = layout }
    }
}

// MARK: - Game

struct GameContainer: UIViewControllerRepresentable {
    let runner: GameRunner
    let model: AppModel

    func makeUIViewController(context: Context) -> GameViewController {
        let vc = GameViewController(runner: runner)
        model.gameController = vc
        return vc
    }

    func updateUIViewController(_ vc: GameViewController, context: Context) {}
}

struct GameScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var runner: GameRunner

    var body: some View {
        ZStack {
            GameContainer(runner: runner, model: model)
                .ignoresSafeArea()
            if let lesson = runner.session.lesson, runner.outcome == .none {
                // Top-left, beside the playfield and above the D-pad.
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lesson.title.uppercased()).font(pixelFont(13)).foregroundColor(Palette.leaf)
                            Text(lesson.text).font(pixelFont(10)).foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(width: 215, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                        .allowsHitTesting(false)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 6)
                .padding(.leading, 6)
            }
            if runner.paused && runner.outcome == .none {
                PauseOverlay(runner: runner)
            }
            if runner.outcome != .none {
                ResultOverlay(runner: runner)
            }
        }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(18)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.panel.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.leaf, lineWidth: 2))
    }
}

struct PauseOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var runner: GameRunner

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Panel {
                PixelText(text: "PAUSED", color: 0x9CDB_6EFF, scale: 4)
                Button("RESUME") { model.resume() }.buttonStyle(MenuButtonStyle())
                Button("RESTART") { model.restart() }.buttonStyle(MenuButtonStyle(tint: Palette.ember))
                Toggle("MUTE", isOn: $model.settings.muted)
                    .font(pixelFont(14))
                    .tint(Palette.leaf)
                Button("QUIT TO MENU") { model.quitToMenu() }.buttonStyle(MenuButtonStyle(tint: .gray))
            }
        }
    }
}

struct ResultOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var runner: GameRunner

    var title: String {
        switch runner.outcome {
        case .none: return ""
        case .roundWon: return "CLEAR!"
        case .campaignComplete: return "FOREST SAVED!"
        case let .roundLost(reason):
            switch reason {
            case .overflow: return "OVERGROWN"
            case .crushed: return "SQUASHED"
            case .trapped: return "TRAPPED"
            }
        case .trialComplete: return "TRAIL DONE!"
        case .lessonComplete: return "WELL DONE!"
        case let .versusOver(w): return "PLAYER \(w + 1) WINS"
        }
    }

    var detail: String {
        let s = runner.session
        switch runner.outcome {
        case let .trialComplete(ticks):
            return "TIME " + GameScene.clock(ticks) + (runner.newRecord ? "  NEW BEST!" : "")
        case .roundLost where s.kind == .endless:
            return "SCORE \(s.state.score)" + (runner.newRecord ? "  NEW BEST!" : "")
        case .lessonComplete, .versusOver:
            return ""
        default:
            return "SCORE \(s.state.score)   BEST CHAIN X\(max(1, s.state.maxChain))"
        }
    }

    var primary: String? {
        let s = runner.session
        guard s.next != nil else { return nil }
        switch runner.outcome {
        case .roundWon: return s.trail != nil ? "NEXT ROUND" : "NEXT ROUND"
        case .roundLost: return "TRY AGAIN"
        case .trialComplete: return "RUN IT AGAIN"
        case .lessonComplete: return "NEXT LESSON"
        case .versusOver: return "REMATCH"
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            Panel {
                PixelText(text: title, color: 0xFFD8_4AFF, scale: 4)
                if !detail.isEmpty {
                    Text(detail).font(pixelFont(13)).foregroundColor(.white)
                }
                if let primary {
                    Button(primary) { model.continueAfterOutcome() }.buttonStyle(MenuButtonStyle())
                }
                Button("MENU") { model.quitToMenu() }.buttonStyle(MenuButtonStyle(tint: .gray))
            }
        }
    }
}
