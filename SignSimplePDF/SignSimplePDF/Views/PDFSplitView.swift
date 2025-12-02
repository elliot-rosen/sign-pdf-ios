import SwiftUI
import PDFKit

struct PDFSplitView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDocument: StoredPDFDocument?
    @State private var splitMode: SplitMode = .everyPage
    @State private var customRanges: [PageRange] = []
    @State private var baseFileName = "Split Document"
    @State private var isProcessing = false
    @State private var showingDocumentPicker = true
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var previewPages: [Int] = []
    @State private var currentRange = PageRange()

    enum SplitMode: String, CaseIterable {
        case everyPage = "Every Page"
        case customRanges = "Custom Ranges"

        var description: String {
            switch self {
            case .everyPage:
                return "Split into individual pages"
            case .customRanges:
                return "Define custom page ranges"
            }
        }

        var icon: String {
            switch self {
            case .everyPage:
                return "rectangle.split.1x2"
            case .customRanges:
                return "rectangle.split.3x1"
            }
        }
    }

    struct PageRange: Identifiable, Equatable {
        let id = UUID()
        var startPage: String = ""
        var endPage: String = ""

        var isValid: Bool {
            guard let start = Int(startPage),
                  let end = Int(endPage),
                  start > 0,
                  end > 0,
                  start <= end else { return false }
            return true
        }

        var displayText: String {
            if startPage.isEmpty && endPage.isEmpty {
                return "New range"
            } else if startPage == endPage {
                return "Page \(startPage)"
            } else {
                return "Pages \(startPage)-\(endPage)"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if !subscriptionManager.canUseAdvancedEditing {
                    premiumRequiredView
                } else if selectedDocument == nil {
                    documentSelectionView
                } else {
                    splitConfigurationView
                }
            }
            .navigationTitle("Split PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Removed Cancel button - users can swipe down to dismiss
                if subscriptionManager.canUseAdvancedEditing && selectedDocument != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Split") {
                            Task {
                                await performSplit()
                            }
                        }
                        .disabled(!canSplit || isProcessing)
                        .fontWeight(.semibold)
                    }
                }
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
            Image(systemName: "scissors")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.premium)

            Text("Premium Feature")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Split PDFs into multiple documents with Premium")
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

    private var documentSelectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.primary)

            Text("Select a PDF to Split")
                .font(.title2)
                .fontWeight(.semibold)

            List {
                ForEach(documentManager.documents) { document in
                    Button {
                        selectDocument(document)
                    } label: {
                        HStack {
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

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var splitConfigurationView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Selected document info
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(AppTheme.Colors.primary)

                VStack(alignment: .leading) {
                    Text(selectedDocument?.name ?? "Untitled")
                        .font(.headline)
                    Text("\(selectedDocument?.pageCount ?? 0) pages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Change") {
                    selectedDocument = nil
                }
                .font(.caption)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            // Split mode selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Split Mode")
                    .font(.headline)

                ForEach(SplitMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring()) {
                            splitMode = mode
                            if mode == .customRanges && customRanges.isEmpty {
                                customRanges = [PageRange()]
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                                .frame(width: 30)

                            VStack(alignment: .leading) {
                                Text(mode.rawValue)
                                    .font(.body)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: splitMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(splitMode == mode ? AppTheme.Colors.primary : .secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            // Custom ranges configuration
            if splitMode == .customRanges {
                customRangesView
            }

            // Preview
            previewSection

            Spacer()

            // Base file name
            VStack(alignment: .leading, spacing: 8) {
                Text("Base File Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Enter base name", text: $baseFileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Text(previewFileNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
    }

    @ViewBuilder
    private var customRangesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Page Ranges")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation {
                        customRanges.append(PageRange())
                    }
                } label: {
                    Label("Add Range", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
            }

            ForEach(customRanges, id: \.id) { range in
                if let index = customRanges.firstIndex(where: { $0.id == range.id }) {
                    HStack {
                        TextField("Start", text: $customRanges[index].startPage)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)

                        Text("to")
                            .foregroundColor(.secondary)

                        TextField("End", text: $customRanges[index].endPage)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)

                        Spacer()

                        Text(range.displayText)
                            .font(.caption)
                            .foregroundColor(range.isValid ? .secondary : .red)

                        Button {
                            withAnimation {
                                customRanges.removeAll { $0.id == range.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(splitPreview.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.systemFill))
                                .frame(width: 60, height: 80)
                                .overlay(
                                    VStack {
                                        Image(systemName: "doc.text")
                                            .foregroundColor(.secondary)
                                        Text("\(splitPreview[index].count)p")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                )

                            Text("Part \(index + 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var splitPreview: [[Int]] {
        guard let document = selectedDocument else { return [] }
        let pageCount = Int(document.pageCount)

        switch splitMode {
        case .everyPage:
            return (1...pageCount).map { [$0] }

        case .customRanges:
            return customRanges.compactMap { range in
                guard let start = Int(range.startPage),
                      let end = Int(range.endPage),
                      start > 0,
                      end > 0,
                      start <= pageCount,
                      end <= pageCount,
                      start <= end else { return nil }
                return Array(start...end)
            }
        }
    }

    private var previewFileNames: String {
        let count = splitPreview.count
        if count == 0 {
            return "No valid ranges defined"
        } else if count == 1 {
            return "\(baseFileName) - Part 1.pdf"
        } else {
            return "\(baseFileName) - Part 1.pdf, ..., \(baseFileName) - Part \(count).pdf"
        }
    }

    private var canSplit: Bool {
        guard selectedDocument != nil else { return false }

        switch splitMode {
        case .everyPage:
            return true
        case .customRanges:
            return !customRanges.isEmpty && customRanges.allSatisfy { $0.isValid }
        }
    }

    private func selectDocument(_ document: StoredPDFDocument) {
        selectedDocument = document
        baseFileName = "\(document.name ?? "Document") Split"
    }

    private func performSplit() async {
        guard let document = selectedDocument else { return }

        isProcessing = true
        errorMessage = nil

        do {
            switch splitMode {
            case .everyPage:
                let _ = try await documentManager.splitPDFByPages(
                    document: document,
                    baseFileName: baseFileName
                )

            case .customRanges:
                let ranges = customRanges.compactMap { range -> (start: Int, end: Int)? in
                    guard let start = Int(range.startPage),
                          let end = Int(range.endPage) else { return nil }
                    return (start: start - 1, end: end - 1) // Convert to 0-indexed
                }

                let _ = try await documentManager.splitPDF(
                    document: document,
                    splitRanges: ranges,
                    baseFileName: baseFileName
                )
            }

            // Success
            await MainActor.run {
                HapticManager.shared.success()
                ReviewRequestManager.shared.recordPremiumFeatureUsed()
                dismiss()
            }
        } catch {
            await MainActor.run {
                HapticManager.shared.error()
                errorMessage = "Failed to split document: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}

struct PDFSplitView_Previews: PreviewProvider {
    static var previews: some View {
        PDFSplitView()
            .environmentObject(DocumentManager())
            .environmentObject(SubscriptionManager())
    }
}
