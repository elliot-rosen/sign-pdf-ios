//
//  ShapeDrawingHandler.swift
//  SignSimplePDF
//
//  Interactive shape drawing with rubber band visual feedback
//

import UIKit
import PDFKit

// MARK: - Shape Drawing Delegate
public protocol ShapeDrawingHandlerDelegate: AnyObject {
    func shapeDrawingHandler(_ handler: ShapeDrawingHandler, didCreateShape shape: UnifiedAnnotation)
    func shapeDrawingHandler(_ handler: ShapeDrawingHandler, isDrawingShape frame: CGRect)
    func shapeDrawingHandlerDidCancel(_ handler: ShapeDrawingHandler)
}

// MARK: - Shape Drawing Handler
public class ShapeDrawingHandler: NSObject {
    // MARK: - Properties
    public weak var delegate: ShapeDrawingHandlerDelegate?
    public weak var annotationEngine: PDFAnnotationEngine?
    public weak var pdfView: PDFView?

    private var rubberBandView: RubberBandView?
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var isDrawing = false
    private var currentTool: AnnotationTool = .rectangle
    private var currentPageIndex = 0

    // Shape constraints
    private var constrainProportions = false  // Hold shift for square/circle

    // MARK: - Setup
    public func configure(with pdfView: PDFView, engine: PDFAnnotationEngine) {
        self.pdfView = pdfView
        self.annotationEngine = engine
    }

    // MARK: - Shape Drawing
    public func startDrawingShape(tool: AnnotationTool, at point: CGPoint, on pageIndex: Int) {
        guard [.rectangle, .oval, .line, .arrow, .polygon].contains(tool) else { return }

        currentTool = tool
        currentPageIndex = pageIndex
        startPoint = point
        currentPoint = point
        isDrawing = true

        // Create rubber band view
        createRubberBandView()
        updateRubberBand()
    }

    public func continueDrawingShape(to point: CGPoint) {
        guard isDrawing else { return }

        currentPoint = point
        updateRubberBand()

        // Notify delegate of current frame
        let frame = currentShapeFrame()
        delegate?.shapeDrawingHandler(self, isDrawingShape: frame)
    }

    public func endDrawingShape(at point: CGPoint) -> UnifiedAnnotation? {
        guard isDrawing else { return nil }

        currentPoint = point
        isDrawing = false

        // Remove rubber band
        rubberBandView?.removeFromSuperview()
        rubberBandView = nil

        // Create annotation
        let frame = currentShapeFrame()

        // Minimum size threshold
        guard frame.width > 10 && frame.height > 10 else {
            delegate?.shapeDrawingHandlerDidCancel(self)
            return nil
        }

        let annotation = createAnnotation(with: frame)
        delegate?.shapeDrawingHandler(self, didCreateShape: annotation)

        return annotation
    }

    public func cancelDrawing() {
        isDrawing = false
        rubberBandView?.removeFromSuperview()
        rubberBandView = nil
        delegate?.shapeDrawingHandlerDidCancel(self)
    }

    // MARK: - Constraint Handling
    public func setConstrainProportions(_ constrain: Bool) {
        constrainProportions = constrain
        if isDrawing {
            updateRubberBand()
        }
    }

    // MARK: - Private Methods
    private func createRubberBandView() {
        guard let pdfView = pdfView else { return }

        rubberBandView?.removeFromSuperview()

        let rubberBand = RubberBandView(frame: .zero)
        rubberBand.shapeType = currentTool
        rubberBand.strokeColor = annotationEngine?.currentStrokeColor ?? .systemBlue
        rubberBand.fillColor = annotationEngine?.currentFillColor
        rubberBand.strokeWidth = annotationEngine?.currentStrokeWidth ?? 2.0

        pdfView.addSubview(rubberBand)
        rubberBandView = rubberBand
    }

    private func updateRubberBand() {
        guard let rubberBand = rubberBandView,
              let pdfView = pdfView,
              let page = pdfView.currentPage else { return }

        // Convert to view coordinates
        let viewStart = pdfView.convert(startPoint, from: page)
        let viewCurrent = pdfView.convert(currentPoint, from: page)

        // Calculate frame
        var frame = CGRect(
            x: min(viewStart.x, viewCurrent.x),
            y: min(viewStart.y, viewCurrent.y),
            width: abs(viewCurrent.x - viewStart.x),
            height: abs(viewCurrent.y - viewStart.y)
        )

        // Apply constraints if needed
        if constrainProportions {
            frame = constrainedFrame(frame, start: viewStart, current: viewCurrent)
        }

        // Update rubber band
        rubberBand.frame = frame
        rubberBand.updateShape(from: viewStart, to: viewCurrent)
    }

    private func currentShapeFrame() -> CGRect {
        var frame = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )

        // Apply constraints if needed
        if constrainProportions {
            frame = constrainedFrame(frame, start: startPoint, current: currentPoint)
        }

