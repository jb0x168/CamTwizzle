import AVFoundation
import CoreVideo
import Foundation

/// Opens any camera (including virtual ones) exactly like a client app would —
/// used to verify what Photo Booth / Zoom actually receive.
public final class CameraClient: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.camtwizzle.client")
    public var onFrame: ((CVPixelBuffer) -> Void)?
    public private(set) var frames = 0

    public init?(deviceNameOrID: String) {
        super.init()
        let all = CameraDevices.list(includeVirtual: true)
        guard let info = all.first(where: { $0.uniqueID == deviceNameOrID })
                ?? all.first(where: { $0.name.localizedCaseInsensitiveContains(deviceNameOrID) }),
              let device = AVCaptureDevice(uniqueID: info.uniqueID),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        session.beginConfiguration()
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(out) else { return nil }
        session.addOutput(out)
        session.commitConfiguration()
    }

    public func start() { queue.async { self.session.startRunning() } }
    public func stop() { queue.async { self.session.stopRunning() } }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames += 1
        onFrame?(pb)
    }
}
