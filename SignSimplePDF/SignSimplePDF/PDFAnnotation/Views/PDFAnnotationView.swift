//
//  PDFAnnotationView.swift
//  SignSimplePDF
//
//  Main PDF annotation view - brings everything together
//

import UIKit
import PDFKit
import PencilKit
import Combine

// MARK: - PDFAnnotationView Delegate
public protocol PDFAnnotationViewDelegate: AnyObject {
    func annotationView(_ view: PDFAnnotationView, didAddAnnotation annotation: UnifiedAnnotation)
    func annotationView(_ view: PDFAnnotationView, didUpdateAnnotation annotation: UnifiedAnnotation)
    func annotationView(_ view: PDFAnnotationView, didRemoveAnnotation annotation: UnifiedAnnotation)
    func annotationView(_ view: PDFAnnotationView, didSelectAnnotation annotation: UnifiedAnnotation?)
    func annotationViewDidSave(_ view: PDFAnnotationView)
    func annotationViewDidCancel(_ view: PDFAnnotationView)
}

// MARK: - PDFAnnotationView
public class PDFAnnotationView: UIView {
    // MARK: - Properties
    public weak var delegate: PDFAnnotationViewDelegate?

    // Core components
    public private(set) var pdfView: PDFView!
    public private(set) var annotationEngine: PDFAnnotationEngine!
    private var annotationRenderer: AnnotationRenderer!
    private var interactionHandler: AnnotationInteractionHandler!

    // UI components
    private var toolbar: AnnotationToolbar?
    private var propertyInspector: PropertyInspector?
    private var canvasView: PKCanvasView?  // For PencilKit drawing
    private var overlayView: UIView!  // For annotations overlay

    // State
    @Published public private(set) var isDrawing = false
    @Published public private(set) var hasUnsavedChanges = false
    
    private var isOverlayMode = false
    private var cancellables = Set<AnyCancellable>()
    private var currentDrawingPath: [CGPoint] = []
    private var currentPageIndex = 0

    // Configuration
    public var allowsEditing = true {
        didSet {
            toolbar?.isHidden = !allowsEditing
            interactionHandler.isEnabled = allowsEditing
        }
    }

    public var showsToolbar = true {
        didSet {
            toolbar?.isHidden = !showsToolbar
        }
    }

