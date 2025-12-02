//
//  AnnotationPersistence.swift
//  SignSimplePDF
//
//  Clean Core Data persistence for the new annotation system
//

import Foundation
import CoreData
import UIKit
import ObjectiveC

// MARK: - PDF Annotation Persistence Manager
public class PDFAnnotationPersistenceManager {
    // MARK: - Properties
    private let context: NSManagedObjectContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization
    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Save Annotations
    public func saveAnnotations(_ annotations: [UnifiedAnnotation], for document: StoredPDFDocument) throws {
        // Remove existing annotations
        if let existingAnnotations = document.annotations as? Set<StoredPDFAnnotation> {
            existingAnnotations.forEach { context.delete($0) }
        }

        // Save new annotations
        for annotation in annotations {
            let stored = StoredPDFAnnotation(context: context)

            // Basic properties
            stored.id = annotation.id
            stored.annotationType = annotation.tool.rawValue
            stored.pageIndex = Int32(annotation.pageIndex)
            stored.createdAt = annotation.createdAt

            // Encode frame as JSON string
            let frameData = try encoder.encode(annotation.frame)
            stored.bounds = String(data: frameData, encoding: .utf8)

            // Encode properties as JSON
            let propertiesData = try encoder.encode(annotation.properties)
            stored.contents = String(data: propertiesData, encoding: .utf8)

            // Special handling for specific types
            switch annotation.tool {
            case .signature:
                stored.signatureData = annotation.properties.signatureImage
            case .text:
                stored.fontSize = Float(annotation.properties.fontSize)
                stored.color = annotation.properties.strokeColor.hexString
            case .pen, .highlighter:
                // Store paths as data
                if let pathsData = try? encoder.encode(annotation.properties.paths) {
                    stored.signatureData = pathsData // Reuse field for paths
                }
            default:
                break
            }

            // Link to document
            stored.document = document
        }

        // Save context
        try context.save()
    }

    // MARK: - Load Annotations
    public func loadAnnotations(for document: StoredPDFDocument) throws -> [UnifiedAnnotation] {
        guard let storedAnnotations = document.annotations as? Set<StoredPDFAnnotation> else {
            return []
        }

        return try storedAnnotations.compactMap { stored in
            // Decode frame - handle both String and legacy Binary formats
            guard let boundsString = stored.bounds,
                  let boundsData = boundsString.data(using: .utf8),
                  let frame = try? decoder.decode(CGRect.self, from: boundsData),
                  let toolString = stored.annotationType,
                  let tool = AnnotationTool(rawValue: toolString) else {
                return nil
            }

            // Create annotation
            let annotation = UnifiedAnnotation(
                tool: tool,
                frame: frame,
                pageIndex: Int(stored.pageIndex)
            )

            // Restore ID
            if let id = stored.id {
                annotation.id = id
            }

            // Decode properties
            if let propertiesString = stored.contents,
               let propertiesData = propertiesString.data(using: .utf8),
               let properties = try? decoder.decode(AnnotationProperties.self, from: propertiesData) {
                annotation.properties = properties
            }

            // Special handling for specific types
            switch tool {
            case .signature:
                annotation.properties.signatureImage = stored.signatureData
            case .pen, .highlighter:
                // Restore paths from signatureData field
                if let pathsData = stored.signatureData,
                   let paths = try? decoder.decode([BezierPath].self, from: pathsData) {
                    annotation.properties.paths = paths
                }
            case .text:
                annotation.properties.fontSize = stored.fontSize > 0 ? CGFloat(stored.fontSize) : 14
                if let colorHex = stored.color {
                    annotation.properties.strokeColor = UIColor(hex: colorHex) ?? .label
                }
            default:
                break
            }

            return annotation
        }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Quick Save (for autosave)
    public func quickSave(_ annotations: [UnifiedAnnotation], for documentID: UUID) throws {
        // Fetch document
        let request = StoredPDFDocument.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)

        guard let document = try context.fetch(request).first else {
            throw PersistenceError.documentNotFound
        }

        try saveAnnotations(annotations, for: document)
    }

