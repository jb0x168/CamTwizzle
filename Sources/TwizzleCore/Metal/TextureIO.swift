import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

public enum TextureIO {
    /// Read back a texture (any of bgra8/rgba8/rgba16f) as a CGImage. Blocks until the GPU is done.
    public static func cgImage(from texture: MTLTexture, metal: MetalContext) -> CGImage? {
        let w = texture.width, h = texture.height
        // Normalize to bgra8 via a render pass so we can handle any format.
        let staging: MTLTexture = {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            return metal.device.makeTexture(descriptor: d)!
        }()
        guard let cb = metal.queue.makeCommandBuffer() else { return nil }
        metal.encodeInternal("twz_copy", cb: cb, target: staging, textures: [texture], uniforms: [SIMD4(0, 0, 0, 0)])
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PluginError.unsupported("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw PluginError.unsupported("cannot finalize \(url.path)") }
    }

    public static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Load an image file into a private bgra8 texture, scaled to the given size (aspect fill).
    public static func loadTexture(_ url: URL, width: Int, height: Int, metal: MetalContext) -> MTLTexture? {
        guard let img = loadCGImage(url) else { return nil }
        return texture(from: img, width: width, height: height, metal: metal)
    }

    public static func texture(from img: CGImage, width: Int, height: Int, metal: MetalContext) -> MTLTexture? {
        let bpr = width * 4
        var data = [UInt8](repeating: 0, count: bpr * height)
        data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            ctx.interpolationQuality = .high
            let s = max(Double(width) / Double(img.width), Double(height) / Double(img.height))
            let dw = Double(img.width) * s, dh = Double(img.height) * s
            ctx.draw(img, in: CGRect(x: (Double(width) - dw) / 2, y: (Double(height) - dh) / 2, width: dw, height: dh))
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        guard let tex = metal.device.makeTexture(descriptor: d) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: bpr)
        return tex
    }
}
