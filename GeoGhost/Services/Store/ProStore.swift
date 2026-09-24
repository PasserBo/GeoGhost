import Foundation
import Observation
import StoreKit

/// GeoGhost Pro: one-time unlock. Free tier is capped at `freeLimit` artworks.
@Observable
@MainActor
final class ProStore {
    static let productID = "com.passerbo.geoghost.pro"
    static let freeLimit = 50

    private(set) var isPro: Bool = UserDefaults.standard.bool(forKey: "isPro")
    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await self?.handle(t) }
            }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { pro = true }
        }
        setPro(pro)
    }

    func purchase() async {
        guard let product else { await load(); return }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let t) = verification {
                await handle(t)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func canAddArtwork(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeLimit
    }

    private func handle(_ t: Transaction) async {
        if t.productID == Self.productID { setPro(t.revocationDate == nil) }
        await t.finish()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: "isPro")
    }
}
