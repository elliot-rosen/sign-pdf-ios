import SwiftUI

struct SignatureView: View {
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var showDrawingView = false
    @State private var showUpgradePrompt = false
    @State private var signatureToDelete: Signature?
    @State private var showDeleteConfirmation = false
    @State private var signatureToRename: Signature?
    @State private var showRenameAlert = false
    @State private var newSignatureName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: AppTheme.Spacing.md)
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
            .navigationTitle("Signatures")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton
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
            .confirmationDialog(
                "Delete Signature",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let signature = signatureToDelete {
                        deleteSignature(signature)
                    }
                }
                Button("Cancel", role: .cancel) {
                    signatureToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this signature? This action cannot be undone.")
            }
            .alert("Rename Signature", isPresented: $showRenameAlert) {
                TextField("Name", text: $newSignatureName)
                Button("Cancel", role: .cancel) {
                    signatureToRename = nil
                    newSignatureName = ""
                }
                Button("Save") {
                    if let signature = signatureToRename {
                        renameSignature(signature, to: newSignatureName)
                    }
                }
            } message: {
                Text("Enter a new name for this signature")
            }
        }
    }

    private func renameSignature(_ signature: Signature, to newName: String) {
        let name = newName.isEmpty ? "Untitled" : newName
        HapticManager.shared.buttonTap()
        signatureManager.updateSignatureName(signature, newName: name)
        signatureToRename = nil
        newSignatureName = ""
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "signature",
            title: "No Signatures",
            description: "Create your first signature to start signing documents",
            primaryAction: EmptyStateAction("Create Signature", icon: "plus.circle.fill") {
                handleAddSignature()
            }
        )
    }

    // MARK: - Signature Grid

    private var signatureGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // Signature count info
                if !subscriptionManager.isSubscribed {
                    signatureCountBanner
                }

                // Grid of signatures
                LazyVGrid(columns: columns, spacing: AppTheme.Spacing.md) {
                    ForEach(signatureManager.signatures, id: \.id) { signature in
                        SignatureCard(
                            signature: signature,
                            onRename: {
                                signatureToRename = signature
                                newSignatureName = signature.name ?? ""
                                showRenameAlert = true
                            },
                            onDelete: {
                                signatureToDelete = signature
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }

    // MARK: - Signature Count Banner

    private var maxFreeSignatures: Int { 3 }  // Matches SubscriptionManager.maxFreeSignatures

    private var signatureCountBanner: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppTheme.Colors.info)

            Text("\(signatureManager.signatureCount)/\(maxFreeSignatures) signatures used")
                .font(AppTheme.Typography.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)

            Spacer()

            if signatureManager.signatureCount >= maxFreeSignatures {
                Button("Upgrade") {
                    showUpgradePrompt = true
                }
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.primary)
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.info.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.sm)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            handleAddSignature()
        } label: {
            Image(systemName: "plus")
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

    private func deleteSignature(_ signature: Signature) {
        HapticManager.shared.buttonTap()
        signatureManager.deleteSignature(signature)
        signatureToDelete = nil
    }
}

// MARK: - Signature Card

struct SignatureCard: View {
    let signature: Signature
    let onRename: () -> Void
    let onDelete: () -> Void

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
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 80)
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
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    SignatureView()
        .environmentObject(SignatureManager(subscriptionManager: SubscriptionManager()))
        .environmentObject(SubscriptionManager())
}
