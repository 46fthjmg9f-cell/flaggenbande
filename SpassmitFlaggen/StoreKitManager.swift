import SwiftUI
import Foundation
import Combine
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedFullVersion: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published var statusText: String?

    private var updatesTask: Task<Void, Never>?
    private let missingFullVersionProductMessage = "Vollversion-Kauf nicht gefunden. Prüfe die Product ID in App Store Connect."

    init() {}

    deinit {
        updatesTask?.cancel()
    }

    var fullVersionProduct: Product? {
        products.first { $0.id == StoreProductID.fullVersion.rawValue }
    }

    var donationProducts: [Product] {
        products
            .filter { StoreProductID.donationIDs.contains($0.id) }
            .sorted { $0.displayPrice < $1.displayPrice }
    }

    private func startObservingTransactionsIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handleTransactionResult(result)
            }
        }
    }

    func loadProducts(reportErrors: Bool = false) async {
        startObservingTransactionsIfNeeded()
        isLoading = true
        defer { isLoading = false }

        do {
            mergeProducts(try await Product.products(for: StoreProductID.allIDs))
            await refreshEntitlements()
            if reportErrors {
                statusText = fullVersionProduct == nil ? missingFullVersionProductMessage : nil
            }
        } catch {
            if reportErrors {
                statusText = "Store konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    func purchaseFullVersion() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        if fullVersionProduct == nil {
            await loadFullVersionProduct()
        }

        guard let product = fullVersionProduct else {
            statusText = missingFullVersionProductMessage
            return
        }

        await purchase(product)
    }

    private func loadFullVersionProduct() async {
        startObservingTransactionsIfNeeded()
        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedProducts = try await Product.products(for: [StoreProductID.fullVersion.rawValue])
            mergeProducts(fetchedProducts)
            await refreshEntitlements()
            if fullVersionProduct == nil {
                statusText = missingFullVersionProductMessage
            }
        } catch {
            statusText = "Store konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    private func mergeProducts(_ fetchedProducts: [Product]) {
        var productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        for product in fetchedProducts {
            productsByID[product.id] = product
        }
        products = StoreProductID.allIDs.compactMap { productsByID[$0] }
    }

    func purchase(_ product: Product) async {
        startObservingTransactionsIfNeeded()
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                await handleTransactionResult(verificationResult)
            case .pending:
                statusText = "Kauf wartet auf Bestätigung."
            case .userCancelled:
                statusText = nil
            @unknown default:
                statusText = "Kauf konnte nicht abgeschlossen werden."
            }
        } catch {
            statusText = "Kauf fehlgeschlagen."
        }
    }

    func restorePurchases() async {
        startObservingTransactionsIfNeeded()
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusText = purchasedFullVersion ? "Vollversion wiederhergestellt." : "Keine Vollversion gefunden."
        } catch {
            statusText = "Wiederherstellen fehlgeschlagen."
        }
    }

    func refreshEntitlements() async {
        var hasFullVersion = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == StoreProductID.fullVersion.rawValue && transaction.revocationDate == nil {
                hasFullVersion = true
            }
        }
        purchasedFullVersion = hasFullVersion
    }

    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            if transaction.productID == StoreProductID.fullVersion.rawValue {
                purchasedFullVersion = transaction.revocationDate == nil
                statusText = purchasedFullVersion ? "Vollversion freigeschaltet." : nil
            } else if StoreProductID.donationIDs.contains(transaction.productID) {
                statusText = "Danke für deine Unterstützung."
            }
            await transaction.finish()
        case .unverified:
            statusText = "Kauf konnte nicht verifiziert werden."
        }
    }
}
