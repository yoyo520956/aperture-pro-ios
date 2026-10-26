import WidgetKit
import SwiftUI

struct ApertureProEntry: TimelineEntry {
    let date: Date
    let shotCount: Int
    let lastShot: Date?
    let isLive: Bool
}

struct ApertureProProvider: TimelineProvider {
    private static let groupID = "group.com.aperture.pro"

    func placeholder(in context: Context) -> ApertureProEntry {
        ApertureProEntry(date: Date(), shotCount: 0, lastShot: nil, isLive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ApertureProEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ApertureProEntry>) -> Void) {
        let entry = readEntry()
        // 有活数据时 30 分钟刷一次，静态卡不刷
        let policy: TimelineReloadPolicy = entry.isLive ? .after(Date().addingTimeInterval(1800)) : .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func readEntry() -> ApertureProEntry {
        guard
            let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID),
            let data = try? Data(contentsOf: dir.appendingPathComponent("ap_state.json")),
            let obj = try? JSONDecoder().decode(StateJSON.self, from: data)
        else {
            return ApertureProEntry(date: Date(), shotCount: 0, lastShot: nil, isLive: false)
        }
        return ApertureProEntry(date: Date(), shotCount: obj.shotCount, lastShot: obj.lastShot, isLive: true)
    }

    private struct StateJSON: Codable {
        let shotCount: Int
        let lastShot: Date?
    }
}

struct ApertureProEntryView: View {
    let entry: ApertureProEntry

    var body: some View {
        ZStack {
            cardContent
                .padding()
            if let url = URL(string: "aperturepro://camera") {
                Link(destination: url) {
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var cardContent: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.06, green: 0.07, blue: 0.08))
            VStack(spacing: 6) {
                Image(systemName: "aperture")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(Color(red: 0.42, green: 0.62, blue: 0.74))
                Text("光圈Pro")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.93, green: 0.91, blue: 0.87))
                if entry.isLive, let ls = entry.lastShot {
                    Text("已拍 \(entry.shotCount) 张 · 最近 \(Self.timeString(ls))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.75))
                        .padding(.top, 2)
                } else {
                    Text("宣纸 · 青黛 · 朱砂")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.45))
                        .padding(.top, 2)
                }
            }
        }
    }

    private static func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

struct ApertureProWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ApertureProWidget", provider: ApertureProProvider()) { entry in
            ApertureProEntryView(entry: entry)
        }
        .configurationDisplayName("光圈Pro")
        .description("中式相机，一键直达取景；配齐 App Group 后显示活数据")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ApertureProWidgetBundle: WidgetBundle {
    var body: some Widget {
        ApertureProWidget()
    }
}
