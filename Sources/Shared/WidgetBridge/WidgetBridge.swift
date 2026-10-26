import Foundation
import WidgetKit

/// Widget 活数据桥：App 侧把最新拍摄状态写进 App Group 容器，Widget 侧读取。
/// 侧载/未配 App Group 时 containerURL 为 nil 或写入失败 → 静默降级为静态卡片，不影响 App。
enum WidgetBridge {
    static let groupID = "group.com.aperture.pro"

    struct State: Codable {
        let shotCount: Int
        let lastShot: Date?
        let note: String
    }

    /// App 侧：每次拍完照/录完视频调一次
    static func publish(shotCount: Int, lastShot: Date?, note: String) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return
        }
        let url = dir.appendingPathComponent("ap_state.json")
        let state = State(shotCount: shotCount, lastShot: lastShot, note: note)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // 未配 App Group / 权限不足 → 静默降级
        }
    }

    /// Widget 侧：读不到 nil → 静态卡片
    static func readState() -> State? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return nil
        }
        let url = dir.appendingPathComponent("ap_state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
}
