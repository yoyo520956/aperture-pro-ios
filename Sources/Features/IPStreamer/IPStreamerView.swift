import SwiftUI

/// IP 推流面板：局域网标准 HTTP MJPEG 流
/// 接收方浏览器 / VLC / ffplay 直接开 streamer.streamURL
struct IPStreamerView: View {
    @ObservedObject private var streamer = IPStreamerService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: streamer.isStreaming
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(streamer.isStreaming ? .green : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("IP 推流")
                        .font(.headline)
                    Text(streamer.isStreaming ? "服务运行中" : "未启动")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if streamer.isStreaming {
                    streamer.stop()
                } else {
                    streamer.start()
                }
            } label: {
                Label(
                    streamer.isStreaming ? "停止推流" : "启动推流",
                    systemImage: streamer.isStreaming ? "stop.circle" : "play.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(streamer.isStreaming ? .red : .blue)

            if streamer.isStreaming {
                statGrid
                receiverHint
            }

            specsGrid
        }
        .padding()
        .onChange(of: scenePhase) { phase in
            // 退到后台就停，避免白占局域网端口与流量
            if phase != .active && streamer.isStreaming {
                streamer.stop()
            }
        }
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            cell("在线客户端", "\(streamer.clientCount)")
            Divider().frame(height: 40)
            cell("已推帧", "\(streamer.framesPushed)")
            Divider().frame(height: 40)
            cell("帧率", "10fps")
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var specsGrid: some View {
        HStack(spacing: 12) {
            cell("端口", "\(IPStreamerService.port)")
            Divider().frame(height: 40)
            cell("协议", "HTTP MJPEG")
            Divider().frame(height: 40)
            cell("格式", "JPEG 帧")
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var receiverHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本机地址")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(streamer.streamURL)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
            Text("浏览器 / VLC / ffplay 直接打开上面地址即可看流（同网段）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }
}
