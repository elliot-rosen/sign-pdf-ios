//
//  PenTool.swift
//  SignSimplePDF
//
//  PencilKit integration for pen and highlighter tools
//

import UIKit
import PencilKit

// MARK: - Pen Tool Handler
public class PenToolHandler: NSObject {
    // MARK: - Properties
    private weak var annotationEngine: PDFAnnotationEngine?
    private var canvasView: PKCanvasView?
    private var currentPageIndex: Int = 0

    // MARK: - Setup
    public func configure(with engine: PDFAnnotationEngine, canvasView: PKCanvasView) {
        self.annotationEngine = engine
        self.canvasView = canvasView
        setupCanvas()
    }

    private func setupCanvas() {
        guard let canvas = canvasView else { return }

        // Configure for current tool
        if annotationEngine?.currentTool == .pen {
            canvas.tool = PKInkingTool(.pen, color: annotationEngine?.currentStrokeColor ?? .black, width: annotationEngine?.currentStrokeWidth ?? 2)
        } else if annotationEngine?.currentTool == .highlighter {
            canvas.tool = PKInkingTool(.marker, color: annotationEngine?.currentStrokeColor.withAlphaComponent(0.5) ?? .yellow, width: annotationEngine?.currentStrokeWidth ?? 15)
        }

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = self
    }

    // MARK: - Drawing Conversion
    public func convertDrawingToAnnotation(_ drawing: PKDrawing, on pageIndex: Int) -> UnifiedAnnotation? {
        let strokes = drawing.strokes
        guard !strokes.isEmpty else { return nil }

        // Calculate bounds
        let bounds = drawing.bounds

        // Create annotation
        let tool: AnnotationTool = annotationEngine?.currentTool ?? .pen
        let annotation = UnifiedAnnotation(
            tool: tool,
            frame: bounds,
            pageIndex: pageIndex
        )

        // Convert strokes to paths
        var paths: [BezierPath] = []

        for stroke in strokes {
            let strokePath = stroke.path
            var isFirstPoint = true

            for point in strokePath {
                let cgPoint = point.location

                if isFirstPoint {
                    paths.append(BezierPath(points: [cgPoint], type: .moveTo))
                    isFirstPoint = false
                } else {
                    paths.append(BezierPath(points: [cgPoint], type: .lineTo))
                }
            }
        }

        annotation.properties.paths = paths
        annotation.properties.strokeColor = annotationEngine?.currentStrokeColor ?? .black
        annotation.properties.strokeWidth = annotationEngine?.currentStrokeWidth ?? 2

        if tool == .highlighter {
            annotation.properties.opacity = 0.5
        }

        return annotation
    }

    // MARK: - Clear Canvas
    public func clearCanvas() {
        canvasView?.drawing = PKDrawing()
    }
}

// MARK: - PKCanvasViewDelegate
extension PenToolHandler: PKCanvasViewDelegate {
    public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Convert drawing to annotation in real-time
        guard let annotation = convertDrawingToAnnotation(canvasView.drawing, on: currentPageIndex) else { return }

        // Update or add annotation
        if let existingAnnotation = annotationEngine?.selectedAnnotation,
           existingAnnotation.tool == annotation.tool {
            // Update existing
            existingAnnotation.frame = annotation.frame
            existingAnnotation.properties = annotation.properties
            annotationEngine?.updateAnnotation(existingAnnotation)
        } else {
            // Add new
            annotationEngine?.addAnnotation(annotation)
            annotationEngine?.selectAnnotation(annotation)
        }
    }
}