import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Drives one capture: photo → segmentation → selection → save.
@Observable
@MainActor
final class CaptureFlowModel {
    enum Stage: Equatable {
        case camera
        case analyzing
        case editing
        case manualCrop
        case failed(String)
    }

    private(set) var stage: Stage = .camera

    /// Encoded original bytes (HEIC/JPEG) with EXIF.
    private(set) var originalData: Data?
    private(set) var originalExtension = "heic"
    private(set) var fullImage: CGImage?
    private(set) var metadata = CaptureMetadata()

    private(set) var analysis: SegmentationAnalysis?
    /// Vision instances currently selected.
    private(set) var selection = IndexSet()
    /// Regions grown from the user's long-presses (used when Vision has no instance at that point).
    private(set) var pointRegions: [PointSegmentation] = []
    /// Ordered history so Undo can pop either kind of selection.
    private enum SelectionStep { case instance(Int), region }
    private var history: [SelectionStep] = []
    private(set) var previewImage: CGImage?
    private(set) var isRenderingPreview = false
    private(set) var isPicking = false
    private(set) var lastPickFailed = false
    /// The most recently added piece, rendered alone so the editor can animate it.
    struct PickHighlight: Identifiable { let id = UUID(); let image: CGImage; let rect: CGRect }
    private(set) var lastPickHighlight: PickHighlight?
    private var selectionWasAdjusted = false

    /// Final cutout ready for saving.
    private(set) var cutout: CGImage?
    private(set) var cutoutRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private(set) var segmentationMode: SegmentationMode = .auto
    var showSaveSheet = false

    // MARK: Input

    /// Photo from the in-app camera: sensor metadata is authoritative, EXIF fills the rest.
    func receiveCameraPhoto(_ data: Data, sensor: CaptureMetadata) {
        let exif = ImageMetadataReader.read(data)
        var m = sensor.merging(fallback: exif)
        if m.locationSource == .none, exif.coordinate != nil { m.locationSource = .exif }
        begin(data: data, metadata: m, ext: Self.fileExtension(for: data))
    }

    /// Photo picked from the library: EXIF is all we have.
    func receiveImportedPhoto(_ data: Data) {
        var m = ImageMetadataReader.read(data)
        if m.capturedAt == nil { m.capturedAt = Date(); m.capturedAtIsEstimated = true }
        begin(data: data, metadata: m, ext: Self.fileExtension(for: data))
    }

    private func begin(data: Data, metadata: CaptureMetadata, ext: String) {
        originalData = data
        originalExtension = ext
        self.metadata = metadata
        stage = .analyzing
        Task.detached(priority: .userInitiated) { [data] in
            // Segment on a bounded-size copy; masks are generated at this resolution.
            guard let image = ImageProcessing.decodeUpright(data, maxPixelSize: 3000) else {
                await MainActor.run { self.stage = .failed(String(localized: "The photo could not be decoded.")) }
                return
            }
            let result: Result<SegmentationAnalysis, Error> = Result { try SegmentationService.analyze(image) }
            await MainActor.run {
                self.fullImage = image
                if self.metadata.pixelWidth == 0 { self.metadata.pixelWidth = image.width; self.metadata.pixelHeight = image.height }
                self.analysis = try? result.get()
                self.selection = self.analysis?.hasInstances == true ? self.analysis!.defaultSelection() : []
                self.pointRegions = []
                self.history = []
                self.selectionWasAdjusted = false
                self.stage = .editing
                self.refreshPreview()
            }
        }
    }

    // MARK: Editing

    /// Whether anything is selected (Vision instances or grown regions).
    var hasSelection: Bool { !selection.isEmpty || !pointRegions.isEmpty }
    var canUndo: Bool { !history.isEmpty }

    /// Vision instances larger than this share of the frame are probably the wall/pole, not the piece.
    private let largeInstanceArea = 0.35

