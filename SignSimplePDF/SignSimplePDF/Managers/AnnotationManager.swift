import Foundation
import PDFKit
import UIKit
import SwiftUI

// MARK: - Annotation Types

enum AnnotationType {
    case signature(imageData: Data)
    case text(content: String, fontSize: CGFloat, color: UIColor)
    case highlight(color: UIColor)
    case drawing(paths: [DrawingPath], color: UIColor, lineWidth: CGFloat)
}

// Structure to store drawing path data
struct DrawingPath: Codable {
    let points: [CGPoint]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let pointsData = points.map { ["x": $0.x, "y": $0.y] }
        try container.encode(pointsData, forKey: .points)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pointsData = try container.decode([[String: CGFloat]].self, forKey: .points)
        self.points = pointsData.compactMap { dict in
            guard let x = dict["x"], let y = dict["y"] else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    init(points: [CGPoint]) {
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case points
    }
}

// MARK: - Annotation Model

class PDFAnnotationItem: ObservableObject, Identifiable {
    let id = UUID()
    let type: AnnotationType

    /// Position in PDF coordinates (bottom-left origin)
    /// This is the ONLY source of truth for position
    @Published var pdfPosition: CGPoint

    /// Base size before scaling
    @Published var size: CGSize

    /// Page index in the document
    @Published var pageIndex: Int

    /// Selection state
    @Published var isSelected: Bool = false

    /// Scale factor applied to base size
    @Published var scale: CGFloat = 1.0

    /// Reference to the actual PDFAnnotation when applied to document
    var pdfAnnotation: PDFAnnotation?

    init(type: AnnotationType, pdfPosition: CGPoint, size: CGSize, pageIndex: Int) {
        self.type = type
        self.pdfPosition = pdfPosition
        self.size = size
        self.pageIndex = pageIndex
    }

    /// The actual display size after scaling
    var displaySize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The bounds in PDF coordinates
    var pdfBounds: CGRect {
        CGRect(origin: pdfPosition, size: displaySize)
    }

    /// Move annotation to new PDF position
    func move(to newPDFPosition: CGPoint) {
        pdfPosition = newPDFPosition
    }

    /// Create a deep copy of this annotation
    func copy() -> PDFAnnotationItem {
        let item = PDFAnnotationItem(type: type, pdfPosition: pdfPosition, size: size, pageIndex: pageIndex)
        item.scale = scale
        item.isSelected = isSelected
        return item
    }

    /// Get screen bounds for current PDFView state (computed on-demand)
    func screenBounds(on page: PDFPage, in pdfView: PDFView) -> CGRect {
        return PDFCoordinateConverter.pdfToScreen(rect: pdfBounds, on: page, in: pdfView)
    }
}

// MARK: - Edit Actions for Undo/Redo

enum PDFEditAction {
    case add(annotation: PDFAnnotationItem)
    case delete(annotation: PDFAnnotationItem)
    case move(annotation: PDFAnnotationItem, from: CGPoint, to: CGPoint)
    case modify(annotation: PDFAnnotationItem, oldState: PDFAnnotationItem)

    var inverse: PDFEditAction {
        switch self {
        case .add(let annotation):
            return .delete(annotation: annotation)
        case .delete(let annotation):
            return .add(annotation: annotation)
        case .move(let annotation, let from, let to):
            return .move(annotation: annotation, from: to, to: from)
        case .modify(let annotation, let oldState):
            return .modify(annotation: oldState, oldState: annotation)
        }
    }
}

// MARK: - Annotation Manager

@MainActor
class AnnotationManager: ObservableObject {
    @Published var annotations: [PDFAnnotationItem] = []
    @Published var selectedAnnotation: PDFAnnotationItem?
    @Published var hasUnsavedChanges: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    private var undoStack: [PDFEditAction] = []
    private var redoStack: [PDFEditAction] = []
    private let maxUndoStackSize = 50

    // MARK: - Annotation Management

    func addAnnotation(_ annotation: PDFAnnotationItem) {
        annotations.append(annotation)
        recordAction(.add(annotation: annotation))
        hasUnsavedChanges = true
    }

