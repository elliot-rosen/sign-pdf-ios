import Foundation
import PDFKit
import UIKit

/// Base class for custom PDF annotations that support editing in the app
///
/// This class provides:
/// - Proper coordinate handling for PDF space (bottom-left origin)
/// - Edit mode support for post-save editing
/// - Serialization for persistence
/// - Drawing logic that works consistently across zoom levels
///
/// Subclasses should override:
/// - `draw(with:in:)` to provide custom rendering
/// - `encode(with:)` and `init?(coder:)` for persistence
class EditablePDFAnnotation: PDFAnnotation {

    /// Unique identifier for this annotation
    var annotationID: UUID

    /// Whether this annotation can be edited after being saved
    var isEditable: Bool = true

    /// Creation date for sorting and tracking
    var creationDate: Date

    /// Last modification date
    var lastModified: Date

    // MARK: - Initialization

    init(bounds: CGRect, annotationID: UUID = UUID()) {
        self.annotationID = annotationID
        self.creationDate = Date()
        self.lastModified = Date()

        super.init(
            bounds: bounds,
            forType: .stamp,
            withProperties: nil
        )

        // Set default properties
        self.color = .clear
        self.backgroundColor = .clear
        self.shouldDisplay = true
        self.shouldPrint = true
    }

    required init?(coder: NSCoder) {
        // Decode custom properties
        if let idData = coder.decodeObject(forKey: "annotationID") as? Data,
           let id = try? JSONDecoder().decode(UUID.self, from: idData) {
            self.annotationID = id
        } else {
            self.annotationID = UUID()
        }

        self.isEditable = coder.decodeBool(forKey: "isEditable")

        if let creationDate = coder.decodeObject(forKey: "creationDate") as? Date {
            self.creationDate = creationDate
        } else {
            self.creationDate = Date()
        }

        if let modificationDate = coder.decodeObject(forKey: "lastModified") as? Date {
            self.lastModified = modificationDate
        } else {
            self.lastModified = Date()
        }

        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)

        // Encode custom properties
        if let idData = try? JSONEncoder().encode(annotationID) {
            coder.encode(idData, forKey: "annotationID")
        }

        coder.encode(isEditable, forKey: "isEditable")
        coder.encode(creationDate, forKey: "creationDate")
        coder.encode(lastModified, forKey: "lastModified")
    }

    // MARK: - Position and Size Management

    /// Update the bounds of the annotation, maintaining PDF coordinate system integrity
    func updateBounds(to newBounds: CGRect, on page: PDFPage) {
        // Clamp to page bounds
        let clampedBounds = PDFCoordinateConverter.clamp(
            pdfRect: newBounds,
            on: page,
            box: .mediaBox
        )

        self.bounds = clampedBounds
        self.lastModified = Date()
    }

    /// Move the annotation to a new position
    func move(to point: CGPoint, on page: PDFPage) {
        let newBounds = CGRect(origin: point, size: bounds.size)
        updateBounds(to: newBounds, on: page)
    }

    /// Resize the annotation while maintaining aspect ratio if desired
    func resize(to size: CGSize, on page: PDFPage, maintainAspectRatio: Bool = true) {
        var newSize = size

        if maintainAspectRatio {
            let aspectRatio = bounds.width / bounds.height
            let targetAspectRatio = size.width / size.height

            if targetAspectRatio > aspectRatio {
                // Width is too large, constrain it
                newSize.width = size.height * aspectRatio
            } else {
                // Height is too large, constrain it
                newSize.height = size.width / aspectRatio
            }
        }

        let newBounds = CGRect(origin: bounds.origin, size: newSize)
        updateBounds(to: newBounds, on: page)
    }

    // MARK: - Validation

    /// Check if the annotation is valid and can be drawn
    var isValid: Bool {
        return bounds.width > 0 &&
               bounds.height > 0 &&
               bounds.width.isFinite &&
               bounds.height.isFinite
    }

    /// Validate bounds against page constraints
    func isWithinBounds(of page: PDFPage) -> Bool {
        return PDFCoordinateConverter.isWithinBounds(pdfRect: bounds, on: page, box: .mediaBox)
    }

    // MARK: - Helper Methods

    /// Convert annotation bounds to screen coordinates for a given PDFView
    func screenBounds(in pdfView: PDFView) -> CGRect? {
        guard let page = page else { return nil }
        return PDFCoordinateConverter.pdfToScreen(rect: bounds, on: page, in: pdfView)
    }

    /// Mark as modified
    func markAsModified() {
        lastModified = Date()
    }

    // MARK: - Drawing

    /// Override this in subclasses to provide custom drawing
    /// Default implementation does nothing (transparent annotation)
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Subclasses should override this method
        // By default, this annotation is invisible
    }

    // MARK: - Serialization

    /// Convert annotation to dictionary for JSON serialization
    func toDictionary() -> [String: Any] {
        return [
            "annotationID": annotationID.uuidString,
            "bounds": NSCoder.string(for: bounds),
            "isEditable": isEditable,
            "creationDate": ISO8601DateFormatter().string(from: creationDate),
            "lastModified": ISO8601DateFormatter().string(from: lastModified)
        ]
    }

    /// Create annotation from dictionary
    class func fromDictionary(_ dict: [String: Any]) -> EditablePDFAnnotation? {
        guard let idString = dict["annotationID"] as? String,
              let id = UUID(uuidString: idString),
              let boundsString = dict["bounds"] as? String else {
            return nil
        }

        let bounds = NSCoder.cgRect(for: boundsString)
        let annotation = EditablePDFAnnotation(bounds: bounds, annotationID: id)

        if let isEditable = dict["isEditable"] as? Bool {
            annotation.isEditable = isEditable
        }

        if let creationDateString = dict["creationDate"] as? String,
           let creationDate = ISO8601DateFormatter().date(from: creationDateString) {
            annotation.creationDate = creationDate
        }

        if let modificationDateString = dict["lastModified"] as? String,
           let modificationDate = ISO8601DateFormatter().date(from: modificationDateString) {
            annotation.lastModified = modificationDate
        }

        return annotation
    }
}

// MARK: - Equatable

extension EditablePDFAnnotation {
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? EditablePDFAnnotation else {
            return false
        }
        return annotationID == other.annotationID
    }

    override var hash: Int {
        return annotationID.hashValue
    }
}
