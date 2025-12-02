//
//  ShapeRecognition.swift
//  SignSimplePDF
//
//  Smart shape recognition for converting rough drawings to perfect shapes
//

import UIKit
import Vision
import CoreML

// MARK: - Recognized Shape Types
public enum RecognizedShape {
    case line(start: CGPoint, end: CGPoint)
    case rectangle(frame: CGRect)
    case circle(center: CGPoint, radius: CGFloat)
    case ellipse(frame: CGRect)
    case triangle(points: [CGPoint])
    case arrow(start: CGPoint, end: CGPoint)
    case star(center: CGPoint, radius: CGFloat)
    case polygon(points: [CGPoint])
    case none
}

// MARK: - Shape Recognition Engine
public class ShapeRecognitionEngine {
    // MARK: - Properties
    private let confidenceThreshold: CGFloat = 0.85
    private let angleThreshold: CGFloat = 15.0  // degrees
    private let distanceThreshold: CGFloat = 20.0  // points

    // Vision request for ML-based recognition (optional)
    private var visionRequest: VNCoreMLRequest?

    // MARK: - Initialization
    public init() {
        setupVisionRequest()
    }

    private func setupVisionRequest() {
        // TODO: Add CoreML model for advanced shape recognition if available
        // For now, we'll use algorithmic recognition
    }

    // MARK: - Public Methods
    public func recognizeShape(from points: [CGPoint]) -> RecognizedShape {
        guard points.count > 2 else { return .none }

        // Try different shape recognizers in order of complexity
        if let line = recognizeLine(from: points) {
            return line
        }

        if let rectangle = recognizeRectangle(from: points) {
            return rectangle
        }

        if let circle = recognizeCircle(from: points) {
            return circle
        }

        if let ellipse = recognizeEllipse(from: points) {
            return ellipse
        }

        if let triangle = recognizeTriangle(from: points) {
            return triangle
        }

        if let arrow = recognizeArrow(from: points) {
            return arrow
        }

        if let star = recognizeStar(from: points) {
            return star
        }

        if let polygon = recognizePolygon(from: points) {
            return polygon
        }

        return .none
    }

    // MARK: - Line Recognition
    private func recognizeLine(from points: [CGPoint]) -> RecognizedShape? {
        guard points.count >= 2 else { return nil }

        let start = points.first!
        let end = points.last!

        // Calculate total distance along path
        var totalDistance: CGFloat = 0
        for i in 1..<points.count {
            totalDistance += distance(from: points[i-1], to: points[i])
        }

        // Calculate straight line distance
        let straightDistance = distance(from: start, to: end)

        // Check if path is relatively straight
        let straightness = straightDistance / totalDistance
        if straightness > 0.95 {
            // Check for arrow pattern (hook at the end)
            if hasArrowHead(points) {
                return .arrow(start: start, end: end)
            }
            return .line(start: start, end: end)
        }

        return nil
    }

    // MARK: - Rectangle Recognition
    private func recognizeRectangle(from points: [CGPoint]) -> RecognizedShape? {
        // Find corners using Douglas-Peucker algorithm
        let simplifiedPoints = douglasPeucker(points, epsilon: 10.0)

        // Check if we have 4 or 5 points (closed rectangle)
        if simplifiedPoints.count == 4 || simplifiedPoints.count == 5 {
            // Check if first and last points are close (closed shape)
            if simplifiedPoints.count == 5 {
                let dist = distance(from: simplifiedPoints.first!, to: simplifiedPoints.last!)
                if dist > distanceThreshold {
                    return nil
                }
            }

            // Check angles between segments
            let corners = Array(simplifiedPoints.prefix(4))
            if areAnglesRectangular(corners) {
                let bounds = boundingBox(of: corners)
                return .rectangle(frame: bounds)
            }
        }

        return nil
    }

    // MARK: - Circle Recognition
    private func recognizeCircle(from points: [CGPoint]) -> RecognizedShape? {
        guard points.count > 8 else { return nil }

        // Calculate centroid
        let center = centroid(of: points)

        // Calculate average radius
        var totalRadius: CGFloat = 0
        for point in points {
            totalRadius += distance(from: center, to: point)
        }
        let averageRadius = totalRadius / CGFloat(points.count)

        // Check variance in radius
        var variance: CGFloat = 0
        for point in points {
            let radius = distance(from: center, to: point)
            let diff = radius - averageRadius
            variance += diff * diff
        }
        variance /= CGFloat(points.count)
        let standardDeviation = sqrt(variance)

        // Check if variance is low enough for a circle
        let circleConfidence = 1.0 - (standardDeviation / averageRadius)
        if circleConfidence > confidenceThreshold {
            return .circle(center: center, radius: averageRadius)
        }

        return nil
    }

