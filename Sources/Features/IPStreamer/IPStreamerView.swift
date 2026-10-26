import SwiftUI

struct IPStreamerView: View {
    @StateObject private var streamer = IPStreamerService()
    @State private var showQRCode: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: streamer.isStreaming ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(streamer.isStreaming ? .green : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("IP 推流")
                        .font(.headline)
                    Text(streamer.isStreaming ? "\(streamer.clientCount) 个客户端已连接" : "未启动")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if streamer.isStreaming {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i < streamer.clientCount ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.vertical, 8)
            }

            Button {
                if streamer.isStreaming {
                    streamer.stop()
                } else {
                    streamer.start() { frame in
                        // 实际项目中从 CameraEngine 获取帧
                        print("Frame: \(frame.count) bytes")
                    }
                }
            } label: {
                Label(
                    streamer.isStreaming ? "停止推流" : "启动推流",
                    systemImage: streamer.isStreaming ? "stop.circle" : "play.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(streamer.isStreaming ? .red : .blue)

            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("端口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("8585")
                        .font(.system(size: 16, weight: .medium))
                }
                Divider().frame(height: 40)
                VStack(spacing: 2) {
                    Text("协议")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("TCP")
                        .font(.system(size: 16, weight: .medium))
                }
                Divider().frame(height: 40)
                VStack(spacing: 2) {
                    Text("格式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("JPEG 帧")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .padding()
    }
}
