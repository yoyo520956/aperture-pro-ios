#!/usr/bin/env python3
"""原子修复 Aperture Pro 剩余 Photos API 错签名（第 2 轮）
官方签名已核验（developer.apple.com 文档 JSON 直接抓取）：
- PHAssetCreationRequest.forAsset() + addResource(with:data:options:) / addResource(with:fileURL:options:)   ✅ 存在
- PHAssetChangeRequest.creationRequestForAsset(from:)             ❌ 不存在（只有 UIImage 的 update）
- PHAssetCreationRequest.addPhoto/addLivePhoto                     ❌ 不存在
- PHVideoExportSession / PHVideoExportPreset                       ❌ 404 不存在
- PHImageManager.requestExportSession(forVideo:options:exportPreset:resultHandler:) -> (AVAssetExportSession?, [AnyHashable: Any]?)  ✅ 真身
"""
import io, os, sys
ROOT = "/var/minis/workspace/aperture-pro/repo"

def patch(rel, pairs):
    path = os.path.join(ROOT, rel)
    src = io.open(path, encoding="utf-8").read()
    for old, new in pairs:
        if old not in src:
            print(f"!! MISS in {rel}: {old[:80]!r}")
            sys.exit(2)
        src = src.replace(old, new)
        print(f"   ok: {old.strip().splitlines()[0][:70]}")
    tmp = path + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(src)
    os.replace(tmp, path)
    print(f"   wrote {rel} ({len(src.encode())}B)")

# ---- 1) LivePhotoService：addPhoto / addLivePhoto 都不存在 ----
patch("Sources/Core/LivePhoto/LivePhotoService.swift", [
(
"""/// Live Photo 保存服务
/// 相机 requestLivePhotoCapture 得到 .mov 后，按 Apple 官方范式
/// 组装 AVLivePhotoPhoto，和照片一起写进系统相册
@MainActor
enum LivePhotoService {
    static func saveLivePhoto(videoURL: URL, photoData: Data) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addPhoto(from: photoData, options: nil)
            if let lp = buildLivePhoto(videoURL: videoURL) {
                request.addLivePhoto(lp)
            }
        } completionHandler: { success, _ in
            NSLog("live photo saved: \\(success)")
        }
    }

    /// 官方 WWDC17 范式：reader→writer 复制 mov，再包 AVLivePhotoPhoto
    private nonisolated static func buildLivePhoto(videoURL: URL) -> AVLivePhotoPhoto? {
        let srcAsset = AVURLAsset(url: videoURL)
        guard let track = srcAsset.tracks(with: .video).first else { return nil }
        do {
            let reader = try AVAssetReader(asset: srcAsset)
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(readerOutput)

            let writerURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("liveout_\\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: writerURL, fileType: .mov)
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            guard writer.canInput(writerInput) else { return nil }
            writer.add(writerInput)

            reader.startReading()
            writer.startWriting()
            writer.startSession()
            while reader.status == .reading,
                  let sample = readerOutput.copyNextSampleBuffer() {
                if writerInput.isReadyForMoreMediaData {
                    writerInput.append(sample)
                }
            }
            writerInput.markAsFinished()
            writer.finishWriting { _ in }
            return AVLivePhotoPhoto(asset: AVURLAsset(url: writerURL), previewImageKey: .default)
        } catch {
            NSLog("live photo build error: \\(error.localizedDescription)")
            return nil
        }
    }
}""",
"""/// Live Photo 保存服务
/// 相机 requestLivePhotoCapture 得到 .mov，按 Apple 官方范式
/// 把静态图（.photo）+ 配对视频（.pairedVideo）一起写进系统相册
/// 说明：AVCapturePhotoOutput 的 movieFileDataRepresentation() 已自带
/// Live Photo 配对 metadata（asset identifier / still image time），
/// 直接作为 .pairedVideo 资源即可，无需再 reader→writer 重封装。
@MainActor
enum LivePhotoService {
    static func saveLivePhoto(videoURL: URL, photoData: Data) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        } completionHandler: { success, error in
            NSLog("live photo saved: \\(success) error: \\(error?.localizedDescription ?? "-")")
        }
    }
}"""
),
])

# ---- 2) VideoExporter：creationRequestForAsset(from: URL) 不存在 ----
patch("Sources/Features/VideoEditor/VideoExporter.swift", [
(
"""        _ = PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: outURL)
        }""",
"""        _ = PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: outURL, options: nil)
        }"""
),
])

# ---- 3) PHLibraryService.exportVideo：PHVideoExportSession/Preset 不存在 ----
patch("Sources/Core/PHLibrary/PHLibraryService.swift", [
(
"""    /// 视频导出到临时目录
    static func exportVideo(_ assetID: String, completion: @escaping (URL?) -> Void) {
        let options = PHFetchOptions()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard result.count > 0, let asset = result.firstObject else {
            completion(nil)
            return
        }
        let options2 = PHVideoExportSession(options: PHVideoExportPreset.muxFormatH264AVCProfileBaseline)
        options2.outputFileType = .mpeg4
        let session = PHVideoExportSession(asset: asset, options: options2)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\\(assetID).m4v")
        session.outputFileURL = outURL
        session.startExporting { status, _ in
            DispatchQueue.main.async {
                if status == .completed, FileManager.default.fileExists(atPath: outURL.path) {
                    completion(outURL)
                } else {
                    completion(nil)
                }
            }
        }
    }""",
"""    /// 视频导出到临时目录
    /// 官方 API：requestExportSession(forVideo:options:exportPreset:resultHandler:)
    /// 回调给的是 (AVAssetExportSession?, [AnyHashable: Any]?)
    static func exportVideo(_ assetID: String, completion: @escaping (URL?) -> Void) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else {
            completion(nil)
            return
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\\(assetID).m4v")
        let options = PHVideoRequestOptions()
        PHImageManager.default().requestExportSession(
            forVideo: asset,
            options: options,
            exportPreset: AVAssetExportPresetPassthroughQuality
        ) { session, info in
            guard let session else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            session.outputURL = outURL
            session.outputFileType = .mpeg4
            try? FileManager.default.removeItem(at: outURL)
            session.exportAsynchronously {
                DispatchQueue.main.async {
                    if session.status == .completed, FileManager.default.fileExists(atPath: outURL.path) {
                        completion(outURL)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }"""
),
])

print("ALL PATCHED ROUND 2")
