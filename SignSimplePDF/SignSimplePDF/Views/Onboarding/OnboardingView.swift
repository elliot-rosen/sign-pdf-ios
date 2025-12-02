import SwiftUI

struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background
            AppTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        coordinator.completeOnboarding()
                    }
                    .font(AppTheme.Typography.callout)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.md)
                }

                // Content
                TabView(selection: $coordinator.currentStep) {
                    ForEach(0..<coordinator.onboardingSteps.count, id: \.self) { index in
                        OnboardingStepView(
                            step: coordinator.onboardingSteps[index],
                            isSubscribed: subscriptionManager.isSubscribed
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: coordinator.currentStep)

                // Page indicator and navigation
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Page dots
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(0..<coordinator.onboardingSteps.count, id: \.self) { index in
                            Circle()
                                .fill(index == coordinator.currentStep ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == coordinator.currentStep ? 1.2 : 1.0)
                                .animation(.spring(), value: coordinator.currentStep)
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: AppTheme.Spacing.md) {
                        // Back button
                        if coordinator.currentStep > 0 {
                            Button(action: coordinator.previousStep) {
                                Text("Back")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        Spacer()

                        // Next/Get Started button
                        Button(action: {
                            if coordinator.currentStep == coordinator.onboardingSteps.count - 1 {
                                coordinator.completeOnboarding()
                            } else {
                                coordinator.nextStep()
                            }
                        }) {
                            Text(coordinator.currentStep == coordinator.onboardingSteps.count - 1 ? "Get Started" : "Next")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                }
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
    }
}

struct OnboardingStepView: View {
    let step: OnboardingStep
    let isSubscribed: Bool

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primary.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .overlay(
                        step.isPremium && !isSubscribed
                            ? Circle()
                                .fill(AppTheme.Colors.premiumGradient)
                                .frame(width: 120, height: 120)
                            : nil
                    )

                Image(systemName: step.icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(
                        step.isPremium && !isSubscribed
                            ? .white
                            : AppTheme.Colors.primary
                    )
            }
            .shadow(
                color: step.isPremium && !isSubscribed
                    ? AppTheme.Colors.premium.opacity(0.3)
                    : Color.clear,
                radius: 16,
                x: 0,
                y: 8
            )

            VStack(spacing: AppTheme.Spacing.md) {
                // Title with premium badge
                HStack {
                    Text(step.title)
                        .font(AppTheme.Typography.title1)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    if step.isPremium && !step.isPromo {
                        PremiumFeatureBadge(isUnlocked: isSubscribed, showText: false)
                    }
                }

                // Description
                Text(step.description)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }

            // Features list
            VStack(spacing: AppTheme.Spacing.md) {
                ForEach(step.features, id: \.self) { feature in
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: step.isPremium && !isSubscribed ? "star.fill" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(
                                step.isPremium && !isSubscribed
                                    ? AppTheme.Colors.premium
                                    : AppTheme.Colors.success
                            )

                        Text(feature)
                            .font(AppTheme.Typography.callout)
                            .foregroundColor(AppTheme.Colors.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.xl)
                }
            }

            // Promo section for last step
            if step.isPromo && !isSubscribed {
                VStack(spacing: AppTheme.Spacing.md) {
                    Text("Start your free trial today!")
                        .font(AppTheme.Typography.title3)
                        .foregroundColor(AppTheme.Colors.premium)
                        .fontWeight(.semibold)

                    Text("Cancel anytime")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(AppTheme.Colors.premium.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(AppTheme.Colors.premium.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

#Preview("Onboarding") {
    OnboardingView(coordinator: OnboardingCoordinator(subscriptionManager: SubscriptionManager()))
        .environmentObject(SubscriptionManager())
}