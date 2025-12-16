import SwiftUI
import PDFKit

// MARK: - Resize Handle Enum

enum ResizeHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - Annotation Editing Overlay (UIKit)

class AnnotationEditingOverlay: UIView {
    weak var pdfView: PDFView?

    var selectedAnnotation: PDFAnnotation? {
        didSet { setNeedsDisplay() }
    }
    var selectedPage: PDFPage? {
        didSet { setNeedsDisplay() }
    }

    var onBoundsChanged: (() -> Void)?
    var onDelete: (() -> Void)?

    private var initialBounds: CGRect?
    private var activeHandle: ResizeHandle?
    private var deleteButton: UIButton?

    private let handleSize: CGFloat = 24
    private let handleHitRadius: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // Add pan gesture
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        // Create delete button
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "trash.fill"), for: .normal)
        btn.tintColor = .systemRed
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 16
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.2
        btn.layer.shadowOffset = CGSize(width: 0, height: 2)
        btn.layer.shadowRadius = 4
        btn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        btn.isHidden = true
        addSubview(btn)
        deleteButton = btn
    }

    @objc private func deleteTapped() {
        HapticManager.shared.importantAction()
        onDelete?()
    }

    func refresh() {
        setNeedsDisplay()
        updateDeleteButtonPosition()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let pdfView = pdfView,
              let annotation = selectedAnnotation,
              let page = selectedPage else {
            deleteButton?.isHidden = true
            return
        }

        // Convert PDF bounds to view coordinates
        let pdfBounds = annotation.bounds
        let topLeft = pdfView.convert(CGPoint(x: pdfBounds.minX, y: pdfBounds.maxY), from: page)
        let bottomRight = pdfView.convert(CGPoint(x: pdfBounds.maxX, y: pdfBounds.minY), from: page)

        // Convert from PDFView coords to our overlay coords
        let viewTopLeft = pdfView.convert(topLeft, to: self)
        let viewBottomRight = pdfView.convert(bottomRight, to: self)

        let viewBounds = CGRect(
            x: viewTopLeft.x,
            y: viewTopLeft.y,
            width: viewBottomRight.x - viewTopLeft.x,
            height: viewBottomRight.y - viewTopLeft.y
        )

        guard viewBounds.width > 0 && viewBounds.height > 0 else {
            deleteButton?.isHidden = true
            return
        }

        // Draw selection fill
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.08).cgColor)
        ctx.fill(viewBounds)

        // Draw dashed border
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: [6, 3])
        ctx.stroke(viewBounds)

        // Draw corner handles
        ctx.setLineDash(phase: 0, lengths: [])
        let corners = [
            CGPoint(x: viewBounds.minX, y: viewBounds.minY),
            CGPoint(x: viewBounds.maxX, y: viewBounds.minY),
            CGPoint(x: viewBounds.minX, y: viewBounds.maxY),
            CGPoint(x: viewBounds.maxX, y: viewBounds.maxY)
        ]

        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize/2,
                y: corner.y - handleSize/2,
                width: handleSize,
                height: handleSize
            )

            // White fill
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: handleRect)

            // Blue border
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: handleRect)
        }

        // Position delete button
        deleteButton?.isHidden = false
        deleteButton?.frame = CGRect(x: viewBounds.maxX + 8, y: viewBounds.minY - 32, width: 32, height: 32)
    }

    private func updateDeleteButtonPosition() {
        guard let pdfView = pdfView,
              let annotation = selectedAnnotation,
              let page = selectedPage else {
            deleteButton?.isHidden = true
            return
        }

        let pdfBounds = annotation.bounds
        let topRight = pdfView.convert(CGPoint(x: pdfBounds.maxX, y: pdfBounds.maxY), from: page)
        let viewTopRight = pdfView.convert(topRight, to: self)

        deleteButton?.frame = CGRect(x: viewTopRight.x + 8, y: viewTopRight.y - 32, width: 32, height: 32)
    }

    // MARK: - Pan Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let pdfView = pdfView,
              let annotation = selectedAnnotation,
              let page = selectedPage else { return }

        let location = gesture.location(in: pdfView)
        let pdfPoint = pdfView.convert(location, to: page)

        switch gesture.state {
        case .began:
            initialBounds = annotation.bounds
            activeHandle = detectHandle(at: pdfPoint, bounds: annotation.bounds)

        case .changed:
            guard let initial = initialBounds else { return }

            let translation = gesture.translation(in: pdfView)
            let scale = pdfView.scaleFactor
            let dx = translation.x / scale
            let dy = -translation.y / scale  // Invert for PDF coords

            var newBounds: CGRect
            if let handle = activeHandle {
                newBounds = resizeBounds(initial, dx: dx, dy: dy, handle: handle)
            } else {
                newBounds = initial.offsetBy(dx: dx, dy: dy)
            }

            // Minimum size constraint (allow smaller signatures)
            if newBounds.width >= 15 && newBounds.height >= 15 {
                annotation.bounds = newBounds
                pdfView.setNeedsDisplay()
                setNeedsDisplay()
            }

        case .ended, .cancelled:
            HapticManager.shared.selection()
            onBoundsChanged?()
            initialBounds = nil
            activeHandle = nil

        default:
            break
        }
    }

    private func detectHandle(at point: CGPoint, bounds: CGRect) -> ResizeHandle? {
        // PDF coordinates: origin is bottom-left
        let corners: [(ResizeHandle, CGPoint)] = [
            (.bottomLeft, CGPoint(x: bounds.minX, y: bounds.minY)),
            (.bottomRight, CGPoint(x: bounds.maxX, y: bounds.minY)),
            (.topLeft, CGPoint(x: bounds.minX, y: bounds.maxY)),
            (.topRight, CGPoint(x: bounds.maxX, y: bounds.maxY))
        ]

        for (handle, corner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) <= handleHitRadius {
                return handle
            }
        }
        return nil
    }

    private func resizeBounds(_ initial: CGRect, dx: CGFloat, dy: CGFloat, handle: ResizeHandle) -> CGRect {
        var b = initial
        switch handle {
        case .topLeft:
            b.origin.x += dx
            b.size.width -= dx
            b.size.height += dy
        case .topRight:
            b.size.width += dx
            b.size.height += dy
        case .bottomLeft:
            b.origin.x += dx
            b.origin.y += dy
            b.size.width -= dx
            b.size.height -= dy
        case .bottomRight:
            b.origin.y += dy
            b.size.width += dx
            b.size.height -= dy
        }
        return b
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Check delete button first
        if let btn = deleteButton, !btn.isHidden {
            let btnPoint = convert(point, to: btn)
            if btn.bounds.insetBy(dx: -10, dy: -10).contains(btnPoint) {
                return btn
            }
        }

        // Only intercept touches on or near the annotation
        guard let pdfView = pdfView,
              let annotation = selectedAnnotation,
              let page = selectedPage else {
            return nil
        }

        let pdfBounds = annotation.bounds
        let topLeft = pdfView.convert(CGPoint(x: pdfBounds.minX, y: pdfBounds.maxY), from: page)
        let bottomRight = pdfView.convert(CGPoint(x: pdfBounds.maxX, y: pdfBounds.minY), from: page)
        let viewTopLeft = pdfView.convert(topLeft, to: self)
        let viewBottomRight = pdfView.convert(bottomRight, to: self)

        let viewBounds = CGRect(
            x: viewTopLeft.x,
            y: viewTopLeft.y,
            width: viewBottomRight.x - viewTopLeft.x,
            height: viewBottomRight.y - viewTopLeft.y
        )

        // Expand hit area for handles
        let hitArea = viewBounds.insetBy(dx: -handleHitRadius, dy: -handleHitRadius)

        if hitArea.contains(point) {
            return self
        }

        return nil
    }
}

