//
//  AnnotationInteractionHandler.swift
//  SignSimplePDF
//
//  Handles all gesture-based interactions for PDF annotations
//

import UIKit
import PDFKit

// MARK: - Interaction Handle Type
public enum InteractionHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case topCenter, bottomCenter, leftCenter, rightCenter
    case rotation
    case move
    case none
}

// MARK: - Interaction Delegate
public protocol AnnotationInteractionHandlerDelegate: AnyObject {
    func interactionHandler(_ handler: AnnotationInteractionHandler, didSelectAnnotation annotation: UnifiedAnnotation?)
    func interactionHandler(_ handler: AnnotationInteractionHandler, didMoveAnnotation annotation: UnifiedAnnotation, to point: CGPoint)
    func interactionHandler(_ handler: AnnotationInteractionHandler, didResizeAnnotation annotation: UnifiedAnnotation, to frame: CGRect)
    func interactionHandler(_ handler: AnnotationInteractionHandler, didRotateAnnotation annotation: UnifiedAnnotation, by degrees: CGFloat)
    func interactionHandler(_ handler: AnnotationInteractionHandler, shouldBeginEditing annotation: UnifiedAnnotation) -> Bool
    func interactionHandler(_ handler: AnnotationInteractionHandler, didBeginEditing annotation: UnifiedAnnotation)
    func interactionHandler(_ handler: AnnotationInteractionHandler, didEndEditing annotation: UnifiedAnnotation)
    func interactionHandler(_ handler: AnnotationInteractionHandler, requestsContextMenu for: UnifiedAnnotation, at point: CGPoint)
    func interactionHandler(_ handler: AnnotationInteractionHandler, requestsSignaturePickerAt point: CGPoint, on pageIndex: Int)
}

// MARK: - Annotation Interaction Handler
public class AnnotationInteractionHandler: NSObject {
    // MARK: - Properties
    public weak var delegate: AnnotationInteractionHandlerDelegate?
    public weak var annotationEngine: PDFAnnotationEngine?
    public weak var pdfView: PDFView?

    // Interaction state
    private var currentInteractionHandle: InteractionHandle = .none
    private var initialTouchPoint: CGPoint = .zero
    private var initialAnnotationFrame: CGRect = .zero
    private var initialRotation: CGFloat = 0
    private var lastTouchPoint: CGPoint = .zero
    private var isDragging = false
    private var isPinching = false
    private var isRotating = false

    // Multi-touch tracking
    private var activeTouches: Set<UITouch> = []
    private var initialPinchScale: CGFloat = 1.0
    private var initialPinchFrame: CGRect = .zero

    // Haptic feedback
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    // Configuration
    public var isEnabled: Bool = true
    public var handleSize: CGFloat = 44.0  // Touch target size
    public var rotationHandleOffset: CGFloat = 30.0
    public var minimumAnnotationSize: CGSize = CGSize(width: 20, height: 20)
    public var maximumAnnotationSize: CGSize = CGSize(width: 2000, height: 2000)

    // MARK: - Initialization
    public override init() {
        super.init()
        impactFeedback.prepare()
        selectionFeedback.prepare()
    }

    // Track the view where gestures are attached
    private weak var gestureTargetView: UIView?

    // MARK: - Configuration
    /// Configure the interaction handler
    /// - Parameters:
    ///   - pdfView: The PDF view for coordinate conversion
    ///   - engine: The annotation engine
    ///   - gestureTarget: The view to attach gesture recognizers to (typically the overlay view)
    public func configure(with pdfView: PDFView, engine: PDFAnnotationEngine, gestureTarget: UIView? = nil) {
        self.pdfView = pdfView
        self.annotationEngine = engine
        // Use provided gestureTarget, or fall back to pdfView for backwards compatibility
        let targetView = gestureTarget ?? pdfView
        self.gestureTargetView = targetView
        setupGestureRecognizers(on: targetView)
    }

