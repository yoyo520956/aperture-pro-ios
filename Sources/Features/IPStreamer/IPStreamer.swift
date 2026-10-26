import Network
import Foundation

class IPStreamerService: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var clientCount: Int = 0

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let maxClients = 5
    private let port: NWEndpoint.Port = 8585
    private var framePump: DispatchSourceTimer?
    private var frameSource: (([UInt8]) -> Void)?

    func start(frameSource: @escaping ([UInt8]) -> Void) {
        guard !isStreaming else { return }
        self.frameSource = frameSource
        isStreaming = true
        setupListener()
        startFramePump()
    }

    func stop() {
        isStreaming = false
        framePump?.cancel()
        framePump = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        clientCount = 0
    }

    private func setupListener() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(
                on: port,
                using: params
            )
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[IPStreamer] 服务已启动，端口 \(self.port.rawValue)")
                case .failed(let error):
                    print("[IPStreamer] 服务失败: \(error.localizedDescription)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.acceptConnection(connection)
            }
            listener?.start()
        } catch {
            print("[IPStreamer] 创建监听器失败: \(error.localizedDescription)")
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        guard connections.count < maxClients else {
            connection.cancel()
            return
        }
        connections.append(connection)
        clientCount = connections.count
        print("[IPStreamer] 新客户端连接，当前 \(clientCount)/\(maxClients)")
        connection.start(using: .unspecified)
    }

    private func startFramePump() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(repeating: 0.033)
        timer.setEventHandler { [weak self] in
            guard let self, let source = self.frameSource else { return }
            let frame = source()
            guard !frame.isEmpty else { return }
            self.broadcastFrame(frame)
        }
        timer.resume()
        framePump = timer
    }

    private func broadcastFrame(_ frame: [UInt8]) {
        let length = UInt32(frame.count).bigEndian
        var payload = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            payload[i] = UInt8((length >> (8 * (3 - i))) & 0xFF)
        }
        payload.append(contentsOf: frame)
        for conn in connections {
            conn.send(content: payload.data, contentContext: .message, completion: .contentProcessed { error in
                if let error {
                    print("[IPStreamer] 发送失败: \(error.localizedDescription)")
                }
            })
        }
    }

    private var payload.data: Data {
        Data(bytes: self, count: count)
    }
}

extension Array where Element == UInt8 {
    var data: Data {
        Data(bytes: self, count: count)
    }
}
