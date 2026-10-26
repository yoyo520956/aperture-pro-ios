import SwiftUI

struct EditorView: View {
    @StateObject private var filterEngine = FilterEngine()
    @State private var selectedImage: Data?
    @State private var originalImage: Data?
    @State private var showPicker: Bool = false
    @State private var resultImage: Data?
    @State private var processing: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let img = resultImage ?? selectedImage {
                    Image(uiImage: UIImage(data: img) ?? UIImage())
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 56))
                            .foregroundStyle(.gray)
                        Text("选择一张照片开始编辑")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                HStack(spacing: 8) {
                    Button("选择照片") {
                        showPicker = true
                    }
                    .buttonStyle(.bordered)

                    if let orig = originalImage {
                        Button("应用滤镜") {
                            processing = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                if let filtered = filterEngine.applyFilter(orig, preset: filterEngine.activeFilter) {
                                    DispatchQueue.main.async {
                                        resultImage = filtered
                                        processing = false
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(processing)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterEngine.filterPresets, id: \.self) { preset in
                            FilterChip(preset: preset, isActive: filterEngine.activeFilter == preset)
                                .onTapGesture {
                                    filterEngine.activeFilter = preset
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        resultImage = nil
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("编辑")
            .sheet(isPresented: $showPicker) {
                PhotoPickerView { data in
                    selectedImage = data
                    originalImage = data
                    resultImage = nil
                }
            }
        }
    }
}

struct FilterChip: View {
    let preset: FilterPreset
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? .blue : .gray.opacity(0.5))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 16))
                        .foregroundStyle(isActive ? .white : .white.opacity(0.6))
                }
            Text(preset.rawValue)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

struct PhotoPickerView: View {
    var onPick: (Data) -> Void
    @State private var pickedImage: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("确认选择") {
                    if let data = img.jpegData(compressionQuality: 0.92) {
                        onPick(data)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                    Text("选择一张照片")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
        .padding()
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upTo: .medium))
    }
}
