import ThicketCore
import ThicketKit
import UIKit

/// On-screen D-pad and buttons. All the multitouch logic lives in the tested
/// `TouchTracker`; this view only forwards touches and draws.
final class TouchControlsView: UIView {
    var layout: ControlLayout = .standard {
        didSet { relayout() }
    }

    /// Edit mode: drag controls around instead of pressing them.
    var editing = false {
        didSet {
            tracker.reset()
            dragging.removeAll()
            refresh()
        }
    }

    /// Called whenever a control goes down (for haptics).
    var onPress: ((ControlID) -> Void)?
    /// Edit mode: called after a control was moved.
    var onLayoutChange: ((ControlLayout) -> Void)?

    private(set) var tracker = TouchTracker(controls: [])
    private var shapes: [ControlID: CAShapeLayer] = [:]
    private var labels: [ControlID: CATextLayer] = [:]
    private var arrowLayers: [Buttons.RawValue: CAShapeLayer] = [:]
    private var dragging: [Int: ControlID] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Safe area for the controls: the system safe area plus a margin so nothing
    /// sits under the screen-edge gesture zones.
    var controlArea: Rect2 {
        let r = bounds.inset(by: safeAreaInsets).insetBy(dx: 12, dy: 10)
        return Rect2(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        relayout()
    }

    func relayout() {
        tracker.setControls(layout.resolve(in: controlArea))
        rebuildLayers()
    }

    /// Releases every control (interruptions, pause, backgrounding).
    func releaseAll() {
        tracker.reset()
        refresh()
    }

    func consume() -> SourceState {
        SourceState(held: tracker.held, pressed: tracker.consumePressed())
    }

    // MARK: Drawing

    private func rebuildLayers() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        shapes.removeAll()
        labels.removeAll()
        arrowLayers.removeAll()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        for c in tracker.controls {
            let center = CGPoint(x: c.center.x, y: c.center.y)
            let r = CGFloat(c.radius)
            let shape = CAShapeLayer()
            shape.lineWidth = 2
            if c.id == .dpad {
                // A plus-shaped pad with four arrow highlights.
                let arm = r * 0.36
                let path = UIBezierPath()
                path.append(UIBezierPath(roundedRect: CGRect(x: center.x - arm, y: center.y - r, width: arm * 2, height: r * 2),
                                         cornerRadius: 6))
                path.append(UIBezierPath(roundedRect: CGRect(x: center.x - r, y: center.y - arm, width: r * 2, height: arm * 2),
                                         cornerRadius: 6))
                shape.path = path.cgPath
                shape.fillRule = .nonZero
                let arrows: [(Buttons, CGFloat)] = [(.up, -CGFloat.pi / 2), (.down, CGFloat.pi / 2),
                                                    (.left, CGFloat.pi), (.right, 0)]
                for (dir, angle) in arrows {
                    let tri = CAShapeLayer()
                    let tip = CGPoint(x: center.x + cos(angle) * r * 0.85, y: center.y + sin(angle) * r * 0.85)
                    let baseC = CGPoint(x: center.x + cos(angle) * r * 0.55, y: center.y + sin(angle) * r * 0.55)
                    let perp = CGPoint(x: -sin(angle) * arm * 0.6, y: cos(angle) * arm * 0.6)
                    let p = UIBezierPath()
                    p.move(to: tip)
                    p.addLine(to: CGPoint(x: baseC.x + perp.x, y: baseC.y + perp.y))
                    p.addLine(to: CGPoint(x: baseC.x - perp.x, y: baseC.y - perp.y))
                    p.close()
                    tri.path = p.cgPath
                    arrowLayers[dir.rawValue] = tri
                }
            } else {
                shape.path = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).cgPath
                let text = CATextLayer()
                text.string = c.id.label
                text.alignmentMode = .center
                text.contentsScale = scale
                let size: CGFloat = c.id == .a || c.id == .b ? r * 0.8 : r * 0.55
                text.font = UIFont.monospacedSystemFont(ofSize: size, weight: .heavy)
                text.fontSize = size
                text.frame = CGRect(x: center.x - r, y: center.y - size * 0.62, width: r * 2, height: size * 1.3)
                labels[c.id] = text
            }
            shapes[c.id] = shape
            layer.addSublayer(shape)
        }
        arrowLayers.values.forEach { layer.addSublayer($0) }
        labels.values.forEach { layer.addSublayer($0) }
        refresh()
    }

    /// Updates highlight colors; call after touch changes.
    func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let active = tracker.activeControls
        let alpha = CGFloat(layout.opacity)
        for (id, shape) in shapes {
            let on = active.contains(id) && id != .dpad
            let base: UIColor = id == .a ? UIColor(red: 0.90, green: 0.62, blue: 0.0, alpha: 1)
                : id == .b ? UIColor(red: 0.24, green: 0.61, blue: 0.88, alpha: 1)
                : id == .ab ? UIColor(red: 0.85, green: 0.49, blue: 0.71, alpha: 1)
                : UIColor(white: 0.85, alpha: 1)
            shape.fillColor = base.withAlphaComponent((on ? 0.85 : 0.35) * alpha + (editing ? 0.2 : 0)).cgColor
            shape.strokeColor = UIColor.white.withAlphaComponent((editing ? 1 : 0.7) * alpha).cgColor
            if id == .dpad {
                shape.fillColor = UIColor(white: 0.2, alpha: 0.55 * alpha + (editing ? 0.2 : 0)).cgColor
            }
        }
        let dir = tracker.dpadDirection
        for (raw, tri) in arrowLayers {
            let on = dir.contains(Buttons(rawValue: raw))
            tri.fillColor = UIColor.white.withAlphaComponent((on ? 0.95 : 0.4) * alpha).cgColor
        }
        for (_, text) in labels {
            text.foregroundColor = UIColor.white.withAlphaComponent(min(1, alpha + 0.2)).cgColor
        }
        CATransaction.commit()
    }

    // MARK: Touches

    private func key(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

    private func point(_ t: UITouch) -> Vec2 {
        let p = t.location(in: self)
        return Vec2(Double(p.x), Double(p.y))
    }

    private func syncLiveTouches(_ event: UIEvent?) {
        let live = (event?.touches(for: self) ?? [])
            .filter { $0.phase != .ended && $0.phase != .cancelled }
            .map(key)
        tracker.sync(activeTouches: Set(live))
    }

    private func emitFeedback() {
        for id in tracker.consumeFeedback() { onPress?(id) }
        refresh()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing {
            for t in touches {
                let p = point(t)
                if let c = tracker.controls.filter({ $0.contains(p) })
                    .min(by: { $0.center.distance(to: p) < $1.center.distance(to: p) }) {
                    dragging[key(t)] = c.id
                }
            }
            return
        }
        for t in touches { tracker.began(key(t), at: point(t)) }
        emitFeedback()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing {
            for t in touches {
                guard let id = dragging[key(t)] else { continue }
                layout.setCenter(id, controlArea.normalized(point(t)))
            }
            return
        }
        for t in touches { tracker.moved(key(t), to: point(t)) }
        emitFeedback()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, event)
    }

    private func finish(_ touches: Set<UITouch>, _ event: UIEvent?) {
        if editing {
            var moved = false
            for t in touches where dragging.removeValue(forKey: key(t)) != nil { moved = true }
            if moved { onLayoutChange?(layout) }
            return
        }
        for t in touches { tracker.ended(key(t)) }
        syncLiveTouches(event)
        refresh()
    }
}
