import SwiftUI
import StoreKit

struct ProductSelectionCard: View {
    let product: Product
    let isSelected: Bool
    let isEligibleForTrial: Bool
    let onTap: () -> Void

    private var isLifetime: Bool {
        product.type == .nonConsumable
    }

    private var isWeekly: Bool {
        product.id.contains("weekly")
    }

    private var badgeText: String? {
        if isLifetime {
            return "BEST VALUE"
        } else if isEligibleForTrial && trialPeriodText != nil {
            return "FREE TRIAL"
        }
        return nil
    }

    private var trialPeriodText: String? {
        guard isEligibleForTrial,
              let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer,
              introOffer.paymentMode == .freeTrial else {
            return nil
        }

        let period = introOffer.period
        switch period.unit {
        case .day:
            return "\(period.value) day\(period.value > 1 ? "s" : "")"
        case .week:
            return "\(period.value) week\(period.value > 1 ? "s" : "")"
        case .month:
            return "\(period.value) month\(period.value > 1 ? "s" : "")"
        case .year:
            return "\(period.value) year\(period.value > 1 ? "s" : "")"
        @unknown default:
            return "trial"
        }
    }

    private var productTitle: String {
        if isLifetime {
            return "Lifetime Access"
        } else if isWeekly {
            return "Weekly Premium"
        } else {
            // Fallback - extract from product display name
            return product.displayName
        }
    }

    private var subscriptionPeriodText: String? {
        guard let subscription = product.subscription else {
            return isLifetime ? "One-time purchase" : nil
        }

        let period = subscription.subscriptionPeriod
        switch period.unit {
        case .day:
            return period.value == 1 ? "per day" : "per \(period.value) days"
        case .week:
            return period.value == 1 ? "per week" : "per \(period.value) weeks"
        case .month:
            return period.value == 1 ? "per month" : "per \(period.value) months"
        case .year:
            return period.value == 1 ? "per year" : "per \(period.value) years"
        @unknown default:
            return nil
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Badge
                if let badgeText = badgeText {
                    HStack {
                        Spacer()
                        Text(badgeText)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                                    .fill(
                                        LinearGradient(
                                            colors: isLifetime ? [.green, .mint] : [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        Spacer()
                    }
                    .padding(.top, -AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.sm)
                }

                // Main content
                VStack(spacing: AppTheme.Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            // Plan name
                            Text(productTitle)
                                .font(AppTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            // Trial info or one-time indicator
                            if let trialText = trialPeriodText, isEligibleForTrial {
                                Text("\(trialText) free trial")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.semibold)
                            } else if isLifetime {
                                Text("Pay once, use forever")
                                    .font(.caption)
                                    .foregroundColor(.mint)
                                    .fontWeight(.semibold)
                            }
                        }

                        Spacer()

                        // Selection indicator
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }

                    // Pricing
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            // Main price (from StoreKit)
                            Text(product.displayPrice)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            // Period (dynamic from StoreKit)
                            if let periodText = subscriptionPeriodText {
                                Text(periodText)
                                    .font(.callout)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Spacer()

                        // Value indicator for lifetime
                        if isLifetime {
                            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                                Text("Save forever")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)

                                Text("No recurring fees")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    // Features highlight
                    Text("✓ All premium features ✓ Unlimited usage")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.2)
                        : Color.white.opacity(0.1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                        .stroke(
                            isSelected
                                ? Color.white
                                : Color.white.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(
            color: isSelected ? Color.white.opacity(0.2) : Color.clear,
            radius: isSelected ? 8 : 0,
            x: 0,
            y: isSelected ? 4 : 0
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}