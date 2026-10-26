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
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = 1.2
            filter.radius = 180.0
            if let result = filter.outputImage {
                output = result
            }
        case .blackWhite:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = output
            if let result = filter.outputImage {
                output = result
            }
        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = output
            filter.intensity = 1.0
            if let result = filter.outputImage {
                output = result
            }
        case .cool:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.saturation = 1.1
            filter.contrast = 1.05
            if let result = filter.outputImage {
                output = result
            }
        case .warm:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.saturation = 1.15
            filter.brightness = 0.05
            if let result = filter.outputImage {
                output = result
            }
        case .dramatic:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.brightness = 0.05
            filter.contrast = 1.3
            filter.saturation = 1.2
            if let result = filter.outputImage {
                output = result
            }
        case .film:
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = 0.8
            filter.radius = 250.0
            if let result = filter.outputImage {
                output = result
            }
        }

        guard let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
        else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.92)
    }
}
