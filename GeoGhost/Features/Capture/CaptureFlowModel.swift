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
    private(set) var selection = IndexSet()
    private(set) var previewImage: CGImage?
    private(set) var isRenderingPreview = false
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
                switch result {
                case .success(let analysis) where analysis.hasInstances:
                    self.analysis = analysis
                    self.selection = analysis.defaultSelection()
                    self.selectionWasAdjusted = false
                    self.stage = .editing
                    self.refreshPreview()
                default:
                    self.analysis = nil
                    self.stage = .manualCrop
                }
            }
        }
    }

    // MARK: Editing

    func toggleInstance(atNormalized point: CGPoint) {
        guard let analysis, let idx = analysis.instance(atNormalized: point) else { return }
        if selection.contains(idx) {
            if selection.count > 1 { selection.remove(idx) }
        } else {
            selection.insert(idx)
        }
        selectionWasAdjusted = true
        refreshPreview()
    }

    func selectOnly(atNormalized point: CGPoint) {
        guard let analysis, let idx = analysis.instance(atNormalized: point) else { return }
        selection = [idx]
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
    var selectedArea: Double { analysis?.area(of: selection) ?? 0 }

    private var previewTask: Task<Void, Never>?
    private func refreshPreview() {
        guard let analysis else { return }
        let sel = selection
        previewTask?.cancel()
        isRenderingPreview = true
        previewTask = Task.detached(priority: .userInitiated) {
            let img = try? analysis.previewComposite(selected: sel)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.selection == sel { self.previewImage = img; self.isRenderingPreview = false }
            }
        }
    }

    func switchToManualCrop() {
        stage = .manualCrop
    }

    func backToAutomatic() {
        if analysis != nil { stage = .editing; refreshPreview() }
    }

    // MARK: Finalize

    /// Render the selected instances into a transparent cutout and open the save sheet.
    func finishAutomatic() async {
        guard let analysis else { return }
        let sel = selection
        let adjusted = selectionWasAdjusted
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage, CGRect)? in
            guard let cg = try? analysis.cutout(for: sel) else { return nil }
            let rect = analysis.boundingRect(of: sel) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            return (cg, rect)
        }.value
        guard let (cg, rect) = result else { stage = .failed(SegmentationError.renderFailed.localizedDescription); return }
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
