import SwiftUI
import PDFKit

// MARK: - Base Draggable Annotation View

struct DraggableAnnotationView: View {
    @ObservedObject var annotation: PDFAnnotationItem
    @ObservedObject var annotationManager: AnnotationManager
    let pageSize: CGSize
    let pdfView: PDFView
    let page: PDFPage

    @State private var isDragging = false
    @State private var isScaling = false
    @State private var showScaleBadge = false
    @State private var scaleSnapshot: PDFAnnotationItem?
    @State private var initialScaleValue: CGFloat = 1.0
    @State private var dragStartState: PDFAnnotationItem?
    @State private var dragStartPDFPosition: CGPoint = .zero
    @State private var lastHapticThreshold: CGFloat = 1.0

    // Compute screen bounds on-demand
    private var screenBounds: CGRect {
        annotation.screenBounds(on: page, in: pdfView)
    }

    private var screenSize: CGSize {
        screenBounds.size
    }

    private var screenPosition: CGPoint {
        screenBounds.origin
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Annotation content with drag handle and scale badge
            VStack(spacing: 0) {
                // Scale percentage badge - shown during scaling
                if showScaleBadge {
                    ScaleBadge(scale: annotation.scale)
                        .offset(y: -42)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(1000)
                }

                // Drag handle with icon + text - only show when selected
                if annotation.isSelected && !showScaleBadge {
                    MinimalDragHandle()
                        .offset(y: -10)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                // Annotation content
                annotationContent
                    .frame(width: max(screenSize.width, 1),
                           height: max(screenSize.height, 1))
                    .overlay(
                        // Refined selection border with enhanced visual feedback
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                annotation.isSelected ?
                                    LinearGradient(
                                        colors: [AppTheme.Colors.primary, AppTheme.Colors.primaryDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                                lineWidth: annotation.isSelected ? 3 : 0
                            )
                            .shadow(
                                color: annotation.isSelected ? AppTheme.Colors.primary.opacity(0.25) : Color.clear,
                                radius: annotation.isSelected ? 6 : 0,
                                x: 0,
                                y: 2
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: annotation.isSelected)
                            .overlay(
                                // Resize handles
                                Group {
                                    if annotation.isSelected {
                                        RefinedResizeHandles(
                                            annotation: annotation,
                                            annotationManager: annotationManager,
                                            page: page,
                                            pdfView: pdfView
                                        )
                                    }
                                }
                            )
                    )
            }
            .scaleEffect(isDragging ? 1.02 : (annotation.isSelected ? 1.0 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: annotation.isSelected)
            .shadow(
                color: isDragging ? Color.black.opacity(0.15) : (annotation.isSelected ? Color.black.opacity(0.08) : Color.clear),
                radius: isDragging ? 8 : (annotation.isSelected ? 4 : 0),
                x: 0,
                y: isDragging ? 4 : (annotation.isSelected ? 2 : 0)
            )

            // Refined delete button
            if annotation.isSelected {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        HapticManager.shared.impact(.medium)
                        annotationManager.deleteAnnotation(annotation)
                    }
                } label: {
                    ZStack {
                        // Larger tap target (invisible)
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 44, height: 44)

                        // Refined button with gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                            .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)

                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .offset(x: 12, y: -12)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .position(
            // .position() uses the center of the view, compute from PDF coordinates
            x: screenPosition.x + screenSize.width / 2,
            y: screenPosition.y + screenSize.height / 2
        )
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isDragging = true
                        }
                        HapticManager.shared.selection()
                        annotationManager.selectAnnotation(annotation)
                        dragStartState = annotation.copy()
                        dragStartPDFPosition = annotation.pdfPosition
                    }

                    // Get current screen position at drag start
                    let startScreenBounds = PDFCoordinateConverter.pdfToScreen(
                        rect: CGRect(origin: dragStartPDFPosition, size: annotation.displaySize),
                        on: page,
                        in: pdfView
                    )

                    // Calculate proposed screen position
                    let proposedScreenTopLeft = CGPoint(
                        x: startScreenBounds.origin.x + value.translation.width,
                        y: startScreenBounds.origin.y + value.translation.height
                    )

                    // Convert to PDF coordinates
                    let proposedScreenRect = CGRect(origin: proposedScreenTopLeft, size: startScreenBounds.size)
                    let proposedPDFRect = PDFCoordinateConverter.screenToPDF(
                        rect: proposedScreenRect,
                        on: page,
                        in: pdfView
                    )

                    // Clamp and set
                    let clampedPDFPosition = PDFCoordinateConverter.clamp(
                        pdfPoint: proposedPDFRect.origin,
                        size: annotation.displaySize,
                        on: page
                    )

                    annotation.pdfPosition = clampedPDFPosition
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isDragging = false
                    }
                    if let snapshot = dragStartState,
                       snapshot.pdfPosition != annotation.pdfPosition {
                        annotationManager.recordModification(of: annotation, from: snapshot)
                    }
                    dragStartState = nil
                    HapticManager.shared.impact(.light)
                }
        )
        .simultaneousGesture(
            MagnificationGesture(minimumScaleDelta: 0.01)
                .onChanged { value in
                    if !annotation.isSelected {
                        annotationManager.selectAnnotation(annotation)
                    }
                    guard annotation.isSelected else { return }

                    // Initialize scaling state
                    if scaleSnapshot == nil {
                        scaleSnapshot = annotation.copy()
                        initialScaleValue = annotation.scale
                        lastHapticThreshold = annotation.scale
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            showScaleBadge = true
                            isScaling = true
                        }
                        HapticManager.shared.selection()
                    }

                    let proposedScale = initialScaleValue * value
                    let clampedScale = clampScale(proposedScale, for: annotation)

                    // Haptic feedback at scale thresholds
                    checkScaleThresholdHaptic(currentScale: clampedScale)

                    applyScale(clampedScale)
                }
                .onEnded { value in
                    guard annotation.isSelected else { return }
                    let proposedScale = initialScaleValue * value
                    let clampedScale = clampScale(proposedScale, for: annotation)
                    applyScale(clampedScale)

                    if let snapshot = scaleSnapshot, snapshot.scale != annotation.scale {
                        annotationManager.recordModification(of: annotation, from: snapshot)
                    }

                    scaleSnapshot = nil
                    initialScaleValue = annotation.scale
                    lastHapticThreshold = 1.0

                    // Hide scale badge after a delay
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isScaling = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showScaleBadge = false
                        }
                    }

                    HapticManager.shared.impact(.light)
                }
        )
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    HapticManager.shared.selection()
                    if annotationManager.selectedAnnotation?.id == annotation.id {
                        annotationManager.deselectAll()
                    } else {
                        annotationManager.selectAnnotation(annotation)
                    }
                }
        )
    }

    @ViewBuilder
    private var annotationContent: some View {
        switch annotation.type {
        case .signature(let imageData):
            SignatureAnnotationView(imageData: imageData)

        case .text(let content, let fontSize, let color):
            TextAnnotationView(
                text: content,
                fontSize: fontSize * annotation.scale,
                color: Color(color)
            )

        case .highlight(let color):
            HighlightAnnotationView(color: Color(color))

        case .drawing(let paths, let color, let lineWidth):
            DrawingAnnotationView(
                paths: paths,
                color: Color(color),
                lineWidth: lineWidth,
                pdfSize: annotation.displaySize,
                screenSize: screenSize,
                scale: annotation.scale
            )
        }
    }

    private func clampScale(_ scale: CGFloat, for annotation: PDFAnnotationItem) -> CGFloat {
        let range: ClosedRange<CGFloat>
        switch annotation.type {
        case .signature:
            range = 0.25...3.0
        case .text:
            range = 0.3...4.0
        case .highlight:
            range = 0.2...3.0
        case .drawing:
            range = 0.3...3.0
        }

        // Prevent division by zero
        guard annotation.size.width > 0 && annotation.size.height > 0 else {
            return max(range.lowerBound, min(scale, range.upperBound))
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let widthLimit = max(0.15, (pageBounds.width - 24) / annotation.size.width)
        let heightLimit = max(0.15, (pageBounds.height - 24) / annotation.size.height)
        let pageLimit = max(0.15, min(widthLimit, heightLimit))
        var lower = min(range.lowerBound, pageLimit)
        let upper = min(range.upperBound, pageLimit)
        if upper < lower { lower = upper }
        return min(max(scale, lower), upper)
    }

    private func applyScale(_ newScale: CGFloat) {
        guard annotation.scale != newScale else { return }

        annotation.scale = newScale

        // Adjust position to maintain center point
        let newPosition = PDFCoordinateConverter.adjustOriginForResize(
            currentOrigin: annotation.pdfPosition,
            currentSize: annotation.size,
            newSize: annotation.displaySize,
            on: page
        )

        annotation.pdfPosition = newPosition
    }

    private func checkScaleThresholdHaptic(currentScale: CGFloat) {
        let thresholds: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0]

        for threshold in thresholds {
            // Check if we crossed this threshold
            let crossedFromBelow = lastHapticThreshold < threshold && currentScale >= threshold
            let crossedFromAbove = lastHapticThreshold > threshold && currentScale <= threshold

            if crossedFromBelow || crossedFromAbove {
                HapticManager.shared.selection()
                lastHapticThreshold = threshold
                break
            }
        }
    }
}