    public var showsPropertyInspector = true {
        didSet {
            if !showsPropertyInspector {
                propertyInspector?.hide()
            }
        }
    }

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Default setup - creates internal PDFView
        setupView()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupBindings()
    }
    
    /// Configure as an overlay for an existing PDFView
    /// - Parameters:
    ///   - externalPDFView: The PDFView to overlay
    ///   - engine: The shared annotation engine (from Bridge). If nil, creates internal engine.
    public func configureAsOverlay(for externalPDFView: PDFView, engine: PDFAnnotationEngine? = nil) {
        self.isOverlayMode = true
        self.pdfView = externalPDFView
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true

        // Remove internal PDFView if it was created
        self.subviews.forEach { $0.removeFromSuperview() }

        // Use shared engine from Bridge, or create internal one for standalone use
        if let sharedEngine = engine {
            self.annotationEngine = sharedEngine
            // Set delegate so we receive annotation change callbacks for redrawing
            // Note: This overrides the Bridge's delegate, but Bridge uses Combine observation
            self.annotationEngine.delegate = self
        } else {
            setupAnnotationEngine()
        }

        // Re-setup components with the external view
        setupOverlayView()
        setupRenderer()
        setupInteractionHandler()
        setupCanvasView()
        setupNotifications()
        setupEngineObservation()

        // Note: We do NOT setup toolbar/inspector here as the Bridge/SwiftUI manages them
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = .systemBackground

        if !isOverlayMode {
            // Setup internal PDF view only if not in overlay mode
            setupPDFView()
            setupOverlayView()
            setupAnnotationEngine()
            setupRenderer()
            setupInteractionHandler()
            setupToolbar()
            setupPropertyInspector()
            setupCanvasView()
            setupNotifications()
        }
    }

    private func setupPDFView() {
        guard pdfView == nil else { return }
        
        pdfView = PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .systemGray6

        addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupOverlayView() {
        overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = true  // Enable interaction - hitTest controls what gets intercepted

        addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupAnnotationEngine() {
        annotationEngine = PDFAnnotationEngine()
        annotationEngine.configure(with: pdfView)
        annotationEngine.delegate = self
    }

    private func setupRenderer() {
        annotationRenderer = AnnotationRenderer()
        annotationRenderer.configure(with: pdfView)
    }

    private func setupInteractionHandler() {
        interactionHandler = AnnotationInteractionHandler()
        // In overlay mode, attach gestures to self (the overlay) so it receives touches
        // In standalone mode, attach to pdfView for backwards compatibility
        let gestureTarget: UIView? = isOverlayMode ? self : nil
        interactionHandler.configure(with: pdfView, engine: annotationEngine, gestureTarget: gestureTarget)
        interactionHandler.delegate = self
    }

    private func setupToolbar() {
        guard !isOverlayMode else { return }
        
        toolbar = AnnotationToolbar()
        toolbar?.translatesAutoresizingMaskIntoConstraints = false
        if let toolbar = toolbar {
            toolbar.delegate = self
            toolbar.annotationEngine = annotationEngine

            addSubview(toolbar)

            // Position toolbar at top center
            NSLayoutConstraint.activate([
                toolbar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
                toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
                toolbar.heightAnchor.constraint(equalToConstant: 52)
            ])
        }
    }

    private func setupPropertyInspector() {
        guard !isOverlayMode else { return }

        propertyInspector = PropertyInspector()
        propertyInspector?.translatesAutoresizingMaskIntoConstraints = false
        if let propertyInspector = propertyInspector {
            propertyInspector.delegate = self
            propertyInspector.annotationEngine = annotationEngine

            addSubview(propertyInspector)

            // Position inspector on right side
            NSLayoutConstraint.activate([
                propertyInspector.topAnchor.constraint(equalTo: toolbar?.bottomAnchor ?? topAnchor, constant: 16),
                propertyInspector.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
                propertyInspector.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -16)
            ])
        }
    }

    private func setupCanvasView() {
        canvasView = PKCanvasView()
        canvasView?.translatesAutoresizingMaskIntoConstraints = false
        canvasView?.backgroundColor = .clear
        canvasView?.isOpaque = false
        canvasView?.delegate = self
        canvasView?.isHidden = true
        canvasView?.tool = PKInkingTool(.pen, color: .black, width: 2)

        if let canvasView = canvasView {
            // For overlay mode, add to self (which is over pdfView).
            addSubview(canvasView)

            NSLayoutConstraint.activate([
                canvasView.topAnchor.constraint(equalTo: topAnchor),
                canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
                canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
                canvasView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfPageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfScaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfVisiblePagesChanged(_:)),
            name: .PDFViewVisiblePagesChanged,
            object: pdfView
        )
    }

    // MARK: - Bindings
    private func setupBindings() {
        // Bind to annotation engine
        // Note: engine might be nil until configured
    }

    /// Setup Combine observation of the annotation engine's published properties
    private func setupEngineObservation() {
        guard let engine = annotationEngine else {
            print("⚠️ PDFAnnotationView.setupEngineObservation: No engine available")
            return
        }

        print("✅ PDFAnnotationView.setupEngineObservation: Setting up Combine observation")

        // Cancel existing subscriptions
        cancellables.removeAll()

        // Observe annotations array changes - this triggers redraw
        engine.$annotations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotations in
                print("🔄 PDFAnnotationView: Annotations changed, count: \(annotations.count)")
                self?.redrawAnnotations()
            }
            .store(in: &cancellables)

        // Observe selection changes
        engine.$selectedAnnotation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotation in
                self?.handleSelectionChanged(annotation)
                self?.redrawAnnotations()
            }
            .store(in: &cancellables)

        // Observe tool changes
        engine.$currentTool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tool in
                self?.updateTouchInteractionForTool(tool)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Hit Testing for Overlay Mode
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isOverlayMode else {
            return super.hitTest(point, with: event)
        }

        // If no engine configured yet, let PDF handle everything
        guard let engine = annotationEngine else {
            return nil
        }

        let tool = engine.currentTool

        // For selection tool (default): ONLY intercept if touching an actual annotation
        // This allows PDF scroll/zoom to work normally
        if tool == .selection {
            // Convert point from overlay coordinates to PDFView coordinates
            let pdfViewPoint = convert(point, to: pdfView)

            // Use nearest:false to only get page if point is actually on it
            guard let page = pdfView.page(for: pdfViewPoint, nearest: false),
                  let pageIndex = pdfView.document?.index(for: page) else {
                // Point is not on any page - let PDF handle (scroll/zoom in margins)
                return nil
            }

            let pagePoint = pdfView.convert(pdfViewPoint, to: page)

            // Intercept ONLY if touching an annotation
            if engine.annotation(at: pagePoint, on: pageIndex) != nil {
                return self
            }

            // If we have a selected annotation, check if touch is within its frame
            // (for moving/resizing) - otherwise let PDF handle scroll
            if let selected = engine.selectedAnnotation {
                // Only intercept if touch is near the selected annotation
                let annotationFrame = selected.frame.insetBy(dx: -20, dy: -20)  // 20pt touch margin
                if annotationFrame.contains(pagePoint) && selected.pageIndex == pageIndex {
                    return self
                }
            }

            // No annotation interaction needed - let PDF handle scroll/zoom
            return nil
        }

        // For drawing/creation tools, always intercept
        if tool == .pen || tool == .highlighter || tool == .text ||
           tool == .rectangle || tool == .oval || tool == .arrow ||
           tool == .line || tool == .signature || tool == .note {
            return self
        }

        // Default: let PDF handle
        return nil
    }

    // MARK: - Public Methods
    public func loadPDF(_ document: PDFDocument) {
        if !isOverlayMode {
            pdfView.document = document
        }
        annotationEngine.loadAnnotations(for: document)
        redrawAnnotations()
    }

    public func savePDF() -> PDFDocument? {
        return annotationEngine.exportToPDF()
    }

    public func clearAllAnnotations() {
        annotationEngine.clearAll()
    }

    public func undo() {
        annotationEngine.undo()
    }

    public func redo() {
        annotationEngine.redo()
    }

    // MARK: - Drawing
    private func redrawAnnotations() {
        // Clear overlay
        overlayView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let page = pdfView.currentPage,
              let pageIndex = pdfView.document?.index(for: page) else {
            print("⚠️ PDFAnnotationView.redrawAnnotations: No current page")
            return
        }

        // Guard against zero-size bounds (view not laid out yet)
        guard overlayView.bounds.size.width > 0, overlayView.bounds.size.height > 0 else {
            print("⚠️ PDFAnnotationView.redrawAnnotations: Zero-size overlay bounds")
            return
        }

        // Get annotations for current page
        let annotations = annotationEngine.getAnnotations(for: pageIndex)
        print("📝 PDFAnnotationView.redrawAnnotations: Drawing \(annotations.count) annotations for page \(pageIndex)")

        guard let renderer = annotationRenderer else {
            print("⚠️ PDFAnnotationView.redrawAnnotations: No annotation renderer!")
            return
        }

        // Create layer for annotations
        let annotationLayer = CALayer()
        annotationLayer.frame = overlayView.bounds
        print("   overlayView.bounds: \(overlayView.bounds)")

        // Use UIGraphicsImageRenderer instead of deprecated UIGraphicsBeginImageContextWithOptions
        let imageRenderer = UIGraphicsImageRenderer(size: overlayView.bounds.size)
        let image = imageRenderer.image { rendererContext in
            let context = rendererContext.cgContext

            // Get the page bounds in PDF coordinates and view coordinates
            let pdfPageBounds = page.bounds(for: .mediaBox)
            let viewPageRect = pdfView.convert(pdfPageBounds, from: page)
            print("   pdfPageBounds: \(pdfPageBounds)")
            print("   viewPageRect: \(viewPageRect)")

            // Calculate scale factors
            let scaleX = viewPageRect.width / pdfPageBounds.width
            let scaleY = viewPageRect.height / pdfPageBounds.height
            print("   scale: (\(scaleX), \(scaleY))")

            // Build transform: PDF coordinates -> View coordinates
            // PDF has origin at bottom-left, UIKit at top-left
            // 1. Flip Y axis (PDF y=0 is at bottom, we need it at top of page rect)
            // 2. Scale to view size
            // 3. Translate to page position in view
            var transform = CGAffineTransform.identity

            // Move to where the page is rendered in the view
            transform = transform.translatedBy(x: viewPageRect.origin.x, y: viewPageRect.origin.y)

            // Scale from PDF points to view points
            transform = transform.scaledBy(x: scaleX, y: scaleY)

            // Flip Y axis: PDF origin is bottom-left, translate up by page height then flip
            transform = transform.translatedBy(x: 0, y: pdfPageBounds.height)
            transform = transform.scaledBy(x: 1, y: -1)

            print("   final transform: \(transform)")

            // Render using the renderer
            renderer.renderAnnotations(annotations, in: context, for: page, with: transform)
        }

        annotationLayer.contents = image.cgImage
        overlayView.layer.addSublayer(annotationLayer)
    }

    private func handleSelectionChanged(_ annotation: UnifiedAnnotation?) {
        // Update UI based on selection
        if annotation != nil {
            propertyInspector?.show()
        } else {
            propertyInspector?.hide()
        }

        delegate?.annotationView(self, didSelectAnnotation: annotation)
    }

    // MARK: - Touch Handling
    // NOTE: All touch handling is now done via gesture recognizers in AnnotationInteractionHandler.
    // Touch overrides have been removed to avoid conflicts with gestures.
    // Drawing (pen/highlighter) is handled by the pan gesture recognizer.

    // MARK: - Notifications
    @objc private func pdfPageChanged(_ notification: Notification) {
        currentPageIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
        redrawAnnotations()
    }

    @objc private func pdfScaleChanged(_ notification: Notification) {
        redrawAnnotations()
    }
    
    @objc private func pdfVisiblePagesChanged(_ notification: Notification) {
        redrawAnnotations()
    }
}

