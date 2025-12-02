import SwiftUI

struct UpgradePromptView: View {
    let feature: String
    let description: String
    let icon: String
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Header with dismiss button
            HStack {
                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            // Icon and content
            VStack(spacing: AppTheme.Spacing.md) {
                // Premium icon
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.premiumGradient)
                        .frame(width: 64, height: 64)

                    Image(systemName: icon)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .shadow(
                    color: AppTheme.Colors.premium.opacity(0.3),
                    radius: 12,
                    x: 0,
                    y: 6
                )

                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("Upgrade to Premium")
                        .font(AppTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.textPrimary)

                    Text(feature)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.premium)
                        .fontWeight(.semibold)

                    Text(description)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }

            // Features list
            VStack(spacing: AppTheme.Spacing.sm) {
                UpgradeFeatureRow(icon: "signature", text: "Unlimited signatures")
                UpgradeFeatureRow(icon: "doc.text.image", text: "Advanced PDF editing")
                UpgradeFeatureRow(icon: "rectangle.stack", text: "Batch processing")
                UpgradeFeatureRow(icon: "paintbrush.pointed", text: "Custom stamps & watermarks")
            }

            // Upgrade button
            Button(action: onUpgrade) {
                Text("Upgrade Now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PremiumButtonStyle())

            // Cancel button
            Button("Maybe Later", action: onDismiss)
                .font(AppTheme.Typography.callout)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl)
                .fill(AppTheme.Colors.surface)
                .shadow(
                    color: AppTheme.Shadows.large.color,
                    radius: AppTheme.Shadows.large.radius,
                    x: AppTheme.Shadows.large.x,
                    y: AppTheme.Shadows.large.y
                )
        )
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

struct UpgradeFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundColor(AppTheme.Colors.premium)
                .frame(width: 20)

            Text(text)
                .font(AppTheme.Typography.callout)
                .foregroundColor(AppTheme.Colors.textPrimary)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundColor(AppTheme.Colors.success)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }
}

// MARK: - Overlay Modifier

struct UpgradePromptOverlay: ViewModifier {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showUpgradePrompt = false

    let feature: String
    let description: String
    let icon: String
    let requiresPremium: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if showUpgradePrompt {
                        ZStack {
                            // Semi-transparent background
                            Color.black.opacity(0.6)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        showUpgradePrompt = false
                                    }
                                }

                            // Upgrade prompt
                            UpgradePromptView(
                                feature: feature,
                                description: description,
                                icon: icon,
                                onUpgrade: {
                                    showUpgradePrompt = false
                                    subscriptionManager.presentPaywall()
                                },
                                onDismiss: {
                                    withAnimation(.spring()) {
                                        showUpgradePrompt = false
                                    }
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            )
            .onTapGesture {
                if requiresPremium && !subscriptionManager.isSubscribed {
                    withAnimation(.spring()) {
                        showUpgradePrompt = true
                    }
                }
            }
    }
}

extension View {
    func upgradePrompt(
        feature: String,
        description: String,
        icon: String,
        requiresPremium: Bool = true
    ) -> some View {
        self.modifier(
            UpgradePromptOverlay(
                feature: feature,
                description: description,
                icon: icon,
                requiresPremium: requiresPremium
            )
        )
    }
}

#Preview("Upgrade Prompt") {
    ZStack {
        AppTheme.Colors.background
            .ignoresSafeArea()

        UpgradePromptView(
            feature: "Advanced PDF Editing",
            description: "Merge, split, rotate pages and more with professional editing tools.",
            icon: "doc.text.image",
            onUpgrade: {},
            onDismiss: {}
        )
    }
}