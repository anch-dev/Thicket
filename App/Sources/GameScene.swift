import SpriteKit
import ThicketCore
import ThicketKit

private let cell: CGFloat = 16

private func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

private func rect(_ c: UIColor, _ w: CGFloat, _ h: CGFloat, x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0) -> SKSpriteNode {
    let n = SKSpriteNode(color: c, size: CGSize(width: w, height: h))
    n.anchorPoint = .zero
    n.position = CGPoint(x: x, y: y)
    n.zPosition = z
    return n
}

/// Everything drawn for one playfield. Coordinates are art pixels; (0,0) is the
/// bottom-left corner of the field and one cell is 16 px (= `Rules.sub`).
final class BoardView: SKNode {
    let columns: Int
    let rows: Int
    var fieldWidth: CGFloat { CGFloat(columns) * cell }
    var fieldHeight: CGFloat { CGFloat(rows) * cell }

    private var pieceNodes: [Int: SKSpriteNode] = [:]
    private var pieceKeys: [Int: String] = [:]
    private let pip = SKSpriteNode(texture: TextureCache.shared.sprite("pip_idle"))
    private let canopy = SKNode()
    private let actor = SKSpriteNode(texture: TextureCache.shared.sprite("wren_1"))
    private let meterFill: SKSpriteNode
    private let gloomTint: SKSpriteNode
    private let effects = SKNode()
    private var canopyY: CGFloat
    private var actorX: CGFloat = 0
    private var actorTarget: CGFloat = 0
    private var lastSpawnTick = -999

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        canopyY = CGFloat(rows) * cell
        meterFill = rect(color(0xFFD84A), 0, 3)
        gloomTint = rect(color(0x2A1840), CGFloat(columns) * cell, CGFloat(rows) * cell, z: 25)
        super.init()
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        let w = fieldWidth, h = fieldHeight
        let tex = TextureCache.shared
        // Forest backdrop.
        addChild(rect(color(0x1C2B22), w, h, z: 0))
        for (i, x) in stride(from: CGFloat(4), to: w - 8, by: 37).enumerated() {
            for y in stride(from: CGFloat(0), to: h, by: cell) {
                let t = SKSpriteNode(texture: tex.sprite("trunk"))
                t.anchorPoint = .zero
                t.position = CGPoint(x: x + CGFloat(i % 2) * 5, y: y)
                t.alpha = 0.22
                t.zPosition = 1
                addChild(t)
            }
        }
        // Column guides.
        for c in 1..<columns {
            addChild(rect(color(0x24382B), 1, h, x: CGFloat(c) * cell, z: 1))
        }
        // Ground and side walls.
        for x in stride(from: CGFloat(0), to: w, by: cell) {
            let g = SKSpriteNode(texture: tex.sprite("ground"))
            g.anchorPoint = .zero
            g.position = CGPoint(x: x, y: -8)
            g.zPosition = 2
            addChild(g)
        }
        addChild(rect(color(0x3B2616), 4, h + 36, x: -4, y: -8, z: 40))
        addChild(rect(color(0x3B2616), 4, h + 36, x: w, y: -8, z: 40))

        // Canopy: a row of leaves plus dark foliage filling the space above it.
        for x in stride(from: CGFloat(0), to: w, by: cell) {
            let leaf = SKSpriteNode(texture: tex.sprite("canopy"))
            leaf.anchorPoint = .zero
            leaf.position = CGPoint(x: x, y: -3)
            canopy.addChild(leaf)
        }
        canopy.addChild(rect(color(0x173B22), w, h, y: 5))
        canopy.zPosition = 30
        canopy.position = CGPoint(x: 0, y: canopyY)
        addChild(canopy)

        // Sky strip with Wren / the Gloom, and the phase meter.
        addChild(rect(color(0x101A14), w, 28, y: h, z: 31))
        addChild(rect(color(0x2B3A30), w, 3, y: h + 23, z: 32))
        meterFill.position = CGPoint(x: 0, y: h + 23)
        meterFill.zPosition = 33
        addChild(meterFill)
        actor.anchorPoint = .zero
        actor.position = CGPoint(x: 0, y: h + 4)
        actor.zPosition = 34
        addChild(actor)