// MARK: - PDFAnnotationEngineDelegate
extension PDFAnnotationView: PDFAnnotationEngineDelegate {
    public func annotationEngine(_ engine: PDFAnnotationEngine, didAdd annotation: UnifiedAnnotation) {
        redrawAnnotations()
        delegate?.annotationView(self, didAddAnnotation: annotation)
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didUpdate annotation: UnifiedAnnotation) {
        redrawAnnotations()
        delegate?.annotationView(self, didUpdateAnnotation: annotation)
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didRemove annotation: UnifiedAnnotation) {
        redrawAnnotations()
        delegate?.annotationView(self, didRemoveAnnotation: annotation)
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didSelect annotation: UnifiedAnnotation?) {
        delegate?.annotationView(self, didSelectAnnotation: annotation)
        handleSelectionChanged(annotation)
    }

    public func annotationEngineDidChangeUndoState(_ engine: PDFAnnotationEngine) {
        // Update UI if needed
    }
}

// MARK: - Public Tool Selection
extension PDFAnnotationView {
    /// Update the current tool and enable/disable touch interaction accordingly
    /// Call this method for programmatic tool selection (not from toolbar)
    public func setCurrentTool(_ tool: AnnotationTool) {
        annotationEngine.selectTool(tool)
        updateTouchInteractionForTool(tool)
    }

