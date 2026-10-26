import SwiftUI

// MARK: - 设置（功能中枢 · iCloud · 外观 · 中式皮）

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var icloud = ICloudSyncService()
    @AppStorage("aperturePro.cloudSync") private var cloudSync: Bool = false
    @AppStorage("aperturePro.colorScheme") private var colorSchemeIndex: Int = 0
    @State private var module: FeatureModule?
    @State private var showDocScan: Bool = false

    enum FeatureModule: String, Identifiable {
        case ar = "AR"
        case ip = "IP"
        case motion = "Motion"
        case qr = "QR"
        case video = "Video"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    moduleRow("AR 面部追踪", "faceportrait") {
                        module = .ar
                    }
                    moduleRow("IP 推流 · 手机变摄像头", "video.badge.record") {
                        module = .ip
                    }
                    moduleRow("频闪摄影", "bolt.horizontal.circle") {
                        module = .motion
                    }
                    moduleRow("扫码识别", "qrcode") {
                        module = .qr
                    }
                    moduleRow("视频编辑", "scissors") {
                        module = .video
                    }
                    moduleRow("文档扫描", "doc.text.viewfinder") {
                        showDocScan = true
                    }
                } header: {
                    Text("功能模块")
                } footer: {
                    Text("含蓄 · 藏而不露，需要时再取用")
                        .font(CNTheme.f12)
                }

                Section {
                    Toggle("iCloud 同步", isOn: $cloudSync)
                    if cloudSync {
                        HStack {
                            Text(icloud.isSyncing ? "同步中…" : "状态")
                                .font(CNTheme.f14)
                            Spacer()
                            Text(icloud.lastMessage)
                                .font(CNTheme.f12)
                                .foregroundStyle(Color(CNTheme.inkFaint))
                        }
                        Button("立即同步") {
                            icloud.scheduleBackgroundSync()
                            icloud.backgroundSync()
                        }
                        .font(CNTheme.f14)
                        .tint(Color(CNTheme.indigo))
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("同步需要 Apple ID 开启 iCloud 云盘")
                        .font(CNTheme.f12)
                }

                Section {
                    LabeledContent("外观") {
                        Picker("外观", selection: $colorSchemeIndex) {
                            Text("跟随系统").tag(0)
                            Text("宣纸（浅）").tag(1)
                            Text("夜墨（深）").tag(2)
                        }
                        .pickerStyle(.menu)
                        .tint(Color(CNTheme.indigo))
                    }
                } header: {
                    Text("中式皮")
                } footer: {
                    Text("宣纸米白 · 青黛 · 朱砂点缀，留白 4pt 网格")
                        .font(CNTheme.f12)
                }

                Section {
                    LabeledContent("版本") {
                        Text("1.1.0 (20261027.01)")
                            .font(CNTheme.f14)
                            .foregroundStyle(Color(CNTheme.inkSub))
                    }
                    LabeledContent("制作者") {
                        Text("主人与姐姐")
                            .font(CNTheme.f14)
                            .foregroundStyle(Color(CNTheme.inkSub))
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .background(CNTheme.pageBackground())
        }
        .tint(Color(CNTheme.indigo))
        .onChange(of: colorSchemeIndex) { index in
            appState.colorScheme = index == 0 ? nil : (index == 1 ? .light : .dark)
        }
        .onAppear {
            icloud.foregroundFetch()
        }
        .sheet(item: $module) { m in
            NavigationStack {
                moduleView(m)
            }
        }
        .sheet(isPresented: $showDocScan) {
            NavigationStack {
                DocumentScanView()
            }
        }
    }

    @ViewBuilder
    private func moduleView(_ m: FeatureModule) -> some View {
        switch m {
        case .ar:
            ARFaceView()
                .navigationTitle("AR 面部追踪")
        case .ip:
            IPStreamerView()
                .navigationTitle("IP 推流")
        case .motion:
            MotionShotView()
                .navigationTitle("频闪摄影")
        case .qr:
                QRScannerView()
                    .navigationTitle("扫码识别")
        case .video:
            VideoEditorView()
                .navigationTitle("视频编辑")
        }
    }

    private func moduleRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CNTheme.sp8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color(CNTheme.indigo))
                    .frame(width: 24)
                Text(title)
                    .font(CNTheme.f15)
                    .foregroundStyle(Color(CNTheme.ink))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color(CNTheme.inkFaint))
            }
        }
        .tint(Color(CNTheme.ink))
    }
}
