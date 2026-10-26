import AVFoundation
import SwiftUI

/// Pro 手动控制：ISO / 快门 / 曝光补偿 / 对焦 / 白平衡
@MainActor
class ProController: ObservableObject {
    @Published var iso: Double = 100
    @Published var shutterNumerator: Double = 1000
    @Published var exposureOffset: Double = 0
    @Published var focusMode: AVDeviceFocusMode = .auto
    @Published var wbTemperature: Double = 5500
    @Published var autoOn: Bool = true
    @Published var hint: String = ""

    func apply(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isISOEnabledSupported {
                device.isISOEnabled = true
                device.isoSensitivity = iso
            }
            if device.isExposureDurationSupported, !autoOn {
                let lo = Double(device.minExposureDuration)
                let hi = Double(device.maxExposureDuration)
                let shutter = min(max(1.0 / shutterNumerator, lo), hi)
                device.exposureDuration = CMTime(seconds: shutter, preferredTimescale: 1_000_000)
            }
            if device.isExposureTargetOffsetSupported {
                device.exposureTargetOffset = exposureOffset
            }
            if !autoOn, device.isFocusModeSupported(.fixed) {
                device.focusMode = .fixed
            } else {
                device.focusMode = focusMode
            }
            if device.isWhiteBalanceTemperatureAndTintSupported {
                device.isLockedForWhiteBalance = false
                device.whiteBalanceTemperature = wbTemperature
            }
            device.unlockForConfiguration()
            hint = ""
        } catch {
            hint = "设置失败：\(error.localizedDescription)"
        }
    }
}

struct ProModeView: View {
    @ObservedObject var pro: ProController
    let device: AVCaptureDevice

    var body: some View {
        VStack(alignment: .leading, spacing: CNTheme.sp16) {
            header
            if !pro.hint.isEmpty {
                Text(pro.hint)
                    .font(CNTheme.f12)
                    .foregroundStyle(Color(CNTheme.cinnabar))
            }
            sliderRow(title: "ISO", value: $pro.iso, range: 50...3200, step: 25)
            sliderRow(title: "快门 1/\(Int(pro.shutterNumerator))s",
                      value: $pro.shutterNumerator, range: 8...4000, step: 1)
            sliderRow(title: "曝光补偿 \(String(format: "%+.1f", pro.exposureOffset)) EV",
                      value: $pro.exposureOffset, range: -2...2, step: 0.5)
            sliderRow(title: "白平衡 \(Int(pro.wbTemperature))K",
                      value: $pro.wbTemperature, range: 2800...12000, step: 100)
            HStack(spacing: CNTheme.sp8) {
                Button {
                    pro.autoOn.toggle()
                    pro.apply(to: device)
                } label: {
                    Label(pro.autoOn ? "自动" : "手动", systemImage: pro.autoOn ? "circle.fill" : "circle")
                        .font(CNTheme.f14)
                }
                .buttonStyle(.bordered)
                Text("ISO \(Int(pro.iso)) · 1/\(Int(pro.shutterNumerator))s")
                    .font(CNTheme.f12)
                    .foregroundStyle(Color(CNTheme.inkSub))
            }
            Spacer()
        }
        .padding(CNTheme.sp16)
    }

    private var header: some View {
        HStack {
            Text("Pro 手动")
                .font(CNTheme.f22)
                .foregroundStyle(Color(CNTheme.ink))
            Spacer()
            Text("轻调 · 藏而不露")
                .font(CNTheme.f12)
                .foregroundStyle(Color(CNTheme.inkFaint))
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: CNTheme.sp4) {
            Text(title)
                .font(CNTheme.f14)
                .foregroundStyle(Color(CNTheme.ink))
            Slider(value: value, in: range, step: step) {
                pro.apply(to: device)
            }
            .tint(Color(CNTheme.indigo))
        }
    }
}