// MARK: - Signature Annotation View

struct SignatureAnnotationView: View {
    let imageData: Data

    var body: some View {
        Group {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "signature")
                            .foregroundColor(.gray)
                    )
            }
        }
    }
}

// MARK: - Text Annotation View

struct TextAnnotationView: View {
    let text: String
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(color)
            .padding(4)
            .background(
                Color.white.opacity(0.01) // Invisible but tappable background
            )
    }
}

// MARK: - Highlight Annotation View

struct HighlightAnnotationView: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.3))
            .allowsHitTesting(false)
    }
}

// MARK: - Drag Handle & Scale Badge

struct MinimalDragHandle: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "move.3d")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)

            Text("Move")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.Colors.primary, AppTheme.Colors.primaryDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppTheme.Colors.primary.opacity(0.4), radius: 4, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct ScaleBadge: View {
    let scale: CGFloat

    private var scaleText: String {
        let percentage = Int(scale * 100)
        return "\(percentage)%"
    }

    private var scaleIcon: String {
        if scale < 0.75 {
            return "arrow.down.right.and.arrow.up.left"
        } else if scale > 1.5 {
            return "arrow.up.left.and.arrow.down.right"
        } else {
            return "equal"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: scaleIcon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)

            Text(scaleText)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.Colors.primary, AppTheme.Colors.primaryDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppTheme.Colors.primary.opacity(0.5), radius: 6, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Drawing Annotation View

struct DrawingAnnotationView: View {
    let paths: [DrawingPath]
    let color: Color
    let lineWidth: CGFloat
    let pdfSize: CGSize
    let screenSize: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            for path in paths {
                guard path.points.count > 1 else { continue }

                var linePath = Path()
                let first = scaledPoint(path.points[0])
                linePath.move(to: first)

                for point in path.points.dropFirst() {
                    linePath.addLine(to: scaledPoint(point))
                }

                context.stroke(
                    linePath,
                    with: .color(color),
                    lineWidth: max(0.5, lineWidth * ((widthScaleFactor + heightScaleFactor) / 2))
                )
            }
        }
        .frame(width: max(screenSize.width, 1), height: max(screenSize.height, 1))
        .background(Color.white.opacity(0.01)) // Invisible but tappable
    }

    private var widthScaleFactor: CGFloat {
        guard pdfSize.width > 0 else { return 1.0 }
        return screenSize.width / pdfSize.width
    }

    private var heightScaleFactor: CGFloat {
        guard pdfSize.height > 0 else { return 1.0 }
        return screenSize.height / pdfSize.height
    }

    private func scaledPoint(_ normalizedPoint: CGPoint) -> CGPoint {
        // Points are in normalized coordinates (0-1 range)
        // Simply multiply by screen size to get screen coordinates
        return CGPoint(
            x: normalizedPoint.x * screenSize.width,
            y: normalizedPoint.y * screenSize.height
        )
    }
}

