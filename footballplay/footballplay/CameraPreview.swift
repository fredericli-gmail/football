import SwiftUI
import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isConfigured = false
    @Published var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
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
            
            // Remove existing inputs
            self.session.inputs.forEach { input in
                self.session.removeInput(input)
            }
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let deviceInput = try? AVCaptureDeviceInput(device: device) else {
                return
            }
            if self.session.canAddInput(deviceInput) {
                self.session.addInput(deviceInput)
            }
        }
    }
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
