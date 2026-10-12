import SceneKit
import ThicketCore
import ThicketKit
import UIKit

// A 3D rendering of the same simulation, built entirely from procedural
// SceneKit geometry (no imported assets). One cell = 1 unit; the board stands
// in the x/y plane facing the camera, z points toward the viewer.

private func rgb(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

private func material(_ color: UIColor, emission: UIColor? = nil, shiny: Bool = true) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = color
    m.specular.contents = shiny ? UIColor(white: 0.45, alpha: 1) : UIColor.black
    m.shininess = 0.35
    if let emission { m.emission.contents = emission }
    return m
}

private func node(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3 = SCNVector3Zero) -> SCNNode {
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = p
    return n
}

enum Palette3D {
    static func main(_ c: PieceColor) -> UIColor {
        rgb((SpriteData.pieceColors[PixelArt.colorName(c)]?["1"] ?? 0xFFFFFFFF) >> 8)
    }

    static let white = material(.white, emission: UIColor(white: 0.25, alpha: 1))
    static let black = material(rgb(0x1B1A2E), shiny: true)
    static let brown = material(rgb(0x8A5A34), shiny: false)
    static let darkBrown = material(rgb(0x5A3722), shiny: false)
    static let leaf = material(rgb(0x4CA84C), shiny: false)
    static let darkLeaf = material(rgb(0x2D6B3A), shiny: false)
    static let skin = material(rgb(0xF6CFA8))
    static let yellow = material(rgb(0xFFD84A), emission: rgb(0x7A5A00))
}

/// Builds (and caches) the piece models; the scene uses clones.
final class PieceModels {
    private var cache: [String: SCNNode] = [:]
    private var bodyMaterials: [PieceColor: SCNMaterial] = [:]

    func body(_ c: PieceColor) -> SCNMaterial {
        if let m = bodyMaterials[c] { return m }
        let m = material(Palette3D.main(c))
        bodyMaterials[c] = m
        return m
    }

    static func key(_ p: Piece) -> String {
        "\(p.kind.rawValue)|\(p.color.rawValue)|\(p.kind == .mite ? p.mite.rawValue : -1)|\(p.shifted)"
    }

    func make(_ p: Piece) -> SCNNode {
        let k = Self.key(p)
        if cache[k] == nil { cache[k] = build(p) }
        return cache[k]!.clone()
    }

    private func build(_ p: Piece) -> SCNNode {
        let root = SCNNode()
        switch p.kind {
        case .mite: buildMite(p, into: root)
        case .seed: buildSeed(p.color, into: root)
        case .starseed: buildStar(p.color, into: root)
        }
        return root
    }

    private func eyes(_ root: SCNNode, y: Float, z: Float, spread: Float = 0.15) {
        for sx in [-spread, spread] {
            root.addChildNode(node(SCNSphere(radius: 0.1), Palette3D.white, SCNVector3(sx, y, z)))
            root.addChildNode(node(SCNSphere(radius: 0.05), Palette3D.black, SCNVector3(sx, y, z + 0.08)))
        }
    }

