import Foundation
import StoreKit

/// App Store premium: three pay-what-you-want annual tiers that all unlock
/// the same features; the higher tiers are voluntary extra support (the
/// Yuka model). Purchases verify on-device through StoreKit 2 and never
/// touch our server, matching the no-accounts privacy stance. The active
/// state mirrors into UserDefaults so Entitlements can read it without
/// importing StoreKit.
@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    static let iapActiveKey = "entitlements.iapActive"
    static let productIds = [
        "com.studio86.simply.premium.year12",
        "com.studio86.simply.premium.year24",
        "com.studio86.simply.premium.year48",
    ]

    @Published private(set) var products: [StoreKit.Product] = []
    @Published private(set) var hasActiveSubscription =
        UserDefaults.standard.bool(forKey: Purchases.iapActiveKey)

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Transaction.updates delivers renewals, refunds, and purchases
        // completed outside the app (Ask to Buy, offer codes); every event
        // re-derives the entitlement from scratch.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    func loadProducts() async {
        let loaded = (try? await StoreKit.Product.products(for: Self.productIds)) ?? []
        products = loaded.sorted { $0.price < $1.price }
    }

    /// Re-derives premium from the current verified entitlements. Never
    /// trusts a cached flag over StoreKit: a refund or expiry drops it on
    /// the next pass.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIds.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        hasActiveSubscription = active
        UserDefaults.standard.set(active, forKey: Self.iapActiveKey)
    }

    /// True on a completed, verified purchase.
    func purchase(_ product: StoreKit.Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        guard case .success(let verification) = result,
              case .verified(let transaction) = verification else { return false }
        await transaction.finish()
        await refreshEntitlement()
        return true
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
