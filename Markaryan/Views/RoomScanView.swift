import SwiftUI
#if canImport(RoomPlan)
import RoomPlan
#endif

/// LiDAR room scan (Apple RoomPlan): walls, doors, windows and furniture → 2D plan + 3D model.
/// iPhones without LiDAR are offered the AR floor contour instead.
struct RoomScanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .intro
    @State private var stopRequested = false
    @State private var name = ""
    @State private var error: String?

    enum Phase { case intro, scanning, processing }

    private var isSupported: Bool {
        #if canImport(RoomPlan)
        return RoomCaptureSession.isSupported
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            #if canImport(RoomPlan)
            if phase != .intro && isSupported {
                RoomCaptureRepresentable(stopRequested: stopRequested) { room, captureError in
                    handle(room: room, error: captureError)
                }
                .ignoresSafeArea()
            }
            #endif
            VStack {
                HStack {
                    Text(phase == .intro ? "СКАН КОМНАТЫ" : "СКАНИРОВАНИЕ").font(.headline).tracking(2)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Закрыть")
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer()
                switch phase {
                case .intro: intro
                case .scanning:
                    VStack(spacing: 12) {
                        Text("Медленно обходите комнату, наводя камеру на стены, углы, окна и двери. Модель строится на экране.").font(.footnote).multilineTextAlignment(.center)
                        PrimaryButton(title: "Готово — построить план", icon: "checkmark") { stopRequested = true; phase = .processing; Haptics.success() }
                    }
                    .padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(12)
                case .processing:
                    HStack(spacing: 12) { ProgressView(); Text("Собираем стены, проёмы и мебель…").font(.subheadline) }
                        .padding(18).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 30)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 20) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "cube.transparent").font(.system(size: 52, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 96, height: 96).background(Theme.orange, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Text("Планировка за минуту").font(.system(.largeTitle, weight: .bold)).tracking(-1)
                Text("iPhone сканирует комнату лидаром: стены, окна, двери и мебель. Получите точный план сверху с размерами, 3D‑модель и дизайн‑проект от ИИ прямо по этой планировке.").foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Включите свет и откройте двери", systemImage: "lightbulb")
                    Label("Держите iPhone на уровне груди", systemImage: "iphone")
                    Label("Обойдите комнату по периметру за 1–2 минуты", systemImage: "figure.walk")
                }
                .font(.subheadline)
                if isSupported {
                    PrimaryButton(title: "Начать сканирование", icon: "viewfinder") { stopRequested = false; error = nil; phase = .scanning; store.track("room_scan_start") }
                } else {
                    InfoNote(text: "Для скана нужен iPhone с лидаром (модели Pro начиная с iPhone 12 Pro). На этом iPhone постройте план по углам пола: AR‑студия → «Площадь» → обойдите углы → «Сохранить как план».")
                    PrimaryButton(title: "Открыть контур в AR", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                        dismiss()
                        Task { try? await Task.sleep(for: .milliseconds(500)); store.showAR = true }
                    }
                }
            }
            .padding(24)
        }
    }

    #if canImport(RoomPlan)
    private func handle(room: CapturedRoom?, error captureError: Error?) {
        guard let room, captureError == nil else {
            error = "Скан не удался: \(captureError?.localizedDescription ?? "нет данных"). Попробуйте ещё раз при лучшем освещении."
            phase = .intro
            return
        }
        let id = UUID()
        var modelName: String? = "room-\(id.uuidString).usdz"
        do {
            let url = try AppStore.planModelFolder().appendingPathComponent(modelName!)
            try room.export(to: url, exportOptions: .parametric)
        } catch { modelName = nil }
        let count = store.floorPlans.count + 1
        var plan = FloorPlanBuilder.fromRoom(room, name: "Комната \(count)", modelFilename: modelName)
        plan.id = id
        guard !plan.walls.isEmpty else {
            error = "Не удалось распознать стены. Обойдите комнату медленнее, захватывая углы."
            phase = .intro
            return
        }
        store.savePlan(plan)
        store.track("room_scan_saved")
        Haptics.success()
        dismiss()
        Task { try? await Task.sleep(for: .milliseconds(450)); store.planToOpen = plan.id }
    }
    #endif
}

#if canImport(RoomPlan)
/// Wraps Apple's RoomCaptureView (live scan UI with the growing 3D model).
struct RoomCaptureRepresentable: UIViewRepresentable {
    let stopRequested: Bool
    let onResult: (CapturedRoom?, Error?) -> Void

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator() }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        context.coordinator.onResult = onResult
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        context.coordinator.onResult = onResult
        if stopRequested && !context.coordinator.stopped {
            context.coordinator.stopped = true
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomScanCoordinator) {
        if !coordinator.stopped { view.captureSession.stop() }
    }
}

final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate {
    var onResult: ((CapturedRoom?, Error?) -> Void)?
    var stopped = false

    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let callback = onResult
        DispatchQueue.main.async { callback?(processedResult, error) }
    }
}
#endif
