import SwiftUI
import PDFKit
import Combine

// MARK: - PDF View State Monitor

@MainActor
class PDFViewStateMonitor: ObservableObject {
    @Published var updateTrigger: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private weak var pdfView: PDFView?
    private var scaleObservation: NSKeyValueObservation?

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        setupObservers()
    }

    private func setupObservers() {
        guard let pdfView = pdfView else { return }

        print("🔄 [PDFViewStateMonitor] Setting up PDF view observers")

        // Observe visible pages changed (scroll events)
        NotificationCenter.default.publisher(for: .PDFViewVisiblePagesChanged, object: pdfView)
            .sink { [weak self] _ in
                print("   📜 [PDFViewStateMonitor] PDFViewVisiblePagesChanged - Triggering update")
                self?.triggerUpdate()
            }
            .store(in: &cancellables)

        // Observe page changed
        NotificationCenter.default.publisher(for: .PDFViewPageChanged, object: pdfView)
            .sink { [weak self] _ in
                print("   📄 [PDFViewStateMonitor] PDFViewPageChanged - Triggering update")
                self?.triggerUpdate()
            }
            .store(in: &cancellables)

        // Observe scale factor changes (zoom)
        scaleObservation = pdfView.observe(\.scaleFactor, options: [.new]) { [weak self] pdfView, change in
            print("   🔍 [PDFViewStateMonitor] ScaleFactor changed to \(pdfView.scaleFactor) - Triggering update")
            self?.triggerUpdate()
        }
    }

    private func triggerUpdate() {
        updateTrigger += 1
        print("   ⚡ [PDFViewStateMonitor] Update triggered - new trigger value: \(updateTrigger)")
    }

    deinit {
        scaleObservation?.invalidate()
        cancellables.removeAll()
    }
}

struct PDFAnnotationOverlay: View {
    @ObservedObject var annotationManager: AnnotationManager
    let pdfView: PDFView
    let currentPageIndex: Int
    let pdfDocument: PDFDocument

    @StateObject private var viewStateMonitor: PDFViewStateMonitor
    @State private var viewSize: CGSize = .zero

    init(annotationManager: AnnotationManager, pdfView: PDFView, currentPageIndex: Int, pdfDocument: PDFDocument) {
        self.annotationManager = annotationManager
        self.pdfView = pdfView
        self.currentPageIndex = currentPageIndex
        self.pdfDocument = pdfDocument
        self._viewStateMonitor = StateObject(wrappedValue: PDFViewStateMonitor(pdfView: pdfView))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Render all annotations for current page
                // Screen positions recomputed whenever pdfView state changes
                let _ = viewStateMonitor.updateTrigger  // Force dependency

                ForEach(annotationsForCurrentPage) { annotation in
                    if let page = pdfDocument.page(at: annotation.pageIndex) {
                        DraggableAnnotationView(
                            annotation: annotation,
                            annotationManager: annotationManager,
                            pageSize: pageSize,
                            pdfView: pdfView,
                            page: page
                        )
                    }
                }
            }
            .onAppear {
                viewSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                viewSize = newSize
            }
        }
        .allowsHitTesting(true)
    }

    private var annotationsForCurrentPage: [PDFAnnotationItem] {
        annotationManager.annotations.filter { $0.pageIndex == currentPageIndex }
    }

    private var pageSize: CGSize {
        guard let page = pdfView.document?.page(at: currentPageIndex) else {
            return CGSize(width: 612, height: 792) // Default US Letter size
        }
        let bounds = page.bounds(for: .mediaBox)
        return bounds.size
    }

}

// MARK: - Undo/Redo Toolbar

struct UndoRedoToolbar: View {
    @ObservedObject var annotationManager: AnnotationManager

    var body: some View {
        HStack {
            // Undo/Redo buttons
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    HapticManager.shared.buttonTap()
                    annotationManager.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            annotationManager.canUndo ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary.opacity(0.3)
                        )
                }
                .disabled(!annotationManager.canUndo)

                Button {
                    HapticManager.shared.buttonTap()
                    annotationManager.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            annotationManager.canRedo ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary.opacity(0.3)
                        )
                }
                .disabled(!annotationManager.canRedo)
            }

            Spacer()

            // Unsaved changes indicator
            if annotationManager.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.1))
                )
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(AppTheme.Colors.separator),
                    alignment: .bottom
                )
        )
    }
}
