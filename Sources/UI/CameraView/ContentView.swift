import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - 根视图：四个标签页 + 中式皮 + iCloud 场景联动

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var icloud = ICloudSyncService()

    var body: some View {
        ZStack {
            Group {
            switch appState.currentTab {
            case .camera:
                CameraPage()
            case .gallery:
                TabbedPage { GalleryView() }
            case .editor:
                TabbedPage { EditorView() }
            case .settings:
                TabbedPage { SettingsView() }
            }
            }
            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        }
        .animation(.easeInOut(duration: 0.22), value: appState.currentTab)
        .tint(CNTheme.indigo)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                icloud.backgroundSync()
            } else if phase == .active {
                icloud.foregroundFetch()
            }
        }
    }
}

// MARK: - 非相机页：内容 + 中式标签栏

struct TabbedPage<Content: View>: View {
    let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
            AppTabBar()
        }
        .background(CNTheme.pageBackground())
    }
}

// MARK: - 中式标签栏（留白 · 素色 · 朱砂一点）

struct AppTabBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.gallery, icon: "photo.on.rectangle.angled", title: "相册")
            tabButton(.editor, icon: "wand.and.stars", title: "编辑")
            tabButton(.settings, icon: "gearshape", title: "设置")
        }
        .padding(.top, CNTheme.sp8)
        .padding(.bottom, CNTheme.sp4)
        .background(CNTheme.paper.opacity(0.94).ignoresSafeArea())
    }

    private func tabButton(_ tab: MainTab, icon: String, title: String) -> some View {
        Button {
            appState.currentTab = tab
        } label: {
            VStack(spacing: CNTheme.sp4) {
                Image(systemName: appState.currentTab == tab ? icon + ".fill" : icon)
                    .font(.system(size: 20, weight: .light))
                Text(title)
                    .font(CNTheme.f10)
            }
            .foregroundStyle(appState.currentTab == tab ? CNTheme.indigo : CNTheme.inkFaint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 相机页（全功能）

struct CameraPage: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var engine = CameraEngine()
    @StateObject private var pro = ProController()
    @State private var showProSheet: Bool = false
    @State private var showDocSheet: Bool = false
    @State private var countdown: Int?
    @State private var timerTask: Task<Void, Never>?
    @State private var lastPhoto: Data?
    @State private var showShareSheet: Bool = false
    @State private var timerSeconds: Int?
    @State private var timelapseDone: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(engine: engine)
                .ignoresSafeArea()
            if engine.mode == .panorama {
                PanoramaView(engine: engine)
            }
            if let countdown {
                timerOverlay(countdown)
            }
            VStack {
                topControls
                Spacer()
                if engine.mode == .timelapse {
                    timelapseControls
                } else {
                    bottomControls
                }
            }
            .padding(.vertical, CNTheme.sp8)
        }
        .onAppear {
            engine.start()
            engine.onPhotoCaptured = { data in
                saveAndShow(data)
            }
            engine.onVideoFinished = { name in
                let url = CameraEngine.mediaDir.appendingPathComponent(name)
                Task {
                    _ = await PHLibraryService.requestAuth()
                    _ = PHLibraryService.saveVideo(url)
                }
            }
            engine.setFrameCallback { buf in
                if engine.mode == .timelapse, engine.timelapse.isWriting {
                    engine.timelapse.addFrame(buf)
                } else if engine.mode == .panorama, engine.panoramaEngine.isCollecting {
                    if let pb = CMSampleBufferGetImageBuffer(buf) {
                        engine.panoramaEngine.addFrame(pb)
                    }
                }
            }
        }
        .onDisappear {
            timerTask?.cancel()
            engine.stop()
        }
        .sheet(isPresented: $showProSheet) {
            if let dev = engine.currentDevice {
                ProModeView(pro: pro, device: dev)
                    .presentationDetents([.medium])
            } else {
                Text("无可用相机")
                    .foregroundStyle(CNTheme.ink)
                    .padding()
            }
        }
        .sheet(isPresented: $showDocSheet) {
            NavigationStack {
                DocumentScanView()
                    .onAppear { engine.stop() }
                    .onDisappear { engine.start() }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareView(items: lastPhoto.map { [$0] } ?? [])
        }
    }
    // MARK: 顶部 · 模式 + 快捷

    private var topControls: some View {
        VStack(spacing: CNTheme.sp8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CNTheme.sp8) {
                    ForEach(CameraEngine.CaptureMode.allCases, id: \.self) { m in
                        CNTheme.ModeChip(title: m.rawValue, icon: modeIcon(m), active: engine.mode == m) {
                            selectMode(m)
                        }
                    }
                }
                .padding(.horizontal, CNTheme.sp12)
            }
            HStack(spacing: CNTheme.sp24) {
                Button { appState.currentTab = .gallery } label: {
                    topIcon("photo.on.rectangle.angled")
                }
                Button { appState.currentTab = .settings } label: {
                    topIcon("gearshape")
                }
                Spacer()
                timerChip
                Button {
                    showProSheet = true
                } label: {
                    topIcon("slider.horizontal.3")
                }
                Button {
                    engine.setFlash(engine.flashMode == .off ? .auto : .off)
                } label: {
                    topIcon(engine.flashMode == .off ? "bolt.slash" : "bolt.fill")
                }
                Button {
                    engine.switchCamera(engine.cameraPosition == .back ? .front : .back)
                } label: {
                    topIcon("camera.rotate")
                }
                Spacer()
                filterChips
            }
            .padding(.horizontal, CNTheme.sp16)
        }
    }

    private func topIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.white.opacity(0.08)))
    }

    private func modeIcon(_ m: CameraEngine.CaptureMode) -> String {
        switch m {
        case .photo: "camera"
        case .video: "video"
        case .slowMo: "tortoise"
        case .timelapse: "clock.arrow.circlepath"
        case .livePhoto: "photo"
        case .night: "moon.stars"
        case .panorama: "rectangle.and.rectangle.crossing"
        case .document: "doc.text.viewfinder"
        }
    }

    private func selectMode(_ m: CameraEngine.CaptureMode) {
        switch m {
        case .document:
            engine.setMode(.document)
            showDocSheet = true
        case .livePhoto:
            // Live 能力按官方口径在 photo output 上查（device 没有该属性）
            guard engine.currentDevice != nil, AVCapturePhotoOutput().isLivePhotoCaptureSupported else {
                engine.setMode(.photo)
                return
            }
            engine.setMode(.livePhoto)
        default:
            engine.setMode(m)
        }
    }

    private var timerChip: some View {
        Button {
            if timerSeconds == nil {
                timerSeconds = 5
            } else {
                timerSeconds = nil
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "timer")
                    .font(.system(size: 16))
                Text(timerSeconds.map { "\($0)s" } ?? "定时")
                    .font(CNTheme.f10)
            }
            .foregroundStyle(timerSeconds != nil ? CNTheme.cinnabar : .white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.white.opacity(0.08)))
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CNTheme.sp4) {
                ForEach(FilterPreset.allCases, id: \.self) { preset in
                    Button(preset.rawValue) {
                        engine.filterEngine.activeFilter = preset
                    }
                    .font(CNTheme.f12)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(engine.filterEngine.activeFilter == preset
                            ? CNTheme.cinnabar : .white.opacity(0.1))
                    )
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 220)
    }

    // MARK: 底部 · 快门 / 录像 / 定时

    private var bottomControls: some View {
        HStack(spacing: 0) {
            if engine.mode == .video || engine.mode == .slowMo {
                recordButton
            } else {
                Button { } label: {
                    Circle().fill(.white.opacity(0.15)).frame(width: 56, height: 56)
                }
                .disabled(true)
            }
            Spacer()
            shutterButton
            Spacer()
            if engine.mode == .night {
                Button("夜景长曝", action: {})
                    .font(CNTheme.f12)
                    .foregroundStyle(CNTheme.cinnabar)
            } else {
                Button { } label: {
                    Circle().fill(.white.opacity(0.15)).frame(width: 56, height: 56)
                }
                .disabled(true)
            }
        }
        .padding(.horizontal, CNTheme.sp24)
    }

    private var shutterButton: some View {
        Group {
            if engine.isCapturing {
                ProgressView()
                    .tint(.white)
                    .frame(width: 72, height: 72)
            } else {
                Button {
                    doShutter()
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(CNTheme.shutterRing, lineWidth: 4))
                        .animation(.easeInOut(duration: 0.15), value: engine.isCapturing)
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            if engine.isCapturing {
                engine.stopRecording()
            } else {
                engine.startRecording()
            }
        } label: {
            VStack(spacing: CNTheme.sp4) {
                Circle()
                    .fill(engine.isCapturing ? CNTheme.cinnabar : .white)
                    .frame(width: 14, height: 14)
                Text(engine.isCapturing ? "停止" : "录像")
                    .font(CNTheme.f10)
            }
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(.white.opacity(0.08)))
        }
    }

    private var timelapseControls: some View {
        HStack(spacing: CNTheme.sp16) {
            Button {
                if let name = engine.timelapse.stop() {
                    timelapseDone = name
                }
            } label: {
                VStack(spacing: CNTheme.sp4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 34))
                    Text("停止合成")
                        .font(CNTheme.f10)
                }
                .foregroundStyle(.white)
            }
            if let done = timelapseDone {
                Text("已存 \(done)")
                    .font(CNTheme.f10)
                    .foregroundStyle(CNTheme.cinnabar)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var timerOverlay: some View {
        Text("\(countdown ?? 0)")
            .font(.system(size: 96, weight: .thin))
            .foregroundStyle(Color.white.opacity(0.9))
            .transition(.opacity)
    }

    private func doShutter() {
        switch engine.mode {
        case .video, .slowMo:
            if engine.isCapturing {
                engine.stopRecording()
            } else {
                engine.startRecording()
            }
        case .timelapse:
            break
        case .panorama, .document:
            break
        default:
            if let secs = timerSeconds {
                startCountdown(secs)
            } else {
                engine.capturePhoto()
            }
        }
    }

    private func startCountdown(_ secs: Int) {
        timerTask?.cancel()
        let eng = engine
        timerTask = Task { @MainActor in
            var c = secs
            while c > 0 {
                guard !Task.isCancelled else { return }
                countdown = c
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                c -= 1
            }
            countdown = nil
            eng.capturePhoto()
        }
    }

    private func saveAndShow(_ data: Data) {
        var out = data
        if engine.filterEngine.activeFilter != .original {
            out = engine.filterEngine.applyFilter(data, preset: engine.filterEngine.activeFilter) ?? data
        }
        lastPhoto = out
        showShareSheet = true
    }
}
