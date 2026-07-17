import SwiftUI
import StoreKit
import Combine

@MainActor
final class StoreKitManager: ObservableObject {

    @Published private(set) var products: [Product] = []
    @Published private(set) var fullVersionProduct: Product?

    @Published private(set) var purchasedFullVersion: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRefreshingEntitlements: Bool = false

    @Published var statusText: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private var lastEntitlementRefreshAt: Date?
    private static let localFullVersionPurchasedKey = "storeKitFullVersionPurchasedV1"
    private let unavailableFullVersionMessage = """
    Vollversion-Kauf nicht gefunden. Product-ID stimmt im Code. Prüfe in App Store Connect: gleiche App/Bundle-ID, In-App-Kauf-Status, Preis/Verfügbarkeit und Paid-Apps-Vertrag. Danach kann TestFlight bis zu 1 Stunde brauchen.
    """

    init() {
        purchasedFullVersion = Self.loadLocalFullVersionPurchase()
        startTransactionListener()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    // MARK: - Setup

    private func startTransactionListener() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handleTransactionResult(result)
            }
        }
    }

    // MARK: - Produkte laden

    func loadProducts(reportErrors: Bool = false, refreshPurchasedEntitlements: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if refreshPurchasedEntitlements {
            await refreshPurchasedProducts()
        }

        if fullVersionProduct != nil {
            if reportErrors {
                statusText = nil
            }
            return
        }

        do {
            let fullVersionID = StoreProductID.fullVersion.rawValue
            let fetchedFullVersionProducts = try await Product.products(for: [fullVersionID])

            products = fetchedFullVersionProducts
            fullVersionProduct = fetchedFullVersionProducts.first { $0.id == fullVersionID }

            if reportErrors {
                if fullVersionProduct == nil {
                    statusText = unavailableFullVersionMessage
                } else {
                    statusText = nil
                }
            }

        } catch {
            debugLog("StoreKit product load failed: \(error.localizedDescription)")

            if reportErrors {
                statusText = "Store konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Kaufen

    @discardableResult
    func purchaseFullVersion() async -> Bool {
        guard !isPurchasing else { return false }

        isPurchasing = true
        defer { isPurchasing = false }

        if fullVersionProduct == nil {
            statusText = "Store wird geladen ..."
            await loadProducts(reportErrors: true, refreshPurchasedEntitlements: false)
        }

        guard let product = fullVersionProduct else {
            statusText = unavailableFullVersionMessage
            return false
        }

        return await purchase(product)
    }


    @discardableResult
    private func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                return await handleTransactionResult(verificationResult)

            case .pending:
                statusText = "Kauf wartet auf Bestätigung."
                return false

            case .userCancelled:
                statusText = nil
                return false

            @unknown default:
                statusText = "Kauf konnte nicht abgeschlossen werden."
                return false
            }

        } catch StoreKitError.notAvailableInStorefront {
            statusText = "Dieser Kauf ist in deinem Storefront aktuell nicht verfügbar."
            return false
        } catch StoreKitError.networkError {
            statusText = "Store-Verbindung fehlgeschlagen. Bitte prüfe deine Internetverbindung."
            return false
        } catch {
            debugLog("Purchase failed: \(error.localizedDescription)")
            statusText = "Kauf fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Käufe wiederherstellen

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            debugLog("Restore purchases synced AppStore successfully.")
            await refreshPurchasedProducts(clearLocalPurchaseIfMissing: true, force: true)

            if purchasedFullVersion {
                statusText = "Vollversion wiederhergestellt."
            } else {
                statusText = "Keine Vollversion gefunden."
            }

        } catch {
            debugLog("Restore failed: \(error.localizedDescription)")
            statusText = "Wiederherstellen fehlgeschlagen."
        }
    }

    // MARK: - Berechtigungen prüfen

    func refreshPurchasedProducts(clearLocalPurchaseIfMissing: Bool = false, force: Bool = false) async {
        await refreshEntitlements(clearLocalPurchaseIfMissing: clearLocalPurchaseIfMissing, force: force)
    }

    private func refreshEntitlements(clearLocalPurchaseIfMissing: Bool = false, force: Bool = false) async {
        guard !isRefreshingEntitlements else { return }
        if !force,
           let lastEntitlementRefreshAt,
           Date().timeIntervalSince(lastEntitlementRefreshAt) < 5 * 60 {
            return
        }

        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        var ownsFullVersion = false
        var entitlementProductIDs: [String] = []

        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                entitlementProductIDs.append(transaction.productID)

                guard transaction.revocationDate == nil else {
                    debugLog("Verified entitlement is revoked: \(transaction.productID)")
                    continue
                }

                if transaction.productID == StoreProductID.fullVersion.rawValue {
                    ownsFullVersion = true
                }

            case .unverified(_, let error):
                debugLog("Unverified entitlement ignored: \(error.localizedDescription)")
                continue
            }
        }

        if ownsFullVersion {
            setPurchasedFullVersion(true, persistLocalCache: true)
        } else if clearLocalPurchaseIfMissing {
            setPurchasedFullVersion(false, persistLocalCache: true)
        }

        lastEntitlementRefreshAt = Date()

        debugLog("Current entitlements: \(entitlementProductIDs). StoreKit premium: \(ownsFullVersion). Local premium: \(purchasedFullVersion)")
    }

    // MARK: - Transaktionen verarbeiten

    @discardableResult
    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        switch result {
        case .verified(let transaction):
            return await handleVerifiedTransaction(transaction)

        case .unverified(_, let error):
            debugLog("Unverified transaction update ignored: \(error.localizedDescription)")
            statusText = "Kauf konnte nicht verifiziert werden."
            return false
        }
    }

    @discardableResult
    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async -> Bool {
        let productID = transaction.productID
        let isRevoked = transaction.revocationDate != nil

        if productID == StoreProductID.fullVersion.rawValue {
            setPurchasedFullVersion(!isRevoked, persistLocalCache: true)
            if !isRevoked {
                statusText = "Vollversion freigeschaltet."
            }
        }

        await transaction.finish()
        await refreshEntitlements(clearLocalPurchaseIfMissing: isRevoked, force: true)

        let ownsUpdatedFullVersion = productID == StoreProductID.fullVersion.rawValue && !isRevoked && purchasedFullVersion
        return ownsUpdatedFullVersion
    }

    private func setPurchasedFullVersion(_ isPurchased: Bool, persistLocalCache: Bool) {
        purchasedFullVersion = isPurchased

        guard persistLocalCache else { return }
        UserDefaults.standard.set(isPurchased, forKey: Self.localFullVersionPurchasedKey)
        debugLog("Local premium cache set to \(isPurchased).")
    }

    private static func loadLocalFullVersionPurchase() -> Bool {
        UserDefaults.standard.bool(forKey: localFullVersionPurchasedKey)
    }

    #if DEBUG
    func resetLocalPremiumStatusForDebug() {
        UserDefaults.standard.removeObject(forKey: Self.localFullVersionPurchasedKey)
        purchasedFullVersion = false
        statusText = "Lokaler Premiumstatus wurde zurückgesetzt."
        debugLog("Local premium cache reset from debug menu.")
    }
    #endif

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[StoreKitManager] \(message)")
        #endif
    }
}
