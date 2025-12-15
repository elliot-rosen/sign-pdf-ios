import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var canDismiss = false
    @State private var showFeatures = false
    @State private var showingTermsOfService = false
    @State private var showingPrivacyPolicy = false
    @State private var activateTrial = true

    let dismissCountdown: TimeInterval = 8.0

    // Update these URLs with your actual Terms of Service and Privacy Policy URLs
    private let termsOfServiceURL = URL(string: "https://www.noworrieslifestyle.com/eula")!
    private let privacyPolicyURL = URL(string: "https://www.noworrieslifestyle.com/privacy-policy")!

    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                colors: [
                    AppTheme.Colors.primary.opacity(0.9),
                    AppTheme.Colors.primaryDark
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Semi-transparent overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Header with dismiss button
                    headerSection

                    // Hero section
                    heroSection

                    // Features preview
                    featuresSection

                    // Product selection
                    productSelectionSection

                    // Call to action
                    callToActionSection

                    // Footer
                    footerSection
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .onAppear {
            // Always default to weekly product and trial enabled
            selectedProduct = subscriptionManager.weeklyProduct ?? subscriptionManager.lifetimeProduct
            activateTrial = true

            // Show features with animation
            withAnimation(.spring().delay(0.5)) {
                showFeatures = true
            }
        }
        .task {
            // Ensure products are loaded when paywall appears
            if subscriptionManager.products.isEmpty && !subscriptionManager.isLoadingProducts {
                await subscriptionManager.loadProducts()
                // Update selected product after load
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.weeklyProduct ?? subscriptionManager.lifetimeProduct
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingTermsOfService) {
            SafariView(url: termsOfServiceURL)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            SafariView(url: privacyPolicyURL)
        }
    }

    private var headerSection: some View {
        HStack {
            Spacer()

            // Countdown dismiss button
            Button(action: {
                if canDismiss {
                    subscriptionManager.dismissPaywall()
                }
            }) {
                CircularCountdownView(duration: dismissCountdown) {
                    canDismiss = true
                }
            }
            .disabled(!canDismiss)
            .opacity(canDismiss ? 1.0 : 0.7)
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private var heroSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // App icon or logo
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "signature")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Unlock Premium")
                    .font(AppTheme.Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Professional PDF tools for power users")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var featuresSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            let features = [
                ("signature", "Unlimited Signatures", "Save and manage all your signatures"),
                ("doc.on.doc", "Merge PDFs", "Combine multiple PDFs into one document"),
                ("scissors", "Split PDFs", "Split PDFs into separate documents"),
                ("arrow.up.arrow.down", "Reorder Pages", "Drag and drop to reorganize PDF pages"),
                ("arrow.clockwise", "Rotate Pages", "Rotate individual pages in your PDFs"),
                ("trash", "Delete Pages", "Remove unwanted pages from documents")
            ]

            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                FeatureRow(
                    icon: feature.0,
                    title: feature.1,
                    description: feature.2
                )
                .opacity(showFeatures ? 1.0 : 0.0)
                .offset(x: showFeatures ? 0 : -50)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.8)
                        .delay(Double(index) * 0.1),
                    value: showFeatures
                )
            }
        }
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    private var productSelectionSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Trial toggle (only show if user is eligible and weekly subscription has trial)
            if let weeklyProduct = subscriptionManager.weeklyProduct,
               subscriptionManager.isEligibleForTrial,
               weeklyProduct.subscription?.introductoryOffer?.paymentMode == .freeTrial {

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activate free 3-day trial")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Try all premium features risk-free")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Toggle("", isOn: $activateTrial)
                        .labelsHidden()
                        .tint(AppTheme.Colors.primary)
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.bottom, AppTheme.Spacing.sm)
                .onChange(of: activateTrial) { newValue in
                    withAnimation(.spring()) {
                        if newValue {
                            // When trial is activated, select weekly product
                            selectedProduct = weeklyProduct
                        } else {
                            // When trial is deactivated, select lifetime product if available
                            if let lifetimeProduct = subscriptionManager.lifetimeProduct {
                                selectedProduct = lifetimeProduct
                            }
                        }
                    }
                }
            }

            if subscriptionManager.isLoadingProducts {
                // Loading state
                LoadingProductsView()
            } else if subscriptionManager.products.isEmpty, let error = subscriptionManager.productLoadError {
                // Error state with retry and dismiss options (only if no products loaded)
                ProductLoadErrorView(
                    errorMessage: error,
                    onRetry: {
                        Task {
                            await subscriptionManager.loadProducts()
                        }
                    },
                    onDismiss: {
                        subscriptionManager.dismissPaywall()
                    }
                )
            } else if subscriptionManager.products.isEmpty {
                // Products empty but not loading - trigger reload
                LoadingProductsView()
                    .task {
                        await subscriptionManager.loadProducts()
                    }
            } else {
                // Products loaded successfully - show them
                ForEach(subscriptionManager.products, id: \.id) { product in
                    let isTrialEligible = activateTrial &&
                                          subscriptionManager.isEligibleForTrial &&
                                          product.subscription?.introductoryOffer?.paymentMode == .freeTrial

                    ProductSelectionCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        isEligibleForTrial: isTrialEligible
                    ) {
                        withAnimation(.spring()) {
                            selectedProduct = product
                            // Sync trial toggle with product selection
                            if product.id.contains("lifetime") {
                                activateTrial = false
                            } else if product.id.contains("weekly") &&
                                      subscriptionManager.isEligibleForTrial &&
                                      product.subscription?.introductoryOffer != nil {
                                activateTrial = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var callToActionSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button(action: {
                guard let product = selectedProduct else { return }
                Task {
                    await subscriptionManager.purchase(product)
                }
            }) {
                HStack {
                    if subscriptionManager.purchaseState == .purchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }

                    Text(ctaButtonText)
                        .font(AppTheme.Typography.button)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                        .fill(Color.white)
                )
                .foregroundColor(AppTheme.Colors.primary)
            }
            .disabled(selectedProduct == nil || subscriptionManager.purchaseState == .purchasing)
            .opacity(selectedProduct == nil ? 0.6 : 1.0)

            // Restore purchases
            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            }
            .font(AppTheme.Typography.callout)
            .foregroundColor(.white.opacity(0.8))
        }
    }

    private var footerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text(selectedProduct?.id.contains("lifetime") == true ?
                 "One-time purchase. Lifetime access." :
                 "Auto-renewable subscription. Cancel anytime.")
                .font(AppTheme.Typography.caption1)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.Spacing.lg) {
                Button("Terms of Service") {
                    showingTermsOfService = true
                }
                .font(AppTheme.Typography.caption1)
                .foregroundColor(.white.opacity(0.8))

                Button("Privacy Policy") {
                    showingPrivacyPolicy = true
                }
                .font(AppTheme.Typography.caption1)
                .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.top, AppTheme.Spacing.lg)
    }

    private var ctaButtonText: String {
        guard let product = selectedProduct else {
            return "Select a Plan"
        }

        if subscriptionManager.purchaseState == .purchasing {
            return "Processing..."
        }

        // Check for trial on subscription products (only if trial toggle is on)
        if activateTrial,
           let subscription = product.subscription,
           subscriptionManager.isEligibleForTrial,
           let introOffer = subscription.introductoryOffer,
           introOffer.paymentMode == .freeTrial {
            let period = introOffer.period
            var trialText = ""
            switch period.unit {
            case .day:
                trialText = "\(period.value) Day"
            case .week:
                trialText = "\(period.value) Week"
            case .month:
                trialText = "\(period.value) Month"
            default:
                trialText = ""
            }
            return "Start \(trialText) Free Trial"
        }

        // For lifetime/non-consumable
        if product.type == .nonConsumable {
            return "Buy Now - \(product.displayPrice)"
        }

        // For subscriptions without trial
        return "Subscribe - \(product.displayPrice)"
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(AppTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct LoadingProductsView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)

            Text("Loading subscription options...")
                .font(AppTheme.Typography.callout)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(height: 120)
    }
}

struct ProductLoadErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(errorMessage)
                .font(AppTheme.Typography.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.Spacing.md) {
                Button(action: onDismiss) {
                    Text("Close")
                        .font(AppTheme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                }

                Button(action: onRetry) {
                    Text("Try Again")
                        .font(AppTheme.Typography.button)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                                .fill(Color.white)
                        )
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}