import Foundation
import ThicketCore

/// Anything that can hold blobs by key (UserDefaults, a file directory, memory).
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class MemoryStore: KeyValueStore {
    public private(set) var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func set(_ data: Data?, forKey key: String) { values[key] = data }
}

/// Stores each key as a file in a directory (used for the larger mid-round snapshot).
public final class FileStore: KeyValueStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(_ key: String) -> URL { directory.appendingPathComponent(key + ".json") }

    public func data(forKey key: String) -> Data? { try? Data(contentsOf: url(key)) }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            try? data.write(to: url(key), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url(key))
        }
    }
}

// MARK: - Saved models

public struct Settings: Codable, Equatable {
    public var musicVolume: Double = 0.6
    public var sfxVolume: Double = 0.85
    public var muted = false
    public var haptics = true
    /// Show touch controls even when a controller/keyboard is connected.
    public var alwaysShowTouchControls = false
    /// Saved per device class (see `ControlLayout.deviceKey`).
    public var controlLayouts: [String: ControlLayout] = [:]

    public init() {}

    public func layout(for deviceKey: String) -> ControlLayout {
        (controlLayouts[deviceKey] ?? .standard).sanitized()
    }

    public mutating func setLayout(_ layout: ControlLayout, for deviceKey: String) {
        controlLayouts[deviceKey] = layout.sanitized()
    }

    // Tolerant decoding: missing keys from older versions fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        musicVolume = (try? c.decode(Double.self, forKey: .musicVolume)) ?? d.musicVolume
        sfxVolume = (try? c.decode(Double.self, forKey: .sfxVolume)) ?? d.sfxVolume
        muted = (try? c.decode(Bool.self, forKey: .muted)) ?? d.muted
        haptics = (try? c.decode(Bool.self, forKey: .haptics)) ?? d.haptics
        alwaysShowTouchControls = (try? c.decode(Bool.self, forKey: .alwaysShowTouchControls)) ?? false
        controlLayouts = (try? c.decode([String: ControlLayout].self, forKey: .controlLayouts)) ?? [:]
        musicVolume = min(1, max(0, musicVolume))
        sfxVolume = min(1, max(0, sfxVolume))
    }
}

public struct SaveData: Codable, Equatable {
    public var campaign = CampaignProgress()
    /// Best Time Trial times in ticks, by trail id.
    public var bestTimes: [String: Int] = [:]
    public var endlessBest = 0
    public var bestChain = 0
    public var lessonsCompleted: Set<String> = []

    public init() {}

    public mutating func recordTime(trail: String, ticks: Int) -> Bool {
        if let best = bestTimes[trail], best <= ticks { return false }
        bestTimes[trail] = ticks
        return true
    }

    public mutating func recordEndless(score: Int, chain: Int) -> Bool {
        bestChain = max(bestChain, chain)
        guard score > endlessBest else { return false }
        endlessBest = score
        return true
    }
}

/// What to resume after the app was terminated in the background.
public enum SessionKind: Codable, Equatable {
    case campaign(round: Int)
    case endless
    case timeTrial(trail: String, index: Int, elapsedTicks: Int)
    case lesson(id: String)
    case versus
}

public struct SuspendedSession: Codable, Equatable {
    public var kind: SessionKind
    public var state: GameState?
    public var versus: VersusMatch?
    public var savedAt: Date

    public init(kind: SessionKind, state: GameState?, versus: VersusMatch?, savedAt: Date = Date()) {
        self.kind = kind
        self.state = state
        self.versus = versus
        self.savedAt = savedAt
    }
}

// MARK: - Store

/// Versioned JSON persistence. Corrupt or incompatible data never crashes the app:
/// it falls back to defaults (and the bad blob is discarded).
public final class Persistence {
    public static let version = 1

    enum Key {
        static let settings = "thicket.settings"
        static let save = "thicket.save"
        static let suspended = "thicket.suspended"
    }

    struct Envelope<T: Codable>: Codable {
        var version: Int
        var payload: T
    }

    let store: KeyValueStore
    /// The (larger) snapshot can live in a different store, e.g. a file.
    let snapshotStore: KeyValueStore

    public init(store: KeyValueStore, snapshotStore: KeyValueStore? = nil) {
        self.store = store
        self.snapshotStore = snapshotStore ?? store
    }

    func load<T: Codable>(_ type: T.Type, key: String, from s: KeyValueStore) -> T? {
        guard let data = s.data(forKey: key) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope<T>.self, from: data),
              env.version <= Persistence.version else {
            s.set(nil, forKey: key)
            return nil
        }
        return env.payload
    }

    func save<T: Codable>(_ value: T, key: String, to s: KeyValueStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(Envelope(version: Persistence.version, payload: value)) {
            s.set(data, forKey: key)
        }
    }

    public func loadSettings() -> Settings { load(Settings.self, key: Key.settings, from: store) ?? Settings() }
    public func saveSettings(_ s: Settings) { save(s, key: Key.settings, to: store) }

    public func loadSave() -> SaveData { load(SaveData.self, key: Key.save, from: store) ?? SaveData() }
    public func saveSave(_ s: SaveData) { save(s, key: Key.save, to: store) }

    public func loadSuspended() -> SuspendedSession? {
        load(SuspendedSession.self, key: Key.suspended, from: snapshotStore)
    }

    public func saveSuspended(_ s: SuspendedSession) { save(s, key: Key.suspended, to: snapshotStore) }
    public func clearSuspended() { snapshotStore.set(nil, forKey: Key.suspended) }
}
