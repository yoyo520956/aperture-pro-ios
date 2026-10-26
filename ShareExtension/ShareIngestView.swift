import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers

#if canImport(ExtensionFoundation)
import ExtensionFoundation
#endif

// MARK: - 分享扩展主类

/// 侧载 + 无 App Group 环境下：主类用纯 UIKit + SwiftUI（必定可编译）。
/// 入库走 best-effort——能取到共享项就写系统相册，取不到也正常收尾。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let card = UIHostingController(rootView: ShareIngestCard())
        addChild(card)
        card.view.frame = view.bounds
        view.addSubview(card.view)
        card.didMove(toParent: self)
        ingestBestEffort()
    }
}

// MARK: - SwiftUI 卡片

struct ShareIngestCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("Aperture Pro")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("共享内容将写入系统相册")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97))
    }
}

// MARK: - best-effort 入库（拿得到共享项才写）

/// iOS 18 SDK 里 requestAuthorization(for:handler:) 存在返回 DispatchWorkItem 的重载，
/// 尾随闭包会撞歧义；改用 async 版 requestAuthorization(for:) -> Task，无歧义。
private func ingestBestEffort() {
    Task {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            NSLog("[Share] 无相册写入权限，跳过入库")
            return
        }
        // 扩展沙箱内无 App Group，无法直接拿主 App 的附件；
        // 若系统把共享项临时落盘到扩展容器则这里可读到，否则跳过。
        // 注意：SearchPathDirectory 没有 .temporaryDirectory 成员，temp 目录要用 property
        let cacheDirs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let bases = cacheDirs + [FileManager.default.temporaryDirectory]
        var photos: [Data] = []
        for base in bases {
            let items = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            for url in items {
                let ext = url.pathExtension.lowercased()
                if ext == "jpg" || ext == "jpeg" {
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        photos.append(data)
                    }
                }
            }
        }
        guard !photos.isEmpty else {
            NSLog("[Share] 扩展容器内无共享图片，跳过入库")
            return
        }
        // 与主 App PHLibraryService 同款调用（已验证可编译）：Data → 相册
        PHPhotoLibrary.shared().performChanges {
            for data in photos {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: data)
            }
        }
        PHPhotoLibrary.shared().synchronizeChanges()
        NSLog("[Share] best-effort 入库完成 \(photos.count) 张")
    }
}
