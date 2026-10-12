import Foundation
import ThicketCore

public enum LogLevel: Int, Codable, Comparable, CaseIterable {
    case debug, info, warning, error

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var tag: String {
        switch self {
        case .debug: return "DBG"
        case .info: return "INF"
        case .warning: return "WRN"
        case .error: return "ERR"
        }
    }
}

/// In-memory ring buffer of log lines, shared by the whole app.
///
/// `debug` lines are only kept when `verbose` is on. Every line also goes to
/// `sink` (the app mirrors it to `os.Logger`, i.e. the Xcode / Console.app log).
/// Thread-safe.
public final class GameLog: @unchecked Sendable {
    public static let shared = GameLog()

    public let capacity: Int
    private let lock = NSLock()
    private var lines: [String] = []
    private var _verbose = false
    private var _dirty = false
    /// Mirror for each accepted line: (level, category, message).
    public var sink: ((LogLevel, String, String) -> Void)?

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public init(capacity: Int = 5000) {
        self.capacity = capacity
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public var verbose: Bool {
        get { locked { _verbose } }
        set { locked { _verbose = newValue } }
    }

    public func log(_ level: LogLevel, _ category: String, _ message: @autoclosure () -> String,
                    date: Date = Date()) {
        if level == .debug && !verbose { return }
        let text = message()
        let line = "\(formatter.string(from: date)) \(level.tag) [\(category)] \(text)"
        locked {
            lines.append(line)
            if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
            _dirty = true
        }
        sink?(level, category, text)
    }

    public func debug(_ category: String, _ message: @autoclosure () -> String) { log(.debug, category, message()) }
    public func info(_ category: String, _ message: @autoclosure () -> String) { log(.info, category, message()) }
    public func warning(_ category: String, _ message: @autoclosure () -> String) { log(.warning, category, message()) }
    public func error(_ category: String, _ message: @autoclosure () -> String) { log(.error, category, message()) }

    public var snapshot: [String] { locked { lines } }
    public var text: String { snapshot.joined(separator: "\n") + "\n" }

    public func clear() {
        locked {
            lines.removeAll()
            _dirty = true
        }
    }

    /// Writes the log to `url` if anything changed since the last write.
    @discardableResult
    public func flush(to url: URL, force: Bool = false) -> Bool {
        let (needed, body): (Bool, String) = locked {
            let n = _dirty || force
            _dirty = false
            return (n, lines.joined(separator: "\n") + "\n")
        }
        guard needed else { return false }
        do {
            try body.data(using: .utf8)?.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Descriptions

public enum LogFormat {
    public static func buttons(_ b: Buttons) -> String {
        let names: [(Buttons, String)] = [(.up, "U"), (.down, "D"), (.left, "L"), (.right, "R"),
                                          (.a, "A"), (.b, "B"), (.start, "St"), (.pause, "Pa")]
        let s = names.filter { b.contains($0.0) }.map(\.1).joined(separator: "+")
        return s.isEmpty ? "-" : s
    }

    public static func frame(_ f: InputFrame) -> String {
        "held=\(buttons(f.held)) pressed=\(buttons(f.pressed))"
    }

    public static func pip(_ p: Pip) -> String {
        var s = "Pip(\(p.column),\(p.row)) facing=\(p.facing == .left ? "L" : "R")"
        if p.clinging { s += " clinging" }
        if p.isCarrying { s += " carrying=[\(p.carried.map(Board.token(for:)).joined(separator: " "))]" }
        if p.busy > 0 { s += " \(p.motion) \(p.busy)t" }
        return s
    }

    public static func event(_ e: GameEvent) -> String {
        switch e {
        case let .actionRejected(action, reason): return "rejected \(action): \(reason)"
        case let .cleared(cells, pieces, chain, score):
            return "cleared \(pieces.count) [\(pieces.map(Board.token(for:)).joined(separator: " "))] at \(cells.map(\.description).joined()) chain=\(chain) +\(score)"
        default: return "\(e)"
        }
    }

    /// Multi-line dump of the field, for logging game overs and bug reports.
    public static func state(_ s: GameState) -> String {
        var out = ["tick=\(s.tick) status=\(s.status) phase=\(s.phase.kind) \(s.phase.elapsed)/\(s.phase.duration) ceiling=\(s.board.ceiling) score=\(s.score) mites=\(s.mitesRemaining)",
                   pip(s.pip)]
        for f in s.fallers {
            out.append("  faller \(Board.token(for: f.piece)) col=\(f.column) y=\(f.y) hang=\(f.hang) \(f.origin)")
        }
        let notation = s.board.notation
        out.append(contentsOf: notation.isEmpty ? ["  (empty board)"] : notation.map { "  | " + $0 })
        return out.joined(separator: "\n")
    }

}