    private func setupGestureRecognizers(on targetView: UIView) {
        // Remove existing gesture recognizers if any
        targetView.gestureRecognizers?.forEach { gesture in
            if gesture.delegate === self {
                targetView.removeGestureRecognizer(gesture)
            }
        }

        // Tap gesture for selection
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        targetView.addGestureRecognizer(tapGesture)

        // Double tap for editing
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        targetView.addGestureRecognizer(doubleTapGesture)

        // Long press for context menu
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        targetView.addGestureRecognizer(longPressGesture)

        // Pan gesture for moving
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        targetView.addGestureRecognizer(panGesture)

        // Pinch gesture for scaling
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        targetView.addGestureRecognizer(pinchGesture)

        // Rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        targetView.addGestureRecognizer(rotationGesture)

        // Ensure tap requires double tap to fail
        tapGesture.require(toFail: doubleTapGesture)
    }

    // MARK: - Gesture Handlers
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard isEnabled,
              let pdfView = pdfView,
              let engine = annotationEngine else { return }

        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return }

        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        // Check if tapping on an annotation
        if let annotation = engine.annotation(at: pagePoint, on: pageIndex) {
            // Check if tapping on a handle
            let handle = interactionHandle(at: location, for: annotation)
            if handle != .none {
                currentInteractionHandle = handle
            } else {
                // Select the annotation
                engine.selectAnnotation(annotation)
                delegate?.interactionHandler(self, didSelectAnnotation: annotation)
                selectionFeedback.selectionChanged()
            }
        } else {
            // Deselect current annotation or add new one based on tool
            if engine.currentTool == .selection {
                engine.selectAnnotation(nil)
                delegate?.interactionHandler(self, didSelectAnnotation: nil)
            } else {
                // Handle tool-specific tap actions
                handleToolTap(at: pagePoint, on: pageIndex)
            }
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let pdfView = pdfView,
              let engine = annotationEngine else { return }

        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return }

        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        if let annotation = engine.annotation(at: pagePoint, on: pageIndex) {
            if annotation.tool == .text {
                // Begin editing text
                if delegate?.interactionHandler(self, shouldBeginEditing: annotation) ?? true {
                    annotation.isEditing = true
                    delegate?.interactionHandler(self, didBeginEditing: annotation)
                    impactFeedback.impactOccurred()
                }
            }
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let pdfView = pdfView,
              let engine = annotationEngine else { return }

        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return }

        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        if let annotation = engine.annotation(at: pagePoint, on: pageIndex) {
            engine.selectAnnotation(annotation)
            delegate?.interactionHandler(self, requestsContextMenu: annotation, at: location)
            impactFeedback.impactOccurred(intensity: 0.75)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEnabled,
              let pdfView = pdfView,
              let engine = annotationEngine else { return }

        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true),
              let pageIndex = pdfView.document?.index(for: page) else { return }

        let pagePoint = pdfView.convert(location, to: page)

        // DRAWING MODE: Handle pen/highlighter tools via pan gesture
        if engine.currentTool == .pen || engine.currentTool == .highlighter {
            switch gesture.state {
            case .began:
                engine.startDrawing(at: pagePoint, on: pageIndex)
                impactFeedback.impactOccurred(intensity: 0.3)
            case .changed:
                engine.continueDrawing(to: pagePoint)
            case .ended, .cancelled:
                engine.endDrawing()
            default:
                break
            }
            return  // Don't continue to selection/moving logic
        }

        // SELECTION/MOVING MODE: Requires a selected annotation
        guard let selectedAnnotation = engine.selectedAnnotation else { return }

        switch gesture.state {
        case .began:
            isDragging = true
            initialTouchPoint = pagePoint
            initialAnnotationFrame = selectedAnnotation.frame
            initialRotation = selectedAnnotation.rotation

            // Determine interaction handle if not already set
            if currentInteractionHandle == .none {
                currentInteractionHandle = interactionHandle(at: location, for: selectedAnnotation)
            }

            // Visual feedback
            UIView.animate(withDuration: 0.1) {
                selectedAnnotation.isDragging = true
            }

        case .changed:
            let translation = CGPoint(
                x: pagePoint.x - initialTouchPoint.x,
                y: pagePoint.y - initialTouchPoint.y
            )

            switch currentInteractionHandle {
            case .move, .none:
                // Move the annotation
                let newOrigin = CGPoint(
                    x: initialAnnotationFrame.origin.x + translation.x,
                    y: initialAnnotationFrame.origin.y + translation.y
                )
                selectedAnnotation.frame.origin = newOrigin
                delegate?.interactionHandler(self, didMoveAnnotation: selectedAnnotation, to: newOrigin)

            case .rotation:
                // Rotate the annotation
                let center = CGPoint(
                    x: initialAnnotationFrame.midX,
                    y: initialAnnotationFrame.midY
                )
                let angle1 = atan2(initialTouchPoint.y - center.y, initialTouchPoint.x - center.x)
                let angle2 = atan2(pagePoint.y - center.y, pagePoint.x - center.x)
                let rotation = (angle2 - angle1) * 180 / .pi

                selectedAnnotation.rotation = initialRotation + rotation
                delegate?.interactionHandler(self, didRotateAnnotation: selectedAnnotation, by: rotation)

            default:
                // Resize the annotation
                let newFrame = resizedFrame(
                    from: initialAnnotationFrame,
                    handle: currentInteractionHandle,
                    translation: translation
                )
                selectedAnnotation.frame = newFrame
                delegate?.interactionHandler(self, didResizeAnnotation: selectedAnnotation, to: newFrame)
            }

            // Haptic feedback at boundaries
            if shouldProvideBoundaryFeedback(for: selectedAnnotation) {
                impactFeedback.impactOccurred(intensity: 0.5)
            }

        case .ended, .cancelled:
            isDragging = false
            currentInteractionHandle = .none

            // Visual feedback
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                selectedAnnotation.isDragging = false
            }

            // Final update
            engine.updateAnnotation(selectedAnnotation)

        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let engine = annotationEngine,
              let selectedAnnotation = engine.selectedAnnotation else { return }

        switch gesture.state {
        case .began:
            isPinching = true
            initialPinchScale = gesture.scale
            initialPinchFrame = selectedAnnotation.frame
            impactFeedback.impactOccurred(intensity: 0.3)

        case .changed:
            let scale = gesture.scale / initialPinchScale
            let newSize = CGSize(
                width: initialPinchFrame.width * scale,
                height: initialPinchFrame.height * scale
            )

            // Apply size constraints
            let constrainedSize = constrainSize(newSize)

            // Keep center point fixed
            let centerX = selectedAnnotation.frame.midX
            let centerY = selectedAnnotation.frame.midY

            selectedAnnotation.frame = CGRect(
                x: centerX - constrainedSize.width / 2,
                y: centerY - constrainedSize.height / 2,
                width: constrainedSize.width,
                height: constrainedSize.height
            )

            delegate?.interactionHandler(self, didResizeAnnotation: selectedAnnotation, to: selectedAnnotation.frame)

            // Haptic feedback at scale thresholds
            let thresholds: [CGFloat] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
            for threshold in thresholds {
                if abs(scale - threshold) < 0.05 {
                    selectionFeedback.selectionChanged()
                    break
                }
            }

        case .ended, .cancelled:
            isPinching = false
            engine.updateAnnotation(selectedAnnotation)

        default:
            break
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let engine = annotationEngine,
              let selectedAnnotation = engine.selectedAnnotation else { return }

        switch gesture.state {
        case .began:
            isRotating = true
            initialRotation = selectedAnnotation.rotation
            impactFeedback.impactOccurred(intensity: 0.3)

        case .changed:
            let rotation = gesture.rotation * 180 / .pi
            selectedAnnotation.rotation = initialRotation + rotation

            delegate?.interactionHandler(self, didRotateAnnotation: selectedAnnotation, by: rotation)

            // Snap to 45-degree increments with haptic feedback
            let snappedAngle = round(selectedAnnotation.rotation / 45) * 45
            if abs(selectedAnnotation.rotation - snappedAngle) < 5 {
                selectedAnnotation.rotation = snappedAngle
                selectionFeedback.selectionChanged()
            }

        case .ended, .cancelled:
            isRotating = false
            engine.updateAnnotation(selectedAnnotation)

        default:
            break
        }
    }

    // MARK: - Tool-Specific Tap Handling
    private func handleToolTap(at point: CGPoint, on pageIndex: Int) {
        guard let engine = annotationEngine else {
            print("⚠️ handleToolTap: No engine")
            return
        }

        print("🎯 handleToolTap: tool=\(engine.currentTool), point=\(point), page=\(pageIndex)")

        switch engine.currentTool {
        case .text:
            // Show text input
            print("   -> Showing text input")
            showTextInput(at: point, on: pageIndex)

        case .signature:
            // Show signature picker
            print("   -> Showing signature picker")
            showSignaturePicker(at: point, on: pageIndex)

        case .note:
            // Add note annotation
            addNoteAnnotation(at: point, on: pageIndex)

        case .pen, .highlighter:
            // Start drawing
            engine.startDrawing(at: point, on: pageIndex)

        case .arrow, .line, .rectangle, .oval:
            // Start shape drawing
            startShapeDrawing(at: point, on: pageIndex)

        default:
            break
        }
    }

    private func showTextInput(at point: CGPoint, on pageIndex: Int) {
        guard let engine = annotationEngine else {
            print("⚠️ showTextInput: No engine")
            return
        }

        let alert = UIAlertController(title: "Add Text", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Enter text..."
            textField.autocapitalizationType = .sentences
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak engine] _ in
            if let text = alert.textFields?.first?.text, !text.isEmpty {
                print("   Adding text annotation: '\(text)'")
                engine?.addTextAnnotation(at: point, on: pageIndex, text: text)
            }
        })

        // Find the topmost view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            print("   Presenting text input alert from: \(type(of: topVC))")
            topVC.present(alert, animated: true)
        } else {
            print("⚠️ showTextInput: Could not find view controller to present from")
        }
    }

    private func showSignaturePicker(at point: CGPoint, on pageIndex: Int) {
        // Delegate handles presenting the signature picker UI
        if delegate == nil {
            print("⚠️ showSignaturePicker: No delegate set!")
        } else {
            print("   Calling delegate to show signature picker")
        }
        delegate?.interactionHandler(self, requestsSignaturePickerAt: point, on: pageIndex)
    }

    private func addNoteAnnotation(at point: CGPoint, on pageIndex: Int) {
        guard let engine = annotationEngine else { return }

        let noteAnnotation = UnifiedAnnotation(
            tool: .note,
            frame: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24),
            pageIndex: pageIndex
        )
        noteAnnotation.properties.noteContent = ""
        noteAnnotation.properties.noteAuthor = "User"

        engine.addAnnotation(noteAnnotation)
    }

    private func startShapeDrawing(at point: CGPoint, on pageIndex: Int) {
        // TODO: Implement interactive shape drawing
        guard let engine = annotationEngine else { return }

        // For now, create a default shape
        let defaultSize = CGSize(width: 100, height: 100)
        let frame = CGRect(origin: point, size: defaultSize)

        engine.addShapeAnnotation(tool: engine.currentTool, frame: frame, on: pageIndex)
    }

    // MARK: - Helper Methods
    private func interactionHandle(at point: CGPoint, for annotation: UnifiedAnnotation) -> InteractionHandle {
        guard let pdfView = pdfView,
              let page = pdfView.currentPage else { return .none }

        // Convert annotation frame to view coordinates
        let viewFrame = pdfView.convert(annotation.frame, from: page)

        // Define handle regions
        let handles: [(InteractionHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: viewFrame.minX, y: viewFrame.minY)),
            (.topRight, CGPoint(x: viewFrame.maxX, y: viewFrame.minY)),
            (.bottomLeft, CGPoint(x: viewFrame.minX, y: viewFrame.maxY)),
            (.bottomRight, CGPoint(x: viewFrame.maxX, y: viewFrame.maxY)),
            (.topCenter, CGPoint(x: viewFrame.midX, y: viewFrame.minY)),
            (.bottomCenter, CGPoint(x: viewFrame.midX, y: viewFrame.maxY)),
            (.leftCenter, CGPoint(x: viewFrame.minX, y: viewFrame.midY)),
            (.rightCenter, CGPoint(x: viewFrame.maxX, y: viewFrame.midY)),
            (.rotation, CGPoint(x: viewFrame.midX, y: viewFrame.minY - rotationHandleOffset))
        ]

        // Check if point is near any handle
        for (handle, handlePoint) in handles {
            let distance = hypot(point.x - handlePoint.x, point.y - handlePoint.y)
            if distance <= handleSize / 2 {
                return handle
            }
        }

        // Check if point is inside the annotation
        if viewFrame.contains(point) {
            return .move
        }

        return .none
    }

    private func resizedFrame(from originalFrame: CGRect, handle: InteractionHandle, translation: CGPoint) -> CGRect {
        var newFrame = originalFrame

        switch handle {
        case .topLeft:
            newFrame.origin.x += translation.x
            newFrame.origin.y += translation.y
            newFrame.size.width -= translation.x
            newFrame.size.height -= translation.y

        case .topRight:
            newFrame.origin.y += translation.y
            newFrame.size.width += translation.x
            newFrame.size.height -= translation.y

        case .bottomLeft:
            newFrame.origin.x += translation.x
            newFrame.size.width -= translation.x
            newFrame.size.height += translation.y

        case .bottomRight:
            newFrame.size.width += translation.x
            newFrame.size.height += translation.y

        case .topCenter:
            newFrame.origin.y += translation.y
            newFrame.size.height -= translation.y

        case .bottomCenter:
            newFrame.size.height += translation.y

        case .leftCenter:
            newFrame.origin.x += translation.x
            newFrame.size.width -= translation.x

        case .rightCenter:
            newFrame.size.width += translation.x

        default:
            break
        }

        // Apply size constraints
        newFrame.size = constrainSize(newFrame.size)

        // Ensure positive size
        if newFrame.size.width < 0 {
            newFrame.origin.x += newFrame.size.width
            newFrame.size.width = abs(newFrame.size.width)
        }
        if newFrame.size.height < 0 {
            newFrame.origin.y += newFrame.size.height
            newFrame.size.height = abs(newFrame.size.height)
        }

        return newFrame
    }

    private func constrainSize(_ size: CGSize) -> CGSize {
        return CGSize(
            width: min(max(size.width, minimumAnnotationSize.width), maximumAnnotationSize.width),
            height: min(max(size.height, minimumAnnotationSize.height), maximumAnnotationSize.height)
        )
    }

    private func shouldProvideBoundaryFeedback(for annotation: UnifiedAnnotation) -> Bool {
        guard let pdfView = pdfView,
              let page = pdfView.currentPage else { return false }

        let pageBounds = page.bounds(for: .mediaBox)

        // Check if annotation is near page edges
        let margin: CGFloat = 10
        return annotation.frame.minX < margin ||
               annotation.frame.minY < margin ||
               annotation.frame.maxX > pageBounds.width - margin ||
               annotation.frame.maxY > pageBounds.height - margin
    }
}

