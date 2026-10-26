import SwiftUI
import Intents
import UniformTypeIdentifiers

/// 分享扩展：接收外部图片 / 视频，暂存并回显（App Group 配齐后可直通本机相册）
@main
struct ApertureProShare: INExtension {
    var body: some View {
        ShareIngestView()
    }
}

struct ShareIngestView: View {
    @Environment(\.extensionContext) private var context
    @State private var received: [String] = []

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
            }
            Text("提示：在签名配置中加上 App Group 后，这里的数据可直通本机相册")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("完成") {
                context.complete()
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
        for item in context.extensionItems {
            for attachment in item.attachments {
                if attachment.registeredTypeIdentifier == UTType.image.identifier,
                   let url = attachment.url {
                    received.append(url.lastPathComponent)
                } else if attachment.registeredTypeIdentifier == UTType.movie.identifier,
                          let url = attachment.url {
                    received.append(url.lastPathComponent)
                }
            }
        }
    }
}
