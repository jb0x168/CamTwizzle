import AVFoundation
import CoreVideo
import Foundation
import Metal

/// A frame from a source: either a CVPixelBuffer (cameras, screens, movies) or a texture.
public struct SourceFrame {
    public var pixelBuffer: CVPixelBuffer?
    public var texture: MTLTexture?
    public var width: Int
    public var height: Int
    public var timestamp: Double

    public init(pixelBuffer: CVPixelBuffer, timestamp: Double) {
        self.pixelBuffer = pixelBuffer
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        self.timestamp = timestamp
    }

    public init(texture: MTLTexture, timestamp: Double) {
        self.texture = texture
        width = texture.width
        height = texture.height
        self.timestamp = timestamp
    }
}

public enum SourceState: Equatable {
    case idle
    case starting
    case running
    case failed(String)

    public var message: String? {
        if case let .failed(m) = self { return m }
        return nil
    }
}

/// A live video input. Implementations must be thread-safe for `currentFrame()`.
public protocol VideoSource: AnyObject {
    var spec: SourceSpec { get }
    var state: SourceState { get }
    func start()
    func stop()
    func currentFrame() -> SourceFrame?
}

/// Sources that are generated on the GPU each frame (test patterns).
public protocol GeneratedSource: VideoSource {
    func encode(into texture: MTLTexture, time: Double, metal: MetalContext, cb: MTLCommandBuffer)
}

/// Base class with a lock-protected "latest frame" slot.
open class BufferedSource: NSObject, VideoSource {
    public let spec: SourceSpec
    private let lock = NSLock()
    private var _frame: SourceFrame?
    private var _state: SourceState = .idle
    public private(set) var frameCount = 0

    public init(spec: SourceSpec) {
        self.spec = spec
        super.init()
    }

    public var state: SourceState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public func setState(_ s: SourceState) {
        lock.lock(); _state = s; lock.unlock()
        if case let .failed(m) = s { TwzLog.warn("source \(spec.name): \(m)") }
    }

    public func publish(_ frame: SourceFrame) {
        lock.lock()
        _frame = frame
        frameCount += 1
        if _state != .running { _state = .running }
        lock.unlock()
    }

    public func currentFrame() -> SourceFrame? {
        lock.lock(); defer { lock.unlock() }
        return _frame
    }

    public func clearFrame() {
        lock.lock(); _frame = nil; lock.unlock()
    }

    open func start() {}
    open func stop() {}
}

/// Hands out shared, reference-counted source instances keyed by SourceSpec.key.
public final class SourceManager {
    private var sources: [String: (source: VideoSource, refs: Int)] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.camtwizzle.sources")
    public var analyzers: [String: SourceAnalyzer] = [:]

    public init() {}

    public func acquire(_ spec: SourceSpec) -> VideoSource {
        lock.lock()
        if let s = sources[spec.key] {
            sources[spec.key] = (s.source, s.refs + 1)
            lock.unlock()
            return s.source
        }
        let src = SourceManager.make(spec)
        sources[spec.key] = (src, 1)
        lock.unlock()
        queue.async { src.start() }
        return src
    }

    public func release(_ key: String) {
        lock.lock()
        guard let s = sources[key] else { lock.unlock(); return }
        if s.refs <= 1 {
            sources.removeValue(forKey: key)
            let a = analyzers.removeValue(forKey: key)
            lock.unlock()
            a?.stop()
            queue.async { s.source.stop() }
        } else {
            sources[key] = (s.source, s.refs - 1)
            lock.unlock()
        }
    }

    public func existing(_ key: String) -> VideoSource? {
        lock.lock(); defer { lock.unlock() }
        return sources[key]?.source
    }

    public func analyzer(for key: String) -> SourceAnalyzer? {
        lock.lock(); defer { lock.unlock() }
        if let a = analyzers[key] { return a }
        guard let s = sources[key]?.source else { return nil }
        let a = SourceAnalyzer(source: s)
        analyzers[key] = a
        return a
    }

