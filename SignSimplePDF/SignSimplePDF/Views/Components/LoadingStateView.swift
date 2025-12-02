import SwiftUI

struct LoadingStateView: View {
    let message: String
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.primary.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                AppTheme.Colors.primary,
                                AppTheme.Colors.primaryLight
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: rotationAngle
                    )
            }
            .onAppear {
                rotationAngle = 360
            }

            Text(message)
                .font(AppTheme.Typography.callout)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

struct SkeletonRowView: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Thumbnail skeleton
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 60)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)

                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 12)

                // Date skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [
                    .clear,
                    .white.opacity(0.4),
                    .clear
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 100)
            .offset(x: shimmerOffset)
            .animation(
                .linear(duration: 1.5).repeatForever(autoreverses: false),
                value: shimmerOffset
            )
        )
        .clipped()
        .onAppear {
            shimmerOffset = 300
        }
    }
}

#Preview {
    VStack {
        LoadingStateView(message: "Loading your documents...")
            .frame(height: 200)

        Divider()

        SkeletonRowView()
            .padding()
    }
}