    private func buildMite(_ p: Piece, into root: SCNNode) {
        let m = body(p.color)
        var front: Float = 0.36
        switch p.color {
        case .ember: // round
            let s = SCNSphere(radius: 0.4)
            s.segmentCount = 28
            root.addChildNode(node(s, m))
            eyes(root, y: 0.08, z: 0.31)
        case .tide: // pointed drop
            let s = SCNSphere(radius: 0.36)
            s.segmentCount = 28
            root.addChildNode(node(s, m, SCNVector3(0, -0.08, 0)))
            root.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.33, height: 0.42), m, SCNVector3(0, 0.25, 0)))
            eyes(root, y: 0.0, z: 0.27)
            front = 0.33
        case .bloom: // blocky with ears
            root.addChildNode(node(SCNBox(width: 0.78, height: 0.72, length: 0.7, chamferRadius: 0.16), m))
            for sx: Float in [-0.25, 0.25] {
                root.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.18), m, SCNVector3(sx, 0.43, 0)))
            }
            eyes(root, y: 0.07, z: 0.3)
        }
        root.addChildNode(node(SCNBox(width: 0.18, height: 0.035, length: 0.03, chamferRadius: 0.01),
                               Palette3D.black, SCNVector3(0, -0.13, front)))
        switch p.mite {
        case .common:
            break
        case .slant: // diagonal stripes across the belly
            for sx: Float in [-0.14, 0.06] {
                let stripe = node(SCNBox(width: 0.05, height: 0.32, length: 0.03, chamferRadius: 0.01),
                                  Palette3D.white, SCNVector3(sx, -0.1, front + 0.02))
                stripe.eulerAngles.z = -.pi / 4
                root.addChildNode(stripe)
            }
        case .shifter: // two horns (grey once already hit)
            let horn = p.shifted ? material(.gray) : Palette3D.white
            for sx: Float in [-0.22, 0.22] {
                let h = node(SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.24), horn, SCNVector3(sx, 0.45, 0))
                h.eulerAngles.z = sx > 0 ? -0.5 : 0.5
                root.addChildNode(h)
            }
        case .flicker: // glowing antenna
            root.addChildNode(node(SCNCylinder(radius: 0.02, height: 0.26), Palette3D.black, SCNVector3(0, 0.5, 0)))
            root.addChildNode(node(SCNSphere(radius: 0.08), Palette3D.yellow, SCNVector3(0, 0.66, 0)))
        }
    }

    private func buildSeed(_ c: PieceColor, into root: SCNNode) {
        let s = SCNSphere(radius: 0.34)
        s.segmentCount = 28
        let bodyNode = node(s, body(c), SCNVector3(0, -0.07, 0))
        bodyNode.scale = SCNVector3(1, 1.06, 1)
        root.addChildNode(bodyNode)
        root.addChildNode(node(SCNCylinder(radius: 0.37, height: 0.16), Palette3D.brown, SCNVector3(0, 0.22, 0)))
        let top = node(SCNSphere(radius: 0.3), Palette3D.brown, SCNVector3(0, 0.27, 0))
        top.scale = SCNVector3(1, 0.4, 1)
        root.addChildNode(top)
        root.addChildNode(node(SCNCylinder(radius: 0.035, height: 0.14), Palette3D.darkBrown, SCNVector3(0, 0.4, 0)))
        // Emblem: circle / triangle / square, so colors are never the only cue.
        let emblem: SCNNode
        switch c {
        case .ember:
            emblem = node(SCNCylinder(radius: 0.12, height: 0.04), Palette3D.white)
            emblem.eulerAngles.x = .pi / 2
        case .tide:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 0.14))
            path.addLine(to: CGPoint(x: 0.14, y: -0.1))
            path.addLine(to: CGPoint(x: -0.14, y: -0.1))
            path.close()
            emblem = node(SCNShape(path: path, extrusionDepth: 0.04), Palette3D.white)
        case .bloom:
            emblem = node(SCNBox(width: 0.22, height: 0.22, length: 0.04, chamferRadius: 0.01), Palette3D.white)
        }
        emblem.position = SCNVector3(0, -0.07, 0.33)
        root.addChildNode(emblem)
    }

    private func buildStar(_ c: PieceColor, into root: SCNNode) {
        let path = UIBezierPath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 0.46 : 0.2
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.22)
        shape.chamferRadius = 0.03
        let star = node(shape, material(Palette3D.main(c), emission: Palette3D.main(c).withAlphaComponent(0.6)))
        star.name = "spin"
        root.addChildNode(star)
        star.addChildNode(node(SCNSphere(radius: 0.08), Palette3D.white, SCNVector3(0, 0, 0.12)))
    }

    // MARK: Characters

    static func pip() -> SCNNode {
        let root = SCNNode()
        let body = SCNNode()
        body.name = "body"
        root.addChildNode(body)
        body.addChildNode(node(SCNCapsule(capRadius: 0.2, height: 0.52), Palette3D.leaf, SCNVector3(0, 0.3, 0)))
        body.addChildNode(node(SCNSphere(radius: 0.2), Palette3D.skin, SCNVector3(0, 0.66, 0)))
        body.addChildNode(node(SCNCylinder(radius: 0.3, height: 0.04), Palette3D.darkLeaf, SCNVector3(0, 0.79, 0)))
        body.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.32), Palette3D.leaf, SCNVector3(0, 0.96, 0)))
        for sx: Float in [-0.075, 0.075] {
            body.addChildNode(node(SCNSphere(radius: 0.035), Palette3D.black, SCNVector3(sx, 0.69, 0.18)))
            body.addChildNode(node(SCNSphere(radius: 0.09), Palette3D.darkBrown, SCNVector3(sx * 1.4, 0.06, 0.03)))
        }
        for (i, sx) in [Float(-0.26), 0.26].enumerated() {
            let arm = node(SCNSphere(radius: 0.075), Palette3D.skin, SCNVector3(sx, 0.4, 0.02))
            arm.name = i == 0 ? "armL" : "armR"
            body.addChildNode(arm)
        }
        return root
    }

    static func wren() -> SCNNode {
        let root = SCNNode()
        let b = node(SCNSphere(radius: 0.22), Palette3D.brown)
        b.scale = SCNVector3(1.25, 1, 1)
        root.addChildNode(b)
        root.addChildNode(node(SCNSphere(radius: 0.12), material(rgb(0xFFD84A)), SCNVector3(0.05, -0.08, 0.12)))
        root.addChildNode(node(SCNSphere(radius: 0.15), Palette3D.brown, SCNVector3(0.22, 0.16, 0)))
        let beak = node(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.15), material(rgb(0xFFB020)), SCNVector3(0.4, 0.16, 0))
        beak.eulerAngles.z = -.pi / 2
        root.addChildNode(beak)
        root.addChildNode(node(SCNSphere(radius: 0.03), Palette3D.black, SCNVector3(0.3, 0.2, 0.11)))
        let tail = node(SCNBox(width: 0.24, height: 0.06, length: 0.14, chamferRadius: 0.03), Palette3D.darkBrown, SCNVector3(-0.3, 0.12, 0))
        tail.eulerAngles.z = 0.6
        root.addChildNode(tail)
        for (i, z) in [Float(0.17), -0.17].enumerated() {
            let w = node(SCNSphere(radius: 0.18), Palette3D.darkBrown, SCNVector3(-0.02, 0.1, z))
            w.scale = SCNVector3(1, 0.3, 0.8)
            w.name = i == 0 ? "wingF" : "wingB"
            root.addChildNode(w)
        }
        return root
    }

    static func gloom() -> SCNNode {
        let root = SCNNode()
        let cloud = material(rgb(0x8E92A8), shiny: false)
        let dark = material(rgb(0x5E6078), shiny: false)
        for (x, y, r) in [(-0.55, 0.0, 0.35), (-0.2, 0.15, 0.45), (0.25, 0.12, 0.42), (0.6, -0.02, 0.32)] as [(Float, Float, CGFloat)] {
            root.addChildNode(node(SCNSphere(radius: r), cloud, SCNVector3(x, y, 0)))
        }
        let under = node(SCNSphere(radius: 0.4), dark, SCNVector3(0, -0.15, 0))
        under.scale = SCNVector3(2.4, 0.6, 1)
        root.addChildNode(under)
        let eye = material(rgb(0xE04A4A), emission: rgb(0xC02020))
        for sx: Float in [-0.2, 0.2] {
            root.addChildNode(node(SCNSphere(radius: 0.07), eye, SCNVector3(sx, 0.05, 0.42)))
            let brow = node(SCNBox(width: 0.18, height: 0.04, length: 0.03, chamferRadius: 0), Palette3D.black, SCNVector3(sx, 0.16, 0.44))
            brow.eulerAngles.z = sx < 0 ? -0.4 : 0.4
            root.addChildNode(brow)
        }
        let bolt = node(SCNBox(width: 0.06, height: 0.6, length: 0.06, chamferRadius: 0), Palette3D.yellow, SCNVector3(0.1, -0.55, 0.2))
        bolt.eulerAngles.z = 0.3
        bolt.name = "bolt"
        bolt.isHidden = true
        root.addChildNode(bolt)
        return root
    }
}

