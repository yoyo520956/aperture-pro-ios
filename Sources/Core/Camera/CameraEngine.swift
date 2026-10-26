import AVFoundation
import CoreImage
import UIKit
import Photos

/// 相机引擎 v2：拍照 / 录像 / 4K / 慢动作 / 夜景 / HDR / Live Photo / 稳定器
@MainActor
class CameraEngine: ObservableObject {
    enum CaptureMode: String, CaseIterable {
        case photo = "照片"
        case video = "录像"
        case slowMo = "慢动作"
        case timelapse = "延时"
        case livePhoto = "Live"
        case night = "夜景"
        case panorama = "全景"
        case document = "文档"
    }

    @Published var isRunning: Bool = false
    @Published var isCapturing: Bool = false
    @Published var flashMode: AVFlashMode = .off
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var mode: CaptureMode = .photo
    @Published var recordingName: String = ""

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDataCallback: ((CMSampleBuffer) -> Void)?
    private var photoDoneCallback: ((Data) -> Void)?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    let filterEngine = FilterEngine()
    var panoramaEngine = PanoramaEngine()
    let timelapse = TimelapseEngine()
    /// 拍摄成功后回调
    var onPhotoCaptured: ((Data) -> Void)?
    /// 录像结束后回调（文件名）
    var onVideoFinished: ((String) -> Void)?

    static var mediaDir: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var sessionConfigured: Bool { session.inputs.count > 0 }

    // MARK: 会话

    func configure() {
        guard session.inputs.isEmpty else { return }
        setupVideoOutput()
        setupPhotoOutput()
        setupMovieOutput()
        switchCamera(cameraPosition)
        session.sessionPreset = .high
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
        if let device = currentDevice {
            switchCameraInput(device: device, position: position)
            applyStabilization()
        }
    }

