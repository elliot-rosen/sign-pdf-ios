import SwiftUI
import UIKit

// MARK: - App Theme
struct AppTheme {
    static let shared = AppTheme()
    private init() {}
}

// MARK: - Colors
extension AppTheme {
    struct Colors {
        // Primary brand colors
        static let primary = Color("PrimaryColor")
        static let primaryLight = Color("PrimaryLightColor")
        static let primaryDark = Color("PrimaryDarkColor")

        // Secondary colors
        static let secondary = Color("SecondaryColor")
        static let secondaryLight = Color("SecondaryLightColor")

        // Semantic colors
        static let success = Color("SuccessColor")
        static let warning = Color("WarningColor")
        static let error = Color("ErrorColor")
        static let info = Color("InfoColor")

        // Surface colors
        static let surface = Color("SurfaceColor")
        static let surfaceElevated = Color("SurfaceElevatedColor")
        static let background = Color("BackgroundColor")
        static let backgroundSecondary = Color("BackgroundSecondaryColor")

        // Text colors
        static let textPrimary = Color("TextPrimaryColor")
        static let textSecondary = Color("TextSecondaryColor")
        static let textTertiary = Color("TextTertiaryColor")
        static let textOnPrimary = Color("TextOnPrimaryColor")

        // Border and separator
        static let border = Color("BorderColor")
        static let separator = Color("SeparatorColor")

        // Premium colors
        static let premium = Color("PremiumColor")
        static let premiumGradient = LinearGradient(
            colors: [Color("PremiumColor"), Color("PremiumLightColor")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography
extension AppTheme {
    struct Typography {
        // Headings
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title1 = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)

        // Body text
        static let headline = Font.headline.weight(.medium)
        static let body = Font.body
        static let bodyMedium = Font.body.weight(.medium)
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption1 = Font.caption
        static let caption2 = Font.caption2

        // Custom styles
        static let button = Font.headline.weight(.medium)
        static let navigationTitle = Font.title2.weight(.bold)
    }
}

// MARK: - Spacing
extension AppTheme {
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64

        // Semantic spacing
        static let padding = md
        static let margin = lg
        static let inset = sm
        static let gap = md
    }
}

// MARK: - Corner Radius
extension AppTheme {
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24

        // Semantic radius
        static let button = md
        static let card = lg
        static let modal = xl
    }
}

// MARK: - Shadows
extension AppTheme {
    struct Shadows {
        static let small = Shadow(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )

        static let medium = Shadow(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )

        static let large = Shadow(
            color: Color.black.opacity(0.2),
            radius: 16,
            x: 0,
            y: 8
        )
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Animation Durations
extension AppTheme {
    struct Animation {
        static let fast: Double = 0.2
        static let medium: Double = 0.3
        static let slow: Double = 0.5

        // Animation curves
        static let spring = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.8)
        static let easeInOut = SwiftUI.Animation.easeInOut(duration: medium)
        static let bouncy = SwiftUI.Animation.interpolatingSpring(stiffness: 300, damping: 30)
    }
}

// MARK: - View Modifiers
extension View {
    // Apply card styling
    func cardStyle() -> some View {
        self
            .background(AppTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card))
            .shadow(
                color: AppTheme.Shadows.small.color,
                radius: AppTheme.Shadows.small.radius,
                x: AppTheme.Shadows.small.x,
                y: AppTheme.Shadows.small.y
            )
    }

    // Apply elevated card styling
    func elevatedCardStyle() -> some View {
        self
            .background(AppTheme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card))
            .shadow(
                color: AppTheme.Shadows.medium.color,
                radius: AppTheme.Shadows.medium.radius,
                x: AppTheme.Shadows.medium.x,
                y: AppTheme.Shadows.medium.y
            )
    }

    // Apply primary button styling
    func primaryButtonStyle() -> some View {
        self
            .font(AppTheme.Typography.button)
            .foregroundColor(AppTheme.Colors.textOnPrimary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                    .fill(AppTheme.Colors.primary)
            )
    }

    // Apply secondary button styling
    func secondaryButtonStyle() -> some View {
        self
            .font(AppTheme.Typography.button)
            .foregroundColor(AppTheme.Colors.primary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                    .stroke(AppTheme.Colors.primary, lineWidth: 1.5)
            )
    }

    // Apply premium button styling
    func premiumButtonStyle() -> some View {
        self
            .font(AppTheme.Typography.button)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)
                    .fill(AppTheme.Colors.premiumGradient)
            )
            .shadow(
                color: AppTheme.Colors.premium.opacity(0.3),
                radius: 8,
                x: 0,
                y: 4
            )
    }

    // Haptic feedback
    func onTapHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        }
    }
}