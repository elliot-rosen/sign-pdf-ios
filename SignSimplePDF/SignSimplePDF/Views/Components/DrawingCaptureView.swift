import SwiftUI
import PDFKit

struct DrawingCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: [CGPoint] = []
    @State private var allPaths: [DrawingPath] = []
    @State private var lineWidth: CGFloat
    @State private var selectedColor: Color
    @State private var canvasSize: CGSize = .zero
    @State private var isErasing = false

    let onComplete: ([DrawingPath], UIColor, CGFloat, CGSize) -> Void

    init(
        initialColor: UIColor = .black,
        initialLineWidth: CGFloat = 3.0,
        onComplete: @escaping ([DrawingPath], UIColor, CGFloat, CGSize) -> Void
    ) {
        _selectedColor = State(initialValue: Color(initialColor))
        _lineWidth = State(initialValue: initialLineWidth)
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Drawing tools
                drawingToolbar

                // Canvas
                GeometryReader { geometry in
                    ZStack {
                        Color.white
                            .overlay(
                                Canvas { context, size in
                                    // Draw all completed paths
                                    for path in allPaths {
                                        drawPath(path.points, in: context, size: size)
                                    }

                                    // Draw current path
                                    if !currentPath.isEmpty {
                                        drawPath(currentPath, in: context, size: size)
                                    }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            )
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if isErasing {
                                            // Handle erasing
                                            eraseAt(point: value.location)
                                        } else {
                                            // Add point to current path
                                            currentPath.append(value.location)
                                        }
                                    }
                                    .onEnded { _ in
                                        if !isErasing && !currentPath.isEmpty {
                                            allPaths.append(DrawingPath(points: currentPath))
                                            currentPath = []
                                        }
                                    }
                            )
                            .onAppear {
                                canvasSize = geometry.size
                            }
                    }
                    .clipShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding()

                // Bottom controls
                bottomControls
            }
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        completeDrawing()
                    }
                    .fontWeight(.semibold)
                    .disabled(allPaths.isEmpty)
                }
            }
            .background(Color(UIColor.systemBackground))
        }
    }

    private var drawingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Tool selection
                HStack(spacing: 8) {
                    Button {
                        isErasing = false
                    } label: {
                        Image(systemName: "pencil.tip")
                            .font(.system(size: 20))
                            .foregroundColor(isErasing ? .gray : AppTheme.Colors.primary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isErasing ? Color.clear : AppTheme.Colors.primary.opacity(0.1))
                            )
                    }

                    Button {
                        isErasing = true
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 20))
                            .foregroundColor(isErasing ? AppTheme.Colors.primary : .gray)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isErasing ? AppTheme.Colors.primary.opacity(0.1) : Color.clear)
                            )
                    }
                }

                Divider()
                    .frame(height: 30)

                // Color selection
                HStack(spacing: 8) {
                    ForEach([Color.black, .red, .blue, .green, .yellow, .purple], id: \.self) { color in
                        Button {
                            selectedColor = color
                            isErasing = false
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.black : Color.clear, lineWidth: 2)
                                        .padding(2)
                                )
                        }
                    }
                }

                Divider()
                    .frame(height: 30)

                // Line width
                HStack(spacing: 8) {
                    ForEach([1, 3, 5, 8, 12], id: \.self) { width in
                        Button {
                            lineWidth = CGFloat(width)
                            isErasing = false
                        } label: {
                            Circle()
                                .fill(Color.black)
                                .frame(width: CGFloat(width + 10), height: CGFloat(width + 10))
                                .opacity(lineWidth == CGFloat(width) ? 1.0 : 0.3)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 60)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var bottomControls: some View {
        HStack {
            Button {
                clearCanvas()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 15))
            }
            .foregroundColor(.red)
            .padding(.horizontal)

            Spacer()

            Button {
                undoLastPath()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18))
            }
            .disabled(allPaths.isEmpty)
            .padding(.horizontal)
        }
        .frame(height: 50)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func drawPath(_ points: [CGPoint], in context: GraphicsContext, size: CGSize) {
        guard points.count > 1 else { return }

        var path = Path()
        path.move(to: points[0])

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(
            path,
            with: .color(selectedColor),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func eraseAt(point: CGPoint) {
        // Simple erase: remove paths that are close to the touch point
        let eraseRadius: CGFloat = 20
        allPaths.removeAll { path in
            path.points.contains { pathPoint in
                let distance = sqrt(pow(pathPoint.x - point.x, 2) + pow(pathPoint.y - point.y, 2))
                return distance < eraseRadius
            }
        }
    }

    private func clearCanvas() {
        allPaths.removeAll()
        currentPath.removeAll()
    }

    private func undoLastPath() {
        if !allPaths.isEmpty {
            allPaths.removeLast()
        }
    }

    private func completeDrawing() {
        guard !allPaths.isEmpty else { return }

        // Calculate bounding box for all paths
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var maxY = CGFloat.leastNormalMagnitude

        for path in allPaths {
            for point in path.points {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }

        // Add padding
        let padding: CGFloat = lineWidth * 2
        minX -= padding
        minY -= padding
        maxX += padding
        maxY += padding

        let drawingSize = CGSize(width: maxX - minX, height: maxY - minY)

        // Normalize paths to (0-1) range relative to bounding box
        // This makes them resolution-independent and perfect for scaling
        let normalizedPaths = allPaths.map { path in
            DrawingPath(points: path.points.map { point in
                CGPoint(
                    x: (point.x - minX) / drawingSize.width,
                    y: (point.y - minY) / drawingSize.height
                )
            })
        }

        onComplete(normalizedPaths, UIColor(selectedColor), lineWidth, drawingSize)
        dismiss()
    }
}