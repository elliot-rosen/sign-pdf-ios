import Foundation
import UIKit
import CoreData
import PencilKit
import PDFKit
import Combine

@MainActor
public class SignatureManager: ObservableObject {
    @Published var signatures: [Signature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSubscribed = false

    private let persistenceController = PersistenceController.shared
    let maxFreeSignatures = 3

    private weak var subscriptionManager: SubscriptionManager?

    init(subscriptionManager: SubscriptionManager? = nil) {
        self.subscriptionManager = subscriptionManager
        loadSignatures()
    }

    func configure(with subscriptionManager: SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        synchronizeSignatureUsage()
    }

    // MARK: - Signature Management

    func loadSignatures() {
        let request: NSFetchRequest<Signature> = Signature.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Signature.createdAt, ascending: false)]

        do {
            signatures = try persistenceController.container.viewContext.fetch(request)
            synchronizeSignatureUsage()
        } catch {
            errorMessage = "Failed to load signatures: \(error.localizedDescription)"
        }
    }

    func saveSignature(
        name: String,
        drawing: PKDrawing,
        strokeColor: UIColor = .black,
        strokeWidth: CGFloat = 2.0,
        canSaveUnlimited: Bool
    ) throws -> Signature {

        // Check if user can save more signatures
        if !canSaveUnlimited && signatures.count >= maxFreeSignatures {
            throw SignatureError.limitReached
        }

        let context = persistenceController.container.viewContext
        let signature = Signature(context: context)

        signature.id = UUID()
        signature.name = name
        signature.createdAt = Date()
        signature.strokeColor = strokeColor.toHexString()
        signature.strokeWidth = Float(strokeWidth)

        // Convert PKDrawing to image data
        let image = drawing.image(from: drawing.bounds, scale: 2.0)
        signature.imageData = image.pngData()

        saveContext()
        loadSignatures() // Reload to ensure UI updates
        synchronizeSignatureUsage()

        // Track for review request
        ReviewRequestManager.shared.recordSignatureCreated()

        return signature
    }

    func deleteSignature(_ signature: Signature) {
        persistenceController.container.viewContext.delete(signature)
        saveContext()

        if let index = signatures.firstIndex(of: signature) {
            signatures.remove(at: index)
        }

        synchronizeSignatureUsage()
    }

    func updateSignature(_ signature: Signature, name: String) {
        signature.name = name
        saveContext()
    }

    private func synchronizeSignatureUsage() {
        subscriptionManager?.setSignatureCount(signatures.count)
    }

    // MARK: - Signature Application

    func applySignatureToPage(
        signature: Signature,
        page: PDFPage,
        at point: CGPoint,
        size: CGSize = CGSize(width: 150, height: 75)
    ) throws {
        guard let imageData = signature.imageData,
              let image = UIImage(data: imageData) else {
            throw SignatureError.invalidSignature
        }

        // Convert point from view coordinates to PDF coordinates
        let pageBounds = page.bounds(for: .mediaBox)
        let adjustedPoint = CGPoint(
            x: point.x,
            y: pageBounds.height - point.y - size.height
        )

        // Create signature annotation bounds
        let bounds = CGRect(origin: adjustedPoint, size: size)

        let annotation = SignatureAnnotation(bounds: bounds, image: image)

        page.addAnnotation(annotation)
    }

    func createTextAnnotation(
        text: String,
        page: PDFPage,
        at point: CGPoint,
        fontSize: CGFloat = 12,
        color: UIColor = .black
    ) {
        let bounds = CGRect(origin: point, size: CGSize(width: 200, height: fontSize * 1.5))
        let annotation = PDFKit.PDFAnnotation(
            bounds: bounds,
            forType: PDFKit.PDFAnnotationSubtype.freeText,
            withProperties: nil
        )

        annotation.contents = text
        annotation.font = UIFont.systemFont(ofSize: fontSize)
        annotation.fontColor = color
        annotation.backgroundColor = UIColor.clear

        page.addAnnotation(annotation)
    }

    func createHighlightAnnotation(
        page: PDFPage,
        selectionBounds: [CGRect],
        color: UIColor = .yellow
    ) {
        for bounds in selectionBounds {
            let annotation = PDFKit.PDFAnnotation(
                bounds: bounds,
                forType: PDFKit.PDFAnnotationSubtype.highlight,
                withProperties: nil
            )
            annotation.color = color.withAlphaComponent(0.3)
            page.addAnnotation(annotation)
        }
    }

    // MARK: - Signature Creation Helpers

    func createSignatureFromDrawing(
        _ drawing: PKDrawing,
        name: String,
        backgroundColor: UIColor = .clear,
        strokeColor: UIColor = .black
    ) -> UIImage {
        let bounds = drawing.bounds
        let renderer = UIGraphicsImageRenderer(size: bounds.size)

        return renderer.image { context in
            backgroundColor.setFill()
            context.fill(bounds)

            let cgContext = context.cgContext
            cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            drawing.image(from: bounds, scale: 1.0).draw(at: bounds.origin)
        }
    }

    // MARK: - Helper Methods

    private func saveContext() {
        persistenceController.save()
    }

    var canAddMoreSignatures: Bool {
        signatures.count < maxFreeSignatures
    }

    var freeSignatureSlotsRemaining: Int {
        max(0, maxFreeSignatures - signatures.count)
    }
}

