import SwiftUI
import PDFKit
import VisionKit
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var signatureManager: SignatureManager

    @State private var showingDocumentPicker = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingSubscriptionSheet = false
    @State private var selectedDocument: StoredPDFDocument?
    @State private var showingDeleteAlert = false
    @State private var documentToDelete: StoredPDFDocument?
    @State private var showingMergeView = false
    @State private var showingSplitView = false
    @State private var showingRenameAlert = false
    @State private var documentToRename: StoredPDFDocument?
    @State private var newDocumentName = ""
    @State private var showingErrorAlert = false

    var body: some View {
        NavigationView {
            mainContentView
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if !subscriptionManager.isSubscribed {
                premiumBanner
            }

            if documentManager.documents.isEmpty {
                emptyStateView
            } else {
                documentListView
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
        .background(AppTheme.Colors.background)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                addMenu
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            documentPickerSheet
        }
        .sheet(isPresented: $showingImagePicker) {
            imagePickerSheet
        }
        .sheet(isPresented: $showingCamera) {
            cameraSheet
        }
        .fullScreenCover(item: $selectedDocument) { document in
            pdfViewerCover(for: document)
        }
        .sheet(isPresented: $showingSubscriptionSheet) {
            PaywallView()
        }
        .sheet(isPresented: $showingMergeView) {
            PDFMergeView()
        }
        .sheet(isPresented: $showingSplitView) {
            PDFSplitView()
        }
        .alert("Delete Document", isPresented: $showingDeleteAlert) {
            deleteAlertButtons
        } message: {
            Text("Are you sure you want to delete this document? This action cannot be undone.")
        }
        .alert("Rename Document", isPresented: $showingRenameAlert) {
            renameAlertContent
        } message: {
            Text("Enter a new name for this document")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                documentManager.errorMessage = nil
            }
        } message: {
            Text(documentManager.errorMessage ?? "An error occurred")
        }
        .onChange(of: documentManager.errorMessage) { newValue in
            showingErrorAlert = newValue != nil
        }
    }

    // MARK: - Add Menu

    @ViewBuilder
    private var addMenu: some View {
        Menu {
            addMenuContent
        } label: {
            addMenuLabel
        } primaryAction: {
            HapticManager.shared.buttonTap()
            showingDocumentPicker = true
        }
    }

    @ViewBuilder
    private var addMenuContent: some View {
        Button {
            HapticManager.shared.buttonTap()
            showingDocumentPicker = true
        } label: {
            Label("Import PDF", systemImage: "doc.badge.plus")
        }

        Button {
            HapticManager.shared.buttonTap()
            if subscriptionManager.canUseBatchProcessing {
                showingImagePicker = true
            } else {
                subscriptionManager.presentPaywall()
            }
        } label: {
            Label("Import Photos", systemImage: "photo.on.rectangle")
            if !subscriptionManager.canUseBatchProcessing {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }

        if VNDocumentCameraViewController.isSupported {
            Button {
                HapticManager.shared.buttonTap()
                if subscriptionManager.canUseBatchProcessing {
                    showingCamera = true
                } else {
                    subscriptionManager.presentPaywall()
                }
            } label: {
                Label("Scan Document", systemImage: "camera")
                if !subscriptionManager.canUseBatchProcessing {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                }
            }
        }

        Divider()

        Button {
            HapticManager.shared.buttonTap()
            if subscriptionManager.canUseAdvancedEditing {
                showingMergeView = true
            } else {
                subscriptionManager.presentPaywall()
            }
        } label: {
            Label("Merge PDFs", systemImage: "doc.on.doc")
            if !subscriptionManager.canUseAdvancedEditing {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }

        Button {
            HapticManager.shared.buttonTap()
            if subscriptionManager.canUseAdvancedEditing {
                showingSplitView = true
            } else {
                subscriptionManager.presentPaywall()
            }
        } label: {
            Label("Split PDF", systemImage: "scissors")
            if !subscriptionManager.canUseAdvancedEditing {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var addMenuLabel: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.primary)
                .frame(width: 32, height: 32)
                .shadow(
                    color: AppTheme.Colors.primary.opacity(0.3),
                    radius: 4,
                    x: 0,
                    y: 2
                )

            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private var documentPickerSheet: some View {
        DocumentPicker { url in
            Task {
                do {
                    _ = try await documentManager.importDocument(from: url)
                } catch {
                    documentManager.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var imagePickerSheet: some View {
        if subscriptionManager.canUseBatchProcessing {
            ImagePicker { images in
                Task {
                    do {
                        _ = try await documentManager.createPDFFromImages(images)
                    } catch {
                        documentManager.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cameraSheet: some View {
        if VNDocumentCameraViewController.isSupported && subscriptionManager.canUseBatchProcessing {
            DocumentCameraView { images in
                Task {
                    do {
                        _ = try await documentManager.createPDFFromImages(images)
                    } catch {
                        documentManager.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pdfViewerCover(for document: StoredPDFDocument) -> some View {
        PDFViewerViewNew(document: document, context: documentManager.context)
            .environmentObject(documentManager)
            .environmentObject(subscriptionManager)
            .environmentObject(signatureManager)
    }

    // MARK: - Alert Content

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Delete", role: .destructive) {
            if let document = documentToDelete {
                documentManager.deleteDocument(document)
            }
        }
        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private var renameAlertContent: some View {
        TextField("Document name", text: $newDocumentName)
        Button("Rename") {
            if let document = documentToRename {
                renameDocument(document, newName: newDocumentName)
            }
        }
        Button("Cancel", role: .cancel) {
            documentToRename = nil
            newDocumentName = ""
        }
    }

    private var premiumBanner: some View {
        Button {
            HapticManager.shared.buttonTap()
            subscriptionManager.presentPaywall()
        } label: {
            HStack(spacing: 12) {
                // Premium icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.Colors.premium,
                                    AppTheme.Colors.premium.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade to Premium")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textPrimary)

                    Text("Unlimited signatures • Merge & split PDFs • Advanced editing")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.premium.opacity(0.08),
                                AppTheme.Colors.premium.opacity(0.12)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.premium.opacity(0.3),
                                AppTheme.Colors.premium.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "doc.text",
            title: "No Documents",
            description: "Import PDFs, take photos, or scan documents to get started with signing and editing.",
            primaryAction: EmptyStateAction("Import PDF", icon: "doc.badge.plus") {
                HapticManager.shared.buttonTap()
                showingDocumentPicker = true
            },
            secondaryAction: EmptyStateAction("Import Photos", icon: "photo.on.rectangle") {
                HapticManager.shared.buttonTap()
                if subscriptionManager.canUseBatchProcessing {
                    showingImagePicker = true
                } else {
                    subscriptionManager.presentPaywall()
                }
            },
            tertiaryAction: VNDocumentCameraViewController.isSupported
                ? EmptyStateAction("Scan Document", icon: "camera") {
                    HapticManager.shared.buttonTap()
                    showingCamera = true
                }
                : nil
        )
    }

    private var documentListView: some View {
        List {
            ForEach(documentManager.documents, id: \.id) { document in
                DocumentRowView(document: document) {
                    HapticManager.shared.buttonTap()
                    selectedDocument = document
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        HapticManager.shared.importantAction()
                        documentToDelete = document
                        showingDeleteAlert = true
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Rename") {
                        HapticManager.shared.buttonTap()
                        documentToRename = document
                        newDocumentName = document.name ?? ""
                        showingRenameAlert = true
                    }
                    .tint(.blue)

                    Button("Share") {
                        HapticManager.shared.buttonTap()
                        shareDocument(document)
                    }
                    .tint(AppTheme.Colors.primary)

                    Button("Duplicate") {
                        HapticManager.shared.buttonTap()
                        if subscriptionManager.canUseAdvancedEditing {
                            duplicateDocument(document)
                        } else {
                            subscriptionManager.presentPaywall()
                        }
                    }
                    .tint(subscriptionManager.canUseAdvancedEditing ? AppTheme.Colors.success : AppTheme.Colors.premium)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 6,
                    leading: 16,
                    bottom: 6,
                    trailing: 16
                ))
            }
        }
        .listStyle(.plain)
        .background(AppTheme.Colors.background)
        .refreshable {
            HapticManager.shared.subtle()
            documentManager.refreshDocuments()
        }
    }

    private func shareDocument(_ document: StoredPDFDocument) {
        Task {
            do {
                let url = try await documentManager.exportDocument(document)
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityVC, animated: true)

                    // Track successful export for review
                    ReviewRequestManager.shared.recordPDFExported()
                }
            } catch {
                documentManager.errorMessage = error.localizedDescription
                ReviewRequestManager.shared.recordError()
            }
        }
    }

    private func duplicateDocument(_ document: StoredPDFDocument) {
        Task {
            do {
                _ = try await documentManager.duplicateDocument(document)
            } catch {
                documentManager.errorMessage = error.localizedDescription
            }
        }
    }

    private func renameDocument(_ document: StoredPDFDocument, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            documentManager.errorMessage = "Document name cannot be empty"
            return
        }

        document.name = trimmedName
        document.lastModified = Date()
        documentManager.saveContext()
        HapticManager.shared.success()

        // Clear state
        documentToRename = nil
        newDocumentName = ""
    }
}

struct DocumentRowView: View {
    let document: StoredPDFDocument
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Enhanced thumbnail
                thumbnailView

                // Document info with improved hierarchy
                VStack(alignment: .leading, spacing: 6) {
                    // Title
                    Text(document.name ?? "Untitled Document")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Metadata row with improved icons
                    HStack(spacing: 12) {
                        // Page count
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textTertiary)
                            Text("\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages")")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }

                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textTertiary.opacity(0.5))

                        // File size
                        Text(formatFileSize(document.fileSize))
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    // Last modified with relative time
                    if let lastModified = document.lastModified {
                        Text("Modified \(lastModified, format: .relative(presentation: .named))")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.Colors.border.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(
                        color: isPressed ? AppTheme.Colors.primary.opacity(0.1) : Color.black.opacity(0.04),
                        radius: isPressed ? 8 : 4,
                        x: 0,
                        y: isPressed ? 4 : 2
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
            if pressing {
                HapticManager.shared.selection()
            }
        }, perform: {})
    }

    private var thumbnailView: some View {
        ZStack {
            // Enhanced thumbnail container
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.98, blue: 0.99),
                            Color(red: 0.96, green: 0.96, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppTheme.Colors.border.opacity(0.15),
                                    AppTheme.Colors.border.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )

            // Thumbnail content
            Group {
                if let thumbnailData = document.thumbnailData,
                   let thumbnail = UIImage(data: thumbnailData) {
                    // Actual PDF thumbnail
                    ZStack {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 70, height: 85)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        // PDF badge overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("PDF")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(AppTheme.Colors.primary.opacity(0.9))
                                    )
                                    .padding(4)
                            }
                        }
                    }
                } else {
                    // Placeholder for documents without thumbnail
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        AppTheme.Colors.primary,
                                        AppTheme.Colors.primaryDark
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("PDF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }

            // Page indicator for multi-page documents
            if document.pageCount > 1 {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.primary)
                                .frame(width: 20, height: 20)
                            Text("\(min(document.pageCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 5, y: -5)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 70, height: 85)
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        let subscriptionManager = SubscriptionManager()
        HomeView()
            .environmentObject(DocumentManager())
            .environmentObject(subscriptionManager)
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
    }
}