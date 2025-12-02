import Foundation
import StoreKit
import Combine
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    @Published var isSubscribed = false
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var subscriptionStatus: SubscriptionStatus?
    @Published var currentSubscription: Product.SubscriptionInfo.Status?
    @Published var subscriptionRenewalDate: Date?
    @Published var isEligibleForTrial = false
    @Published var showPaywall = false
    @Published var isLoadingProducts = false
    @Published var productLoadError: String? = nil

    // Free tier limits
    @Published var signatureCount = 0
    private let maxFreeSignatures = 3

    private var updateListenerTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()

    static let shared = SubscriptionManager()

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(Error)
        case pending
        case restored

        static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.purchasing, .purchasing),
                 (.purchased, .purchased), (.pending, .pending),
                 (.restored, .restored):
                return true
            case (.failed(_), .failed(_)):
                // Consider all failed states equal for UI purposes
                return true
            default:
                return false
            }
        }
    }

    enum SubscriptionStatus {
        case active
        case expired
        case inGracePeriod
        case inBillingRetryPeriod
        case revoked
        case notSubscribed

        var displayText: String {
            switch self {
            case .active:
                return "Active"
            case .expired:
                return "Expired"
            case .inGracePeriod:
                return "Grace Period"
            case .inBillingRetryPeriod:
                return "Billing Retry"
            case .revoked:
                return "Revoked"
            case .notSubscribed:
                return "Not Subscribed"
            }
        }

        var isActive: Bool {
            switch self {
            case .active, .inGracePeriod, .inBillingRetryPeriod:
                return true
            default:
                return false
            }
        }
    }

    // Product IDs - these should match your App Store Connect configuration
    private let productIds = [
        "com.noworrieslifestyle.signsimplepdf.premium.weekly",
        "com.noworrieslifestyle.signsimplepdf.premium.lifetime"
    ]

    init() {
        // Load signature count from UserDefaults
        signatureCount = UserDefaults.standard.integer(forKey: "signatureCount")

        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Check if user should see paywall
        checkPaywallPresentation()

        Task {
            await loadProducts()
            await updateCurrentEntitlements()
            await checkTrialEligibility()
        }
    }

    private func checkPaywallPresentation() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hasSeenPaywallToday = UserDefaults.standard.bool(forKey: "hasSeenPaywallToday")
        let lastPaywallDate = UserDefaults.standard.object(forKey: "lastPaywallDate") as? Date

        let shouldShowPaywall = hasCompletedOnboarding &&
                               !isSubscribed &&
                               (!hasSeenPaywallToday || !Calendar.current.isDateInToday(lastPaywallDate ?? .distantPast))

        showPaywall = shouldShowPaywall
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        productLoadError = nil

        do {
            let storeProducts = try await Product.products(for: productIds)
            self.products = storeProducts.sorted { $0.price < $1.price }

            if storeProducts.isEmpty {
                productLoadError = "No subscription options available"
                print("⚠️ No products returned from StoreKit")
            } else {
                print("✅ Loaded \(storeProducts.count) products successfully")
            }
        } catch {
            print("❌ Failed to load products: \(error)")
            productLoadError = "Unable to load subscription options. Please check your connection."
            self.products = []
        }

        isLoadingProducts = false
    }

    func purchase(_ product: Product) async {
        purchaseState = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateSubscriptionStatus(transaction: transaction)
                await transaction.finish()
                purchaseState = .purchased

                // Hide paywall after successful purchase
                showPaywall = false

                // Track purchase event
                print("✅ Purchase successful: \(product.displayName)")

                // Request review after successful premium subscription
                ReviewRequestManager.shared.recordPremiumFeatureUsed()

            case .userCancelled:
                purchaseState = .idle
                print("🚫 Purchase cancelled by user")

            case .pending:
                purchaseState = .pending
                print("⏳ Purchase pending approval")

            @unknown default:
                purchaseState = .idle
                print("❓ Unknown purchase result")
            }

        } catch {
            purchaseState = .failed(error)
            print("❌ Purchase failed: \(error)")
        }
    }

    func restorePurchases() async {
        purchaseState = .purchasing

        do {
            try await AppStore.sync()
            await updateCurrentEntitlements()

            if isSubscribed {
                purchaseState = .restored
                showPaywall = false
                print("✅ Purchases restored successfully")
            } else {
                purchaseState = .idle
                print("ℹ️ No active subscriptions found")
            }
        } catch {
            purchaseState = .failed(error)
            print("❌ Restore failed: \(error)")
        }
    }

    func updateCurrentEntitlements() async {
        var activeSubscription = false
        var hasLifetime = false
        var latestTransaction: StoreKit.Transaction?

        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    activeSubscription = true
                    latestTransaction = transaction
                    await updateSubscriptionStatus(transaction: transaction)
                } else if transaction.productType == .nonConsumable &&
                         transaction.productID == "com.noworrieslifestyle.signsimplepdf.premium.lifetime" {
                    hasLifetime = true
                    activeSubscription = true // Lifetime counts as active subscription
                }
            }
        }

        self.isSubscribed = activeSubscription || hasLifetime

        if !activeSubscription {
            subscriptionStatus = .notSubscribed
            currentSubscription = nil
            subscriptionRenewalDate = nil
        }

        // Update paywall presentation if subscription status changed
        checkPaywallPresentation()
    }

    func updateSubscriptionStatus(transaction: StoreKit.Transaction) async {
        guard transaction.productType == .autoRenewable else { return }

        // Check subscription status
        do {
            // Get the product for this transaction
            guard let product = products.first(where: { $0.id == transaction.productID }) else { return }

            let statuses = try await product.subscription?.status ?? []

            guard let status = statuses.first else { return }
            currentSubscription = status

            // Use transaction expiration date for renewal date
            subscriptionRenewalDate = transaction.expirationDate

            switch status.state {
            case .subscribed:
                subscriptionStatus = .active
                isSubscribed = true

            case .expired:
                subscriptionStatus = .expired
                isSubscribed = false
                subscriptionRenewalDate = nil

            case .inGracePeriod:
                subscriptionStatus = .inGracePeriod
                isSubscribed = true

            case .inBillingRetryPeriod:
                subscriptionStatus = .inBillingRetryPeriod
                isSubscribed = true

            case .revoked:
                subscriptionStatus = .revoked
                isSubscribed = false
                subscriptionRenewalDate = nil

            default:
                subscriptionStatus = .notSubscribed
                isSubscribed = false
                subscriptionRenewalDate = nil
            }
        } catch {
            print("❌ Failed to get subscription status: \(error)")
            subscriptionStatus = .notSubscribed
            isSubscribed = false
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    await MainActor.run {
                        Task {
                            await self.updateSubscriptionStatus(transaction: transaction)
                        }
                    }

                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Trial Eligibility

    private func checkTrialEligibility() async {
        for product in products {
            if let subscription = product.subscription,
               let introOffer = subscription.introductoryOffer {
                do {
                    let eligible = await subscription.isEligibleForIntroOffer
                    if eligible {
                        isEligibleForTrial = true
                        return
                    }
                } catch {
                    print("❌ Failed to check trial eligibility: \(error)")
                }
            }
        }
        isEligibleForTrial = false
    }

    // MARK: - Signature Management

    func incrementSignatureCount() {
        setSignatureCount(signatureCount + 1)
    }

    func resetSignatureCount() {
        setSignatureCount(0)
    }

    func setSignatureCount(_ count: Int) {
        signatureCount = max(0, count)
        UserDefaults.standard.set(signatureCount, forKey: "signatureCount")
    }

    // MARK: - Premium Features Check

    var canUsePremiumFeatures: Bool {
        isSubscribed
    }

    var canSaveUnlimitedSignatures: Bool {
        isSubscribed || signatureCount < maxFreeSignatures
    }

    var remainingFreeSignatures: Int {
        max(0, maxFreeSignatures - signatureCount)
    }

    var canUseAdvancedEditing: Bool {
        isSubscribed
    }

    var canUseBatchProcessing: Bool {
        isSubscribed
    }

    var canUseCustomStamps: Bool {
        isSubscribed
    }

    var canUseFormFilling: Bool {
        isSubscribed
    }

    var canUseAdvancedAnnotations: Bool {
        isSubscribed
    }

    // MARK: - Paywall Management

    func showPaywallIfNeeded() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding && !isSubscribed {
            showPaywall = true
        }
    }

    func dismissPaywall() {
        showPaywall = false
        UserDefaults.standard.set(true, forKey: "hasSeenPaywallToday")
        UserDefaults.standard.set(Date(), forKey: "lastPaywallDate")
    }

    func presentPaywall() {
        showPaywall = true
    }

    // MARK: - Subscription Info

    var subscriptionDisplayName: String {
        guard isSubscribed,
              let subscription = currentSubscription,
              case .verified(let renewalInfo) = subscription.renewalInfo,
              let currentProduct = products.first(where: { product in
                  product.id == renewalInfo.currentProductID
              }) else {
            return "Not Subscribed"
        }

        return currentProduct.displayName
    }

    var subscriptionPrice: String {
        guard isSubscribed,
              let subscription = currentSubscription,
              case .verified(let renewalInfo) = subscription.renewalInfo,
              let currentProduct = products.first(where: { product in
                  product.id == renewalInfo.currentProductID
              }) else {
            return ""
        }

        return currentProduct.displayPrice
    }

    var formattedRenewalDate: String {
        guard let renewalDate = subscriptionRenewalDate else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: renewalDate)
    }

    // MARK: - Product Helpers

    var weeklyProduct: Product? {
        products.first { $0.id == "com.noworrieslifestyle.signsimplepdf.premium.weekly" }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == "com.noworrieslifestyle.signsimplepdf.premium.lifetime" }
    }

    func lifetimeSavingsMonths() -> Int {
        guard let weekly = weeklyProduct,
              let lifetime = lifetimeProduct else {
            return 0
        }

        // Calculate how many weeks of subscription equals the lifetime price
        let lifetimePrice = (lifetime.price as Decimal) as NSDecimalNumber
        let weeklyPrice = (weekly.price as Decimal) as NSDecimalNumber
        let weeksEquivalent = lifetimePrice.doubleValue / weeklyPrice.doubleValue
        // Convert to months (approximately)
        let monthsEquivalent = Int(weeksEquivalent * 12 / 52)

        // Lifetime pays for itself after this many months
        return monthsEquivalent
    }
}

enum StoreError: Error {
    case failedVerification
}
