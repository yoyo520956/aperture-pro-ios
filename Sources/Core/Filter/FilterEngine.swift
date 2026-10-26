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
            let c = CIFilter.vignette()
            c.inputImage = output
            c.intensity = 1.2
            c.radius = 180
            output = c.outputImage
        case .blackWhite:
            let c = CIFilter.photoEffect()
            c.inputImage = output
            c.outputImage = output
            let c2 = CIFilter.colorControls()
            c2.inputImage = c.outputImage
            c2.saturation = 0.0
            output = c2.outputImage
        case .sepia:
            let c = CIFilter.sepiaTone()
            c.inputImage = output
            c.intensity = 1.0
            output = c.outputImage
        case .cool:
            let c = CIFilter.colorControls()
            c.inputImage = output
            c.temperature = -0.3
            c.tint = 10
            c.saturation = 1.1
            output = c.outputImage
        case .warm:
            let c = CIFilter.colorControls()
            c.inputImage = output
            c.temperature = 0.3
            c.tint = 10
            c.saturation = 1.1
            output = c.outputImage
        case .dramatic:
            let c = CIFilter.colorControls()
            c.inputImage = output
            c.brightness = 0.1
            c.contrast = 1.3
            c.saturation = 1.2
            output = c.outputImage
        case .film:
            let c = CIFilter.vignette()
            c.inputImage = output
            c.intensity = 0.8
            c.radius = 250
            output = c.outputImage
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
