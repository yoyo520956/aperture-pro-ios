import Foundation
import Network

/// IP 推流服务（标准协议）：局域网 HTTP MJPEG 流，通用播放器/浏览器直接可开
/// - GET http://IP:8585/stream  → multipart/x-mixed-replace 持续 JPEG 帧（10fps，带背压丢帧）
/// - GET http://IP:8585/info    → 状态 JSON（客户端数/已推帧数/端口）
/// 底层 NWListener(TCP) + 手写 HTTP/1.0 响应（Connection: close，单连接单请求，稳）
final class IPStreamerService: ObservableObject {
    static let shared = IPStreamerService()
    static let port: UInt16 = 8585

    @Published var isStreaming: Bool = false
    @Published var clientCount: Int = 0
    @Published var serverIP: String = "127.0.0.1"
    @Published var framesPushed: Int = 0

    /// 当前可分享的外接流 URL
    var streamURL: String { "http://\(serverIP):\(Self.port)/stream" }

    private var listener: NWListener?
    private var clients: [NWConnection] = []
    private let netQueue = DispatchQueue(label: "com.aperture.pro.ipstreamer")
    private var latestFrame: Data?
    private let frameLock = NSLock()
    /// 每个 TCP 连接是否已收到 GET 请求（收到才进推流泵）
    private var connReady: Set<ObjectIdentifier> = []
    private let readyLock = NSLock()
    private var pumpTimer: DispatchSourceTimer?

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
            for c in self.clients { c.cancel() }
            self.clients.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.pumpTimer?.cancel()
            self.pumpTimer = nil
            self.markReady([ObjectIdentifier]())
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
                    NSLog("[IPStreamer] 监听 :\(Self.port)（HTTP MJPEG）")
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

    private func accept(_ conn: NWConnection) {
        clients.append(conn)
        setCount(clients.count)
        conn.start(queue: netQueue)
        // 读首包请求行
        conn.receive(minimumLength: 1, maximumLength: 512, queue: netQueue) { [weak self, weak conn] data, _ in
            guard let self, let conn else { return }
            guard let data, !data.isEmpty else {
                self.remove(conn)
                return
            }
            let line = String(decoding: data, as: UTF8.self)
            let isGet = line.uppercased().hasPrefix("GET")
            let isStream = line.contains("/stream")
            let isInfo = line.contains("/info")
            if isGet {
                if isInfo {
                    self.respond(conn, body: Self.infoJSON(), status: "200 OK",
                                 contentType: "application/json", keepAlive: false)
                } else {
                    // /stream（或任意 GET）→ 开 MJPEG 流
                    let head = "HTTP/1.0 200 OK\r\n"
                        + "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
                        + "Connection: close\r\n\r\n"
                    conn.send(content: .data(Data(head.utf8)), completion: .contentProcessed { _ in }
                    )
                    self.markReady([ObjectIdentifier(conn)])
                }
            } else {
                // 非 GET（旧协议 TCP 裸连等）→ 关掉
                self.remove(conn)
            }
        }
        conn.stateHandler = { [weak self] state in
            guard let self else { return }
            if case .cancelled = state {
                self.remove(conn)
            }
        }
        NSLog("[IPStreamer] 新客户端接入")
    }

    /// 10fps 泵：只给「已收到 GET 且发送缓冲不满」的连接推帧
    private func startPump() {
        guard pumpTimer == nil else { return }
        let timer = DispatchSource.makeTimer(queue: netQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let frame = self.latestFrame() else { return }
            let boundary = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(frame.count)\r\n\r\n"
            let head = Data(boundary.utf8)
            let payload = head + frame
            let readySet = self.readySnapshot()
            for c in self.clients {
                guard c.state == .ready else { continue }
                // 只给已收到 GET 的连接推帧（请求前连着的保持空闲等待）
                guard readySet.contains(ObjectIdentifier(c)) else { continue }
                // 背压：缓冲没写完就跳过本帧（丢帧不断流）
                guard c.isContentBufferSatisfied else { continue }
                c.send(content: .data(payload), completion: .contentProcessed { [weak self, weak c] error in
                    if error != nil, let c {
                        self?.remove(c)
                    }
                })
            }
        }
        timer.resume()
        pumpTimer = timer
    }

    private func remove(_ conn: NWConnection) {
        netQueue.async { [weak self] in
            guard let self else { return }
            if let i = self.clients.firstIndex(where: { $0 === conn }) {
                self.clients.remove(at: i)
            }
            self.markReady(self.readySnapshot().filter { $0 != ObjectIdentifier(conn) })
            self.setCount(self.clients.count)
        }
    }

    private func markReady(_ ids: Set<ObjectIdentifier>) {
        readyLock.lock()
        connReady = ids
        readyLock.unlock()
    }

    private func readySnapshot() -> Set<ObjectIdentifier> {
        readyLock.lock()
        defer { readyLock.unlock() }
        return connReady
    }

    private func latestFrame() -> Data? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame
    }

    private func respond(_ conn: NWConnection, body: String, status: String, contentType: String, keepAlive: Bool) {
        let head = "HTTP/1.0 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        conn.send(content: .data(Data(head.utf8) + Data(body.utf8)), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func infoJSON() -> String {
        #"""
        {"app":"aperture-pro","protocol":"mjpeg-http","port":8585,"stream":"/stream"}
        """#
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
