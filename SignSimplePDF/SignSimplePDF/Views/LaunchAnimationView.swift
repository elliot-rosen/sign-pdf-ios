import SwiftUI

struct LaunchAnimationView: View {
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var isAnimating = false
    @State private var showPulse = false

    let animationComplete: () -> Void

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.Colors.primary.opacity(0.1),
                    AppTheme.Colors.background
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Logo with pulse effect
                ZStack {
                    // Pulse circles
                    if showPulse {
                        Circle()
                            .stroke(AppTheme.Colors.primary.opacity(0.3), lineWidth: 2)
                            .frame(width: 150, height: 150)
                            .scaleEffect(showPulse ? 1.5 : 1.0)
                            .opacity(showPulse ? 0 : 0.8)
                            .animation(
                                Animation.easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: showPulse
                            )

                        Circle()
                            .stroke(AppTheme.Colors.primary.opacity(0.2), lineWidth: 2)
                            .frame(width: 150, height: 150)
                            .scaleEffect(showPulse ? 1.8 : 1.0)
                            .opacity(showPulse ? 0 : 0.6)
                            .animation(
                                Animation.easeOut(duration: 1.5)
                                    .delay(0.2)
                                    .repeatForever(autoreverses: false),
                                value: showPulse
                            )
                    }

                    // Main logo
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primary)
                            .frame(width: 120, height: 120)

                        Image(systemName: "signature")
                            .font(.system(size: 50, weight: .medium))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(isAnimating ? 0 : -10))
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                }

                // App name and tagline
                VStack(spacing: 8) {
                    Text("SignSimple")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.primary)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    Text("PDF Signing Made Simple")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                }

                Spacer()

                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.primary))
                    .scaleEffect(0.8)
                    .opacity(textOpacity)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Phase 1: Logo appears and scales up
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Phase 2: Start pulse effect
        withAnimation(.easeInOut.delay(0.3)) {
            showPulse = true
        }

        // Phase 3: Text appears
        withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
            textOpacity = 1.0
            textOffset = 0
        }

        // Phase 4: Signature rotation animation
        withAnimation(.easeInOut(duration: 0.5).delay(0.8)) {
            isAnimating = true
        }

        // Complete animation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete()
            }
        }
    }
}

// Alternative minimal launch animation
struct MinimalLaunchView: View {
    @State private var isAnimating = false
    let animationComplete: () -> Void

    var body: some View {
        ZStack {
            AppTheme.Colors.background
                .ignoresSafeArea()

            VStack {
                Image(systemName: "signature")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(AppTheme.Colors.primary)
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0)

                if isAnimating {
                    Text("SignSimple")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isAnimating = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                animationComplete()
            }
        }
    }
}

struct LaunchAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LaunchAnimationView(animationComplete: {})
                .previewDisplayName("Full Animation")

            MinimalLaunchView(animationComplete: {})
                .previewDisplayName("Minimal Animation")
        }
    }
}