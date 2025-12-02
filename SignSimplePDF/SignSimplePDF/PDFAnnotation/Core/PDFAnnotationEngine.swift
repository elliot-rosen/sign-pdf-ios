//
//  PDFAnnotationEngine.swift
//  SignSimplePDF
//
//  Core engine for managing PDF annotations - Apple Preview style
//

import Foundation
import PDFKit
import Combine
import UIKit
import CoreData

// MARK: - Annotation Engine Delegate
public protocol PDFAnnotationEngineDelegate: AnyObject {
    func annotationEngine(_ engine: PDFAnnotationEngine, didAdd annotation: UnifiedAnnotation)
    func annotationEngine(_ engine: PDFAnnotationEngine, didUpdate annotation: UnifiedAnnotation)
    func annotationEngine(_ engine: PDFAnnotationEngine, didRemove annotation: UnifiedAnnotation)
    func annotationEngine(_ engine: PDFAnnotationEngine, didSelect annotation: UnifiedAnnotation?)
    func annotationEngineDidChangeUndoState(_ engine: PDFAnnotationEngine)
}

// MARK: - PDF Annotation Engine
public class PDFAnnotationEngine: NSObject, ObservableObject {
    // MARK: - Properties
    @Published public private(set) var annotations: [UnifiedAnnotation] = []
    @Published public private(set) var selectedAnnotation: UnifiedAnnotation?
    @Published public private(set) var currentTool: AnnotationTool = .selection
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    public weak var delegate: PDFAnnotationEngineDelegate?
    public private(set) weak var pdfView: PDFView?

    // Tool properties
    @Published public var currentStrokeColor = UIColor.label
    @Published public var currentFillColor: UIColor? = nil
    @Published public var currentStrokeWidth: CGFloat = 2.0
    @Published public var currentFontSize: CGFloat = 14.0
    @Published public var currentFontName = "Helvetica"

    // Undo/Redo stacks
    private var undoStack: [AnnotationAction] = []
    private var redoStack: [AnnotationAction] = []
    private let maxUndoStackSize = 50

    // Performance optimization
    private var annotationCache: [Int: [UnifiedAnnotation]] = [:]  // Page-based cache
    private let cacheQueue = DispatchQueue(label: "com.signsimplepdf.annotation.cache", attributes: .concurrent)

    // Autosave
    private var autosaveTimer: Timer?
    private let autosaveInterval: TimeInterval = 5.0

    // State tracking
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var dragStartFrame: CGRect = .zero

    // Current drawing state for pen/highlighter
    private var currentDrawingPath: [BezierPath] = []
    private var isDrawing = false

    // MARK: - Initialization
    public override init() {
        super.init()
        setupAutosave()
    }

    deinit {
        autosaveTimer?.invalidate()
    }

    public func configure(with pdfView: PDFView) {
        self.pdfView = pdfView
        rebuildCache()
    }

    // MARK: - Tool Selection
    public func selectTool(_ tool: AnnotationTool) {
        // Deselect any selected annotation when switching tools
        if tool != .selection {
            selectAnnotation(nil)
        }
        currentTool = tool
    }

    // MARK: - Annotation Management
    public func addAnnotation(_ annotation: UnifiedAnnotation) {
        print("➕ PDFAnnotationEngine.addAnnotation: Adding \(annotation.tool) annotation on page \(annotation.pageIndex), frame: \(annotation.frame)")
        annotations.append(annotation)
        annotation.zIndex = annotations.count
        print("   Total annotations: \(annotations.count)")

        // Update cache
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.annotationCache[annotation.pageIndex]?.append(annotation)
        }

        // Add to undo stack
        addUndoAction(.add(annotation))

