import Foundation
import CoreData
import PDFKit
import UIKit

/// Manages persistence of PDF annotations to Core Data
///
/// This manager enables:
/// - Saving annotations separately from the PDF for re-editing
/// - Loading annotations from storage
/// - Syncing annotations with PDFDocument
/// - Export mode: flattening annotations into PDF
@MainActor
class AnnotationPersistenceManager {

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Save Annotations

    /// Save annotations for a document to Core Data
    /// - Parameters:
    ///   - annotations: Array of annotation items to save
    ///   - document: The PDF document these annotations belong to
    func saveAnnotations(_ annotations: [PDFAnnotationItem], for document: StoredPDFDocument) throws {
        print("💾 [PersistenceManager] saveAnnotations - Saving \(annotations.count) annotations")

        let context = persistenceController.container.viewContext

        // Remove existing annotations for this document
        if let existingAnnotations = document.annotations as? Set<StoredPDFAnnotation> {
            print("   🗑️ Deleting \(existingAnnotations.count) existing annotations")
            for annotation in existingAnnotations {
                context.delete(annotation)
            }
        }

        // Save new annotations
        for (index, annotationItem) in annotations.enumerated() {
            print("   📌 Saving annotation \(index):")
            print("      pdfPosition=\(annotationItem.pdfPosition), size=\(annotationItem.size), scale=\(annotationItem.scale)")
            print("      pdfBounds=\(annotationItem.pdfBounds)")
            let storedAnnotation = StoredPDFAnnotation(context: context)
            storedAnnotation.id = UUID()
            storedAnnotation.document = document
            storedAnnotation.pageIndex = Int32(annotationItem.pageIndex)
            storedAnnotation.createdAt = Date()

            // Serialize annotation based on type
            switch annotationItem.type {
            case .signature(let imageData):
                storedAnnotation.annotationType = "signature"
                storedAnnotation.signatureData = imageData
                storedAnnotation.bounds = NSCoder.string(for: annotationItem.pdfBounds)
                print("      → Saved as signature, bounds: \(annotationItem.pdfBounds)")

            case .text(let content, let fontSize, let color):
                storedAnnotation.annotationType = "text"
                storedAnnotation.contents = content
                storedAnnotation.fontSize = Float(fontSize * annotationItem.scale)
                storedAnnotation.color = color.toHexString()
                storedAnnotation.bounds = NSCoder.string(for: annotationItem.pdfBounds)
                print("      → Saved as text:")
                print("         content='\(content)', fontSize=\(fontSize * annotationItem.scale)")
                print("         color=\(color.toHexString()), bounds=\(annotationItem.pdfBounds)")

            case .highlight(let color):
                storedAnnotation.annotationType = "highlight"
                storedAnnotation.color = color.toHexString()
                storedAnnotation.bounds = NSCoder.string(for: annotationItem.pdfBounds)
                print("      → Saved as highlight, bounds: \(annotationItem.pdfBounds)")

            case .drawing(let paths, let color, let lineWidth):
                storedAnnotation.annotationType = "drawing"
                storedAnnotation.color = color.toHexString()

                // Serialize paths
                if let pathsData = try? JSONEncoder().encode(paths) {
                    storedAnnotation.signatureData = pathsData
                }

                // Store line width and scale in bounds string
                let boundsDict: [String: Any] = [
                    "bounds": NSCoder.string(for: annotationItem.pdfBounds),
                    "lineWidth": lineWidth,
                    "scale": annotationItem.scale
                ]
                if let dictData = try? JSONSerialization.data(withJSONObject: boundsDict),
                   let dictString = String(data: dictData, encoding: .utf8) {
                    storedAnnotation.bounds = dictString
                }
                print("      → Saved as drawing:")
                print("         paths.count=\(paths.count), lineWidth=\(lineWidth), scale=\(annotationItem.scale)")
                print("         bounds=\(annotationItem.pdfBounds)")
            }
        }

        // Save context
        print("   💿 Saving Core Data context...")
        try context.save()
        print("✅ [PersistenceManager] saveAnnotations - Completed successfully")
    }

    // MARK: - Load Annotations

