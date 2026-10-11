import Foundation
import ThicketCore

public enum ControlID: String, Codable, CaseIterable, Hashable {
    case dpad
    case a
    case b
    case ab
    case start
    case pause

    /// The game buttons this control drives (the D-pad is handled separately).
    public var buttons: Buttons {
        switch self {
        case .dpad: return []
        case .a: return .a
        case .b: return .b
        case .ab: return [.a, .b]
        case .start: return .start
        case .pause: return .pause
        }
    }

    public var label: String {
        switch self {
        case .dpad: return "D-Pad"
        case .a: return "A"
        case .b: return "B"
        case .ab: return "A+B"
        case .start: return "START"
        case .pause: return "II"
        }
    }
}

// MARK: - D-pad

/// Converts a finger position into D-pad directions.
///
/// The pad is split into 8 sectors around its center. Cardinal sectors are wider
/// than diagonal ones (`diagonalDegrees`) so a slightly-off thumb does not
/// accidentally press two directions.
public struct DPadGeometry: Equatable {
    public var center: Vec2
    public var radius: Double
    /// Fraction of the radius around the center that registers nothing.
    public var deadZone: Double
    /// Angular width of each diagonal sector.
    public var diagonalDegrees: Double

    public init(center: Vec2, radius: Double, deadZone: Double = 0.18, diagonalDegrees: Double = 30) {
        self.center = center
        self.radius = radius
        self.deadZone = deadZone
        self.diagonalDegrees = diagonalDegrees
    }

    public func buttons(at p: Vec2) -> Buttons {
        let d = p - center
        if d.length < radius * deadZone { return [] }
        // Math angle with y up, 0° = right, counter-clockwise.
        var angle = atan2(-d.y, d.x) * 180 / .pi
        if angle < 0 { angle += 360 }
        let cardinal = 90 - diagonalDegrees
        let half = cardinal / 2
        // Sector centers every 45°, alternating cardinal/diagonal widths.
        func within(_ center: Double, _ halfWidth: Double) -> Bool {
            var delta = abs(angle - center).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta = 360 - delta }
            return delta <= halfWidth
        }
        if within(0, half) { return .right }
        if within(90, half) { return .up }
        if within(180, half) { return .left }
        if within(270, half) { return .down }
        switch angle {
        case ..<90: return [.up, .right]
        case ..<180: return [.up, .left]
        case ..<270: return [.down, .left]
        default: return [.down, .right]
        }
    }
}

// MARK: - Layout

public struct ControlPlacement: Codable, Equatable, Hashable {
    public var id: ControlID
    /// Center, normalized to the safe-area rect (0...1).
    public var center: Vec2
    /// Base radius in points before the layout's scale.
    public var radius: Double

    public init(id: ControlID, center: Vec2, radius: Double) {
        self.id = id
        self.center = center
        self.radius = radius
    }
}

/// User-adjustable on-screen controls. Saved per device class.
public struct ControlLayout: Codable, Equatable, Hashable {
    public var placements: [ControlPlacement]
    /// Size multiplier (0.7...1.5).
    public var scale: Double
    /// 0.15...1.
    public var opacity: Double

    public static let scaleRange = 0.7...1.5
    public static let opacityRange = 0.15...1.0

    public init(placements: [ControlPlacement], scale: Double = 1, opacity: Double = 0.6) {
        self.placements = placements
        self.scale = scale
        self.opacity = opacity
    }

    /// Default layout: D-pad bottom-left, A/B bottom-right, the playfield stays clear
    /// in the middle third of the screen.
    public static let standard = ControlLayout(placements: [
        ControlPlacement(id: .dpad, center: Vec2(0.13, 0.68), radius: 64),
        ControlPlacement(id: .a, center: Vec2(0.92, 0.60), radius: 32),
        ControlPlacement(id: .b, center: Vec2(0.80, 0.78), radius: 32),
        ControlPlacement(id: .ab, center: Vec2(0.91, 0.86), radius: 22),
        ControlPlacement(id: .start, center: Vec2(0.86, 0.10), radius: 18),
        ControlPlacement(id: .pause, center: Vec2(0.95, 0.10), radius: 18),
    ])

    public func placement(_ id: ControlID) -> ControlPlacement? { placements.first { $0.id == id } }

    public mutating func setCenter(_ id: ControlID, _ c: Vec2) {
        guard let i = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[i].center = Vec2(min(1, max(0, c.x)), min(1, max(0, c.y)))
    }

    /// Clamps values into range (e.g. after decoding an old save).
    public func sanitized() -> ControlLayout {
        var l = self
        l.scale = min(ControlLayout.scaleRange.upperBound, max(ControlLayout.scaleRange.lowerBound, scale))
        l.opacity = min(ControlLayout.opacityRange.upperBound, max(ControlLayout.opacityRange.lowerBound, opacity))
        for id in ControlID.allCases where l.placement(id) == nil {
            if let p = ControlLayout.standard.placement(id) { l.placements.append(p) }
        }
        for i in l.placements.indices {
            let c = l.placements[i].center
            l.placements[i].center = Vec2(min(1, max(0, c.x)), min(1, max(0, c.y)))
        }
        return l
    }

    /// Resolves the layout into on-screen circles inside `safeArea`, keeping each
    /// control fully inside it (away from the screen edges and system gesture zones).
    public func resolve(in safeArea: Rect2) -> [ResolvedControl] {
        sanitized().placements.map { p in
            let r = p.radius * scale
            var c = safeArea.point(normalized: p.center)
            c.x = min(max(c.x, safeArea.minX + r), safeArea.maxX - r)
            c.y = min(max(c.y, safeArea.minY + r), safeArea.maxY - r)
            return ResolvedControl(id: p.id, center: c, radius: r)
        }
    }

