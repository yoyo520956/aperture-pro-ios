import Foundation
import Network

/// IP 推流服务：局域网 TCP 推 JPEG 帧（NWListener 真实现）
/// 协议：每帧 = 4 字节大端长度 + JPEG 载荷；HTTP 客户端抓首帧亦可
final class IPStreamerService: ObservableObject {
    static let shared = IPStreamerService()
    static let port: UInt16 = 8585

    @Published var isStreaming: Bool = false
    @Published var clientCount: Int = 0
    @Published var serverIP: String = "127.0.0.1"
    @Published var framesPushed: Int = 0

    private var listener: NWListener?
    private var clients: [NWConnection] = []
    private let netQueue = DispatchQueue(label: "com.aperture.pro.ipstreamer")
    private var latestFrame: Data?
    private let frameLock = NSLock()

    private init() {}

    // MARK: - 相机侧：喂帧

    /// 由相机帧回调节流后调用（约 12fps）
    func pushFrame(_ jpeg: Data) {
        frameLock.lock()
        latestFrame = jpeg
        frameLock.unlock()
        framesPushed += 1
    }

    // MARK: - 启停

    func start() {
        guard !isStreaming else { return }
        netQueue.async { [weak self] in self?.startListener() }
        isStreaming = true
        serverIP = Self.localIPv4()
    }

    func stop() {
        isStreaming = false
        netQueue.async { [weak self] in
            guard let self else { return }
            for c in self.clients {
                c.cancel()
            }
            self.clients.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.pumpTimer?.cancel()
            self.pumpTimer = nil
            self.clientCount = 0
            NSLog("[IPStreamer] 推流服务已停止")
        }
    }

    // MARK: - NWListener 接线

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.port = NWPort(Self.port)
            listener = try NWListener(using: params)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener?.stateHandler = { [weak self] state in
                switch state {
                case .ready:
                    NSLog("[IPStreamer] 监听 :\(Self.port)")
                case .failed(let err):
                    NSLog("[IPStreamer] 监听失败 \(err)")
                default:
                    break
                }
            }
            listener?.start(queue: netQueue)
            startPump()
        } catch {
            NSLog("[IPStreamer] NWListener 创建失败 \(error)")
        }
    }

    private var pumpTimer: DispatchSourceTimer?

    /// 10fps 定时把最新帧推给所有在线客户端
    private func startPump() {
        guard pumpTimer == nil else { return }
        let timer = DispatchSource.makeTimer(queue: netQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, let frame = self.latestFrame() else { return }
            for c in self.clients where c.state == .ready {
                self.send(frame, to: c)
            }
        }
        timer.resume()
        pumpTimer = timer
    }

    private func accept(_ conn: NWConnection) {
        clients.append(conn)
        setCount(clients.count)
        conn.start(queue: netQueue)
        conn.stateHandler = { [weak self] state in
            guard let self else { return }
            if case .cancelled = state {
                self.remove(conn)
            }
        }
        NSLog("[IPStreamer] 新客户端接入")
        // 推一帧当前画面做握手
        if let frame = latestFrame() {
            send(frame, to: conn)
        }
    }

    private func remove(_ conn: NWConnection) {
        netQueue.async { [weak self] in
            guard let self else { return }
            if let i = self.clients.firstIndex(where: { $0 === conn }) {
                self.clients.remove(at: i)
            }
            self.setCount(self.clients.count)
        }
    }

    private func latestFrame() -> Data? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame
    }

    private func send(_ frame: Data, to conn: NWConnection) {
        var len = UInt32(frame.count).bigEndian
        let payload = withUnsafeBytes(of: &len) { Data($0) } + frame
        conn.send(content: .data(payload), completion: .contentProcessed { [weak self, weak conn] error in
            if let error {
                if let conn { self?.remove(conn) }
            }
        })
    }

    private func setCount(_ n: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.clientCount = n
        }
    }

    // MARK: - 本机 IPv4

    static func localIPv4() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.ifa_flags)
            let family = p.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) && (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 {
                let host = [Int8](repeating: 0, count: INET_ADDRSTRLEN)
                if inet_ntop(AF_INET, p.ifa_addr, host) != nil {
                    let s = String(cString: host)
                    if !s.isEmpty { address = s }
                }
                break
            }
            ptr = p.ifa_next
        }
        return address
    }
}