// MARK: - Extensions

extension UIColor {
    func toHexString() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(format: "#%02X%02X%02X",
                     Int(red * 255),
                     Int(green * 255),
                     Int(blue * 255))
    }

    convenience init?(hexString: String) {
        let r, g, b: CGFloat

        if hexString.hasPrefix("#") {
            let start = hexString.index(hexString.startIndex, offsetBy: 1)
            let hexColor = String(hexString[start...])

            if hexColor.count == 6 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0

                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                    b = CGFloat(hexNumber & 0x0000ff) / 255

                    self.init(red: r, green: g, blue: b, alpha: 1.0)
                    return
                }
            }
        }

        return nil
    }
}

// MARK: - Errors

enum SignatureError: LocalizedError {
    case limitReached
    case invalidSignature
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .limitReached:
            return "You've reached the maximum number of signatures for the free version. Upgrade to Premium for unlimited signatures."
        case .invalidSignature:
            return "The signature data is invalid"
        case .saveFailed:
            return "Failed to save the signature"
        }
    }
}

// MARK: - Custom Signature Annotation

final class SignatureAnnotation: EditablePDFAnnotation {
    private let image: UIImage
    private let imageData: Data

    init(bounds: CGRect, image: UIImage, annotationID: UUID = UUID()) {
        // Store image as-is - draw() method will handle coordinate transformation
        self.image = image
        self.imageData = image.pngData() ?? Data()

        super.init(bounds: bounds, annotationID: annotationID)

        // Signatures should always be printable and displayable
        self.shouldDisplay = true
        self.shouldPrint = true
    }

    required init?(coder: NSCoder) {
        // Decode image data
        if let data = coder.decodeObject(forKey: "signatureImageData") as? Data,
           let img = UIImage(data: data) {
            // Store image as-is - draw() handles coordinate transformation
            self.image = img
            self.imageData = data
        } else {
            // Fallback to empty image
            let size = CGSize(width: 100, height: 50)
            let renderer = UIGraphicsImageRenderer(size: size)
            let emptyImage = renderer.image { _ in }
            self.image = emptyImage
            self.imageData = Data()
        }

        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(imageData, forKey: "signatureImageData")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = image.cgImage else { return }

        context.saveGState()

        // PDF coordinate system: bounds.origin is at bottom-left, Y increases upward
        // CGImage coordinate system: origin at top-left, Y increases downward
        // Since image is already normalized via normalizedForPDF(), we need to:
        // 1. Position at bounds origin
        // 2. Flip coordinate system to match PDF's Y-up orientation

        // Move to bottom-left of annotation bounds
        context.translateBy(x: bounds.minX, y: bounds.minY)

        // Since we want the image right-side up in the final PDF:
        // Move to top of bounds, then flip Y axis so image draws downward
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw image - it will now appear correctly oriented
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))

        context.restoreGState()
    }

    // MARK: - Serialization Support

    override func toDictionary() -> [String: Any] {
        var dict = super.toDictionary()
        dict["type"] = "signature"
        dict["imageData"] = imageData.base64EncodedString()
        return dict
    }

    override class func fromDictionary(_ dict: [String: Any]) -> SignatureAnnotation? {
        guard let idString = dict["annotationID"] as? String,
              let id = UUID(uuidString: idString),
              let boundsString = dict["bounds"] as? String,
              let imageDataString = dict["imageData"] as? String,
              let imageData = Data(base64Encoded: imageDataString),
              let image = UIImage(data: imageData) else {
            return nil
        }

        let bounds = NSCoder.cgRect(for: boundsString)
        let annotation = SignatureAnnotation(bounds: bounds, image: image, annotationID: id)

        if let isEditable = dict["isEditable"] as? Bool {
            annotation.isEditable = isEditable
        }

        return annotation
    }
}

private extension UIImage {
    func normalizedForPDF() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
