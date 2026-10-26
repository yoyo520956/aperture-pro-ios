import SwiftUI
import Vision

class QRScanner: ObservableObject {
    @Published var scanResult: String?
    @Published var isScanning: Bool = false

    func scan(from image: UIImage) {
        guard let requestHandler = VNImageRequestHandler(image: image) else { return }
        let request = VNBarcodeObservingRequest()
        request.recognitionLevel = .accurate
        request.symbologies = [.qr, .ean13, .ean8, .code128, .pdf417, .aztec, .dataMatrix]

        do {
            try requestHandler.perform([request])
            if let barcode = request.results?.first?.payload {
                scanResult = barcode
                isScanning = false
            }
        } catch {
            print("QR 扫描失败: \(error)")
        }
    }

    func scanVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isScanning else { return }
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let request = VNBarcodeObservingRequest()
        request.recognitionLevel = .fast
        request.symbologies = [.qr]

        do {
            try requestHandler.perform([request])
            if let barcode = request.results?.first?.payload {
                scanResult = barcode
                isScanning = false
            }
        } catch {
            // 静默处理视频帧错误
        }
    }

    func reset() {
        scanResult = nil
        isScanning = false
    }
}

struct QRScannerView: View {
    @StateObject var scanner: QRScanner
    @State private var showResult: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 240, height: 240)

                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text(scanner.isScanning ? "扫描中..." : "将二维码对准框内")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            if let result = scanner.scanResult {
                VStack(spacing: 8) {
                    Text("识别结果")
                        .font(.headline)
                    Text(result)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: 12) {
                        Button("复制") {
                            UIPasteboard.general.string = result
                        }
                        .buttonStyle(.bordered)

                        Button("关闭") {
                            scanner.reset()
                            showResult = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            scanner.isScanning = true
        }
    }
}
