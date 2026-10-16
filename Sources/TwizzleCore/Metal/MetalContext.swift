import CoreImage
import CoreVideo
import Foundation
import Metal

/// Shared GPU state: device, queue, Core Image context, texture cache/pool
/// and the engine's internal render pipelines.
public final class MetalContext {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public let ciContext: CIContext
    public let pool: TexturePool
    public let textureCache: CVMetalTextureCache
    /// Default pixel format for intermediate images.
    public let workingFormat: MTLPixelFormat = .bgra8Unorm

    private let internalLibrary: MTLLibrary
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private let pipelineLock = NSLock()
    public let vertexFunction: MTLFunction

    /// 1×1 helper textures.
    public private(set) var whiteTexture: MTLTexture!
    public private(set) var clearTexture: MTLTexture!
    public private(set) var blackTexture: MTLTexture!

    public static let shared: MetalContext = {
        do { return try MetalContext() } catch { fatalError("Metal unavailable: \(error)") }
    }()

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw PluginError.unsupported("no Metal device") }
        self.device = device
        guard let queue = device.makeCommandQueue(maxCommandBufferCount: 32) else { throw PluginError.unsupported("no command queue") }
        queue.label = "CamTwizzle"
        self.queue = queue
        ciContext = CIContext(mtlCommandQueue: queue, options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false,
            .name: "CamTwizzle",
        ])
        pool = TexturePool(device: device)
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let cache else { throw PluginError.unsupported("no texture cache") }
        textureCache = cache
        internalLibrary = try device.makeLibrary(source: InternalShaders.source, options: nil)
        guard let vf = internalLibrary.makeFunction(name: "twz_fullscreen_vertex") else {
            throw PluginError.unsupported("internal vertex function missing")
        }
        vertexFunction = vf
        whiteTexture = makeSolidTexture([255, 255, 255, 255])
        clearTexture = makeSolidTexture([0, 0, 0, 0])
        blackTexture = makeSolidTexture([0, 0, 0, 255])
    }

    private func makeSolidTexture(_ bgra: [UInt8]) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        let t = device.makeTexture(descriptor: d)!
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bgra, bytesPerRow: 4)
        return t
    }

    /// Pipeline for one of the internal fragment functions.
    public func internalPipeline(_ fragment: String, format: MTLPixelFormat, blending: Bool = false) -> MTLRenderPipelineState? {
        let key = "\(fragment)|\(format.rawValue)|\(blending)"
        pipelineLock.lock(); defer { pipelineLock.unlock() }
        if let p = pipelines[key] { return p }
        guard let ff = internalLibrary.makeFunction(name: fragment) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vertexFunction
        d.fragmentFunction = ff
        d.colorAttachments[0].pixelFormat = format
        if blending {
            let a = d.colorAttachments[0]!
            a.isBlendingEnabled = true
            a.sourceRGBBlendFactor = .sourceAlpha
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.sourceAlphaBlendFactor = .one
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipelines[key] = p
            return p
        } catch {
            TwzLog.error("pipeline \(fragment): \(error)")
            return nil
        }
    }

    /// Make a render pipeline for a user fragment function, pairing it with the shared vertex function.
    public func makePipeline(fragment: MTLFunction, vertex: MTLFunction? = nil, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vertex ?? vertexFunction
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: d)
    }

    public func makeTexture(width: Int, height: Int, format: MTLPixelFormat? = nil, label: String? = nil) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format ?? workingFormat, width: max(1, width), height: max(1, height), mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite, .renderTarget]
        d.storageMode = .private
        let t = device.makeTexture(descriptor: d)!
        t.label = label
        return t
    }

    /// Wrap a CVPixelBuffer as a Metal texture (zero copy). Keep the returned
    /// CVMetalTexture alive until the GPU is done with the texture.
    public func texture(from pixelBuffer: CVPixelBuffer, plane: Int = 0, format: MTLPixelFormat = .bgra8Unorm) -> (MTLTexture, CVMetalTexture)? {
        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) > 0 ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) > 0 ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, format, w, h, plane, &cvTex)
        guard status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return nil }
        return (tex, cvTex)
    }

    /// Encode a fullscreen pass with one of the internal fragment functions.
    public func encodeInternal(_ fragment: String, cb: MTLCommandBuffer, target: MTLTexture, textures: [MTLTexture?],
                               uniforms: [SIMD4<Float>] = [], clear: MTLClearColor? = nil, blending: Bool = false, label: String? = nil) {
        guard let pipeline = internalPipeline(fragment, format: target.pixelFormat, blending: blending) else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        if let clear {
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = clear
        } else {
            rp.colorAttachments[0].loadAction = blending ? .load : .dontCare
        }
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.label = label ?? fragment
        enc.setRenderPipelineState(pipeline)
        for (i, t) in textures.enumerated() { enc.setFragmentTexture(t ?? clearTexture, index: i) }
        var u = uniforms.isEmpty ? [SIMD4<Float>.zero] : uniforms
        enc.setFragmentBytes(&u, length: MemoryLayout<SIMD4<Float>>.stride * u.count, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// CIImage for a texture, in Core Image's bottom-left-origin convention.
    public func ciImage(from texture: MTLTexture) -> CIImage {
        let img = CIImage(mtlTexture: texture, options: [.colorSpace: NSNull()])!
        // Metal textures are top-left origin; flip so CI sees the image upright.
        return img.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(texture.height)))
    }

    /// Render a CIImage (bottom-left origin) into a texture (top-left origin).
    public func render(_ image: CIImage, to texture: MTLTexture, cb: MTLCommandBuffer) {
        let h = CGFloat(texture.height)
        let flipped = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h))
        let bounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        ciContext.render(flipped, to: texture, commandBuffer: cb, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }
}

/// Reuses intermediate textures by size/format. Textures may be released as soon
/// as their last reader has been *encoded*: Metal's hazard tracking orders the
/// GPU work within (and across) command buffers on the same queue.
public final class TexturePool {
    let device: MTLDevice
    private var free: [Key: [MTLTexture]] = [:]
    private let lock = NSLock()
    private var outstanding = 0

    struct Key: Hashable { let w: Int, h: Int, f: UInt }

    init(device: MTLDevice) { self.device = device }

    public func acquire(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture {
        let key = Key(w: max(1, width), h: max(1, height), f: format.rawValue)
        lock.lock()
        outstanding += 1
        if var list = free[key], let t = list.popLast() {
            free[key] = list
            lock.unlock()
            return t
        }
        lock.unlock()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: key.w, height: key.h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite, .renderTarget]
        d.storageMode = .private
        let t = device.makeTexture(descriptor: d)!
        t.label = "pool \(key.w)x\(key.h)"
        return t
    }

    public func release(_ t: MTLTexture?) {
        guard let t else { return }
        let key = Key(w: t.width, h: t.height, f: t.pixelFormat.rawValue)
        lock.lock()
        outstanding -= 1
        var list = free[key] ?? []
        if !list.contains(where: { $0 === t }) {
            if list.count < 12 { list.append(t) }
            free[key] = list
        }
        lock.unlock()
    }

    /// Drop all cached textures (e.g. after a resolution change).
    public func purge() {
        lock.lock(); free.removeAll(); lock.unlock()
    }

    public var stats: (cached: Int, outstanding: Int) {
        lock.lock(); defer { lock.unlock() }
        return (free.values.reduce(0) { $0 + $1.count }, outstanding)
    }
}
