import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

/// A CoreMediaIO device as seen by clients, with its streams.
public struct VirtualCameraDevice: Identifiable, Hashable {
    public var id: String { uid }
    public let objectID: CMIOObjectID
    public let uid: String
    public let name: String
    public let model: String
    public let sinkStreams: [CMIOStreamID]
    public let sourceStreams: [CMIOStreamID]
    public var hasSink: Bool { !sinkStreams.isEmpty }
    /// Our own extension vs a third-party one (OBS) we can feed.
    public var isCamTwizzle: Bool { model.lowercased().contains("camtwizzle") || name.lowercased().contains("camtwizzle") }
    public var isOBS: Bool { name.lowercased().contains("obs") }
}

public enum CMIO {
    static func address(_ selector: CMIOObjectPropertySelector, scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                        element: CMIOObjectPropertyElement = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func objectIDs(_ obj: CMIOObjectID, _ selector: Int) -> [CMIOObjectID] {
        var addr = address(CMIOObjectPropertySelector(selector))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(obj, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func string(_ obj: CMIOObjectID, _ selector: Int) -> String? {
        var addr = address(CMIOObjectPropertySelector(selector))
        guard CMIOObjectHasProperty(obj, &addr) else { return nil }
        var cf: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &cf) { p in
            CMIOObjectGetPropertyData(obj, &addr, 0, nil, size, &used, p)
        }
        guard st == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    static func uint32(_ obj: CMIOObjectID, _ selector: Int) -> UInt32? {
        var addr = address(CMIOObjectPropertySelector(selector))
        guard CMIOObjectHasProperty(obj, &addr) else { return nil }
        var v: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(obj, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &v) == noErr else { return nil }
        return v
    }

    /// Allow access to "screen capture" style devices (iOS devices etc.). Harmless, and makes
    /// enumeration consistent with what other apps see.
    public static func enableAllDevices() {
        var addr = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    public static func devices() -> [VirtualCameraDevice] {
        objectIDs(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices).compactMap { dev in
            guard let uid = string(dev, kCMIODevicePropertyDeviceUID) else { return nil }
            let name = string(dev, kCMIOObjectPropertyName) ?? uid
            let model = string(dev, kCMIODevicePropertyModelUID) ?? ""
            var sinks: [CMIOStreamID] = []
            var sources: [CMIOStreamID] = []
            for s in objectIDs(dev, kCMIODevicePropertyStreams) {
                // kCMIOStreamPropertyDirection: 0 = output (data flows into the device: a sink), 1 = input
                if uint32(s, kCMIOStreamPropertyDirection) == 0 { sinks.append(s) } else { sources.append(s) }
            }
            return VirtualCameraDevice(objectID: dev, uid: uid, name: name, model: model, sinkStreams: sinks, sourceStreams: sources)
        }
    }

    /// Devices that accept frames from us (virtual cameras with a sink stream).
    public static func sinkDevices() -> [VirtualCameraDevice] { devices().filter(\.hasSink) }

    /// Calls `handler` on `queue` whenever cameras appear or disappear (e.g. a camera
    /// extension approved in System Settings while we're running).
    public static func observeDevices(queue: DispatchQueue = .main, _ handler: @escaping () -> Void) {
        var addr = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, queue) { _, _ in handler() }
    }

    public static func isRunningSomewhere(_ dev: CMIOObjectID) -> Bool {
        (uint32(dev, kCMIODevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    /// Whether any *client* (Zoom, Photo Booth...) is reading the device's source stream.
    public static func isInUse(_ device: VirtualCameraDevice) -> Bool {
        isRunningSomewhere(device.objectID)
    }
}

/// Feeds frames into a virtual camera's sink stream (our own Camera Extension,
/// or any compatible extension such as OBS Virtual Camera).
public final class CMIOSinkOutput {
    public let device: VirtualCameraDevice
    private let streamID: CMIOStreamID
    private var queue: CMSimpleQueue?
    private var formatDescription: CMVideoFormatDescription?
    private var running = false
    private let lock = NSLock()
    public private(set) var framesSent = 0
    public private(set) var framesDropped = 0
    public private(set) var lastError: String?
    /// Frames rejected in a row because the driver stopped draining our queue.
    private var consecutiveFull = 0
    public private(set) var restarts = 0

    public init?(deviceUID: String) {
        guard let d = CMIO.devices().first(where: { $0.uid == deviceUID }), let s = d.sinkStreams.first else { return nil }
        device = d
        streamID = s
    }

    public func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if running { return true }
        var unmanaged: Unmanaged<CMSimpleQueue>?
        let st = CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &unmanaged)
        guard st == noErr, let q = unmanaged?.takeRetainedValue() else {
            lastError = "CMIOStreamCopyBufferQueue failed (\(st))"
            TwzLog.error(lastError!)
            return false
        }
        queue = q
        let st2 = CMIODeviceStartStream(device.objectID, streamID)
        guard st2 == noErr else {
            lastError = "CMIODeviceStartStream failed (\(st2))"
            TwzLog.error(lastError!)
            queue = nil
            return false
        }
        running = true
        lastError = nil
        TwzLog.info("sink started on \(device.name)")
        return true
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        CMIODeviceStopStream(device.objectID, streamID)
        running = false
        queue = nil
    }

    deinit { stop() }

    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// The driver hasn't taken a frame for a while. Happens when another app (e.g. OBS's own
    /// "Start Virtual Camera") grabbed the device's sink, or after that app let go of it —
    /// OBS's extension then stops draining every client. Restarting the stream reclaims it.
    public var isStalled: Bool { lock.lock(); defer { lock.unlock() }; return running && consecutiveFull >= 45 }

    public func restart() {
        stop()
        lock.lock(); consecutiveFull = 0; restarts += 1; lock.unlock()
        _ = start()
        TwzLog.info("sink restarted on \(device.name) (stalled)")
    }

    /// Enqueue a frame. Returns false if the queue was full (frame dropped).
    @discardableResult
    public func send(_ pixelBuffer: CVPixelBuffer, hostTime: CMTime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard running, let queue else { return false }
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) {
            framesDropped += 1
            consecutiveFull += 1
            return false
        }
        consecutiveFull = 0
        if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            var fd: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
            formatDescription = fd
        }
        guard let fd = formatDescription else { return false }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: hostTime, decodeTimeStamp: .invalid)
        var sbuf: CMSampleBuffer?
        let st = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: fd,
                                                          sampleTiming: &timing, sampleBufferOut: &sbuf)
        guard st == noErr, let sbuf else { return false }
        let ptr = Unmanaged.passRetained(sbuf).toOpaque()
        let st2 = CMSimpleQueueEnqueue(queue, element: ptr)
        if st2 != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(ptr).release()
            framesDropped += 1
            return false
        }
        framesSent += 1
        return true
    }
}
