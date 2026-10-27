import AVFoundation
import CoreImage
import ImageIO
import UIKit
import Photos

/// 相机引擎 v2：拍照 / 录像 / 4K / 慢动作 / 夜景 / HDR / Live Photo / 稳定器
/// 全部使用 Apple 官方公开 API（iOS 16 基线），公开接口与 v2 保持一致
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
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var mode: CaptureMode = .photo
    @Published var recordingName: String = ""

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    /// 帧回调代理（delegate 自持回调，避开 @MainActor 隔离冲突）
    private let videoDelegate = VideoDataDelegate()
    /// 录像委托（AVFoundation 不强持有，引擎强持有）
    private var movieDelegate: MovieRecordingDelegate?
    /// 拍照委托强持有（AV 拍照期间不强持有 delegate，需自持）
    private var photoDelegates: [NSObject] = []
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    let filterEngine = FilterEngine()
    var panoramaEngine = PanoramaEngine()
    let timelapse = TimelapseEngine()
    /// 拍摄成功后回调
    var onPhotoCaptured: ((Data) -> Void)?
    /// 录像结束后回调（文件名）
    var onVideoFinished: ((String) -> Void)?
    /// 慢动作成片（0.25× 导出）完成后回调
    var onSlowMoFinished: ((String) -> Void)?
    /// 夜景是否走多帧堆栈融合（默认开；关 = 单帧长曝）
    @Published var nightStack: Bool = true
    var nightQueue: [CIImage] = []
    var nightEVs: [Double] = []

    nonisolated static var mediaDir: URL {
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
        session.beginConfiguration()
        setupVideoOutput()
        setupPhotoOutput()
        setupMovieOutput()
        session.commitConfiguration()
        switchCamera(cameraPosition)
        session.sessionPreset = .high
    }

    private func setupVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoDelegate.parent = self
        videoOutput.setSampleBufferDelegate(videoDelegate,
                                             queue: DispatchQueue(label: "video.data.queue"))
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    }

    private func setupPhotoOutput() {
        // Live Photo 能力在 output 上开启（官方：isLivePhotoCaptureSupported / Enabled）
        if photoOutput.isLivePhotoCaptureSupported {
            photoOutput.isLivePhotoCaptureEnabled = true
        }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
    }

    private func setupMovieOutput() {
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
    }

    func switchCamera(_ position: AVCaptureDevice.Position) {
        cameraPosition = position
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        let want: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        let dev = AVCaptureDevice.default(want, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        if let dev, let input = try? AVCaptureDeviceInput(device: dev) {
            if session.canAddInput(input) { session.addInput(input) }
        }
        session.commitConfiguration()
        applyStabilization()
    }

    /// 官方防抖：AVCaptureConnection.preferredVideoStabilizationMode
    /// .auto 由系统按机型选最高档（A12+ 自动给 .cinematic），对应旧意图 cinematicAuto→standard 降级
    private func applyStabilization() {
        applyStabilization(on: videoOutput.connection(with: .video))
        applyStabilization(on: movieOutput.connection(with: .video))
    }

    private func applyStabilization(on connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = .auto
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

    /// 闪光模式按照片粒度生效（官方：settings.flashMode），这里只记状态
    func setFlash(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }

    var currentDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: 模式切换

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        switch mode {
        case .timelapse:
            timelapse.start(width: 1280, height: 720)
        case .panorama:
            panoramaEngine.reset()
        case .slowMo:
            configureFormat(width: 1920, height: 1080, fps: 120)
            session.sessionPreset = .hd1920x1080
        case .night:
            configureFormat(width: 3840, height: 2160, fps: 30)
            session.sessionPreset = .hd4K3840x2160
        case .photo:
            session.sessionPreset = .photo
            timelapse.stop()
        default:
            session.sessionPreset = .high
            timelapse.stop()
        }
    }

    /// 按分辨率 + 帧率挑一个可用的设备 format（慢动作要 120fps）
    /// 官方 API：CMVideoFormatDescriptionGetDimensions + videoSupportedFrameRateRanges + lockForConfiguration
    private func configureFormat(width: Int32, height: Int32, fps: Int32) {
        guard let device = currentDevice else { return }
        var matched: AVCaptureDevice.Format?
        for fmt in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let sizeOK = abs(Int(dims.width) - Int(width)) < 64
                && abs(Int(dims.height) - Int(height)) < 64
            guard sizeOK else { continue }
            var rateOK = false
            for range in fmt.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(fps) - 1.5 { rateOK = true; break }
            }
            if rateOK { matched = fmt; break }
        }
        guard let fmt = matched else {
            NSLog("configureFormat: no format for %dx%d@%d, keep current", width, height, fps)
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = fmt
            device.unlockForConfiguration()
        } catch {
            NSLog("format switch failed: %@", error.localizedDescription)
        }
    }

    // MARK: 拍照

    func capturePhoto() {
        guard !isCapturing else { return }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        settings.isAutoStillImageStabilizationEnabled = true
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        switch mode {
        case .night:
            if nightStack {
                captureNightStack()
                return
            }
            // 官方低光增强：device.automaticallyEnablesLowLightBoostWhenAvailable
            if let device = currentDevice, device.isLowLightBoostSupported {
                do {
                    try device.lockForConfiguration()
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                    device.unlockForConfiguration()
                } catch {
                    NSLog("low light boost failed: %@", error.localizedDescription)
                }
            }
        case .livePhoto:
            captureLivePhoto()
            return
        default:
            break
        }
        isCapturing = true
        let delegate = PhotoCaptureDelegate()
        delegate.parent = self
        retainPhotoDelegate(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    /// Live Photo 官方范式（AVCam）：
    /// settings.livePhotoMovieFileURL + quickTimeMetadataKeyContentIdentifier
    /// + JPEG MakerApple 字典 "17"（asset identifier）双向配对，
    /// 影片落盘走 delegate 的 didFinishRecordingLivePhotoMovieForEventualFileAt 回调
    private func captureLivePhoto() {
        guard photoOutput.isLivePhotoCaptureSupported else {
            capturePhoto()
            return
        }
        photoOutput.isLivePhotoCaptureEnabled = true
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        let assetID = UUID().uuidString
        let movieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("live_\(assetID).mov")
        settings.livePhotoMovieFileURL = movieURL
        let idItem = AVMutableMetadataItem()
        idItem.keySpace = .quickTimeMetadata
        idItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier
            as (NSCopying & NSObjectProtocol)?
        idItem.value = assetID as (NSCopying & NSObjectProtocol)?
        settings.livePhotoMovieMetadata = [idItem]
        settings.metadata["MakerApple"] = ["17": assetID]
        isCapturing = true
        let delegate = PhotoCaptureDelegate()
        delegate.parent = self
        retainPhotoDelegate(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    /// 拍照收尾统一出口：写盘 + 回调
    func finishCapture(_ data: Data) {
        let dest = Self.mediaDir.appendingPathComponent("p_\(UUID().uuidString).jpg")
        try? data.write(to: dest)
        isCapturing = false
        onPhotoCaptured?(data)
    }

    // MARK: 录像

    func startRecording() {
        guard !isCapturing else { return }
        let name = "rec_\(Int(Date().timeIntervalSince1970)).mov"
        let outURL = Self.mediaDir.appendingPathComponent(name)
        recordingName = name
        let delegate = MovieRecordingDelegate()
        delegate.parent = self
        movieDelegate = delegate
        movieOutput.startRecording(to: outURL, recordingDelegate: delegate)
        isCapturing = true
    }

    func stopRecording() -> String? {
        guard isCapturing, mode == .video || mode == .slowMo else { return nil }
        movieOutput.stopRecording()
        isCapturing = false
        let name = recordingName
        // 慢动作模式：自动把 120fps 原片导成 0.25× 慢放成片进相册
        if mode == .slowMo {
            Task { [weak self] in
                let ok = await self?.exportSlowMo(name) ?? false
                if ok {
                    self?.onSlowMoFinished?("slowmo")
                }
            }
        }
        return name
    }

    /// 120fps 源 → 0.25× 慢放成片（去原声）
    func exportSlowMo(_ name: String) async -> Bool {
        let url = Self.mediaDir.appendingPathComponent(name)
        return await SlowMotionExporter.export(source: url)
    }

    // MARK: 夜景多帧堆栈（5 帧 ISO 包围 + Mantiuk 融合）

    func captureNightStack() {
        guard let device = currentDevice else { return }
        nightQueue = []
        nightEVs = []
        isCapturing = true
        captureNightFrame(index: 0, of: 5, device: device)
    }

    /// ISO 包围：base × 2^(index-mid)，官方 setExposureModeCustom(duration:iso:) 手动曝光
    func captureNightFrame(index: Int, of total: Int, device: AVCaptureDevice) {
        guard index < total else {
            finishNightStack()
            return
        }
        let mid = Double(total - 1) / 2.0
        let base = Double(device.iso)
        let target = Float(base * pow(2.0, Double(index) - mid))
        // minISO/maxISO 在当前 SDK 不可用，改用通用夹取区间
        let clampedISO = Float(max(100.0, min(12800.0, Double(target))))
        let quarter: CMTime = CMTime(seconds: 0.25, preferredTimescale: 600)
        let maxDur = device.activeFormat.maxExposureDuration
        let dur = CMTimeCompare(maxDur, quarter) < 0 ? maxDur : quarter
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: dur, iso: clampedISO, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            NSLog("manual exposure failed: %@", error.localizedDescription)
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        let delegate = NightStackDelegate()
        delegate.parent = self
        delegate.index = index
        delegate.total = total
        delegate.ev = Double(index) - mid
        retainPhotoDelegate(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    func finishNightStack() {
        let frames = nightQueue
        let evs = nightEVs
        nightQueue = []
        nightEVs = []
        guard !frames.isEmpty else {
            isCapturing = false
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var jpeg: Data?
            if let fused = NightFusion.fuse(frames: frames, evs: evs) {
                jpeg = NightFusion.renderJPEG(fused)
            }
            if jpeg == nil {
                jpeg = NightFusion.renderJPEG(frames[frames.count / 2])
            }
            await MainActor.run {
                guard let data = jpeg else {
                    self.isCapturing = false
                    return
                }
                let url = Self.mediaDir.appendingPathComponent(
                    "night_\(Int(Date().timeIntervalSince1970)).jpg"
                )
                try? data.write(to: url)
                PHLibraryService.saveImage(data)
                self.isCapturing = false
                self.onPhotoCaptured?(data)
            }
        }
    }

    // MARK: 委托强持有（AV 不强持有拍照 delegate）

    func retainPhotoDelegate(_ delegate: NSObject) {
        photoDelegates.append(delegate)
        // 顺带清掉已释放 parent 的旧委托
        photoDelegates.removeAll {
            ($0 as? PhotoCaptureDelegate)?.parent == nil
                || ($0 as? NightStackDelegate)?.parent == nil
        }
    }

    // MARK: 回调注入

    func setFrameCallback(_ callback: @escaping ((CMSampleBuffer) -> Void)) {
        videoDelegate.callback = callback
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        videoPreviewLayer = layer
        layer.session = session
    }
}

// MARK: - 帧数据委托（视频队列回调，非隔离类）

final class VideoDataDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var parent: CameraEngine?
    /// 主线程写、视频队列读：预览帧管线可容忍良性竞态
    var callback: ((CMSampleBuffer) -> Void)?

    func videoDataOutput(
        _ output: AVCaptureVideoDataOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        callback?(sampleBuffer)
    }
}

// MARK: - 夜景堆栈委托：逐帧 ISO 包围 → 收齐进融合

final class NightStackDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var parent: CameraEngine?
    var index: Int = 0
    var total: Int = 5
    var ev: Double = 0

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            guard let parent = self.parent else { return }
            if let data, let ci = CIImage(data: data) {
                parent.nightQueue.append(ci)
                parent.nightEVs.append(self.ev)
            }
            if self.index + 1 < self.total, let device = parent.currentDevice {
                parent.captureNightFrame(index: self.index + 1, of: self.total, device: device)
            } else {
                parent.finishNightStack()
            }
        }
    }
}

// MARK: - 拍照委托（含 Live Photo 影片完成回调）

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var parent: CameraEngine?
    /// Live 模式：照片先到，暂存等配对影片回调
    private var pendingJPEG: Data?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            guard let parent = self.parent else { return }
            guard let data else {
                parent.isCapturing = false
                return
            }
            if parent.mode == .livePhoto {
                self.pendingJPEG = data
                // 兜底：2 秒内配对影片回调没来，就按普通照片收尾
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    guard let pending = self.pendingJPEG else { return }
                    self.pendingJPEG = nil
                    parent.finishCapture(pending)
                }
                return
            }
            parent.finishCapture(data)
        }
    }

    /// 官方 Live 影片落盘回调：与 JPEG 一起交给 LivePhotoService（.photo + .pairedVideo）
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL,
        resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        DispatchQueue.main.async {
            guard let parent = self.parent, let jpeg = self.pendingJPEG else { return }
            self.pendingJPEG = nil
            LivePhotoService.saveLivePhoto(videoURL: outputFileURL, photoData: jpeg)
            parent.finishCapture(jpeg)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {}
}

// MARK: - 录像委托（官方 AVCaptureFileOutputRecordingDelegate）

final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var parent: CameraEngine?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {}

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            NSLog("record failed: %@", error.localizedDescription)
        }
        DispatchQueue.main.async {
            self.parent?.isCapturing = false
            self.parent?.onVideoFinished?(outputFileURL.lastPathComponent)
        }
    }
}
