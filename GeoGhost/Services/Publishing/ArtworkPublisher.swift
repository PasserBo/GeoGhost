import CoreGraphics
import Foundation
import SwiftData

enum PublishError: Error, Equatable {
    /// Pieces without a location cannot appear on the world map (spec: publishing).
    case noLocation
    case missingCutout
    case imageTooLarge
}

/// Publishing flow for one piece (design.md §8): encode → create the post → upload → record the
/// state. Each step is saved, so an interrupted publish shows as unfinished and retrying reuses
/// the same post (the server keys it by the artwork id) without using quota again.
@MainActor
struct ArtworkPublisher {
    let backend: any PublishBackend
    let context: ModelContext
    /// The cutout to publish; the shared image store by default.
    var loadCutout: @Sendable (UUID, String) -> CGImage? = { id, imageID in
        ImageStore.shared.loadImage(artworkID: id, imageID: imageID)
    }
    var calendar: Calendar = .current

    /// Publishes (or finishes publishing) the piece and returns its new state.
    /// Refusals such as `.refused(.profileRequired)` or `.refused(.quotaDay)` leave the piece as it was.
    @discardableResult
    func publish(_ artwork: Artwork) async throws -> PublishState {
        guard let coordinate = artwork.coordinate else { throw PublishError.noLocation }
        let artworkID = artwork.id, cutoutID = artwork.cutoutImageID, load = loadCutout
        let images: PublishImageEncoder.Output = try await Task.detached(priority: .userInitiated) {
            guard let cutout = load(artworkID, cutoutID) else { throw PublishError.missingCutout }
            do { return try PublishImageEncoder.encode(cutout) } catch PublishImageEncoder.EncodeError.tooLarge {
                throw PublishError.imageTooLarge
            }
        }.value

        let snapped = LocationBlur.snap(coordinate)
        let draft = PostDraft(clientArtworkId: artworkID, kind: artwork.kind.rawValue, lat: snapped.latitude, lng: snapped.longitude,
                              locality: artwork.localityName, countryCode: artwork.countryCode,
                              capturedOn: OnlineHTTP.dayString(artwork.displayDate, calendar: calendar),
                              width: images.fullWidth, height: images.fullHeight)
        let created = try await backend.createPost(draft)
        artwork.remotePostID = created.postId
        let createdState = PublishState(serverStatus: created.status)
        if createdState != .uploading {
            // Already finished earlier (the images went up but the answer was lost).
            record(createdState, on: artwork)
            return createdState
        }
        record(.uploading, on: artwork)

        let state = PublishState(serverStatus: try await backend.uploadImages(postID: created.postId, images: images))
        record(state, on: artwork)
        return state
    }

    /// Takes the public copy down; the piece becomes private again.
    func retract(_ artwork: Artwork) async throws {
        if let postID = artwork.remotePostID { try await backend.retract(postID: postID) }
        record(.unpublished, on: artwork)
    }

    /// Retracts every piece with a public copy. Stops at the first failure; already retracted ones stay retracted.
    func retractAll(_ artworks: [Artwork]) async throws {
        for artwork in artworks where artwork.publishState.hasRemoteCopy {
            try await retract(artwork)
        }
    }

    /// Brings local states in line with the server: reviews finished, posts hidden after reports,
    /// posts gone because the online data was deleted.
    func refreshStates(_ artworks: [Artwork]) async throws {
        let tracked = artworks.filter { $0.remotePostID != nil && $0.publishState.hasRemoteCopy }
        guard !tracked.isEmpty else { return }
        let statuses = try await backend.statuses(of: tracked.compactMap(\.remotePostID))
        for artwork in tracked {
            guard let postID = artwork.remotePostID else { continue }
            let state = PublishState(serverStatus: statuses[postID])
            if state != artwork.publishState { record(state, on: artwork) }
        }
    }

    private func record(_ state: PublishState, on artwork: Artwork) {
        let postID = artwork.remotePostID
        artwork.publishState = state
        if state.hasRemoteCopy { artwork.remotePostID = postID }
        if state == .published, artwork.publishedAt == nil { artwork.publishedAt = Date() }
        try? context.save()
    }
}