    /// Load annotations for a document from Core Data
    /// - Parameter document: The PDF document to load annotations for
    /// - Returns: Array of annotation items
    func loadAnnotations(for document: StoredPDFDocument) throws -> [PDFAnnotationItem] {
        print("📂 [PersistenceManager] loadAnnotations - Loading for document: \(document.name ?? "unknown")")

        guard let storedAnnotations = document.annotations as? Set<StoredPDFAnnotation> else {
            print("   ⚠️ No stored annotations found")
            return []
        }

        print("   Found \(storedAnnotations.count) stored annotations")

        var annotations: [PDFAnnotationItem] = []

        for (index, stored) in storedAnnotations.sorted(by: { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }).enumerated() {
            guard let annotationType = stored.annotationType,
                  let boundsString = stored.bounds else {
                print("   ⚠️ Skipping annotation \(index) - missing type or bounds")
                continue
            }

            let pageIndex = Int(stored.pageIndex)
            print("   📌 Loading annotation \(index): type=\(annotationType), pageIndex=\(pageIndex)")

            switch annotationType {
            case "signature":
                guard let imageData = stored.signatureData else { continue }
                let bounds = NSCoder.cgRect(for: boundsString)

                print("      Loaded signature bounds: \(bounds)")

                let annotation = PDFAnnotationItem(
                    type: .signature(imageData: imageData),
                    pdfPosition: bounds.origin,
                    size: bounds.size,
                    pageIndex: pageIndex
                )
                print("      → Created PDFAnnotationItem: pdfPosition=\(annotation.pdfPosition), size=\(annotation.size)")
                annotations.append(annotation)

            case "text":
                guard let content = stored.contents,
                      let colorHex = stored.color,
                      let color = UIColor(hexString: colorHex) else {
                    print("      ⚠️ Skipping text annotation - missing content or color")
                    continue
                }

                let bounds = NSCoder.cgRect(for: boundsString)
                let fontSize = CGFloat(stored.fontSize)

                print("      Loaded text bounds: \(bounds)")
                print("      content='\(content)', fontSize=\(fontSize), color=\(colorHex)")

                let annotation = PDFAnnotationItem(
                    type: .text(
                        content: content,
                        fontSize: fontSize,
                        color: color
                    ),
                    pdfPosition: bounds.origin,
                    size: bounds.size,
                    pageIndex: pageIndex
                )
                print("      → Created PDFAnnotationItem: pdfPosition=\(annotation.pdfPosition), size=\(annotation.size), scale=\(annotation.scale)")
                annotations.append(annotation)

            case "highlight":
                guard let colorHex = stored.color,
                      let color = UIColor(hexString: colorHex) else { continue }

                let bounds = NSCoder.cgRect(for: boundsString)

                let annotation = PDFAnnotationItem(
                    type: .highlight(color: color),
                    pdfPosition: bounds.origin,
                    size: bounds.size,
                    pageIndex: pageIndex
                )
                annotations.append(annotation)

            case "drawing":
                guard let pathsData = stored.signatureData,
                      let paths = try? JSONDecoder().decode([DrawingPath].self, from: pathsData),
                      let colorHex = stored.color,
                      let color = UIColor(hexString: colorHex) else { continue }

                // Parse bounds dictionary
                var bounds = CGRect.zero
                var lineWidth: CGFloat = 2.0
                var scale: CGFloat = 1.0

                if let dictData = boundsString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: dictData) as? [String: Any] {
                    if let boundsStr = dict["bounds"] as? String {
                        bounds = NSCoder.cgRect(for: boundsStr)
                    }
                    if let lw = dict["lineWidth"] as? CGFloat {
                        lineWidth = lw
                    }
                    if let s = dict["scale"] as? CGFloat {
                        scale = s
                    }
                }

                let annotation = PDFAnnotationItem(
                    type: .drawing(paths: paths, color: color, lineWidth: lineWidth),
                    pdfPosition: bounds.origin,
                    size: bounds.size,
                    pageIndex: pageIndex
                )
                annotation.scale = scale
                annotations.append(annotation)

            default:
                print("      ⚠️ Unknown annotation type: \(annotationType)")
                continue
            }
        }

        print("✅ [PersistenceManager] loadAnnotations - Loaded \(annotations.count) annotations successfully")
        return annotations
    }

    // MARK: - Clear Annotations

    /// Clear all annotations for a document
    /// - Parameter document: The PDF document to clear annotations from
    func clearAnnotations(for document: StoredPDFDocument) throws {
        let context = persistenceController.container.viewContext

        if let existingAnnotations = document.annotations as? Set<StoredPDFAnnotation> {
            for annotation in existingAnnotations {
                context.delete(annotation)
            }
        }

        try context.save()
    }

    // MARK: - Utility Methods

    /// Check if a document has saved annotations
    /// - Parameter document: The PDF document to check
    /// - Returns: True if annotations exist
    func hasAnnotations(for document: StoredPDFDocument) -> Bool {
        guard let annotations = document.annotations as? Set<StoredPDFAnnotation> else {
            return false
        }
        return !annotations.isEmpty
    }

    /// Get annotation count for a document
    /// - Parameter document: The PDF document
    /// - Returns: Number of annotations
    func annotationCount(for document: StoredPDFDocument) -> Int {
        return (document.annotations as? Set<StoredPDFAnnotation>)?.count ?? 0
    }
}

