import Foundation

// A tiny chiptune engine: pulse, triangle and noise voices, a step sequencer for
// the (original) songs below, and procedurally generated sound effects.
// It only produces Float samples; the iOS layer feeds them to AVAudioEngine.

public enum Waveform: Int, Codable {
    case pulse12, pulse25, pulse50, triangle, noise

    var duty: Double {
        switch self {
        case .pulse12: return 0.125
        case .pulse25: return 0.25
        default: return 0.5
        }
    }
}

public func midiFrequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

// MARK: - Songs

public struct NoteEvent: Equatable {
    public var step: Int
    public var length: Int
    /// MIDI note number, or for noise tracks a drum id (0 kick, 1 snare, 2 hat).
    public var note: Int
}

public struct Track: Equatable {
    public var wave: Waveform
    public var volume: Float
    public var events: [NoteEvent]
    public var steps: Int
}

public struct Song: Equatable {
    public var name: String
    public var bpm: Double
    public var tracks: [Track]
    public var loops: Bool

    public var steps: Int { tracks.map(\.steps).max() ?? 0 }
}

public enum NotationError: Error, Equatable {
    case badToken(String)
}

/// Parses a compact note string: space-separated `Name[accidental]Octave[:steps]`
/// tokens (`C5`, `F#4:2`, `Bb3:4`), `-` / `-:n` for rests, and for noise tracks
/// `k` (kick), `s` (snare), `h` (hat). Steps are 16th notes; default length is 1.
public enum NoteParser {
    static let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    public static func midi(_ name: Substring) -> Int? {
        var chars = Array(name)
        guard let first = chars.first, let base = semitones[first] else { return nil }
        chars.removeFirst()
        var semi = base
        if let c = chars.first, c == "#" || c == "b" {
            semi += c == "#" ? 1 : -1
            chars.removeFirst()
        }
        guard let octave = Int(String(chars)) else { return nil }
        return 12 * (octave + 1) + semi
    }

    public static func parse(_ text: String) throws -> (events: [NoteEvent], steps: Int) {
        var events: [NoteEvent] = []
        var step = 0
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "|" }) {
            let parts = token.split(separator: ":")
            guard let head = parts.first, parts.count <= 2 else { throw NotationError.badToken(String(token)) }
            var length = 1
            if parts.count == 2 {
                guard let l = Int(parts[1]), l > 0 else { throw NotationError.badToken(String(token)) }
                length = l
            }
            switch head {
            case "-": break
            case "k": events.append(NoteEvent(step: step, length: length, note: 0))
            case "s": events.append(NoteEvent(step: step, length: length, note: 1))
            case "h": events.append(NoteEvent(step: step, length: length, note: 2))
            default:
                guard let m = midi(head) else { throw NotationError.badToken(String(token)) }
                events.append(NoteEvent(step: step, length: length, note: m))
            }
            step += length
        }
        return (events, step)
    }

    public static func track(_ wave: Waveform, _ volume: Float, _ text: String) -> Track {
        // Songs are authored in this file; a parse failure is a programming error.
        let parsed = try! parse(text)
        return Track(wave: wave, volume: volume, events: parsed.events, steps: parsed.steps)
    }
}

