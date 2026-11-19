// Checks that Apple Vision can cut the target sticker out of each coaching sample, the way the editor does:
// VNGenerateForegroundInstanceMaskRequest, default pick = instance under the frame centre, else the largest
// (SegmentationAnalysis.defaultSelection), or the instance under a tap at the target's centre.
// Runs on macOS (the simulator has no Vision segmentation models); a real iPhone can still differ.
//
// Usage: swift scripts/check-coaching-cutout.swift CoachingSamples/brand
//   expects <name>.jpg + <name>-mask.png (from make-coaching-samples.swift) and samples.json
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "CoachingSamples/brand")

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

/// Grayscale 0/1 mask at w×h (thresholded at 0.5).
func binary(_ img: CGImage, w: Int, h: Int) -> [Bool] {
    var bytes = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return bytes.map { $0 >= 128 }
}

func iou(_ a: [Bool], _ b: [Bool]) -> Double {
    var i = 0, u = 0
    for k in a.indices { if a[k] && b[k] { i += 1 }; if a[k] || b[k] { u += 1 } }
    return u == 0 ? 0 : Double(i) / Double(u)
}

let meta = (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("samples.json")))) as? [[String: Any]] ?? []
var failures = 0

for m in meta {
    let name = m["name"] as! String
    let image = load(dir.appendingPathComponent("\(name).jpg"))
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])
    guard let obs = request.results?.first else { print("\(name): no instances"); failures += 1; continue }

    let buffer = obs.instanceMask
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let mw = CVPixelBufferGetWidth(buffer), mh = CVPixelBufferGetHeight(buffer), rb = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var labels = [UInt8](repeating: 0, count: mw * mh)
    for y in 0..<mh { for x in 0..<mw { labels[y * mw + x] = base[y * rb + x] } }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

    let truth = binary(load(dir.appendingPathComponent("\(name)-mask.png")), w: mw, h: mh)
    func mask(_ set: Set<Int>) -> [Bool] { labels.map { set.contains(Int($0)) } }
    func label(at p: CGPoint) -> Int? {
        let l = Int(labels[min(mh - 1, Int(p.y * CGFloat(mh))) * mw + min(mw - 1, Int(p.x * CGFloat(mw)))])
        return l == 0 ? nil : l
    }

    print("\n\(name)  (\(image.width)×\(image.height), mask \(mw)×\(mh), target \(m["target"] as! String))")
    var best = (label: 0, iou: 0.0)
    for l in obs.allInstances.sorted() {
        let mk = mask([l])
        let area = Double(mk.filter { $0 }.count) / Double(mw * mh)
        let v = iou(mk, truth)
        if v > best.iou { best = (l, v) }
        print(String(format: "  instance %d: area %5.1f%%  IoU vs target %.3f", l, area * 100, v))
    }
    // Default pick, as in SegmentationAnalysis.defaultSelection.
    var def = label(at: CGPoint(x: 0.5, y: 0.5))
    if def == nil {
        def = obs.allInstances.max { a, b in mask([a]).filter { $0 }.count < mask([b]).filter { $0 }.count }
    }
    let tap = m["tapPoint"] as! [Double]
    let tapLabel = label(at: CGPoint(x: tap[0], y: tap[1]))
    let defIoU = def.map { iou(mask([$0]), truth) } ?? 0
    let tapIoU = tapLabel.map { iou(mask([$0]), truth) } ?? 0
    print(String(format: "  default pick: %@ → IoU %.3f", def.map(String.init) ?? "none", defIoU))
    print(String(format: "  tap at target centre (%.2f, %.2f): %@ → IoU %.3f", tap[0], tap[1], tapLabel.map(String.init) ?? "background", tapIoU))
    print(String(format: "  best single instance: %d → IoU %.3f", best.label, best.iou))
    // ① must work on the default pick; the others when the target is tapped.
    let ok = name.hasPrefix("1-") ? defIoU >= 0.9 : tapIoU >= 0.9
    print("  " + (ok ? "PASS" : "FAIL"))
    if !ok { failures += 1 }
}
exit(failures == 0 ? 0 : 1)
