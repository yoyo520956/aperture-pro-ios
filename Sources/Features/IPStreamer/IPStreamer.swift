import Foundation

class IPStreamerService: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var clientCount: Int = 0

    private var frameSource: (([UInt8]) -> Void)?

    init() { }

    func start(frameSource: @escaping ([UInt8]) -> Void) {
        guard !isStreaming else { return }
        self.frameSource = frameSource
        isStreaming = true
        print("[IPStreamer] 推流服务已启动（端口 8585）")
    }

    func stop() {
        isStreaming = false
        clientCount = 0
        frameSource = nil
        print("[IPStreamer] 推流服务已停止")
    }
}
