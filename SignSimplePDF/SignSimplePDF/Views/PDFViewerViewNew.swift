import SwiftUI
import PDFKit
import CoreData

struct PDFViewerViewNew: View {
    let document: StoredPDFDocument
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    // New annotation system bridge
    @StateObject private var annotationBridge: PDFAnnotationIntegrationBridge

    @State private var pdfDocument: PDFKit.PDFDocument?
    @State private var pdfView: PDFView?
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0
    @State private var showingSidebar = false // Default closed on small screens?
    @State private var selectedPage: PDFPage?
    
    @State private var showingSignatureSelector = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var showingRenameAlert = false
    @State private var newDocumentName = ""
    @State private var showingCancelConfirmation = false
    
    // Track key for forcing view refreshes after edits
    @State private var viewID = UUID()

    init(document: StoredPDFDocument, context: NSManagedObjectContext) {
        self.document = document
        _annotationBridge = StateObject(wrappedValue: PDFAnnotationIntegrationBridge(context: context))
    }

    var body: some View {
        NavigationView {
            mainContent
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if isLoading {
                PDFLoadingView(progress: loadingProgress)
                    .transition(.opacity)
            } else if let pdfDoc = pdfDocument {
                pdfContentView(pdfDocument: pdfDoc)
            } else {
                ContentUnavailableView(
                    "Cannot Load PDF",
                    systemImage: "doc.text",
                    description: Text("This PDF file could not be loaded.")
                )
            }
        }
        .navigationTitle(document.name ?? "PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await loadPDF()
        }
        .sheet(isPresented: $showingSignatureSelector) {
            SignatureSelectorViewNew { signature in
                applySignature(signature)
            }
        }
        .alert("Discard Changes?", isPresented: $showingCancelConfirmation) {
            Button("Discard", role: .destructive) {
                annotationBridge.disableAnnotationMode()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onChange(of: errorMessage) { newValue in
            showingErrorAlert = newValue != nil
        }
        .alert("Rename Document", isPresented: $showingRenameAlert) {
            TextField("Document name", text: $newDocumentName)
            Button("Rename") {
                renameDocument(newName: newDocumentName)
            }
            Button("Cancel", role: .cancel) {
                newDocumentName = ""
            }
        } message: {
            Text("Enter a new name for this document")
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { note in
            if let pdfView = note.object as? PDFView,
               pdfView == self.pdfView,
               let page = pdfView.currentPage {
                self.selectedPage = page
            }
        }
    }

    @ViewBuilder
    private func pdfContentView(pdfDocument: PDFKit.PDFDocument) -> some View {
        HStack(spacing: 0) {
            if showingSidebar, let currentPdfView = pdfView {
                PDFThumbnailSidebar(
                    pdfDocument: pdfDocument,
                    selectedPage: $selectedPage,
                    pdfView: $pdfView,
                    onRotate: handleRotatePage,
                    onDelete: handleDeletePage,
                    onReorder: handleReorderPage
                )
                .frame(width: 120)
                .transition(AnyTransition.move(edge: .leading))
                .zIndex(1)

                Divider()
            }

            pdfMainArea(pdfDocument: pdfDocument)
                .zIndex(0)
        }
    }

    @ViewBuilder
    private func pdfMainArea(pdfDocument: PDFKit.PDFDocument) -> some View {
        ZStack {
            PDFKitViewNew(
                pdfDocument: pdfDocument,
                pdfView: $pdfView,
                annotationBridge: annotationBridge,
                document: document
            )
            .id(viewID)

            if annotationBridge.isAnnotating {
                annotationOverlay
            }
        }
    }

    @ViewBuilder
    private var annotationOverlay: some View {
        VStack {
            HStack {
                AnnotationToolbarWrapper(bridge: annotationBridge)
                    .frame(height: 60)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .padding()

                Spacer()
            }

            Spacer()

            if annotationBridge.currentTool != .selection {
                HStack {
                    Spacer()

                    PropertyInspectorWrapper(bridge: annotationBridge)
                        .frame(width: 280, height: 400)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 8)
                        .padding()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3), value: annotationBridge.currentTool)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarItems
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            trailingToolbarItems
        }
    }

    @ViewBuilder
    private var leadingToolbarItems: some View {
        HStack {
            Button {
                cancelEditing()
            } label: {
                Image(systemName: "chevron.left")
            }
            .foregroundColor(AppTheme.Colors.textSecondary)

            Button {
                withAnimation {
                    showingSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundColor(showingSidebar ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var trailingToolbarItems: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                annotationBridge.isAnnotating.toggle()
                if !annotationBridge.isAnnotating {
                    annotationBridge.selectTool(.selection)
                }
            }
        } label: {
            Image(systemName: annotationBridge.isAnnotating ? "pencil.circle.fill" : "pencil.circle")
                .foregroundColor(annotationBridge.isAnnotating ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
                .font(.title3)
        }

        if annotationBridge.isAnnotating {
            undoRedoButtons
        }

        Button("Save") {
            saveDocument()
        }
        .fontWeight(.semibold)
        .disabled(!annotationBridge.hasUnsavedChanges)

        moreMenu
    }

    @ViewBuilder
    private var undoRedoButtons: some View {
        HStack(spacing: 12) {
            Button {
                annotationBridge.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(annotationBridge.canUndo ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
            }
            .disabled(!annotationBridge.canUndo)

            Button {
                annotationBridge.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundColor(annotationBridge.canRedo ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
            }
            .disabled(!annotationBridge.canRedo)
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            Button {
                newDocumentName = document.name ?? ""
                showingRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                shareDocument()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                exportWithAnnotations()
            } label: {
                Label("Export with Annotations", systemImage: "arrow.down.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }

    // MARK: - Helper Methods

    private func loadPDF() async {
        do {
            await MainActor.run {
                loadingProgress = 0.2
            }

            let loadedPDF = try await documentManager.loadPDFDocument(for: document)

            await MainActor.run {
                loadingProgress = 0.8
            }

            // Small delay for smooth transition
            try? await Task.sleep(nanoseconds: 100_000_000)

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.pdfDocument = loadedPDF
                    self.loadingProgress = 1.0
                    self.isLoading = false

                    // Set initial page if available
                    if let firstPage = loadedPDF.page(at: 0) {
                        self.selectedPage = firstPage
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Page Editing Handlers
    
    private func handleRotatePage(page: PDFPage, angle: Int) {
        guard subscriptionManager.canUseAdvancedEditing else {
            subscriptionManager.presentPaywall()
            return
        }
        
        guard let pdfDocument = pdfDocument else { return }
        let index = pdfDocument.index(for: page)
        
        documentManager.rotatePage(in: pdfDocument, pageIndex: index, rotation: angle)
        
        // Refresh logic
        pdfView?.layoutDocumentView()
        annotationBridge.hasUnsavedChanges = true
        
        // Force sidebar refresh
        self.viewID = UUID()
    }
    
    private func handleDeletePage(page: PDFPage) {
        guard subscriptionManager.canUseAdvancedEditing else {
            subscriptionManager.presentPaywall()
            return
        }

        guard let pdfDocument = pdfDocument else { return }
        let index = pdfDocument.index(for: page)
        
        documentManager.deletePage(in: pdfDocument, at: index)
        
        // Refresh logic
        pdfView?.layoutDocumentView()
        annotationBridge.hasUnsavedChanges = true
        
        // Select previous page if possible
        if index > 0, let prevPage = pdfDocument.page(at: index - 1) {
            selectedPage = prevPage
        } else if let firstPage = pdfDocument.page(at: 0) {
            selectedPage = firstPage
        }
        
        self.viewID = UUID()
    }
    
    private func handleReorderPage(from sourceIndex: Int, to destinationIndex: Int) {
        guard subscriptionManager.canUseAdvancedEditing else {
            subscriptionManager.presentPaywall()
            return
        }

        guard let pdfDocument = pdfDocument else { return }
        
        documentManager.reorderPages(in: pdfDocument, from: sourceIndex, to: destinationIndex)
        
        // Refresh logic
        pdfView?.layoutDocumentView()
        annotationBridge.hasUnsavedChanges = true
        self.viewID = UUID()
    }

    private func applySignature(_ signature: Signature) {
        guard let imageData = signature.imageData,
              let pdfView = pdfView,
              let page = pdfView.currentPage else { return }

        let pageIndex = pdfView.document?.index(for: page) ?? 0
        let center = CGPoint(x: page.bounds(for: .mediaBox).width / 2,
                           y: page.bounds(for: .mediaBox).height / 2)

        annotationBridge.addSignature(imageData, at: center, on: pageIndex)
        HapticManager.shared.success()
    }

    private func saveDocument() {
        annotationBridge.save()

        // Save the PDF data
        if let pdfDocument = annotationBridge.exportPDF(),
           let data = pdfDocument.dataRepresentation() {
            Task {
                do {
                    try await documentManager.savePDFData(data, for: document)
                    document.lastModified = Date()
                    documentManager.saveContext()

                    await MainActor.run {
                        HapticManager.shared.success()
                        annotationBridge.hasUnsavedChanges = false // Reset flag
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save document: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func exportWithAnnotations() {
        guard let exportedPDF = annotationBridge.exportPDF() else {
            errorMessage = "Failed to export PDF with annotations"
            return
        }

        // Share the exported PDF
        if let data = exportedPDF.dataRepresentation() {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(document.name ?? "document")_annotated.pdf")

            do {
                try data.write(to: tempURL)

                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityVC, animated: true)
                }
            } catch {
                errorMessage = "Failed to export: \(error.localizedDescription)"
            }
        }
    }

    private func shareDocument() {
        Task {
            do {
                let url = try await documentManager.exportDocument(document)
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityVC, animated: true)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameDocument(newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Document name cannot be empty"
            return
        }

        document.name = trimmedName
        document.lastModified = Date()
        documentManager.saveContext()
        HapticManager.shared.success()
        newDocumentName = ""
    }

    private func cancelEditing() {
        if annotationBridge.hasUnsavedChanges {
            showingCancelConfirmation = true
        } else {
            dismiss()
        }
    }
}

// MARK: - PDFKit View Wrapper

struct PDFKitViewNew: UIViewRepresentable {
    let pdfDocument: PDFKit.PDFDocument
    @Binding var pdfView: PDFView?
    let annotationBridge: PDFAnnotationIntegrationBridge
    let document: StoredPDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = pdfDocument
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.minScaleFactor = 0.5
        view.maxScaleFactor = 5.0
        view.backgroundColor = .systemGray6

        DispatchQueue.main.async {
            self.pdfView = view

            // Configure annotation bridge
            annotationBridge.configure(with: view)
            annotationBridge.loadDocument(document, pdfDocument: pdfDocument)
        }

        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Update if needed
        // We generally avoid recreating the view unless the document actually changes,
        // which is handled by the id() modifier in the parent view if strictly necessary.
    }
}

// MARK: - UI Wrapper Components

struct AnnotationToolbarWrapper: UIViewRepresentable {
    let bridge: PDFAnnotationIntegrationBridge

    func makeUIView(context: Context) -> UIView {
        return bridge.createToolbar()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct PropertyInspectorWrapper: UIViewRepresentable {
    let bridge: PDFAnnotationIntegrationBridge

    func makeUIView(context: Context) -> UIView {
        return bridge.createInspector()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Signature Selector View

struct SignatureSelectorViewNew: View {
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    let onSignatureSelected: (Signature) -> Void

    @State private var showingSignatureCreator = false
    @State private var showingSignaturePicker = false

    var body: some View {
        NavigationView {
            VStack {
                if signatureManager.signatures.isEmpty {
                    EmptyStateView(
                        icon: "signature",
                        title: "No Signatures",
                        description: "Create a signature first to use it in your documents.",
                        primaryAction: EmptyStateAction("Create Signature", icon: "plus") {
                            showingSignatureCreator = true
                        }
                    )
                } else {
                    // Show the new signature picker
                    Button("Select from Saved Signatures") {
                        showingSignaturePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()

                    Button("Create New Signature") {
                        showingSignatureCreator = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Add Signature")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.subtle()
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .sheet(isPresented: $showingSignatureCreator) {
                SignatureDrawingView()
                    .environmentObject(signatureManager)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $showingSignaturePicker) {
                // Use the new SignaturePicker
                SignaturePickerWrapper(signatureManager: signatureManager) { signature in
                    onSignatureSelected(signature)
                    dismiss()
                }
            }
        }
    }
}

// Wrapper for the new SignaturePicker
struct SignaturePickerWrapper: UIViewControllerRepresentable {
    let signatureManager: SignatureManager
    let onSignatureSelected: (Signature) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = SignaturePicker()
        picker.signatureManager = signatureManager
        picker.delegate = context.coordinator
        picker.title = "Select Signature"

        let navController = UINavigationController(rootViewController: picker)
        return navController
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSignatureSelected: onSignatureSelected)
    }

    class Coordinator: NSObject, SignaturePickerDelegate {
        let onSignatureSelected: (Signature) -> Void

        init(onSignatureSelected: @escaping (Signature) -> Void) {
            self.onSignatureSelected = onSignatureSelected
        }

        func signaturePicker(_ picker: SignaturePicker, didSelectSignature signature: Signature) {
            onSignatureSelected(signature)
        }

        func signaturePickerDidCancel(_ picker: SignaturePicker) {
            // Handle cancel if needed
        }

        func signaturePicker(_ picker: SignaturePicker, didCreateSignature imageData: Data) {
            // Handle new signature creation if needed
        }
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - PDF Loading View

struct PDFLoadingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView(value: progress)
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.primary))
                .scaleEffect(1.5)

            Text("Loading PDF...")
                .font(AppTheme.Typography.callout)
                .foregroundColor(AppTheme.Colors.textSecondary)

            if progress > 0 {
                Text("\(Int(progress * 100))%")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
    }
}

// MARK: - Preview

struct PDFViewerViewNew_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let document = StoredPDFDocument(context: context)
        document.name = "Sample Document"
        document.fileName = "sample.pdf"
        let subscriptionManager = SubscriptionManager()

        return PDFViewerViewNew(document: document, context: context)
            .environmentObject(DocumentManager())
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
            .environmentObject(subscriptionManager)
    }
}