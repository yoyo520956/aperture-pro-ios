import CoreImage
import UIKit

class MotionShotEngine: ObservableObject {
    @Published var isCapturing: Bool = false
    @Published var frameCount: Int = 0
    @Published var maxFrames: Int = 8

    private var capturedFrames: [UIImage] = []
    private let ciContext = CIContext()

    func startCapture() {
        capturedFrames = []
        frameCount = 0
        isCapturing = true
    }

    func addFrame(_ uiImage: UIImage) {
        guard isCapturing, capturedFrames.count < maxFrames else { return }
        capturedFrames.append(uiImage)
        frameCount = capturedFrames.count
    }

    func stopCapture() -> UIImage? {
        isCapturing = false
        guard !capturedFrames.isEmpty else { return nil }
        return composeFrames()
    }

    private func composeFrames() -> UIImage? {
        guard let first = capturedFrames.first,
              let ciImages = capturedFrames.compactMap({ CIImage(image: $0) }),
              let outputCI = CIFilter.motionBlur() as? CIMotionBlur else {
            return compositeOverlay(ciImages: ciImages)
        }

        let targetSize = ciImages.first!.extent.size
        var combined = ciImages[0]

        for i in stride(from: 1, to: ciImages.count, by: 1) {
            let blend = CIFilter.blendWithAlpha()
            blend.inputImage = combined
            blend.backgroundImage = ciImages[i]
            blend.blendMode = .plusLighter
            combined = blend.outputImage
        }

        let scale = 1.0
        let renderSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        let outputCG = ciContext.createCGImage(combined, from: CGRect(origin: .zero, size: renderSize))
        return UIImage(cgImage: outputCG)
    }

    private func compositeOverlay(ciImages: [CIImage]) -> UIImage? {
        guard let first = ciImages.first else { return nil }
        let baseSize = first.extent.size
        let totalHeight = baseSize.height * CGFloat(ciImages.count)
        let outputCI = CIImage(size: CGSize(width: baseSize.width, height: totalHeight))

        var result = outputCI
        for (i, img) in ciImages.enumerated() {
            let translated = img.transformed(by: CGAffineTransform(translationX: 0, y: -CGFloat(i) * baseSize.height))
            let blend = CIFilter.blendWithAlpha()
            blend.inputImage = result
            blend.backgroundImage = translated
            result = blend.outputImage
        }

        let cg = ciContext.createCGImage(result, from: CGRect(origin: .zero, size: CGSize(width: baseSize.width, height: totalHeight)))
        return UIImage(cgImage: cg)
    }

    func saveResult(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = "motion_\(Date().timeIntervalSince1970).jpg"
        let url = docs.appendingPathComponent(filename)
        try? data.write(to: url)
        return filename
    }
}