    // MARK: - Ellipse Recognition
    private func recognizeEllipse(from points: [CGPoint]) -> RecognizedShape? {
        guard points.count > 8 else { return nil }

        // If not a circle, try ellipse fitting
        let bounds = boundingBox(of: points)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2

        // Check if points fit ellipse equation
        var totalError: CGFloat = 0
        for point in points {
            let normalizedX = (point.x - center.x) / radiusX
            let normalizedY = (point.y - center.y) / radiusY
            let ellipseValue = normalizedX * normalizedX + normalizedY * normalizedY
            totalError += abs(ellipseValue - 1.0)
        }
        let averageError = totalError / CGFloat(points.count)

        if averageError < 0.2 {
            return .ellipse(frame: bounds)
        }

        return nil
    }

    // MARK: - Triangle Recognition
    private func recognizeTriangle(from points: [CGPoint]) -> RecognizedShape? {
        let simplifiedPoints = douglasPeucker(points, epsilon: 15.0)

        if simplifiedPoints.count == 3 || simplifiedPoints.count == 4 {
            // Check if first and last points are close (closed shape)
            if simplifiedPoints.count == 4 {
                let dist = distance(from: simplifiedPoints.first!, to: simplifiedPoints.last!)
                if dist > distanceThreshold {
                    return nil
                }
            }

            let corners = Array(simplifiedPoints.prefix(3))
            return .triangle(points: corners)
        }

        return nil
    }

    // MARK: - Arrow Recognition
    private func recognizeArrow(from points: [CGPoint]) -> RecognizedShape? {
        // Check if we have a line with an arrowhead
        if let line = recognizeLine(from: points) {
            if case .line(let start, let end) = line {
                if hasArrowHead(points) {
                    return .arrow(start: start, end: end)
                }
            }
        }
        return nil
    }

    // MARK: - Star Recognition
    private func recognizeStar(from points: [CGPoint]) -> RecognizedShape? {
        let simplifiedPoints = douglasPeucker(points, epsilon: 10.0)

        // Stars typically have 10 or 11 points (5 outer, 5 inner, possibly closed)
        if simplifiedPoints.count >= 8 && simplifiedPoints.count <= 12 {
            // Check for alternating distances from center
            let center = centroid(of: simplifiedPoints)
            var distances: [CGFloat] = []

            for point in simplifiedPoints {
                distances.append(distance(from: center, to: point))
            }

            // Check if distances alternate between two values
            if hasAlternatingPattern(distances) {
                let maxRadius = distances.max() ?? 0
                return .star(center: center, radius: maxRadius)
            }
        }

        return nil
    }

    // MARK: - Polygon Recognition
    private func recognizePolygon(from points: [CGPoint]) -> RecognizedShape? {
        let simplifiedPoints = douglasPeucker(points, epsilon: 12.0)

        if simplifiedPoints.count >= 3 && simplifiedPoints.count <= 12 {
            // Check if closed
            if let first = simplifiedPoints.first,
               let last = simplifiedPoints.last {
                let dist = distance(from: first, to: last)
                if dist < distanceThreshold {
                    return .polygon(points: Array(simplifiedPoints.dropLast()))
                }
            }
            return .polygon(points: simplifiedPoints)
        }

        return nil
    }

