import SwiftUI
import AVFoundation
import Combine
import Photos
import CoreImage

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isConfigured = false
    @Published var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastSaveMessage: String?
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var videoDevice: AVCaptureDevice?
    private var currentLens: LensType?
    private var durationTimer: AnyCancellable?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private var recordingStartTime: CMTime?
    private var outputDimensions = CGSize(width: 3840, height: 2160)
    private let scoreboard: ScoreboardState
    private let overlayRenderer: ScoreboardRenderer
    private let ciContext = CIContext()
    
    init(scoreboard: ScoreboardState) {
        self.scoreboard = scoreboard
        self.overlayRenderer = ScoreboardRenderer(state: scoreboard)
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
            if self.session.canSetSessionPreset(.hd4K3840x2160) {
                self.session.sessionPreset = .hd4K3840x2160
                self.outputDimensions = CGSize(width: 3840, height: 2160)
            } else if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            } else {
                self.session.sessionPreset = .medium
            }
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
            self.configureAudioInput()
            self.configureOutputs()
        }
    }
    
    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let desiredLens: LensType = (factor < 1 && self.cameraDevice(for: .ultraWide) != nil) ? .ultraWide : .wide
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
        if cameraDevice(for: .wide) != nil {
            return .wide
        } else if cameraDevice(for: .ultraWide) != nil {
            return .ultraWide
        } else {
            return .wide
        }
    }

    private func applyLens(_ lens: LensType) {
        guard let newDevice = cameraDevice(for: lens),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
        session.beginConfiguration()
        session.inputs
            .filter { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }
            .forEach { session.removeInput($0) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoDevice = newDevice
            currentLens = lens
            let desc = newDevice.activeFormat.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            outputDimensions = CGSize(width: Int(dims.width), height: Int(dims.height))
        }
        session.commitConfiguration()
    }
    
    private func configureAudioInput() {
        guard session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }) == false,
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else { return }
        if session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
    }
    
    private func configureOutputs() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let connection = videoOutput.connections.first,
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            self.videoOutput = videoOutput
        }
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            self.audioOutput = audioOutput
        }
    }
    
    private func cameraDevice(for lens: LensType) -> AVCaptureDevice? {
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
    
    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isRecording else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("broadcast-\(UUID().uuidString).mov")
            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(self.outputDimensions.width),
                    AVVideoHeightKey: Int(self.outputDimensions.height)
                ]
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.expectsMediaDataInRealTime = true
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
                guard writer.canAdd(videoInput) else { throw RecordingError.cannotAddVideoInput }
                writer.add(videoInput)
                var audioInput: AVAssetWriterInput?
                if self.audioOutput != nil {
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: 1,
                        AVSampleRateKey: 44100,
                        AVEncoderBitRateKey: 64000
                    ]
                    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                    input.expectsMediaDataInRealTime = true
                    if writer.canAdd(input) {
                        writer.add(input)
                        audioInput = input
                    }
                }
                self.assetWriter = writer
                self.videoInput = videoInput
                self.audioInput = audioInput
                self.pixelBufferAdaptor = adaptor
                self.recordingURL = url
                self.recordingStartTime = nil
                writer.startWriting()
                DispatchQueue.main.async {
                    self.recordingDuration = 0
                    self.lastSaveMessage = nil
                    self.isRecording = true
                    self.startDurationTimer()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastSaveMessage = "錄影啟動失敗：\(error.localizedDescription)"
                }
            }
        }
    }
    
    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            let writer = self.assetWriter
            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.pixelBufferAdaptor = nil
            let url = self.recordingURL
            self.recordingURL = nil
            writer?.finishWriting { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.stopDurationTimer()
                }
                if writer?.status == .completed, let url {
                    self.saveToPhotoLibrary(videoURL: url)
                } else if let error = writer?.error {
                    DispatchQueue.main.async {
                        self.lastSaveMessage = "錄影失敗：\(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.cancel()
        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recordingDuration += 1
            }
    }
    
    private func stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = nil
    }
    
    private func saveToPhotoLibrary(videoURL: URL) {
        let requestAuth: (@escaping (PHAuthorizationStatus) -> Void) -> Void
        if #available(iOS 14, *) {
            requestAuth = { handler in
                PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: handler)
            }
        } else {
            requestAuth = PHPhotoLibrary.requestAuthorization
        }
        requestAuth { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.lastSaveMessage = "請在設定中允許寫入相簿"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.lastSaveMessage = "儲存失敗：\(error.localizedDescription)"
                    } else if success {
                        self.lastSaveMessage = "已儲存到相簿"
                    }
                }
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            processVideoSampleBuffer(sampleBuffer)
        } else if output == audioOutput {
            processAudioSampleBuffer(sampleBuffer)
        }
    }
    
    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let assetWriter = assetWriter,
              assetWriter.status == .writing,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor,
              let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if recordingStartTime == nil {
            recordingStartTime = presentationTime
            assetWriter.startSession(atSourceTime: presentationTime)
        }
        guard let pool = adaptor.pixelBufferPool else { return }
        var newBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &newBuffer) == kCVReturnSuccess, let pixelBuffer = newBuffer else { return }
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        let size = CGSize(width: width, height: height)
        var image = CIImage(cvPixelBuffer: sourceBuffer)
        if let overlay = overlayRenderer.makeOverlay(for: size) {
            image = overlay.composited(over: image)
        }
        ciContext.render(image, to: pixelBuffer)
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }
    
    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              recordingStartTime != nil,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }
}

private enum LensType: Equatable {
    case wide
    case ultraWide
}

private enum RecordingError: Error {
    case cannotAddVideoInput
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        updateOrientation(for: view.videoPreviewLayer.connection)
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        updateOrientation(for: uiView.videoPreviewLayer.connection)
    }
    
    private func updateOrientation(for connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoOrientationSupported {
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