/// One playfield in 3D.
final class Board3D {
    let root = SCNNode()
    let columns: Int
    let rows: Int
    private let models: PieceModels
    private var pieces: [Int: SCNNode] = [:]
    private var keys: [Int: String] = [:]
    private var markers: [Int: SCNNode] = [:]
    private let pip = PieceModels.pip()
    private let wren = PieceModels.wren()
    private let gloom = PieceModels.gloom()
    private let canopy = SCNNode()
    private let canopyFill = SCNNode()
    private let meterFill: SCNNode
    private let effects = SCNNode()
    private var canopyY: Float
    private var actorX: Float = 0
    private var actorTarget: Float = 0
    private var lastSpawnTick = -999
    private let markerMaterial = material(UIColor(white: 1, alpha: 0.35), shiny: false)

    init(columns: Int, rows: Int, models: PieceModels) {
        self.columns = columns
        self.rows = rows
        self.models = models
        canopyY = Float(rows)
        meterFill = node(SCNBox(width: 1, height: 0.14, length: 0.1, chamferRadius: 0.03),
                         material(rgb(0xFFD84A), emission: rgb(0x403000)))
        build()
    }

    func x(_ c: Double) -> Float { Float(c + 0.5 - Double(columns) / 2) }

    private func build() {
        let w = CGFloat(columns), h = CGFloat(rows)
        // Back panel and column guides.
        root.addChildNode(node(SCNBox(width: w, height: h, length: 0.1, chamferRadius: 0),
                               material(rgb(0x1E3326), shiny: false), SCNVector3(0, Float(h) / 2, -0.6)))
        let guide = material(rgb(0x2A4433), shiny: false)
        for c in 1..<columns {
            root.addChildNode(node(SCNBox(width: 0.03, height: h, length: 0.02, chamferRadius: 0), guide,
                                   SCNVector3(Float(c) - Float(w) / 2, Float(h) / 2, -0.54)))
        }
        // Ground: grass on soil.
        root.addChildNode(node(SCNBox(width: w + 0.7, height: 0.2, length: 1.8, chamferRadius: 0.05),
                               Palette3D.leaf, SCNVector3(0, -0.1, 0)))
        root.addChildNode(node(SCNBox(width: w + 0.7, height: 0.6, length: 1.7, chamferRadius: 0.05),
                               Palette3D.brown, SCNVector3(0, -0.5, 0)))
        // Side posts.
        for sx in [-1, 1] as [Float] {
            root.addChildNode(node(SCNBox(width: 0.28, height: h + 2.2, length: 1.2, chamferRadius: 0.08),
                                   Palette3D.darkBrown, SCNVector3(sx * (Float(w) / 2 + 0.14), Float(h + 2.2) / 2 - 0.4, 0)))
        }
        // Canopy: a row of leaf clusters with dense foliage above.
        let leafMaterials = [Palette3D.leaf, Palette3D.darkLeaf]
        var i = 0
        for cx in stride(from: -Float(w) / 2 + 0.3, through: Float(w) / 2 - 0.3, by: 0.62) {
            let s = SCNSphere(radius: 0.48)
            s.segmentCount = 16
            canopy.addChildNode(node(s, leafMaterials[i % 2], SCNVector3(cx, 0.42 + (i % 2 == 0 ? 0 : 0.08), 0.05)))
            i += 1
        }
        canopyFill.geometry = SCNBox(width: w, height: 1, length: 1.1, chamferRadius: 0)
        canopyFill.geometry?.materials = [material(rgb(0x173B22), shiny: false)]
        canopy.addChildNode(canopyFill)
        root.addChildNode(canopy)

        // Sky actors and the phase meter.
        root.addChildNode(wren)
        root.addChildNode(gloom)
        root.addChildNode(node(SCNBox(width: w, height: 0.14, length: 0.08, chamferRadius: 0.03),
                               material(rgb(0x2B3A30), shiny: false), SCNVector3(0, Float(h) + 1.55, 0)))
        root.addChildNode(meterFill)

        root.addChildNode(pip)
        root.addChildNode(effects)
    }