// MARK: - Refined Resize Handles

struct RefinedResizeHandles: View {
    @ObservedObject var annotation: PDFAnnotationItem
    @ObservedObject var annotationManager: AnnotationManager
    let page: PDFPage
    let pdfView: PDFView

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Corner handles - refined 8px circles
                ForEach(HandlePosition.allCases, id: \.self) { position in
                    RefinedResizeHandle(
                        annotation: annotation,
                        annotationManager: annotationManager,
                        position: position,
                        page: page,
                        pdfView: pdfView
                    )
                    .position(handlePosition(for: position, in: geometry.size))
                }
            }
        }
    }

    private func handlePosition(for position: HandlePosition, in size: CGSize) -> CGPoint {
        switch position {
        case .topLeft:
            return CGPoint(x: 0, y: 0)
        case .topRight:
            return CGPoint(x: size.width, y: 0)
        case .bottomLeft:
            return CGPoint(x: 0, y: size.height)
        case .bottomRight:
            return CGPoint(x: size.width, y: size.height)
        }
    }

    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

struct RefinedResizeHandle: View {
    @ObservedObject var annotation: PDFAnnotationItem
    @ObservedObject var annotationManager: AnnotationManager
    let position: RefinedResizeHandles.HandlePosition
    let page: PDFPage
    let pdfView: PDFView