/// Original compositions for Thicket.
public enum SongLibrary {
    /// "Wren's Glade": bright, C major.
    public static let wren = Song(name: "Wren's Glade", bpm: 132, tracks: [
        NoteParser.track(.pulse25, 0.20, """
        E5:2 G5:2 C6:2 G5:2 A5:2 G5:2 E5:4 | F5:2 A5:2 G5:2 E5:2 D5:4 -:4
        E5:2 G5:2 C6:2 D6:2 E6:2 D6:2 C6:4 | A5:2 G5:2 E5:2 D5:2 C5:6 -:2
        C5:2 E5:2 G5:2 E5:2 F5:2 A5:2 C6:4 | B5:2 G5:2 D5:2 G5:2 B5:4 -:4
        C6:2 B5:2 A5:2 G5:2 F5:2 E5:2 D5:2 F5:2 | E5:4 D5:4 C5:6 -:2
        """),
        NoteParser.track(.triangle, 0.30, """
        C3:2 G3:2 C4:2 G3:2 C3:2 G3:2 C4:2 G3:2 | F2:2 C3:2 F3:2 C3:2 G2:2 D3:2 G3:2 D3:2
        C3:2 G3:2 C4:2 G3:2 A2:2 E3:2 A3:2 E3:2 | F2:2 C3:2 G2:2 D3:2 C3:4 G2:4
        C3:2 G3:2 C4:2 G3:2 F2:2 C3:2 F3:2 C3:2 | G2:2 D3:2 G3:2 D3:2 G2:2 D3:2 B2:2 D3:2
        A2:2 E3:2 A3:2 E3:2 F2:2 C3:2 G2:2 D3:2 | C3:2 G3:2 E3:2 G3:2 C3:4 -:4
        """),
        NoteParser.track(.noise, 0.10, String(repeating: "k:2 h:2 s:2 h:2 k:2 h:2 s:2 h:2 ", count: 8)),
    ], loops: true)

    /// "The Gloom": tense, A minor.
    public static let gloom = Song(name: "The Gloom", bpm: 116, tracks: [
        NoteParser.track(.pulse50, 0.16, """
        A4:3 C5:1 E5:2 D5:2 C5:2 B4:2 A4:4 | G#4:2 B4:2 E5:4 D5:2 B4:2 G#4:4
        A4:2 C5:2 F5:4 E5:2 D5:2 C5:4 | B4:2 G#4:2 E4:4 -:8
        """),
        NoteParser.track(.triangle, 0.32, """
        A2:2 A2:2 A3:2 A2:2 A2:2 A2:2 A3:2 A2:2 | E2:2 E2:2 E3:2 E2:2 E2:2 E2:2 G#2:2 E2:2
        F2:2 F2:2 F3:2 F2:2 D2:2 D2:2 D3:2 D2:2 | E2:2 E2:2 E3:2 E2:2 E2:2 G#2:2 B2:2 E3:2
        """),
        NoteParser.track(.noise, 0.12, String(repeating: "k:2 h:1 h:1 s:2 h:2 k:1 k:1 h:2 s:2 h:2 ", count: 4)),
    ], loops: true)

    /// "Under the Leaves": gentle menu theme, F major.
    public static let menu = Song(name: "Under the Leaves", bpm: 96, tracks: [
        NoteParser.track(.pulse25, 0.16, """
        F5:4 A5:4 C6:4 A5:4 | G5:4 Bb5:4 A5:8 | F5:4 D5:4 C5:4 D5:4 | E5:4 G5:4 F5:8
        """),
        NoteParser.track(.triangle, 0.28, "F3:8 C3:8 | G2:8 C3:8 | Bb2:8 F2:8 | C3:8 F2:8"),
    ], loops: true)

    public static let all = [wren, gloom, menu]
}

// MARK: - Sound effects

public enum SoundEffect: String, CaseIterable {
    case step, turn, lift, pull, place, kick, land, bump, caught
    case clear, chain2, chain3, chain4, chain5, starseed, burst, hit
    case spawnSeed, spawnMite, slam, canopyLift, phaseGloom, phaseWren
    case gameOver, roundClear, menuMove, menuSelect

    public static func chain(_ level: Int) -> SoundEffect {
        switch level {
        case ..<2: return .clear
        case 2: return .chain2
        case 3: return .chain3
        case 4: return .chain4
        default: return .chain5
        }
    }
}

/// A sound effect is a list of segments rendered back to back (or layered).
struct Segment {
    var wave: Waveform
    var from: Double
    var to: Double
    var duration: Double
    var volume: Double
    var at: Double = 0
}