extension AnnotationEditingOverlay: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - PDF Viewer Representable

struct InteractivePDFView: UIViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var currentPageIndex: Int
    @Binding var selectedAnnotation: PDFAnnotation?
    @Binding var selectedPage: PDFPage?
    @Binding var pdfViewRef: PDFView?
    let isPlacingSignature: Bool
    let onSignaturePlacement: (CGPoint, PDFPage) -> Void
    let onAnnotationChanged: () -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Create PDFView
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(AppTheme.Colors.background)
        pdfView.document = pdfDocument
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pdfView)

        // Create editing overlay
        let overlay = AnnotationEditingOverlay()
        overlay.pdfView = pdfView
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onBoundsChanged = onAnnotationChanged
        overlay.onDelete = onDelete
        container.addSubview(overlay)

        // Layout
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Tap gesture on PDFView
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pdfView.addGestureRecognizer(tap)

        // Store references
        context.coordinator.pdfView = pdfView
        context.coordinator.overlay = overlay

        // Observe zoom/scroll changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewChanged),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Use display link for smooth tracking during scroll
        context.coordinator.startDisplayLink()

        DispatchQueue.main.async {
            self.pdfViewRef = pdfView
        }

        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let pdfView = context.coordinator.pdfView,
              let overlay = context.coordinator.overlay else { return }

        if pdfView.document !== pdfDocument {
            pdfView.document = pdfDocument
        }

        // Update coordinator state
        context.coordinator.isPlacingSignature = isPlacingSignature
        context.coordinator.onSignaturePlacement = onSignaturePlacement

        // Update overlay
        overlay.selectedAnnotation = selectedAnnotation
        overlay.selectedPage = selectedPage
        overlay.onBoundsChanged = onAnnotationChanged
        overlay.onDelete = onDelete
        overlay.refresh()

        // Navigate to page
        if let doc = pdfDocument,
           let page = doc.page(at: currentPageIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        DispatchQueue.main.async {
            if self.pdfViewRef !== pdfView {
                self.pdfViewRef = pdfView
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        let parent: InteractivePDFView
        weak var pdfView: PDFView?
        weak var overlay: AnnotationEditingOverlay?

        var isPlacingSignature = false
        var onSignaturePlacement: ((CGPoint, PDFPage) -> Void)?

        private var displayLink: CADisplayLink?

        init(parent: InteractivePDFView) {
            self.parent = parent
        }

        deinit {
            displayLink?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }

        func startDisplayLink() {
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc func displayLinkFired() {
            overlay?.refresh()
        }

        @objc func pdfViewChanged() {
            overlay?.refresh()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView = pdfView else { return }

            let point = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: point, nearest: true) else { return }
            let pdfPoint = pdfView.convert(point, to: page)

            // Signature placement mode
            if isPlacingSignature {
                onSignaturePlacement?(pdfPoint, page)
                return
            }

            // Check if tapped on annotation
            if let annotation = findAnnotation(at: pdfPoint, on: page) {
                HapticManager.shared.selection()
                DispatchQueue.main.async {
                    self.parent.selectedAnnotation = annotation
                    self.parent.selectedPage = page
                }
            } else {
                // Deselect
                DispatchQueue.main.async {
                    self.parent.selectedAnnotation = nil
                    self.parent.selectedPage = nil
                }
            }
        }

        private func findAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
            for annotation in page.annotations where annotation is ImageStampAnnotation {
                let expanded = annotation.bounds.insetBy(dx: -15, dy: -15)
                if expanded.contains(point) {
                    return annotation
                }
            }
            return nil
        }
    }
}

