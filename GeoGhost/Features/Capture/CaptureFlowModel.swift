import CoreGraphics
import Foundation
import Observation
import os
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

    /// Whole-photo Vision analysis (may have zero instances).
    private(set) var analysis: SegmentationAnalysis?
    /// Vision analysis of the current zoomed viewport, when zoomed in far enough to matter.
    private(set) var scopedAnalysis: SegmentationAnalysis?
    private var fullPrepared: PointSegmenter.Prepared?
    private var scopedPrepared: PointSegmenter.Prepared?
    private(set) var viewport = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var viewportTask: Task<Void, Never>?
    private(set) var isAnalyzingViewport = false

    /// Committed selection.
    private(set) var pieces: [SelectedPiece] = []
    /// Regions already saved as artworks from this photo (this session or earlier); shown ghosted, not selectable.
    private(set) var savedRegions: [CGRect] = []
    /// Artworks saved from this photo during this editing session.
    private(set) var savedCount = 0
    /// Lasso in progress / just completed (normalized full-photo points), for the overlay.
    private(set) var lassoPoints: [CGPoint] = []
    private var undoStack: [[SelectedPiece]] = []
    private var selectionWasAdjusted = false

    /// In-progress hold gesture.
    struct Hold {
        enum Axis { case undecided, horizontal, vertical }
        enum Intent { case add, replace, discard, delete, expand }
        var origin: CGPoint
        /// Piece already under the finger when the hold began (drill / delete target).
        var target: SelectedPiece?
        var tentative: SelectedPiece?
        var axis: Axis = .undecided
        var intent: Intent
        var tolerance: Float = PointSegmenter.Parameters().colorTolerance
        var layers: Int = PointSegmenter.Parameters().expansionLayers
        var usesRegion = false
        var failed = false
    }
    private(set) var hold: Hold?
    private var holdGeneration = 0
    private var holdTask: Task<Void, Never>?
    /// A hold released before its tentative result arrived: commit the result when it lands.
    private var pendingCommit: (generation: Int, hold: Hold)?

    private(set) var previewImage: CGImage?
    private(set) var isRenderingPreview = false
    private(set) var isPicking = false
    private(set) var lastPickFailed = false
    /// The most recently committed piece, rendered alone so the editor can animate it.
    struct PickHighlight: Identifiable { let id = UUID(); let image: CGImage; let rect: CGRect }
    private(set) var lastPickHighlight: PickHighlight?
    /// The tentative piece rendered for the "lift" effect: original colours plus a white edge ring.
    struct TentativeVisual: Identifiable { let id: UUID; let cutout: CGImage; let outline: CGImage; let rect: CGRect }
    private(set) var tentativeVisual: TentativeVisual?
    private var tentativeVisualTask: Task<Void, Never>?

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

    /// Re-open a saved artwork's original photo to pick more pieces from it.
    func receiveStoredPhoto(_ data: Data, metadata: CaptureMetadata, alreadySaved: [CGRect]) {
        var m = metadata.merging(fallback: ImageMetadataReader.read(data))
        if m.capturedAt == nil { m.capturedAt = Date(); m.capturedAtIsEstimated = true }
        savedRegions = alreadySaved
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
                self.pieces = []
                if let a = self.analysis, a.hasInstances, let idx = a.defaultSelection().first {
                    let piece = SelectedPiece(vision: a, instance: idx)
                    if !self.isSaved(piece.rect) { self.pieces = [piece] }
                }
                self.undoStack = []
                self.selectionWasAdjusted = false
                self.stage = .editing
                self.refreshPreview()
            }
            // Region-growing preprocessing for the whole photo, ready before the first hold.
            let prepared = PointSegmenter.Prepared(image: image)
            await MainActor.run { self.fullPrepared = prepared }
        }
    }

    // MARK: Editing

    var hasSelection: Bool { !pieces.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var instanceCount: Int { (scopedAnalysis ?? analysis)?.allInstances.count ?? 0 }
    var selectedArea: Double { pieces.reduce(0) { $0 + $1.area } }

    /// Vision instances larger than this share of the frame are probably the wall/pole, not the piece.
    private let largeInstanceArea = 0.35

    // MARK: Viewport → scoped analysis

    /// Called by the editor whenever the zoom/pan settles. Re-runs Vision on the visible crop so small
    /// pieces the whole-photo pass missed become instances, and scopes region growth to what's on screen.
    func setViewport(_ visible: CGRect) {
        let clamped = visible.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard clamped != viewport, let fullImage else { return }
        viewport = clamped
        viewportTask?.cancel()
        let area = clamped.width * clamped.height
        if area >= 0.9 {
            scopedAnalysis = nil
            scopedPrepared = nil
            isAnalyzingViewport = false
            return
        }
        isAnalyzingViewport = true
        viewportTask = Task.detached(priority: .userInitiated) {
            let analysis = try? SegmentationService.analyze(fullImage, frame: clamped)
            let prepared = PointSegmenter.Prepared(image: fullImage, frame: clamped)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.viewport == clamped else { return }
                self.scopedAnalysis = analysis
                self.scopedPrepared = prepared
                self.isAnalyzingViewport = false
            }
        }
    }

    private var activePrepared: PointSegmenter.Prepared? { scopedPrepared ?? fullPrepared }

    /// Vision instance under a point: the zoomed-in analysis wins over the whole-photo one.
    private func visionCandidate(at p: CGPoint) -> SelectedPiece? {
        for a in [scopedAnalysis, analysis].compactMap({ $0 }) {
            if let idx = a.instance(atNormalized: p) { return SelectedPiece(vision: a, instance: idx) }
        }
        return nil
    }

    // MARK: Saved regions (multiple pieces per photo)

    /// A candidate whose bounds mostly sit inside an already-saved region is that saved piece.
    private func isSaved(_ rect: CGRect) -> Bool {
        savedRegions.contains { saved in
            let inter = saved.intersection(rect)
            guard !inter.isEmpty, rect.width * rect.height > 0 else { return false }
            return (inter.width * inter.height) / (rect.width * rect.height) > 0.7
        }
    }

    /// After a save that keeps the editor open: ghost what was saved and start a fresh selection.
    func markSaved() {
        savedRegions += pieces.map(\.rect)
        savedCount += 1
        pieces = []
        undoStack = []
        cutout = nil
        showSaveSheet = false
        refreshPreview()
    }

    // MARK: Lasso (draw a loop around the piece)

    func lassoChanged(_ points: [CGPoint]) { lassoPoints = points }

    /// Close the loop and select what's inside: Vision instances that sit inside it, else a
    /// background-model segmentation of the interior.
    func lassoEnded(_ points: [CGPoint]) {
        lassoPoints = []
        let log = Logger(subsystem: "com.passerbo.geoghost", category: "Lasso")
        log.info("lasso ended with \(points.count) points")
        guard let fullImage, points.count >= 8 else { return }
        lastPickFailed = false
        // Simplify to ≤ 64 vertices.
        let step = max(1, points.count / 64)
        let polygon = stride(from: 0, to: points.count, by: step).map { points[$0] }
        var bbox = polygon.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        guard bbox.width > 0.01, bbox.height > 0.01 else { return }
        bbox = bbox.insetBy(dx: -bbox.width * 0.15, dy: -bbox.height * 0.15).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let prepared = activePrepared
        let scopedInside = prepared.map { $0.frame.contains(bbox) } ?? false
        log.info("bbox \(bbox.debugDescription, privacy: .public) prepared=\(prepared != nil) scopedInside=\(scopedInside) image \(fullImage.width)x\(fullImage.height)")
        isPicking = true
        Task.detached(priority: .userInitiated) {
            var result: [SelectedPiece] = []
            // 1. Vision on a crop around the loop: instances that are ≥ 80% inside the loop.
            if let a = try? SegmentationService.analyze(fullImage, frame: bbox), a.hasInstances {
                let cov = a.coverage(insidePolygon: polygon)
                let picked = IndexSet(cov.filter { $0.value >= 0.8 }.map(\.key))
                let loopArea = Double(bbox.width * bbox.height) * 0.7
                if !picked.isEmpty, a.area(of: picked) >= loopArea * 0.15 {
                    result = picked.map { SelectedPiece(vision: a, instance: $0) }
                }
            }
            // 2. Background-model segmentation inside the loop.
            if result.isEmpty {
                let prep = scopedInside ? prepared : PointSegmenter.Prepared(image: fullImage, frame: bbox)
                log.info("prep \(prep?.width ?? -1)x\(prep?.height ?? -1) frame \(prep?.frame.debugDescription ?? "nil", privacy: .public)")
                if let prep, let region = LassoSegmenter.segment(prep, polygon: polygon) {
                    log.info("lasso region area \(region.area)")
                    result = [SelectedPiece(region: region)]
                } else {
                    log.info("lasso segmentation returned nil")
                }
            }
            await MainActor.run {
                self.isPicking = false
                guard !result.isEmpty else { self.lastPickFailed = true; return }
                var next = self.pieces
                next.append(contentsOf: result)
                self.commit(next)
                if let last = result.last { self.makeHighlight(for: last) }
                self.refreshPreview()
            }
        }
    }

    // MARK: Hold gesture (press = try, release = commit, swipe down = throw away)

    func beginHold(at p: CGPoint) {
        guard fullImage != nil else { return }
        lastPickFailed = false
        pendingCommit = nil
        if savedRegions.contains(where: { $0.contains(p) }) && !pieces.contains(where: { $0.contains(p) }) {
            lastPickFailed = true   // already saved from this photo
            return
        }
        let target = pieces.last { $0.contains(p) }
        var h = Hold(origin: p, target: target, intent: target == nil ? .add : .replace)
        // Drilling into an existing piece always uses region growth (that's what "smaller" means here).
        h.usesRegion = target != nil
        hold = h
        computeTentative()
    }

    /// `translation` in screen points since the hold began.
    func updateHold(translation t: CGSize) {
        guard var h = hold else { return }
        if h.axis == .undecided {
            guard hypot(t.width, t.height) > 12 else { return }
            h.axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
        }
        switch h.axis {
        case .horizontal:
            // Right loosens, left tightens. Full travel ≈ 240 pt.
            let base = PointSegmenter.Parameters().colorTolerance
            let tol = base + Float(t.width / 240) * 0.3
            let clamped = min(max(tol, PointSegmenter.Parameters.toleranceRange.lowerBound), PointSegmenter.Parameters.toleranceRange.upperBound)
            let changed = abs(clamped - h.tolerance) > 0.004 || !h.usesRegion
            h.tolerance = clamped
            h.usesRegion = true
            h.intent = h.target == nil ? .add : .replace
            hold = h
            if changed { computeTentative() }
        case .vertical:
            if t.height > 48 {
                h.intent = h.target == nil ? .discard : .delete
                hold = h
            } else if t.height < -48 {
                let layers = min(4, PointSegmenter.Parameters().expansionLayers + 1 + Int((-t.height - 48) / 90))
                let changed = layers != h.layers || h.intent != .expand
                h.layers = layers
                h.intent = .expand
                h.usesRegion = true
                hold = h
                if changed { computeTentative() }
            } else {
                let wasVertical = h.intent == .discard || h.intent == .delete || h.intent == .expand
                h.intent = h.target == nil ? .add : .replace
                hold = h
                if wasVertical { computeTentative() }
            }
        case .undecided:
            hold = h
        }
    }

    func endHold() {
        guard let h = hold else { return }
        hold = nil
        defer { refreshPreview() }
        switch h.intent {
        case .discard:
            holdTask?.cancel()
            isPicking = false
            return
        case .delete:
            holdTask?.cancel()
            isPicking = false
            if let t = h.target { commit(pieces.filter { $0.id != t.id }) }
        case .add, .expand, .replace:
            if let tentative = h.tentative {
                holdTask?.cancel()
                isPicking = false
                apply(h, tentative: tentative)
            } else if h.failed {
                isPicking = false
            } else {
                // Still computing: let the result commit itself when it arrives.
                pendingCommit = (holdGeneration, h)
            }
        }
    }

    private func apply(_ h: Hold, tentative: SelectedPiece) {
        var next = pieces
        if let t = h.target { next.removeAll { $0.id == t.id } }
        next.append(tentative)
        commit(next)
        makeHighlight(for: tentative)
    }

    func cancelHold() {
        holdTask?.cancel()
        pendingCommit = nil
        isPicking = false
        hold = nil
        refreshPreview()
    }

    /// A quick tap on a committed piece removes it. Tapping elsewhere does nothing (no accidental selects).
    func tap(at p: CGPoint) {
        guard let t = pieces.last(where: { $0.contains(p) }) else { return }
        commit(pieces.filter { $0.id != t.id })
        refreshPreview()
    }

    private func commit(_ next: [SelectedPiece]) {
        undoStack.append(pieces)
        if undoStack.count > 30 { undoStack.removeFirst() }
        pieces = next
        selectionWasAdjusted = true
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        pieces = previous
        selectionWasAdjusted = true
        refreshPreview()
    }

    func clearSelection() {
        guard !pieces.isEmpty else { return }
        commit([])
        refreshPreview()
    }

    func selectAll() {
        guard let a = scopedAnalysis ?? analysis, a.hasInstances else { return }
        commit(a.allInstances.map { SelectedPiece(vision: a, instance: $0) })
        refreshPreview()
    }

    /// Work out what the current hold would select, off the main thread, and show it tinted.
    private func computeTentative() {
        guard var h = hold, let fullImage else { return }
        holdGeneration += 1
        let gen = holdGeneration
        holdTask?.cancel()

        // Vision path is synchronous and cheap: instance lookup only.
        if !h.usesRegion, let candidate = visionCandidate(at: h.origin), candidate.area < largeInstanceArea {
            h.tentative = candidate
            hold = h
            refreshPreview()
            return
        }
        // Otherwise grow a region (also the fallback when the Vision instance is huge).
        let fallback = h.usesRegion ? nil : visionCandidate(at: h.origin)
        let targetArea = h.target?.area
        var params = PointSegmenter.Parameters()
        params.colorTolerance = h.tolerance
        params.expansionLayers = h.layers
        let prepared = activePrepared
        let origin = h.origin
        isPicking = true
        holdTask = Task.detached(priority: .userInitiated) {
            let region: PointSegmentation? = prepared.flatMap { PointSegmenter.segment($0, atNormalized: origin, parameters: params) }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.holdGeneration == gen else { return }
                self.isPicking = false
                var tentative: SelectedPiece?
                if let region, targetArea.map({ region.area < $0 * 0.6 }) ?? true {
                    tentative = SelectedPiece(region: region)
                } else if let fallback {
                    tentative = fallback
                }
                if var h = self.hold {
                    h.tentative = tentative
                    if tentative == nil { h.failed = true; self.lastPickFailed = true }
                    self.hold = h
                    self.refreshPreview()
                } else if let pending = self.pendingCommit, pending.generation == gen {
                    // Finger already lifted: commit (or report) now.
                    self.pendingCommit = nil
                    if let tentative { self.apply(pending.hold, tentative: tentative) } else { self.lastPickFailed = true }
                    self.refreshPreview()
                }
                _ = fullImage
            }
        }
    }

    /// Render just the newly committed piece at preview resolution for the pop animation.
    private func makeHighlight(for piece: SelectedPiece) {
        guard let fullImage else { return }
        Task.detached(priority: .userInitiated) {
            let small = ImageProcessing.downsample(fullImage, maxLongEdge: 1280)
            let size = CGSize(width: small.width, height: small.height)
            guard let mask = piece.mask(fullSize: size),
                  let cg = MaskCompositor.cutout(image: small, mask: mask, normalizedRect: piece.rect) else { return }
            await MainActor.run { self.lastPickHighlight = PickHighlight(image: cg, rect: piece.rect) }
        }
    }

    /// Full-resolution union mask of the committed pieces.
    private func combinedMask(of pieces: [SelectedPiece]) -> CIImage? {
        guard let fullImage, !pieces.isEmpty else { return nil }
        let size = CGSize(width: fullImage.width, height: fullImage.height)
        let masks = pieces.compactMap { $0.mask(fullSize: size) }
        return MaskCompositor.union(masks, size: size).map { MaskCompositor.feathered($0, radius: 0.7) }
    }

    private func selectionBounds() -> CGRect? {
        guard var u = pieces.first?.rect else { return nil }
        for p in pieces.dropFirst() { u = u.union(p.rect) }
        return u.insetBy(dx: -0.004, dy: -0.004).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Render the tentative piece (original colours) and its edge ring at preview resolution.
    private func refreshTentativeVisual() {
        tentativeVisualTask?.cancel()
        guard let fullImage, let piece = hold?.tentative else { tentativeVisual = nil; return }
        if tentativeVisual?.id == piece.id { return }
        tentativeVisualTask = Task.detached(priority: .userInitiated) {
            let small = ImageProcessing.downsample(fullImage, maxLongEdge: 1280)
            let size = CGSize(width: small.width, height: small.height)
            guard let mask = piece.mask(fullSize: size),
                  let cutout = MaskCompositor.cutout(image: small, mask: mask, normalizedRect: piece.rect),
                  let outline = MaskCompositor.outline(mask: mask, imageSize: size, normalizedRect: piece.rect, thickness: 3) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.hold?.tentative?.id == piece.id else { return }
                self.tentativeVisual = TentativeVisual(id: piece.id, cutout: cutout, outline: outline, rect: piece.rect)
            }
        }
    }

    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0
    private func refreshPreview() {
        guard let fullImage else { return }
        previewGeneration += 1
        let gen = previewGeneration
        refreshTentativeVisual()
        // Masks are built on the main thread (they only reference Vision/CI objects), rendered off it.
        let committed = combinedMask(of: pieces)
        let hidingTarget = hold?.target.map { t in pieces.filter { $0.id != t.id } }
        let committedShown = (hold?.intent == .replace || hold?.intent == .delete) ? hidingTarget.flatMap { combinedMask(of: $0) } : committed
        // When something is only tentatively selected, dim the rest so the lifted piece stands out.
        let dimAll = hold?.tentative != nil && committedShown == nil
        let savedMask = savedRegions.isEmpty ? nil : MaskCompositor.rectsMask(savedRegions, size: CGSize(width: fullImage.width, height: fullImage.height))
        previewTask?.cancel()
        isRenderingPreview = true
        previewTask = Task.detached(priority: .userInitiated) {
            let img = MaskCompositor.preview(image: fullImage, mask: committedShown, saved: savedMask, dimWhenEmpty: dimAll)
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
        guard let fullImage, let mask = combinedMask(of: pieces), let rect = selectionBounds() else { return }
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
        scopedAnalysis = nil
        fullPrepared = nil
        scopedPrepared = nil
        viewport = CGRect(x: 0, y: 0, width: 1, height: 1)
        pieces = []
        undoStack = []
        savedRegions = []
        savedCount = 0
        lassoPoints = []
        hold = nil
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
