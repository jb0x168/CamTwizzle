import CoreVideo
import Foundation
import Metal
import Vision

/// Runs Vision on a source's frames in the background: face landmarks and/or
/// person segmentation. Results are in the source's normalized, top-left space.
public final class SourceAnalyzer {
    weak var source: VideoSource?
    private let queue = DispatchQueue(label: "dev.camtwizzle.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var busyFace = false
    private var busyMask = false
    private var lastFaceRun = 0.0
    private var lastMaskRun = 0.0
    private var _face = FaceInfo()
    private var _mask: CVPixelBuffer?
    private var smoothed: FaceInfo?
    private var lastSeen = 0.0
    public var faceInterval = 1.0 / 15
    public var maskInterval = 1.0 / 30
    public var maskQuality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced
    private lazy var segmentation: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = maskQuality
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()

    init(source: VideoSource) { self.source = source }

    func stop() {}

    public var face: FaceInfo {
        lock.lock(); defer { lock.unlock() }
        return _face
    }

    public var mask: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return _mask
    }

    /// Call once per rendered frame with what's needed; work is throttled and async.
    public func update(wantFace: Bool, wantMask: Bool, now: Double) {
        guard let frame = source?.currentFrame(), let pb = frame.pixelBuffer else { return }
        lock.lock()
        let runFace = wantFace && !busyFace && now - lastFaceRun >= faceInterval
        let runMask = wantMask && !busyMask && now - lastMaskRun >= maskInterval
        if runFace { busyFace = true; lastFaceRun = now }
        if runMask { busyMask = true; lastMaskRun = now }
        lock.unlock()
        if runFace { queue.async { self.detectFaces(pb, now: now) } }
        if runMask { queue.async { self.segment(pb) } }
    }

    /// One-shot analysis of a still image (used by the CLI and tests).
    public static func analyze(_ image: CGImage, face: Bool, mask: Bool) -> (FaceInfo, CVPixelBuffer?) {
        var info = FaceInfo()
        var m: CVPixelBuffer?
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        if face {
            let req = VNDetectFaceLandmarksRequest()
            if (try? handler.perform([req])) != nil { info = faceInfo(from: req.results ?? []) }
        }
        if mask {
            let req = VNGeneratePersonSegmentationRequest()
            req.qualityLevel = .accurate
            req.outputPixelFormat = kCVPixelFormatType_OneComponent8
            if (try? handler.perform([req])) != nil { m = req.results?.first?.pixelBuffer }
        }
        return (info, m)
    }

    private func detectFaces(_ pb: CVPixelBuffer, now: Double) {
        defer { lock.lock(); busyFace = false; lock.unlock() }
        let req = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        do { try handler.perform([req]) } catch { return }
        let info = SourceAnalyzer.faceInfo(from: req.results ?? [])
        updateFace(info, now: now)
    }

    static func faceInfo(from results: [VNFaceObservation]) -> FaceInfo {
        let faces = results.sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
        var info = FaceInfo()
        info.count = faces.count
        if let f = faces.first {
            let bb = f.boundingBox  // normalized, bottom-left origin
            info.rect = SIMD4(Float(bb.minX), Float(1 - bb.maxY), Float(bb.width), Float(bb.height))
            info.confidence = f.confidence
            info.roll = -(f.roll?.floatValue ?? 0)
            info.yaw = f.yaw?.floatValue ?? 0
            func centroid(_ region: VNFaceLandmarkRegion2D?) -> SIMD2<Float>? {
                guard let r = region, r.pointCount > 0 else { return nil }
                var sx = 0.0, sy = 0.0
                for p in r.normalizedPoints { sx += Double(p.x); sy += Double(p.y) }
                let px = bb.minX + (sx / Double(r.pointCount)) * bb.width
                let py = bb.minY + (sy / Double(r.pointCount)) * bb.height
                return SIMD2(Float(px), Float(1 - py))
            }
            let lm = f.landmarks
            // Vision's "left eye" is the subject's left (image right).
            if let l = centroid(lm?.leftEye) { info.rightEye = l }
            if let r = centroid(lm?.rightEye) { info.leftEye = r }
            if info.leftEye.x > info.rightEye.x { swap(&info.leftEye, &info.rightEye) }
            if let m = centroid(lm?.outerLips) { info.mouth = m }
            if let n = centroid(lm?.nose) { info.nose = n }
        }
        return info
    }

    private func updateFace(_ info: FaceInfo, now: Double) {
        lock.lock()
        if info.count > 0 {
            lastSeen = now
            // Light exponential smoothing to reduce jitter.
            if var s = smoothed {
                let a: Float = 0.55
                s.rect = s.rect + (info.rect - s.rect) * a
                s.leftEye = s.leftEye + (info.leftEye - s.leftEye) * a
                s.rightEye = s.rightEye + (info.rightEye - s.rightEye) * a
                s.mouth = s.mouth + (info.mouth - s.mouth) * a
                s.nose = s.nose + (info.nose - s.nose) * a
                s.roll = s.roll + (info.roll - s.roll) * a
                s.yaw = s.yaw + (info.yaw - s.yaw) * a
                s.count = info.count
                s.confidence = info.confidence
                smoothed = s
            } else {
                smoothed = info
            }
            _face = smoothed!
        } else if now - lastSeen > 0.6 {
            // Keep the last position briefly so effects don't flicker on missed detections.
            smoothed = nil
            _face.count = 0
        }
        lock.unlock()
    }

    private func segment(_ pb: CVPixelBuffer) {
        defer { lock.lock(); busyMask = false; lock.unlock() }
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        do { try handler.perform([segmentation]) } catch { return }
        guard let out = segmentation.results?.first?.pixelBuffer else { return }
        lock.lock(); _mask = out; lock.unlock()
    }
}