    // MARK: - Migration Support
    public func migrateOldAnnotations(from document: StoredPDFDocument) throws -> [UnifiedAnnotation] {
        // Convert old annotation format to new UnifiedAnnotation
        guard let oldAnnotations = document.annotations as? Set<StoredPDFAnnotation> else {
            return []
        }

        return oldAnnotations.compactMap { old in
            // Map old annotation types to new tools
            let tool: AnnotationTool
            switch old.annotationType {
            case "ink", "pen": tool = .pen
            case "highlight", "highlighter": tool = .highlighter
            case "text", "freeText": tool = .text
            case "signature": tool = .signature
            case "square", "rectangle": tool = .rectangle
            case "circle", "oval": tool = .oval
            case "line": tool = .line
            case "arrow": tool = .arrow
            default: return nil
            }

            // Try to decode bounds from String
            guard let boundsString = old.bounds,
                  let boundsData = boundsString.data(using: .utf8),
                  let frame = try? decoder.decode(CGRect.self, from: boundsData) else {
                return nil
            }

            let annotation = UnifiedAnnotation(
                tool: tool,
                frame: frame,
                pageIndex: Int(old.pageIndex)
            )

            // Restore properties
            if let contents = old.contents {
                annotation.properties.text = contents
            }

            if let signatureData = old.signatureData {
                annotation.properties.signatureImage = signatureData
            }

            return annotation
        }
    }
}

// MARK: - Persistence Errors
public enum PersistenceError: LocalizedError {
    case documentNotFound
    case saveFailed(Error)
    case loadFailed(Error)
    case migrationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "Document not found in database"
        case .saveFailed(let error):
            return "Failed to save annotations: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load annotations: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Failed to migrate annotations: \(error.localizedDescription)"
        }
    }
}

// MARK: - Color Extensions
private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        getRed(&r, green: &g, blue: &b, alpha: &a)

        return String(format: "#%02X%02X%02X%02X",
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255),
                      Int(a * 255))
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - CGRect Codable
extension CGRect: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
}

// MARK: - Integration with PDFAnnotationEngine
public extension PDFAnnotationEngine {
    func setupPersistence(context: NSManagedObjectContext) {
        let persistenceManager = PDFAnnotationPersistenceManager(context: context)

        // Override saveAnnotations
        self.saveAnnotationsHandler = { [weak self] in
            guard let self = self,
                  let document = self.currentDocument else { return }

            do {
                try persistenceManager.saveAnnotations(self.annotations, for: document)
                print("✅ Saved \(self.annotations.count) annotations")
            } catch {
                print("❌ Failed to save annotations: \(error)")
            }
        }

        // Override loadAnnotations
        self.loadAnnotationsHandler = { [weak self] document in
            guard let self = self,
                  let pdfDocument = document as? StoredPDFDocument else { return }

            do {
                let loadedAnnotations = try persistenceManager.loadAnnotations(for: pdfDocument)
                // Clear existing annotations and add new ones
                self.clearAll()
                for annotation in loadedAnnotations {
                    self.addAnnotation(annotation)
                }
                self.currentDocument = pdfDocument
                print("✅ Loaded \(loadedAnnotations.count) annotations")
            } catch {
                print("❌ Failed to load annotations: \(error)")
                // Clear annotations using public method
                self.clearAll()
            }
        }
    }

    private struct AssociatedKeys {
        static var currentDocument = "currentDocument"
        static var saveAnnotationsHandler = "saveAnnotationsHandler"
        static var loadAnnotationsHandler = "loadAnnotationsHandler"
    }

    private var currentDocument: StoredPDFDocument? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.currentDocument) as? StoredPDFDocument
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.currentDocument, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var saveAnnotationsHandler: (() -> Void)? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.saveAnnotationsHandler) as? () -> Void
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.saveAnnotationsHandler, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    private var loadAnnotationsHandler: ((Any) -> Void)? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.loadAnnotationsHandler) as? (Any) -> Void
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.loadAnnotationsHandler, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}