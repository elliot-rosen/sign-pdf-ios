//
//  EraserTool.swift
//  SignSimplePDF
//
//  Eraser tool for removing annotations and parts of drawings
//

import UIKit
import PDFKit

// MARK: - Eraser Tool Delegate
public protocol EraserToolDelegate: AnyObject {
    func eraserTool(_ tool: EraserTool, didEraseAnnotation annotation: UnifiedAnnotation)
    func eraserTool(_ tool: EraserTool, didModifyAnnotation annotation: UnifiedAnnotation)
    func eraserToolDidStartErasing(_ tool: EraserTool)
    func eraserToolDidEndErasing(_ tool: EraserTool)
}

// MARK: - Eraser Tool
public class EraserTool: NSObject {
    // MARK: - Properties
    public weak var delegate: EraserToolDelegate?
    public weak var annotationEngine: PDFAnnotationEngine?
    public weak var pdfView: PDFView?

    // Eraser configuration
    public var eraserSize: CGFloat = 20.0 {
        didSet {
            eraserView?.frame.size = CGSize(width: eraserSize, height: eraserSize)
        }
    }

    public var eraseMode: EraseMode = .partial

    // Visual feedback
    private var eraserView: EraserCursorView?
    private var erasePath: UIBezierPath = UIBezierPath()
    private var isErasing = false

    // Tracking
    private var erasedAnnotations: Set<UUID> = []
    private var modifiedAnnotations: [UUID: UnifiedAnnotation] = [:]

    // MARK: - Eraser Modes
    public enum EraseMode {
        case partial  // Erase parts of paths
        case whole    // Erase entire annotations
    }

    // MARK: - Setup
    public func configure(with pdfView: PDFView, engine: PDFAnnotationEngine) {
        self.pdfView = pdfView
        self.annotationEngine = engine
        setupEraserCursor()
    }

    private func setupEraserCursor() {
        eraserView?.removeFromSuperview()

        let cursor = EraserCursorView(frame: CGRect(x: 0, y: 0, width: eraserSize, height: eraserSize))
        cursor.isUserInteractionEnabled = false
        cursor.isHidden = true

        pdfView?.addSubview(cursor)
        eraserView = cursor
    }

    // MARK: - Erasing
    public func startErasing(at point: CGPoint, on pageIndex: Int) {
        isErasing = true
        erasePath = UIBezierPath()
        erasePath.move(to: point)
        erasedAnnotations.removeAll()
        modifiedAnnotations.removeAll()

        showEraserCursor(at: point)
        delegate?.eraserToolDidStartErasing(self)

        // Check for annotations at this point
        eraseAt(point, on: pageIndex)
    }

    public func continueErasing(at point: CGPoint, on pageIndex: Int) {
        guard isErasing else { return }

        erasePath.addLine(to: point)
        updateEraserCursor(at: point)

        // Erase along the path
        eraseAt(point, on: pageIndex)
    }

    public func endErasing() {
        guard isErasing else { return }

        isErasing = false
        hideEraserCursor()

        // Finalize modifications
        for annotation in modifiedAnnotations.values {
            annotationEngine?.updateAnnotation(annotation)
        }

        delegate?.eraserToolDidEndErasing(self)
    }

    // MARK: - Erasing Logic
    private func eraseAt(_ point: CGPoint, on pageIndex: Int) {
        guard let engine = annotationEngine else { return }

        let annotations = engine.getAnnotations(for: pageIndex)
        let eraseRect = CGRect(
            x: point.x - eraserSize / 2,
            y: point.y - eraserSize / 2,
            width: eraserSize,
            height: eraserSize
        )

        for annotation in annotations {
            // Skip already erased annotations
            guard !erasedAnnotations.contains(annotation.id) else { continue }

            if eraseMode == .whole {
                // Whole annotation erasing
                if annotation.frame.intersects(eraseRect) || annotation.contains(point: point) {
                    eraseWholeAnnotation(annotation)
                }
            } else {
                // Partial erasing for path-based annotations
                if annotation.tool == .pen || annotation.tool == .highlighter {
                    erasePartialPath(in: annotation, at: point, eraseRect: eraseRect)
                } else if annotation.frame.intersects(eraseRect) {
                    // For non-path annotations, erase whole
                    eraseWholeAnnotation(annotation)
                }
            }
        }
    }