        gloomTint.alpha = 0
        addChild(gloomTint)
        pip.anchorPoint = CGPoint(x: 0.5, y: 0)
        pip.zPosition = 12
        addChild(pip)
        effects.zPosition = 50
        addChild(effects)
    }

    // MARK: Per-frame sync

    private func spriteKey(_ p: Piece) -> String {
        "\(PixelArt.spriteName(for: p))|\(p.color.rawValue)|\(p.kind == .mite ? p.mite.rawValue : -1)|\(p.shifted)"
    }

    private func node(for p: Piece) -> SKSpriteNode {
        let n: SKSpriteNode
        if let existing = pieceNodes[p.id] {
            n = existing
        } else {
            n = SKSpriteNode()
            n.anchorPoint = .zero
            n.zPosition = 10
            pieceNodes[p.id] = n
            addChild(n)
        }
        let key = spriteKey(p)
        if pieceKeys[p.id] != key {
            pieceKeys[p.id] = key
            n.texture = TextureCache.shared.sprite(PixelArt.spriteName(for: p), color: p.color)
            n.size = CGSize(width: cell, height: cell)
            n.removeAllChildren()
            if p.kind == .mite, let overlay = PixelArt.overlayName(for: p.mite) {
                let o = SKSpriteNode(texture: TextureCache.shared.sprite(overlay))
                o.anchorPoint = .zero
                o.zPosition = 1
                // A Shifter that has already been hit loses its horns' left half: show it dimmed.
                o.alpha = p.mite == .shifter && p.shifted ? 0.45 : 1
                n.addChild(o)
            }
        }
        return n
    }

    func render(_ s: GameState) {
        var seen = Set<Int>()
        let tick = s.tick
        func show(_ p: Piece, _ x: CGFloat, _ y: CGFloat, z: CGFloat = 10) {
            let n = node(for: p)
            n.position = CGPoint(x: x.rounded(), y: y.rounded())
            n.zPosition = z
            n.alpha = p.isFlashing ? ((tick / 4) % 2 == 0 ? 1 : 0.3) : 1
            seen.insert(p.id)
        }
        for c in 0..<min(columns, s.board.width) {
            for (r, p) in s.board.columns[c].enumerated() {
                show(p, CGFloat(c) * cell, CGFloat(r) * cell)
            }
        }
        for f in s.fallers {
            var x = CGFloat(f.column)
            if f.origin == .kicked, let from = f.slideFrom, f.hang > 0 {
                let total = CGFloat(abs(f.column - from) * Rules.kickSlideTicksPerCell)
                let progress = total > 0 ? 1 - CGFloat(f.hang) / total : 1
                x = CGFloat(from) + CGFloat(f.column - from) * progress
            }
            show(f.piece, x * cell, CGFloat(f.y))
        }

        // Pip (interpolated through his current motion).
        let t = CGFloat(s.pip.motionProgress)
        let px = (CGFloat(s.pip.fromColumn) + CGFloat(s.pip.column - s.pip.fromColumn) * t) * cell
        let py = (CGFloat(s.pip.fromRow) + CGFloat(s.pip.row - s.pip.fromRow) * t) * cell
        pip.position = CGPoint(x: px.rounded() + cell / 2, y: py.rounded())
        pip.xScale = s.pip.facing == .left ? -1 : 1
        let name: String
        if case .lost = s.status {
            name = "pip_hurt"
        } else if s.pip.isCarrying {
            name = "pip_lift"
        } else if s.pip.clinging || s.pip.motion == .climb {
            name = "pip_climb"
        } else if s.pip.motion == .walk || s.pip.motion == .fall {
            name = (tick / 4) % 2 == 0 ? "pip_walk" : "pip_idle"
        } else {
            name = "pip_idle"
        }
        pip.texture = TextureCache.shared.sprite(name)
        for (i, p) in s.pip.carried.enumerated() {
            show(p, px, py + CGFloat(i + 1) * cell, z: 13)
        }

        for (id, n) in pieceNodes where !seen.contains(id) {
            n.removeFromParent()
            pieceNodes[id] = nil
            pieceKeys[id] = nil
        }

        // Canopy eases toward its row so a slam is visible.
        let target = CGFloat(s.board.ceiling) * cell
        if canopyY > target {
            canopyY = max(target, canopyY - 4)
        } else if canopyY < target {
            canopyY = min(target, canopyY + 1)
        }
        canopy.position.y = canopyY

        // Wren or the Gloom.
        let gloom = s.phase.kind == .gloom
        let actorWidth: CGFloat = gloom ? 32 : 16
        actor.texture = TextureCache.shared.sprite(gloom ? ((tick / 20) % 2 == 0 ? "gloom_1" : "gloom_2")
                                                        : ((tick / 8) % 2 == 0 ? "wren_1" : "wren_2"))
        actor.size = CGSize(width: actorWidth, height: 16)
        if tick - lastSpawnTick > 40 {
            let wander = (sin(Double(tick) / 70) + 1) / 2
            actorTarget = CGFloat(wander) * (fieldWidth - actorWidth)
        }
        actorTarget = min(max(0, actorTarget), fieldWidth - actorWidth)
        actorX += (actorTarget - actorX) * 0.2
        actor.position.x = actorX.rounded()
        actor.xScale = 1
        actor.isHidden = !s.config.phasesEnabled

        meterFill.size = CGSize(width: (fieldWidth * CGFloat(s.phase.meter)).rounded(), height: 3)
        meterFill.color = gloom ? color(0x9C6ADE) : color(0xFFD84A)
        meterFill.isHidden = !s.config.phasesEnabled
        gloomTint.alpha += ((gloom ? 0.22 : 0) - gloomTint.alpha) * 0.1
    }

    // MARK: Effects

    func apply(_ events: [GameEvent], state s: GameState) {
        for e in events {
            switch e {
            case let .cleared(cells, pieces, _, score):
                for (cellPos, p) in zip(cells, pieces) {
                    pop(p, at: cellPos)
                }
                if let first = cells.first, score > 0 {
                    floatText("+\(score)", at: CGPoint(x: CGFloat(first.col) * cell + 8, y: CGFloat(first.row) * cell + 12),
                              color: 0xFFFFFFFF)
                }
            case let .chain(level):
                banner("CHAIN X\(level)", color: 0xFFD84AFF)
            case let .hit(c):
                flash(at: c, color: 0xFFFFFF)
            case let .starseedCreated(c, _):
                flash(at: c, color: 0xFFD84A)
                banner("STARSEED!", color: 0xA8DBFFFF)
            case let .starseedBurst(pc):
                let main = SpriteData.pieceColors[PixelArt.colorName(pc)]?["1"] ?? 0xFFFFFFFF
                let f = rect(color(main >> 8), fieldWidth, fieldHeight, z: 45)
                f.alpha = 0.5
                effects.addChild(f)
                f.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            case let .spawned(column, _):
                lastSpawnTick = s.tick
                let w: CGFloat = s.phase.kind == .gloom ? 32 : 16
                actorTarget = CGFloat(column) * cell + 8 - w / 2
            case .phaseChanged(.gloom):
                banner("THE GLOOM!", color: 0xC9A8FFFF)
            case .phaseChanged(.wren):
                banner("WREN!", color: 0xFFD84AFF)
            case .roundCleared:
                banner("CLEAR!", color: 0x9CDB6EFF)
            case let .gameOver(reason):
                switch reason {
                case .overflow: banner("OVERGROWN", color: 0xE04A4AFF)
                case .crushed: banner("SQUASHED", color: 0xE04A4AFF)
                case .trapped: banner("TRAPPED", color: 0xE04A4AFF)
                }
            default:
                break
            }
        }
    }

    private func pop(_ p: Piece, at c: Cell) {
        let n = SKSpriteNode(texture: TextureCache.shared.sprite(PixelArt.spriteName(for: p), color: p.color, tint: 0xFFFFFFFF))
        n.position = CGPoint(x: CGFloat(c.col) * cell + 8, y: CGFloat(c.row) * cell + 8)
        effects.addChild(n)
        n.run(.sequence([.group([.scale(to: 1.6, duration: 0.22), .fadeOut(withDuration: 0.22)]), .removeFromParent()]))
        // Four little sparks.
        for (dx, dy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(CGFloat, CGFloat)] {
            let s = rect(color(0xFFF2B0), 2, 2)
            s.position = n.position
            effects.addChild(s)
            s.run(.sequence([.group([.moveBy(x: dx * 12, y: dy * 12, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                             .removeFromParent()]))
        }
    }

    private func flash(at c: Cell, color rgb: UInt32) {
        let f = rect(color(rgb), cell, cell, x: CGFloat(c.col) * cell, y: CGFloat(c.row) * cell)
        f.alpha = 0.8
        effects.addChild(f)
        f.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    private func floatText(_ text: String, at p: CGPoint, color rgb: UInt32) {
        let n = SKSpriteNode(texture: TextureCache.shared.text(text, color: rgb))
        n.position = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        effects.addChild(n)
        n.run(.sequence([.moveBy(x: 0, y: 14, duration: 0.6), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    private func banner(_ text: String, color rgb: UInt32) {
        let n = SKSpriteNode(texture: TextureCache.shared.text(text, color: rgb))
        let back = rect(color(0x101A14, 0.8), n.size.width + 6, n.size.height + 4,
                        x: -n.size.width / 2 - 3, y: -n.size.height / 2 - 2, z: -1)
        n.addChild(back)
        n.position = CGPoint(x: (fieldWidth / 2).rounded(), y: (fieldHeight * 0.6).rounded())
        n.setScale(1)
        effects.addChild(n)
        n.run(.sequence([.wait(forDuration: 0.7), .group([.moveBy(x: 0, y: 10, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                         .removeFromParent()]))
    }
}

/// The game scene: one or two boards plus HUD, drawn into an integer-scaled
/// "world" so every art pixel covers a whole number of device pixels.
final class GameScene: SKScene {
    private let world = SKNode()
    private(set) var boards: [BoardView] = []
    private var hud: [String: SKSpriteNode] = [:]
    private var hudText: [String: String] = [:]
    private var artSize = CGSize(width: 1, height: 1)
    private var players = 1
    private var shakeTicks = 0
    private var basePosition = CGPoint.zero
    private(set) var pixelScale: CGFloat = 1

    static let panelWidth: CGFloat = 40

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = color(0x0C140F)
        scaleMode = .resizeFill
        anchorPoint = .zero
        addChild(world)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(columns: Int, rows: Int, players: Int) {
        self.players = players
        boards.forEach { $0.removeFromParent() }
        boards = (0..<players).map { _ in BoardView(columns: columns, rows: rows) }
        let boardBox = CGFloat(columns) * cell + 8
        let fieldH = CGFloat(rows) * cell
        if players == 1 {
            boards[0].position = CGPoint(x: Self.panelWidth + 4 + 4, y: 8)
            artSize = CGSize(width: Self.panelWidth * 2 + 8 + boardBox, height: fieldH + 8 + 28 + 2)
        } else {
            for (i, b) in boards.enumerated() {
                b.position = CGPoint(x: 4 + CGFloat(i) * (boardBox + 24), y: 8)
            }
            artSize = CGSize(width: boardBox * 2 + 24, height: fieldH + 8 + 28 + 12)
        }
        boards.forEach(world.addChild)
    }

    /// Picks the largest whole-number pixel scale that fits the safe area.
    func layout(safeInsets: UIEdgeInsets, screenScale: CGFloat) {
        let safe = CGRect(x: safeInsets.left, y: safeInsets.bottom,
                          width: size.width - safeInsets.left - safeInsets.right,
                          height: size.height - safeInsets.top - safeInsets.bottom)
        let px = max(1, floor(min(safe.width * screenScale / artSize.width, safe.height * screenScale / artSize.height)))
        pixelScale = px
        let s = px / screenScale
        world.setScale(s)
        let x = safe.midX - artSize.width * s / 2
        let y = safe.midY - artSize.height * s / 2
        basePosition = CGPoint(x: (x * screenScale).rounded() / screenScale, y: (y * screenScale).rounded() / screenScale)
        world.position = basePosition
    }

    private func setHUD(_ key: String, _ text: String, x: CGFloat, y: CGFloat, color rgb: UInt32 = 0xFFFFFFFF) {
        let node: SKSpriteNode
        if let n = hud[key] {
            node = n
        } else {
            node = SKSpriteNode()
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.zPosition = 60
            world.addChild(node)
            hud[key] = node
        }
        node.position = CGPoint(x: x, y: y)
        if hudText[key] != text {
            hudText[key] = text
            let t = TextureCache.shared.text(text, color: rgb)
            node.texture = t
            node.size = t.size()
        }
    }

    static func clock(_ ticks: Int) -> String {
        let secs = ticks / Rules.ticksPerSecond
        return String(format: "%02d:%02d", min(99, secs / 60), secs % 60)
    }

    func render(_ session: SessionModel) {
        if let v = session.versus {
            for (i, b) in boards.enumerated() where i < v.players.count {
                b.render(v.players[i])
                let top = artSize.height - 1
                let x = b.position.x
                setHUD("p\(i)", "P\(i + 1)", x: x, y: top, color: i == 0 ? 0xFFD84AFF : 0xA8DBFFFF)
                setHUD("s\(i)", String(v.players[i].score), x: x + 16, y: top)
            }
        } else if let b = boards.first {
            let s = session.state
            b.render(s)
            let top = artSize.height - 4
            let rightX = b.position.x + b.fieldWidth + 8
            let label: UInt32 = 0x9CDB6EFF
            // Two short lines so the text always fits the 40 px side panel.
            let title: (String, String)
            switch session.kind {
            case let .campaign(round): title = ("ROUND", String(round))
            case .endless: title = ("MODE", "ENDLS")
            case let .timeTrial(_, i, _): title = ("TRIAL", "\(i + 1)/\(session.trail?.rounds.count ?? 0)")
            case .lesson: title = ("", "")
            case .versus: title = ("VS", "")
            }
            // Lessons show their instructions on the left instead of the score panel.
            if session.lesson == nil {
                setHUD("titleL", title.0, x: 0, y: top, color: label)
                setHUD("title", title.1, x: 0, y: top - 9)
                setHUD("scoreL", "SCORE", x: 0, y: top - 23, color: label)
                setHUD("score", String(s.score), x: 0, y: top - 32)
                setHUD("mitesL", "MITES", x: 0, y: top - 46, color: label)
                setHUD("mites", String(s.mitesRemaining), x: 0, y: top - 55)
            }
            setHUD("timeL", "TIME", x: rightX, y: top, color: label)
            setHUD("time", Self.clock(session.trialTicks), x: rightX, y: top - 9)
            setHUD("chainL", "CHAIN", x: rightX, y: top - 23, color: label)
            setHUD("chain", "X\(max(1, s.maxChain))", x: rightX, y: top - 32)
            if s.config.endless && s.config.phasesEnabled {
                setHUD("levelL", "LEVEL", x: rightX, y: top - 46, color: label)
                setHUD("level", String(s.endlessLevel + 1), x: rightX, y: top - 55)
            }
        }
        if shakeTicks > 0 {
            shakeTicks -= 1
            let dx: CGFloat = shakeTicks % 2 == 0 ? 1 : -1
            world.position = CGPoint(x: basePosition.x + dx * world.xScale, y: basePosition.y)
        } else {
            world.position = basePosition
        }
    }

    func apply(_ events: [[GameEvent]], session: SessionModel) {
        for (i, ev) in events.enumerated() where i < boards.count {
            let state = session.versus?.players[i] ?? session.state
            boards[i].apply(ev, state: state)
            if ev.contains(where: { if case .canopySlam = $0 { return true } else { return false } }) {
                shakeTicks = 8
            }
        }
    }
}
