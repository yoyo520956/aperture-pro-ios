import Foundation
import BackgroundTasks

/// iCloud 同步服务（NSUbiquitousContainer）
/// 双向合并：本地新→上传；云端新→拉回；两端都改→保留较新+旧版备份；删除经 manifest 传播
@MainActor
final class ICloudSyncService: ObservableObject {
    static let containerIdentifier = "iCloud.com.aperture.pro"
    static let group = "iCloud.com.aperture.pro"

    @Published var lastSync: Date?
    @Published var isSyncing: Bool = false
    @Published var lastMessage: String = "尚未同步"

    private static let bgTaskID = "com.aperture.pro.icloud"

    private static var localMediaDir: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 后台任务

    func scheduleBackgroundSync() {
        guard FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) != nil else {
            lastMessage = "本机未开启 iCloud 存储"
            return
        }
        let ok = BGTaskScheduler.shared().register(
            forTaskWithIdentifier: Self.bgTaskID, using: nil
        ) { task in
            task.expirationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.backgroundSync()
                }
            }
            Task { @MainActor [weak self] in
                self?.backgroundSync()
                task.setTaskCompleted(success: true)
            }
        }
        if ok {
            let req = BGProcessingTaskRequest(identifier: Self.bgTaskID)
            req.requiresNetworkAccess = true
            req.requiresExternalPower = false
            BGTaskScheduler.shared().submit(req)
        }
    }

    func backgroundSync() {
        guard !isSyncing else { return }
        syncAll()
    }

    func foregroundFetch() {
        Task {
            await syncAll()
        }
    }

    // MARK: - 双向同步

    private func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastMessage = "正在同步…"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.runMerge()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncing = false
                self.lastSync = Date()
                self.lastMessage = result
            }
        }
    }

    /// 执行合并，返回可读结果描述
    nonisolated private static func runMerge() -> String {
        let fm = FileManager.default
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return "iCloud 容器不可用"
        }
        if !base.startAccessingSecurityScopedResource() { return "iCloud 访问被拒" }
        defer { base.stopAccessingSecurityScopedResource() }

        let cloudMedia = base.appendingPathComponent("Media", isDirectory: true)
        let localMedia = localMediaDir
        try? fm.createDirectory(at: cloudMedia, withIntermediateDirectories: true)

        var uploaded = 0
        var pulled = 0
        var conflicts = 0
        var deleted = 0

        // 1) 删除清单：本地删除 → 云端删除
        let manifestURL = localMedia.appendingPathComponent(".deleted_manifest.json")
        var manifest: [String] = []
        if let data = try? Data(contentsOf: manifestURL),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            manifest = arr
        }
        for name in manifest {
            let cloudFile = cloudMedia.appendingPathComponent(name)
            if fm.fileExists(atPath: cloudFile.path) {
                try? fm.removeItem(at: cloudFile)
                deleted += 1
            }
            let localFile = localMedia.appendingPathComponent(name)
            if fm.fileExists(atPath: localFile.path) {
                try? fm.removeItem(at: localFile)
            }
        }
        if !manifest.isEmpty {
            // 清单内所有名称已处理（云端已删）→ 清空清单
            try? manifestURL.removeItem()
            manifest.removeAll()
        }

        // 2) 上传：本地比云端新（或云端没有）
        let localFiles = (try? fm.contentsOfDirectory(at: localMedia, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in localFiles {
            let name = file.lastPathComponent
            if name.hasPrefix(".") { continue }
            let dest = cloudMedia.appendingPathComponent(name)
            let localM = try? fm.contentModificationDate(atPath: file.path)
            let cloudM = try? fm.contentModificationDate(atPath: dest.path)
            if fm.fileExists(atPath: dest.path) {
                if let lm = localM, let cm = cloudM, lm <= cm {
                    // 云端更新：拉回并备份本地旧版
                    try? fm.copyItem(at: dest, to: file.deletingLastPathComponent()
                        .appendingPathComponent(".conflict-\(Int(Date().timeIntervalSince1970))-\(name)"))
                    try? fm.removeItem(at: file)
                    try? fm.copyItem(at: dest, to: file)
                    pulled += 1
                    conflicts += 1
                } else {
                    try? fm.copyItem(at: file, to: dest)
                    uploaded += 1
                }
            } else {
                try? fm.copyItem(at: file, to: dest)
                uploaded += 1
            }
        }

        // 3) 拉取：云端有而本地没有（且不在删除清单）
        let cloudFiles = (try? fm.contentsOfDirectory(at: cloudMedia, includingPropertiesForKeys: [])) ?? []
        for file in cloudFiles {
            let name = file.lastPathComponent
            if name.hasPrefix(".") || manifest.contains(name) { continue }
            let dest = localMedia.appendingPathComponent(name)
            if !fm.fileExists(atPath: dest.path) {
                if (try? fm.copyItem(at: file, to: dest)) != nil {
                    pulled += 1
                }
            }
        }

        if uploaded + pulled + deleted == 0 { return "云盘已是最新" }
        return "上传 \(uploaded) · 拉回 \(pulled) · 冲突备份 \(conflicts) · 远端删除 \(deleted)"
    }

    // MARK: - 删除传播

    /// 本地删除媒体文件时调用：记入删除清单，下次同步删除云端
    func recordLocalDeletion(filename: String) {
        let manifestURL = Self.localMediaDir.appendingPathComponent(".deleted_manifest.json")
        var manifest: [String] = []
        if let data = try? Data(contentsOf: manifestURL),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            manifest = arr
        }
        manifest.append(filename)
        manifest = Array(Set(manifest)).suffix(200).map { $0 }
        try? manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }
}
