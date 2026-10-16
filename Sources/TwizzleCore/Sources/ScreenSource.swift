import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct ScreenInfo: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var isWindow: Bool
    public var appName: String?
}

public enum ScreenDevices {
    /// Whether the app currently has Screen Recording permission (no prompt).
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt (once) if permission hasn't been decided.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public static func displays() async -> [ScreenInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            return content.displays.enumerated().map { i, d in
                let name = screenName(for: d.displayID) ?? "Display \(i + 1)"
                return ScreenInfo(id: String(d.displayID), name: "\(name) (\(d.width)×\(d.height))", width: d.width, height: d.height, isWindow: false)
            }
        } catch {
            // Fall back to CoreGraphics so the menu still lists screens before permission is granted.
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetActiveDisplayList(16, &ids, &count)
            return ids.prefix(Int(count)).enumerated().map { i, id in
                ScreenInfo(id: String(id), name: screenName(for: id) ?? "Display \(i + 1)", width: Int(CGDisplayPixelsWide(id)), height: Int(CGDisplayPixelsHigh(id)), isWindow: false)
            }
        }
    }

    public static func windows() async -> [ScreenInfo] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let me = Bundle.main.bundleIdentifier
        return content.windows.filter { w in
            w.isOnScreen && w.frame.width > 120 && w.frame.height > 80 && w.windowLayer == 0
                && w.owningApplication?.bundleIdentifier != me && !(w.title ?? "").isEmpty
        }.map { w in
            let app = w.owningApplication?.applicationName ?? "?"
            return ScreenInfo(id: String(w.windowID), name: "\(app) — \(w.title ?? "")", width: Int(w.frame.width), height: Int(w.frame.height), isWindow: true, appName: app)
        }.sorted { $0.name < $1.name }
    }

    static func screenName(for id: CGDirectDisplayID) -> String? {
        #if canImport(AppKit)
        return NSScreenNameLookup.name(for: id)
        #else
        return nil
        #endif
    }
}

#if canImport(AppKit)
import AppKit
enum NSScreenNameLookup {
    static func name(for id: CGDirectDisplayID) -> String? {
        for s in NSScreen.screens {
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber, n.uint32Value == id {
                return s.localizedName
            }
        }
        return nil
    }
}
#endif

/// Screen or window capture via ScreenCaptureKit.
public final class ScreenSource: BufferedSource, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "dev.camtwizzle.screen", qos: .userInteractive)

    public override func start() {
        setState(.starting)
        Task { await self.configure() }
    }

    private func configure() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let filter: SCContentFilter
            var w = 1920, h = 1080
            let maxW = Int(spec.options["maxWidth"] ?? "1920") ?? 1920
            if spec.kind == .window {
                guard let win = content.windows.first(where: { String($0.windowID) == spec.identifier }) else {
                    setState(.failed("Window '\(spec.name)' is no longer available"))
                    return
                }
                filter = SCContentFilter(desktopIndependentWindow: win)
                let scale = Double(filter.pointPixelScale)
                w = Int(win.frame.width * scale); h = Int(win.frame.height * scale)
            } else {
                guard let display = content.displays.first(where: { String($0.displayID) == spec.identifier }) ?? content.displays.first else {
                    setState(.failed("No display available"))
                    return
                }
                // Don't capture our own windows (avoids infinite mirror tunnels).
                let mine = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: spec.options["includeSelf"] == "true" ? [] : mine, exceptingWindows: [])
                let scale = Double(filter.pointPixelScale)
                w = Int(Double(display.width) * scale); h = Int(Double(display.height) * scale)
            }
            if w > maxW { h = h * maxW / w; w = maxW }
            let cfg = SCStreamConfiguration()
            cfg.width = max(2, w & ~1)
            cfg.height = max(2, h & ~1)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Int(spec.options["fps"] ?? "30") ?? 30))
            cfg.showsCursor = spec.options["cursor"] != "false"
            cfg.queueDepth = 5
            cfg.colorSpaceName = CGColorSpace.sRGB
            let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            setState(.running)
        } catch {
            let ns = error as NSError
            if ns.domain == SCStreamErrorDomain || !ScreenDevices.hasPermission {
                setState(.failed("Screen recording not permitted — allow CamTwizzle in System Settings › Privacy & Security › Screen & System Audio Recording"))
            } else {
                setState(.failed(error.localizedDescription))
            }
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pb = sampleBuffer.imageBuffer else { return }
        // Skip idle/blank frames (status attachment).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        publish(SourceFrame(pixelBuffer: pb, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds))
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        setState(.failed(error.localizedDescription))
    }

    public override func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
        clearFrame()
        setState(.idle)
    }
}
