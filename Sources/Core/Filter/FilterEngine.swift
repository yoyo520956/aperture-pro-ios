import CoreImage
import UIKit

enum FilterPreset: String, CaseIterable, Codable {
    case original = "原图"
    case vintage = "复古"
    case blackWhite = "黑白"
    case sepia = "暖棕"
    case cool = "冷调"
    case warm = "暖调"
    case dramatic = "戏剧"
    case film = "胶片"
}

class FilterEngine: ObservableObject {
    @Published var activeFilter: FilterPreset = .original
    let filterPresets: [FilterPreset] = [
        .original, .vintage, .blackWhite, .sepia,
        .cool, .warm, .dramatic, .film
    ]

    private let ciContext = CIContext()

    func applyFilter(_ data: Data, preset: FilterPreset) -> Data? {
        guard let image = UIImage(data: data),
              let ciImage = CIImage(image: image)
        else { return nil }

        var output = ciImage

        switch preset {
        case .original:
            break
        case .vintage:
            if let filter = CIFilter(name: "CIVignette"),
               let result = applyFilter(filter, inputImage: output,
                                        intensity: 1.2, radius: 180.0) {
                output = result
            }
        case .blackWhite:
            if let filter = CIFilter(name: "CIPhotoEffectNoir"),
               let result = applySimpleFilter(filter, inputImage: output) {
                output = result
            }
        case .sepia:
            if let filter = CIFilter(name: "CISepiaTone"),
               let result = applyFilter(filter, inputImage: output,
                                        intensity: 1.0) {
                output = result
            }
        case .cool:
            if let filter = CIFilter(name: "CIColorControls"),
               let result = applyColorControls(filter, inputImage: output,
                                               saturation: 1.1, contrast: 1.05) {
                output = result
            }
        case .warm:
            if let filter = CIFilter(name: "CIColorControls"),
               let result = applyColorControls(filter, inputImage: output,
                                               saturation: 1.15, brightness: 0.05) {
                output = result
            }
        case .dramatic:
            if let filter = CIFilter(name: "CIColorControls"),
               let result = applyColorControls(filter, inputImage: output,
                                               saturation: 1.2, contrast: 1.3,
                                               brightness: 0.05) {
                output = result
            }
        case .film:
            if let filter = CIFilter(name: "CIVignette"),
               let result = applyFilter(filter, inputImage: output,
                                        intensity: 0.8, radius: 250.0) {
                output = result
            }
        }

        guard let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
        else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.92)
    }

    private func applySimpleFilter(_ filter: CIFilter, inputImage: CIImage) -> CIImage? {
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    private func applyFilter(_ filter: CIFilter, inputImage: CIImage,
                             intensity: Double, radius: Double? = nil) -> CIImage? {
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: "intensity")
        if let radius {
            filter.setValue(radius, forKey: "radius")
        }
        return filter.outputImage
    }

    private func applyColorControls(_ filter: CIFilter, inputImage: CIImage,
                                    saturation: Double, contrast: Double = 1.0,
                                    brightness: Double = 0.0) -> CIImage? {
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(saturation, forKey: "saturation")
        filter.setValue(contrast, forKey: "contrast")
        filter.setValue(brightness, forKey: "brightness")
        return filter.outputImage
    }
}

extension FilterEngine {
    /// 滤镜直接作用于 CIImage（编辑管线用）
    func renderPreset(_ image: CIImage, preset: FilterPreset) -> CIImage {
        switch preset {
        case .original:
            return image
        case .vintage:
            guard let f = CIFilter(name: "CIVignette") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.2, forKey: "intensity")
            f.setValue(180.0, forKey: "radius")
            return f.outputImage ?? image
        case .blackWhite:
            guard let f = CIFilter(name: "CIPhotoEffectNoir") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            return f.outputImage ?? image
        case .sepia:
            guard let f = CIFilter(name: "CISepiaTone") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.0, forKey: "intensity")
            return f.outputImage ?? image
        case .cool:
            guard let f = CIFilter(name: "CIColorControls") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.1, forKey: "saturation")
            f.setValue(1.05, forKey: "contrast")
            return f.outputImage ?? image
        case .warm:
            guard let f = CIFilter(name: "CIColorControls") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.15, forKey: "saturation")
            f.setValue(0.05, forKey: "brightness")
            return f.outputImage ?? image
        case .dramatic:
            guard let f = CIFilter(name: "CIColorControls") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.2, forKey: "saturation")
            f.setValue(1.3, forKey: "contrast")
            f.setValue(0.05, forKey: "brightness")
            return f.outputImage ?? image
        case .film:
            guard let f = CIFilter(name: "CIVignette") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(0.8, forKey: "intensity")
            f.setValue(250.0, forKey: "radius")
            return f.outputImage ?? image
        }
    }
}