    private func switchCameraInput(device: AVCaptureDevice, position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        let want: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        let dev = AVCaptureDevice.default(want, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        if let dev, let input = try? AVCaptureDeviceInput(device: dev) {
            session.addInput(input)
        }
        applyStabilization()
        session.commitConfiguration()
    }

    private func applyStabilization() {
        guard let device = currentDevice else { return }
        if device.stabilizationSupported {
            if device.supportsStabilization(.cinematicAuto) {
                device.stabilization = .cinematicAuto
            } else {
                device.stabilization = .standard
            }
        }
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

    var currentDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: 模式切换

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        session.beginConfiguration()
        switch mode {
        case .timelapse:
            timelapse.start(width: 1280, height: 720)
        case .panorama:
            panoramaEngine.reset()
        case .slowMo:
            configureFormat(width: 1920, height: 1080, fps: 120)
            session.sessionPreset = .photo4032x3024
        case .night:
            configureFormat(width: 3840, height: 2160, fps: 30)
            session.sessionPreset = .photo4032x3024
        default:
            session.sessionPreset = .high
            timelapse.stop()
            break
        }
        session.commitConfiguration()
    }

    /// 按分辨率 + 帧率挑一个可用的设备 format（慢动作要 120fps）
    private func configureFormat(width: Int32, height: Int32, fps: Int32) {
        guard let device = currentDevice else { return }
        let matched = device.formats.first { fmt -> Bool in
            let size = fmt.videoSupportedDimensions.contains {
                abs($0.width - width) < 64 && abs($0.height - height) < 64
            }
            let rate = fmt.videoSupportedFrameRates.contains { abs($0.value - Double(fps)) < 1.5 }
            return size && rate
        }
        if let matched {
            do { try device.setActiveFormat(matched) } catch {
                NSLog("format switch failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: 拍照

    func capturePhoto() {
        guard !isCapturing else { return }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if photoOutput.isFlashSupported {
            settings.flashMode = flashMode
        }
        switch mode {
        case .night:
            if AVCapturePhotoSettings.supportsLowLightMode {
                settings.lowLightMode = .night
            }
            if AVCapturePhotoSettings.supportsHighDynamicRange20Bit {
                settings.isHighDynamicRange20BitEnabled = true
            }
        case .livePhoto:
            captureLivePhoto()
            return
        default:
            break
        }
        isCapturing = true
        photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate(self))
    }

    /// Live Photo：先向设备申请 live 输出格式，再走 live 拍照
    private func captureLivePhoto() {
        guard let device = currentDevice, device.supportsLivePhotoCapture else {
            capturePhoto()
            return
        }
        device.requestLivePhotoCapture { [weak self] outputFormat, error in
            guard let self else { return }
            guard let outputFormat, error == nil else {
                DispatchQueue.main.async {
                    self.capturePhoto()
                    self.isCapturing = false
                }
                return
            }
            let settings = AVCapturePhotoSettings(livePhotoCaptureOutputFormat: outputFormat)
            settings.photoQualityPrioritization = .auto
            if self.photoOutput.isFlashSupported {
                settings.flashMode = self.flashMode
            }
            self.isCapturing = true
            self.photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate(self))
        }
    }

    // MARK: 录像

    func startRecording() {
        guard !isCapturing else { return }
        let name = "rec_\(Int(Date().timeIntervalSince1970)).mov"
        let outURL = Self.mediaDir.appendingPathComponent(name)
        recordingName = name
        movieOutput.startRecording(to: outURL, delegate: MovieRecordingDelegate(self))
        isCapturing = true
    }

    func stopRecording() -> String? {
        guard isCapturing, mode == .video || mode == .slowMo else { return nil }
        movieOutput.stopRecording()
        isCapturing = false
        return recordingName
    }

    // MARK: 回调注入

    func setFrameCallback(_ callback: @escaping ((CMSampleBuffer) -> Void)) {
        videoDataCallback = callback
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        videoPreviewLayer = layer
        layer.session = session
    }
}

extension CameraEngine {
    struct VideoDataDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let parent: CameraEngine

        func videoDataOutput(
            _ output: AVCaptureVideoDataOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from _ connection: AVCaptureConnection
        ) {
            parent.videoDataCallback?(sampleBuffer)
        }
    }
}

extension CameraEngine {
    struct PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        let parent: CameraEngine

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            guard let data = photo.fileDataRepresentation() else {
                DispatchQueue.main.async { self.parent.isCapturing = false }
                return
            }
            DispatchQueue.main.async {
                if self.parent.mode == .livePhoto {
                    if let movieData = photo.movieFileDataRepresentation() {
                        let liveURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("live_\(UUID().uuidString).mov")
                        try? movieData.write(to: liveURL)
                        LivePhotoService.saveLivePhoto(videoURL: liveURL, photoData: data)
                    }
                }
                let dest = Self.mediaDirURL().appendingPathComponent("p_\(UUID().uuidString).jpg")
                try? data.write(to: dest)
                self.parent.isCapturing = false
                self.parent.onPhotoCaptured?(data)
            }
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishCapturingPhotoInHighResolution _ photo: AVCapturePhoto,
            error: Error?
        ) {}
    }

    private static func mediaDirURL() -> URL {
        CameraEngine.mediaDir
    }
}

extension CameraEngine {
    struct MovieRecordingDelegate: NSObject, AVCaptureFileDataRecordingDelegate {
        let parent: CameraEngine

        func fileOutput(
            _ output: AVCaptureFileDataOutput,
            didStartRecordingTo fileURL: URL,
            recordingTimeIn _ fileDuration: CMTime
        ) {}

        func fileOutput(
            _ output: AVCaptureFileDataOutput,
            didFinishRecordingTo fileURL: URL,
            from time: CMTime,
            error: Error?
        ) {
            DispatchQueue.main.async {
                let name = fileURL.lastPathComponent
                self.parent.isCapturing = false
                self.parent.onVideoFinished?(name)
            }
        }

        func fileOutput(
            _ output: AVCaptureFileDataOutput,
            didRecordFileDataForType type: AVMediaType,
            at fileURL: URL
        ) {}
    }
}
