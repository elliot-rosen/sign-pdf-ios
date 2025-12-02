import Foundation
import UIKit
import PDFKit
import Combine
import Darwin

// MARK: - Memory Manager

class MemoryManager: ObservableObject {

    static let shared = MemoryManager()

    // Memory thresholds
    private let maxPDFSizeInMemory: Int64 = 50 * 1024 * 1024  // 50MB
    private let warningMemoryThreshold: Float = 0.8  // 80% memory usage
    private let criticalMemoryThreshold: Float = 0.9  // 90% memory usage

    // Cache management
    private var pdfCache = NSCache<NSString, PDFDocument>()
    private var thumbnailCache = NSCache<NSString, UIImage>()
    private var cancellables = Set<AnyCancellable>()

    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    @Published var isLowMemory = false

    enum MemoryPressureLevel {
        case normal
        case warning
        case critical

        var shouldReduceQuality: Bool {
            switch self {
            case .warning, .critical:
                return true
            case .normal:
                return false
            }
        }

        var maxConcurrentOperations: Int {
            switch self {
            case .normal:
                return 3
            case .warning:
                return 2
            case .critical:
                return 1
            }
        }
    }

    private init() {
        setupMemoryWarningObserver()
        configureCaches()
    }

    // MARK: - Setup

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)

        // Monitor memory usage periodically
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkMemoryUsage()
            }
            .store(in: &cancellables)
    }

    private func configureCaches() {
        // Configure PDF cache
        pdfCache.countLimit = 5
        pdfCache.totalCostLimit = Int(maxPDFSizeInMemory)

        // Configure thumbnail cache
        thumbnailCache.countLimit = 50
        thumbnailCache.totalCostLimit = 10 * 1024 * 1024  // 10MB for thumbnails
    }

    // MARK: - Memory Monitoring

    private func checkMemoryUsage() {
        let memoryUsage = getCurrentMemoryUsage()

        if memoryUsage > criticalMemoryThreshold {
            memoryPressureLevel = .critical
            isLowMemory = true
            performAggressiveCleanup()
        } else if memoryUsage > warningMemoryThreshold {
            memoryPressureLevel = .warning
            isLowMemory = true
            performModerateCleanup()
        } else {
            memoryPressureLevel = .normal
            isLowMemory = false
        }
    }

    private func getCurrentMemoryUsage() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let usedMemory = Float(info.resident_size)
        let totalMemory = Float(ProcessInfo.processInfo.physicalMemory)

        return usedMemory / totalMemory
    }

    // MARK: - Memory Warning Handling

    private func handleMemoryWarning() {
        ErrorLogger.shared.logWarning("Received memory warning")
        memoryPressureLevel = .critical
        isLowMemory = true
        performAggressiveCleanup()
    }

    private func performModerateCleanup() {
        // Clear some caches
        thumbnailCache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()

        // Reduce PDF cache
        if pdfCache.countLimit > 2 {
            pdfCache.countLimit = 2
        }
    }

    private func performAggressiveCleanup() {
        // Clear all caches
        pdfCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()

        // Clear image cache
        SDImageCache.shared.clearMemory()

        // Force garbage collection
        autoreleasepool {
            // Trigger memory cleanup
        }

        ErrorLogger.shared.logWarning("Performed aggressive memory cleanup")
    }

    // MARK: - PDF Memory Management

    func loadPDFEfficiently(at url: URL) async throws -> PDFKit.PDFDocument? {
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0

        // Check if file is too large for memory
        if fileSize > maxPDFSizeInMemory {
            throw AppError.documentTooLarge(maxSize: Int(maxPDFSizeInMemory))
        }

        // Check current memory pressure
        if memoryPressureLevel == .critical {
            performAggressiveCleanup()

            // If still critical, reject loading
            if memoryPressureLevel == .critical {
                throw AppError.insufficientMemory
            }
        }

        // Check cache first
        let cacheKey = url.path as NSString
        if let cachedPDF = pdfCache.object(forKey: cacheKey) {
            return cachedPDF
        }

        // Load PDF with memory consideration
        guard let pdfDocument = PDFKit.PDFDocument(url: url) else {
            throw AppError.pdfProcessingFailed(reason: "Failed to load PDF")
        }

        // Cache if memory allows
        if memoryPressureLevel == .normal {
            pdfCache.setObject(pdfDocument, forKey: cacheKey, cost: Int(fileSize))
        }

        return pdfDocument
    }

    func generateThumbnail(for pdfDocument: PDFKit.PDFDocument, pageIndex: Int, size: CGSize) -> UIImage? {
        let cacheKey = "\(pdfDocument.documentURL?.path ?? "")-\(pageIndex)" as NSString

        // Check cache first
        if let cachedThumbnail = thumbnailCache.object(forKey: cacheKey) {
            return cachedThumbnail
        }

        guard let page = pdfDocument.page(at: pageIndex) else { return nil }

        // Adjust quality based on memory pressure
        let scale: CGFloat = memoryPressureLevel.shouldReduceQuality ? 1.0 : 2.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let thumbnail = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()

            let bounds = page.bounds(for: .mediaBox)
            let scaleFactor = min(size.width / bounds.width, size.height / bounds.height)

            context.cgContext.scaleBy(x: scaleFactor, y: scaleFactor)
            page.draw(with: .mediaBox, to: context.cgContext)

            context.cgContext.restoreGState()
        }

        // Cache if memory allows
        if memoryPressureLevel != .critical {
            let cost = Int(size.width * size.height * 4 * scale)  // Approximate memory cost
            thumbnailCache.setObject(thumbnail, forKey: cacheKey, cost: cost)
        }

        return thumbnail
    }

    // MARK: - Large PDF Handling

    func processLargePDF(_ pdfDocument: PDFKit.PDFDocument, operation: (PDFPage) -> Void) async throws {
        let pageCount = pdfDocument.pageCount

        // Process in batches based on memory pressure
        let batchSize = memoryPressureLevel.maxConcurrentOperations

        for startIndex in stride(from: 0, to: pageCount, by: batchSize) {
            // Check memory before each batch
            if memoryPressureLevel == .critical {
                performAggressiveCleanup()
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Wait 1 second
            }

            autoreleasepool {
                let endIndex = min(startIndex + batchSize, pageCount)
                for pageIndex in startIndex..<endIndex {
                    if let page = pdfDocument.page(at: pageIndex) {
                        operation(page)
                    }
                }
            }
        }
    }

    // MARK: - Public Methods

    func clearCaches() {
        pdfCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    func canLoadFileOfSize(_ size: Int64) -> Bool {
        if size > maxPDFSizeInMemory {
            return false
        }

        if memoryPressureLevel == .critical {
            return false
        }

        return true
    }

    func prepareForLargeOperation() {
        if memoryPressureLevel != .normal {
            performModerateCleanup()
        }
    }
}

// MARK: - Memory-Efficient PDF Loading Extension

extension PDFDocument {

    static func loadEfficiently(from url: URL) async throws -> PDFKit.PDFDocument? {
        return try await MemoryManager.shared.loadPDFEfficiently(at: url)
    }

    func generateThumbnails(size: CGSize, completion: @escaping ([UIImage]) -> Void) {
        Task {
            var thumbnails: [UIImage] = []

            for index in 0..<min(pageCount, 10) {  // Limit to first 10 pages
                if let thumbnail = MemoryManager.shared.generateThumbnail(for: self, pageIndex: index, size: size) {
                    thumbnails.append(thumbnail)
                }

                // Yield periodically to prevent blocking
                if index % 3 == 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second
                }
            }

            await MainActor.run {
                completion(thumbnails)
            }
        }
    }
}

// MARK: - Image Cache Placeholder (Replace with actual implementation)

class SDImageCache {
    static let shared = SDImageCache()

    func clearMemory() {
        // Clear image memory cache
    }
}