import SwiftUI
import VisionKit
import CoreImage
import UIKit

/// 文档扫描：VisionKit 相机取景 + 自动透视矫正 + 黑白/白底处理 + PDF 导出
@available(iOS 16.0, *)
struct DocumentScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cgImage: CGImage?
    @State private var processed: UIImage?
    @State private var style: DocStyle = .blackWhite
    @State private var showSave: Bool = false

    enum DocStyle: String, CaseIterable {
        case blackWhite = "黑白"
        case warmPaper = "宣纸"
        case plain = "原色"
    }

    var body: some View {
        VStack(spacing: CNTheme.sp16) {
            if let cg = cgImage {
                previewArea
            } else {
                DocCamera(
                    onDocument: { doc in
                        cgImage = doc
                        process()
                    },
                    onCancel: { dismiss() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CNTheme.paper.ignoresSafeArea())
        .navigationTitle("文档扫描")
        .onDisappear {
            // 文档扫描使用独立相机会话
        }
    }

    private var previewArea: some View {
        VStack(spacing: CNTheme.sp12) {
            if let processed {
                Image(uiImage: processed)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: CNTheme.r8))
                    .shadow(color: .black.opacity(0.12), radius: 12)
                    .padding(.horizontal, CNTheme.sp16)
            }
            HStack(spacing: CNTheme.sp8) {
                ForEach(DocStyle.allCases, id: \.self) { s in
                    Button(s.rawValue) {
                        style = s
                        process()
                    }
                    .buttonStyle(.bordered)
                    .tint(style == s ? CNTheme.indigo : CNTheme.inkFaint)
                }
            }
            HStack(spacing: CNTheme.sp16) {
                Button("重新扫描") {
                    cgImage = nil
                    processed = nil
                }
                Button("保存 PNG") {
                    saveAsPNG()
                }
                .tint(CNTheme.indigo)
                Button("导出 PDF") {
                    saveAsPDF()
                }
                .tint(CNTheme.cinnabar)
            }
            .font(CNTheme.f14)
        }
    }

    private func process() {
        guard let cg = cgImage else { return }
        let ci = CIImage(cgImage: cg)
        var out = ci
        switch style {
        case .blackWhite:
            if let f = CIFilter(name: "CIPhotoEffectMono") {
                f.setValue(ci, forKey: kCIInputImageKey)
                out = f.outputImage ?? ci
            }
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(out, forKey: kCIInputImageKey)
                f.setValue(1.4, forKey: "contrast")
                out = f.outputImage ?? out
            }
        case .warmPaper:
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(0.0, forKey: "saturation")
                f.setValue(1.3, forKey: "contrast")
                f.setValue(0.06, forKey: "brightness")
                out = f.outputImage ?? ci
            }
        case .plain:
            out = ci
        }
        let ctx = CIContext()
        if let cg2 = ctx.createCGImage(out, from: ci.extent) {
            processed = UIImage(cgImage: cg2)
        }
    }

    private func saveAsPNG() {
        guard let processed else { return }
        let data = processed.pngData() ?? processed.jpegData(compressionQuality: 0.9) ?? Data()
        let dest = CameraEngine.mediaDir.appendingPathComponent("doc_\(Int(Date().timeIntervalSince1970)).png")
        try? data.write(to: dest)
        _ = PHLibraryService.saveImage(data)
    }

    private func saveAsPDF() {
        guard let processed else { return }
        let dest = CameraEngine.mediaDir.appendingPathComponent("doc_\(Int(Date().timeIntervalSince1970)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: processed.size))
        let data = renderer.pdfData { pdf in
            pdf.beginPage()
            processed.draw(in: CGRect(origin: .zero, size: processed.size))
        }
        try? data.write(to: dest)
        showSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showSave = false
        }
    }
}

/// VisionKit 文档相机
@available(iOS 16.0, *)
struct DocCamera: UIViewControllerRepresentable {
    var onDocument: (CGImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocCamera

        init(_ parent: DocCamera) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0,
                  let page = scan.imageOfPage(at: 0).cgImage else { return }
            parent.onDocument(page)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }
    }
}
