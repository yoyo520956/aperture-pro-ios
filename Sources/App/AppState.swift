import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var currentTab: MainTab = .camera
    @Published var colorScheme: ColorScheme?
    @Published var isCapturing: Bool = false
    @Published var lastCapturedMedia: MediaItem?

    var colorScheme: ColorScheme? {
        didSet {
            if colorScheme == nil {
                // 跟随系统
            }
        }
    }
}

enum MainTab: Int, CaseIterable {
    case camera = 0
    case gallery = 1
    case editor = 2
    case settings = 3

    var title: String {
        switch self {
        case .camera: return "相机"
        case .gallery: return "相册"
        case .editor: return "编辑"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .gallery: return "photo.on.rectangle.angled"
        case .editor: return "wand.and.stars"
        case .settings: return "gearshape.fill"
        }
    }
}
