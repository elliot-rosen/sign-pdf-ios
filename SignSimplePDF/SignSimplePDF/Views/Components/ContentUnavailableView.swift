import SwiftUI

// iOS 15 compatible ContentUnavailableView
struct ContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.textTertiary)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTheme.Typography.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)

                if let description = description {
                    description
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
    }
}