    @State private var initialSize = CGSize.zero
    @State private var initialPosition = CGPoint.zero
    @State private var initialScale: CGFloat = 1.0
    @State private var scaleSnapshot: PDFAnnotationItem?
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Larger invisible tap target - 44pt for better touch
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)

            // Enhanced 10pt handle with gradient and glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color.white.opacity(0.95)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.Colors.primary, AppTheme.Colors.primaryDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )
                .shadow(color: AppTheme.Colors.primary.opacity(0.3), radius: 3, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                .scaleEffect(isHovered ? 1.5 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if scaleSnapshot == nil {
                        scaleSnapshot = annotation.copy()
                        initialSize = annotation.displaySize
                        initialPosition = annotation.pdfPosition
                        initialScale = annotation.scale
                        annotationManager.selectAnnotation(annotation)
                        isHovered = true
                        HapticManager.shared.selection()
                    }
                    applyResize(translation: value.translation)
                }
                .onEnded { value in
                    if let snapshot = scaleSnapshot, snapshot.scale != annotation.scale || snapshot.pdfPosition != annotation.pdfPosition {
                        annotationManager.recordModification(of: annotation, from: snapshot)
                    }
                    scaleSnapshot = nil
                    isHovered = false
                    HapticManager.shared.impact(.light)
                }
        )
    }

    private func applyResize(translation: CGSize) {
        // Prevent division by zero
        guard annotation.size.height > 0 else { return }
        let aspectRatio = annotation.size.width / annotation.size.height

        // Get screen bounds at start
        let startScreenBounds = PDFCoordinateConverter.pdfToScreen(
            rect: CGRect(origin: initialPosition, size: initialSize),
            on: page,
            in: pdfView
        )

        // Calculate delta in screen space
        var widthDelta: CGFloat = 0
        var heightDelta: CGFloat = 0

        switch position {
        case .bottomRight:
            widthDelta = translation.width
            heightDelta = translation.height
        case .bottomLeft:
            widthDelta = -translation.width
            heightDelta = translation.height
        case .topRight:
            widthDelta = translation.width
            heightDelta = -translation.height
        case .topLeft:
            widthDelta = -translation.width
            heightDelta = -translation.height
        }

        // Convert screen delta to PDF delta
        let screenToPDFRatio = initialSize.width / max(startScreenBounds.width, 1)
        let pdfWidthDelta = widthDelta * screenToPDFRatio
        let pdfHeightDelta = heightDelta * screenToPDFRatio

        // Use larger delta to maintain aspect ratio
        let delta = abs(pdfWidthDelta) > abs(pdfHeightDelta) ? pdfWidthDelta : pdfHeightDelta * aspectRatio

        // Calculate new scale
        let newWidth = annotation.size.width * initialScale + delta
        guard annotation.size.width > 0 else { return }
        let newScale = newWidth / annotation.size.width

        // Clamp the scale
        let clampedScale = clampScale(newScale, for: annotation)

        annotation.scale = clampedScale

        // Map corner position to AnnotationCorner enum
        let anchorCorner: AnnotationCorner
        switch position {
        case .bottomRight: anchorCorner = .topLeft
        case .bottomLeft: anchorCorner = .topRight
        case .topRight: anchorCorner = .bottomLeft
        case .topLeft: anchorCorner = .bottomRight
        }

        // Use PDFCoordinateConverter to adjust position
        let newPosition = PDFCoordinateConverter.adjustOriginForCornerResize(
            currentOrigin: initialPosition,
            currentSize: initialSize,
            newSize: annotation.displaySize,
            anchorCorner: anchorCorner,
            on: page
        )

        annotation.pdfPosition = newPosition
    }

    private func clampScale(_ scale: CGFloat, for annotation: PDFAnnotationItem) -> CGFloat {
        let range: ClosedRange<CGFloat>
        switch annotation.type {
        case .signature:
            range = 0.25...3.0
        case .text:
            range = 0.3...4.0
        case .highlight:
            range = 0.2...3.0
        case .drawing:
            range = 0.3...3.0
        }

        // Prevent division by zero
        guard annotation.size.width > 0 && annotation.size.height > 0 else {
            return max(range.lowerBound, min(scale, range.upperBound))
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let widthLimit = max(0.15, (pageBounds.width - 24) / annotation.size.width)
        let heightLimit = max(0.15, (pageBounds.height - 24) / annotation.size.height)
        let pageLimit = max(0.15, min(widthLimit, heightLimit))
        var lower = min(range.lowerBound, pageLimit)
        let upper = min(range.upperBound, pageLimit)
        if upper < lower { lower = upper }
        return min(max(scale, lower), upper)
    }
}
