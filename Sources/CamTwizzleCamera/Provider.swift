import AppKit
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio
import os.log
import VideoToolbox

/// Stable UUIDs: devices/streams are derived from a fixed namespace so the
/// app can find them again after updates.
enum IDs {
    static func uuid(_ index: Int, _ role: UInt8) -> UUID {
        // 5C2A7E9B-… namespace with the device index and role in the last bytes.
        UUID(uuid: (0x5C, 0x2A, 0x7E, 0x9B, 0x1D, 0x4F, 0x4A, 0x11, 0x9E, 0x3C, 0xCA, 0x77, 0x7E, 0x15, UInt8(index), role))
    }
}

final class CamTwizzleProvider: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var devices: [CamTwizzleDevice] = []

    init(deviceCount: Int, baseName: String) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)
        for i in 0..<deviceCount {
            let name = i == 0 ? baseName : "\(baseName) \(i + 1)"
            let d = CamTwizzleDevice(name: name, index: i)
            devices.append(d)
            do { try provider.addDevice(d.device) } catch {
                os_log(.error, log: log, "addDevice failed: %{public}@", error.localizedDescription)
            }
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerName, .providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerName) { p.name = "CamTwizzle" }
        if properties.contains(.providerManufacturer) { p.manufacturer = "CamTwizzle" }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

struct VideoFormat {
    let width: Int32
    let height: Int32
    let fps: Int32
    let description: CMFormatDescription
    let streamFormat: CMIOExtensionStreamFormat

    init(width: Int32, height: Int32, fps: Int32) {
        self.width = width
        self.height = height
        self.fps = fps
        var fd: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
                                       width: width, height: height, extensions: nil, formatDescriptionOut: &fd)
        description = fd!
        let dur = CMTime(value: 1, timescale: fps)
        streamFormat = CMIOExtensionStreamFormat(formatDescription: fd!, maxFrameDuration: dur, minFrameDuration: dur, validFrameDurations: nil)
    }
}