    /// Internal method to update touch interaction state based on tool
    private func updateTouchInteractionForTool(_ tool: AnnotationTool) {
        // Interaction is always enabled - hitTest() controls what gets intercepted
        // Gesture recognizers handle all interactions (drawing, selection, moving, etc.)
        isUserInteractionEnabled = true

        // Hide PencilKit canvas - we use gesture-based drawing instead
        canvasView?.isHidden = true
    }
}

// MARK: - AnnotationToolbarDelegate
extension PDFAnnotationView: AnnotationToolbarDelegate {
    public func toolbar(_ toolbar: AnnotationToolbar, didSelectTool tool: AnnotationTool) {
        annotationEngine.selectTool(tool)
        updateTouchInteractionForTool(tool)
    }

    public func toolbarDidTapUndo(_ toolbar: AnnotationToolbar) {
        undo()
    }

    public func toolbarDidTapRedo(_ toolbar: AnnotationToolbar) {
        redo()
    }

    public func toolbarDidTapDone(_ toolbar: AnnotationToolbar) {
        annotationEngine.saveAnnotations()
        delegate?.annotationViewDidSave(self)
    }

    public func toolbar(_ toolbar: AnnotationToolbar, didChangeVisibility isVisible: Bool) {
        // Handle toolbar visibility changes if needed
    }
}

