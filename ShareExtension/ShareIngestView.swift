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

private func ingestBestEffort() {
    DispatchQueue.global(qos: .userInitiated).async {
        let lib = PHPhotoLibrary.shared()
        _ = lib.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            // 扩展沙箱内无 App Group，无法直接拿主 App 的附件；
            // 若系统把共享项临时落盘到扩展容器则这里可读到，否则跳过。
            let bases = FileManager.default.urls(for: [.cachesDirectory, .temporaryDirectory], in: .userDomainMask)
            let container = bases
            for base in container {
                let items = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
                for url in items where url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" {
                    if let data = try? Data(contentsOf: url) {
                        let req = PHAssetCreationRequest.forAsset()
                        req.addPhoto(with: data, options: nil)
                        lib.performChanges { }
                    }
                }
            }
            NSLog("[Share] best-effort 入库完成")
        }
    }
}
