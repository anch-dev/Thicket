public struct Buttons: OptionSet, Codable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let up = Buttons(rawValue: 1 << 0)
    public static let down = Buttons(rawValue: 1 << 1)
    public static let left = Buttons(rawValue: 1 << 2)
    public static let right = Buttons(rawValue: 1 << 3)
    public static let a = Buttons(rawValue: 1 << 4)
    public static let b = Buttons(rawValue: 1 << 5)
    public static let start = Buttons(rawValue: 1 << 6)
    public static let pause = Buttons(rawValue: 1 << 7)

    public static let directions: Buttons = [.up, .down, .left, .right]
    public static let all: Buttons = [.up, .down, .left, .right, .a, .b, .start, .pause]
}

/// What the simulation sees for one tick.
/// `pressed` holds every button that went down since the previous tick, even if it
/// was already released again (so very short taps are never lost).
public struct InputFrame: Codable, Equatable, Hashable {
    public var held: Buttons
    public var pressed: Buttons

    public init(held: Buttons = [], pressed: Buttons = []) {
        self.held = held
        self.pressed = pressed
    }

    public static let none = InputFrame()

    /// A one-tick tap of the given buttons.
    public static func tap(_ b: Buttons) -> InputFrame { InputFrame(held: b, pressed: b) }
}

/// A discrete thing Pip can be asked to do.
public enum PipAction: Int, Codable, Hashable, CaseIterable {
    case walkLeft
    case walkRight
    case climb
    case climbDown
    /// A: lift the piece in front and the whole stack above it.
    case liftStack
    /// B: pull out only the piece in front; pieces above it drop.
    case pull
    /// Down + A: kick the piece in front sideways.
    case kick
    /// While carrying: A, B, A+B or Up – put the load down in front.
    case place
    /// While carrying: Down – put the load down under Pip and stand on it.
    case placeBelow
}
