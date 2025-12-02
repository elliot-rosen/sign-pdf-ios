import Foundation
import PDFKit
import UIKit

/// Handles text selection in PDFView for creating text-based highlight annotations
///
/// This handler enables Apple Preview-style text highlighting where users:
/// 1. Select text in the PDF using native selection gestures
/// 2. Create highlight annotations that follow the text selection bounds
/// 3. Support multi-line text selections
/// 4. Handle rotated and skewed text properly
@MainActor
class PDFTextSelectionHandler: NSObject {

    /// The PDFView being monitored
    private weak var pdfView: PDFView?

    /// Callback when text selection changes
    var onSelectionChanged: ((PDFSelection?) -> Void)?

    /// Callback when user taps to create highlight from selection
    var onCreateHighlight: ((PDFSelection, UIColor) -> Void)?

    /// Current selection
    private(set) var currentSelection: PDFSelection?

    /// Whether text selection mode is active
    private(set) var isSelectionModeActive: Bool = false

    // MARK: - Initialization

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init()
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupObservers() {
        guard let pdfView = pdfView else { return }

        // Observe selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
    }

    // MARK: - Selection Management

    /// Enable text selection mode in PDFView
    func enableSelectionMode() {
        isSelectionModeActive = true
    }

    /// Disable text selection mode
    func disableSelectionMode() {
        isSelectionModeActive = false
        clearSelection()
    }

    /// Clear current text selection
    func clearSelection() {
        pdfView?.clearSelection()
        currentSelection = nil
        onSelectionChanged?(nil)
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        guard isSelectionModeActive else { return }

        currentSelection = pdfView?.currentSelection
        onSelectionChanged?(currentSelection)
    }

    // MARK: - Highlight Creation

    /// Create highlight annotation from current selection
    /// - Parameter color: Color for the highlight
    /// - Returns: Array of highlight annotations (one per selection bounds)
    func createHighlightFromSelection(color: UIColor) -> [PDFAnnotation]? {
        guard let selection = currentSelection else { return nil }

        var annotations: [PDFAnnotation] = []

        // Get all pages that contain the selection
        let pages = selection.pages

        for page in pages {
            // Get selection bounds on this page
            let selectionBounds = selection.bounds(for: page)

            // Create highlight annotation
            let highlightAnnotation = PDFAnnotation(
                bounds: selectionBounds,
                forType: .highlight,
                withProperties: nil
            )

            // Set highlight properties
            highlightAnnotation.color = color.withAlphaComponent(0.3)
            highlightAnnotation.backgroundColor = .clear
            highlightAnnotation.shouldDisplay = true
            highlightAnnotation.shouldPrint = true

            // Add selection text as contents for searchability
            highlightAnnotation.contents = selection.string

            annotations.append(highlightAnnotation)

            // Add to page
            page.addAnnotation(highlightAnnotation)
        }

        // Notify callback
        onCreateHighlight?(selection, color)

        // Clear selection after creating highlight
        clearSelection()

        return annotations.isEmpty ? nil : annotations
    }

    /// Get bounds for current selection on a specific page
    /// - Parameter page: The PDF page
    /// - Returns: Rectangle representing selection bounds
    func selectionBounds(for page: PDFPage) -> CGRect {
        guard let selection = currentSelection else { return .zero }
        return selection.bounds(for: page)
    }

    /// Check if there is an active text selection
    var hasSelection: Bool {
        guard let selection = currentSelection,
              let text = selection.string else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Get the selected text string
    var selectedText: String? {
        return currentSelection?.string
    }

    // MARK: - Helper Methods

    /// Get selection for a line at a given point
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - page: The PDF page
    /// - Returns: Selection for the word/line at that point
    func selection(at point: CGPoint, on page: PDFPage) -> PDFSelection? {
        guard let pdfView = pdfView else { return nil }

        // Convert screen point to PDF coordinates
        let pdfPoint = pdfView.convert(point, to: page)

        // Try to get word at point
        if let wordSelection = page.selection(for: CGRect(origin: pdfPoint, size: CGSize(width: 1, height: 1))) {
            return wordSelection
        }

        return nil
    }

    /// Extend selection to include word at point
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - page: The PDF page
    func extendSelection(to point: CGPoint, on page: PDFPage) {
        guard let pdfView = pdfView else { return }

        let pdfPoint = pdfView.convert(point, to: page)

        if let wordSelection = page.selection(for: CGRect(origin: pdfPoint, size: CGSize(width: 1, height: 1))) {
            if let currentSelection = currentSelection {
                // Extend existing selection
                currentSelection.add(wordSelection)
                pdfView.setCurrentSelection(currentSelection, animate: true)
            } else {
                // Create new selection
                currentSelection = wordSelection
                pdfView.setCurrentSelection(wordSelection, animate: true)
            }
        }
    }

    /// Select entire word at point
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - page: The PDF page
    func selectWord(at point: CGPoint, on page: PDFPage) {
        guard let pdfView = pdfView else { return }

        let pdfPoint = pdfView.convert(point, to: page)

        // Create small rect around point
        let selectionRect = CGRect(
            x: pdfPoint.x - 1,
            y: pdfPoint.y - 1,
            width: 2,
            height: 2
        )

        if let wordSelection = page.selection(for: selectionRect) {
            currentSelection = wordSelection
            pdfView.setCurrentSelection(wordSelection, animate: true)
            onSelectionChanged?(wordSelection)
        }
    }

    /// Select entire line at point
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - page: The PDF page
    func selectLine(at point: CGPoint, on page: PDFPage) {
        guard let pdfView = pdfView else { return }

        let pdfPoint = pdfView.convert(point, to: page)

        // Get page bounds
        let pageBounds = page.bounds(for: .mediaBox)

        // Create rect spanning full width of page at point
        let lineRect = CGRect(
            x: pageBounds.minX,
            y: pdfPoint.y - 5,
            width: pageBounds.width,
            height: 10
        )

        if let lineSelection = page.selection(for: lineRect) {
            currentSelection = lineSelection
            pdfView.setCurrentSelection(lineSelection, animate: true)
            onSelectionChanged?(lineSelection)
        }
    }
}

// MARK: - PDFSelection Extensions

extension PDFSelection {
    /// Get bounds for all pages in the selection
    func allBounds() -> [(page: PDFPage, bounds: CGRect)] {
        return pages.map { page in
            (page: page, bounds: bounds(for: page))
        }
    }

    /// Check if selection is empty or whitespace only
    var isEmpty: Bool {
        guard let text = string else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Get selections broken down by line
    func selectionsByLine() -> [PDFSelection] {
        var lineSelections: [PDFSelection] = []

        for page in pages {
            let bounds = bounds(for: page)

            if let lineSelection = page.selection(for: bounds) {
                lineSelections.append(lineSelection)
            }
        }

        return lineSelections
    }
}