// MARK: - PropertyInspectorDelegate
extension PDFAnnotationView: PropertyInspectorDelegate {
    public func inspector(_ inspector: PropertyInspector, didChangeStrokeColor color: UIColor) {
        annotationEngine.currentStrokeColor = color
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeFillColor color: UIColor?) {
        annotationEngine.currentFillColor = color
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeStrokeWidth width: CGFloat) {
        annotationEngine.currentStrokeWidth = width
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeFontSize size: CGFloat) {
        annotationEngine.currentFontSize = size
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeFontName name: String) {
        annotationEngine.currentFontName = name
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeOpacity opacity: CGFloat) {
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeCornerRadius radius: CGFloat) {
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeDashPattern pattern: [CGFloat]?) {
        redrawAnnotations()
    }

    public func inspector(_ inspector: PropertyInspector, didChangeArrowStyle style: AnnotationProperties.ArrowHeadStyle) {
        redrawAnnotations()
    }

    public func inspectorDidClose(_ inspector: PropertyInspector) {
        annotationEngine.selectAnnotation(nil)
    }
}

// MARK: - AnnotationInteractionHandlerDelegate
extension PDFAnnotationView: AnnotationInteractionHandlerDelegate {
    public func interactionHandler(_ handler: AnnotationInteractionHandler, didSelectAnnotation annotation: UnifiedAnnotation?) {
        // Selection handled by engine
    }

    // Signature picker state
    private static var pendingSignatureLocation: CGPoint?
    private static var pendingSignaturePageIndex: Int?

