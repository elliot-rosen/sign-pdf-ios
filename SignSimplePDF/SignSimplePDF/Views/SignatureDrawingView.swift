import SwiftUI
import PencilKit

// MARK: - Pen Configuration

enum PenColor: String, CaseIterable {
    case black = "Black"
    case blue = "Blue"
    case darkBlue = "Dark Blue"

    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .blue: return UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        case .darkBlue: return UIColor(red: 0, green: 0.25, blue: 0.5, alpha: 1)
        }
    }

    var color: Color {
        Color(uiColor)
    }
}

enum PenWidth: String, CaseIterable {
    case thin = "Thin"
    case medium = "Medium"
    case thick = "Thick"

    var width: CGFloat {
        switch self {
        case .thin: return 3
        case .medium: return 6
        case .thick: return 10
        }
    }
}

// MARK: - PKCanvasView Representable

struct PKCanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let penColor: PenColor
    let penWidth: PenWidth
    let onDrawingChanged: (() -> Void)?

    init(canvasView: Binding<PKCanvasView>, penColor: PenColor = .black, penWidth: PenWidth = .medium, onDrawingChanged: (() -> Void)? = nil) {
        self._canvasView = canvasView
        self.penColor = penColor
        self.penWidth = penWidth
        self.onDrawingChanged = onDrawingChanged
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput

        // Set up ink tool
        let ink = PKInkingTool(.pen, color: penColor.uiColor, width: penWidth.width)
        canvasView.tool = ink

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update pen tool when color or width changes
        let ink = PKInkingTool(.pen, color: penColor.uiColor, width: penWidth.width)
        uiView.tool = ink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (() -> Void)?

        init(onDrawingChanged: (() -> Void)?) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged?()
        }
    }
}

// MARK: - Signature Drawing View

struct SignatureDrawingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var canvasView = PKCanvasView()
    @State private var signatureName = ""
    @State private var hasDrawing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var selectedColor: PenColor = .black
    @State private var selectedWidth: PenWidth = .medium
    @State private var showPreview = false
    @State private var previewImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instructions
                Text("Draw your signature below")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.top, AppTheme.Spacing.md)

                // Drawing canvas
                ZStack {
                    // Background with border
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(AppTheme.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                        )

                    // Signature line
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(AppTheme.Colors.textTertiary.opacity(0.3))
                            .frame(height: 1)
                            .padding(.horizontal, AppTheme.Spacing.xl)
                            .padding(.bottom, AppTheme.Spacing.xxl)
                    }

                    // Canvas
                    PKCanvasViewRepresentable(
                        canvasView: $canvasView,
                        penColor: selectedColor,
                        penWidth: selectedWidth,
                        onDrawingChanged: {
                            hasDrawing = !canvasView.drawing.bounds.isEmpty
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
                }
                .frame(height: 200)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.md)

                // Pen options
                penOptionsView
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)

                // Name field
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Signature Name (optional)")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    TextField("My Signature", text: $signatureName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.md)

                Spacer()

                // Clear button
                Button {
                    HapticManager.shared.buttonTap()
                    clearCanvas()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(AppTheme.Typography.body)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasDrawing)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("New Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") {
                        showSignaturePreview()
                    }
                    .disabled(!hasDrawing || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showPreview) {
                SignaturePreviewSheet(
                    previewImage: previewImage,
                    signatureName: $signatureName,
                    onConfirm: confirmSave,
                    onCancel: { showPreview = false }
                )
            }
        }
    }

    private func showSignaturePreview() {
        // Generate preview image from drawing
        let drawing = canvasView.drawing
        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        previewImage = drawing.image(from: bounds, scale: 2.0)
        showPreview = true
    }

    // MARK: - Pen Options View

    private var penOptionsView: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            // Color picker
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Color")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(PenColor.allCases, id: \.self) { color in
                        Button {
                            HapticManager.shared.selection()
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? AppTheme.Colors.primary : Color.clear, lineWidth: 2)
                                        .padding(-2)
                                )
                        }
                    }
                }
            }

            Spacer()

            // Width picker
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Width")
                    .font(AppTheme.Typography.caption1)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(PenWidth.allCases, id: \.self) { width in
                        Button {
                            HapticManager.shared.selection()
                            selectedWidth = width
                        } label: {
                            RoundedRectangle(cornerRadius: width.width / 2)
                                .fill(selectedColor.color)
                                .frame(width: 32, height: width.width)
                                .padding(.vertical, (12 - width.width) / 2)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xs)
                                        .fill(selectedWidth == width ? AppTheme.Colors.primary.opacity(0.1) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xs)
                                        .stroke(selectedWidth == width ? AppTheme.Colors.primary : Color.clear, lineWidth: 1)
                                )
                        }
                        .frame(width: 40, height: 28)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.CornerRadius.sm)
    }

    private func clearCanvas() {
        canvasView.drawing = PKDrawing()
        hasDrawing = false
    }

    private func confirmSave() {
        isSaving = true
        showPreview = false

        let name = signatureName.isEmpty ? "Signature \(signatureManager.signatureCount + 1)" : signatureName

        do {
            _ = try signatureManager.createSignature(
                from: canvasView.drawing,
                name: name
            )
            HapticManager.shared.success()
            dismiss()
        } catch {
            HapticManager.shared.error()
            errorMessage = error.localizedDescription
            showError = true
            isSaving = false
        }
    }
}

// MARK: - Signature Preview Sheet

struct SignaturePreviewSheet: View {
    let previewImage: UIImage?
    @Binding var signatureName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.lg) {
                Text("Preview your signature")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.top, AppTheme.Spacing.md)

                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .stroke(AppTheme.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                        )

                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(AppTheme.Spacing.md)
                    } else {
                        Text("No preview available")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                .frame(height: 150)
                .padding(.horizontal, AppTheme.Spacing.md)

                // Name field
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Signature Name")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    TextField("My Signature", text: $signatureName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                // Info text
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppTheme.Colors.info)
                    Text("This is how your signature will appear on documents")
                        .font(AppTheme.Typography.caption1)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                Spacer()

                // Save button
                Button {
                    HapticManager.shared.buttonTap()
                    onConfirm()
                } label: {
                    Text("Save Signature")
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("Confirm Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SignatureDrawingView()
        .environmentObject(SignatureManager(subscriptionManager: SubscriptionManager()))
        .environmentObject(SubscriptionManager())
}
