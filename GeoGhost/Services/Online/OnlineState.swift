import Foundation
import Observation
import SwiftData

/// What the online screens share: the user's profile and whether the identity was lost.
@Observable
@MainActor
final class OnlineState {
    /// Bumped when the community rules change; users agree again before their next post.
    static let termsVersion = 1
    static let rulesURL = URL(string: "https://passerbo.github.io/GeoGhost/community-rules/")!
    static let nicknameCooldown: TimeInterval = 7 * 24 * 3600

    let services: OnlineServices
    private(set) var profile: OnlineProfile?
    /// The previous guest identity stopped working; the user must confirm before a new one is made.
    var identityExpired = false

    init(services: OnlineServices) {
        self.services = services
    }

    var hasIdentity: Bool { get async { await services.identity.userID != nil } }

    /// Before publishing: a nickname and agreement to the current rules (spec: online-identity).
    var needsProfileSetup: Bool { (profile?.termsVersion ?? 0) < Self.termsVersion }

    /// When the nickname may be changed again; nil if it may be changed now.
    var nicknameChangeAvailableAt: Date? {
        guard let changed = profile?.nicknameChangedAt else { return nil }
        let next = changed.addingTimeInterval(Self.nicknameCooldown)
        return next > Date() ? next : nil
    }

    func loadProfile() async throws {
        profile = try await services.account.ownProfile()
    }

    func saveProfile(nickname: String) async throws {
        profile = try await services.account.saveProfile(nickname: nickname, termsVersion: Self.termsVersion)
    }

    /// Deletes everything on the server; pieces on this phone stay and become private.
    func deleteOnlineData(context: ModelContext) async throws {
        try await services.account.deleteMyOnlineData()
        profile = nil
        Self.makePrivate(context: context)
    }

    /// The user confirmed the lost identity. Their old posts can no longer be managed from here,
    /// so local pieces become private; the next online action starts a new guest.
    func acceptExpiredIdentity(context: ModelContext) async {
        await services.identity.acceptExpiry()
        profile = nil
        identityExpired = false
        Self.makePrivate(context: context)
    }

    /// Pieces that had a public copy become private on this phone.
    static func makePrivate(context: ModelContext) {
        let unpublished = PublishState.unpublished.rawValue
        let shared = (try? context.fetch(FetchDescriptor<Artwork>(predicate: #Predicate { $0.publishStateRaw != unpublished }))) ?? []
        for artwork in shared { artwork.publishState = .unpublished }
        try? context.save()
    }

    /// Routes an error: a lost identity raises the shared alert; anything else is returned for the caller to show.
    func handle(_ error: any Error) -> (any Error)? {
        if error as? OnlineError == .identityExpired {
            identityExpired = true
            return nil
        }
        return error
    }
}

/// Words for online errors, as the user should read them.
enum OnlineMessage {
    static func text(for error: any Error) -> String {
        #if DEBUG
        return userText(for: error) + "\n(\(error))"
        #else
        return userText(for: error)
        #endif
    }

    private static func userText(for error: any Error) -> String {
        switch error {
        case PublishError.noLocation:
            String(localized: "This piece has no location, so it can't appear on the world map.")
        case PublishError.missingCutout:
            String(localized: "This piece's cutout is missing. Use Edit this piece to cut it out again.")
        case PublishError.imageTooLarge:
            String(localized: "This cutout is too large to publish.")
        case let online as OnlineError:
            text(for: online)
        default:
            String(localized: "Something went wrong. Please try again.")
        }
    }

    static func text(for error: OnlineError) -> String {
        switch error {
        case .offline:
            String(localized: "You're offline. Connect to the internet and try again.")
        case .refused(.quotaDay):
            String(localized: "You've reached today's publishing limit. You can publish again tomorrow.")
        case .refused(.quotaMonth):
            String(localized: "You've reached this month's publishing limit. It resets on the 1st.")
        case .refused(.banned):
            String(localized: "Your account can no longer publish because it broke the community rules.")
        case .refused(.nicknameCooldown):
            String(localized: "You changed your nickname recently. Please wait a few days before changing it again.")
        case .refused(.termsRequired), .refused(.profileRequired):
            String(localized: "Choose a nickname and agree to the community rules first.")
        case .refused(.savesFull), .refused(.likesDay), .refused(.reportsDay):
            String(localized: "You've reached today's limit. Please try again later.")
        case .identityExpired:
            String(localized: "Your online identity is no longer valid.")
        case .notConfigured:
            String(localized: "Online features aren't available in this build.")
        case .tooLarge, .unsupportedImage:
            String(localized: "This cutout couldn't be uploaded.")
        default:
            String(localized: "The server couldn't complete this. Please try again later.")
        }
    }
}
