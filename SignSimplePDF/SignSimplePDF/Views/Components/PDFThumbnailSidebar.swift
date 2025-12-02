import SwiftUI
import PDFKit

struct PDFThumbnailSidebar: View {
    let pdfDocument: PDFKit.PDFDocument
    @Binding var selectedPage: PDFPage?
    @Binding var pdfView: PDFView?
    
    // Actions
    var onRotate: (PDFPage, Int) -> Void
    var onDelete: (PDFPage) -> Void
    var onReorder: (Int, Int) -> Void
    
    @State private var thumbnails: [Int: UIImage] = [:]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<pdfDocument.pageCount, id: \.self) { index in
                        if let page = pdfDocument.page(at: index) {
                            ThumbnailCell(
                                page: page,
                                pageIndex: index + 1,
                                isSelected: selectedPage == page,
                                image: thumbnails[index]
                            )
                            .id(index)
                            .onAppear {
                                generateThumbnail(for: page, at: index)
                            }
                            .onTapGesture {
                                selectedPage = page
                                if let pdfView = pdfView {
                                    pdfView.go(to: page)
                                }
                            }
                            .contextMenu {
                                Button {
                                    onRotate(page, -90)
                                    updateThumbnail(at: index)
                                } label: {
                                    Label("Rotate Left", systemImage: "rotate.left")
                                }
                                
                                Button {
                                    onRotate(page, 90)
                                    updateThumbnail(at: index)
                                } label: {
                                    Label("Rotate Right", systemImage: "rotate.right")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    onDelete(page)
                                    // Force refresh logic handled by parent usually
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            // Simple Drag and Drop hook
                            .onDrag {
                                NSItemProvider(object: String(index) as NSString)
                            }
                            .onDrop(of: [.text], delegate: PageDropDelegate(
                                currentIndex: index,
                                onReorder: { src, dst in
                                    onReorder(src, dst)
                                    // Clear thumbnails to force regenerate after reorder
                                    thumbnails = [:] 
                                }
                            ))
                        }
                    }
                }
                .padding()
            }
            .onChange(of: selectedPage) { newPage in
                if let page = newPage, let index = pdfDocument.index(for: page) as Int? {
                    withAnimation {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
    
    private func generateThumbnail(for page: PDFPage, at index: Int) {
        // Simple cache check
        if thumbnails[index] != nil { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let size = CGSize(width: 100, height: 140) // Aspect ratio approximate
            let thumbnail = page.thumbnail(of: size, for: .cropBox)
            
            DispatchQueue.main.async {
                self.thumbnails[index] = thumbnail
            }
        }
    }
    
    private func updateThumbnail(at index: Int) {
        // Invalidate cache for this index
        thumbnails[index] = nil
        if let page = pdfDocument.page(at: index) {
            generateThumbnail(for: page, at: index)
        }
    }
}

struct ThumbnailCell: View {
    let page: PDFPage
    let pageIndex: Int
    let isSelected: Bool
    let image: UIImage?
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    ProgressView()
                }
            }
            .frame(width: 80, height: 110) // Fixed width thumbnail
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            
            Text("\(pageIndex)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct PageDropDelegate: DropDelegate {
    let currentIndex: Int
    let onReorder: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        
        item.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
            if let data = data as? Data,
               let sourceIndexString = String(data: data, encoding: .utf8),
               let sourceIndex = Int(sourceIndexString),
               sourceIndex != currentIndex {
                
                DispatchQueue.main.async {
                    onReorder(sourceIndex, currentIndex)
                }
            }
        }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback could go here
    }
}
