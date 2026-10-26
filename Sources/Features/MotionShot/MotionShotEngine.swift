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
        guard isCapturing else { return }
        guard capturedFrames.count < maxFrames else { return }
        capturedFrames.append(uiImage)
        frameCount = capturedFrames.count
    }

    func stopCapture() -> UIImage? {
        isCapturing = false
        guard !capturedFrames.isEmpty else { return nil }
        return composeFrames()
    }

    private func composeFrames() -> UIImage? {
        var ciImages: [CIImage] = []
        for frame in capturedFrames {
            if let ci = CIImage(image: frame) {
                ciImages.append(ci)
            }
        }
        guard !ciImages.isEmpty else { return nil }

        var result: CIImage? = ciImages[0]
        for i in stride(from: 1, to: ciImages.count, by: 1) {
            guard let current = result,
                  let blend = CIFilter(name: "CIBlendWithMask")
            else { break }
            blend.setValue(current, forKey: kCIInputImageKey)
            blend.setValue(ciImages[i], forKey: "backgroundImage")
            let mask = ciImages[i].clampedToExtent()
            blend.setValue(mask, forKey: "maskImage")
            result = blend.outputImage
        }

        guard let finalResult = result,
              let cgImage = ciContext.createCGImage(finalResult, from: finalResult.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 存到 Documents/Media，和 App 媒体库 / iCloud 同步目录对齐
    func saveResult(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let media = docs.appendingPathComponent("Media", isDirectory: true)
        try? fm.createDirectory(at: media, withIntermediateDirectories: true)
        let filename = "motion_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = media.appendingPathComponent(filename)
        try? data.write(to: url)
        return filename
    }
}
