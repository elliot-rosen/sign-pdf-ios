//
//  TextDetection.swift
//  SignSimplePDF
//
//  Text detection for smart highlighting
//

import UIKit
import PDFKit
import Vision

// MARK: - Text Detection Engine
public class TextDetectionEngine {
    // MARK: - Properties
    private weak var pdfView: PDFView?
    private let textRecognitionQueue = DispatchQueue(label: "com.signsimplepdf.textrecognition", qos: .userInitiated)

    // MARK: - Configuration
    public func configure(with pdfView: PDFView) {
        self.pdfView = pdfView
    }

    // MARK: - Text Detection
    public func detectText(at point: CGPoint, on page: PDFPage, completion: @escaping ([CGRect]) -> Void) {
        // First try native PDFKit text detection
        if let textBounds = detectTextWithPDFKit(at: point, on: page) {
            completion(textBounds)
            return
        }

        // Fall back to Vision framework
        detectTextWithVision(at: point, on: page, completion: completion)
    }

    // MARK: - PDFKit Text Detection
    private func detectTextWithPDFKit(at point: CGPoint, on page: PDFPage) -> [CGRect]? {
        // Get selection at point
        if let selection = page.selectionForWord(at: point) {
            let bounds = selection.bounds(for: page)
            return [bounds]
        }

        // Try line selection
        if let selection = page.selectionForLine(at: point) {
            let bounds = selection.bounds(for: page)
            return [bounds]
        }

        return nil
    }

    // MARK: - Vision Framework Text Detection
    private func detectTextWithVision(at point: CGPoint, on page: PDFPage, completion: @escaping ([CGRect]) -> Void) {
        textRecognitionQueue.async { [weak self] in
            guard let self = self else { return }

            // Render page to image
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)

            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(bounds)

                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)

                page.draw(with: .mediaBox, to: context.cgContext)
            }

            // Create Vision request
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                // Find text near the tap point
                let normalizedPoint = CGPoint(
                    x: point.x / bounds.width,
                    y: 1 - (point.y / bounds.height)
                )

                var textBounds: [CGRect] = []

                for observation in observations {
                    let observationBounds = observation.boundingBox

                    // Check if point is within this text
                    if observationBounds.contains(normalizedPoint) {
                        // Convert to PDF coordinates
                        let rect = CGRect(
                            x: observationBounds.minX * bounds.width,
                            y: (1 - observationBounds.maxY) * bounds.height,
                            width: observationBounds.width * bounds.width,
                            height: observationBounds.height * bounds.height
                        )
                        textBounds.append(rect)
                    }
                }

                DispatchQueue.main.async {
                    completion(textBounds)
                }
            }

            request.recognitionLevel = .accurate

            // Process image
            guard let cgImage = image.cgImage else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Smart Text Selection
    public func selectTextBetween(start: CGPoint, end: CGPoint, on page: PDFPage) -> [CGRect] {
        // Create selection between two points
        guard let selection = page.selection(from: start, to: end) else { return [] }

        var bounds: [CGRect] = []

        // Get bounds for each line in selection
        for selectionPage in selection.selectionsByLine() {
            bounds.append(selectionPage.bounds(for: page))
        }

        return bounds
    }

    // MARK: - Word/Line Detection
    public func getWordBounds(at point: CGPoint, on page: PDFPage) -> CGRect? {
        return page.selectionForWord(at: point)?.bounds(for: page)
    }

    public func getLineBounds(at point: CGPoint, on page: PDFPage) -> CGRect? {
        return page.selectionForLine(at: point)?.bounds(for: page)
    }

    // MARK: - Paragraph Detection
    public func getParagraphBounds(at point: CGPoint, on page: PDFPage) -> [CGRect] {
        var bounds: [CGRect] = []

        // Start from the line at point
        guard var currentSelection = page.selectionForLine(at: point) else { return [] }
        bounds.append(currentSelection.bounds(for: page))

        // Expand upward
        var currentY = point.y
        while currentY > 0 {
            currentY -= 20  // Move up by line height estimate
            let testPoint = CGPoint(x: point.x, y: currentY)

            if let lineSelection = page.selectionForLine(at: testPoint) {
                let lineBounds = lineSelection.bounds(for: page)

                // Check if this is part of the same paragraph (small vertical gap)
                if let lastBounds = bounds.last {
                    let gap = abs(lineBounds.maxY - lastBounds.minY)
                    if gap < 30 {
                        bounds.insert(lineBounds, at: 0)
                    } else {
                        break  // Paragraph boundary
                    }
                }
            } else {
                break  // No text found
            }
        }

        // Expand downward
        currentY = point.y
        let pageHeight = page.bounds(for: .mediaBox).height
        while currentY < pageHeight {
            currentY += 20  // Move down by line height estimate
            let testPoint = CGPoint(x: point.x, y: currentY)

            if let lineSelection = page.selectionForLine(at: testPoint) {
                let lineBounds = lineSelection.bounds(for: page)

                // Check if this is part of the same paragraph
                if let lastBounds = bounds.last {
                    let gap = abs(lineBounds.minY - lastBounds.maxY)
                    if gap < 30 {
                        bounds.append(lineBounds)
                    } else {
                        break  // Paragraph boundary
                    }
                }
            } else {
                break  // No text found
            }
        }

        return bounds
    }
}

// MARK: - Highlight Helper
public extension TextDetectionEngine {
    func createSmartHighlight(at point: CGPoint, on page: PDFPage, mode: HighlightMode) -> [CGRect] {
        switch mode {
        case .word:
            if let bounds = getWordBounds(at: point, on: page) {
                return [bounds]
            }
        case .line:
            if let bounds = getLineBounds(at: point, on: page) {
                return [bounds]
            }
        case .paragraph:
            return getParagraphBounds(at: point, on: page)
        }
        return []
    }

    enum HighlightMode {
        case word, line, paragraph
    }
}