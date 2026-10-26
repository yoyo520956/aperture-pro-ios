import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            mainContent
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .opacity))
        }
        .animation(.easeInOut(duration: 0.25), value: appState.currentTab)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.currentTab {
        case .camera:
            CameraView()
        case .gallery:
            GalleryView()
        case .editor:
            EditorView()
        case .settings:
            SettingsView()
        }
    }
}

struct CameraView: View {
    @StateObject private var engine = CameraEngine()
    @State private var showManualPanel: Bool = false
    @State private var showFilterPanel: Bool = false
    @State private var lastPhoto: Data?
    @State private var showShareSheet: Bool = false
    @State private var recordedVideo: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(engine: engine)
                .ignoresSafeArea()

            VStack {
                topControls
                Spacer()
                bottomControls
            }
            .padding(.vertical, 8)
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sheet(isPresented: $showShareSheet) {
            ShareView(items: lastPhoto.map { [Data($0)] } ?? [])
        }
    }

    private var topControls: some View {
        HStack(spacing: 20) {
            Button {
                showManualPanel = !showManualPanel
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                engine.switchCamera(engine.cameraPosition == .back ? .front : .back)
            } label: {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            Button {
                engine.setFlash(engine.flashMode == .off ? .on : .off)
            } label: {
                Image(systemName: engine.flashMode == .off ? "bolt.slash" : "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(engine.flashMode == .off ? .white : .yellow)
            }
        }
    }

    private var bottomControls: some View {
        HStack {
            Button {
                showFilterPanel = !showFilterPanel
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 18))
                    Text("滤镜")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white)
            }

            Spacer()

            if engine.isCapturing && !lastPhoto.isEmpty {
                ProgressView()
                    .tint(.white)
            } else {
                Button {
                    let data = engine.capturePhoto()
                    if let data {
                        lastPhoto = data
                        showShareSheet = true
                    }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 4)
                        )
                }
            }

            Spacer()

            Button {
                if engine.isCapturing {
                    recordedVideo = engine.stopRecording()
                } else {
                    engine.startRecording()
                }
            } label: {
                VStack(spacing: 4) {
                    Circle()
                        .fill(engine.isCapturing ? .red : .white)
                        .frame(width: 12, height: 12)
                    Text(engine.isCapturing ? "停止" : "录像")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white)
            }
        }
    }
}
