import AVFoundation
import CoreMediaIO
import Foundation

public struct CameraDeviceInfo: Identifiable, Hashable {
    public var id: String { uniqueID }
    public let uniqueID: String
    public let name: String
    public let model: String
    public let isVirtual: Bool
}

public enum CameraDevices {
    /// Names/models of virtual cameras we must never capture from (feedback loops).
    static let virtualMarkers = ["camtwizzle", "obs virtual camera", "obs camera extension", "virtual", "camtwist", "snap camera", "mmhmm"]

    public static func list(includeVirtual: Bool = false) -> [CameraDeviceInfo] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        if #available(macOS 15.0, *) {} // deskViewCamera is also available but rarely useful as a layer
        types.append(.deskViewCamera)
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        return session.devices.map { d in
            let lname = (d.localizedName + " " + d.modelID + " " + d.manufacturer).lowercased()
            let virt = virtualMarkers.contains { lname.contains($0) }
            return CameraDeviceInfo(uniqueID: d.uniqueID, name: d.localizedName, model: d.modelID, isVirtual: virt)
        }.filter { includeVirtual || !$0.isVirtual }
    }

    public static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    public static func requestAccess(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
    }
}

/// Webcam capture via AVFoundation, delivering BGRA pixel buffers.
public final class CameraSource: BufferedSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "dev.camtwizzle.camera", qos: .userInteractive)

    public override func start() {
        guard CameraDevices.authorization != .denied && CameraDevices.authorization != .restricted else {
            setState(.failed("Camera access denied — enable it in System Settings › Privacy & Security › Camera"))
            return
        }
        if CameraDevices.authorization == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                guard let self else { return }
                if ok { self.queue.async { self.configure() } } else { self.setState(.failed("Camera access denied")) }
            }
            return
        }
        queue.async { self.configure() }
    }

    private func configure() {
        setState(.starting)
        guard let device = AVCaptureDevice(uniqueID: spec.identifier) ?? (spec.identifier == "default" ? AVCaptureDevice.default(for: .video) : nil) else {
            setState(.failed("Camera '\(spec.name)' not found"))
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw PluginError.unsupported("cannot add camera input") }
            session.addInput(input)
        } catch {
            setState(.failed("\(error.localizedDescription)"))
            return
        }
        // Choose the format closest to the requested size (default 1920×1080) at ≥30 fps.
        let wantW = Int(spec.options["width"] ?? "1920") ?? 1920
        let wantH = Int(spec.options["height"] ?? "1080") ?? 1080
        let wantFPS = Double(spec.options["fps"] ?? "30") ?? 30
        var best: AVCaptureDevice.Format?
        var bestScore = Double.infinity
        for f in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let maxFPS = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            if maxFPS + 0.5 < wantFPS { continue }
            let score = abs(Double(Int(dims.width) * Int(dims.height) - wantW * wantH)) / Double(wantW * wantH)
                + (Double(dims.width) / Double(dims.height) - Double(wantW) / Double(wantH)).magnitude
            if score < bestScore { bestScore = score; best = f }
        }
        if let best {
            do {
                try device.lockForConfiguration()
                device.activeFormat = best
                let range = best.videoSupportedFrameRateRanges.first { $0.maxFrameRate + 0.5 >= wantFPS }
                if let range {
                    let fps = min(wantFPS, range.maxFrameRate)
                    device.activeVideoMinFrameDuration = CMTime(value: 1000, timescale: CMTimeScale(fps * 1000))
                }
                device.unlockForConfiguration()
            } catch {
                TwzLog.warn("camera format: \(error)")
            }
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            setState(.failed("cannot add video output"))
            return
        }
        session.addOutput(output)
        session.commitConfiguration()
        NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] n in
            let err = n.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.setState(.failed(err?.localizedDescription ?? "capture error"))
        }
        self.session = session
        session.startRunning()
        if !session.isRunning { setState(.failed("Camera could not start (in use by another app?)")) }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        publish(SourceFrame(pixelBuffer: pb, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds))
    }

    public override func stop() {
        let s = session
        session = nil
        queue.async { s?.stopRunning() }
        clearFrame()
        setState(.idle)
    }
}
