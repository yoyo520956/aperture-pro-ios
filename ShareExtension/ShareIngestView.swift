import SwiftUI
import Intents
import IntentsUI
#if canImport(ExtensionFoundation)
import ExtensionFoundation
#endif
import UniformTypeIdentifiers

/// 扩展上下文持有者（避免依赖 @Environment(\.extensionContext)，兼容 iOS 16）
enum ShareContextHolder {
    static var context: NSExtensionContext?
}

/// 分享扩展入口：NSExtensionRequestHandlingDelegate + SwiftUI 宿主
/// Info.plist 的 NSExtensionPrincipalClass = ApertureProShare.ShareViewController
final class ShareViewController: NSExtensionRequestHandlingDelegate {
    override func main() {
        super.main()
        ShareContextHolder.context = self.extensionContext
        guard let root = extensionContext?.viewControllers.first else { return }
        let hosting = UIHostingController(rootView: ShareIngestView())
        hosting.view.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        root.addChild(hosting)
        hosting.view.frame = root.view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(hosting.view)
        hosting.didMove(toParent: root)
    }
}

/// 分享扩展：接收外部图片 / 视频，暂存并回显（配齐 App Group 后可直通本机相册）
struct ShareIngestView: View {
    @State private var received: [String] = []
    @State private var savedCount: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "aperture")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color(red: 0.24, green: 0.36, blue: 0.42))
            Text("光圈Pro 已收到")
                .font(.system(size: 17, weight: .medium))
            if received.isEmpty {
                Text("没有可识别的附件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(received, id: \.self) { name in
                    Text(name)
                        .font(.footnote)
                        .lineLimit(1)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                }
                if savedCount > 0 {
                    Label("已暂存 \(savedCount) 项到 App 媒体库", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.24, green: 0.36, blue: 0.42))
                }
            }
            Text("配齐 App Group 签名后，这里的数据可直通本机相册")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("完成") {
                ShareContextHolder.context?.complete()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.71, green: 0.28, blue: 0.25))
        }
        .padding()
        .onAppear {
            collectAttachments()
        }
    }

    private func collectAttachments() {
        guard let items = ShareContextHolder.context?.extensionItems else { return }
        for item in items {
            for attachment in item.attachments {
                // 按 UTI 层级判断，别只匹配精确的 public.image / public.movie
                if let type = UTType(attachment.registeredTypeIdentifier) {
                    if type.conforms(to: .image), let url = attachment.url {
                        received.append(url.lastPathComponent)
                        ingest(url)
                    } else if type.conforms(to: .movie), let url = attachment.url {
                        received.append(url.lastPathComponent)
                        ingest(url)
                    }
                }
            }
        }
    }

    /// 把附件拷进 App Group 容器（签名为配齐 App Group 时生效；未配齐则静默跳过）
    private func ingest(_ source: URL) {
        let group = "group.com.aperture.pro"
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let destDir = dir.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(source.lastPathComponent)
        if (try? FileManager.default.copyItem(at: source, to: dest)) != nil {
            savedCount += 1
        }
    }
}
