import SwiftUI

struct SignaturePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    let onSignatureSelected: (Signature) -> Void

    @State private var showDrawingView = false
    @State private var showUpgradePrompt = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppTheme.Spacing.md)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if signatureManager.signatures.isEmpty {
                    emptyState
                } else {
                    signatureGrid
                }
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("Select Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        handleAddSignature()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showDrawingView) {
                SignatureDrawingView()
            }
            .upgradePromptOverlay(
                isPresented: $showUpgradePrompt,
                feature: "Unlimited Signatures",
                featureIcon: "signature",
                features: [
                    "Save unlimited signatures",
                    "Combine multiple PDFs",
                    "No watermarks on exports"
                ]
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "signature")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.Colors.textTertiary)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Signatures")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)

                Text("Create a signature to add it to your document")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                handleAddSignature()
            } label: {
                Label("Create Signature", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppTheme.Spacing.xxl)
        }
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Signature Grid

    private var signatureGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.md) {
                ForEach(signatureManager.signatures, id: \.id) { signature in
                    SignaturePickerCard(signature: signature)
                        .onTapGesture {
                            HapticManager.shared.selection()
                            onSignatureSelected(signature)
                            dismiss()
                        }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }

    // MARK: - Actions

    private func handleAddSignature() {
        HapticManager.shared.buttonTap()

        if signatureManager.canCreateSignature {
            showDrawingView = true
        } else {
            showUpgradePrompt = true
        }
    }
}

// MARK: - Signature Picker Card

struct SignaturePickerCard: View {
    let signature: Signature

    @EnvironmentObject var signatureManager: SignatureManager

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Signature image - always display in light mode to preserve signature colors
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                    .fill(Color.white)

                if let image = signatureManager.imageForSignature(signature) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(AppTheme.Spacing.sm)
                } else {
                    Image(systemName: "signature")
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 70)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .environment(\.colorScheme, .light)

            // Signature name
            Text(signature.name ?? "Untitled")
                .font(AppTheme.Typography.caption1)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.CornerRadius.md)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    SignaturePickerSheet { signature in
        print("Selected: \(signature.name ?? "")")
    }
    .environmentObject(SignatureManager(subscriptionManager: SubscriptionManager()))
    .environmentObject(SubscriptionManager())
}
