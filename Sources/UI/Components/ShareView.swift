import SwiftUI
import UIKit

struct ShareView: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("没有可分享的内容")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
            } else {
                ShareViewContent(items: items)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ShareViewContent: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: _ Context) {}
}
