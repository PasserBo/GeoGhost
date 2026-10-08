import Foundation
import Observation
import StoreKit

/// GeoGhost Pro: one-time unlock. Collecting is never limited; Pro adds polish on top
/// (all share-card styles, unbranded cards, full-resolution exports). See docs/06-product-roadmap.md.
@Observable
@MainActor
final class ProStore {
    static let productID = "com.passerbo.geoghost.pro"
    /// Long edge of exported transparent PNGs on the free tier; Pro exports the stored cutout untouched.
    static let freeExportLongEdge = 1600

    enum RestoreResult { case restored, nothingToRestore, cancelled, failed }

    private(set) var isPro: Bool = UserDefaults.standard.bool(forKey: "isPro")
    private(set) var product: Product?
    private(set) var isLoading = false
    /// Shown under the purchase button; only set in response to something the user did.
    private(set) var lastError: String?
    /// Ask to Buy / SCA: the purchase went through but awaits approval.
    private(set) var isPending = false
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await self?.handle(t) }
            }
        }
    }

    /// Fetch the product and current entitlements. Silent: a failure here just leaves `product` nil
    /// and is reported when the user actually tries to buy.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        product = (try? await Product.products(for: [Self.productID]))?.first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { pro = true }
        }
        setPro(pro)
    }

    func purchase() async {
        lastError = nil
        if product == nil { await load() }
        guard let product else {
            lastError = String(localized: "The App Store can't be reached right now. Check your connection and try again.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                isPending = false
                await handle(t)
            case .success(.unverified):
                lastError = String(localized: "The App Store couldn't verify this purchase. Try Restore purchase, or contact support.")
            case .pending:
                isPending = true
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async -> RestoreResult {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
        await refreshEntitlements()
        return isPro ? .restored : .nothingToRestore
    }

    private func handle(_ t: Transaction) async {
        if t.productID == Self.productID { setPro(t.revocationDate == nil); isPending = false }
        await t.finish()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: "isPro")
    }
}
