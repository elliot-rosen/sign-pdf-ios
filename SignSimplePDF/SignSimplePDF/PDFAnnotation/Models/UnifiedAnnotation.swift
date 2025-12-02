//
//  UnifiedAnnotation.swift
//  SignSimplePDF
//
//  Unified annotation model for the new Apple Preview-inspired PDF annotation system
//

import Foundation
import UIKit
import PDFKit
import PencilKit

// MARK: - Annotation Tool Types
public enum AnnotationTool: String, CaseIterable, Codable {
    // Drawing tools
    case selection
    case pen
    case highlighter
    case eraser

    // Shape tools
    case arrow
    case line
    case rectangle
    case oval
    case polygon

    // Content tools
    case text
    case signature
    case note
    case magnifier

    var icon: String {
        switch self {
        case .selection: return "arrow.up.left.and.arrow.down.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser.line.dashed"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .polygon: return "triangle"
        case .text: return "textformat"
        case .signature: return "signature"
        case .note: return "note.text"
        case .magnifier: return "magnifyingglass.circle"
        }
    }

    var defaultColor: UIColor {
        switch self {
        case .highlighter: return .systemYellow.withAlphaComponent(0.5)
        case .note: return .systemYellow
        default: return .label
        }
    }
}

// MARK: - Annotation Properties
public struct AnnotationProperties: Codable {
    // Common properties
    var strokeColor: UIColor = .label
    var fillColor: UIColor? = nil
    var strokeWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0

    // Text properties
    var fontSize: CGFloat = 14.0
    var fontName: String = "Helvetica"
    var textAlignment: NSTextAlignment = .left
    var text: String = ""

    // Shape properties
    var cornerRadius: CGFloat = 0
    var arrowHeadStyle: ArrowHeadStyle = .open
    var lineDashPattern: [CGFloat]? = nil

    // Drawing properties
    var drawingData: Data? = nil  // PencilKit drawing
    var paths: [BezierPath] = []  // Custom paths for shapes

    // Signature properties
    var signatureImage: Data? = nil

    // Note properties
    var noteContent: String = ""
    var noteAuthor: String = ""

    public enum ArrowHeadStyle: String, Codable {
        case none, open, closed, circle, square
    }

    // Codable support for UIColor
    enum CodingKeys: String, CodingKey {
        case strokeColorData, fillColorData, strokeWidth, opacity
        case fontSize, fontName, textAlignment, text
        case cornerRadius, arrowHeadStyle, lineDashPattern
        case drawingData, paths, signatureImage
        case noteContent, noteAuthor
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let colorData = try? container.decode(Data.self, forKey: .strokeColorData) {
            strokeColor = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) ?? .label
        }

        if let colorData = try? container.decode(Data.self, forKey: .fillColorData) {
            fillColor = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData)
        }

        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2.0
        opacity = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 14.0
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica"
        textAlignment = NSTextAlignment(rawValue: try container.decodeIfPresent(Int.self, forKey: .textAlignment) ?? 0) ?? .left
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        arrowHeadStyle = try container.decodeIfPresent(ArrowHeadStyle.self, forKey: .arrowHeadStyle) ?? .open
        lineDashPattern = try container.decodeIfPresent([CGFloat].self, forKey: .lineDashPattern)
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        paths = try container.decodeIfPresent([BezierPath].self, forKey: .paths) ?? []
        signatureImage = try container.decodeIfPresent(Data.self, forKey: .signatureImage)
        noteContent = try container.decodeIfPresent(String.self, forKey: .noteContent) ?? ""
        noteAuthor = try container.decodeIfPresent(String.self, forKey: .noteAuthor) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let strokeColorData = try NSKeyedArchiver.archivedData(withRootObject: strokeColor, requiringSecureCoding: true)
        try container.encode(strokeColorData, forKey: .strokeColorData)

        if let fillColor = fillColor {
            let fillColorData = try NSKeyedArchiver.archivedData(withRootObject: fillColor, requiringSecureCoding: true)
            try container.encode(fillColorData, forKey: .fillColorData)
        }

        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(textAlignment.rawValue, forKey: .textAlignment)
        try container.encode(text, forKey: .text)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(arrowHeadStyle, forKey: .arrowHeadStyle)
        try container.encodeIfPresent(lineDashPattern, forKey: .lineDashPattern)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encode(paths, forKey: .paths)
        try container.encodeIfPresent(signatureImage, forKey: .signatureImage)
        try container.encode(noteContent, forKey: .noteContent)
        try container.encode(noteAuthor, forKey: .noteAuthor)
    }
}

