import SwiftUI
import PhotosUI
import CoreImage

// MARK: - 编辑页（滤镜 + 裁剪 + 旋转 + 调色 · 中式皮）

struct EditorView: View {
    @StateObject private var filterEngine = FilterEngine()
    @State private var selection: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var cropAspect: CropAspect = .original
    @State private var rotation: Int = 0
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var output: UIImage?
    @State private var note: String = ""
    @State private var showShare: Bool = false

    enum CropAspect: String, CaseIterable {
        case original = "原画"
        case square = "1:1"
        case fourThree = "4:3"
        case nineSixteen = "9:16"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CNTheme.sp12) {
                previewArea
                controls
                if !note.isEmpty {
                    Text(note)
                        .font(CNTheme.f12)
                        .foregroundStyle(Color(CNTheme.inkFaint))
                }
            }
            .padding(CNTheme.sp16)
            .background(CNTheme.pageBackground())
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var previewArea: some View {
        ZStack {
            if let img = output ?? source {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: CNTheme.r8))
            } else {
                VStack(spacing: CNTheme.sp8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(Color(CNTheme.inkFaint))
                    Text("选一张照片")
                        .font(CNTheme.f15)
                        .foregroundStyle(Color(CNTheme.inkSub))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(CNTheme.card())
            }
        }
    }

    private var controls: some View {
        VStack(spacing: CNTheme.sp12) {
            PhotosPicker(selection: $selection, matching: .images) {
                Label("选择照片", systemImage: "plus.rectangle.on.rectangle")
                    .font(CNTheme.f14)
            }
            .buttonStyle(.bordered)
            .tint(Color(CNTheme.indigo))
            .onChange(of: selection) { item in
                Task { @MainActor in
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        source = ui
                        output = nil
                        render()
                    }
                }
            }

            HStack(spacing: CNTheme.sp8) {
                ForEach(CropAspect.allCases, id: \.self) { a in
                    Button(a.rawValue) {
                        cropAspect = a
                        render()
                    }
                    .buttonStyle(.bordered)
                    .tint(cropAspect == a ? Color(CNTheme.indigo) : Color(CNTheme.inkFaint))
                }
                Button {
                    rotation = (rotation + 90) % 360
                    render()
                } label: {
                    Label("旋转", systemImage: "arrow.right.arrow.left")
                }
                .buttonStyle(.bordered)
                .tint(Color(CNTheme.inkSub))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CNTheme.sp4) {
                    ForEach(FilterPreset.allCases, id: \.self) { preset in
                        FilterChip(preset: preset, isActive: filterEngine.activeFilter == preset)
                            .onTapGesture {
                                filterEngine.activeFilter = preset
                                render()
                            }
                    }
                }
            }

            adjustSlider("亮度", value: $brightness, range: -0.3...0.3)
            adjustSlider("对比", value: $contrast, range: 0.5...1.8)
            adjustSlider("饱和", value: $saturation, range: 0...2)

            HStack(spacing: CNTheme.sp16) {
                Button {
                    reset()
                } label: {
                    Text("重置").font(CNTheme.f14)
                }
                .tint(Color(CNTheme.inkSub))
                Spacer()
                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "checkmark")
                        .font(CNTheme.f14)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(CNTheme.cinnabar))
                .disabled(output == nil)
            }
        }
    }

    private func adjustSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(CNTheme.f12)
                .foregroundStyle(Color(CNTheme.inkSub))
                .frame(width: 36, alignment: .leading)
            Slider(value: value, in: range) { editing in
                if !editing { render() }
            }
            .tint(Color(CNTheme.indigo))
        }
    }

    private func reset() {
        cropAspect = .original
        rotation = 0
        brightness = 0
        contrast = 1.0
        saturation = 1.0
        filterEngine.activeFilter = .original
        render()
    }

    private func save() {
        guard let output, let data = output.jpegData(compressionQuality: 0.92) else {
            note = "保存失败"
            return
        }
        let name = "edit_\(Int(Date().timeIntervalSince1970)).jpg"
        try? data.write(to: CameraEngine.mediaDir.appendingPathComponent(name))
        _ = PHLibraryService.saveImage(data)
        note = "已保存到相册"
        output = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            note = ""
        }
    }
}

// MARK: - 渲染管线

extension EditorView {
    func render() {
        guard let source else { return }
        let ci = CIImage(image: source) ?? CIImage()
        let scale = min(1, 2048 / max(CGFloat(ci.extent.width), CGFloat(ci.extent.height)))
        var img = ci
        if scale < 1 {
            img = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        img = crop(img)
        img = rotate(img)
        img = adjust(img)
        img = filterEngine.renderPreset(img, preset: filterEngine.activeFilter)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(img, from: img.extent) else { return }
        output = UIImage(cgImage: cg)
    }

    private func crop(_ ci: CIImage) -> CIImage {
        let e = ci.extent
        switch cropAspect {
        case .original:
            return ci
        case .square:
            let s = min(e.width, e.height)
            return ci.cropped(to: CGRect(x: (e.width - s) / 2, y: (e.height - s) / 2, width: s, height: s))
        case .fourThree:
            let w = e.height * 4 / 3
            let cw = min(w, e.width)
            let ch = cw * 3 / 4
            return ci.cropped(to: CGRect(x: (e.width - cw) / 2, y: (e.height - ch) / 2, width: cw, height: ch))
        case .nineSixteen:
            let h = e.width * 16 / 9
            let ch = min(h, e.height)
            let cw = ch * 9 / 16
            return ci.cropped(to: CGRect(x: (e.width - cw) / 2, y: (e.height - ch) / 2, width: cw, height: ch))
        }
    }

    private func rotate(_ ci: CIImage) -> CIImage {
        var img = ci
        for _ in 0..<(rotation / 90) {
            img = img.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
        }
        return img
    }

    private func adjust(_ ci: CIImage) -> CIImage {
        guard brightness != 0 || contrast != 1.0 || saturation != 1.0 else { return ci }
        guard let f = CIFilter(name: "CIColorControls") else { return ci }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(brightness, forKey: "brightness")
        f.setValue(contrast, forKey: "contrast")
        f.setValue(saturation, forKey: "saturation")
        return f.outputImage ?? ci
    }
}

// MARK: - 滤镜胶囊

struct FilterChip: View {
    let preset: FilterPreset
    let isActive: Bool

    var body: some View {
        Text(preset.rawValue)
            .font(CNTheme.f12)
            .padding(.horizontal, CNTheme.sp12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? Color(CNTheme.cinnabar) : Color(CNTheme.paperDeep))
            )
            .foregroundStyle(isActive ? .white : Color(CNTheme.inkSub))
            .overlay(
                Capsule().stroke(isActive ? Color.clear : Color(CNTheme.line), lineWidth: 1)
            )
    }
}
