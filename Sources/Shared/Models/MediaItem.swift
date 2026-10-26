import Foundation

enum MediaKind: String, Codable, CaseIterable {
    case photo = "photo"
    case video = "video"
    case motionShot = "motion"
}

struct MediaItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: MediaKind
    let filename: String
    let date: Date
    let duration: Double?
    let width: Int
    let height: Int
    let fileSize: Int64
    var isFavorite: Bool
    var filterName: String?

    init(kind: MediaItem.MediaKind = .photo, filename: String, date: Date = .now, duration: Double? = nil, width: Int = 0, height: Int = 0, fileSize: Int64 = 0, isFavorite: Bool = false, filterName: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.filename = filename
        self.date = date
        self.duration = duration
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.isFavorite = isFavorite
        self.filterName = filterName
    }

    var displayDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }

    var displaySize: String {
        let mb = Double(fileSize) / 1024 / 1024
        if mb > 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(fileSize) / 1024
        return String(format: "%.0f KB", kb)
    }
}