// MARK: - UIGestureRecognizerDelegate
extension AnnotationInteractionHandler: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation to work together
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
           (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
            return true
        }

        // Don't interfere with PDF view's built-in gestures when no annotation is selected
        if annotationEngine?.selectedAnnotation == nil {
            return false
        }

        return false
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pdfView = pdfView,
              let engine = annotationEngine else { return false }

        let location = gestureRecognizer.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return false }

        let pagePoint = pdfView.convert(location, to: page)
        let pageIndex = pdfView.document?.index(for: page) ?? 0

        // For drawing tools (pen/highlighter), always allow pan gesture
        if [.pen, .highlighter].contains(engine.currentTool) {
            // Only allow pan for drawing - block pinch/rotation during drawing
            return gestureRecognizer is UIPanGestureRecognizer ||
                   gestureRecognizer is UITapGestureRecognizer
        }

        // For shape/text/signature tools, allow tap to create
        if [.text, .signature, .note, .rectangle, .oval, .arrow, .line].contains(engine.currentTool) {
            return gestureRecognizer is UITapGestureRecognizer
        }

        // For selection tool, check if there's an annotation at the location
        if engine.currentTool == .selection {
            // Always allow tap for selection/deselection
            if gestureRecognizer is UITapGestureRecognizer {
                return true
            }

            // For pan/pinch/rotation, require touching an annotation or having one selected
            if let _ = engine.annotation(at: pagePoint, on: pageIndex) {
                return true
            }

            // Allow if we have a selected annotation (for moving/resizing)
            if let selected = engine.selectedAnnotation,
               selected.pageIndex == pageIndex {
                return true
            }

            // No annotation - don't begin (let PDF scroll/zoom)
            return false
        }

        return true
    }
}