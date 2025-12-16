import SwiftUI

struct PremiumFeatureBadge: View {
    let isUnlocked: Bool
    let showText: Bool

    init(isUnlocked: Bool, showText: Bool = true) {
        self.isUnlocked = isUnlocked
        self.showText = showText
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: isUnlocked ? "star.fill" : "lock.fill")
                .font(.caption2)
                .fontWeight(.semibold)

            if showText {
                Text(isUnlocked ? "PREMIUM" : "PRO")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xs)
                .fill(
                    isUnlocked
                        ? AppTheme.Colors.premiumGradient
                        : LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
        )
        .shadow(
            color: (isUnlocked ? AppTheme.Colors.premium : Color.orange).opacity(0.3),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

struct FeatureRowView: View {
    let icon: String
    let title: String
    let description: String
    let isPremium: Bool
    let isUnlocked: Bool
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String,
        isPremium: Bool = false,
        isUnlocked: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.isPremium = isPremium
        self.isUnlocked = isUnlocked
        self.action = action
    }

    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            isUnlocked || !isPremium
                                ? AppTheme.Colors.primary.opacity(0.1)
                                : AppTheme.Colors.secondary.opacity(0.1)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(
                            isUnlocked || !isPremium
                                ? AppTheme.Colors.primary
                                : AppTheme.Colors.secondary
                        )
                }

                // Content
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack {
                        Text(title)
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(
                                isUnlocked || !isPremium
                                    ? AppTheme.Colors.textPrimary
                                    : AppTheme.Colors.textSecondary
                            )

                        if isPremium {
                            PremiumFeatureBadge(isUnlocked: isUnlocked)
                        }

                        Spacer()
                    }

                    Text(description)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Action indicator
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                    .stroke(
                        isPremium && !isUnlocked
                            ? AppTheme.Colors.premium.opacity(0.2)
                            : AppTheme.Colors.border.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(isPremium && !isUnlocked ? 0.7 : 1.0)
    }
}

#Preview {
    VStack(spacing: AppTheme.Spacing.md) {
        FeatureRowView(
            icon: "signature",
            title: "Unlimited Signatures",
            description: "Save as many signatures as you need",
            isPremium: true,
            isUnlocked: true
        ) {
            print("Tapped")
        }

        FeatureRowView(
            icon: "doc.text.image",
            title: "Advanced PDF Editing",
            description: "Combine, reorder, and delete pages",
            isPremium: true,
            isUnlocked: false
        ) {
            print("Tapped")
        }

        FeatureRowView(
            icon: "square.and.arrow.down",
            title: "Export PDFs",
            description: "Share your signed documents anywhere",
            isPremium: false,
            isUnlocked: true
        ) {
            print("Tapped")
        }
    }
    .padding()
    .background(AppTheme.Colors.background)
}