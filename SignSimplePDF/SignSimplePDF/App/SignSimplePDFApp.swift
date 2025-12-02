import SwiftUI
import StoreKit

@main
struct SignSimplePDFApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var documentManager = DocumentManager()
    @StateObject private var signatureManager = SignatureManager()
    @StateObject private var onboardingCoordinator: OnboardingCoordinator

    init() {
        let subscriptionManager = SubscriptionManager()
        self._subscriptionManager = StateObject(wrappedValue: subscriptionManager)
        self._onboardingCoordinator = StateObject(wrappedValue: OnboardingCoordinator(subscriptionManager: subscriptionManager))
        self._documentManager = StateObject(wrappedValue: DocumentManager())
        self._signatureManager = StateObject(wrappedValue: SignatureManager(subscriptionManager: subscriptionManager))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(subscriptionManager)
                    .environmentObject(documentManager)
                    .environmentObject(signatureManager)
                    .environmentObject(onboardingCoordinator)

                if onboardingCoordinator.showOnboarding {
                    OnboardingView(coordinator: onboardingCoordinator)
                        .environmentObject(subscriptionManager)
                        .transition(.opacity)
                        .zIndex(1)
                }

                if subscriptionManager.showPaywall && !onboardingCoordinator.showOnboarding {
                    PaywallView()
                        .environmentObject(subscriptionManager)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .task {
                await setupStoreKit()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await subscriptionManager.updateCurrentEntitlements()
                    subscriptionManager.showPaywallIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func setupStoreKit() async {
        await subscriptionManager.loadProducts()
        await subscriptionManager.updateCurrentEntitlements()

        // Handle transactions that were completed while app wasn't running
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                await subscriptionManager.updateSubscriptionStatus(transaction: transaction)
                await transaction.finish()
            }
        }

        // Show paywall if needed after setup
        subscriptionManager.showPaywallIfNeeded()
    }
}