    /// Pick whatever is under a normalized point.
    ///
    /// Order of preference: a point region the user already added (hold again → remove) · a Vision
    /// instance that isn't selected yet (select it, unless it's huge — then try to grow a smaller region
    /// first) · a Vision instance that *is* selected (drill down: replace it with the region under the
    /// finger, so a sticker sitting on a detected pole can still be isolated) · grow a region.
    func pick(atNormalized point: CGPoint) {
        lastPickFailed = false
        guard let fullImage, !isPicking else { return }

        if let regionIndex = pointRegions.lastIndex(where: { $0.contains(point) }) {
            pointRegions.remove(at: regionIndex)
            if let h = history.lastIndex(where: { if case .region = $0 { return true }; return false }) { history.remove(at: h) }
            selectionWasAdjusted = true
            refreshPreview()
            return
        }

        let instance = analysis?.instance(atNormalized: point)
        if let analysis, let idx = instance {
            let instanceArea = analysis.area(of: [idx])
            let alreadySelected = selection.contains(idx)
            if !alreadySelected && instanceArea < largeInstanceArea {
                select(instance: idx, in: analysis)
                return
            }
            // Selected already, or suspiciously large: try to isolate the smaller piece under the finger.
            growRegion(at: point, in: fullImage) { [weak self] region in
                guard let self else { return }
                if let region, region.area < instanceArea * 0.6 {
                    if alreadySelected { self.deselect(instance: idx) }
                    self.add(region: region)
                } else if alreadySelected {
                    self.deselect(instance: idx)
                    self.refreshPreview()
                } else {
                    self.select(instance: idx, in: analysis)
                }
            }
            return
        }

        growRegion(at: point, in: fullImage) { [weak self] region in
            guard let self else { return }
            if let region { self.add(region: region) } else { self.lastPickFailed = true }
        }
    }

    private func select(instance idx: Int, in analysis: SegmentationAnalysis) {
        selection.insert(idx)
        history.append(.instance(idx))
        if let buffer = try? analysis.scaledMask(for: [idx]), let rect = analysis.boundingRect(of: [idx]) {
            makeHighlight(mask: CIImage(cvPixelBuffer: buffer), rect: rect)
        }
        selectionWasAdjusted = true
        refreshPreview()
    }

    private func deselect(instance idx: Int) {
        selection.remove(idx)
        history.removeAll { if case .instance(let i) = $0 { return i == idx }; return false }
        selectionWasAdjusted = true
    }

    private func add(region: PointSegmentation) {
        pointRegions.append(region)
        history.append(.region)
        selectionWasAdjusted = true
        makeHighlight(mask: MaskCompositor.sharpened(MaskCompositor.feathered(CIImage(cgImage: region.mask), radius: 1.0)), rect: region.boundingRect)
        refreshPreview()
    }

    private func growRegion(at point: CGPoint, in image: CGImage, completion: @escaping @MainActor (PointSegmentation?) -> Void) {
        isPicking = true
        Task.detached(priority: .userInitiated) {
            let region = PointSegmenter.segment(image: image, atNormalized: point)
            await MainActor.run {
                self.isPicking = false
                completion(region)
            }
        }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        switch last {
        case .instance(let i): selection.remove(i)
        case .region: if !pointRegions.isEmpty { pointRegions.removeLast() }
        }
        refreshPreview()
    }

    func clearSelection() {
        selection = []
        pointRegions = []
        history = []
        selectionWasAdjusted = true
        refreshPreview()
    }

    func selectAll() {
        guard let analysis else { return }
        selection = analysis.allInstances
        selectionWasAdjusted = true
        refreshPreview()
    }

    var instanceCount: Int { analysis?.allInstances.count ?? 0 }
    var selectedArea: Double { (analysis?.area(of: selection) ?? 0) + pointRegions.reduce(0) { $0 + $1.area } }

    /// Full-resolution union mask of everything selected.
    private func combinedMask() -> CIImage? {
        guard let fullImage else { return nil }
        var parts: [CIImage] = []
        if let analysis, !selection.isEmpty, let buffer = try? analysis.scaledMask(for: selection) {
            parts.append(CIImage(cvPixelBuffer: buffer))
        }
        let size = CGSize(width: fullImage.width, height: fullImage.height)
        if !pointRegions.isEmpty {
            // Upscale the hard low-res masks, blur to interpolate, then steepen so edges stay crisp.
            let regions = pointRegions.map { CIImage(cgImage: $0.mask) }
            if let u = MaskCompositor.union(regions, size: size) {
                parts.append(MaskCompositor.sharpened(MaskCompositor.feathered(u, radius: 2.5)))
            }
        }
        guard !parts.isEmpty else { return nil }
        return MaskCompositor.union(parts, size: size).map { MaskCompositor.feathered($0, radius: 0.7) }
    }

