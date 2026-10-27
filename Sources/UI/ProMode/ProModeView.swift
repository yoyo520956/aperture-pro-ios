import AVFoundation
import SwiftUI

/// Pro 手动控制：ISO / 快门 / 曝光补偿 / 对焦 / 白平衡
/// 官方链路：手动曝光 setExposureModeCustom(duration:iso:)，补偿 setExposureTargetBias，
/// 白平衡手动 = setWhiteBalanceModeLocked（锁定当前画面白平衡，K 值为取景参考）
@MainActor
class ProController: ObservableObject {
    @Published var iso: Double = 100
    @Published var shutterNumerator: Double = 1000
    @Published var exposureOffset: Double = 0
    @Published var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    @Published var wbTemperature: Double = 5500
    @Published var autoOn: Bool = true
    @Published var hint: String = ""

    func apply(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // ---- 曝光：手动 = 自定义时长 + ISO（夹在设备/格式允许范围内）----
            // minISO/maxISO 在当前 SDK 不可用，改用通用 ISO 夹取区间
            let targetISO = Float(max(100.0, min(12800.0, iso)))
            let fmt = device.activeFormat
            var want = CMTime(seconds: min(max(1.0 / shutterNumerator, 1.0 / 8000.0), 1.0 / 4.0),
                              preferredTimescale: 1_000_000)
            if CMTimeCompare(want, fmt.maxExposureDuration) > 0 { want = fmt.maxExposureDuration }
            if CMTimeCompare(want, fmt.minExposureDuration) < 0 { want = fmt.minExposureDuration }
            if !autoOn {
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: want, iso: targetISO,
                                                 completionHandler: nil)
                }
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                device.exposureMode = .continuousAutoExposure
            }

            // ---- 曝光补偿（bias，钳到设备范围）----
            let bias = Float(min(max(exposureOffset,
                                     Double(device.minExposureTargetBias)),
                                 Double(device.maxExposureTargetBias)))
            device.setExposureTargetBias(bias, completionHandler: nil)

            // ---- 对焦：手动 = 锁定，自动 = 连续对焦 ----
            if !autoOn, device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            // ---- 白平衡：手动 = 锁定当前；自动 = 连续白平衡 ----
            if !autoOn, device.isWhiteBalanceModeSupported(.locked) {
                device.setWhiteBalanceModeLocked(completionHandler: nil)
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
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
                    .foregroundStyle(CNTheme.cinnabar)
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
                    .foregroundStyle(CNTheme.inkSub)
            }
            Spacer()
        }
        .padding(CNTheme.sp16)
    }

    private var header: some View {
        HStack {
            Text("Pro 手动")
                .font(CNTheme.f22)
                .foregroundStyle(CNTheme.ink)
            Spacer()
            Text("轻调 · 藏而不露")
                .font(CNTheme.f12)
                .foregroundStyle(CNTheme.inkFaint)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: CNTheme.sp4) {
            Text(title)
                .font(CNTheme.f14)
                .foregroundStyle(CNTheme.ink)
            Slider(value: value, in: range, step: step,
                   onEditingChanged: { _ in pro.apply(to: device) })
                .tint(CNTheme.indigo)
        }
    }
}