public enum SFXSynth {
    static func arpeggio(_ wave: Waveform, _ notes: [Int], each: Double, volume: Double,
                         hold: Double = 0) -> [Segment] {
        var segs: [Segment] = []
        for (i, n) in notes.enumerated() {
            let f = midiFrequency(n)
            let last = i == notes.count - 1
            segs.append(Segment(wave: wave, from: f, to: f, duration: each + (last ? hold : 0),
                                volume: volume, at: Double(i) * each))
        }
        return segs
    }

    static func segments(_ fx: SoundEffect) -> [Segment] {
        switch fx {
        case .step: return [Segment(wave: .pulse12, from: 900, to: 650, duration: 0.03, volume: 0.10)]
        case .turn: return [Segment(wave: .pulse12, from: 700, to: 700, duration: 0.02, volume: 0.07)]
        case .lift: return [Segment(wave: .pulse25, from: 300, to: 760, duration: 0.09, volume: 0.25)]
        case .pull: return [Segment(wave: .pulse25, from: 520, to: 880, duration: 0.07, volume: 0.25)]
        case .place:
            return [Segment(wave: .pulse50, from: 420, to: 180, duration: 0.08, volume: 0.22),
                    Segment(wave: .noise, from: 3000, to: 1500, duration: 0.05, volume: 0.15)]
        case .kick:
            return [Segment(wave: .noise, from: 6000, to: 2000, duration: 0.12, volume: 0.2),
                    Segment(wave: .pulse25, from: 700, to: 140, duration: 0.14, volume: 0.2)]
        case .land: return [Segment(wave: .triangle, from: 220, to: 110, duration: 0.06, volume: 0.35)]
        case .bump: return [Segment(wave: .pulse50, from: 130, to: 110, duration: 0.07, volume: 0.18)]
        case .caught: return [Segment(wave: .pulse25, from: 620, to: 620, duration: 0.05, volume: 0.2)]
        case .clear: return arpeggio(.pulse25, [72, 76, 79], each: 0.05, volume: 0.25, hold: 0.05)
        case .chain2: return arpeggio(.pulse25, [74, 78, 81, 86], each: 0.045, volume: 0.26, hold: 0.06)
        case .chain3: return arpeggio(.pulse25, [76, 80, 83, 88], each: 0.042, volume: 0.27, hold: 0.07)
        case .chain4: return arpeggio(.pulse25, [79, 83, 86, 91], each: 0.04, volume: 0.28, hold: 0.08)
        case .chain5: return arpeggio(.pulse12, [81, 85, 88, 93, 97], each: 0.038, volume: 0.3, hold: 0.1)
        case .starseed: return arpeggio(.pulse12, [84, 88, 91, 96, 100], each: 0.04, volume: 0.25, hold: 0.15)
        case .burst:
            return [Segment(wave: .noise, from: 8000, to: 500, duration: 0.4, volume: 0.25),
                    Segment(wave: .pulse25, from: 1600, to: 200, duration: 0.4, volume: 0.15)]
        case .hit: return [Segment(wave: .pulse50, from: 1000, to: 1400, duration: 0.06, volume: 0.18)]
        case .spawnSeed: return [Segment(wave: .pulse12, from: 1800, to: 2300, duration: 0.04, volume: 0.07)]
        case .spawnMite: return [Segment(wave: .pulse50, from: 160, to: 120, duration: 0.05, volume: 0.08)]
        case .slam:
            return [Segment(wave: .noise, from: 900, to: 120, duration: 0.4, volume: 0.35),
                    Segment(wave: .triangle, from: 110, to: 45, duration: 0.35, volume: 0.45)]
        case .canopyLift: return [Segment(wave: .triangle, from: 110, to: 260, duration: 0.25, volume: 0.35)]
        case .phaseGloom: return arpeggio(.pulse50, [57, 63, 56, 62], each: 0.09, volume: 0.2, hold: 0.1)
        case .phaseWren:
            return [Segment(wave: .pulse12, from: 1900, to: 2500, duration: 0.05, volume: 0.15),
                    Segment(wave: .pulse12, from: 2100, to: 2700, duration: 0.05, volume: 0.15, at: 0.08)]
        case .gameOver: return arpeggio(.pulse50, [79, 76, 72, 67, 60], each: 0.15, volume: 0.25, hold: 0.25)
        case .roundClear: return arpeggio(.pulse25, [72, 76, 79, 84, 88], each: 0.08, volume: 0.25, hold: 0.35)
        case .menuMove: return [Segment(wave: .pulse12, from: 1200, to: 1200, duration: 0.03, volume: 0.1)]
        case .menuSelect: return [Segment(wave: .pulse25, from: 880, to: 1320, duration: 0.08, volume: 0.2)]
        }
    }

