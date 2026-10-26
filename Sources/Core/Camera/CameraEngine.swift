import AVFoundation
import CoreImage

@MainActor
class CameraEngine: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isCapturing: Bool = false
    @Published var flashMode: AVFlashMode = .off
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isFilterEnabled: Bool = false

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var videoDataCallback: ((CMSampleBuffer) -> Void)?
    private var pendingFrame: Data?

    let filterEngine = FilterEngine()

    var sessionConfigured: Bool {
        session.inputs.count > 0
    }

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        setupVideoOutput()
        setupPhotoOutput()
        setupMovieOutput()
        switchCamera(cameraPosition)
        session.commitConfiguration()
    }

    private func setupVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(VideoDataDelegate(self), queue: DispatchQueue(label: "video.data.queue"))
        session.addOutput(videoOutput)
    }

    private func setupPhotoOutput() {
        if photoOutput.isFlashSupported {
            photoOutput.flashMode = flashMode
        }
        session.addOutput(photoOutput)
    }

    private func setupMovieOutput() {
        session.addOutput(movieOutput)
    }

    func switchCamera(_ position: AVCaptureDevice.Position) {
        cameraPosition = position
        if let device = AVCaptureDevice.default(for: .video) {
            switchCameraInput(device: device, position: position)
        }
    }

    private func switchCameraInput(device: AVCaptureDevice, position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        switch position {
        case .front:
            if let frontDevice = AVCaptureDevice.devices(for: .video).first(where: { $0.position == .front }),
               let input = try? AVCaptureDeviceInput(device: frontDevice) {
                session.addInput(input)
            }
        case .back:
            if let backDevice = AVCaptureDevice.devices(for: .video).first(where: { $0.position == .back }),
               let input = try? AVCaptureDeviceInput(device: backDevice) {
                session.addInput(input)
            }
        @unknown default:
            break
        }
        session.commitConfiguration()
    }

    func start() {
        guard !isRunning else { return }
        configure()
        session.startRunning()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    func setFlash(_ mode: AVFlashMode) {
        flashMode = mode
        if photoOutput.isFlashSupported {
            photoOutput.flashMode = mode
        }
    }

    func capturePhoto() -> Data? {
        guard !isCapturing else { return nil }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if photoOutput.isFlashSupported {
            settings.flashMode = flashMode
        }
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate(self))
        return pendingFrame
    }

    func startRecording() {
        guard !isCapturing else { return }
        let outputURL = FileManager.default.urlsForInDirectory(.documentDirectory).first!
            .appendingPathComponent("rec_\(Date().timeIntervalSince1970).mov")
        movieOutput.startRecording(to: outputURL, delegate: MovieRecordingDelegate(self))
        isCapturing = true
    }

    func stopRecording() -> String? {
        guard isCapturing else { return nil }
        let fileURL = movieOutput.recordedVideoFileURL
        movieOutput.stopRecording()
        isCapturing = false
        return fileURL?.lastPathComponent
    }

    func setFrameCallback(_ callback: @escaping ((CMSampleBuffer) -> Void)) {
        videoDataCallback = callback
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        videoPreviewLayer = layer
        layer.session = session
    }
}

extension CameraEngine {
    func configureCameraInput(position: AVCaptureDevice.Position) {
        switch position {
        case .back:
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                try? device.lockForConfiguration()
                device.isFlashMode = flashMode
                device.unlockForConfiguration()
                switchCameraInput(device: device, position: .back)
            }
        case .front:
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                switchCameraInput(device: device, position: .front)
            }
        @unknown default:
            break
        }
    }

    var currentDevice: AVCaptureDevice? {
        AVCaptureDevice.default(for: .video)
    }
}

extension CameraEngine {
    struct VideoDataDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let parent: CameraEngine

        func videoDataOutput(_ output: AVCaptureVideoDataOutput, didOutput sampleBuffer: CMSampleBuffer, from _ connection: AVCaptureConnection) {
            parent.videoDataCallback?(sampleBuffer)
        }
    }
}

extension CameraEngine {
    struct PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        let parent: CameraEngine

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let data = photo.fileDataRepresentation() {
                parent.pendingFrame = data
                DispatchQueue.main.async {
                    self.parent.isCapturing = false
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.isCapturing = false
                }
            }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingPhotoInHighResolution _ photo: AVCapturePhoto, error: Error?) {
        }
    }
}

extension CameraEngine {
    struct MovieRecordingDelegate: NSObject, AVCaptureFileDataRecordingDelegate {
        let parent: CameraEngine

        func fileOutput(_ output: AVCaptureFileDataOutput, didStartRecordingTo fileURL: URL, recordingTimeIn _ fileDuration: CMTime) {
        }

        func fileOutput(_ output: AVCaptureFileDataOutput, didFinishRecordingTo fileURL: URL, from time: CMTime, error: Error?) {
            DispatchQueue.main.async {
                self.parent.isCapturing = false
            }
        }

        func fileOutput(_ output: AVCaptureFileDataOutput, didRecordFileDataForType type: AVMediaType, at fileURL: URL) {
        }
    }
}
