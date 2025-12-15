import SwiftUI

struct CameraPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissionManager = CameraPermissionManager.shared

    let onPermissionGranted: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()

                VStack(spacing: AppTheme.Spacing.lg) {
                    // Icon
                    Image(systemName: permissionManager.permissionStatus == .denied ? "camera.fill" : "camera")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AppTheme.Colors.secondary.opacity(0.6),
                                    AppTheme.Colors.secondary.opacity(0.3)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    VStack(spacing: AppTheme.Spacing.sm) {
                        Text(titleText)
                            .font(AppTheme.Typography.title2)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(descriptionText)
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }

                Spacer()

                VStack(spacing: AppTheme.Spacing.md) {
                    switch permissionManager.permissionStatus {
                    case .notDetermined:
                        Button {
                            HapticManager.shared.buttonTap()
                            requestPermission()
                        } label: {
                            Label("Allow Camera Access", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                    case .denied, .restricted:
                        Button {
                            HapticManager.shared.buttonTap()
                            permissionManager.openSettings()
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                    case .authorized:
                        EmptyView()
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.Colors.background)
            .navigationTitle("Camera Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Refresh permission status when returning from Settings
                permissionManager.checkPermissionStatus()
                if permissionManager.permissionStatus == .authorized {
                    onPermissionGranted()
                    dismiss()
                }
            }
        }
    }

    private var titleText: String {
        switch permissionManager.permissionStatus {
        case .notDetermined:
            return "Camera Access Required"
        case .denied:
            return "Camera Access Denied"
        case .restricted:
            return "Camera Access Restricted"
        case .authorized:
            return "Camera Access Granted"
        }
    }

    private var descriptionText: String {
        switch permissionManager.permissionStatus {
        case .notDetermined:
            return "SignSimple PDF needs camera access to scan documents directly into PDF format for signing and editing."
        case .denied:
            return "Camera access was previously denied. Please open Settings and enable camera access to scan documents."
        case .restricted:
            return "Camera access is restricted on this device. You may need to check parental controls or device management settings."
        case .authorized:
            return "You have granted camera access."
        }
    }

    private func requestPermission() {
        Task {
            let granted = await permissionManager.requestPermission()
            if granted {
                onPermissionGranted()
                dismiss()
            }
        }
    }
}

#Preview("Not Determined") {
    CameraPermissionView {
        print("Permission granted")
    }
}
