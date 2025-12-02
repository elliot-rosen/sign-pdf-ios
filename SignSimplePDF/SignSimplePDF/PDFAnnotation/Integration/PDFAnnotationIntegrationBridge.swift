//
//  PDFAnnotationIntegrationBridge.swift
//  SignSimplePDF
//
//  Bridge file to integrate the new PDF annotation system with existing app components
//

import UIKit
import PDFKit
import CoreData
import SwiftUI
import Combine

// MARK: - PDF Annotation Integration Bridge
/// This bridge helps integrate the new annotation system with the existing app structure
public class PDFAnnotationIntegrationBridge: ObservableObject {
    // MARK: - Properties
    @Published public var isAnnotating = false
    @Published public var currentTool: AnnotationTool = .selection
    @Published public var hasUnsavedChanges = false

    private let annotationEngine: PDFAnnotationEngine
    private let annotationView: PDFAnnotationView
    private let context: NSManagedObjectContext
    private weak var pdfView: PDFView?

    // MARK: - Initialization
    public init(context: NSManagedObjectContext) {
        self.context = context
        self.annotationEngine = PDFAnnotationEngine()
        self.annotationView = PDFAnnotationView(frame: .zero)

        setupBindings()
        configurePersistence()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup
    private func setupBindings() {
        // Use Combine observation instead of delegate
        // The delegate will be assigned to PDFAnnotationView for rendering updates

        // Track unsaved changes via Combine
        annotationEngine.$annotations
            .dropFirst()  // Skip initial empty value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
            }
            .store(in: &cancellables)

        // Also track undo state changes
        annotationEngine.$canUndo
            .combineLatest(annotationEngine.$canRedo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func configurePersistence() {
        annotationEngine.configurePersistence(with: context)
    }

    // MARK: - Public Methods

    /// Configure the bridge with a PDF view from the existing app
    public func configure(with pdfView: PDFView) {
        self.pdfView = pdfView

        // Configure the annotation engine
        annotationEngine.configure(with: pdfView)

        // Configure the annotation view as an overlay, passing the SHARED engine
        // This ensures both Bridge and View use the same engine instance
        annotationView.configureAsOverlay(for: pdfView, engine: annotationEngine)

        // Load document if available
        if let document = pdfView.document {
            // In overlay mode, loadPDF just loads annotations
            annotationView.loadPDF(document)
        }

        // Add annotation view as overlay
        if annotationView.superview == nil {
            pdfView.addSubview(annotationView)
            annotationView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                annotationView.topAnchor.constraint(equalTo: pdfView.topAnchor),
                annotationView.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
                annotationView.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
                annotationView.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor)
            ])
        }
    }

    /// Load annotations for a document
    public func loadDocument(_ document: StoredPDFDocument, pdfDocument: PDFDocument) {
        annotationEngine.setCurrentDocument(document)
        annotationEngine.loadAnnotations(for: pdfDocument)
    }

    /// Save current annotations
    public func save() {
        annotationEngine.saveAnnotations()
        hasUnsavedChanges = false
    }

    /// Export PDF with annotations embedded
    public func exportPDF() -> PDFDocument? {
        return annotationEngine.exportToPDF()
    }

    // MARK: - Tool Selection
    public func selectTool(_ tool: AnnotationTool) {
        currentTool = tool
        annotationView.setCurrentTool(tool)  // This also calls annotationEngine.selectTool and enables touch
        isAnnotating = (tool != .selection)
    }

    // MARK: - Annotation Actions
    public func undo() {
        annotationEngine.undo()
    }

    public func redo() {
        annotationEngine.redo()
    }

    public func deleteSelected() {
        annotationEngine.removeSelectedAnnotation()
    }

    public func clearAll() {
        annotationEngine.clearAll()
    }

    // MARK: - Signature Management
    public func addSignature(_ imageData: Data, at point: CGPoint, on page: Int) {
        annotationEngine.addSignatureAnnotation(at: point, on: page, imageData: imageData)
    }

    // MARK: - Toolbar Creation
    public func createToolbar() -> UIView {
        let toolbar = AnnotationToolbar(frame: CGRect(x: 0, y: 0, width: 500, height: 60))
        toolbar.annotationEngine = annotationEngine
        toolbar.delegate = annotationView  // Connect delegate so tool selection enables touch handling
        return toolbar
    }

    // MARK: - Inspector Creation
    public func createInspector() -> UIView {
        let inspector = PropertyInspector(frame: CGRect(x: 0, y: 0, width: 280, height: 400))
        inspector.annotationEngine = annotationEngine
        return inspector
    }
}

