import AVFoundation
import SpriteKit
import ThicketCore
import ThicketKit
import UIKit

// MARK: - Images

enum PixelImages {
    static func cgImage(_ img: PixelImage) -> CGImage? {
        guard img.width > 0, img.height > 0 else { return nil }
        let data = Data(img.rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func uiImage(_ img: PixelImage) -> UIImage {
        guard let cg = cgImage(img) else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

/// Caches SpriteKit textures generated from the text sprites (always nearest-neighbour).
final class TextureCache {
    static let shared = TextureCache()
    private var sprites: [String: SKTexture] = [:]
    private var texts: [String: SKTexture] = [:]

    func texture(_ img: PixelImage) -> SKTexture {
        let t = PixelImages.cgImage(img).map { SKTexture(cgImage: $0) } ?? SKTexture()
        t.filteringMode = .nearest
        return t
    }

    func sprite(_ name: String, color: PieceColor? = nil, tint: UInt32? = nil) -> SKTexture {
        let key = "\(name)|\(color?.rawValue ?? -1)|\(tint ?? 0)"
        if let t = sprites[key] { return t }
        let t = texture(PixelArt.sprite(name, color: color, tint: tint) ?? PixelImage(width: 1, height: 1, rgba: [0, 0, 0, 0]))
        sprites[key] = t
        return t
    }

    func text(_ s: String, color: UInt32 = 0xFFFF_FFFF) -> SKTexture {
        let key = "\(s)|\(color)"
        if let t = texts[key] { return t }
        if texts.count > 400 { texts.removeAll() }
        let t = texture(PixelArt.text(s, color: color))
        texts[key] = t
        return t
    }
}

// MARK: - Storage

final class UserDefaultsStore: KeyValueStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Haptics

final class Haptics {
    var enabled = true
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func prepare() {
        guard enabled else { return }
        light.prepare()
        medium.prepare()
    }

    func tap() { if enabled { light.impactOccurred(intensity: 0.6) } }
    func bump() { if enabled { medium.impactOccurred() } }
    func slam() { if enabled { heavy.impactOccurred() } }
    func success() { if enabled { notify.notificationOccurred(.success) } }
    func failure() { if enabled { notify.notificationOccurred(.error) } }
}

// MARK: - Audio

/// One AVAudioEngine with a single source node pulling from `ChipMixer`.
/// - Uses the `.ambient` session category, so the ring/silent switch mutes it and
///   other apps' audio can keep playing.
/// - Pauses on interruptions and when backgrounded; there is only ever one engine
///   and one source node, so audio is never duplicated after returning.
final class AudioEngine {
    let mixer = ChipMixer(sampleRate: 44_100)
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var song: Song?
    private var suspended = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.teardown()
            self?.startIfNeeded()
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    func apply(_ settings: Settings) {
        mixer.musicVolume = Float(settings.musicVolume)
        mixer.sfxVolume = Float(settings.sfxVolume)
        mixer.muted = settings.muted
    }

    func startIfNeeded() {
        guard !suspended else { return }
        if let engine, engine.isRunning { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if engine == nil {
            let e = AVAudioEngine()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: mixer.sampleRate, channels: 1) else { return }
            let mixer = self.mixer
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                let n = Int(frameCount)
                guard let first = buffers.first, let raw = first.mData else { return noErr }
                let out = raw.assumingMemoryBound(to: Float.self)
                mixer.render(into: out, count: n)
                for b in buffers.dropFirst() {
                    b.mData?.assumingMemoryBound(to: Float.self).update(from: out, count: n)
                }
                return noErr
            }
            e.attach(node)
            e.connect(node, to: e.mainMixerNode, format: format)
            engine = e
            source = node
        }
        do {
            try engine?.start()
        } catch {
            teardown()
        }
    }

    func teardown() {
        engine?.stop()
        if let source { engine?.detach(source) }
        engine = nil
        source = nil
    }

    /// App going to the background: stop producing sound entirely.
    func suspend() {
        suspended = true
        engine?.pause()
    }

    func resume() {
        suspended = false
        startIfNeeded()
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            engine?.pause()
        case .ended:
            startIfNeeded()
        @unknown default:
            break
        }
    }

    func play(song: Song?) {
        guard song != self.song else { return }
        self.song = song
        mixer.play(song: song)
        startIfNeeded()
    }

    func play(_ fx: SoundEffect) {
        mixer.play(fx)
    }
}