// MARK: - PDF Viewer View

struct PDFViewerView: View {
    let document: StoredPDFDocument

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var currentPageIndex = 0
    @State private var showThumbnailSidebar = true
    @State private var isPlacingSignature = false
    @State private var pendingSignaturePage: PDFPage?
    @State private var pendingSignaturePoint: CGPoint?
    @State private var showSignaturePicker = false
    @State private var isLoading = true
    @State private var hasUnsavedChanges = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    // Undo support
    @State private var lastPlacedAnnotation: PDFAnnotation?
    @State private var lastPlacedPage: PDFPage?
    @State private var canUndo = false

    // Annotation selection
    @State private var selectedAnnotation: PDFAnnotation?
    @State private var selectedPage: PDFPage?

    // Discard confirmation
    @State private var showDiscardAlert = false

    // Add pages (premium feature)
    @State private var showAddPagesUpgradePrompt = false
    @State private var showAddPagesPicker = false

    private var hasSelection: Bool {
        selectedAnnotation != nil
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Thumbnail sidebar
                if showThumbnailSidebar {
                    PDFThumbnailSidebar(
                        pdfDocument: $pdfDocument,
                        currentPageIndex: $currentPageIndex,
                        onReorder: handleReorder,
                        onDelete: handleDeletePage,
                        onAddPages: handleAddPages,
                        onDocumentChanged: { hasUnsavedChanges = true }
                    )
                    .frame(width: min(120, geometry.size.width * 0.25))
                    .transition(.move(edge: .leading))
                }

                Divider()
                    .opacity(showThumbnailSidebar ? 1 : 0)

                // Main PDF view
                ZStack {
                    if isLoading {
                        LoadingStateView(message: "Loading PDF...")
                    } else if let doc = pdfDocument {
                        InteractivePDFView(
                            pdfDocument: doc,
                            currentPageIndex: $currentPageIndex,
                            selectedAnnotation: $selectedAnnotation,
                            selectedPage: $selectedPage,
                            pdfViewRef: $pdfView,
                            isPlacingSignature: isPlacingSignature,
                            onSignaturePlacement: handleSignaturePlacement,
                            onAnnotationChanged: { hasUnsavedChanges = true },
                            onDelete: deleteSelectedAnnotation
                        )
                    } else {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Unable to Load PDF",
                            description: "The document could not be loaded"
                        )
                    }

                    // Mode indicators
                    VStack {
                        if isPlacingSignature {
                            placementModeIndicator
                        }
                        Spacer()
                        if canUndo && !hasSelection {
                            undoIndicator
                        }
                        if hasSelection {
                            editModeIndicator
                        }
                    }
                }
            }
        }
        .background(AppTheme.Colors.background)
        .navigationTitle(document.name ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    if hasUnsavedChanges {
                        Button("Cancel") {
                            HapticManager.shared.buttonTap()
                            showDiscardAlert = true
                        }
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showThumbnailSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: showThumbnailSidebar ? "sidebar.left" : "sidebar.left")
                            .symbolVariant(showThumbnailSidebar ? .fill : .none)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button {
                        enterSignaturePlacementMode()
                    } label: {
                        Image(systemName: "signature")
                    }

                    if hasUnsavedChanges {
                        Button("Save") {
                            HapticManager.shared.buttonTap()
                            saveDocument()
                            HapticManager.shared.success()
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button {
                            exportDocument()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSignaturePicker) {
            SignaturePickerSheet { signature in
                placeSignature(signature)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .sheet(isPresented: $showAddPagesPicker) {
            DocumentPicker { url in
                mergePages(from: url)
            }
        }
        .upgradePromptOverlay(
            isPresented: $showAddPagesUpgradePrompt,
            feature: "Add Pages",
            featureIcon: "doc.badge.plus",
            features: [
                "Combine multiple PDFs",
                "Unlimited signatures",
                "No watermarks on exports"
            ]
        )
        .onAppear {
            loadDocument()
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    // MARK: - Indicators

    private var placementModeIndicator: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "hand.tap")
            Text("Tap where you want to place the signature")
            Spacer()
            Button("Cancel") {
                isPlacingSignature = false
            }
            .fontWeight(.semibold)
        }
        .font(AppTheme.Typography.subheadline)
        .foregroundColor(.white)
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.primary)
        .cornerRadius(AppTheme.CornerRadius.sm)
        .padding(AppTheme.Spacing.md)
        .shadow(radius: 4)
    }

    private var undoIndicator: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
            Text("Signature added")
            Spacer()
            Button {
                undoLastSignature()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Undo")
                }
                .fontWeight(.semibold)
            }
        }
        .font(AppTheme.Typography.subheadline)
        .foregroundColor(.white)
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.success)
        .cornerRadius(AppTheme.CornerRadius.sm)
        .padding(AppTheme.Spacing.md)
        .shadow(radius: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { canUndo = false }
            }
        }
    }

    private var editModeIndicator: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "hand.draw")
            Text("Drag to move, corners to resize")
            Spacer()
            Button("Done") {
                withAnimation {
                    selectedAnnotation = nil
                    selectedPage = nil
                }
            }
            .fontWeight(.semibold)
        }
        .font(AppTheme.Typography.subheadline)
        .foregroundColor(.white)
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.primary)
        .cornerRadius(AppTheme.CornerRadius.sm)
        .padding(AppTheme.Spacing.md)
        .shadow(radius: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Document Operations

    private func loadDocument() {
        Task {
            do {
                pdfDocument = try await documentManager.loadPDFDocument(for: document)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func saveDocument() {
        guard let pdfDocument = pdfDocument,
              let data = pdfDocument.dataRepresentation() else {
            errorMessage = "Failed to generate PDF data"
            showError = true
            return
        }

        Task {
            do {
                try await documentManager.savePDFData(data, for: document)
                document.lastModified = Date()
                document.pageCount = Int32(pdfDocument.pageCount)
                documentManager.saveContext()
                hasUnsavedChanges = false
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func exportDocument() {
        if hasUnsavedChanges { saveDocument() }

        Task {
            do {
                let url = try await documentManager.exportDocument(document)
                exportURL = url
                showExportSheet = true
                HapticManager.shared.success()
            } catch {
                HapticManager.shared.error()
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Page Operations

    private func handleReorder(from source: Int, to destination: Int) {
        guard let pdfDocument = pdfDocument else { return }
        // Just perform the reorder - the sidebar handles index adjustments
        documentManager.reorderPages(in: pdfDocument, from: source, to: destination)
    }

    private func handleDeletePage(at index: Int) {
        guard let pdfDocument = pdfDocument, pdfDocument.pageCount > 1 else { return }
        // Just perform the delete - the sidebar handles index adjustments
        documentManager.deletePage(in: pdfDocument, at: index)
        HapticManager.shared.importantAction()
    }

    private func handleAddPages() {
        if subscriptionManager.isSubscribed {
            showAddPagesPicker = true
        } else {
            showAddPagesUpgradePrompt = true
        }
    }

    private func mergePages(from url: URL) {
        guard let currentDoc = pdfDocument else { return }

        // Access security-scoped resource
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Check file size
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
            if fileSize > DocumentError.maxFileSizeBytes {
                errorMessage = DocumentError.fileTooLarge(maxSizeMB: 50).localizedDescription
                showError = true
                return
            }
        } catch {
            errorMessage = "Could not read the file"
            showError = true
            return
        }

        // Try to open the PDF
        guard let newDoc = PDFDocument(url: url) else {
            errorMessage = DocumentError.corruptedPDF.localizedDescription
            showError = true
            return
        }

        // Check for empty PDF
        if newDoc.pageCount == 0 {
            errorMessage = DocumentError.emptyPDF.localizedDescription
            showError = true
            return
        }

        // Append all pages from the new document
        for i in 0..<newDoc.pageCount {
            if let page = newDoc.page(at: i) {
                currentDoc.insert(page, at: currentDoc.pageCount)
            }
        }

        hasUnsavedChanges = true

        // Force sidebar to refresh by toggling pdfDocument binding
        let doc = pdfDocument
        pdfDocument = nil
        pdfDocument = doc

        refreshPDFView()
        HapticManager.shared.success()
    }

    // MARK: - Signature Operations

    private func enterSignaturePlacementMode() {
        HapticManager.shared.buttonTap()
        selectedAnnotation = nil
        selectedPage = nil
        isPlacingSignature = true
    }

    private func handleSignaturePlacement(point: CGPoint, page: PDFPage) {
        HapticManager.shared.selection()
        pendingSignaturePoint = point
        pendingSignaturePage = page
        isPlacingSignature = false
        showSignaturePicker = true
    }

    private func placeSignature(_ signature: Signature) {
        guard let page = pendingSignaturePage,
              let point = pendingSignaturePoint else { return }

        if let annotation = signatureManager.applySignature(signature, to: page, at: point) {
            lastPlacedAnnotation = annotation
            lastPlacedPage = page
            withAnimation { canUndo = true }
        }

        hasUnsavedChanges = true
        HapticManager.shared.success()

        pendingSignaturePage = nil
        pendingSignaturePoint = nil
    }

    private func undoLastSignature() {
        guard let annotation = lastPlacedAnnotation,
              let page = lastPlacedPage else { return }

        signatureManager.removeAnnotation(annotation, from: page)
        refreshPDFView()
        HapticManager.shared.buttonTap()

        lastPlacedAnnotation = nil
        lastPlacedPage = nil
        withAnimation { canUndo = false }
    }

    private func deleteSelectedAnnotation() {
        guard let annotation = selectedAnnotation,
              let page = selectedPage else { return }

        signatureManager.removeAnnotation(annotation, from: page)
        refreshPDFView()
        hasUnsavedChanges = true

        withAnimation {
            selectedAnnotation = nil
            selectedPage = nil
        }
    }

    private func refreshPDFView() {
        guard let pdfView = pdfView,
              let document = pdfView.document else { return }

        // Store current state
        let currentPageIndex = currentPageIndex
        let currentScale = pdfView.scaleFactor

        // Force PDFKit to completely re-render by toggling the document
        // This clears all internal caches
        pdfView.document = nil
        pdfView.document = document

        // Restore scale
        pdfView.scaleFactor = currentScale

        // Navigate back to the page we were on
        if let page = document.page(at: currentPageIndex) {
            pdfView.go(to: page)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let subscriptionManager = SubscriptionManager()
    NavigationStack {
        PDFViewerView(document: StoredPDFDocument())
            .environmentObject(subscriptionManager)
            .environmentObject(DocumentManager(subscriptionManager: subscriptionManager))
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
    }
}
