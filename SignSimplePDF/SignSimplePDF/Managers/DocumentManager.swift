import Foundation
import PDFKit
import UIKit
import CoreData
import VisionKit
import Combine
import UniformTypeIdentifiers

@MainActor
class DocumentManager: NSObject, ObservableObject {
    @Published var documents: [StoredPDFDocument] = []
    @Published var currentDocument: PDFKit.PDFDocument?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let persistenceController = PersistenceController.shared
    private var cancellables = Set<AnyCancellable>()
    private var subscriptionManager: SubscriptionManager?

    // Expose context for annotation bridge
    var context: NSManagedObjectContext {
        return persistenceController.container.viewContext
    }

    override init() {
        super.init()
        loadDocuments()
    }

    init(subscriptionManager: SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        super.init()
        loadDocuments()
    }

    // MARK: - Document Management

    func loadDocuments() {
        let request: NSFetchRequest<StoredPDFDocument> = StoredPDFDocument.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StoredPDFDocument.lastModified, ascending: false)]

        do {
            documents = try persistenceController.container.viewContext.fetch(request)
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
        }
    }

    func importDocument(from url: URL) async throws -> StoredPDFDocument {
        isLoading = true
        defer { isLoading = false }

        // Try to access as security-scoped resource if needed
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Check file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        if fileSize > DocumentError.maxFileSizeBytes {
            throw DocumentError.fileTooLarge(maxSizeMB: 50)
        }

        let data = try Data(contentsOf: url)

        // Validate PDF
        guard let pdfDocument = PDFKit.PDFDocument(data: data) else {
            throw DocumentError.corruptedPDF
        }

        // Check for empty PDF
        if pdfDocument.pageCount == 0 {
            throw DocumentError.emptyPDF
        }

        let document = createDocument(
            name: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            pdfDocument: pdfDocument
        )

        // Save PDF data to documents directory
        try await savePDFData(data, for: document)

        // Track for review request
        await MainActor.run {
            ReviewRequestManager.shared.recordDocumentProcessed()
        }

        return document
    }

    func importFromCamera() -> Bool {
        guard VNDocumentCameraViewController.isSupported else {
            errorMessage = "Document scanning is not supported on this device"
            return false
        }
        return true
    }

    func createPDFFromImages(_ images: [UIImage]) async throws -> StoredPDFDocument {
        isLoading = true
        defer { isLoading = false }

        let pdfDocument = PDFKit.PDFDocument()

        for (index, image) in images.enumerated() {
            let page = PDFPage(image: image)
            pdfDocument.insert(page!, at: index)
        }

        let document = createDocument(
            name: "Scanned Document \(Date().formatted(.dateTime.month().day()))",
            fileName: "scanned_\(UUID().uuidString).pdf",
            pdfDocument: pdfDocument
        )

        // Save PDF data
        if let data = pdfDocument.dataRepresentation() {
            try await savePDFData(data, for: document)
        }

        return document
    }

    private func createDocument(name: String, fileName: String, pdfDocument: PDFKit.PDFDocument) -> StoredPDFDocument {
        let context = persistenceController.container.viewContext
        let document = StoredPDFDocument(context: context)

        document.id = UUID()
        document.name = name
        document.fileName = fileName
        document.createdAt = Date()
        document.lastModified = Date()
        document.pageCount = Int32(pdfDocument.pageCount)

        // Generate thumbnail
        if let firstPage = pdfDocument.page(at: 0) {
            let thumbnail = firstPage.thumbnail(of: CGSize(width: 200, height: 200), for: .cropBox)
            document.thumbnailData = thumbnail.pngData()
        }

        // Calculate file size
        if let data = pdfDocument.dataRepresentation() {
            document.fileSize = Int64(data.count)
        }

        saveContext()
        documents.insert(document, at: 0)

        return document
    }

    func savePDFData(_ data: Data, for document: StoredPDFDocument) async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(document.fileName ?? "document.pdf")

        try data.write(to: fileURL)
    }

    func loadPDFDocument(for document: StoredPDFDocument) async throws -> PDFKit.PDFDocument {
        guard let fileName = document.fileName else {
            throw DocumentError.fileNotFound
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DocumentError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard let pdfDocument = PDFKit.PDFDocument(data: data) else {
            throw DocumentError.invalidPDF
        }

        currentDocument = pdfDocument
        return pdfDocument
    }

    func deleteDocument(_ document: StoredPDFDocument) {
        // Delete file from disk
        if let fileName = document.fileName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Delete from Core Data
        persistenceController.container.viewContext.delete(document)
        saveContext()

        // Update UI
        if let index = documents.firstIndex(of: document) {
            documents.remove(at: index)
        }
    }

    func renameDocument(_ document: StoredPDFDocument, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        document.name = trimmedName
        document.lastModified = Date()
        saveContext()

        // Trigger UI update
        objectWillChange.send()
    }

    func exportDocument(_ document: StoredPDFDocument) async throws -> URL {
        guard let fileName = document.fileName else {
            throw DocumentError.fileNotFound
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DocumentError.fileNotFound
        }

        // Premium users get clean export
        if subscriptionManager?.isSubscribed == true {
            return fileURL
        }

        // Free users get watermarked export
        guard let pdfDocument = PDFKit.PDFDocument(url: fileURL) else {
            throw DocumentError.invalidPDF
        }

        let watermarkedPDF = applyWatermark(to: pdfDocument)

        // Save to temp location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_\(UUID().uuidString).pdf")
        watermarkedPDF.write(to: tempURL)

        return tempURL
    }

    // MARK: - Watermarking

    private func applyWatermark(to document: PDFKit.PDFDocument) -> PDFKit.PDFDocument {
        let watermarkedDoc = PDFKit.PDFDocument()

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            // Create new page with watermark
            let renderer = UIGraphicsPDFRenderer(bounds: bounds)
            let data = renderer.pdfData { context in
                context.beginPage()

                // Draw original page
                if let cgPage = page.pageRef {
                    let ctx = context.cgContext
                    ctx.saveGState()
                    // PDF pages have origin at bottom-left, need to flip
                    ctx.translateBy(x: 0, y: bounds.height)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.drawPDFPage(cgPage)
                    ctx.restoreGState()
                }

                // Draw watermark
                let watermarkText = "SignSimple"
                let fontSize = bounds.width * 0.08
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.gray.withAlphaComponent(0.2)
                ]

                let textSize = watermarkText.size(withAttributes: attributes)

                // Position in center, rotated -30 degrees
                let ctx = context.cgContext
                ctx.saveGState()
                ctx.translateBy(x: bounds.width / 2, y: bounds.height / 2)
                ctx.rotate(by: -.pi / 6)  // -30 degrees
                watermarkText.draw(
                    at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                    withAttributes: attributes
                )
                ctx.restoreGState()
            }

            if let newPage = PDFKit.PDFDocument(data: data)?.page(at: 0) {
                watermarkedDoc.insert(newPage, at: i)
            }
        }

        return watermarkedDoc
    }

    // MARK: - PDF Editing (Premium Features)

    func duplicateDocument(_ document: StoredPDFDocument) async throws -> StoredPDFDocument {
        guard let pdfDocument = try? await loadPDFDocument(for: document) else {
            throw DocumentError.loadFailed
        }

        let newDocument = createDocument(
            name: "\(document.name ?? "Document") Copy",
            fileName: "copy_\(UUID().uuidString).pdf",
            pdfDocument: pdfDocument
        )

        if let data = pdfDocument.dataRepresentation() {
            try await savePDFData(data, for: newDocument)
        }

        return newDocument
    }

    func rotatePage(in pdfDocument: PDFKit.PDFDocument, pageIndex: Int, rotation: Int) {
        guard let page = pdfDocument.page(at: pageIndex) else { return }
        page.rotation += rotation
    }

    func reorderPages(in pdfDocument: PDFKit.PDFDocument, from sourceIndex: Int, to destinationIndex: Int) {
        let originalCount = pdfDocument.pageCount

        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < originalCount,
              destinationIndex >= 0, destinationIndex <= originalCount,
              let page = pdfDocument.page(at: sourceIndex) else {
            return
        }

        pdfDocument.removePage(at: sourceIndex)

        var targetIndex = destinationIndex
        if destinationIndex > sourceIndex {
            targetIndex -= 1
        }
        targetIndex = max(0, min(targetIndex, pdfDocument.pageCount))

        pdfDocument.insert(page, at: targetIndex)
    }

    func deletePage(in pdfDocument: PDFKit.PDFDocument, at index: Int) {
        guard index < pdfDocument.pageCount else { return }
        pdfDocument.removePage(at: index)
    }

    // MARK: - PDF Merging & Splitting

    func mergePDFs(documents: [StoredPDFDocument], outputName: String) async throws -> StoredPDFDocument {
        // Create new merged PDF
        let mergedPDF = PDFKit.PDFDocument()

        // Load and merge each document
        for document in documents {
            guard let pdfDoc = try? await loadPDFDocument(for: document) else {
                throw DocumentError.loadFailed
            }

            // Add all pages from this document
            for pageIndex in 0..<pdfDoc.pageCount {
                if let page = pdfDoc.page(at: pageIndex) {
                    mergedPDF.insert(page, at: mergedPDF.pageCount)
                }
            }
        }

        // Save merged document
        guard let data = mergedPDF.dataRepresentation() else {
            throw DocumentError.exportFailed
        }

        let fileName = "\(UUID().uuidString).pdf"
        let newDocument = createDocument(
            name: outputName,
            fileName: fileName,
            pdfDocument: mergedPDF
        )

        try await savePDFData(data, for: newDocument)
        loadDocuments() // Refresh documents list

        return newDocument
    }

    func splitPDF(document: StoredPDFDocument, splitRanges: [(start: Int, end: Int)], baseFileName: String) async throws -> [StoredPDFDocument] {
        guard let pdfDocument = try? await loadPDFDocument(for: document) else {
            throw DocumentError.loadFailed
        }

        var splitDocuments: [StoredPDFDocument] = []

        for (index, range) in splitRanges.enumerated() {
            let splitPDF = PDFKit.PDFDocument()

            // Add pages in the specified range
            for pageIndex in range.start...range.end {
                if pageIndex < pdfDocument.pageCount,
                   let page = pdfDocument.page(at: pageIndex) {
                    splitPDF.insert(page, at: splitPDF.pageCount)
                }
            }

            // Save split document
            guard let data = splitPDF.dataRepresentation() else {
                throw DocumentError.exportFailed
            }

            let fileName = "\(UUID().uuidString).pdf"
            let documentName = "\(baseFileName) - Part \(index + 1)"

            let newDocument = createDocument(
                name: documentName,
                fileName: fileName,
                pdfDocument: splitPDF
            )

            try await savePDFData(data, for: newDocument)
            splitDocuments.append(newDocument)
        }

        // Refresh documents list to show new split documents
        loadDocuments()

        return splitDocuments
    }

    func splitPDFByPages(document: StoredPDFDocument, baseFileName: String) async throws -> [StoredPDFDocument] {
        guard let pdfDocument = try? await loadPDFDocument(for: document) else {
            throw DocumentError.loadFailed
        }

        var splitRanges: [(start: Int, end: Int)] = []
        for i in 0..<pdfDocument.pageCount {
            splitRanges.append((start: i, end: i))
        }

        return try await splitPDF(document: document, splitRanges: splitRanges, baseFileName: baseFileName)
    }

    // MARK: - Helper Methods

    func saveContext() {
        persistenceController.save()
    }

    func refreshDocuments() {
        loadDocuments()
    }
}

