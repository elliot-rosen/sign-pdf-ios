import SwiftUI
import PencilKit

struct SignatureView: View {
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var showingSignatureCreator = false
    @State private var showingDeleteAlert = false
    @State private var signatureToDelete: Signature?
    @State private var showingSubscriptionSheet = false

    var body: some View {
        NavigationView {
            VStack {
                if signatureManager.signatures.isEmpty {
                    emptyStateView
                } else {
                    signatureListView
                }
            }
            .navigationTitle("Signatures")
            .navigationBarTitleDisplayMode(.large)
            .background(AppTheme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.buttonTap()
                        if subscriptionManager.isSubscribed || signatureManager.canAddMoreSignatures {
                            showingSignatureCreator = true
                        } else {
                            subscriptionManager.presentPaywall()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    (subscriptionManager.isSubscribed || signatureManager.canAddMoreSignatures)
                                        ? AppTheme.Colors.primary
                                        : AppTheme.Colors.premium
                                )
                                .frame(width: 32, height: 32)
                                .shadow(
                                    color: AppTheme.Colors.primary.opacity(0.3),
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )

                            Image(systemName: (subscriptionManager.isSubscribed || signatureManager.canAddMoreSignatures) ? "plus" : "star.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSignatureCreator) {
                SignatureDrawingView()
                    .environmentObject(signatureManager)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $showingSubscriptionSheet) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .alert("Delete Signature", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let signature = signatureToDelete {
                        signatureManager.deleteSignature(signature)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this signature?")
            }
            .onAppear {
                signatureManager.configure(with: subscriptionManager)
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "signature",
            title: "No Signatures",
            description: "Create your first signature to start signing PDFs quickly and professionally.",
            primaryAction: EmptyStateAction("Create Signature", icon: "plus") {
                HapticManager.shared.buttonTap()
                if subscriptionManager.isSubscribed || signatureManager.canAddMoreSignatures {
                    showingSignatureCreator = true
                } else {
                    subscriptionManager.presentPaywall()
                }
            }
        )
    }

    private var signatureListView: some View {
        VStack {
            if !subscriptionManager.isSubscribed {
                limitWarningView
            }

            List {
                ForEach(signatureManager.signatures, id: \.id) { signature in
                    SignatureRowView(signature: signature) {
                        HapticManager.shared.importantAction()
                        signatureToDelete = signature
                        showingDeleteAlert = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.xs,
                        leading: AppTheme.Spacing.md,
                        bottom: AppTheme.Spacing.xs,
                        trailing: AppTheme.Spacing.md
                    ))
                }
            }
            .listStyle(.plain)
        }
    }

    private var limitWarningView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.premium.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: subscriptionManager.remainingFreeSignatures > 0 ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.Colors.premium)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Free Plan Limit")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary)

                    if subscriptionManager.remainingFreeSignatures > 0 {
                        Text("\(subscriptionManager.remainingFreeSignatures) signature slots remaining")
                            .font(AppTheme.Typography.caption1)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    } else {
                        Text("Upgrade to Premium for unlimited signatures")
                            .font(AppTheme.Typography.caption1)
                            .foregroundColor(AppTheme.Colors.error)
                    }
                }

                Spacer()

                if subscriptionManager.remainingFreeSignatures == 0 {
                    Button("Upgrade") {
                        HapticManager.shared.buttonTap()
                        subscriptionManager.presentPaywall()
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .controlSize(.small)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                .fill(AppTheme.Colors.premium.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .stroke(AppTheme.Colors.premium.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, AppTheme.Spacing.md)
    }
}

struct SignatureRowView: View {
    let signature: Signature
    let onDelete: () -> Void

    @EnvironmentObject var signatureManager: SignatureManager
    @State private var showingRenameAlert = false
    @State private var showingActions = false
    @State private var newName = ""
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            signaturePreview

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(signature.name ?? "Untitled Signature")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(1)

                if let createdAt = signature.createdAt {
                    Text("Created \(createdAt, format: .relative(presentation: .named))")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            Button {
                HapticManager.shared.buttonTap()
                showingActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, AppTheme.Spacing.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                .fill(AppTheme.Colors.surface)
                .shadow(
                    color: AppTheme.Shadows.small.color,
                    radius: isPressed ? AppTheme.Shadows.medium.radius : AppTheme.Shadows.small.radius,
                    x: AppTheme.Shadows.small.x,
                    y: isPressed ? AppTheme.Shadows.medium.y : AppTheme.Shadows.small.y
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(AppTheme.Animation.spring, value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.buttonTap()
            showingActions = true
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                HapticManager.shared.importantAction()
                onDelete()
            }

            Button("Rename") {
                HapticManager.shared.buttonTap()
                newName = signature.name ?? ""
                showingRenameAlert = true
            }
            .tint(AppTheme.Colors.primary)
        }
        .alert("Rename Signature", isPresented: $showingRenameAlert) {
            TextField("Signature name", text: $newName)
            Button("Save") {
                HapticManager.shared.success()
                if !newName.isEmpty {
                    signatureManager.updateSignature(signature, name: newName)
                }
            }
            Button("Cancel", role: .cancel) {
                HapticManager.shared.subtle()
            }
        }
        .confirmationDialog("Signature Options", isPresented: $showingActions, titleVisibility: .visible) {
            Button("Rename") {
                HapticManager.shared.buttonTap()
                newName = signature.name ?? ""
                showingRenameAlert = true
            }

            Button("Delete", role: .destructive) {
                HapticManager.shared.importantAction()
                onDelete()
            }

            Button("Cancel", role: .cancel) { }
        }
    }

    private var signaturePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                        .stroke(AppTheme.Colors.border.opacity(0.3), lineWidth: 1)
                )

            Group {
                if let imageData = signature.imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(AppTheme.Spacing.xs)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "signature")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.Colors.primary)

                        Text("SIG")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
            }
        }
        .frame(width: 80, height: 40)
        .shadow(
            color: AppTheme.Colors.primary.opacity(0.1),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

struct SignatureView_Previews: PreviewProvider {
    static var previews: some View {
        let subscriptionManager = SubscriptionManager()
        SignatureView()
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
            .environmentObject(subscriptionManager)
    }
}
