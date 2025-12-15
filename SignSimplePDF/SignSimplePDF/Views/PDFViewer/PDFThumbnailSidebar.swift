import SwiftUI
import PDFKit

struct PDFThumbnailSidebar: View {
    @Binding var pdfDocument: PDFDocument?
    @Binding var currentPageIndex: Int
    let onReorder: (Int, Int) -> Void
    let onDelete: (Int) -> Void
    let onDocumentChanged: () -> Void

    @State private var draggedPageIndex: Int?
    @State private var dropTargetIndex: Int?
    @State private var refreshToken = UUID()

    private var pageCount: Int {
        pdfDocument?.pageCount ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pages")
                    .font(AppTheme.Typography.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                Spacer()

                Text("\(pageCount)")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)

            Divider()

            // Thumbnail list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(Array(0..<pageCount), id: \.self) { index in
                            ThumbnailCell(
                                pdfDocument: pdfDocument,
                                pageIndex: index,
                                isSelected: index == currentPageIndex,
                                isDragging: draggedPageIndex == index,
                                isDropTarget: dropTargetIndex == index && draggedPageIndex != index,
                                refreshToken: refreshToken
                            )
                            .id("\(refreshToken)-\(index)")
                            .onTapGesture {
                                HapticManager.shared.selection()
                                currentPageIndex = index
                            }
                            .onDrag {
                                draggedPageIndex = index
                                return NSItemProvider(object: String(index) as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ThumbnailDropDelegate(
                                    pageIndex: index,
                                    draggedPageIndex: $draggedPageIndex,
                                    dropTargetIndex: $dropTargetIndex,
                                    onReorder: handleReorder
                                )
                            )
                            .contextMenu {
                                if pageCount > 1 {
                                    Button(role: .destructive) {
                                        handleDelete(at: index)
                                    } label: {
                                        Label("Delete Page", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.sm)
                }
                .onChange(of: currentPageIndex) { _, newValue in
                    withAnimation {
                        proxy.scrollTo("\(refreshToken)-\(newValue)", anchor: .center)
                    }
                }
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    private func handleReorder(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }

        // Call parent's reorder function
        onReorder(sourceIndex, destinationIndex)

        // Update current page index to follow the moved page
        if currentPageIndex == sourceIndex {
            // The dragged page - it moves to the destination
            if destinationIndex > sourceIndex {
                currentPageIndex = destinationIndex - 1
            } else {
                currentPageIndex = destinationIndex
            }
        } else if sourceIndex < currentPageIndex && destinationIndex >= currentPageIndex {
            currentPageIndex -= 1
        } else if sourceIndex > currentPageIndex && destinationIndex <= currentPageIndex {
            currentPageIndex += 1
        }

        // Force rebuild of entire list
        refreshToken = UUID()
        onDocumentChanged()
    }

    private func handleDelete(at index: Int) {
        // Call parent's delete function
        onDelete(index)

        // Adjust current page index
        let newCount = pdfDocument?.pageCount ?? 0
        if currentPageIndex >= newCount && newCount > 0 {
            currentPageIndex = newCount - 1
        } else if index < currentPageIndex {
            currentPageIndex -= 1
        }

        // Force rebuild of entire list
        refreshToken = UUID()
        onDocumentChanged()
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let pdfDocument: PDFDocument?
    let pageIndex: Int
    let isSelected: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let refreshToken: UUID

    @State private var thumbnail: UIImage?

    private var borderColor: Color {
        if isDropTarget {
            return AppTheme.Colors.success
        } else if isSelected {
            return AppTheme.Colors.primary
        } else {
            return AppTheme.Colors.textTertiary.opacity(0.3)
        }
    }

    private var borderWidth: CGFloat {
        (isDropTarget || isSelected) ? 2 : 1
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            // Drop indicator line above
            if isDropTarget {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.Colors.success)
                    .frame(height: 4)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .transition(.opacity)
            }

            // Thumbnail image
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle()
                        .fill(AppTheme.Colors.surface)
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .frame(width: 80, height: 100)
            .background(Color.white)
            .cornerRadius(AppTheme.CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xs)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 4 : 2, x: 0, y: 1)
            .scaleEffect(isDropTarget ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isDropTarget)

            // Page number
            Text("\(pageIndex + 1)")
                .font(AppTheme.Typography.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .onAppear {
            generateThumbnail()
        }
        .onChange(of: refreshToken) { _, _ in
            // Regenerate thumbnail when document changes
            thumbnail = nil
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard let page = pdfDocument?.page(at: pageIndex) else {
            thumbnail = nil
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let thumbnailImage = page.thumbnail(of: CGSize(width: 160, height: 200), for: .cropBox)

            DispatchQueue.main.async {
                self.thumbnail = thumbnailImage
            }
        }
    }
}

// MARK: - Drop Delegate

struct ThumbnailDropDelegate: DropDelegate {
    let pageIndex: Int
    @Binding var draggedPageIndex: Int?
    @Binding var dropTargetIndex: Int?
    let onReorder: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceIndex = draggedPageIndex else { return false }

        if sourceIndex != pageIndex {
            HapticManager.shared.importantAction()
            onReorder(sourceIndex, pageIndex)
        }

        draggedPageIndex = nil
        dropTargetIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let sourceIndex = draggedPageIndex,
              sourceIndex != pageIndex else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            dropTargetIndex = pageIndex
        }
        HapticManager.shared.selection()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if dropTargetIndex == pageIndex {
                dropTargetIndex = nil
            }
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggedPageIndex != nil
    }
}

#Preview {
    HStack {
        PDFThumbnailSidebar(
            pdfDocument: .constant(nil),
            currentPageIndex: .constant(0),
            onReorder: { _, _ in },
            onDelete: { _ in },
            onDocumentChanged: { }
        )
        .frame(width: 120)

        Spacer()
    }
}