// MARK: - Bezier Path for Shapes
public struct BezierPath: Codable {
    var points: [CGPoint]
    var type: PathType

    enum PathType: String, Codable {
        case moveTo, lineTo, curveTo, closePath
    }
}

// MARK: - Unified Annotation Model
public class UnifiedAnnotation: NSObject, Identifiable, ObservableObject {
    public var id = UUID()

    @Published public var tool: AnnotationTool
    @Published public var frame: CGRect  // In PDF coordinates
    @Published public var properties: AnnotationProperties
    @Published public var pageIndex: Int

    // Interaction state
    @Published public var isSelected: Bool = false
    @Published public var isEditing: Bool = false
    @Published public var isDragging: Bool = false

    // Visual state
    @Published public var rotation: CGFloat = 0  // In degrees
    @Published public var zIndex: Int = 0

    // Metadata
    public let createdAt: Date
    public var modifiedAt: Date
    public var author: String?

    // Performance optimization
    private var cachedPath: UIBezierPath?
    private var cachedImage: UIImage?

    public init(
        tool: AnnotationTool,
        frame: CGRect,
        pageIndex: Int,
        properties: AnnotationProperties = AnnotationProperties()
    ) {
        self.tool = tool
        self.frame = frame
        self.pageIndex = pageIndex
        self.properties = properties
        self.createdAt = Date()
        self.modifiedAt = Date()
        super.init()
    }

    // MARK: - Hit Testing
    public func contains(point: CGPoint) -> Bool {
        // Account for rotation
        let transform = CGAffineTransform(rotationAngle: rotation * .pi / 180)
        let rotatedFrame = frame.applying(transform)

        // Add some padding for easier selection
        let hitTestFrame = rotatedFrame.insetBy(dx: -8, dy: -8)
        return hitTestFrame.contains(point)
    }

    // MARK: - Rendering
    public func draw(in context: CGContext, scale: CGFloat = 1.0) {
        context.saveGState()

        // Apply transformations
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: rotation * .pi / 180)
        context.translateBy(x: -frame.width / 2, y: -frame.height / 2)

        // Set opacity
        context.setAlpha(properties.opacity)

        // Draw based on tool type
        switch tool {
        case .pen, .highlighter:
            drawPaths(in: context)
        case .arrow, .line:
            drawLine(in: context)
        case .rectangle:
            drawRectangle(in: context)
        case .oval:
            drawOval(in: context)
        case .text:
            drawText(in: context)
        case .signature:
            drawSignature(in: context)
        case .note:
            drawNote(in: context)
        case .magnifier:
            drawMagnifier(in: context)
        default:
            break
        }

        // Draw selection handles if selected
        if isSelected {
            drawSelectionHandles(in: context)
        }