// MARK: - Document Camera Delegate

extension DocumentManager: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        var images: [UIImage] = []

        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            images.append(image)
        }

        controller.dismiss(animated: true) {
            Task {
                do {
                    _ = try await self.createPDFFromImages(images)
                } catch {
                    self.errorMessage = "Failed to create PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true) {
            self.errorMessage = "Document scanning failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Errors

enum DocumentError: LocalizedError {
    case accessDenied
    case invalidPDF
    case fileNotFound
    case loadFailed
    case saveFailed
    case exportFailed
    case fileTooLarge(maxSizeMB: Int)
    case emptyPDF
    case corruptedPDF

    static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024  // 50 MB

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to the file was denied"
        case .invalidPDF:
            return "The file is not a valid PDF"
        case .fileNotFound:
            return "The PDF file could not be found"
        case .loadFailed:
            return "Failed to load the PDF document"
        case .saveFailed:
            return "Failed to save the PDF document"
        case .exportFailed:
            return "Failed to export the PDF document"
        case .fileTooLarge(let maxSizeMB):
            return "This file exceeds the \(maxSizeMB) MB limit. Please choose a smaller file."
        case .emptyPDF:
            return "This PDF has no pages"
        case .corruptedPDF:
            return "This PDF appears to be corrupted and cannot be opened"
        }
    }
}