        // Notify delegate
        delegate?.annotationEngine(self, didAdd: annotation)
    }

    public func updateAnnotation(_ annotation: UnifiedAnnotation) {
        annotation.modifiedAt = Date()

        // Clear cache for this page
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.annotationCache[annotation.pageIndex] = nil
        }

        delegate?.annotationEngine(self, didUpdate: annotation)
    }

    public func removeAnnotation(_ annotation: UnifiedAnnotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }

        annotations.remove(at: index)

        // Update cache
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.annotationCache[annotation.pageIndex]?.removeAll { $0.id == annotation.id }
        }

        // Add to undo stack
        addUndoAction(.remove(annotation))

        // Clear selection if needed
        if selectedAnnotation?.id == annotation.id {
            selectAnnotation(nil)
        }

        delegate?.annotationEngine(self, didRemove: annotation)
    }

    public func removeSelectedAnnotation() {
        guard let selected = selectedAnnotation else { return }
        removeAnnotation(selected)
    }

    // MARK: - Selection
    public func selectAnnotation(_ annotation: UnifiedAnnotation?) {
        // Deselect previous
        selectedAnnotation?.isSelected = false

        // Select new
        selectedAnnotation = annotation
        annotation?.isSelected = true

        delegate?.annotationEngine(self, didSelect: annotation)
    }

    public func annotation(at point: CGPoint, on page: Int) -> UnifiedAnnotation? {
        let pageAnnotations = getAnnotations(for: page)
        return pageAnnotations
            .sortedByZIndex()
            .reversed()
            .first { $0.contains(point: point) }
    }

    // MARK: - Page-based Queries
    public func getAnnotations(for pageIndex: Int) -> [UnifiedAnnotation] {
        // Try cache first
        var cached: [UnifiedAnnotation]?
        cacheQueue.sync {
            cached = annotationCache[pageIndex]
        }

        if let cached = cached {
            return cached
        }

        // Build cache for this page
        let pageAnnotations = annotations.filter { $0.pageIndex == pageIndex }
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.annotationCache[pageIndex] = pageAnnotations
        }

        return pageAnnotations
    }

    // MARK: - Drawing Support (for pen/highlighter)
    public func startDrawing(at point: CGPoint, on page: Int) {
        guard currentTool == .pen || currentTool == .highlighter else { return }

        isDrawing = true
        currentDrawingPath = [BezierPath(points: [point], type: .moveTo)]

        // Create annotation with initial point
        let annotation = UnifiedAnnotation(
            tool: currentTool,
            frame: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
            pageIndex: page
        )

        annotation.properties.strokeColor = currentStrokeColor
        annotation.properties.strokeWidth = currentStrokeWidth
        annotation.properties.paths = currentDrawingPath

        if currentTool == .highlighter {
            annotation.properties.opacity = 0.5
        }

        addAnnotation(annotation)
        selectAnnotation(annotation)
    }

    public func continueDrawing(to point: CGPoint) {
        guard isDrawing,
              let annotation = selectedAnnotation,
              (annotation.tool == .pen || annotation.tool == .highlighter) else { return }

        // Add point to path
        currentDrawingPath.append(BezierPath(points: [point], type: .lineTo))

        // Update annotation bounds
        let allPoints = currentDrawingPath.flatMap { $0.points }
        let minX = allPoints.map { $0.x }.min() ?? 0
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 0

        annotation.frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        annotation.properties.paths = currentDrawingPath

        updateAnnotation(annotation)
    }

    public func endDrawing() {
        guard isDrawing else { return }

        isDrawing = false
        currentDrawingPath = []

        // Finalize the annotation
        if let annotation = selectedAnnotation {
            // Simplify paths if needed
            annotation.properties.paths = simplifyPaths(annotation.properties.paths)
            updateAnnotation(annotation)
        }
    }

    // MARK: - Shape Recognition
    private func simplifyPaths(_ paths: [BezierPath]) -> [BezierPath] {
        // TODO: Implement Douglas-Peucker algorithm for path simplification
        return paths
    }

    // MARK: - Text Support
    public func addTextAnnotation(at point: CGPoint, on page: Int, text: String) {
        let size = calculateTextSize(text: text, fontSize: currentFontSize, fontName: currentFontName)

        let annotation = UnifiedAnnotation(
            tool: .text,
            frame: CGRect(origin: point, size: size),
            pageIndex: page
        )

        annotation.properties.text = text
        annotation.properties.fontSize = currentFontSize
        annotation.properties.fontName = currentFontName
        annotation.properties.strokeColor = currentStrokeColor

        addAnnotation(annotation)
        selectAnnotation(annotation)
    }

    private func calculateTextSize(text: String, fontSize: CGFloat, fontName: String) -> CGSize {
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return CGSize(width: size.width + 10, height: size.height + 10)  // Add padding
    }

    // MARK: - Signature Support
    public func addSignatureAnnotation(at point: CGPoint, on page: Int, imageData: Data) {
        let annotation = UnifiedAnnotation(
            tool: .signature,
            frame: CGRect(origin: point, size: CGSize(width: 200, height: 80)),
            pageIndex: page
        )

        annotation.properties.signatureImage = imageData
        addAnnotation(annotation)
        selectAnnotation(annotation)
    }

    // MARK: - Shape Support
    public func addShapeAnnotation(tool: AnnotationTool, frame: CGRect, on page: Int) {
        guard [.arrow, .line, .rectangle, .oval, .polygon].contains(tool) else { return }

        let annotation = UnifiedAnnotation(
            tool: tool,
            frame: frame,
            pageIndex: page
        )

        annotation.properties.strokeColor = currentStrokeColor
        annotation.properties.fillColor = currentFillColor
        annotation.properties.strokeWidth = currentStrokeWidth

        addAnnotation(annotation)
        selectAnnotation(annotation)
    }

    // MARK: - Highlight Support
    public func addHighlightAnnotation(over textBounds: [CGRect], on page: Int) {
        guard !textBounds.isEmpty else { return }

        // Create a highlight for each text bound
        for bounds in textBounds {
            let annotation = UnifiedAnnotation(
                tool: .highlighter,
                frame: bounds,
                pageIndex: page
            )

            annotation.properties.strokeColor = .systemYellow
            annotation.properties.opacity = 0.5

            addAnnotation(annotation)
        }
    }

    // MARK: - Transform Operations
    public func moveAnnotation(_ annotation: UnifiedAnnotation, to point: CGPoint) {
        let snapshot = annotation.createSnapshot()
        addUndoAction(.modify(annotation, snapshot))

        annotation.frame.origin = point
        updateAnnotation(annotation)
    }

    public func resizeAnnotation(_ annotation: UnifiedAnnotation, to newFrame: CGRect) {
        let snapshot = annotation.createSnapshot()
        addUndoAction(.modify(annotation, snapshot))

        annotation.frame = newFrame
        updateAnnotation(annotation)
    }

    public func rotateAnnotation(_ annotation: UnifiedAnnotation, by degrees: CGFloat) {
        let snapshot = annotation.createSnapshot()
        addUndoAction(.modify(annotation, snapshot))

        annotation.rotation += degrees
        updateAnnotation(annotation)
    }

    // MARK: - Copy/Paste
    private var copiedAnnotation: UnifiedAnnotation?

    public func copySelectedAnnotation() {
        copiedAnnotation = selectedAnnotation?.copy()
    }

    public func pasteAnnotation(at point: CGPoint, on page: Int) {
        guard let copied = copiedAnnotation else { return }

        // Create a new copy of the annotation
        let pasted = UnifiedAnnotation(
            tool: copied.tool,
            frame: copied.frame,
            pageIndex: page,
            properties: copied.properties
        )
        pasted.frame.origin = point

        addAnnotation(pasted)
        selectAnnotation(pasted)
    }

    // MARK: - Undo/Redo
    private enum AnnotationAction {
        case add(UnifiedAnnotation)
        case remove(UnifiedAnnotation)
        case modify(UnifiedAnnotation, UnifiedAnnotation.Snapshot)
    }

    private func addUndoAction(_ action: AnnotationAction) {
        undoStack.append(action)

        // Limit stack size
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }

        // Clear redo stack
        redoStack.removeAll()

        updateUndoState()
    }

    public func undo() {
        guard !undoStack.isEmpty else { return }

        let action = undoStack.removeLast()
        redoStack.append(action)

        performAction(action, isUndo: true)
        updateUndoState()
    }

    public func redo() {
        guard !redoStack.isEmpty else { return }

        let action = redoStack.removeLast()
        undoStack.append(action)

        performAction(action, isUndo: false)
        updateUndoState()
    }

    private func performAction(_ action: AnnotationAction, isUndo: Bool) {
        switch action {
        case .add(let annotation):
            if isUndo {
                annotations.removeAll { $0.id == annotation.id }
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.annotationCache[annotation.pageIndex]?.removeAll { $0.id == annotation.id }
                }
            } else {
                annotations.append(annotation)
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.annotationCache[annotation.pageIndex]?.append(annotation)
                }
            }

        case .remove(let annotation):
            if isUndo {
                annotations.append(annotation)
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.annotationCache[annotation.pageIndex]?.append(annotation)
                }
            } else {
                annotations.removeAll { $0.id == annotation.id }
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.annotationCache[annotation.pageIndex]?.removeAll { $0.id == annotation.id }
                }
            }

        case .modify(let annotation, let snapshot):
            if isUndo {
                annotation.restore(from: snapshot)
            }
            updateAnnotation(annotation)
        }
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        delegate?.annotationEngineDidChangeUndoState(self)
    }

    // MARK: - Persistence
    private var persistenceManager: PDFAnnotationPersistenceManager?
    private var currentPDFDocument: StoredPDFDocument?

    public func configurePersistence(with context: NSManagedObjectContext) {
        persistenceManager = PDFAnnotationPersistenceManager(context: context)
    }

    public func saveAnnotations() {
        // Save to persistent storage
        autosaveTimer?.invalidate()

        // Save using persistence manager
        if let document = currentPDFDocument,
           let manager = persistenceManager {
            do {
                try manager.saveAnnotations(annotations, for: document)
                print("✅ Saved \(annotations.count) annotations")
            } catch {
                print("❌ Failed to save annotations: \(error)")
            }
        }

        // Restart autosave
        setupAutosave()
    }

    public func loadAnnotations(for document: PDFDocument) {
        // Load using persistence manager
        if let storedDocument = currentPDFDocument,
           let manager = persistenceManager {
            do {
                annotations = try manager.loadAnnotations(for: storedDocument)
                print("✅ Loaded \(annotations.count) annotations")
            } catch {
                print("❌ Failed to load annotations: \(error)")
                annotations = []
            }
        } else {
            annotations = []
        }

        rebuildCache()
    }

    public func setCurrentDocument(_ document: StoredPDFDocument) {
        currentPDFDocument = document
    }

    // MARK: - Export
    public func exportToPDF() -> PDFDocument? {
        guard let pdfView = pdfView,
              let document = pdfView.document else { return nil }

        let exportDocument = PDFDocument()

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // Create a copy of the page
            guard let pageCopy = page.copy() as? PDFPage else { continue }
            let newPage = pageCopy

            // Render annotations onto the page using image-based approach
            let pageAnnotations = getAnnotations(for: pageIndex)
            for annotation in pageAnnotations {
                if let stampAnnotation = createImageBasedPDFAnnotation(from: annotation, for: newPage) {
                    newPage.addAnnotation(stampAnnotation)
                }
            }

            exportDocument.insert(newPage, at: pageIndex)
        }

        return exportDocument
    }

    /// Creates a PDF annotation by rendering the UnifiedAnnotation to an image
    /// and embedding it as a stamp annotation. This approach reliably handles
    /// all annotation types including signatures, pen drawings, and complex shapes.
    private func createImageBasedPDFAnnotation(from annotation: UnifiedAnnotation, for page: PDFPage) -> PDFAnnotation? {
        // Skip selection tool and eraser - they don't produce visible annotations
        guard annotation.tool != .selection && annotation.tool != .eraser else { return nil }

        // Ensure valid frame size
        guard annotation.frame.width > 0 && annotation.frame.height > 0 else { return nil }

        // Render the annotation to an image
        guard let annotationImage = renderAnnotationToImage(annotation) else { return nil }

        // Create a custom annotation that draws the image
        let imageAnnotation = ImageStampAnnotation(
            bounds: annotation.frame,
            image: annotationImage
        )

        return imageAnnotation
    }

    /// Renders a UnifiedAnnotation to a UIImage for embedding in PDF
    private func renderAnnotationToImage(_ annotation: UnifiedAnnotation) -> UIImage? {
        // Add padding to account for stroke width
        let padding = annotation.properties.strokeWidth + 2
        let renderSize = CGSize(
            width: annotation.frame.width + padding * 2,
            height: annotation.frame.height + padding * 2
        )

        guard renderSize.width > 0 && renderSize.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: renderSize)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // Translate to account for padding
            context.translateBy(x: padding, y: padding)

            // The UnifiedAnnotation.draw() method expects to draw at origin
            // but applies transformations relative to frame.midX/midY
            // We need to adjust for this

            // Save state and set up drawing context
            context.saveGState()

            // Apply opacity
            context.setAlpha(annotation.properties.opacity)

            // Draw based on tool type (similar to UnifiedAnnotation.draw but without selection handles)
            drawAnnotationContent(annotation, in: context)

            context.restoreGState()
        }
    }

    /// Draws the annotation content into a graphics context (for export)
    private func drawAnnotationContent(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let width = annotation.frame.width
        let height = annotation.frame.height

        // Apply rotation if any
        if annotation.rotation != 0 {
            context.translateBy(x: width / 2, y: height / 2)
            context.rotate(by: annotation.rotation * .pi / 180)
            context.translateBy(x: -width / 2, y: -height / 2)
        }

        switch annotation.tool {
        case .pen, .highlighter:
            drawExportPaths(annotation, in: context)

        case .text:
            drawExportText(annotation, in: context)

        case .signature:
            drawExportSignature(annotation, in: context)

        case .arrow, .line:
            drawExportLine(annotation, in: context)

        case .rectangle:
            drawExportRectangle(annotation, in: context)

        case .oval:
            drawExportOval(annotation, in: context)

        case .note:
            drawExportNote(annotation, in: context)

        case .magnifier:
            drawExportMagnifier(annotation, in: context)

        default:
            break
        }
    }

    private func drawExportPaths(_ annotation: UnifiedAnnotation, in context: CGContext) {
        guard !annotation.properties.paths.isEmpty else { return }

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if annotation.tool == .highlighter {
            context.setBlendMode(.multiply)
            context.setAlpha(0.5)
        }

        // Translate paths relative to annotation frame origin
        let offsetX = -annotation.frame.minX
        let offsetY = -annotation.frame.minY

        let path = UIBezierPath()
        for bezierPath in annotation.properties.paths {
            guard !bezierPath.points.isEmpty else { continue }

            let adjustedPoint = CGPoint(
                x: bezierPath.points[0].x + offsetX,
                y: bezierPath.points[0].y + offsetY
            )

            switch bezierPath.type {
            case .moveTo:
                path.move(to: adjustedPoint)
            case .lineTo:
                path.addLine(to: adjustedPoint)
            case .curveTo:
                if bezierPath.points.count >= 3 {
                    path.addCurve(
                        to: CGPoint(x: bezierPath.points[2].x + offsetX, y: bezierPath.points[2].y + offsetY),
                        controlPoint1: CGPoint(x: bezierPath.points[0].x + offsetX, y: bezierPath.points[0].y + offsetY),
                        controlPoint2: CGPoint(x: bezierPath.points[1].x + offsetX, y: bezierPath.points[1].y + offsetY)
                    )
                }
            case .closePath:
                path.close()
            }
        }

        context.addPath(path.cgPath)
        context.strokePath()
    }

    private func drawExportText(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let font = UIFont(name: annotation.properties.fontName, size: annotation.properties.fontSize)
            ?? UIFont.systemFont(ofSize: annotation.properties.fontSize)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.properties.strokeColor
        ]

        let text = annotation.properties.text as NSString
        let textRect = CGRect(origin: .zero, size: annotation.frame.size)

        UIGraphicsPushContext(context)
        text.draw(in: textRect, withAttributes: attributes)
        UIGraphicsPopContext()
    }

    private func drawExportSignature(_ annotation: UnifiedAnnotation, in context: CGContext) {
        guard let imageData = annotation.properties.signatureImage,
              let image = UIImage(data: imageData) else { return }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: annotation.frame.size))
        UIGraphicsPopContext()
    }

    private func drawExportLine(_ annotation: UnifiedAnnotation, in context: CGContext) {
        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)

        if let pattern = annotation.properties.lineDashPattern {
            context.setLineDash(phase: 0, lengths: pattern)
        }

        let width = annotation.frame.width
        let height = annotation.frame.height

        context.move(to: CGPoint(x: 0, y: height / 2))
        context.addLine(to: CGPoint(x: width, y: height / 2))

        if annotation.tool == .arrow {
            // Draw arrow head
            let arrowSize: CGFloat = 12
            context.move(to: CGPoint(x: width - arrowSize, y: height / 2 - arrowSize / 2))
            context.addLine(to: CGPoint(x: width, y: height / 2))
            context.addLine(to: CGPoint(x: width - arrowSize, y: height / 2 + arrowSize / 2))
        }

        context.strokePath()
    }

    private func drawExportRectangle(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        if let fillColor = annotation.properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            if annotation.properties.cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: rect, cornerRadius: annotation.properties.cornerRadius)
                context.addPath(path.cgPath)
                context.fillPath()
            } else {
                context.fill(rect)
            }
        }

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)

        if annotation.properties.cornerRadius > 0 {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: annotation.properties.cornerRadius)
            context.addPath(path.cgPath)
        } else {
            context.addRect(rect)
        }
        context.strokePath()
    }

    private func drawExportOval(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        if let fillColor = annotation.properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: rect)
        }

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)
        context.strokeEllipse(in: rect)
    }

    private func drawExportNote(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let iconSize = min(annotation.frame.width, annotation.frame.height, 24)
        let iconRect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)

        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fillEllipse(in: iconRect)

        if let noteIcon = UIImage(systemName: "note.text")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            UIGraphicsPushContext(context)
            noteIcon.draw(in: iconRect.insetBy(dx: 4, dy: 4))
            UIGraphicsPopContext()
        }
    }

    private func drawExportMagnifier(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)
    }

    // MARK: - Private Helpers
    private func setupAutosave() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: autosaveInterval, repeats: true) { [weak self] _ in
            self?.saveAnnotations()
        }
    }

    private func rebuildCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.annotationCache.removeAll()

            guard let annotations = self?.annotations else { return }

            for annotation in annotations {
                if self?.annotationCache[annotation.pageIndex] == nil {
                    self?.annotationCache[annotation.pageIndex] = []
                }
                self?.annotationCache[annotation.pageIndex]?.append(annotation)
            }
        }
    }
}

