import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var showSafari = false
    @State private var safariURL: URL?

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyURL = URL(string: "https://www.apple.com/legal/privacy/")!
    private let supportEmail = "support@noworrieslifestyle.com"

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                Section {
                    subscriptionStatusRow

                    if !subscriptionManager.isSubscribed {
                        Button {
                            HapticManager.shared.buttonTap()
                            subscriptionManager.presentPaywall()
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Upgrade to Premium")
                                    .foregroundColor(AppTheme.Colors.primary)
                            }
                        }
                    }

                    Button {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    } label: {
                        Text("Restore Purchases")
                            .foregroundColor(AppTheme.Colors.primary)
                    }
                } header: {
                    Text("Subscription")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                } header: {
                    Text("About")
                }

                // Legal Section
                Section {
                    Button {
                        safariURL = termsURL
                        showSafari = true
                    } label: {
                        HStack {
                            Text("Terms of Service")
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }

                    Button {
                        safariURL = privacyURL
                        showSafari = true
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }
                } header: {
                    Text("Legal")
                }

                // Support Section
                Section {
                    Button {
                        openMailApp()
                    } label: {
                        HStack {
                            Text("Contact Support")
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }
                } header: {
                    Text("Support")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSafari) {
                if let url = safariURL {
                    SafariView(url: url)
                }
            }
        }
    }

    // MARK: - Subscription Status Row

    private var subscriptionStatusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Status")
                    .font(AppTheme.Typography.body)

                if subscriptionManager.isSubscribed {
                    Text(subscriptionManager.subscriptionDisplayName)
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        Group {
            if subscriptionManager.isSubscribed {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Premium")
                }
                .font(AppTheme.Typography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(
                    LinearGradient(
                        colors: [AppTheme.Colors.primary, AppTheme.Colors.primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(AppTheme.CornerRadius.sm)
            } else {
                Text("Free")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.CornerRadius.sm)
            }
        }
    }

    // MARK: - Actions

    private func openMailApp() {
        let subject = "SignSimple PDF Support"
        let body = "\n\n---\nApp Version: \(appVersion) (\(buildNumber))\nDevice: \(UIDevice.current.model)\niOS: \(UIDevice.current.systemVersion)"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SubscriptionManager())
}
