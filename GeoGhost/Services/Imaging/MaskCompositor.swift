import CoreGraphics
import CoreImage
import Foundation

/// Combines masks from different sources (Vision instances, seed-point regions) at full image
/// resolution and renders previews / transparent cutouts from them.
enum MaskCompositor {
    /// Scale a mask covering the normalized `frame` (origin top-left) into full-photo pixel space.
    static func place(_ mask: CIImage, frame: CGRect, in size: CGSize) -> CIImage {
        let targetW = frame.width * size.width, targetH = frame.height * size.height
        let scaled = mask.transformed(by: .init(scaleX: targetW / mask.extent.width, y: targetH / mask.extent.height))
        // Core Image's origin is bottom-left.
        let tx = frame.minX * size.width - scaled.extent.minX
        let ty = (1 - frame.maxY) * size.height - scaled.extent.minY
        let moved = scaled.transformed(by: .init(translationX: tx, y: ty))
        // Pad to the full canvas with black so unions and blends line up.
        let canvas = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        return moved.composited(over: canvas).cropped(to: canvas.extent)
    }

    /// Union of masks already in full-photo pixel space (see `place`). Masks with other extents are scaled to fit.
    static func union(_ masks: [CIImage], size: CGSize) -> CIImage? {
        var acc: CIImage?
        let full = CGRect(origin: .zero, size: size)
        for m in masks {
            let fitted = m.extent == full ? m : m.transformed(by: .init(scaleX: size.width / m.extent.width, y: size.height / m.extent.height))
            acc = acc.map { fitted.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? fitted
        }
        return acc?.cropped(to: full)
    }

    /// Slightly soften an upscaled hard mask so cutout edges don't look stair-stepped.
    static func feathered(_ mask: CIImage, radius: Double) -> CIImage {
        mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: mask.extent)
    }

    /// Steepen a blurred/upscaled mask so the cutout edge is ~1–2 px wide instead of a soft ramp.
    static func sharpened(_ mask: CIImage) -> CIImage {
        let gain: CGFloat = 4
        let bias: CGFloat = -1.5
        return mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
    }

    /// Dimmed image with committed selection at full brightness and a tentative (still-held) selection tinted.
    static func preview(image: CGImage, mask: CIImage?, tentative: CIImage? = nil, tint: CIColor = CIColor(red: 1.0, green: 0.42, blue: 0.17), maxLongEdge: Int = 1280) -> CGImage? {
        let base = CIImage(cgImage: image)
        var out: CIImage = base
        if mask != nil || tentative != nil {
            let dimmed = base.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.6])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.45])
            out = dimmed
            if let mask {
                out = base.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: mask])
            }
            if let tentative {
                // Bright image washed with the accent colour so it reads as "not yet committed".
                let tinted = CIImage(color: CIColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 0.35)).cropped(to: base.extent).composited(over: base)
                out = tinted.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: tentative])
            }
        }
        let scale = min(1, CGFloat(maxLongEdge) / max(base.extent.width, base.extent.height))
        let scaled = out.transformed(by: .init(scaleX: scale, y: scale))
        return ImageProcessing.ciContext.createCGImage(scaled, from: scaled.extent.integral)
    }

    /// Transparent cutout of `image` under `mask`, cropped to `normalizedRect` (origin top-left).
    static func cutout(image: CGImage, mask: CIImage, normalizedRect r: CGRect) -> CGImage? {
        let base = CIImage(cgImage: image)
        let clear = CIImage(color: .clear).cropped(to: base.extent)
        let out = base.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
        let W = base.extent.width, H = base.extent.height
        // Core Image's origin is bottom-left.
        let crop = CGRect(x: r.minX * W, y: H - r.maxY * H, width: r.width * W, height: r.height * H).integral.intersection(base.extent)
        guard !crop.isEmpty else { return nil }
        return ImageProcessing.ciContext.createCGImage(out, from: crop, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