    private func eraseWholeAnnotation(_ annotation: UnifiedAnnotation) {
        erasedAnnotations.insert(annotation.id)
        annotationEngine?.removeAnnotation(annotation)
        delegate?.eraserTool(self, didEraseAnnotation: annotation)

        // Visual feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func erasePartialPath(in annotation: UnifiedAnnotation, at point: CGPoint, eraseRect: CGRect) {
        // Get or create modified version
        let workingAnnotation = modifiedAnnotations[annotation.id] ?? annotation

        var modifiedPaths: [BezierPath] = []
        var wasModified = false

        for path in workingAnnotation.properties.paths {
            var keepPath = true

            // Check if any point in the path is within eraser rect
            for pathPoint in path.points {
                let distance = hypot(pathPoint.x - point.x, pathPoint.y - point.y)
                if distance <= eraserSize / 2 {
                    keepPath = false
                    wasModified = true
                    break
                }
            }

            if keepPath {
                modifiedPaths.append(path)
            }
        }

        if wasModified {
            // Update the annotation's paths
            workingAnnotation.properties.paths = modifiedPaths

            // Store the modified annotation
            modifiedAnnotations[annotation.id] = workingAnnotation

            // If all paths are erased, remove the annotation
            if modifiedPaths.isEmpty {
                eraseWholeAnnotation(workingAnnotation)
            } else {
                delegate?.eraserTool(self, didModifyAnnotation: workingAnnotation)
            }

            // Visual feedback
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Advanced Path Erasing
    public func splitPath(_ path: UIBezierPath, at erasePoint: CGPoint, radius: CGFloat) -> [UIBezierPath] {
        var segments: [UIBezierPath] = []
        var currentSegment = UIBezierPath()
        var isInErasedArea = false

        // Sample points along the path
        let flatness: CGFloat = 1.0
        path.flatness = flatness

        var previousPoint: CGPoint?
        path.cgPath.applyWithBlock { element in
            var point: CGPoint = .zero

            switch element.pointee.type {
            case .moveToPoint:
                point = element.pointee.points[0]
                if !isPointInErasedArea(point, center: erasePoint, radius: radius) {
                    currentSegment.move(to: point)
                    isInErasedArea = false
                } else {
                    isInErasedArea = true
                }

            case .addLineToPoint:
                point = element.pointee.points[0]
                let inEraseArea = isPointInErasedArea(point, center: erasePoint, radius: radius)

                if !isInErasedArea && !inEraseArea {
                    // Both points outside eraser
                    currentSegment.addLine(to: point)
                } else if isInErasedArea && !inEraseArea {
                    // Exiting eraser area
                    currentSegment = UIBezierPath()
                    currentSegment.move(to: point)
                    isInErasedArea = false
                } else if !isInErasedArea && inEraseArea {
                    // Entering eraser area
                    if !currentSegment.isEmpty {
                        segments.append(currentSegment)
                    }
                    currentSegment = UIBezierPath()
                    isInErasedArea = true
                }

            case .addQuadCurveToPoint:
                point = element.pointee.points[1]
                let controlPoint = element.pointee.points[0]

                if !isPointInErasedArea(point, center: erasePoint, radius: radius) &&
                   !isPointInErasedArea(controlPoint, center: erasePoint, radius: radius) {
                    currentSegment.addQuadCurve(to: point, controlPoint: controlPoint)
                }

            case .addCurveToPoint:
                point = element.pointee.points[2]
                let cp1 = element.pointee.points[0]
                let cp2 = element.pointee.points[1]

                if !isPointInErasedArea(point, center: erasePoint, radius: radius) &&
                   !isPointInErasedArea(cp1, center: erasePoint, radius: radius) &&
                   !isPointInErasedArea(cp2, center: erasePoint, radius: radius) {
                    currentSegment.addCurve(to: point, controlPoint1: cp1, controlPoint2: cp2)
                }

            case .closeSubpath:
                currentSegment.close()
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                }
                currentSegment = UIBezierPath()

            @unknown default:
                break
            }

            previousPoint = point
        }

        // Add final segment if not empty
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        return segments
    }

    private func isPointInErasedArea(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance <= radius
    }

    // MARK: - Eraser Cursor
    private func showEraserCursor(at point: CGPoint) {
        guard let cursor = eraserView,
              let pdfView = pdfView,
              let currentPage = pdfView.currentPage else { return }

        cursor.center = pdfView.convert(point, from: currentPage)
        cursor.isHidden = false
        cursor.alpha = 0.8

        UIView.animate(withDuration: 0.1) {
            cursor.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }
    }

    private func updateEraserCursor(at point: CGPoint) {
        guard let cursor = eraserView,
              let pdfView = pdfView,
              let currentPage = pdfView.currentPage else { return }

        UIView.animate(withDuration: 0.05) {
            cursor.center = pdfView.convert(point, from: currentPage)
        }
    }

    private func hideEraserCursor() {
        UIView.animate(withDuration: 0.2) {
            self.eraserView?.alpha = 0
            self.eraserView?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.eraserView?.isHidden = true
            self.eraserView?.transform = .identity
        }
    }
}

// MARK: - Eraser Cursor View
private class EraserCursorView: UIView {
    private let circleLayer = CAShapeLayer()
    private let crossLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        // Circle outline
        circleLayer.fillColor = UIColor.white.withAlphaComponent(0.3).cgColor
        circleLayer.strokeColor = UIColor.darkGray.cgColor
        circleLayer.lineWidth = 1.5
        layer.addSublayer(circleLayer)

        // Cross in center
        crossLayer.strokeColor = UIColor.darkGray.cgColor
        crossLayer.lineWidth = 1
        crossLayer.lineCap = .round
        layer.addSublayer(crossLayer)

        updatePaths()
    }

    override var frame: CGRect {
        didSet {
            updatePaths()
        }
    }

    private func updatePaths() {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = min(bounds.width, bounds.height) / 2

        // Circle path
        let circlePath = UIBezierPath(
            arcCenter: center,
            radius: radius - 1,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        circleLayer.path = circlePath.cgPath

        // Cross path
        let crossPath = UIBezierPath()
        let crossSize: CGFloat = 6

        crossPath.move(to: CGPoint(x: center.x - crossSize, y: center.y))
        crossPath.addLine(to: CGPoint(x: center.x + crossSize, y: center.y))

        crossPath.move(to: CGPoint(x: center.x, y: center.y - crossSize))
        crossPath.addLine(to: CGPoint(x: center.x, y: center.y + crossSize))

        crossLayer.path = crossPath.cgPath
    }
}

// MARK: - Gesture Integration
public extension EraserTool {
    func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let pdfView = pdfView,
              let page = pdfView.currentPage else { return }

        let location = gesture.location(in: pdfView)
        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        switch gesture.state {
        case .began:
            startErasing(at: pagePoint, on: pageIndex)

        case .changed:
            continueErasing(at: pagePoint, on: pageIndex)

        case .ended, .cancelled:
            endErasing()

        default:
            break
        }
    }
}