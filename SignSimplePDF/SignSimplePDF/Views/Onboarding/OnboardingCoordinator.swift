import SwiftUI
import Combine

@MainActor
class OnboardingCoordinator: ObservableObject {
    @Published var currentStep = 0
    @Published var showOnboarding = false
    @Published var showPaywall = false

    private let subscriptionManager: SubscriptionManager
    private var cancellables = Set<AnyCancellable>()

    let onboardingSteps = [
        OnboardingStep(
            icon: "signature",
            title: "Sign Documents Anywhere",
            description: "Create and manage your digital signatures with ease. Sign PDFs quickly and securely.",
            features: ["Unlimited signatures with Premium", "Secure signature storage", "One-tap signing"]
        ),
        OnboardingStep(
            icon: "doc.text.image",
            title: "Advanced PDF Editing",
            description: "Edit your PDFs like a pro. Merge, split, rotate, and reorder pages with powerful tools.",
            features: ["Merge multiple PDFs", "Split documents", "Batch process images"],
            isPremium: true
        )
    ]

    init(subscriptionManager: SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        checkOnboardingStatus()
    }

    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        showOnboarding = !hasCompletedOnboarding
    }

    func nextStep() {
        if currentStep < onboardingSteps.count - 1 {
            withAnimation(.spring()) {
                currentStep += 1
            }
        } else {
            completeOnboarding()
        }
    }

    func previousStep() {
        if currentStep > 0 {
            withAnimation(.spring()) {
                currentStep -= 1
            }
        }
    }

    func skipToPaywall() {
        currentStep = onboardingSteps.count - 1
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false

        // Show paywall after onboarding completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.subscriptionManager.presentPaywall()
        }
    }

    func restartOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        currentStep = 0
        showOnboarding = true
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let features: [String]
    let isPremium: Bool
    let isPromo: Bool

    init(icon: String, title: String, description: String, features: [String], isPremium: Bool = false, isPromo: Bool = false) {
        self.icon = icon
        self.title = title
        self.description = description
        self.features = features
        self.isPremium = isPremium
        self.isPromo = isPromo
    }
}