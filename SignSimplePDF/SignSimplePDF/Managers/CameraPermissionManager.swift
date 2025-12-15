import AVFoundation
import SwiftUI

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
class CameraPermissionManager: ObservableObject {
    static let shared = CameraPermissionManager()

    @Published private(set) var permissionStatus: CameraPermissionStatus = .notDetermined

    private init() {
        checkPermissionStatus()
    }

    func checkPermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionStatus = mapAuthorizationStatus(status)
    }

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionStatus = granted ? .authorized : .denied
            return granted
        case .authorized:
            permissionStatus = .authorized
            return true
        case .denied, .restricted:
            permissionStatus = status == .denied ? .denied : .restricted
            return false
        @unknown default:
            permissionStatus = .denied
            return false
        }
    }

    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }

    private func mapAuthorizationStatus(_ status: AVAuthorizationStatus) -> CameraPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}
