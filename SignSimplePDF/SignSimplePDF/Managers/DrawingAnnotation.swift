import Foundation
import PDFKit
import UIKit

/// Custom annotation for free-hand drawing (pen tool)
///
/// Stores drawing paths in normalized coordinates (0,0 to 1,1)
/// relative to the annotation bounds for perfect scaling
final class DrawingAnnotation: EditablePDFAnnotation {

    /// Drawing paths in normalized coordinates (0-1 range)
    private let drawingPaths: [DrawingPath]

    /// Drawing color
    private let drawingColor: UIColor

    /// Line width for drawing
    private let lineWidth: CGFloat

    init(bounds: CGRect, paths: [DrawingPath], color: UIColor, lineWidth: CGFloat, annotationID: UUID = UUID()) {
        self.drawingPaths = paths
        self.drawingColor = color
        self.lineWidth = lineWidth

        super.init(bounds: bounds, annotationID: annotationID)

        self.shouldDisplay = true
        self.shouldPrint = true
    }

    required init?(coder: NSCoder) {
        // Decode drawing-specific properties
        if let colorData = coder.decodeObject(forKey: "drawingColor") as? Data,
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            self.drawingColor = color
        } else {
            self.drawingColor = .black
        }

        self.lineWidth = CGFloat(coder.decodeFloat(forKey: "lineWidth"))

        if let pathsData = coder.decodeObject(forKey: "drawingPaths") as? Data,
           let decodedPaths = try? JSONDecoder().decode([DrawingPath].self, from: pathsData) {
            self.drawingPaths = decodedPaths
        } else {
            self.drawingPaths = []
        }

        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)

        // Encode drawing-specific properties
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: drawingColor, requiringSecureCoding: true) {
            coder.encode(colorData, forKey: "drawingColor")
        }

        coder.encode(Float(lineWidth), forKey: "lineWidth")

        if let pathsData = try? JSONEncoder().encode(drawingPaths) {
            coder.encode(pathsData, forKey: "drawingPaths")
        }
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard !drawingPaths.isEmpty else { return }

        context.saveGState()

        // Move to annotation origin
        context.translateBy(x: bounds.minX, y: bounds.minY)

        // Set drawing properties
        context.setStrokeColor(drawingColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw each path
        for path in drawingPaths {
            guard path.points.count > 1 else { continue }

            // Convert normalized points (0-1) to annotation bounds
            let bezierPath = UIBezierPath()

            for (index, normalizedPoint) in path.points.enumerated() {
                // Convert from normalized (0-1) to actual bounds
                // Note: PDF uses bottom-left origin, but paths are drawn top-down
                let x = normalizedPoint.x * bounds.width
                let y = bounds.height - (normalizedPoint.y * bounds.height)
                let point = CGPoint(x: x, y: y)

                if index == 0 {
                    bezierPath.move(to: point)
                } else {
                    bezierPath.addLine(to: point)
                }
            }

            // Add path to context
            context.addPath(bezierPath.cgPath)
        }

        // Stroke all paths
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - Serialization Support

    override func toDictionary() -> [String: Any] {
        var dict = super.toDictionary()
        dict["type"] = "drawing"

        // Encode color as hex
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        drawingColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        dict["color"] = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        dict["alpha"] = a
        dict["lineWidth"] = lineWidth

        // Encode paths
        if let pathsData = try? JSONEncoder().encode(drawingPaths),
           let pathsString = String(data: pathsData, encoding: .utf8) {
            dict["paths"] = pathsString
        }

        return dict
    }

    override class func fromDictionary(_ dict: [String: Any]) -> DrawingAnnotation? {
        guard let idString = dict["annotationID"] as? String,
              let id = UUID(uuidString: idString),
              let boundsString = dict["bounds"] as? String,
              let colorString = dict["color"] as? String,
              let lineWidth = dict["lineWidth"] as? CGFloat,
              let pathsString = dict["paths"] as? String,
              let pathsData = pathsString.data(using: .utf8),
              let paths = try? JSONDecoder().decode([DrawingPath].self, from: pathsData) else {
            return nil
        }

        let bounds = NSCoder.cgRect(for: boundsString)

        // Parse color
        var color = UIColor.black
        if let hexColor = UIColor(hexString: colorString) {
            color = hexColor
            if let alpha = dict["alpha"] as? CGFloat {
                color = color.withAlphaComponent(alpha)
            }
        }

        let annotation = DrawingAnnotation(
            bounds: bounds,
            paths: paths,
            color: color,
            lineWidth: lineWidth,
            annotationID: id
        )

        if let isEditable = dict["isEditable"] as? Bool {
            annotation.isEditable = isEditable
        }

        return annotation
    }
}
