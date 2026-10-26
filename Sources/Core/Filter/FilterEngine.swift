import CoreImage
import CoreImage.CIFilterBuiltins

class FilterEngine: ObservableObject {
    @Published var activeFilter: FilterPreset = .original
    let filterPresets: [FilterPreset] = [
        .original, .vintage, .blackWhite, .sepia, .cool, .warm, .dramatic, .film
    ]

    private let ciContext = CIContext()

    func applyFilter(_ data: Data, preset: FilterPreset) -> Data? {
        guard let image = UIImage(data: data),
              let ciImage = CIImage(image: image) else { return nil }

        var output = ciImage
        switch preset {
        case .original:
            break
        case .vintage:
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = 1.2
            filter.radius = 180
            output = filter.outputImage
        case .blackWhite:
            let filter = CIFilter.photoEffect()
            filter.inputImage = output
            filter.outputImage = output
            let c2 = CIFilter.colorControls()
            filter.inputImage = filter.outputImage
            filter.saturation = 0.0
            output = filter.outputImage
        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = output
            filter.intensity = 1.0
            output = filter.outputImage
        case .cool:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.temperature = -0.3
            filter.tint = 10
            filter.saturation = 1.1
            output = filter.outputImage
        case .warm:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.temperature = 0.3
            filter.tint = 10
            filter.saturation = 1.1
            output = filter.outputImage
        case .dramatic:
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.brightness = 0.1
            filter.contrast = 1.3
            c.saturation = 1.2
            output = filter.outputImage
        case .film:
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = 0.8
            filter.radius = 250
            output = filter.outputImage
        }

        let render = ciContext.createCGImage(output, from: ciImage.extent)
        guard let uiImage = UIImage(cgImage: render) else { return nil }
        return uiImage.jpegData(compressionQuality: 0.92)
    }
}

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