        return frame
    }

    private func constrainedFrame(_ frame: CGRect, start: CGPoint, current: CGPoint) -> CGRect {
        switch currentTool {
        case .rectangle, .oval:
            // Make square/circle
            let size = min(frame.width, frame.height)
            let xSign: CGFloat = current.x >= start.x ? 1 : -1
            let ySign: CGFloat = current.y >= start.y ? 1 : -1

            return CGRect(
                x: start.x + (xSign < 0 ? -size : 0),
                y: start.y + (ySign < 0 ? -size : 0),
                width: size,
                height: size
            )

        case .line, .arrow:
            // Snap to 45-degree angles
            let dx = current.x - start.x
            let dy = current.y - start.y
            let angle = atan2(dy, dx)

            // Snap to nearest 45-degree increment
            let snappedAngle = round(angle / (.pi / 4)) * (.pi / 4)

            let distance = hypot(dx, dy)
            let snappedEnd = CGPoint(
                x: start.x + cos(snappedAngle) * distance,
                y: start.y + sin(snappedAngle) * distance
            )

            return CGRect(
                x: min(start.x, snappedEnd.x),
                y: min(start.y, snappedEnd.y),
                width: abs(snappedEnd.x - start.x),
                height: abs(snappedEnd.y - start.y)
            )

        default:
            return frame
        }
    }

    private func createAnnotation(with frame: CGRect) -> UnifiedAnnotation {
        let annotation = UnifiedAnnotation(
            tool: currentTool,
            frame: frame,
            pageIndex: currentPageIndex
        )

        // Apply current properties
        annotation.properties.strokeColor = annotationEngine?.currentStrokeColor ?? .label
        annotation.properties.fillColor = annotationEngine?.currentFillColor
        annotation.properties.strokeWidth = annotationEngine?.currentStrokeWidth ?? 2.0

        // Special handling for arrows
        if currentTool == .arrow {
            annotation.properties.arrowHeadStyle = .open
        }

        return annotation
    }
}

// MARK: - Rubber Band View
private class RubberBandView: UIView {
    // Properties
    var shapeType: AnnotationTool = .rectangle
    var strokeColor: UIColor = .systemBlue
    var fillColor: UIColor?
    var strokeWidth: CGFloat = 2.0

    private var shapeLayer = CAShapeLayer()
    private var startPoint: CGPoint = .zero
    private var endPoint: CGPoint = .zero

    // Initialization
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

        // Configure shape layer
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.lineDashPattern = [4, 2]
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round

        layer.addSublayer(shapeLayer)

        // Add animation for dashes
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = 6
        animation.duration = 0.5
        animation.repeatCount = .infinity
        shapeLayer.add(animation, forKey: "dashAnimation")
    }

    func updateShape(from start: CGPoint, to end: CGPoint) {
        startPoint = convert(start, from: superview)
        endPoint = convert(end, from: superview)

        // Update colors
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.fillColor = fillColor?.withAlphaComponent(0.2).cgColor
        shapeLayer.lineWidth = strokeWidth

        // Create path based on shape type
        let path = UIBezierPath()

        switch shapeType {
        case .rectangle:
            path.append(UIBezierPath(rect: bounds))

        case .oval:
            path.append(UIBezierPath(ovalIn: bounds))

        case .line, .arrow:
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            if shapeType == .arrow {
                // Add arrow head
                drawArrowHead(on: path, at: endPoint, from: startPoint)
            }

        case .polygon:
            // For now, draw as rectangle
            path.append(UIBezierPath(rect: bounds))

        default:
            break
        }

        shapeLayer.path = path.cgPath
    }

    private func drawArrowHead(on path: UIBezierPath, at point: CGPoint, from start: CGPoint) {
        let angle = atan2(point.y - start.y, point.x - start.x)
        let arrowLength: CGFloat = 12
        let arrowAngle: CGFloat = .pi / 6

        let arrow1 = CGPoint(
            x: point.x - arrowLength * cos(angle - arrowAngle),
            y: point.y - arrowLength * sin(angle - arrowAngle)
        )

        let arrow2 = CGPoint(
            x: point.x - arrowLength * cos(angle + arrowAngle),
            y: point.y - arrowLength * sin(angle + arrowAngle)
        )

        path.move(to: arrow1)
        path.addLine(to: point)
        path.addLine(to: arrow2)
    }
}

// MARK: - Gesture Integration
public extension ShapeDrawingHandler {
    func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let pdfView = pdfView,
              let page = pdfView.currentPage,
              let tool = annotationEngine?.currentTool,
              [.rectangle, .oval, .line, .arrow].contains(tool) else { return }

        let location = gesture.location(in: pdfView)
        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        switch gesture.state {
        case .began:
            startDrawingShape(tool: tool, at: pagePoint, on: pageIndex)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .changed:
            continueDrawingShape(to: pagePoint)

            // Check for shift key (would need keyboard monitoring for this)
            // For now, check if dragging near 45-degree angles
            let dx = pagePoint.x - startPoint.x
            let dy = pagePoint.y - startPoint.y
            let angle = atan2(dy, dx) * 180 / .pi

            // Snap to 45-degree increments if close
            let snapAngles: [CGFloat] = [0, 45, 90, 135, 180, -135, -90, -45]
            for snapAngle in snapAngles {
                if abs(angle - snapAngle) < 5 {
                    setConstrainProportions(true)
                    UISelectionFeedbackGenerator().selectionChanged()
                    break
                } else {
                    setConstrainProportions(false)
                }
            }

        case .ended:
            if let annotation = endDrawingShape(at: pagePoint) {
                annotationEngine?.addAnnotation(annotation)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

        case .cancelled:
            cancelDrawing()

        default:
            break
        }
    }
}

// MARK: - Smart Shape Detection
public extension ShapeDrawingHandler {
    func detectAndConvertShape(from points: [CGPoint]) -> UnifiedAnnotation? {
        // Use shape recognition to convert rough drawing to perfect shape
        let recognizer = ShapeRecognitionEngine()
        let recognizedShape = recognizer.recognizeShape(from: points)

        if let annotation = recognizedShape.toAnnotation(on: currentPageIndex) {
            // Apply current style
            annotation.properties.strokeColor = annotationEngine?.currentStrokeColor ?? .label
            annotation.properties.fillColor = annotationEngine?.currentFillColor
            annotation.properties.strokeWidth = annotationEngine?.currentStrokeWidth ?? 2.0

            return annotation
        }

        return nil
    }
}