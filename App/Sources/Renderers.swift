import SceneKit
import SpriteKit
import ThicketCore
import ThicketKit
import UIKit

/// Draws a running session. Both renderers read the same `SessionModel`.
protocol GameRenderer: AnyObject {
    var view: UIView { get }
    var name: String { get }
    func layout(size: CGSize, safeInsets: UIEdgeInsets, screenScale: CGFloat)
    func render(_ session: SessionModel)
    func apply(_ events: [[GameEvent]], session: SessionModel)
}

/// The original crisp pixel-art renderer (SpriteKit).
final class PixelRenderer: GameRenderer {
    private let skView = SKView()
    private let scene = GameScene(size: CGSize(width: 800, height: 400))
    var view: UIView { skView }
    let name = "pixel"

    init(columns: Int, rows: Int, players: Int) {
        skView.ignoresSiblingOrder = false
        skView.isMultipleTouchEnabled = true
        skView.preferredFramesPerSecond = 60
        scene.configure(columns: columns, rows: rows, players: players)
        skView.presentScene(scene)
    }

    func layout(size: CGSize, safeInsets: UIEdgeInsets, screenScale: CGFloat) {
        scene.size = size
        scene.layout(safeInsets: safeInsets, screenScale: screenScale)
    }

    func render(_ session: SessionModel) { scene.render(session) }
    func apply(_ events: [[GameEvent]], session: SessionModel) { scene.apply(events, session: session) }
}

/// SceneKit 3D renderer with the pixel HUD drawn on top as an overlay.
final class Renderer3D: GameRenderer {
    private let scnView = SCNView()
    private let world: World3D
    private let hud: GameScene
    var view: UIView { scnView }
    let name = "3d"

    init(columns: Int, rows: Int, players: Int) {
        world = World3D(columns: columns, rows: rows, players: players)
        hud = GameScene(size: CGSize(width: 800, height: 400), overlay: true)
        hud.configure(columns: columns, rows: rows, players: players)
        scnView.scene = world.scene
        scnView.pointOfView = world.cameraNode
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        scnView.isMultipleTouchEnabled = true
        scnView.overlaySKScene = hud
    }

    func layout(size: CGSize, safeInsets: UIEdgeInsets, screenScale: CGFloat) {
        hud.size = size
        hud.layout(safeInsets: safeInsets, screenScale: screenScale)
        world.frame(fieldRects: hud.fieldRects(), viewSize: size)
    }

    func render(_ session: SessionModel) {
        world.render(session)
        hud.render(session)
    }

    func apply(_ events: [[GameEvent]], session: SessionModel) {
        world.apply(events, session: session)
        hud.apply(events, session: session)
    }
}
