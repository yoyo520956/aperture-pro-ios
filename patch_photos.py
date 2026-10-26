#!/usr/bin/env python3
"""原子修复 Aperture Pro 全库 Photos API 错签名
Apple 官方签名（已用 developer.apple.com 文档 JSON 核验）：
  PHAssetCreationRequest.forAsset() -> PHAssetCreationRequest
  request.addResource(with: .photo, data: Data, options: PHAssetResourceCreationOptions?)
  request.addResource(with: .video, fileURL: URL, options: PHAssetResourceCreationOptions?)
  PHAssetChangeRequest.creationRequestForAsset(from: UIImage) -> Self   ← 只吃 UIImage！
不存在 creationRequestForAsset(from: Data) / (from: URL)，也不存在 addPhoto / addLivePhoto。
"""
import io, os, sys

ROOT = "/var/minis/workspace/aperture-pro/repo"

def patch(rel, pairs):
    path = os.path.join(ROOT, rel)
    with io.open(path, "r", encoding="utf-8") as f:
        src = f.read()
    orig = src
    for old, new in pairs:
        if old not in src:
            print(f"!! MISS in {rel}: {old[:70]!r}")
            sys.exit(2)
        cnt = src.count(old)
        src = src.replace(old, new)
        print(f"   ok x{cnt}: {old.strip().splitlines()[0][:64]}")
    if src != orig:
        tmp = path + ".tmp"
        with io.open(tmp, "w", encoding="utf-8") as f:
            f.write(src)
        os.replace(tmp, path)
        print(f"   wrote {rel} ({len(src.encode())}B)")

# ---- 1) PHLibraryService：Data/URL 写入 ----
patch("Sources/Core/PHLibrary/PHLibraryService.swift", [
(
"""            guard let asset = PHAssetChangeRequest.creationRequestForAsset(from: data) as? PHAsset else {
                return
            }
            _ = asset""",
"""            // 官方范式：forAsset() + addResource(with:data:)
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)"""
),
(
"""            PHAssetChangeRequest.creationRequestForAsset(from: url)""",
"""            // 官方范式：forAsset() + addResource(with:fileURL:)
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)"""
),
])

# ---- 2) LivePhotoService：addPhoto / addLivePhoto 都不存在 ----
patch("Sources/Core/LivePhoto/LivePhotoService.swift", [
(
"""            let request = PHAssetCreationRequest.forAsset()
            request.addPhoto(from: photoData, options: nil)
            if let lp = buildLivePhoto(videoURL: videoURL) {
                request.addLivePhoto(lp)
            }""",
"""            // 官方范式：静态图走 .photo，配对视频走 .pairedVideo
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            if let lpURL = buildLivePhoto(videoURL: videoURL) {
                request.addResource(with: .pairedVideo, fileURL: lpURL, options: nil)
            }"""
),
(
"""    private nonisolated static func buildLivePhoto(videoURL: URL) -> AVLivePhotoPhoto? {""",
"""    private nonisolated static func buildLivePhoto(videoURL: URL) -> URL? {"""
),
(
"""                writer.finishWriting { _ in }
                return AVLivePhotoPhoto(asset: AVURLAsset(url: writerURL), previewImageKey: .default)""",
"""                writer.finishWriting { _ in }
                return writerURL"""
),
])

# ---- 3) VideoExporter：URL 版本不存在 ----
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

print("ALL PATCHED")
