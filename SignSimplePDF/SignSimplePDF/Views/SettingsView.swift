import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var signatureManager: SignatureManager

    @State private var showingSubscriptionSheet = false
    @State private var showingDeleteAllAlert = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        NavigationView {
            List {
                subscriptionSection
                statisticsSection
                dataSection
                supportSection
                #if DEBUG
                debugSection
                #endif

                // Version info footer
                Section {
                    EmptyView()
                } footer: {
                    VStack(spacing: 4) {
                        Text("SignSimple PDF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Version \(appVersion) • Build \(buildNumber)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .background(AppTheme.Colors.background)
            .sheet(isPresented: $showingSubscriptionSheet) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .alert("Delete All Data", isPresented: $showingDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    deleteAllUserData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all your documents and signatures. This action cannot be undone.")
            }
        }
    }

    private var subscriptionSection: some View {
        Section {
            if subscriptionManager.isSubscribed {
                // Premium active card
                VStack(spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.premiumGradient)
                                .frame(width: 44, height: 44)

                            Image(systemName: "star.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        .shadow(
                            color: AppTheme.Colors.premium.opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 4
                        )

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Premium Active")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.success)

                            Text(subscriptionManager.subscriptionDisplayName)
                                .font(AppTheme.Typography.callout)
                                .foregroundColor(AppTheme.Colors.textPrimary)

                            if let status = subscriptionManager.subscriptionStatus {
                                Text(status.displayText)
                                    .font(AppTheme.Typography.caption1)
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }

                        Spacer()
                    }

                    // Subscription details
                    if subscriptionManager.subscriptionRenewalDate != nil {
                        Divider()

                        VStack(spacing: AppTheme.Spacing.sm) {
                            HStack {
                                Text("Price")
                                    .font(AppTheme.Typography.callout)
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                Spacer()
                                Text(subscriptionManager.subscriptionPrice)
                                    .font(AppTheme.Typography.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                            }

                            HStack {
                                Text("Renews")
                                    .font(AppTheme.Typography.callout)
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                Spacer()
                                Text(subscriptionManager.formattedRenewalDate)
                                    .font(AppTheme.Typography.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(AppTheme.Colors.premium.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(AppTheme.Colors.premium.opacity(0.2), lineWidth: 1)
                        )
                )

                Button("Manage Subscription") {
                    HapticManager.shared.buttonTap()
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundColor(AppTheme.Colors.primary)
            } else {
                // Free tier info
                VStack(spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.secondary.opacity(0.1))
                                .frame(width: 44, height: 44)

                            Image(systemName: "star")
                                .font(.title3)
                                .foregroundColor(AppTheme.Colors.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Free Plan")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.textPrimary)

                            Text("\(subscriptionManager.remainingFreeSignatures) signature slots remaining")
                                .font(AppTheme.Typography.callout)
                                .foregroundColor(subscriptionManager.remainingFreeSignatures > 0 ? AppTheme.Colors.textSecondary : AppTheme.Colors.error)
                        }

                        Spacer()
                    }

                    if subscriptionManager.remainingFreeSignatures == 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.Colors.warning)
                            Text("Upgrade to continue signing documents")
                                .font(AppTheme.Typography.caption1)
                                .foregroundColor(AppTheme.Colors.warning)
                        }
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                                .fill(AppTheme.Colors.warning.opacity(0.1))
                        )
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(AppTheme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(AppTheme.Colors.border.opacity(0.2), lineWidth: 1)
                        )
                )

                Button {
                    HapticManager.shared.buttonTap()
                    subscriptionManager.presentPaywall()
                } label: {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.white)
                        Text("Upgrade to Premium")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumButtonStyle())

                Button("Restore Purchases") {
                    HapticManager.shared.buttonTap()
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .foregroundColor(AppTheme.Colors.primary)
                .disabled(subscriptionManager.purchaseState == .purchasing)
            }
        } header: {
            Text("Subscription")
        }
        .headerProminence(.increased)
    }

    private var statisticsSection: some View {
        Section("Usage") {
            HStack {
                Label {
                    Text("Documents")
                        .font(AppTheme.Typography.body)
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundColor(AppTheme.Colors.primary)
                }
                Spacer()
                Text("\(documentManager.documents.count)")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            HStack {
                Label {
                    Text("Signatures")
                        .font(AppTheme.Typography.body)
                } icon: {
                    Image(systemName: "signature")
                        .foregroundColor(AppTheme.Colors.primary)
                }
                Spacer()
                Text("\(signatureManager.signatures.count)")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            if !subscriptionManager.isSubscribed {
                HStack {
                    Label {
                        Text("Signature Limit")
                            .font(AppTheme.Typography.body)
                    } icon: {
                        Image(systemName: subscriptionManager.remainingFreeSignatures > 0 ? "info.circle" : "exclamationmark.triangle")
                            .foregroundColor(subscriptionManager.remainingFreeSignatures > 0 ? AppTheme.Colors.premium : AppTheme.Colors.warning)
                    }
                    Spacer()
                    Text("\(subscriptionManager.remainingFreeSignatures) / 3 remaining")
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(subscriptionManager.remainingFreeSignatures > 0 ? AppTheme.Colors.premium : AppTheme.Colors.error)
                }
            }
        }
        .headerProminence(.increased)
    }

    private var dataSection: some View {
        Section("Data Management") {
            Button("Export All Documents") {
                HapticManager.shared.buttonTap()
                exportAllDocuments()
            }
            .foregroundColor(AppTheme.Colors.primary)

            Button("Delete All Data", role: .destructive) {
                HapticManager.shared.importantAction()
                showingDeleteAllAlert = true
            }
            .foregroundColor(AppTheme.Colors.error)
        }
        .headerProminence(.increased)
    }

    private var supportSection: some View {
        Section("Support") {
            Button("Rate App") {
                HapticManager.shared.buttonTap()
                requestAppReview()
            }
            .foregroundColor(AppTheme.Colors.primary)

            Button("Contact Support") {
                HapticManager.shared.buttonTap()
                contactSupport()
            }
            .foregroundColor(AppTheme.Colors.primary)

            Link(destination: URL(string: "https://noworrieslifestyle.com/privacy-policy")!) {
                HStack {
                    Text("Privacy Policy")
                        .foregroundColor(AppTheme.Colors.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.footnote)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Link(destination: URL(string: "https://noworrieslifestyle.com/eula")!) {
                HStack {
                    Text("Terms of Service")
                        .foregroundColor(AppTheme.Colors.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.footnote)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .headerProminence(.increased)
    }


    // MARK: - Helper Methods

    private func statusDescription(_ status: SubscriptionManager.SubscriptionStatus) -> String {
        switch status {
        case .active:
            return "Your premium subscription is active"
        case .expired:
            return "Your subscription has expired"
        case .inGracePeriod:
            return "In grace period - please update payment"
        case .inBillingRetryPeriod:
            return "Billing retry in progress"
        case .revoked:
            return "Subscription was revoked"
        case .notSubscribed:
            return "You're currently using the free plan"
        }
    }

    private func deleteAllUserData() {
        // Delete all documents
        for document in documentManager.documents {
            documentManager.deleteDocument(document)
        }

        // Delete all signatures
        for signature in signatureManager.signatures {
            signatureManager.deleteSignature(signature)
        }
    }

    private func exportAllDocuments() {
        // Implementation for exporting all documents
        // This would create a ZIP file with all PDFs
    }

    private func requestAppReview() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    private func contactSupport() {
        // Try the website contact form first, fallback to email
        if let url = URL(string: "https://noworrieslifestyle.com/contact") {
            UIApplication.shared.open(url)
            return
        }

        // Fallback to email
        let email = "support@noworrieslifestyle.com"
        let subject = "SignSimple PDF Support"
        let body = """
        App Version: \(appVersion)
        Build: \(buildNumber)
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)

        Please describe your issue:
        """

        if let url = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(forURLComponents: true) ?? "")&body=\(body.addingPercentEncoding(forURLComponents: true) ?? "")") {
            UIApplication.shared.open(url)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug Options") {
            Toggle(isOn: Binding(
                get: { subscriptionManager.isSubscribed },
                set: { newValue in
                    if newValue {
                        // Simulate premium subscription
                        subscriptionManager.isSubscribed = true
                        subscriptionManager.subscriptionStatus = .active
                        subscriptionManager.showPaywall = false
                    } else {
                        // Reset to free tier
                        subscriptionManager.isSubscribed = false
                        subscriptionManager.subscriptionStatus = .notSubscribed
                    }
                    signatureManager.configure(with: subscriptionManager)
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test Premium Features")
                            .font(AppTheme.Typography.body)
                        Text("Toggle premium subscription for testing")
                            .font(AppTheme.Typography.caption1)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(AppTheme.Colors.premium)
                }
            }

            Button("Reset Onboarding") {
                HapticManager.shared.buttonTap()
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                // The app would need to be restarted for this to take effect
            }
            .foregroundColor(AppTheme.Colors.primary)

            Button("Clear All User Defaults") {
                HapticManager.shared.importantAction()
                if let bundleID = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleID)
                }
            }
            .foregroundColor(AppTheme.Colors.warning)

            // App Store Review Testing
            Button("Test Review Request") {
                HapticManager.shared.buttonTap()
                ReviewRequestManager.shared.forceShowReview()
            }
            .foregroundColor(AppTheme.Colors.primary)

            Button("Reset Review Tracking") {
                HapticManager.shared.buttonTap()
                ReviewRequestManager.shared.resetForTesting()
            }
            .foregroundColor(AppTheme.Colors.warning)

            HStack {
                Text("Debug Mode")
                    .font(AppTheme.Typography.body)
                Spacer()
                Text("Active")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .headerProminence(.increased)
    }
    #endif
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let subscriptionManager = SubscriptionManager()
        SettingsView()
            .environmentObject(subscriptionManager)
            .environmentObject(DocumentManager())
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
    }
}
