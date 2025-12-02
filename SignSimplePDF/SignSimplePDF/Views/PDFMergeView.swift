import SwiftUI
import PDFKit

struct PDFMergeView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDocuments: Set<StoredPDFDocument> = []
    @State private var mergedDocumentName = "Merged Document"
    @State private var isProcessing = false
    @State private var showingNameAlert = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var reorderableDocuments: [StoredPDFDocument] = []

    var body: some View {
        NavigationView {
            VStack {
                if !subscriptionManager.canUseAdvancedEditing {
                    premiumRequiredView
                } else {
                    mergeContentView
                }
            }
            .navigationTitle("Merge PDFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Removed Cancel button - users can swipe down to dismiss
                if subscriptionManager.canUseAdvancedEditing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Merge") {
                            if selectedDocuments.count >= 2 {
                                showingNameAlert = true
                            }
                        }
                        .disabled(selectedDocuments.count < 2 || isProcessing)
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert("Name Your Merged PDF", isPresented: $showingNameAlert) {
                TextField("Document name", text: $mergedDocumentName)
                Button("Merge") {
                    Task {
                        await performMerge()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for the merged document")
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onChange(of: errorMessage) { newValue in
                showingErrorAlert = newValue != nil
            }
        }
    }

    private var premiumRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.premium)

            Text("Premium Feature")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Merge multiple PDFs into one document with Premium")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                subscriptionManager.presentPaywall()
            } label: {
                Text("Unlock Premium")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(AppTheme.Colors.premium)
                    .cornerRadius(12)
            }
        }
    }

    private var mergeContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Label("Select PDFs to merge", systemImage: "info.circle")
                    .font(.headline)
                Text("Select at least 2 documents. They will be merged in the order shown.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            // Document selection list
            if reorderableDocuments.isEmpty {
                List {
                    ForEach(documentManager.documents) { document in
                        DocumentSelectionRow(
                            document: document,
                            isSelected: selectedDocuments.contains(document)
                        ) {
                            toggleDocumentSelection(document)
                        }
                    }
                }
            } else {
                // Reorderable list after selection
                List {
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(reorderableDocuments) { document in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading) {
                                Text(document.name ?? "Untitled")
                                    .font(.body)
                                Text("\(document.pageCount) pages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                removeFromSelection(document)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveDocuments)
                }
                .environment(\.editMode, .constant(.active))
            }

            // Status bar
            HStack {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Merging...")
                        .font(.caption)
                } else {
                    Text("\(selectedDocuments.count) documents selected")
                        .font(.caption)
                }

                Spacer()

                if selectedDocuments.count >= 2 && !reorderableDocuments.isEmpty {
                    Button("Reset") {
                        resetSelection()
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
    }

    private func toggleDocumentSelection(_ document: StoredPDFDocument) {
        withAnimation(.spring()) {
            if selectedDocuments.contains(document) {
                selectedDocuments.remove(document)
                reorderableDocuments.removeAll { $0 == document }
            } else {
                selectedDocuments.insert(document)
                reorderableDocuments.append(document)
            }

            // Show reorderable list when we have at least 2 documents
            if selectedDocuments.count < 2 {
                reorderableDocuments = []
            }
        }
    }

    private func removeFromSelection(_ document: StoredPDFDocument) {
        withAnimation(.spring()) {
            selectedDocuments.remove(document)
            reorderableDocuments.removeAll { $0 == document }

            if selectedDocuments.count < 2 {
                reorderableDocuments = []
            }
        }
    }

    private func resetSelection() {
        withAnimation(.spring()) {
            selectedDocuments.removeAll()
            reorderableDocuments.removeAll()
        }
    }

    private func moveDocuments(from source: IndexSet, to destination: Int) {
        reorderableDocuments.move(fromOffsets: source, toOffset: destination)
    }

    private func performMerge() async {
        isProcessing = true
        errorMessage = nil

        do {
            // Use reorderable array if available, otherwise use selected set
            let documentsToMerge = reorderableDocuments.isEmpty
                ? Array(selectedDocuments)
                : reorderableDocuments

            let _ = try await documentManager.mergePDFs(
                documents: documentsToMerge,
                outputName: mergedDocumentName
            )

            // Success
            await MainActor.run {
                HapticManager.shared.success()
                ReviewRequestManager.shared.recordPremiumFeatureUsed()
                dismiss()
            }
        } catch {
            await MainActor.run {
                HapticManager.shared.error()
                errorMessage = "Failed to merge documents: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}

struct DocumentSelectionRow: View {
    let document: StoredPDFDocument
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppTheme.Colors.primary : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name ?? "Untitled")
                        .font(.body)
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        Label("\(document.pageCount) pages", systemImage: "doc.text")
                        if let date = document.createdAt {
                            Label(date.formatted(.relative(presentation: .named)), systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PDFMergeView_Previews: PreviewProvider {
    static var previews: some View {
        PDFMergeView()
            .environmentObject(DocumentManager())
            .environmentObject(SubscriptionManager())
    }
}