    // MARK: Per-frame sync

    private func pieceNode(_ p: Piece) -> SCNNode {
        let k = PieceModels.key(p)
        if let n = pieces[p.id], keys[p.id] == k { return n }
        pieces[p.id]?.removeFromParentNode()
        let n = models.make(p)
        n.scale = SCNVector3(0.92, 0.92, 0.92)
        root.addChildNode(n)
        pieces[p.id] = n
        keys[p.id] = k
        return n
    }

    func render(_ s: GameState) {
        let tick = s.tick
        var seen = Set<Int>()
        func show(_ p: Piece, _ cx: Double, _ cy: Double) {
            let n = pieceNode(p)
            n.position = SCNVector3(x(cx), Float(cy) + 0.5, 0)
            n.opacity = p.isFlashing ? ((tick / 4) % 2 == 0 ? 1 : 0.3) : 1
            if p.kind == .starseed { n.childNode(withName: "spin", recursively: true)?.eulerAngles.y = Float(tick) * 0.05 }
            seen.insert(p.id)
        }
        for c in 0..<min(columns, s.board.width) {
            for (r, p) in s.board.columns[c].enumerated() { show(p, Double(c), Double(r)) }
        }
        var markerSeen = Set<Int>()
        for f in s.fallers {
            var cx = Double(f.column)
            if f.origin == .kicked, let from = f.slideFrom, f.hang > 0 {
                let total = Double(abs(f.column - from) * Rules.kickSlideTicksPerCell)
                let progress = total > 0 ? 1 - Double(f.hang) / total : 1
                cx = Double(from) + Double(f.column - from) * progress
            }
            show(f.piece, cx, Double(f.y) / Double(Rules.sub))
            if f.origin == .spawn {
                // Landing marker where the dropped piece will come down.
                let m: SCNNode
                if let existing = markers[f.piece.id] {
                    m = existing
                } else {
                    m = node(SCNCylinder(radius: 0.36, height: 0.02), markerMaterial)
                    root.addChildNode(m)
                    markers[f.piece.id] = m
                }
                var landing = Double(s.board.height(f.column))
                if s.pip.column == f.column && s.pip.row >= s.board.height(f.column) {
                    landing = Double(s.pip.row + 1 + s.pip.carried.count)
                }
                m.position = SCNVector3(x(Double(f.column)), Float(landing) + 0.02, 0)
                markerSeen.insert(f.piece.id)
            }
        }
        for (id, m) in markers where !markerSeen.contains(id) {
            m.removeFromParentNode()
            markers[id] = nil
        }

        // Pip.
        let t = s.pip.motionProgress
        let pc = Double(s.pip.fromColumn) + Double(s.pip.column - s.pip.fromColumn) * t
        let pr = Double(s.pip.fromRow) + Double(s.pip.row - s.pip.fromRow) * t
        let walking = s.pip.motion == .walk
        pip.position = SCNVector3(x(pc), Float(pr) + (walking ? Float(abs(sin(Double(tick) * 0.7))) * 0.07 : 0), 0.05)
        pip.eulerAngles.y = s.pip.facing == .right ? 0.65 : -0.65
        let body = pip.childNode(withName: "body", recursively: false)
        if case .lost = s.status { body?.eulerAngles.z = .pi / 2 } else { body?.eulerAngles.z = s.pip.clinging ? (s.pip.facing == .right ? -0.15 : 0.15) : 0 }
        let armsUp = s.pip.isCarrying || s.pip.clinging || s.pip.motion == .climb
        for (name, sx) in [("armL", Float(-1)), ("armR", Float(1))] {
            pip.childNode(withName: name, recursively: true)?.position = armsUp ? SCNVector3(sx * 0.18, 0.95, 0.02)
                : SCNVector3(sx * 0.26, 0.4, 0.02)
        }
        for (i, p) in s.pip.carried.enumerated() { show(p, pc, pr + Double(i + 1)) }

        for (id, n) in pieces where !seen.contains(id) {
            n.removeFromParentNode()
            pieces[id] = nil
            keys[id] = nil
        }

        // Canopy eases toward its row so a slam is visible.
        let target = Float(s.board.ceiling)
        canopyY = canopyY > target ? max(target, canopyY - 0.25) : min(target, canopyY + 0.06)
        canopy.position = SCNVector3(0, canopyY, 0)
        let fillHeight = max(0.05, Float(rows) - canopyY + 0.4)
        canopyFill.scale = SCNVector3(1, fillHeight, 1)
        canopyFill.position = SCNVector3(0, 0.5 + fillHeight / 2, -0.1)

        // Wren / the Gloom.
        let gloomOn = s.phase.kind == .gloom
        wren.isHidden = gloomOn || !s.config.phasesEnabled
        gloom.isHidden = !gloomOn || !s.config.phasesEnabled
        if tick - lastSpawnTick > 40 {
            let wander = (sin(Double(tick) / 70) + 1) / 2
            actorTarget = x(wander * Double(columns - 1))
        }
        actorX += (actorTarget - actorX) * 0.15
        let flap = Float(sin(Double(tick) * 0.5)) * 0.8
        wren.position = SCNVector3(actorX, Float(rows) + 0.75 + Float(sin(Double(tick) * 0.12)) * 0.08, 0.6)
        wren.childNode(withName: "wingF", recursively: false)?.eulerAngles.x = flap
        wren.childNode(withName: "wingB", recursively: false)?.eulerAngles.x = -flap
        gloom.position = SCNVector3(actorX, Float(rows) + 0.8, 0.6)
        gloom.childNode(withName: "bolt", recursively: false)?.isHidden = (tick / 6) % 9 != 0

        let meter = Float(s.phase.meter)
        meterFill.scale = SCNVector3(max(0.001, Float(columns) * meter), 1, 1)
        meterFill.position = SCNVector3(-Float(columns) / 2 + Float(columns) * meter / 2, Float(rows) + 1.55, 0.04)
        meterFill.geometry?.firstMaterial?.diffuse.contents = gloomOn ? rgb(0x9C6ADE) : rgb(0xFFD84A)
        meterFill.isHidden = !s.config.phasesEnabled
    }