    // MARK: - Helper Methods
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    private func centroid(of points: [CGPoint]) -> CGPoint {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for point in points {
            sumX += point.x
            sumY += point.y
        }

        let count = CGFloat(points.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func areAnglesRectangular(_ corners: [CGPoint]) -> Bool {
        guard corners.count == 4 else { return false }

        for i in 0..<4 {
            let p1 = corners[i]
            let p2 = corners[(i + 1) % 4]
            let p3 = corners[(i + 2) % 4]

            let angle = angleBetween(p1: p1, p2: p2, p3: p3)
            let angleDegrees = angle * 180 / .pi

            // Check if angle is approximately 90 degrees
            if abs(angleDegrees - 90) > angleThreshold {
                return false
            }
        }

        return true
    }

    private func angleBetween(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)

        let dotProduct = v1.x * v2.x + v1.y * v2.y
        let magnitude1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let magnitude2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        guard magnitude1 > 0 && magnitude2 > 0 else { return 0 }

        let cosineAngle = dotProduct / (magnitude1 * magnitude2)
        return acos(max(-1, min(1, cosineAngle)))
    }

    private func hasArrowHead(_ points: [CGPoint]) -> Bool {
        guard points.count > 5 else { return false }

        // Check last few points for arrow head pattern
        let tail = Array(points.suffix(5))
        let simplified = douglasPeucker(tail, epsilon: 5.0)

        // Arrow head typically forms a V shape at the end
        return simplified.count >= 3
    }

    private func hasAlternatingPattern(_ values: [CGFloat]) -> Bool {
        guard values.count >= 4 else { return false }

        var differences: [CGFloat] = []
        for i in 1..<values.count {
            differences.append(abs(values[i] - values[i-1]))
        }

        // Check if differences alternate between large and small values
        let avgDiff = differences.reduce(0, +) / CGFloat(differences.count)
        var alternates = true

        for i in 0..<differences.count-1 {
            let diff1 = differences[i]
            let diff2 = differences[i+1]

            // One should be above average, one below
            if !((diff1 > avgDiff && diff2 < avgDiff) || (diff1 < avgDiff && diff2 > avgDiff)) {
                alternates = false
                break
            }
        }

        return alternates
    }

    // MARK: - Douglas-Peucker Algorithm
    private func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        // Find point with maximum distance from line between first and last
        var maxDistance: CGFloat = 0
        var maxIndex = 0

        let first = points.first!
        let last = points.last!

        for i in 1..<points.count-1 {
            let distance = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        // If max distance is greater than epsilon, recursively simplify
        if maxDistance > epsilon {
            let leftPoints = douglasPeucker(Array(points[0...maxIndex]), epsilon: epsilon)
            let rightPoints = douglasPeucker(Array(points[maxIndex..<points.count]), epsilon: epsilon)

            return Array(leftPoints.dropLast()) + rightPoints
        } else {
            return [first, last]
        }
    }

    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y

        let magnitude = sqrt(dx * dx + dy * dy)
        guard magnitude > 0 else { return distance(from: point, to: lineStart) }

        let u = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (magnitude * magnitude)
        let clamped = max(0, min(1, u))

        let closestPoint = CGPoint(
            x: lineStart.x + clamped * dx,
            y: lineStart.y + clamped * dy
        )

        return distance(from: point, to: closestPoint)
    }
}

// MARK: - Shape Conversion
public extension RecognizedShape {
    func toAnnotation(on pageIndex: Int) -> UnifiedAnnotation? {
        switch self {
        case .line(let start, let end):
            let frame = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            return UnifiedAnnotation(tool: .line, frame: frame, pageIndex: pageIndex)

        case .rectangle(let frame):
            return UnifiedAnnotation(tool: .rectangle, frame: frame, pageIndex: pageIndex)

        case .circle(let center, let radius):
            let frame = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            return UnifiedAnnotation(tool: .oval, frame: frame, pageIndex: pageIndex)

        case .ellipse(let frame):
            return UnifiedAnnotation(tool: .oval, frame: frame, pageIndex: pageIndex)

        case .arrow(let start, let end):
            let frame = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let annotation = UnifiedAnnotation(tool: .arrow, frame: frame, pageIndex: pageIndex)
            annotation.properties.arrowHeadStyle = .open
            return annotation

        case .triangle(let points), .polygon(let points):
            let bounds = boundingBox(of: points)
            let annotation = UnifiedAnnotation(tool: .polygon, frame: bounds, pageIndex: pageIndex)

            // Convert points to paths
            var paths: [BezierPath] = []
            for (index, point) in points.enumerated() {
                if index == 0 {
                    paths.append(BezierPath(points: [point], type: .moveTo))
                } else {
                    paths.append(BezierPath(points: [point], type: .lineTo))
                }
            }
            paths.append(BezierPath(points: [], type: .closePath))
            annotation.properties.paths = paths

            return annotation

        case .star(let center, let radius):
            // Create star path
            let frame = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let annotation = UnifiedAnnotation(tool: .polygon, frame: frame, pageIndex: pageIndex)

            // Generate star points
            var paths: [BezierPath] = []
            let points = 5
            let angleStep = (2 * CGFloat.pi) / CGFloat(points)

            for i in 0..<points {
                let outerAngle = CGFloat(i) * angleStep - .pi / 2
                let innerAngle = outerAngle + angleStep / 2

                let outerPoint = CGPoint(
                    x: center.x + cos(outerAngle) * radius,
                    y: center.y + sin(outerAngle) * radius
                )
                let innerPoint = CGPoint(
                    x: center.x + cos(innerAngle) * radius * 0.4,
                    y: center.y + sin(innerAngle) * radius * 0.4
                )

                if i == 0 {
                    paths.append(BezierPath(points: [outerPoint], type: .moveTo))
                } else {
                    paths.append(BezierPath(points: [outerPoint], type: .lineTo))
                }
                paths.append(BezierPath(points: [innerPoint], type: .lineTo))
            }
            paths.append(BezierPath(points: [], type: .closePath))
            annotation.properties.paths = paths

            return annotation

        case .none:
            return nil
        }
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}