// MARK: - PDFAnnotationEngineDelegate
extension PDFAnnotationIntegrationBridge: PDFAnnotationEngineDelegate {
    public func annotationEngine(_ engine: PDFAnnotationEngine, didAdd annotation: UnifiedAnnotation) {
        hasUnsavedChanges = true
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didUpdate annotation: UnifiedAnnotation) {
        hasUnsavedChanges = true
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didRemove annotation: UnifiedAnnotation) {
        hasUnsavedChanges = true
    }

    public func annotationEngine(_ engine: PDFAnnotationEngine, didSelect annotation: UnifiedAnnotation?) {
        // Handle selection changes if needed
    }

    public func annotationEngineDidChangeUndoState(_ engine: PDFAnnotationEngine) {
        // Update UI if needed
    }
}

// MARK: - SwiftUI Integration
/// SwiftUI View wrapper for the new annotation system
public struct PDFAnnotationViewWrapper: UIViewRepresentable {
    let bridge: PDFAnnotationIntegrationBridge
    let pdfView: PDFView

    public init(bridge: PDFAnnotationIntegrationBridge, pdfView: PDFView) {
        self.bridge = bridge
        self.pdfView = pdfView
    }

    public func makeUIView(context: Context) -> UIView {
        bridge.configure(with: pdfView)
        return UIView() // Return empty view as the annotation view is added directly to PDFView
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

// MARK: - Migration Helper
public extension PDFAnnotationIntegrationBridge {
    /// Migrate from old annotation system to new
    func migrateOldAnnotations(from document: StoredPDFDocument) {
        let persistenceManager = PDFAnnotationPersistenceManager(context: context)

        do {
            let migratedAnnotations = try persistenceManager.migrateOldAnnotations(from: document)

            // Add migrated annotations to engine
            for annotation in migratedAnnotations {
                annotationEngine.addAnnotation(annotation)
            }

            // Save the migrated annotations
            save()

            print("✅ Successfully migrated \(migratedAnnotations.count) annotations")
        } catch {
            print("❌ Failed to migrate annotations: \(error)")
        }
    }
}

// MARK: - Existing App Integration Points
public extension PDFAnnotationIntegrationBridge {
    /// Called from PDFEditingView to setup annotation mode
    func enableAnnotationMode(for document: StoredPDFDocument, pdfDocument: PDFDocument, in pdfView: PDFView) {
        configure(with: pdfView)
        loadDocument(document, pdfDocument: pdfDocument)
        isAnnotating = true
    }

    /// Called to disable annotation mode
    func disableAnnotationMode() {
        if hasUnsavedChanges {
            save()
        }
        isAnnotating = false
        selectTool(.selection)
    }

    /// Get current annotation count for display
    var annotationCount: Int {
        annotationEngine.annotations.count
    }

    /// Check if undo/redo available
    var canUndo: Bool {
        annotationEngine.canUndo
    }

    var canRedo: Bool {
        annotationEngine.canRedo
    }
}

// MARK: - Usage Example
/*
 Integration in your SwiftUI view:

 ```swift
 struct YourPDFView: View {
     @StateObject private var annotationBridge: PDFAnnotationIntegrationBridge

     init(context: NSManagedObjectContext) {
         _annotationBridge = StateObject(wrappedValue: PDFAnnotationIntegrationBridge(context: context))
     }
     ...
 }
 ```
 */