    // MARK: Effects

    func apply(_ events: [GameEvent], state s: GameState) {
        for e in events {
            switch e {
            case let .cleared(cells, removed, _, _):
                for (c, p) in zip(cells, removed) { pop(p, at: c) }
            case let .hit(c):
                burst(at: SCNVector3(x(Double(c.col)), Float(c.row) + 0.5, 0.3), color: .white, count: 40)
            case let .starseedCreated(c, color):
                burst(at: SCNVector3(x(Double(c.col)), Float(c.row) + 0.5, 0.3), color: Palette3D.main(color), count: 120)
            case let .spawned(column, _):
                lastSpawnTick = s.tick
                actorTarget = x(Double(column))
            default:
                break
            }
        }
    }

    private func pop(_ p: Piece, at c: Cell) {
        let n = models.make(p)
        n.position = SCNVector3(x(Double(c.col)), Float(c.row) + 0.5, 0)
        n.scale = SCNVector3(0.92, 0.92, 0.92)
        effects.addChildNode(n)
        n.runAction(.sequence([.group([.scale(to: 1.5, duration: 0.22), .fadeOut(duration: 0.22)]), .removeFromParentNode()]))
        burst(at: n.position, color: p.kind == .mite ? Palette3D.main(p.color) : .white, count: 60)
    }

