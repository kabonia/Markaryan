import SwiftUI
import AVFoundation

/// The iPhone flashlight. Works while the camera, an AR session or a room scan is running.
@MainActor final class Torch: ObservableObject {
    @Published private(set) var isOn = false

    static var isAvailable: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { isOn = false; return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
            device.unlockForConfiguration()
            isOn = on
        } catch {
            isOn = false
        }
    }
}

/// Round flashlight button for camera screens; switches the light off when the screen closes.
struct TorchButton: View {
    @StateObject private var torch = Torch()

    var body: some View {
        if Torch.isAvailable {
            Button { torch.toggle(); Haptics.tap() } label: {
                Image(systemName: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(torch.isOn ? Theme.orange : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(torch.isOn ? "Выключить фонарик" : "Включить фонарик")
            .onDisappear { torch.set(false) }
        }
    }
}
