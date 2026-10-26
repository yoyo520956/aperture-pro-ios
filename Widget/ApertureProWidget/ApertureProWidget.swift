import WidgetKit
import SwiftUI

struct ApertureProEntry: TimelineEntry {
    let date: Date
}

struct ApertureProProvider: TimelineProvider {
    func placeholder(in context: Context) -> ApertureProEntry {
        ApertureProEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ApertureProEntry) -> Void) {
        completion(ApertureProEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ApertureProEntry>) -> Void) {
        let entry = ApertureProEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct ApertureProEntryView: View {
    let entry: ApertureProEntry

    var body: some View {
        ZStack {
            cardContent
                .padding()
            if let url = URL(string: "aperturepro://") {
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
                Text("宣纸 · 青黛 · 朱砂")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.top, 2)
            }
        }
    }
}

struct ApertureProWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ApertureProWidget", provider: ApertureProProvider()) { entry in
            ApertureProEntryView(entry: entry)
        }
        .configurationDisplayName("光圈Pro")
        .description("中式相机，一键直达取景")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ApertureProWidgetBundle: WidgetBundle {
    var body: some Widget {
        ApertureProWidget()
    }
}