    private func burst(at position: SCNVector3, color: UIColor, count: CGFloat) {
        let ps = SCNParticleSystem()
        ps.loops = false
        ps.birthRate = count / 0.05
        ps.emissionDuration = 0.05
        ps.particleLifeSpan = 0.45
        ps.particleLifeSpanVariation = 0.15
        ps.particleVelocity = 3
        ps.particleVelocityVariation = 1.5
        ps.spreadingAngle = 180
        ps.particleSize = 0.06
        ps.particleColor = color
        ps.acceleration = SCNVector3(0, -6, 0)
        ps.blendMode = .additive
        ps.isAffectedByGravity = false
        let holder = SCNNode()
        holder.position = position
        holder.addParticleSystem(ps)
        effects.addChildNode(holder)
        holder.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
    }
}

/// The whole 3D scene: forest set, lights, camera and one or two boards.
final class World3D {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var boards: [Board3D] = []
    private let models = PieceModels()
    private let ambient = SCNNode()
    private let sun = SCNNode()
    private var gloomBlend: CGFloat = 0
    private var shake = 0
    private var flashFrames = 0
    private var cameraBase = SCNVector3Zero
    private var spacing: Float = 0

    init(columns: Int, rows: Int, players: Int) {
        let root = scene.rootNode
        spacing = Float(columns + 2)
        for i in 0..<players {
            let b = Board3D(columns: columns, rows: rows, models: models)
            b.root.position = SCNVector3(Float(i) * spacing, 0, 0)
            root.addChildNode(b.root)
            boards.append(b)
        }
        let centerX = Float(players - 1) * spacing / 2

        // Sky gradient + fog for depth.
        scene.background.contents = Self.gradient(top: rgb(0x0B1A12), bottom: rgb(0x23402C))
        scene.fogColor = rgb(0x0E1F15)
        scene.fogStartDistance = 22
        scene.fogEndDistance = 45

        // Forest floor and distant trees (deterministic layout).
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.materials = [material(rgb(0x1F3A24), shiny: false)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -0.8, 0)
        root.addChildNode(floorNode)
        var rng = SeededRNG(seed: 42)
        for i in 0..<16 {
            let side: Float = i % 2 == 0 ? -1 : 1
            let tx = centerX + side * Float(3 + rng.int(below: 9)) + Float(columns) / 2 * side
            let tz = -Float(2 + rng.int(below: 7))
            let height = CGFloat(10 + rng.int(below: 8))
            root.addChildNode(node(SCNCylinder(radius: 0.35 + CGFloat(rng.int(below: 4)) * 0.08, height: height),
                                   Palette3D.darkBrown, SCNVector3(tx, Float(height) / 2 - 0.8, tz)))
            for k in 0..<3 {
                let s = SCNSphere(radius: 1.4 + CGFloat(rng.int(below: 5)) * 0.2)
                s.segmentCount = 14
                root.addChildNode(node(s, k % 2 == 0 ? Palette3D.darkLeaf : material(rgb(0x244F2E), shiny: false),
                                       SCNVector3(tx + Float(k - 1) * 0.9, Float(height) - 1.5 + Float(k % 2), tz)))
            }
        }

        // Lights.
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 520
        amb.color = UIColor(red: 0.95, green: 0.95, blue: 0.85, alpha: 1)
        ambient.light = amb
        root.addChildNode(ambient)
        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowSampleCount = 8
        key.shadowRadius = 2.5
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.45)
        key.automaticallyAdjustsShadowProjection = true
        sun.light = key
        sun.eulerAngles = SCNVector3(-0.85, -0.45, 0)
        root.addChildNode(sun)
        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 300
        rim.color = UIColor(red: 0.6, green: 0.8, blue: 1, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(centerX, Float(rows) + 4, -6)
        root.addChildNode(rimNode)

        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.1
        cam.zFar = 120
        cameraNode.camera = cam
        root.addChildNode(cameraNode)
    }

