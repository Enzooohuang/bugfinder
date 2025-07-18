import AVFoundation
import UIKit

class CameraPermissionManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var showSettingsAlert = false

    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            isAuthorized = true

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                }
            }

        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.showSettingsAlert = true
            }

        @unknown default:
            break
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
