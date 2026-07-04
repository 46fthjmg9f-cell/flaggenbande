import SwiftUI
import StoreKit
import Combine
#if DEBUG && canImport(StoreKitTest)
import StoreKitTest
#endif

@MainActor
final class StoreKitManager: ObservableObject {

    @Published private(set) var products: [Product] = []
    @Published private(set) var fullVersionProduct: Product?
    @Published private(set) var donationProducts: [Product] = []

    @Published private(set) var purchasedFullVersion: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false

    @Published var statusText: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
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
        isLoading = true
        defer { isLoading = false }

        do {
            let fullVersionID = StoreProductID.fullVersion.rawValue
            let requestedDonationIDs = Array(StoreProductID.donationIDs).sorted()
            let fetchedFullVersionProducts = try await Product.products(for: [fullVersionID])
            let fetchedDonationProducts = try await Product.products(for: requestedDonationIDs)
            let fetchedProducts = fetchedFullVersionProducts + fetchedDonationProducts

            print("Angefragte Vollversion Product ID:", fullVersionID)
            print("Gefundene Vollversion Product IDs:", fetchedFullVersionProducts.map { $0.id })
            print("Angefragte Spenden Product IDs:", requestedDonationIDs)
            print("Gefundene Spenden Product IDs:", fetchedDonationProducts.map { $0.id })

            products = fetchedProducts
            fullVersionProduct = fetchedFullVersionProducts.first { $0.id == fullVersionID }
            donationProducts = fetchedDonationProducts.sorted { $0.price < $1.price }

            if refreshPurchasedEntitlements {
                await refreshEntitlements()
            }

            if reportErrors {
                if fullVersionProduct == nil {
                    statusText = "Vollversion-Kauf nicht gefunden. Prüfe Product-ID und ob Flaggenbande.storekit im Scheme aktiv ist."
                } else {
                    statusText = nil
                }
            }

        } catch {
            print("StoreKit Fehler:", error.localizedDescription)

            if reportErrors {
                statusText = "Store konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Kaufen

    func purchaseFullVersion() async {
        guard !isPurchasing else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        if fullVersionProduct == nil {
            await loadProducts(reportErrors: true, refreshPurchasedEntitlements: false)
        }

        guard let product = fullVersionProduct else {
            statusText = "Vollversion-Kauf nicht gefunden. Prüfe Product-ID in App Store Connect."
            return
        }

        await purchase(product)
    }

    func purchase(_ product: Product) async {
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
            print("Kauf fehlgeschlagen:", error.localizedDescription)
            statusText = "Kauf fehlgeschlagen."
        }
    }

    #if DEBUG
    func resetFullVersionPurchaseForDebugTesting() async {
        purchasedFullVersion = false

        #if canImport(StoreKitTest)
        do {
            let session: SKTestSession
            if let configurationURL = Bundle.main.url(forResource: "Flaggenbande", withExtension: "storekit") {
                session = try SKTestSession(contentsOf: configurationURL)
            } else {
                session = try SKTestSession(configurationFileNamed: "Flaggenbande.storekit")
            }

            let fullVersionID = StoreProductID.fullVersion.rawValue
            let fullVersionTransactions = session.allTransactions()
                .filter { $0.productIdentifier == fullVersionID }

            for transaction in fullVersionTransactions {
                try session.deleteTransaction(identifier: transaction.identifier)
            }

            statusText = fullVersionTransactions.isEmpty
                ? "Vollversion lokal zurückgesetzt. Es gab keine StoreKit-Testtransaktion."
                : "Vollversion und StoreKit-Testkauf zurückgesetzt."

        } catch {
            statusText = "Vollversion lokal zurückgesetzt. StoreKit-Testkauf konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
        #else
        statusText = "Vollversion lokal zurückgesetzt. Xcode kann StoreKit-Testkäufe nur über Debug > StoreKit > Manage Transactions löschen."
        #endif
    }
    #endif

    // MARK: - Käufe wiederherstellen

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if purchasedFullVersion {
                statusText = "Vollversion wiederhergestellt."
            } else {
                statusText = "Keine Vollversion gefunden."
            }

        } catch {
            print("Wiederherstellen fehlgeschlagen:", error.localizedDescription)
            statusText = "Wiederherstellen fehlgeschlagen."
        }
    }

    // MARK: - Berechtigungen prüfen

    func refreshEntitlements() async {
        var ownsFullVersion = false

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard transaction.revocationDate == nil else {
                continue
            }

            if transaction.productID == StoreProductID.fullVersion.rawValue {
                ownsFullVersion = true
            }
        }

        purchasedFullVersion = ownsFullVersion
    }

    // MARK: - Transaktionen verarbeiten

    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            await handleVerifiedTransaction(transaction)

        case .unverified:
            statusText = "Kauf konnte nicht verifiziert werden."
        }
    }

    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        if transaction.productID == StoreProductID.fullVersion.rawValue {
            purchasedFullVersion = transaction.revocationDate == nil
            statusText = purchasedFullVersion ? "Vollversion freigeschaltet." : nil
        } else if StoreProductID.donationIDs.contains(transaction.productID) {
            statusText = "Danke für deine Unterstützung!"
        }

        await transaction.finish()
    }
}