        context.restoreGState()
    }

    private func drawPaths(in context: CGContext) {
        guard !properties.paths.isEmpty else { return }

        context.setStrokeColor(properties.strokeColor.cgColor)
        context.setLineWidth(properties.strokeWidth)

        if tool == .highlighter {
            context.setBlendMode(.multiply)
        }

        let path = UIBezierPath()
        for bezierPath in properties.paths {
            if bezierPath.points.isEmpty { continue }

            switch bezierPath.type {
            case .moveTo:
                path.move(to: bezierPath.points[0])
            case .lineTo:
                path.addLine(to: bezierPath.points[0])
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

        path.stroke()
    }

    private func drawLine(in context: CGContext) {
        context.setStrokeColor(properties.strokeColor.cgColor)
        context.setLineWidth(properties.strokeWidth)

        if let pattern = properties.lineDashPattern {
            context.setLineDash(phase: 0, lengths: pattern)
        }

        context.move(to: CGPoint(x: 0, y: frame.height / 2))
        context.addLine(to: CGPoint(x: frame.width, y: frame.height / 2))

        // Draw arrow head if needed
        if tool == .arrow {
            drawArrowHead(in: context, at: CGPoint(x: frame.width, y: frame.height / 2))
        }

        context.strokePath()
    }

    private func drawArrowHead(in context: CGContext, at point: CGPoint) {
        let arrowSize: CGFloat = 12

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)

        switch properties.arrowHeadStyle {
        case .open, .closed:
            context.move(to: CGPoint(x: -arrowSize, y: -arrowSize / 2))
            context.addLine(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -arrowSize, y: arrowSize / 2))

            if properties.arrowHeadStyle == .closed {
                context.closePath()
                context.fillPath()
            } else {
                context.strokePath()
            }

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

    private func drawRectangle(in context: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        if properties.cornerRadius > 0 {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: properties.cornerRadius)
            context.addPath(path.cgPath)
        } else {
            context.addRect(rect)
        }

        if let fillColor = properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillPath()
        }

        context.setStrokeColor(properties.strokeColor.cgColor)
        context.setLineWidth(properties.strokeWidth)
        context.strokePath()
    }

    private func drawOval(in context: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        if let fillColor = properties.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: rect)
        }

        context.setStrokeColor(properties.strokeColor.cgColor)
        context.setLineWidth(properties.strokeWidth)
        context.strokeEllipse(in: rect)
    }

    private func drawText(in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: properties.fontName, size: properties.fontSize) ?? UIFont.systemFont(ofSize: properties.fontSize),
            .foregroundColor: properties.strokeColor
        ]

        let text = properties.text as NSString
        let textRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        UIGraphicsPushContext(context)
        text.draw(in: textRect, withAttributes: attributes)
        UIGraphicsPopContext()
    }

    private func drawSignature(in context: CGContext) {
        guard let imageData = properties.signatureImage,
              let image = UIImage(data: imageData) else { return }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        UIGraphicsPopContext()
    }

    private func drawNote(in context: CGContext) {
        // Draw note icon
        let iconSize: CGFloat = min(frame.width, frame.height, 24)
        let iconRect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)

        // Yellow background
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fillEllipse(in: iconRect)

        // Note icon
        let noteImage = UIImage(systemName: "note.text")?.withTintColor(.white)
        UIGraphicsPushContext(context)
        noteImage?.draw(in: iconRect.insetBy(dx: 4, dy: 4))
        UIGraphicsPopContext()
    }

    private func drawMagnifier(in context: CGContext) {
        // Draw magnifier circle
        let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        context.setStrokeColor(properties.strokeColor.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)

        // TODO: Implement actual magnification effect
    }

    private func drawSelectionHandles(in context: CGContext) {
        let handleSize: CGFloat = 8
        let handleColor = UIColor.systemBlue

        // Corner handles
        let handles = [
            CGPoint(x: 0, y: 0),  // Top-left
            CGPoint(x: frame.width, y: 0),  // Top-right
            CGPoint(x: 0, y: frame.height),  // Bottom-left
            CGPoint(x: frame.width, y: frame.height),  // Bottom-right
            CGPoint(x: frame.width / 2, y: 0),  // Top-center (rotation handle)
        ]

        context.setFillColor(handleColor.cgColor)

        for (index, handle) in handles.enumerated() {
            let handleRect = CGRect(
                x: handle.x - handleSize / 2,
                y: handle.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )

            if index == 4 {
                // Rotation handle is circular
                context.fillEllipse(in: handleRect)
            } else {
                // Resize handles are square
                context.fill(handleRect)
            }
        }

        // Selection border
        context.setStrokeColor(handleColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 2])
        context.stroke(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
    }

    // MARK: - Copy/Paste Support
    public func copy() -> UnifiedAnnotation {
        let copy = UnifiedAnnotation(
            tool: tool,
            frame: frame,
            pageIndex: pageIndex,
            properties: properties
        )
        copy.rotation = rotation
        copy.zIndex = zIndex
        copy.author = author
        return copy
    }

    // MARK: - Undo/Redo Support
    public struct Snapshot {
        let frame: CGRect
        let properties: AnnotationProperties
        let rotation: CGFloat
        let zIndex: Int
    }

    public func createSnapshot() -> Snapshot {
        return Snapshot(
            frame: frame,
            properties: properties,
            rotation: rotation,
            zIndex: zIndex
        )
    }

    public func restore(from snapshot: Snapshot) {
        frame = snapshot.frame
        properties = snapshot.properties
        rotation = snapshot.rotation
        zIndex = snapshot.zIndex
        modifiedAt = Date()
    }
}

// MARK: - Annotation Collection Extensions
extension Array where Element == UnifiedAnnotation {
    public func sortedByZIndex() -> [UnifiedAnnotation] {
        return sorted { $0.zIndex < $1.zIndex }
    }

    public func annotations(on page: Int) -> [UnifiedAnnotation] {
        return filter { $0.pageIndex == page }
    }

    public func annotation(at point: CGPoint, on page: Int) -> UnifiedAnnotation? {
        return annotations(on: page)
            .sortedByZIndex()
            .reversed()
            .first { $0.contains(point: point) }
    }
}