// MARK: - Convenience Extensions
extension PDFAnnotationEngine {
    public var hasUnsavedChanges: Bool {
        return !undoStack.isEmpty
    }

    public func clearAll() {
        let allAnnotations = annotations
        annotations.removeAll()
        annotationCache.removeAll()

        // Add to undo stack
        for annotation in allAnnotations {
            addUndoAction(.remove(annotation))
        }

        selectAnnotation(nil)
    }

    public func bringToFront(_ annotation: UnifiedAnnotation) {
        let maxZIndex = annotations.map { $0.zIndex }.max() ?? 0
        annotation.zIndex = maxZIndex + 1
        updateAnnotation(annotation)
    }

    public func sendToBack(_ annotation: UnifiedAnnotation) {
        let minZIndex = annotations.map { $0.zIndex }.min() ?? 0
        annotation.zIndex = minZIndex - 1
        updateAnnotation(annotation)
    }
}

// MARK: - Image Stamp Annotation
/// A custom PDFAnnotation that draws an image directly onto the PDF page.
/// This is used for reliably embedding any annotation type (signatures, drawings, etc.)
/// into the exported PDF.
final class ImageStampAnnotation: PDFAnnotation {
    private let image: UIImage

    init(bounds: CGRect, image: UIImage) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)

        // Ensure the annotation is visible and printable
        self.shouldDisplay = true
        self.shouldPrint = true
    }

    required init?(coder: NSCoder) {
        // Attempt to decode the image data
        if let imageData = coder.decodeObject(forKey: "imageStampData") as? Data,
           let decodedImage = UIImage(data: imageData) {
            self.image = decodedImage
        } else {
            // Fallback to empty image
            self.image = UIImage()
        }
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let imageData = image.pngData() {
            coder.encode(imageData, forKey: "imageStampData")
        }
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = image.cgImage else { return }

        context.saveGState()

        // PDF coordinate system has Y pointing up, but CGImage draws with Y pointing down
        // We need to flip the coordinate system to draw the image correctly

        // Move to the bottom-left corner of the annotation bounds
        context.translateBy(x: bounds.minX, y: bounds.minY)

        // Flip the Y axis and position at top of bounds
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw the image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))

        context.restoreGState()
    }
}