final class CamTwizzleDevice: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var source: CamTwizzleStream!
    private var sink: CamTwizzleStream!
    let formats = [VideoFormat(width: 1920, height: 1080, fps: 30), VideoFormat(width: 1280, height: 720, fps: 30)]
    var activeFormat = 0

    private let queue = DispatchQueue(label: "dev.camtwizzle.camera.timer", qos: .userInteractive)
    private var sourceTimer: DispatchSourceTimer?
    private var sinkTimer: DispatchSourceTimer?
    private var sourceClients = 0
    private var sinkClient: CMIOExtensionClient?
    private var lastSinkFrame: CMSampleBuffer?
    private var lastSinkTime: UInt64 = 0
    private var pools: [Int: CVPixelBufferPool] = [:]
    private var transfer: VTPixelTransferSession?
    private var placeholder: [Int: CVPixelBuffer] = [:]
    private var sequence: UInt64 = 0
    let name: String

    init(name: String, index: Int) {
        self.name = name
        super.init()
        device = CMIOExtensionDevice(localizedName: name, deviceID: IDs.uuid(index, 0), legacyDeviceID: "CamTwizzle-\(index)", source: self)
        source = CamTwizzleStream(name: "\(name) Output", id: IDs.uuid(index, 1), direction: .source, device: self)
        sink = CamTwizzleStream(name: "\(name) Input", id: IDs.uuid(index, 2), direction: .sink, device: self)
        do {
            try device.addStream(source.stream)
            try device.addStream(sink.stream)
        } catch {
            os_log(.error, log: log, "addStream failed: %{public}@", error.localizedDescription)
        }
        VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { p.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { p.model = "CamTwizzle Camera" }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    var format: VideoFormat { formats[min(activeFormat, formats.count - 1)] }

    // MARK: Source (clients reading)

    func startSource() {
        queue.async {
            self.sourceClients += 1
            guard self.sourceTimer == nil else { return }
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(self.format.fps), leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.emitFrame() }
            t.resume()
            self.sourceTimer = t
        }
    }

    func stopSource() {
        queue.async {
            self.sourceClients = max(0, self.sourceClients - 1)
            if self.sourceClients == 0 {
                self.sourceTimer?.cancel()
                self.sourceTimer = nil
            }
        }
    }

    private func pool(for f: VideoFormat) -> CVPixelBufferPool? {
        let key = Int(f.width) << 16 | Int(f.height)
        if let p = pools[key] { return p }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: f.width,
            kCVPixelBufferHeightKey as String: f.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
        pools[key] = p
        return p
    }

    /// Called at the stream frame rate: forward the latest sink frame (scaled to the
    /// active format if needed) or the placeholder.
    private func emitFrame() {
        let f = format
        let now = mach_absolute_time()
        let fresh = lastSinkFrame != nil && machToSeconds(now &- lastSinkTime) < 1.0
        var out: CVPixelBuffer?
        if fresh, let sb = lastSinkFrame, let img = CMSampleBufferGetImageBuffer(sb) {
            if CVPixelBufferGetWidth(img) == Int(f.width) && CVPixelBufferGetHeight(img) == Int(f.height) {
                out = img
            } else if let pool = pool(for: f), let transfer {
                var dst: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst)
                if let dst, VTPixelTransferSessionTransferImage(transfer, from: img, to: dst) == noErr { out = dst }
            }
        }
        if out == nil { out = placeholderFrame(f) }
        guard let pb = out else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: f.fps),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sbuf: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescription: f.description,
                                                 sampleTiming: &timing, sampleBufferOut: &sbuf)
        guard let sbuf else { return }
        source.stream.send(sbuf, discontinuity: [], hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * 1e9))
    }

    // MARK: Sink (the CamTwizzle app writing)

    func startSink(client: CMIOExtensionClient) {
        queue.async {
            self.sinkClient = client
            self.sinkTimer?.cancel()
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(self.format.fps * 2), leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.consume() }
            t.resume()
            self.sinkTimer = t
        }
    }

    func stopSink() {
        queue.async {
            self.sinkTimer?.cancel()
            self.sinkTimer = nil
            self.sinkClient = nil
            self.lastSinkFrame = nil
        }
    }

    private func consume() {
        guard let client = sinkClient else { return }
        sink.stream.consumeSampleBuffer(from: client) { [weak self] sbuf, seq, _, _, _ in
            guard let self, let sbuf else { return }
            self.queue.async {
                self.lastSinkFrame = sbuf
                self.lastSinkTime = mach_absolute_time()
            }
            let out = CMIOExtensionScheduledOutput(sequenceNumber: seq, hostTimeInNanoseconds: UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1e9))
            self.sink.stream.notifyScheduledOutputChanged(out)
        }
    }

    // MARK: Placeholder

    private func placeholderFrame(_ f: VideoFormat) -> CVPixelBuffer? {
        let key = Int(f.width) << 16 | Int(f.height)
        if let p = placeholder[key] { return p }
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(f.width), Int(f.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(f.width), height: Int(f.height), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let w = CGFloat(f.width), h = CGFloat(f.height)
        let colors = [CGColor(red: 0.16, green: 0.05, blue: 0.28, alpha: 1), CGColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2),
                                   endRadius: w * 0.7, options: .drawsAfterEndLocation)
        }
        func draw(_ s: String, size: CGFloat, y: CGFloat, alpha: CGFloat) {
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: alpha)])
            let line = CTLineCreateWithAttributedString(attr)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            ctx.textPosition = CGPoint(x: (w - bounds.width) / 2 - bounds.minX, y: y)
            CTLineDraw(line, ctx)
        }
        draw("CamTwizzle", size: h * 0.11, y: h * 0.5, alpha: 1)
        draw("Open the CamTwizzle app to start the picture", size: h * 0.035, y: h * 0.4, alpha: 0.6)
        placeholder[key] = pb
        return pb
    }
}

private var timebase: mach_timebase_info_data_t = {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    return t
}()

func machToSeconds(_ t: UInt64) -> Double {
    Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e9
}

final class CamTwizzleStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    unowned let device: CamTwizzleDevice
    let direction: CMIOExtensionStream.Direction
    private var client: CMIOExtensionClient?

    init(name: String, id: UUID, direction: CMIOExtensionStream.Direction, device: CamTwizzleDevice) {
        self.device = device
        self.direction = direction
        super.init()
        stream = CMIOExtensionStream(localizedName: name, streamID: id, direction: direction, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { device.formats.map(\.streamFormat) }

    var availableProperties: Set<CMIOExtensionProperty> {
        var p: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            p.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData])
        }
        return p
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = device.activeFormat }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value: 1, timescale: device.format.fps) }
        if properties.contains(.streamSinkBufferQueueSize) { p.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { p.sinkBuffersRequiredForStartup = 1 }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if direction == .source, let i = streamProperties.activeFormatIndex, i >= 0, i < device.formats.count {
            device.activeFormat = i
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        if direction == .source {
            device.startSource()
        } else if let client {
            device.startSink(client: client)
        }
    }

    func stopStream() throws {
        if direction == .source { device.stopSource() } else { device.stopSink() }
    }
}