    /// Renders an effect to mono samples.
    public static func render(_ fx: SoundEffect, sampleRate: Double) -> [Float] {
        let segs = segments(fx)
        let total = segs.map { $0.at + $0.duration }.max() ?? 0
        var out = [Float](repeating: 0, count: Int(total * sampleRate) + 1)
        for seg in segs {
            var osc = Oscillator(wave: seg.wave)
            let start = Int(seg.at * sampleRate)
            let n = Int(seg.duration * sampleRate)
            for i in 0..<n where start + i < out.count {
                let t = Double(i) / Double(max(1, n))
                let freq = seg.from + (seg.to - seg.from) * t
                // Quick attack, linear decay to zero.
                let env = min(1, Double(i) / (0.002 * sampleRate)) * (1 - t)
                out[start + i] += Float(osc.next(freq: freq, sampleRate: sampleRate) * env * seg.volume)
            }
        }
        return out
    }
}

// MARK: - Oscillator

struct Oscillator {
    var wave: Waveform
    var phase: Double = 0
    var lfsr: UInt16 = 1
    var noiseValue: Double = 1

    init(wave: Waveform) { self.wave = wave }

    mutating func next(freq: Double, sampleRate: Double) -> Double {
        let previous = phase
        phase += freq / sampleRate
        if phase >= 1 { phase -= floor(phase) }
        switch wave {
        case .pulse12, .pulse25, .pulse50:
            return phase < wave.duty ? 1 : -1
        case .triangle:
            // 4-bit stepped triangle, like classic sound chips.
            let tri = phase < 0.5 ? phase * 4 - 1 : 3 - phase * 4
            return (tri * 7.5).rounded() / 7.5
        case .noise:
            // Clock a 15-bit LFSR each time the phase wraps.
            if phase < previous {
                let bit = (lfsr ^ (lfsr >> 1)) & 1
                lfsr = (lfsr >> 1) | (bit << 14)
                noiseValue = (lfsr & 1) == 0 ? 1 : -1
            }
            return noiseValue
        }
    }
}

// MARK: - Mixer

/// Mixes the current song and any playing effects. Thread-safe: commands come
/// from the main thread, `render` is called from the audio thread.
public final class ChipMixer {
    public let sampleRate: Double
    private let lock = NSLock()
    private var effects: [SoundEffect: [Float]] = [:]

    // State shared between threads (guarded by `lock`).
    private var pendingSong: Song??
    private var pendingFX: [SoundEffect] = []
    private var _musicVolume: Float = 0.6
    private var _sfxVolume: Float = 0.85
    private var _muted = false

    // Audio-thread state.
    private var song: Song?
    private var samplePos = 0
    private var voices: [MusicVoice] = []
    private var playing: [(samples: [Float], pos: Int)] = []

    struct MusicVoice {
        var osc: Oscillator
        var freq: Double
        var age = 0
        var length = 0
        var volume: Float
        var drum: Int
        var active = false
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public init(sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        for fx in SoundEffect.allCases { effects[fx] = SFXSynth.render(fx, sampleRate: sampleRate) }
    }

    public var musicVolume: Float {
        get { locked { _musicVolume } }
        set { locked { _musicVolume = max(0, min(1, newValue)) } }
    }

    public var sfxVolume: Float {
        get { locked { _sfxVolume } }
        set { locked { _sfxVolume = max(0, min(1, newValue)) } }
    }

