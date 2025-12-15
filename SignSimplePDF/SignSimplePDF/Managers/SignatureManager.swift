import Foundation
import PDFKit
import PencilKit
import UIKit
import CoreData

// MARK: - Custom PDF Annotation for Signatures

class ImageStampAnnotation: PDFAnnotation {
    var image: UIImage?

    init(bounds: CGRect, image: UIImage) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image = image else { return }

        context.saveGState()

        // Use UIImage's draw method which handles orientation correctly
        // We need to flip the context because PDF has origin at bottom-left
        // but UIImage.draw expects origin at top-left
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw the UIImage directly - this handles all orientation metadata
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: bounds.size))
        UIGraphicsPopContext()

        context.restoreGState()
    }
}

// MARK: - Signature Manager

@MainActor
class SignatureManager: ObservableObject {
    @Published var signatures: [Signature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let subscriptionManager: SubscriptionManager
    private let persistenceController = PersistenceController.shared

    // Default signature size when placing on PDF
    static let defaultSignatureSize = CGSize(width: 150, height: 75)

    // MARK: - Computed Properties

    var canCreateSignature: Bool {
        subscriptionManager.canSaveUnlimitedSignatures
    }

    var remainingFreeSignatures: Int {
        subscriptionManager.remainingFreeSignatures
    }

    var signatureCount: Int {
        signatures.count
    }

    // MARK: - Initialization

    init(subscriptionManager: SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        loadSignatures()
    }

    // MARK: - CRUD Operations

    func loadSignatures() {
        let request: NSFetchRequest<Signature> = Signature.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Signature.createdAt, ascending: false)]

        do {
            signatures = try persistenceController.container.viewContext.fetch(request)
            // Sync count with subscription manager
            subscriptionManager.setSignatureCount(signatures.count)
        } catch {
            errorMessage = "Failed to load signatures: \(error.localizedDescription)"
        }
    }

    func createSignature(from drawing: PKDrawing, name: String, strokeColor: String = "#000000", strokeWidth: Float = 2.0) throws -> Signature {
        // Check if user can create more signatures
        guard canCreateSignature else {
            throw SignatureError.limitReached
        }

        // Convert drawing to image
        guard let imageData = imageDataFromDrawing(drawing) else {
            throw SignatureError.conversionFailed
        }

        // Create new signature entity
        let context = persistenceController.container.viewContext
        let signature = Signature(context: context)

        signature.id = UUID()
        signature.name = name
        signature.imageData = imageData
        signature.strokeColor = strokeColor
        signature.strokeWidth = strokeWidth
        signature.createdAt = Date()

        // Save to Core Data
        do {
            try context.save()
            signatures.insert(signature, at: 0)
            subscriptionManager.incrementSignatureCount()

            // Track for review request
            ReviewRequestManager.shared.recordSignatureCreated()

            return signature
        } catch {
            context.rollback()
            throw SignatureError.saveFailed
        }
    }

    func deleteSignature(_ signature: Signature) {
        let context = persistenceController.container.viewContext
        context.delete(signature)

        do {
            try context.save()
            if let index = signatures.firstIndex(of: signature) {
                signatures.remove(at: index)
            }
            // Update count in subscription manager
            subscriptionManager.setSignatureCount(signatures.count)
        } catch {
            context.rollback()
            errorMessage = "Failed to delete signature: \(error.localizedDescription)"
        }
    }

    func updateSignatureName(_ signature: Signature, newName: String) {
        signature.name = newName

        do {
            try persistenceController.container.viewContext.save()
        } catch {
            errorMessage = "Failed to update signature: \(error.localizedDescription)"
        }
    }

    // MARK: - PDF Annotation

    /// Apply a signature to a PDF page at the specified point
    /// - Parameters:
    ///   - signature: The signature to apply
    ///   - page: The PDF page to add the signature to
    ///   - point: The center point for the signature in PDF coordinates
    ///   - size: The size of the signature annotation (defaults to 150x75)
    /// - Returns: The created annotation, or nil if failed
    @discardableResult
    func applySignature(_ signature: Signature, to page: PDFPage, at point: CGPoint, size: CGSize = defaultSignatureSize) -> PDFAnnotation? {
        guard let imageData = signature.imageData,
              let image = UIImage(data: imageData) else {
            return nil
        }

        // Calculate bounds centered on the tap point
        let bounds = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // Create and add the annotation
        let annotation = ImageStampAnnotation(bounds: bounds, image: image)
        page.addAnnotation(annotation)

        return annotation
    }

    /// Remove an annotation from a PDF page
    func removeAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
    }

    // MARK: - Drawing Conversion

    /// Convert a PencilKit drawing to PNG image data
    private func imageDataFromDrawing(_ drawing: PKDrawing) -> Data? {
        // Get the bounds of the drawing with some padding
        let drawingBounds = drawing.bounds

        // If drawing is empty, return nil
        guard !drawingBounds.isEmpty else {
            return nil
        }

        // Add padding around the drawing
        let padding: CGFloat = 20
        let paddedBounds = drawingBounds.insetBy(dx: -padding, dy: -padding)

        // Generate image at 2x scale for quality
        let image = drawing.image(from: paddedBounds, scale: 2.0)

        return image.pngData()
    }

    /// Get UIImage from a signature
    func imageForSignature(_ signature: Signature) -> UIImage? {
        guard let imageData = signature.imageData else { return nil }
        return UIImage(data: imageData)
    }
}

// MARK: - Signature Errors

enum SignatureError: LocalizedError {
    case limitReached
    case conversionFailed
    case saveFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .limitReached:
            return "You've reached the maximum number of free signatures. Upgrade to Premium for unlimited signatures."
        case .conversionFailed:
            return "Failed to convert the drawing to an image."
        case .saveFailed:
            return "Failed to save the signature."
        case .notFound:
            return "Signature not found."
        }
    }
}
