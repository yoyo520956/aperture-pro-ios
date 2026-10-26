import SwiftUI
import UIKit
import AVFoundation

// MARK: - 实时条码识别（QR / Code128 / EAN / DataMatrix / PDF417 / Aztec）

final class QRScanner: ObservableObject {
    @Published var scanResult: String?
    @Published var isScanning: Bool = false
}

/// 用 AVCaptureSession 的元数据输出做实时识别，设备端最稳的方案
struct QRScannerView: View {
    @StateObject private var scanner = QRScanner()

    var body: some View {
        VStack(spacing: 16) {
            CameraScannerView(model: scanner)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if let result = scanner.scanResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("识别结果")
                        .font(.headline)
                    Text(result)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .lineLimit(6)
                    HStack(spacing: 12) {
                        Button("复制") { UIPasteboard.general.string = result }
                            .buttonStyle(.bordered)
                        Button("扫码下一个") {
                            scanner.scanResult = nil
                            scanner.isScanning = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("将二维码 / 条形码 / 数据矩阵 / PDF417 对准取景框")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// 封装相机 + 元数据输出
private struct CameraScannerView: UIViewControllerRepresentable {
    @ObservedObject var model: QRScanner

    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let vc = CameraScannerViewController()
        vc.onDetected = { value, symbology in
            DispatchQueue.main.async {
                guard model.isScanning else { return }
                model.isScanning = false
                model.scanResult = "\(symbology)：\(value)"
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {
        if model.isScanning { uiViewController.start() } else { uiViewController.stop() }
    }
}

final class CameraScannerViewController: UIViewController {
    private let session = AVCaptureSession()
    private var configured = false
    var onDetected: ((String, String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        do {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try AVCaptureDeviceInput(device: device) else {
                return
            }
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [
                    .qr, .code128, .ean8, .ean13, .pdf417, .dataMatrix, .aztec, .upce
                ]
            }
        } catch {
            NSLog("QRScanner configure error: \(error)")
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
    }

    func start() {
        if session.isRunning { return }
        Task { @MainActor in
            do {
                await AVCaptureDevice.requestAccess(for: .video)
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.startRunning()
                }
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }
}

extension CameraScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AnyMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first?.object as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        onDetected?(value, obj.symbology)
    }
}
