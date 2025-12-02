//
//  AnnotationRenderer.swift
//  SignSimplePDF
//
//  High-performance annotation rendering with Metal support
//

import UIKit
import PDFKit
import CoreGraphics
import Metal
import MetalKit
import PencilKit

// MARK: - Annotation Renderer
public class AnnotationRenderer: NSObject {
    // MARK: - Properties
    private weak var pdfView: PDFView?
    private let renderQueue = DispatchQueue(label: "com.signsimplepdf.annotation.render", qos: .userInitiated)

    // Metal rendering (for complex drawings)
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var metalLayer: CAMetalLayer?

    // Caching
    private var renderedAnnotationCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        return cache
    }()

    // Performance tracking
    private var lastRenderTime: CFTimeInterval = 0
    private var frameRate: Double = 60.0

    // MARK: - Initialization
    public override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        if let device = device {
            commandQueue = device.makeCommandQueue()
        }
    }

    // MARK: - Configuration
    public func configure(with pdfView: PDFView) {
        self.pdfView = pdfView
    }

    // MARK: - Main Render Method
    public func renderAnnotations(
        _ annotations: [UnifiedAnnotation],
        in context: CGContext,
        for page: PDFPage,
        with transform: CGAffineTransform
    ) {
        let startTime = CACurrentMediaTime()

        // Apply page transform
        context.saveGState()
        context.concatenate(transform)

        // Sort annotations by z-index
        let sortedAnnotations = annotations.sortedByZIndex()

        // Render each annotation
        for annotation in sortedAnnotations {
            autoreleasepool {
                renderAnnotation(annotation, in: context, for: page)
            }
        }

        context.restoreGState()

        // Update performance metrics
        let renderTime = CACurrentMediaTime() - startTime
        lastRenderTime = renderTime
        frameRate = min(60, 1.0 / renderTime)
    }

    // MARK: - Individual Annotation Rendering
    private func renderAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext, for page: PDFPage) {
        // Check cache first
        let cacheKey = "\(annotation.id)-\(annotation.modifiedAt.timeIntervalSince1970)" as NSString
        if let cachedImage = renderedAnnotationCache.object(forKey: cacheKey) {
            renderCachedImage(cachedImage, for: annotation, in: context)
            return
        }

        // Determine rendering method based on complexity
        if shouldUseMetalRendering(for: annotation) {
            renderWithMetal(annotation, in: context)
        } else {
            renderWithCoreGraphics(annotation, in: context)
        }

        // Cache the result if appropriate
        if shouldCache(annotation) {
            cacheRenderedAnnotation(annotation, cacheKey: cacheKey)
        }
    }

    // MARK: - Core Graphics Rendering
    private func renderWithCoreGraphics(_ annotation: UnifiedAnnotation, in context: CGContext) {
        context.saveGState()

        // Set up clipping rect for performance
        let clipRect = annotation.frame.insetBy(dx: -10, dy: -10)
        context.clip(to: clipRect)

        // Move to the annotation's origin in PDF coordinates
        // The page transform (including Y-flip) has already been applied
        context.translateBy(x: annotation.frame.origin.x, y: annotation.frame.origin.y)

        // Apply rotation around the center if needed
        if annotation.rotation != 0 {
            context.translateBy(x: annotation.frame.width / 2, y: annotation.frame.height / 2)
            context.rotate(by: annotation.rotation * .pi / 180)
            context.translateBy(x: -annotation.frame.width / 2, y: -annotation.frame.height / 2)
        }

        // Set rendering quality based on annotation type
        setRenderingQuality(for: annotation.tool, in: context)

        // Set alpha
        context.setAlpha(annotation.properties.opacity)

        // Render based on tool type
        switch annotation.tool {
        case .pen:
            renderPenAnnotation(annotation, in: context)
        case .highlighter:
            renderHighlighterAnnotation(annotation, in: context)
        case .text:
            renderTextAnnotation(annotation, in: context)
        case .signature:
            renderSignatureAnnotation(annotation, in: context)
        case .arrow, .line:
            renderLineAnnotation(annotation, in: context)
        case .rectangle:
            renderRectangleAnnotation(annotation, in: context)
        case .oval:
            renderOvalAnnotation(annotation, in: context)
        case .note:
            renderNoteAnnotation(annotation, in: context)
        case .magnifier:
            renderMagnifierAnnotation(annotation, in: context)
        default:
            break
        }

        // Render selection UI if needed
        if annotation.isSelected {
            renderSelectionUI(for: annotation, in: context)
        }

        context.restoreGState()
    }

    // MARK: - Metal Rendering (for complex paths)
    private func renderWithMetal(_ annotation: UnifiedAnnotation, in context: CGContext) {
        // TODO: Implement Metal rendering for complex drawings
        // For now, fall back to Core Graphics
        renderWithCoreGraphics(annotation, in: context)
    }

    // MARK: - Specific Annotation Type Rendering
    private func renderPenAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        guard !annotation.properties.paths.isEmpty else { return }

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Enable smoothing
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let path = UIBezierPath()

        for bezierPath in annotation.properties.paths {
            guard !bezierPath.points.isEmpty else { continue }

            switch bezierPath.type {
            case .moveTo:
                path.move(to: bezierPath.points[0])
            case .lineTo:
                if !path.isEmpty {
                    // Apply smoothing for better appearance
                    let smoothedPoint = smoothPoint(
                        bezierPath.points[0],
                        previousPoint: path.currentPoint
                    )
                    path.addQuadCurve(
                        to: bezierPath.points[0],
                        controlPoint: smoothedPoint
                    )
                } else {
                    path.addLine(to: bezierPath.points[0])
                }
            case .curveTo:
                if bezierPath.points.count >= 3 {
                    path.addCurve(
                        to: bezierPath.points[2],
                        controlPoint1: bezierPath.points[0],
                        controlPoint2: bezierPath.points[1]
                    )
                }
            case .closePath:
                path.close()
            }
        }

        context.addPath(path.cgPath)
        context.strokePath()
    }

    private func renderHighlighterAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        context.saveGState()

        // Set blend mode for highlighter effect
        context.setBlendMode(.multiply)
        context.setAlpha(0.5)

        if annotation.properties.paths.isEmpty {
            // Simple rectangle highlight
            context.setFillColor(annotation.properties.strokeColor.cgColor)
            context.fill(CGRect(origin: .zero, size: annotation.frame.size))
        } else {
            // Path-based highlight
            renderPenAnnotation(annotation, in: context)
        }

        context.restoreGState()
    }

    private func renderTextAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let font = UIFont(name: annotation.properties.fontName, size: annotation.properties.fontSize)
            ?? UIFont.systemFont(ofSize: annotation.properties.fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = annotation.properties.textAlignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.properties.strokeColor,
            .paragraphStyle: paragraphStyle
        ]

        let text = annotation.properties.text as NSString
        let textRect = CGRect(origin: .zero, size: annotation.frame.size)

        UIGraphicsPushContext(context)
        text.draw(in: textRect, withAttributes: attributes)
        UIGraphicsPopContext()
    }

    private func renderSignatureAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        guard let imageData = annotation.properties.signatureImage,
              let image = UIImage(data: imageData) else { return }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: annotation.frame.size))
        UIGraphicsPopContext()
    }

    private func renderLineAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)

        if let pattern = annotation.properties.lineDashPattern {
            context.setLineDash(phase: 0, lengths: pattern)
        }

        let startPoint = CGPoint(x: 0, y: annotation.frame.height / 2)
        let endPoint = CGPoint(x: annotation.frame.width, y: annotation.frame.height / 2)

        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()

        // Draw arrow head if needed
        if annotation.tool == .arrow {
            renderArrowHead(at: endPoint, angle: 0, style: annotation.properties.arrowHeadStyle, in: context)
        }
    }

    private func renderRectangleAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        if annotation.properties.cornerRadius > 0 {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: annotation.properties.cornerRadius)
            context.addPath(path.cgPath)
        } else {
            context.addRect(rect)
        }

        // Fill if needed
        if let fillColor = annotation.properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillPath()
            context.addRect(rect)  // Re-add for stroke
        }

        // Stroke
        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)
        context.strokePath()
    }

    private func renderOvalAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        // Fill if needed
        if let fillColor = annotation.properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: rect)
        }

        // Stroke
        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(annotation.properties.strokeWidth)
        context.strokeEllipse(in: rect)
    }

    private func renderNoteAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        let iconSize = min(annotation.frame.width, annotation.frame.height, 24)
        let iconRect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)

        // Yellow background with shadow
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.2).cgColor)
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fillEllipse(in: iconRect)

        // Draw icon
        context.setShadow(offset: .zero, blur: 0)
        if let noteIcon = UIImage(systemName: "note.text")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            UIGraphicsPushContext(context)
            noteIcon.draw(in: iconRect.insetBy(dx: 4, dy: 4))
            UIGraphicsPopContext()
        }
    }

    private func renderMagnifierAnnotation(_ annotation: UnifiedAnnotation, in context: CGContext) {
        // TODO: Implement actual magnification rendering
        // For now, just draw the magnifier outline
        let rect = CGRect(origin: .zero, size: annotation.frame.size)

        context.setStrokeColor(annotation.properties.strokeColor.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)

        // Draw handle
        let handleStart = CGPoint(x: rect.maxX - 5, y: rect.maxY - 5)
        let handleEnd = CGPoint(x: rect.maxX + 20, y: rect.maxY + 20)
        context.move(to: handleStart)
        context.addLine(to: handleEnd)
        context.strokePath()
    }

    // MARK: - Selection UI Rendering
    private func renderSelectionUI(for annotation: UnifiedAnnotation, in context: CGContext) {
        context.saveGState()

        let selectionColor = UIColor.systemBlue

        // Draw selection border
        context.setStrokeColor(selectionColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 2])
        context.stroke(CGRect(origin: .zero, size: annotation.frame.size))

        // Draw resize handles
        let handleSize: CGFloat = 8
        let handles = [
            CGPoint(x: 0, y: 0),  // Top-left
            CGPoint(x: annotation.frame.width, y: 0),  // Top-right
            CGPoint(x: 0, y: annotation.frame.height),  // Bottom-left
            CGPoint(x: annotation.frame.width, y: annotation.frame.height),  // Bottom-right
        ]

        context.setFillColor(UIColor.white.cgColor)
        context.setStrokeColor(selectionColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [])

        for handle in handles {
            let handleRect = CGRect(
                x: handle.x - handleSize / 2,
                y: handle.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fillEllipse(in: handleRect)
            context.strokeEllipse(in: handleRect)
        }

        // Draw rotation handle at top
        let rotationHandle = CGPoint(x: annotation.frame.width / 2, y: -20)
        let rotationRect = CGRect(
            x: rotationHandle.x - handleSize / 2,
            y: rotationHandle.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        context.setFillColor(selectionColor.cgColor)
        context.fillEllipse(in: rotationRect)

        context.restoreGState()
    }

    // MARK: - Helper Methods
    private func renderArrowHead(at point: CGPoint, angle: CGFloat, style: AnnotationProperties.ArrowHeadStyle, in context: CGContext) {
        let arrowSize: CGFloat = 12

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: angle)

        switch style {
        case .open:
            context.move(to: CGPoint(x: -arrowSize, y: -arrowSize / 2))
            context.addLine(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -arrowSize, y: arrowSize / 2))
            context.strokePath()

        case .closed:
            context.move(to: CGPoint(x: -arrowSize, y: -arrowSize / 2))
            context.addLine(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -arrowSize, y: arrowSize / 2))
            context.closePath()
            context.fillPath()

        case .circle:
            context.addEllipse(in: CGRect(x: -arrowSize / 2, y: -arrowSize / 2, width: arrowSize, height: arrowSize))
            context.strokePath()

        case .square:
            context.addRect(CGRect(x: -arrowSize / 2, y: -arrowSize / 2, width: arrowSize, height: arrowSize))
            context.strokePath()

        case .none:
            break
        }

        context.restoreGState()
    }

    private func smoothPoint(_ point: CGPoint, previousPoint: CGPoint) -> CGPoint {
        let smoothingFactor: CGFloat = 0.5
        return CGPoint(
            x: previousPoint.x + (point.x - previousPoint.x) * smoothingFactor,
            y: previousPoint.y + (point.y - previousPoint.y) * smoothingFactor
        )
    }

    private func setRenderingQuality(for tool: AnnotationTool, in context: CGContext) {
        switch tool {
        case .pen, .signature:
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            context.interpolationQuality = .high

        case .text:
            context.setShouldSmoothFonts(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setShouldSubpixelQuantizeFonts(true)

        case .rectangle, .oval, .arrow, .line:
            context.setShouldAntialias(true)
            context.interpolationQuality = .medium

        default:
            context.interpolationQuality = .default
        }
    }

    private func renderCachedImage(_ image: UIImage, for annotation: UnifiedAnnotation, in context: CGContext) {
        UIGraphicsPushContext(context)
        image.draw(in: annotation.frame)
        UIGraphicsPopContext()
    }

    private func shouldUseMetalRendering(for annotation: UnifiedAnnotation) -> Bool {
        // Use Metal for complex drawings with many paths
        if annotation.tool == .pen || annotation.tool == .highlighter {
            return annotation.properties.paths.count > 100
        }
        return false
    }

    private func shouldCache(_ annotation: UnifiedAnnotation) -> Bool {
        // Cache complex annotations
        switch annotation.tool {
        case .pen, .highlighter:
            return annotation.properties.paths.count > 20
        case .signature:
            return true
        default:
            return false
        }
    }

    private func cacheRenderedAnnotation(_ annotation: UnifiedAnnotation, cacheKey: NSString) {
        renderQueue.async { [weak self] in
            // Guard against zero-size frames
            guard annotation.frame.width > 0, annotation.frame.height > 0 else { return }

            let renderer = UIGraphicsImageRenderer(size: annotation.frame.size)
            let image = renderer.image { rendererContext in
                annotation.draw(in: rendererContext.cgContext)
            }

            self?.renderedAnnotationCache.setObject(image, forKey: cacheKey, cost: Int(annotation.frame.width * annotation.frame.height * 4))
        }
    }

    // MARK: - Performance Monitoring
    public var currentFrameRate: Double {
        return frameRate
    }

    public var lastRenderDuration: CFTimeInterval {
        return lastRenderTime
    }

    public func clearCache() {
        renderedAnnotationCache.removeAllObjects()
    }
}