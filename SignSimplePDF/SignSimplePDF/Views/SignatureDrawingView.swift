import SwiftUI
import PencilKit

struct SignatureDrawingView: View {
    @EnvironmentObject var signatureManager: SignatureManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var canvasView = PKCanvasView()
    @State private var signatureName = ""
    @State private var showingNameAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var strokeColor = UIColor.black
    @State private var strokeWidth: CGFloat = 2.0
    @State private var hasDrawing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Drawing Canvas
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                                .stroke(AppTheme.Colors.border.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(
                            color: AppTheme.Shadows.medium.color,
                            radius: AppTheme.Shadows.medium.radius,
                            x: AppTheme.Shadows.medium.x,
                            y: AppTheme.Shadows.medium.y
                        )

                    // Canvas
                    SignatureCanvas(
                        canvasView: $canvasView,
                        strokeColor: strokeColor,
                        strokeWidth: strokeWidth,
                        onDrawingChanged: { hasDrawing = $0 }
                    )
                    .cornerRadius(AppTheme.CornerRadius.lg)
                    .padding(AppTheme.Spacing.xs)

                    // Hint text
                    if canvasView.drawing.bounds.isEmpty {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "signature")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.Colors.textTertiary)

                            Text("Draw your signature here")
                                .font(AppTheme.Typography.body)
                                .foregroundColor(AppTheme.Colors.textTertiary)

                            Text("Use your finger or Apple Pencil")
                                .font(AppTheme.Typography.caption1)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: 250)
                .padding(AppTheme.Spacing.lg)

                // Tools
                VStack(spacing: AppTheme.Spacing.md) {
                    // Color picker
                    HStack(spacing: AppTheme.Spacing.md) {
                        Text("Color")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textPrimary)

                        Spacer()

                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach([UIColor.black, UIColor.blue, UIColor.systemIndigo], id: \.self) { color in
                                Button {
                                    HapticManager.shared.selection()
                                    strokeColor = color
                                    updateDrawingTool()
                                } label: {
                                    Circle()
                                        .fill(Color(color))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    strokeColor == color ? AppTheme.Colors.primary : Color.clear,
                                                    lineWidth: 3
                                                )
                                                .padding(-4)
                                        )
                                }
                            }
                        }
                    }

                    // Width slider
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack {
                            Text("Thickness")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.textPrimary)

                            Spacer()

                            Text("\(Int(strokeWidth))pt")
                                .font(AppTheme.Typography.callout)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }

                        Slider(value: $strokeWidth, in: 1...5, step: 1) { _ in
                            updateDrawingTool()
                        }
                        .accentColor(AppTheme.Colors.primary)
                    }

                    Divider()

                    // Action buttons
                    HStack(spacing: AppTheme.Spacing.md) {
                        Button {
                            HapticManager.shared.buttonTap()
                            clearCanvas()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(AppTheme.Typography.bodyMedium)
                                .foregroundColor(AppTheme.Colors.error)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .fill(AppTheme.Colors.error.opacity(0.1))
                        )

                        Button {
                            HapticManager.shared.buttonTap()
                            showingNameAlert = true
                        } label: {
                            Label("Save", systemImage: "checkmark")
                                .font(AppTheme.Typography.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                                .fill(AppTheme.Colors.primary)
                                .shadow(
                                    color: AppTheme.Colors.primary.opacity(0.3),
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        )
                        .disabled(!hasDrawing)
                    }
                }
                .padding(AppTheme.Spacing.lg)

                Spacer()
            }
            .navigationTitle("Create Signature")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.subtle()
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.buttonTap()
                        canvasView.drawing = PKDrawing()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(AppTheme.Colors.primary)
                    }
                }
            }
            .alert("Name Your Signature", isPresented: $showingNameAlert) {
                TextField("Signature name", text: $signatureName)
                Button("Save") {
                    saveSignature()
                }
                Button("Cancel", role: .cancel) {
                    signatureName = ""
                }
            } message: {
                Text("Give your signature a name to easily identify it later.")
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            setupCanvas()
            signatureManager.configure(with: subscriptionManager)
        }
    }

    private func setupCanvas() {
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.overrideUserInterfaceStyle = .light
        updateDrawingTool()
        hasDrawing = !canvasView.drawing.bounds.isEmpty
    }

    private func updateDrawingTool() {
        canvasView.tool = PKInkingTool(.pen, color: strokeColor, width: strokeWidth)
    }

    private func clearCanvas() {
        canvasView.drawing = PKDrawing()
        hasDrawing = false
    }

    private func saveSignature() {
        guard !signatureName.isEmpty else {
            errorMessage = "Please enter a name for your signature"
            showingErrorAlert = true
            return
        }

        do {
            _ = try signatureManager.saveSignature(
                name: signatureName,
                drawing: canvasView.drawing,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                canSaveUnlimited: subscriptionManager.isSubscribed
            )
            HapticManager.shared.success()
            hasDrawing = false
            canvasView.drawing = PKDrawing()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            HapticManager.shared.error()
        }
    }
}

struct SignatureCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let strokeColor: UIColor
    let strokeWidth: CGFloat
    let onDrawingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.overrideUserInterfaceStyle = .light
        onDrawingChanged(!canvasView.drawing.bounds.isEmpty)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pen, color: strokeColor, width: strokeWidth)
        uiView.backgroundColor = .white
        uiView.overrideUserInterfaceStyle = .light
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: SignatureCanvas

        init(_ parent: SignatureCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged(!canvasView.drawing.bounds.isEmpty)
        }
    }
}

struct SignatureDrawingView_Previews: PreviewProvider {
    static var previews: some View {
        let subscriptionManager = SubscriptionManager()
        SignatureDrawingView()
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
            .environmentObject(subscriptionManager)
    }
}