    /// A key identifying the device class a layout was made for, e.g. "phone-667x375".
    public static func deviceKey(idiom: String, screenWidth: Double, screenHeight: Double) -> String {
        let w = Int(max(screenWidth, screenHeight).rounded())
        let h = Int(min(screenWidth, screenHeight).rounded())
        return "\(idiom)-\(w)x\(h)"
    }
}

public struct ResolvedControl: Equatable {
    public var id: ControlID
    public var center: Vec2
    public var radius: Double

    public init(id: ControlID, center: Vec2, radius: Double) {
        self.id = id
        self.center = center
        self.radius = radius
    }

    /// Touch target: a little larger than what is drawn.
    public var hitRadius: Double { radius * (id == .dpad ? 1.25 : 1.2) }

    public func contains(_ p: Vec2) -> Bool { p.distance(to: center) <= hitRadius }

    public var frame: Rect2 {
        Rect2(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

// MARK: - Multitouch tracking

/// Turns raw touches into button state with true multitouch semantics:
///
/// * The touch that lands on the D-pad owns it until that finger lifts, even if it
///   slides outside the pad (direction keeps following the finger).
/// * Button fingers can roll from one button to another; sliding off all buttons
///   releases, sliding back on presses again.
/// * Every press is latched until `consumePressed()` so taps shorter than one
///   frame are not lost.
/// * `reset()` / `sync(activeTouches:)` guarantee nothing stays stuck after an
///   interruption or a lost touch-end.
public struct TouchTracker {
    public private(set) var controls: [ResolvedControl]
    private var buttonTouches: [Int: ControlID?] = [:]
    private var dpadTouch: Int?
    private var dpadButtons: Buttons = []
    private var latched: Buttons = []
    private var feedback: [ControlID] = []

    public init(controls: [ResolvedControl]) {
        self.controls = controls
    }

    /// Updates control geometry (e.g. rotation, layout edit) and releases everything.
    public mutating func setControls(_ c: [ResolvedControl]) {
        controls = c
        reset()
    }

    public var held: Buttons {
        var b = dpadButtons
        for case let id? in buttonTouches.values { b.formUnion(id.buttons) }
        return b
    }

    /// Controls currently pressed (for drawing highlights).
    public var activeControls: Set<ControlID> {
        var s = Set(buttonTouches.values.compactMap { $0 })
        if dpadTouch != nil { s.insert(.dpad) }
        return s
    }

    public var dpadDirection: Buttons { dpadButtons }

    var dpad: ResolvedControl? { controls.first { $0.id == .dpad } }

    func button(at p: Vec2) -> ControlID? {
        // Nearest button whose hit circle contains the point.
        controls.filter { $0.id != .dpad && $0.contains(p) }
            .min { $0.center.distance(to: p) < $1.center.distance(to: p) }?.id
    }

    private mutating func record(_ before: Buttons, _ beforeControls: Set<ControlID>) {
        latched.formUnion(held.subtracting(before))
        for c in activeControls.subtracting(beforeControls).sorted(by: { $0.rawValue < $1.rawValue }) {
            feedback.append(c)
        }
    }

    public mutating func began(_ touch: Int, at p: Vec2) {
        let before = held, beforeControls = activeControls
        if dpadTouch == nil, let pad = dpad, pad.contains(p) {
            dpadTouch = touch
            dpadButtons = DPadGeometry(center: pad.center, radius: pad.radius).buttons(at: p)
        } else {
            buttonTouches.updateValue(button(at: p), forKey: touch)
        }
        record(before, beforeControls)
    }

    public mutating func moved(_ touch: Int, to p: Vec2) {
        let before = held, beforeControls = activeControls
        if touch == dpadTouch, let pad = dpad {
            dpadButtons = DPadGeometry(center: pad.center, radius: pad.radius).buttons(at: p)
        } else if buttonTouches.keys.contains(touch) {
            buttonTouches.updateValue(button(at: p), forKey: touch)
        }
        record(before, beforeControls)
    }

    public mutating func ended(_ touch: Int) {
        if touch == dpadTouch {
            dpadTouch = nil
            dpadButtons = []
        }
        buttonTouches.removeValue(forKey: touch)
    }

    public mutating func cancelled(_ touch: Int) { ended(touch) }

    /// Drops any touch the system no longer reports (protects against lost touch-ends).
    public mutating func sync(activeTouches: Set<Int>) {
        if let d = dpadTouch, !activeTouches.contains(d) { ended(d) }
        for t in Array(buttonTouches.keys) where !activeTouches.contains(t) { ended(t) }
    }

    /// Releases everything (app backgrounded, alert shown, controls edited…).
    public mutating func reset() {
        buttonTouches.removeAll()
        dpadTouch = nil
        dpadButtons = []
        latched = []
        feedback.removeAll()
    }

    public var touchCount: Int { buttonTouches.count + (dpadTouch == nil ? 0 : 1) }

    /// Buttons pressed since the last call (even if already released).
    public mutating func consumePressed() -> Buttons {
        defer { latched = [] }
        return latched
    }

    /// Controls that went down since the last call, for haptics/sounds.
    public mutating func consumeFeedback() -> [ControlID] {
        defer { feedback.removeAll() }
        return feedback
    }
}
