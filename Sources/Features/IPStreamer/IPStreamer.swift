// IPStreamer.swift
// TCP 推流服务：将相机帧通过局域网广播
// 依赖 Network framework，iOS 14+

import Network
import Foundation

// MARK: - IP Streamer Service

/// TCP 推流服务，监听端口 8585，支持最多 5 个客户端
@available(iOS 14.0, *)
class IPStreamerService: ObservableObject {
    // MARK: - Published Properties

    /// 是否正在推流
    @Published var isStreaming: Bool = false
    /// 已连接客户端数量
    @Published var clientCount: Int = 0

    // MARK: - Private Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let maxClients = 5
    private let port: UInt16 = 8585
    private let logQueue = DispatchQueue(label: "com.aperturepro.ipstreamer.log")

    /// 相机帧源回调，从外部传入 JPEG 字节
    private var frameSource: (([UInt8]) -> Void)?

    // MARK: - Lifecycle

    init() {
        os_log("IPStreamerService 初始化完成", type: .info)
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// 启动推流，传入帧数据源回调
    /// - Parameter frameSource: 每次调用传入一帧的原始 JPEG 字节
    func start(frameSource: @escaping ([UInt8]) -> Void) {
        guard !isStreaming else {
            os_log("推流已在运行中，跳过重复启动", type: .info)
            return
        }
        self.frameSource = frameSource

        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                self?.onListenerStateChanged(state)
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.onNewConnection(connection)
            }
            listener?.start()
            isStreaming = true
            os_log("推流已启动，端口 %d", type: .info, port)
        } catch {
            os_log("启动推流失败：%@", type: .error, error.localizedDescription)
            isStreaming = false
        }
    }

    /// 停止推流并断开所有客户端
    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        isStreaming = false
        clientCount = 0
        os_log("推流已停止", type: .info)
    }

    // MARK: - Internal Helpers

    /// 将一帧 JPEG 数据打包为 `[长度 UInt32 big-endian][原始数据]` 后推送给所有客户端
    private func broadcastFrame(_ data: [UInt8]) {
        guard !connections.isEmpty else { return }
        let length = UInt32(data.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        let packet = header + Data(data)

        for conn in connections {
            conn.send(content: packet, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.os_log("发送帧失败：%@", type: .error, error.localizedDescription)
                }
            })
        }
    }

    // MARK: - NWListener Handlers

    private func onListenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            os_log("TCP 监听就绪，端口 %d", type: .info, port)
        case .waiting(let error):
            os_log("监听等待中，原因：%@", type: .error, error.localizedDescription)
        case .failed(let error):
            os_log("监听失败：%@", type: .error, error.localizedDescription)
            isStreaming = false
        case .cancelled:
            os_log("监听已取消", type: .info)
            isStreaming = false
        @unknown default:
            break
        }
    }

    private func onNewConnection(_ connection: NWConnection) {
        guard connections.count < maxClients else {
            os_log("客户端已满（%d/%d），拒绝连接", type: .info, connections.count, maxClients)
            connection.cancel()
            return
        }
        os_log("新客户端连接，当前连接数：{}", type: .info, connections.count + 1)
        connections.append(connection)
        clientCount = connections.count
        startReading(connection: connection)

        // 连接断开时清理
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if state == .cancelled || state == .failed {
                self.connections.removeAll { $0 === connection }
                self.clientCount = self.connections.count
                os_log("客户端断开，剩余连接：{}", type: .info, self.connections.count)
            }
        }
    }

    // MARK: - Connection Reader

    private func startReading(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                os_log("读取数据失败：%@", type: .error, error.localizedDescription)
                connection.cancel()
                return
            }
            // 服务端为推流方，通常不需要读客户端数据；此处预留扩展点
            if let data = data, !data.isEmpty {
                os_log("收到客户端数据 {} bytes", type: .debug, data.count)
            }
            if !isComplete {
                self.startReading(connection: connection)
            }
        }
    }

    // MARK: - Frame Pump

    /// 开启帧数据轮询：每 33ms（≈30fps）调用一次 frameSource
    func startFramePump() {
        let queue = DispatchQueue(label: "com.aperturepro.ipstreamer.pump")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.frameSource?({
                // 帧源由外部相机模块注入，此处仅占位
                return [UInt8](repeating: 0xFF, count: 10)
            }())
        }
        timer.resume()
        // 保留 timer 引用防止释放
        _ = timer
    }

    // MARK: - Logging

    private func os_log(_ message: String, type: os_log_type, _ items: Any...) {
        logQueue.async {
            let final = items.isEmpty ? message : String(format: message, items)
            os_log("%@", type: type, final)
        }
    }
}

// MARK: - UInt32 Big-Endian Helper

extension UInt32 {
    /// 转换为 big-endian 字节数组（4 bytes）
    var bigEndianBytes: [UInt8] {
        var value = self.bigEndian
        return withUnsafePointer(to: &value) {
            Array(UnsafeBufferPointer(start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self),
                                       count: MemoryLayout<UInt32>.size))
        }
    }
}

// MARK: - Preview

#if DEBUG && canImport(SwiftUI)
import SwiftUI
struct IPStreamerPreview: View {
    @StateObject private var streamer = IPStreamerService()
    var body: some View {
        VStack(spacing: 20) {
            Text("IP 推流服务")
                .font(.title2)
            Text(streamer.isStreaming ? "推流中：\(streamer.clientCount) 个客户端" : "未推流")
                .font(.body)
            Button(streamer.isStreaming ? "停止推流" : "开始推流") {
                if streamer.isStreaming {
                    streamer.stop()
                } else {
                    streamer.start { data in
                        // 模拟帧数据（实际项目替换为真实 JPEG 数据）
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
struct IPStreamerPreview_Previews: PreviewProvider {
    static var previews: some View { IPStreamerPreview() }
}
#endif
