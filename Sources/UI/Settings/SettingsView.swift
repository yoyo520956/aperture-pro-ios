import SwiftUI

struct SettingsView: View {
    @AppStorage("aperturePro.flashMode") private var flashMode: Int = 0
    @AppStorage("aperturePro.cameraPosition") private var cameraPosition: Int = 1
    @AppStorage("aperturePro.enableAR") private var enableAR: Bool = true
    @AppStorage("aperturePro.enableIPStream") private var enableIPStream: Bool = true
    @AppStorage("aperturePro.enableMotionShot") private var enableMotionShot: Bool = true
    @AppStorage("aperturePro.enableQRScanner") private var enableQRScanner: Bool = true
    @AppStorage("aperturePro.enableVideoEditor") private var enableVideoEditor: Bool = true
    @AppStorage("aperturePro.cloudSync") private var cloudSync: Bool = false
    @AppStorage("aperturePro.colorScheme") private var colorSchemeIndex: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("闪光灯") {
                        Picker("闪光灯", selection: $flashMode) {
                            Text("关").tag(0)
                            Text("自动").tag(1)
                            Text("常亮").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    LabeledContent("默认镜头") {
                        Picker("镜头", selection: $cameraPosition) {
                            Text("后置").tag(1)
                            Text("前置").tag(0)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("相机")
                }

                Section {
                    Toggle("AR 面部追踪", isOn: $enableAR)
                    Toggle("IP 推流（手机变摄像头）", isOn: $enableIPStream)
                    Toggle("频闪摄影", isOn: $enableMotionShot)
                    Toggle("扫码识别", isOn: $enableQRScanner)
                    Toggle("视频编辑", isOn: $enableVideoEditor)
                } header: {
                    Text("功能模块")
                } footer: {
                    Text("关闭的功能不会在相机界面显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("颜色模式") {
                        Picker("模式", selection: $colorSchemeIndex) {
                            Text("跟随系统").tag(0)
                            Text("浅色").tag(1)
                            Text("深色").tag(2)
                        }
                    }
                    Toggle("iCloud 同步", isOn: $cloudSync)
                } header: {
                    Text("外观与数据")
                } footer: {
                    Text("iCloud 同步需要 Apple ID 登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0 (20261026.01)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("开发者")
                        Spacer()
                        Text("Aperture Pro Team")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
        }
    }
}
