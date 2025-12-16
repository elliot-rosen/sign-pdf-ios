import SwiftUI
import VisionKit

struct HomeView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var showDocumentPicker = false
    @State private var showImagePicker = false
    @State private var showDocumentCamera = false
    @State private var showCameraPermission = false
    @State private var selectedDocument: StoredPDFDocument?
    @State private var showViewer = false
    @State private var documentToDelete: StoredPDFDocument?
    @State private var showDeleteConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    @StateObject private var cameraPermissionManager = CameraPermissionManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Premium banner for non-subscribers
                if !subscriptionManager.isSubscribed {
                    PremiumBanner {
                        HapticManager.shared.buttonTap()
                        subscriptionManager.presentPaywall()
                    }
                }

                // Content
                if documentManager.documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    importMenu
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    importPDF(from: url)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker { images in
                    createPDFFromImages(images)
                }
            }
            .sheet(isPresented: $showDocumentCamera) {
                DocumentCameraView { images in
                    createPDFFromImages(images)
                }
            }
            .sheet(isPresented: $showCameraPermission) {
                CameraPermissionView {
                    showDocumentCamera = true
                }
            }
            .navigationDestination(isPresented: $showViewer) {
                if let document = selectedDocument {
                    PDFViewerView(document: document)
                }
            }
            .confirmationDialog(
                "Delete Document",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let document = documentToDelete {
                        deleteDocument(document)
                    }
                }
                Button("Cancel", role: .cancel) {
                    documentToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this document? This action cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if documentManager.isLoading {
                    LoadingStateView(message: "Processing...")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "doc.text",
            title: "No Documents",
            description: "Import a PDF or scan a document to get started",
            primaryAction: EmptyStateAction("Import PDF", icon: "doc.badge.plus") {
                HapticManager.shared.buttonTap()
                showDocumentPicker = true
            },
            secondaryAction: EmptyStateAction("Scan Document", icon: "doc.viewfinder") {
                HapticManager.shared.buttonTap()
                handleScanDocumentTap()
            }
        )
    }

    // MARK: - Document List

    private var documentList: some View {
        List {
            ForEach(documentManager.documents, id: \.id) { document in
                DocumentRow(document: document)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.selection()
                        selectedDocument = document
                        showViewer = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            documentToDelete = document
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            HapticManager.shared.selection()
            documentManager.loadDocuments()
        }
    }

    // MARK: - Import Menu

    private var importMenu: some View {
        Menu {
            Button {
                HapticManager.shared.buttonTap()
                showDocumentPicker = true
            } label: {
                Label("Import PDF", systemImage: "doc.badge.plus")
            }

            Button {
                HapticManager.shared.buttonTap()
                showImagePicker = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }

            if VNDocumentCameraViewController.isSupported {
                Button {
                    HapticManager.shared.buttonTap()
                    handleScanDocumentTap()
                } label: {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    // MARK: - Actions

    private func handleScanDocumentTap() {
        cameraPermissionManager.checkPermissionStatus()
        switch cameraPermissionManager.permissionStatus {
        case .authorized:
            showDocumentCamera = true
        case .notDetermined:
            Task {
                let granted = await cameraPermissionManager.requestPermission()
                if granted {
                    showDocumentCamera = true
                } else {
                    showCameraPermission = true
                }
            }
        case .denied, .restricted:
            showCameraPermission = true
        }
    }

    private func importPDF(from url: URL) {
        Task {
            do {
                _ = try await documentManager.importDocument(from: url)
                HapticManager.shared.success()
            } catch {
                HapticManager.shared.error()
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func createPDFFromImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }

        Task {
            do {
                _ = try await documentManager.createPDFFromImages(images)
                HapticManager.shared.success()
            } catch {
                HapticManager.shared.error()
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func deleteDocument(_ document: StoredPDFDocument) {
        HapticManager.shared.buttonTap()
        documentManager.deleteDocument(document)
        documentToDelete = nil
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: StoredPDFDocument

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                    .fill(AppTheme.Colors.surface)

                if let thumbnailData = document.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm))
                } else {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
            }
            .frame(width: 50, height: 65)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                    .stroke(AppTheme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )

            // Document info
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(document.name ?? "Untitled")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: AppTheme.Spacing.sm) {
                    // Page count
                    Label("\(document.pageCount) pages", systemImage: "doc.on.doc")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    // File size
                    Text(formattedFileSize)
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }

                // Date
                Text(formattedDate)
                    .font(AppTheme.Typography.caption2)
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var formattedFileSize: String {
        let bytes = document.fileSize
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private var formattedDate: String {
        guard let date = document.lastModified ?? document.createdAt else {
            return "Unknown date"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Premium Banner

struct PremiumBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade to Premium")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary)

                    Text("Unlimited signatures, no watermarks")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.5), Color.pink.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

#Preview {
    HomeView()
        .environmentObject(DocumentManager())
        .environmentObject(SignatureManager(subscriptionManager: SubscriptionManager()))
        .environmentObject(SubscriptionManager())
}

#Preview("Premium Banner") {
    PremiumBanner {
        print("Tapped")
    }
    .padding()
}
