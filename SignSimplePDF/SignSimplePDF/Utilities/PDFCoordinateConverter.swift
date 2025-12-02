import Foundation
import PDFKit
import CoreGraphics

/// Robust utility for converting between PDF coordinate space and screen coordinate space.
///
/// PDF Coordinates: Origin at bottom-left, Y increases upward
/// Screen Coordinates: Origin at top-left, Y increases downward
///
/// This class provides the single source of truth for all coordinate transformations,
/// ensuring pixel-perfect positioning across zoom levels, rotations, and page navigation.
final class PDFCoordinateConverter {

    // MARK: - Core Conversion Methods

    /// Convert a point from PDF coordinate space to screen coordinate space
    /// - Parameters:
    ///   - pdfPoint: Point in PDF coordinates (bottom-left origin)
    ///   - page: The PDF page containing the point
    ///   - pdfView: The PDFView displaying the page
    /// - Returns: Point in screen coordinates (top-left origin)
    static func pdfToScreen(
        point pdfPoint: CGPoint,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> CGPoint {
        // PDFView.convert handles the coordinate transformation
        return pdfView.convert(pdfPoint, from: page)
    }

    /// Convert a rect from PDF coordinate space to screen coordinate space
    /// - Parameters:
    ///   - pdfRect: Rectangle in PDF coordinates
    ///   - page: The PDF page containing the rectangle
    ///   - pdfView: The PDFView displaying the page
    /// - Returns: Rectangle in screen coordinates
    static func pdfToScreen(
        rect pdfRect: CGRect,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> CGRect {
        return pdfView.convert(pdfRect, from: page)
    }

    /// Convert a point from screen coordinate space to PDF coordinate space
    /// - Parameters:
    ///   - screenPoint: Point in screen coordinates (top-left origin)
    ///   - page: The PDF page to convert to
    ///   - pdfView: The PDFView displaying the page
    /// - Returns: Point in PDF coordinates (bottom-left origin)
    static func screenToPDF(
        point screenPoint: CGPoint,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> CGPoint {
        return pdfView.convert(screenPoint, to: page)
    }

    /// Convert a rect from screen coordinate space to PDF coordinate space
    /// - Parameters:
    ///   - screenRect: Rectangle in screen coordinates
    ///   - page: The PDF page to convert to
    ///   - pdfView: The PDFView displaying the page
    /// - Returns: Rectangle in PDF coordinates
    static func screenToPDF(
        rect screenRect: CGRect,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> CGRect {
        return pdfView.convert(screenRect, to: page)
    }

    // MARK: - Bounds and Clamping

    /// Get the bounds of a page in PDF coordinates
    /// - Parameters:
    ///   - page: The PDF page
    ///   - box: The box type (typically .mediaBox or .cropBox)
    /// - Returns: The bounds rectangle in PDF coordinates
    static func bounds(
        for page: PDFPage,
        box: PDFDisplayBox = .mediaBox
    ) -> CGRect {
        return page.bounds(for: box)
    }

    /// Clamp a PDF point to stay within page bounds with an annotation size
    /// - Parameters:
    ///   - pdfPoint: The point to clamp (bottom-left corner of annotation)
    ///   - size: The size of the annotation
    ///   - page: The PDF page
    ///   - box: The display box to use for bounds
    ///   - padding: Optional padding from edges (default: 0)
    /// - Returns: Clamped point that keeps the annotation fully within bounds
    static func clamp(
        pdfPoint: CGPoint,
        size: CGSize,
        on page: PDFPage,
        box: PDFDisplayBox = .mediaBox,
        padding: CGFloat = 0
    ) -> CGPoint {
        let bounds = page.bounds(for: box)

        // Calculate valid ranges considering annotation size and padding
        let minX = bounds.minX + padding
        let maxX = bounds.maxX - size.width - padding
        let minY = bounds.minY + padding
        let maxY = bounds.maxY - size.height - padding

        // Clamp X coordinate
        var clampedX = pdfPoint.x
        if maxX >= minX {
            clampedX = min(max(pdfPoint.x, minX), maxX)
        } else {
            // If annotation is larger than page, center it
            clampedX = bounds.minX + (bounds.width - size.width) / 2
        }

        // Clamp Y coordinate
        var clampedY = pdfPoint.y
        if maxY >= minY {
            clampedY = min(max(pdfPoint.y, minY), maxY)
        } else {
            // If annotation is larger than page, center it
            clampedY = bounds.minY + (bounds.height - size.height) / 2
        }

        let result = CGPoint(x: clampedX, y: clampedY)

        // Log if clamping occurred
        if result != pdfPoint {
            print("   🔧 [PDFCoordinateConverter] clamp - Position adjusted")
            print("      Input: \(pdfPoint) → Output: \(result)")
            print("      Size: \(size), PageBounds: \(bounds)")
        }

        return result
    }

    /// Clamp a PDF rectangle to stay within page bounds
    /// - Parameters:
    ///   - pdfRect: The rectangle to clamp
    ///   - page: The PDF page
    ///   - box: The display box to use for bounds
    ///   - padding: Optional padding from edges
    /// - Returns: Clamped rectangle
    static func clamp(
        pdfRect: CGRect,
        on page: PDFPage,
        box: PDFDisplayBox = .mediaBox,
        padding: CGFloat = 0
    ) -> CGRect {
        let clampedOrigin = clamp(
            pdfPoint: pdfRect.origin,
            size: pdfRect.size,
            on: page,
            box: box,
            padding: padding
        )
        return CGRect(origin: clampedOrigin, size: pdfRect.size)
    }

    // MARK: - Annotation Positioning Helpers

    /// Calculate centered position for an annotation on a page
    /// - Parameters:
    ///   - size: Size of the annotation
    ///   - page: The PDF page
    ///   - box: The display box to use
    /// - Returns: Point that centers the annotation on the page
    static func centeredPosition(
        for size: CGSize,
        on page: PDFPage,
        box: PDFDisplayBox = .mediaBox
    ) -> CGPoint {
        let bounds = page.bounds(for: box)
        let x = bounds.midX - size.width / 2
        let y = bounds.midY - size.height / 2
        return CGPoint(x: x, y: y)
    }

    /// Adjust an annotation position when its scale changes, maintaining the center point
    /// - Parameters:
    ///   - currentOrigin: Current PDF origin point (bottom-left)
    ///   - currentSize: Current size
    ///   - newSize: New size after scaling
    ///   - page: The PDF page
    /// - Returns: New origin point that maintains the center position
    static func adjustOriginForResize(
        currentOrigin: CGPoint,
        currentSize: CGSize,
        newSize: CGSize,
        on page: PDFPage
    ) -> CGPoint {
        // Calculate current center
        let currentCenter = CGPoint(
            x: currentOrigin.x + currentSize.width / 2,
            y: currentOrigin.y + currentSize.height / 2
        )

        // Calculate new origin that maintains the center
        let newOrigin = CGPoint(
            x: currentCenter.x - newSize.width / 2,
            y: currentCenter.y - newSize.height / 2
        )

        // Clamp to page bounds
        return clamp(pdfPoint: newOrigin, size: newSize, on: page)
    }

    /// Adjust origin when resizing from a specific corner handle
    /// - Parameters:
    ///   - currentOrigin: Current PDF origin point (bottom-left)
    ///   - currentSize: Current size
    ///   - newSize: New size after scaling
    ///   - anchorCorner: Which corner to keep fixed during resize
    ///   - page: The PDF page
    /// - Returns: New origin point with the anchor corner fixed
    static func adjustOriginForCornerResize(
        currentOrigin: CGPoint,
        currentSize: CGSize,
        newSize: CGSize,
        anchorCorner: AnnotationCorner,
        on page: PDFPage
    ) -> CGPoint {
        let currentRect = CGRect(origin: currentOrigin, size: currentSize)

        // Determine the anchor point based on corner
        let anchorPoint: CGPoint
        switch anchorCorner {
        case .topLeft:
            // In PDF coordinates, "top" means larger Y value
            anchorPoint = CGPoint(x: currentRect.minX, y: currentRect.maxY)
        case .topRight:
            anchorPoint = CGPoint(x: currentRect.maxX, y: currentRect.maxY)
        case .bottomLeft:
            anchorPoint = CGPoint(x: currentRect.minX, y: currentRect.minY)
        case .bottomRight:
            anchorPoint = CGPoint(x: currentRect.maxX, y: currentRect.minY)
        }

        // Calculate new origin based on anchor
        let newOrigin: CGPoint
        switch anchorCorner {
        case .topLeft:
            newOrigin = CGPoint(x: anchorPoint.x, y: anchorPoint.y - newSize.height)
        case .topRight:
            newOrigin = CGPoint(x: anchorPoint.x - newSize.width, y: anchorPoint.y - newSize.height)
        case .bottomLeft:
            newOrigin = anchorPoint
        case .bottomRight:
            newOrigin = CGPoint(x: anchorPoint.x - newSize.width, y: anchorPoint.y)
        }

        // Clamp to page bounds
        return clamp(pdfPoint: newOrigin, size: newSize, on: page)
    }

    // MARK: - Validation

    /// Check if a point is within page bounds
    /// - Parameters:
    ///   - pdfPoint: Point in PDF coordinates
    ///   - page: The PDF page
    ///   - box: The display box to check against
    /// - Returns: True if the point is within bounds
    static func isWithinBounds(
        pdfPoint: CGPoint,
        on page: PDFPage,
        box: PDFDisplayBox = .mediaBox
    ) -> Bool {
        let bounds = page.bounds(for: box)
        return bounds.contains(pdfPoint)
    }

    /// Check if a rectangle is fully within page bounds
    /// - Parameters:
    ///   - pdfRect: Rectangle in PDF coordinates
    ///   - page: The PDF page
    ///   - box: The display box to check against
    /// - Returns: True if the entire rectangle is within bounds
    static func isWithinBounds(
        pdfRect: CGRect,
        on page: PDFPage,
        box: PDFDisplayBox = .mediaBox
    ) -> Bool {
        let bounds = page.bounds(for: box)
        return bounds.contains(pdfRect)
    }

    /// Validate that a size is reasonable for a page
    /// - Parameters:
    ///   - size: Size to validate
    ///   - page: The PDF page
    ///   - maxRatio: Maximum ratio of annotation to page size (default: 0.9)
    /// - Returns: True if size is valid
    static func isValidSize(
        _ size: CGSize,
        for page: PDFPage,
        maxRatio: CGFloat = 0.9
    ) -> Bool {
        let bounds = page.bounds(for: .mediaBox)
        return size.width > 0 &&
               size.height > 0 &&
               size.width <= bounds.width * maxRatio &&
               size.height <= bounds.height * maxRatio
    }
}

// MARK: - Supporting Types

/// Represents the four corners of an annotation for resize operations
enum AnnotationCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// Get the opposite corner
    var opposite: AnnotationCorner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }
}

// MARK: - CGRect Extensions for Convenience

extension CGRect {
    /// Get the center point of the rectangle
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    /// Create a rectangle from center and size
    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
