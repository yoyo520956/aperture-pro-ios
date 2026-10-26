import Foundation
import BackgroundTasks

/// iCloud 同步服务（NSUbiquitousContainer）
/// 退到后台：把本地 Media 增量上传到 iCloud 容器
/// 回到前台：拉回云端 Media，合并进本地相册目录
@MainActor
class ICloudSyncService: ObservableObject {
    static let containerIdentifier = "iCloud.com.aperture.pro"
    @Published var lastSync: Date?
    @Published var isSyncing: Bool = false
    @Published var lastMessage: String = "尚未同步"

    private nonisolated static var localMediaDir: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Media", isDirectory: true)
    }

    func scheduleBackgroundSync() {
        guard NSUbiquitousContainer.default(forAppWithIdentifier: Self.containerIdentifier) != nil else {
            lastMessage = "本机未开启 iCloud 存储"
            return
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.aperture.pro.icloud",
            using: nil
        ) { task in
            task.expirationHandler = {}
            if BGTaskScheduler.shared.appWillResignSuspended() {
                Task { @MainActor [weak self] in
                    self?.backgroundSync()
                }
            }
            task.setTaskCompleted(success: true)
        }
        let request = BGProcessingTaskRequest(identifier: "com.aperture.pro.icloud")
        request.requiresNetworkAccess = true
        request.requiresExternalPower = false
        BGTaskScheduler.shared.submit(request)
    }

    func backgroundSync() {
        guard !isSyncing else { return }
        isSyncing = true
        lastMessage = "正在上传…"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.pushToLocalToCloud()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncing = false
                self.lastSync = Date()
                self.lastMessage = "已同步"
            }
        }
    }

    func foregroundFetch() {
        Task {
            await pullFromCloud()
        }
    }

    private nonisolated func pushToLocalToCloud() {
        guard let container = NSUbiquitousContainer.default(forAppWithIdentifier: Self.containerIdentifier) else { return }
        guard let cloudURL = container.url(for: .documentDirectory) else { return }
        let localMediaURL = Self.localMediaDir
        try? FileManager.default.createDirectory(at: cloudMedia, withIntermediateDirectories: true)
        let fm = FileManager.default
        let localFiles = (try? fm.contentsOfDirectory(
            at: localMediaURL, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        var count = 0
        for file in localFiles {
            let dest = cloudMedia.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: file, to: dest)
                count += 1
            }
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ap.icloud.lastPush")
        _ = count
    }

    private func pullFromCloud() async {
        let localMediaURL = Self.localMediaDir
        guard let container = NSUbiquitousContainer.default(forAppWithIdentifier: Self.containerIdentifier) else {
            lastMessage = "iCloud 容器不可用"
            return
        }
        guard let cloudURL = container.url(for: .documentDirectory) else { return }
        let cloudMedia = cloudURL.appendingPathComponent("Media", isDirectory: true)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cloudMedia, includingPropertiesForKeys: [.isRegularFileKey]) else {
            lastMessage = "云端暂无媒体"
            return
        }
        var newCount = 0
        for file in files {
            let dest = localMediaURL.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try fm.copyItem(at: file, to: dest)
                    newCount += 1
                } catch {
                    lastMessage = "合并中断"
                    return
                }
            }
        }
        lastSync = Date()
        lastMessage = newCount > 0 ? "从 iCloud 取回 \(newCount) 个文件" : "云盘已是最新"
    }
}
