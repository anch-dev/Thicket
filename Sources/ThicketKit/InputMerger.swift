import ThicketCore

/// One input device's contribution to a frame.
public struct SourceState: Equatable {
    public var held: Buttons
    /// Presses latched since the previous frame (may already be released).
    public var pressed: Buttons

    public init(held: Buttons = [], pressed: Buttons = []) {
        self.held = held
        self.pressed = pressed
    }
}

/// Derives press edges for a source that is polled (controllers, keyboards) and
/// adds presses reported by change handlers between polls.
public struct EdgeDetector {
    private var previous: Buttons = []
    private var latched: Buttons = []

    public init() {}

    /// Record a press seen by an event handler (so a tap between polls is kept).
    public mutating func notePress(_ b: Buttons) { latched.formUnion(b) }

    /// Poll result for this frame.
    public mutating func frame(held: Buttons) -> SourceState {
        let pressed = held.subtracting(previous).union(latched)
        previous = held
        latched = []
        return SourceState(held: held, pressed: pressed)
    }

    /// Forget everything (device disconnected, app resigned active).
    public mutating func reset() {
        previous = []
        latched = []
    }
}

/// Merges touch, controller and keyboard sources into the single `InputFrame` the
/// simulation consumes, and buffers presses across frames that run no simulation
/// tick (e.g. two display frames inside one 60 Hz tick).
public struct InputMerger {
    private var carried: Buttons = []

    public init() {}

    public mutating func merge(_ sources: [SourceState]) -> InputFrame {
        var held: Buttons = []
        var pressed = carried
        for s in sources {
            held.formUnion(s.held)
            pressed.formUnion(s.pressed)
        }
        carried = []
        return InputFrame(held: held, pressed: pressed)
    }

    /// The frame was polled but no simulation tick ran; keep its presses for the next one.
    public mutating func carryOver(_ frame: InputFrame) {
        carried.formUnion(frame.pressed)
    }

    public mutating func reset() { carried = [] }
}

/// Hardware keyboard bindings, using USB HID usage codes (the values of
/// `GCKeyCode`), so the mapping can be tested without GameController.framework.
public enum KeyMap {
    public enum HID {
        public static func letter(_ c: Character) -> Int {
            Int(c.asciiValue! - Character("a").asciiValue!) + 0x04
        }

        public static let returnKey = 0x28
        public static let escape = 0x29
        public static let space = 0x2C
        public static let comma = 0x36
        public static let period = 0x37
        public static let slash = 0x38
        public static let right = 0x4F
        public static let left = 0x50
        public static let down = 0x51
        public static let up = 0x52
        public static let leftShift = 0xE1
        public static let rightShift = 0xE5
    }

    /// Single player: arrows or WASD to move, X/K = A, Z/J = B, C/L/Space = A+B,
    /// Return = Start, Esc/P = Pause.
    public static let solo: [Int: Buttons] = [
        HID.up: .up, HID.down: .down, HID.left: .left, HID.right: .right,
        HID.letter("w"): .up, HID.letter("s"): .down, HID.letter("a"): .left, HID.letter("d"): .right,
        HID.letter("x"): .a, HID.letter("k"): .a,
        HID.letter("z"): .b, HID.letter("j"): .b,
        HID.letter("c"): [.a, .b], HID.letter("l"): [.a, .b], HID.space: [.a, .b],
        HID.returnKey: .start,
        HID.escape: .pause, HID.letter("p"): .pause,
    ]

    /// Versus, player 1: WASD + F (A) / G (B), Tab-free so both fit one keyboard.
    public static let versusP1: [Int: Buttons] = [
        HID.letter("w"): .up, HID.letter("s"): .down, HID.letter("a"): .left, HID.letter("d"): .right,
        HID.letter("f"): .a, HID.letter("g"): .b, HID.leftShift: .start,
    ]

    /// Versus, player 2: arrows + . (A) / , (B).
    public static let versusP2: [Int: Buttons] = [
        HID.up: .up, HID.down: .down, HID.left: .left, HID.right: .right,
        HID.period: .a, HID.comma: .b, HID.rightShift: .start,
        HID.returnKey: .start, HID.escape: .pause,
    ]

    public static func buttons(forPressedKeys keys: Set<Int>, map: [Int: Buttons]) -> Buttons {
        keys.reduce(into: Buttons()) { acc, k in acc.formUnion(map[k] ?? []) }
    }
}