    static func gradient(top: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    /// Positions the camera so the boards' playfields land on `fieldRects`
    /// (view coordinates), matching where the HUD overlay expects them.
    func frame(fieldRects: [CGRect], viewSize: CGSize) {
        guard let first = fieldRects.first, viewSize.height > 0, let cam = cameraNode.camera,
              let board = boards.first else { return }
        let union = fieldRects.dropFirst().reduce(first) { $0.union($1) }
        let worldW = Float(boards.count - 1) * spacing + Float(board.columns)
        let worldH = Float(board.rows)
        // Points per world unit at the board plane.
        let k = min(Float(union.width) / worldW, Float(union.height) / worldH)
        guard k > 0 else { return }
        let visibleH = Float(viewSize.height) / k
        let fov = Float(cam.fieldOfView) * .pi / 180
        let distance = visibleH / 2 / tan(fov / 2)
        let pitch: Float = -0.1
        let centerWorldX = Float(boards.count - 1) * spacing / 2
        let centerWorldY = worldH / 2
        let dx = Float(union.midX - viewSize.width / 2) / k
        let dy = Float(union.midY - viewSize.height / 2) / k
        cameraBase = SCNVector3(centerWorldX - dx, centerWorldY + dy + distance * tan(-pitch), distance)
        cameraNode.position = cameraBase
        cameraNode.eulerAngles = SCNVector3(pitch, 0, 0)
        // Fog only on the distant forest, never on the playfield.
        scene.fogStartDistance = CGFloat(distance + 4)
        scene.fogEndDistance = CGFloat(distance + 26)
    }

    func render(_ session: SessionModel) {
        if let v = session.versus {
            for (i, b) in boards.enumerated() where i < v.players.count { b.render(v.players[i]) }
        } else {
            boards.first?.render(session.state)
        }
        // The Gloom darkens the light.
        let gloom = session.state.phase.kind == .gloom ? CGFloat(1) : 0
        gloomBlend += (gloom - gloomBlend) * 0.05
        ambient.light?.intensity = 520 - 220 * gloomBlend
        ambient.light?.color = UIColor(red: 0.95 - 0.25 * gloomBlend, green: 0.95 - 0.35 * gloomBlend,
                                       blue: 0.85 + 0.1 * gloomBlend, alpha: 1)
        sun.light?.intensity = 950 - 400 * gloomBlend + (flashFrames > 0 ? 1800 : 0)
        if flashFrames > 0 { flashFrames -= 1 }
        if shake > 0 {
            shake -= 1
            let d: Float = shake % 2 == 0 ? 0.08 : -0.08
            cameraNode.position = SCNVector3(cameraBase.x + d, cameraBase.y, cameraBase.z)
        } else {
            cameraNode.position = cameraBase
        }
    }

    func apply(_ events: [[GameEvent]], session: SessionModel) {
        for (i, ev) in events.enumerated() where i < boards.count {
            let state = session.versus?.players[i] ?? session.state
            boards[i].apply(ev, state: state)
            for e in ev {
                switch e {
                case .canopySlam: shake = 10
                case .starseedBurst: flash()
                default: break
                }
            }
        }
    }

    private func flash() {
        flashFrames = 8
    }
}
