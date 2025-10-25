import SwiftUI
import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isConfigured = false
    @Published var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var videoDevice: AVCaptureDevice?
    private var currentLens: LensType?
    
    override init() {
        super.init()
        requestAccessIfNeeded()
    }
    
    private func requestAccessIfNeeded() {
        switch authorizationStatus {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.authorizationStatus = granted ? .authorized : .denied
                }
                if granted { self.configureSession() }
            }
        default:
            break
        }
    }
    
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            defer {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
            
            self.applyLens(self.defaultLens)
        }
    }
    
    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let desiredLens: LensType = (factor < 1 && self.device(for: .ultraWide) != nil) ? .ultraWide : .wide
            if self.currentLens != desiredLens {
                self.applyLens(desiredLens)
            }
            guard let device = self.videoDevice else { return }
            let zoomTarget: CGFloat = desiredLens == .ultraWide ? 1.0 : factor
            let minFactor = device.minAvailableVideoZoomFactor
            let maxFactor = min(device.maxAvailableVideoZoomFactor, 5.0)
            let clamped = max(minFactor, min(zoomTarget, maxFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                print("Failed to set zoom: \(error.localizedDescription)")
            }
        }
    }
    
    private var defaultLens: LensType {
        if device(for: .wide) != nil {
            return .wide
        } else if device(for: .ultraWide) != nil {
            return .ultraWide
        } else {
            return .wide
        }
    }
    
    private func applyLens(_ lens: LensType) {
        guard let newDevice = device(for: lens),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoDevice = newDevice
            currentLens = lens
        }
        session.commitConfiguration()
    }
    
    private func device(for lens: LensType) -> AVCaptureDevice? {
        switch lens {
        case .wide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .ultraWide:
            if #available(iOS 13.0, *) {
                return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            } else {
                return nil
            }
        }
    }
}

private enum LensType: Equatable {
    case wide
    case ultraWide
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if let connection = view.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let connection = uiView.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