    public var activeKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(sources.keys)
    }

    public func state(of key: String) -> SourceState? {
        lock.lock(); defer { lock.unlock() }
        return sources[key]?.source.state
    }

    static func make(_ spec: SourceSpec) -> VideoSource {
        switch spec.kind {
        case .camera: return CameraSource(spec: spec)
        case .screen, .window: return ScreenSource(spec: spec)
        case .image: return ImageSource(spec: spec)
        case .movie: return MovieSource(spec: spec)
        case .pattern: return PatternSource(spec: spec)
        case .syphon:
            #if HAVE_SYPHON
            return SyphonSource(spec: spec)
            #else
            let s = PatternSource(spec: spec)
            s.setState(.failed("Syphon support not compiled in"))
            return s
            #endif
        }
    }
}

// MARK: - Image file

public final class ImageSource: BufferedSource {
    private var texture: MTLTexture?

    public override func start() {
        let url = URL(fileURLWithPath: (spec.identifier as NSString).expandingTildeInPath)
        guard let img = TextureIO.loadCGImage(url) else {
            setState(.failed("Cannot read image \(url.lastPathComponent)"))
            return
        }
        // Publish as an IOSurface pixel buffer so Vision (faces, segmentation) works on stills too.
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                                    kCVPixelBufferMetalCompatibilityKey as String: true]
        CVPixelBufferCreate(kCFAllocatorDefault, img.width, img.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: img.width, height: img.height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            publish(SourceFrame(pixelBuffer: pb, timestamp: 0))
        } else {
            let tex = ResourceCache(device: MetalContext.shared.device).texture(from: img)
            texture = tex
            publish(SourceFrame(texture: tex, timestamp: 0))
        }
    }
}

// MARK: - Generated patterns

public final class PatternSource: BufferedSource, GeneratedSource {
    public static let patterns: [(id: String, name: String)] = [
        ("bars", "Test Pattern"), ("plasma", "Plasma"), ("color", "Solid Color"), ("checker", "Checkerboard"),
        ("gradient", "Gradient"), ("noise", "TV Static"),
    ]

    public override func start() { setState(.running) }

    var kind: Float {
        switch spec.identifier {
        case "color": return 0
        case "bars": return 1
        case "plasma": return 2
        case "checker": return 3
        case "gradient": return 4
        case "noise": return 5
        default: return 1
        }
    }

    func color(_ key: String, _ d: SIMD4<Float>) -> SIMD4<Float> {
        guard let s = spec.options[key] else { return d }
        let v = s.split(separator: ",").compactMap { Float($0) }
        return v.count >= 3 ? SIMD4(v[0], v[1], v[2], v.count > 3 ? v[3] : 1) : d
    }

    public func encode(into texture: MTLTexture, time: Double, metal: MetalContext, cb: MTLCommandBuffer) {
        let u: [SIMD4<Float>] = [
            SIMD4(Float(time), kind, Float(texture.width), Float(texture.height)),
            color("color", SIMD4(0.1, 0.1, 0.12, 1)),
            color("color2", SIMD4(0.9, 0.3, 0.6, 1)),
        ]
        metal.encodeInternal("twz_pattern", cb: cb, target: texture, textures: [], uniforms: u)
    }
}

// MARK: - Movie file (loops)

public final class MovieSource: BufferedSource {
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var timer: DispatchSourceTimer?
    private var endObserver: NSObjectProtocol?

    public override func start() {
        let url = URL(fileURLWithPath: (spec.identifier as NSString).expandingTildeInPath)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            setState(.failed("Can't read \(url.lastPathComponent)"))
            return
        }
        // One item with one video output, rewound at the end. (AVPlayerLooper's replica
        // items can't share a single AVPlayerItemVideoOutput, which left the picture frozen.)
        let item = AVPlayerItem(url: url)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        item.add(out)
        let player = AVPlayer(playerItem: item)
        player.isMuted = spec.options["muted"] != "false"
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
        self.player = player
        output = out
        player.play()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "movie"))
        t.schedule(deadline: .now(), repeating: 1.0 / 60)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        guard let player, let output else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time), let pb = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            publish(SourceFrame(pixelBuffer: pb, timestamp: CACurrentMediaTime()))
        }
        if let err = player.currentItem?.error { setState(.failed(err.localizedDescription)) }
    }

    public override func stop() {
        timer?.cancel()
        timer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        output = nil
    }
}
