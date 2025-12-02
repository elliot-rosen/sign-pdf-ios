import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let primaryAction: EmptyStateAction?
    let secondaryAction: EmptyStateAction?
    let tertiaryAction: EmptyStateAction?

    init(
        icon: String,
        title: String,
        description: String,
        primaryAction: EmptyStateAction? = nil,
        secondaryAction: EmptyStateAction? = nil,
        tertiaryAction: EmptyStateAction? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.tertiaryAction = tertiaryAction
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            VStack(spacing: AppTheme.Spacing.lg) {
                // Icon with subtle animation
                Image(systemName: icon)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.secondary.opacity(0.6),
                                AppTheme.Colors.secondary.opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(1.0)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: UUID()
                    )

                VStack(spacing: AppTheme.Spacing.sm) {
                    Text(title)
                        .font(AppTheme.Typography.title2)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(description)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }

            VStack(spacing: AppTheme.Spacing.md) {
                if let primaryAction = primaryAction {
                    Button(action: primaryAction.action) {
                        Label(primaryAction.title, systemImage: primaryAction.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .onTapGesture {
                        HapticManager.shared.buttonTap()
                    }
                }

                if let secondaryAction = secondaryAction {
                    Button(action: secondaryAction.action) {
                        Label(secondaryAction.title, systemImage: secondaryAction.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .onTapGesture {
                        HapticManager.shared.buttonTap()
                    }
                }

                if let tertiaryAction = tertiaryAction {
                    Button(action: tertiaryAction.action) {
                        Label(tertiaryAction.title, systemImage: tertiaryAction.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .onTapGesture {
                        HapticManager.shared.buttonTap()
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

struct EmptyStateAction {
    let title: String
    let icon: String
    let action: () -> Void

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
}

#Preview {
    EmptyStateView(
        icon: "doc.text",
        title: "No Documents",
        description: "Import PDFs, take photos, or scan documents to get started with signing and editing.",
        primaryAction: EmptyStateAction("Import PDF", icon: "doc.badge.plus") {
            print("Import PDF")
        },
        secondaryAction: EmptyStateAction("Import Photos", icon: "photo.on.rectangle") {
            print("Import Photos")
        },
        tertiaryAction: EmptyStateAction("Scan Document", icon: "camera") {
            print("Scan Document")
        }
    )
}