    func deleteAnnotation(_ annotation: PDFAnnotationItem) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations.remove(at: index)
            recordAction(.delete(annotation: annotation))
            if selectedAnnotation?.id == annotation.id {
                selectedAnnotation = nil
            }
            hasUnsavedChanges = true
        }
    }

    func recordModification(of annotation: PDFAnnotationItem, from oldState: PDFAnnotationItem) {
        let newState = annotation.copy()
        recordAction(.modify(annotation: newState, oldState: oldState))
        hasUnsavedChanges = true
    }

    func moveAnnotation(_ annotation: PDFAnnotationItem, to newPDFPosition: CGPoint) {
        let oldPosition = annotation.pdfPosition
        annotation.move(to: newPDFPosition)
        recordAction(.move(annotation: annotation, from: oldPosition, to: newPDFPosition))
        hasUnsavedChanges = true
    }

    func selectAnnotation(_ annotation: PDFAnnotationItem?) {
        selectedAnnotation?.isSelected = false
        selectedAnnotation = annotation
        annotation?.isSelected = true
    }

    func deselectAll() {
        selectedAnnotation?.isSelected = false
        selectedAnnotation = nil
    }

    // MARK: - Undo/Redo

    private func recordAction(_ action: PDFEditAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateUndoRedoState()
    }

    func undo() {
        guard !undoStack.isEmpty else { return }

        let action = undoStack.removeLast()
        executeAction(action.inverse, recordInRedo: true)
        updateUndoRedoState()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }

        let action = redoStack.removeLast()
        executeAction(action.inverse, recordInRedo: false, recordInUndo: true)
        updateUndoRedoState()
    }

    private func executeAction(_ action: PDFEditAction, recordInRedo: Bool = false, recordInUndo: Bool = false) {
        switch action {
        case .add(let annotation):
            annotations.append(annotation)
            if recordInRedo {
                redoStack.append(action.inverse)
            }
            if recordInUndo {
                undoStack.append(action.inverse)
            }

        case .delete(let annotation):
            if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
                annotations.remove(at: index)
                if selectedAnnotation?.id == annotation.id {
                    selectedAnnotation = nil
                }
            }
            if recordInRedo {
                redoStack.append(action.inverse)
            }
            if recordInUndo {
                undoStack.append(action.inverse)
            }

        case .move(let annotation, _, let to):
            if let existingAnnotation = annotations.first(where: { $0.id == annotation.id }) {
                existingAnnotation.pdfPosition = to
            }
            if recordInRedo {
                redoStack.append(action.inverse)
            }
            if recordInUndo {
                undoStack.append(action.inverse)
            }

        case .modify(let annotationState, _):
            if let existingAnnotation = annotations.first(where: { $0.id == annotationState.id }) {
                applyState(annotationState, to: existingAnnotation)
            }
            if recordInRedo {
                redoStack.append(action.inverse)
            }
            if recordInUndo {
                undoStack.append(action.inverse)
            }
        }

        hasUnsavedChanges = true
    }

    private func updateUndoRedoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Save/Reset

    func applyToPDF(document: PDFDocument) throws {
        print("📝 [AnnotationManager] applyToPDF - Starting to apply \(annotations.count) annotations")

        // Apply all annotations to the actual PDF
        for (index, annotation) in annotations.enumerated() {
            guard let page = document.page(at: annotation.pageIndex) else {
                print("⚠️ [AnnotationManager] Page not found for annotation \(index) at pageIndex \(annotation.pageIndex)")
                continue
            }

            print("📍 [AnnotationManager] Annotation \(index) - Type: \(annotation.type)")
            print("   Before: pdfPosition=\(annotation.pdfPosition), size=\(annotation.size), scale=\(annotation.scale)")
            print("   pdfBounds=\(annotation.pdfBounds)")

            switch annotation.type {
            case .signature(let imageData):
                guard let image = UIImage(data: imageData) else { continue }
                if let existing = annotation.pdfAnnotation {
                    page.removeAnnotation(existing)
                }
                let signatureAnnotation = SignatureAnnotation(bounds: annotation.pdfBounds, image: image)
                print("   ✏️ Created SignatureAnnotation with bounds: \(signatureAnnotation.bounds)")
                page.addAnnotation(signatureAnnotation)
                annotation.pdfAnnotation = signatureAnnotation

            case .text(let content, let fontSize, let color):
                if let existing = annotation.pdfAnnotation {
                    page.removeAnnotation(existing)
                }
                let textAnnotation = PDFAnnotation(
                    bounds: annotation.pdfBounds,
                    forType: .freeText,
                    withProperties: nil
                )
                textAnnotation.contents = content

                // Use original fontSize without scaling to prevent repositioning
                // The scale is already applied to annotation.pdfBounds.size
                textAnnotation.font = UIFont.systemFont(ofSize: fontSize)
                textAnnotation.fontColor = color

                // Explicitly set background to transparent using UIColor with 0 alpha
                // .clear might not work correctly with PDFKit
                textAnnotation.backgroundColor = UIColor.white.withAlphaComponent(0.0)

                // Remove border completely
                textAnnotation.color = UIColor.clear  // Border/stroke color
                let border = PDFBorder()
                border.lineWidth = 0
                textAnnotation.border = border

                // Prevent auto-sizing behavior that might shift text
                textAnnotation.shouldDisplay = true
                textAnnotation.shouldPrint = true

                print("   ✏️ Created TextAnnotation:")
                print("      content='\(content)', fontSize=\(fontSize) (NOT scaled)")
                print("      bounds=\(textAnnotation.bounds)")
                print("      backgroundColor=\(String(describing: textAnnotation.backgroundColor))")
                print("      border.lineWidth=\(textAnnotation.border?.lineWidth ?? -1)")

                page.addAnnotation(textAnnotation)
                annotation.pdfAnnotation = textAnnotation

            case .highlight(let color):
                if let existing = annotation.pdfAnnotation {
                    page.removeAnnotation(existing)
                }
                let highlightAnnotation = PDFAnnotation(
                    bounds: annotation.pdfBounds,
                    forType: .highlight,
                    withProperties: nil
                )
                highlightAnnotation.color = color.withAlphaComponent(0.3)
                print("   ✏️ Created HighlightAnnotation with bounds: \(highlightAnnotation.bounds)")
                page.addAnnotation(highlightAnnotation)
                annotation.pdfAnnotation = highlightAnnotation

            case .drawing(let paths, let color, let lineWidth):
                if let existing = annotation.pdfAnnotation {
                    page.removeAnnotation(existing)
                }

                // Use DrawingAnnotation for proper coordinate handling
                let drawingAnnotation = DrawingAnnotation(
                    bounds: annotation.pdfBounds,
                    paths: paths,
                    color: color,
                    lineWidth: lineWidth
                )

                print("   ✏️ Created DrawingAnnotation:")
                print("      paths.count=\(paths.count), lineWidth=\(lineWidth)")
                print("      bounds=\(drawingAnnotation.bounds)")

                page.addAnnotation(drawingAnnotation)
                annotation.pdfAnnotation = drawingAnnotation
            }

            // Log annotation after adding to page
            if let pdfAnnotation = annotation.pdfAnnotation {
                print("   ✅ Added to page - Final bounds in PDF: \(pdfAnnotation.bounds)")
            }
        }

        print("✅ [AnnotationManager] applyToPDF - Completed")
        clearHistory()
    }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        hasUnsavedChanges = false
        updateUndoRedoState()
    }

    func reset() {
        annotations.removeAll()
        selectedAnnotation = nil
        clearHistory()
    }

    // MARK: - Coordinate Transformations (Delegate to PDFCoordinateConverter)

    /// Convert a PDF point to screen coordinates
    func pdfToScreen(point: CGPoint, on page: PDFPage, in pdfView: PDFView) -> CGPoint {
        return PDFCoordinateConverter.pdfToScreen(point: point, on: page, in: pdfView)
    }

    /// Convert a PDF rectangle to screen coordinates
    func pdfToScreen(rect: CGRect, on page: PDFPage, in pdfView: PDFView) -> CGRect {
        return PDFCoordinateConverter.pdfToScreen(rect: rect, on: page, in: pdfView)
    }

    /// Convert a screen point to PDF coordinates
    func screenToPDF(point: CGPoint, on page: PDFPage, in pdfView: PDFView) -> CGPoint {
        return PDFCoordinateConverter.screenToPDF(point: point, on: page, in: pdfView)
    }

    /// Convert a screen rectangle to PDF coordinates
    func screenToPDF(rect: CGRect, on page: PDFPage, in pdfView: PDFView) -> CGRect {
        return PDFCoordinateConverter.screenToPDF(rect: rect, on: page, in: pdfView)
    }

    // MARK: - Helper Methods

    func annotationAt(pdfPoint: CGPoint, pageIndex: Int) -> PDFAnnotationItem? {
        return annotations
            .filter { $0.pageIndex == pageIndex }
            .first { annotation in
                annotation.pdfBounds.contains(pdfPoint)
            }
    }

    func deleteSelectedAnnotation() {
        if let selected = selectedAnnotation {
            deleteAnnotation(selected)
        }
    }

    func clamp(pdfPosition: CGPoint, size: CGSize, on page: PDFPage) -> CGPoint {
        return PDFCoordinateConverter.clamp(pdfPoint: pdfPosition, size: size, on: page)
    }

    func applyState(_ state: PDFAnnotationItem, to target: PDFAnnotationItem) {
        target.pdfPosition = state.pdfPosition
        target.size = state.size
        target.scale = state.scale
        target.pageIndex = state.pageIndex
    }
}