    private func selectionBounds() -> CGRect? {
        var rects: [CGRect] = []
        if let analysis, !selection.isEmpty, let r = analysis.boundingRect(of: selection) { rects.append(r) }
        rects += pointRegions.map(\.boundingRect)
        guard var u = rects.first else { return nil }
        for r in rects.dropFirst() { u = u.union(r) }
        // Small margin so feathered edges aren't clipped.
        return u.insetBy(dx: -0.004, dy: -0.004).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Render just the newly picked piece at preview resolution for the pop animation.
    private func makeHighlight(mask: CIImage, rect: CGRect) {
        guard let fullImage else { return }
        Task.detached(priority: .userInitiated) {
            let small = ImageProcessing.downsample(fullImage, maxLongEdge: 1280)
            let size = CGSize(width: small.width, height: small.height)
            guard let scaled = MaskCompositor.union([mask], size: size),
                  let cg = MaskCompositor.cutout(image: small, mask: scaled, normalizedRect: rect) else { return }
            await MainActor.run { self.lastPickHighlight = PickHighlight(image: cg, rect: rect) }
        }
    }

    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0
    private func refreshPreview() {
        guard let fullImage else { return }
        previewGeneration += 1
        let gen = previewGeneration
        let mask = combinedMask()
        previewTask?.cancel()
        isRenderingPreview = true
        previewTask = Task.detached(priority: .userInitiated) {
            let img = MaskCompositor.preview(image: fullImage, mask: mask)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.previewGeneration == gen { self.previewImage = img; self.isRenderingPreview = false }
            }
        }
    }

    func switchToManualCrop() {
        stage = .manualCrop
    }

    func backToAutomatic() {
        if fullImage != nil { stage = .editing; refreshPreview() }
    }

    // MARK: Finalize

    /// Render the selection into a transparent cutout and open the save sheet.
    func finishAutomatic() async {
        guard let fullImage, let mask = combinedMask(), let rect = selectionBounds() else { return }
        let adjusted = selectionWasAdjusted
        let cg = await Task.detached(priority: .userInitiated) {
            MaskCompositor.cutout(image: fullImage, mask: mask, normalizedRect: rect)
        }.value
        guard let cg else { stage = .failed(SegmentationError.renderFailed.localizedDescription); return }
        cutout = cg
        cutoutRect = rect
        segmentationMode = adjusted ? .autoAdjusted : .auto
        showSaveSheet = true
    }

    /// Crop the full image by a normalized rect (opaque result).
    func finishManualCrop(normalizedRect rect: CGRect) {
        guard let fullImage, let cg = ImageProcessing.crop(fullImage, normalized: rect) else { return }
        cutout = cg
        cutoutRect = rect
        segmentationMode = .manualCrop
        showSaveSheet = true
    }

    func reset() {
        stage = .camera
        originalData = nil
        fullImage = nil
        analysis = nil
        selection = []
        pointRegions = []
        history = []
        lastPickHighlight = nil
        previewImage = nil
        cutout = nil
        metadata = CaptureMetadata()
        showSaveSheet = false
    }

    /// Whether the chosen subject touches ≥ 3 edges → probably a whole wall (mural).
    var coversMostOfFrame: Bool {
        let r = cutoutRect
        var edges = 0
        if r.minX <= 0.02 { edges += 1 }
        if r.minY <= 0.02 { edges += 1 }
        if r.maxX >= 0.98 { edges += 1 }
        if r.maxY >= 0.98 { edges += 1 }
        return edges >= 3 || (r.width * r.height) > 0.85
    }

    nonisolated static func fileExtension(for data: Data) -> String {
        guard data.count >= 12 else { return "jpg" }
        let b = [UInt8](data.prefix(12))
        if b[0] == 0xFF && b[1] == 0xD8 { return "jpg" }
        if b[0] == 0x89 && b[1] == 0x50 { return "png" }
        if b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70 { return "heic" }
        return "jpg"
    }
}