    public func interactionHandler(_ handler: AnnotationInteractionHandler, requestsSignaturePickerAt point: CGPoint, on pageIndex: Int) {
        // Store the location for when signature is selected
        PDFAnnotationView.pendingSignatureLocation = point
        PDFAnnotationView.pendingSignaturePageIndex = pageIndex

        // Create and present the signature picker
        let signaturePicker = SignaturePicker()
        signaturePicker.delegate = self

        // Present modally
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(signaturePicker, animated: true)
        }
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, didMoveAnnotation annotation: UnifiedAnnotation, to point: CGPoint) {
        redrawAnnotations()
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, didResizeAnnotation annotation: UnifiedAnnotation, to frame: CGRect) {
        redrawAnnotations()
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, didRotateAnnotation annotation: UnifiedAnnotation, by degrees: CGFloat) {
        redrawAnnotations()
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, shouldBeginEditing annotation: UnifiedAnnotation) -> Bool {
        return allowsEditing
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, didBeginEditing annotation: UnifiedAnnotation) {
        // Show text editing UI
        if annotation.tool == .text {
            showTextEditor(for: annotation)
        }
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, didEndEditing annotation: UnifiedAnnotation) {
        redrawAnnotations()
    }

    public func interactionHandler(_ handler: AnnotationInteractionHandler, requestsContextMenu for: UnifiedAnnotation, at point: CGPoint) {
        showContextMenu(for: `for`, at: point)
    }

    // MARK: - Text Editor
    private func showTextEditor(for annotation: UnifiedAnnotation) {
        let alert = UIAlertController(title: "Edit Text", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = annotation.properties.text
            textField.autocapitalizationType = .sentences
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            if let text = alert.textFields?.first?.text {
                annotation.properties.text = text
                annotation.isEditing = false
                self?.annotationEngine.updateAnnotation(annotation)
                self?.redrawAnnotations()
            }
        })

        if let viewController = window?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }

    // MARK: - Context Menu
    private func showContextMenu(for annotation: UnifiedAnnotation, at point: CGPoint) {
        let menu = UIMenuController.shared
        let deleteItem = UIMenuItem(title: "Delete", action: #selector(deleteSelectedAnnotation))
        let copyItem = UIMenuItem(title: "Copy", action: #selector(copySelectedAnnotation))
        let bringToFrontItem = UIMenuItem(title: "Bring to Front", action: #selector(bringToFront))
        let sendToBackItem = UIMenuItem(title: "Send to Back", action: #selector(sendToBack))

        menu.menuItems = [deleteItem, copyItem, bringToFrontItem, sendToBackItem]
        menu.showMenu(from: self, rect: CGRect(origin: point, size: .zero))
    }

    @objc private func deleteSelectedAnnotation() {
        annotationEngine.removeSelectedAnnotation()
    }

    @objc private func copySelectedAnnotation() {
        annotationEngine.copySelectedAnnotation()
    }

    @objc private func bringToFront() {
        if let selected = annotationEngine.selectedAnnotation {
            annotationEngine.bringToFront(selected)
            redrawAnnotations()
        }
    }

    @objc private func sendToBack() {
        if let selected = annotationEngine.selectedAnnotation {
            annotationEngine.sendToBack(selected)
            redrawAnnotations()
        }
    }
}

// MARK: - PKCanvasViewDelegate
extension PDFAnnotationView: PKCanvasViewDelegate {
    public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Handle PencilKit drawing changes if needed
    }
}

// MARK: - SignaturePickerDelegate
extension PDFAnnotationView: SignaturePickerDelegate {
    public func signaturePicker(_ picker: SignaturePicker, didSelectSignature signature: Signature) {
        // Get the stored location and page index
        guard let point = PDFAnnotationView.pendingSignatureLocation,
              let pageIndex = PDFAnnotationView.pendingSignaturePageIndex,
              let imageData = signature.imageData else {
            return
        }

        // Add signature annotation at the tapped location
        annotationEngine.addSignatureAnnotation(at: point, on: pageIndex, imageData: imageData)

        // Clear pending state
        PDFAnnotationView.pendingSignatureLocation = nil
        PDFAnnotationView.pendingSignaturePageIndex = nil

        redrawAnnotations()
    }

    public func signaturePickerDidCancel(_ picker: SignaturePicker) {
        // Clear pending state
        PDFAnnotationView.pendingSignatureLocation = nil
        PDFAnnotationView.pendingSignaturePageIndex = nil
    }

    public func signaturePicker(_ picker: SignaturePicker, didCreateSignature imageData: Data) {
        // Get the stored location and page index
        guard let point = PDFAnnotationView.pendingSignatureLocation,
              let pageIndex = PDFAnnotationView.pendingSignaturePageIndex else {
            return
        }

        // Add signature annotation at the tapped location
        annotationEngine.addSignatureAnnotation(at: point, on: pageIndex, imageData: imageData)

        // Clear pending state
        PDFAnnotationView.pendingSignatureLocation = nil
        PDFAnnotationView.pendingSignaturePageIndex = nil

        redrawAnnotations()
    }
}