    public var muted: Bool {
        get { locked { _muted } }
        set { locked { _muted = newValue } }
    }

    public func play(song: Song?) {
        locked { pendingSong = .some(song) }
    }

    public func play(_ fx: SoundEffect) {
        locked {
            if pendingFX.count < 16 { pendingFX.append(fx) }
        }
    }

    /// Stops everything immediately (used when the engine is torn down).
    public func silence() {
        locked {
            pendingSong = .some(nil)
            pendingFX.removeAll()
        }
    }

    var samplesPerStep: Int {
        guard let s = song else { return 1 }
        return max(1, Int(sampleRate * 60 / (s.bpm * 4)))
    }

    /// Fills `count` mono samples.
    public func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        lock.lock()
        let newSong = pendingSong
        pendingSong = nil
        let fx = pendingFX
        pendingFX.removeAll()
        let musicVol = _musicVolume, sfxVol = _sfxVolume, muted = _muted
        lock.unlock()

        if let s = newSong {
            song = s
            samplePos = 0
            voices = (s?.tracks ?? []).map {
                MusicVoice(osc: Oscillator(wave: $0.wave), freq: 0, volume: $0.volume, drum: 0)
            }
        }
        for f in fx {
            if let samples = effects[f] {
                if playing.count >= 8 { playing.removeFirst() }
                playing.append((samples, 0))
            }
        }

        let spStep = samplesPerStep
        for i in 0..<count {
            var music: Float = 0
            if let s = song, s.steps > 0 {
                if samplePos % spStep == 0 {
                    let step = samplePos / spStep
                    if step >= s.steps {
                        if s.loops {
                            samplePos = 0
                        } else {
                            song = nil
                        }
                    }
                    if let s = song {
                        let st = samplePos / spStep
                        for (t, track) in s.tracks.enumerated() where t < voices.count {
                            if let e = track.events.first(where: { $0.step == st }) {
                                voices[t].active = true
                                voices[t].age = 0
                                voices[t].length = e.length * spStep
                                if track.wave == .noise {
                                    voices[t].drum = e.note
                                    voices[t].freq = [800, 4000, 12000][min(2, max(0, e.note))]
                                } else {
                                    voices[t].freq = midiFrequency(e.note)
                                }
                            }
                        }
                    }
                }
                for v in voices.indices where voices[v].active {
                    let age = voices[v].age
                    let env: Float
                    if voices[v].osc.wave == .noise {
                        let decay = [0.06, 0.09, 0.03][voices[v].drum] * sampleRate
                        env = Float(max(0, 1 - Double(age) / decay))
                    } else {
                        let len = voices[v].length
                        let release = Int(0.02 * sampleRate)
                        let gate = max(1, len - release)
                        if age < gate {
                            env = age < 100 ? Float(age) / 100 : 1 - 0.3 * Float(age) / Float(gate)
                        } else {
                            env = max(0, 0.7 * (1 - Float(age - gate) / Float(release)))
                        }
                    }
                    if env <= 0 && age > 0 {
                        voices[v].active = false
                        continue
                    }
                    let freq = voices[v].drum == 0 && voices[v].osc.wave == .noise
                        ? voices[v].freq * (1 - min(0.8, Double(age) / sampleRate * 8)) : voices[v].freq
                    music += Float(voices[v].osc.next(freq: freq, sampleRate: sampleRate)) * env * voices[v].volume
                    voices[v].age += 1
                }
                samplePos += 1
            }
            var sfx: Float = 0
            var j = 0
            while j < playing.count {
                let p = playing[j]
                if p.pos < p.samples.count {
                    sfx += p.samples[p.pos]
                    playing[j].pos += 1
                    j += 1
                } else {
                    playing.remove(at: j)
                }
            }
            let mixed = muted ? 0 : music * musicVol + sfx * sfxVol
            // Soft clip.
            out[i] = mixed / (1 + abs(mixed))
        }
    }
}
