import SwiftUI
#if canImport(RoomPlan)
import RoomPlan
#endif

/// What the scan should do next; a new `token` makes the capture view act once.
struct ScanCommand: Equatable {
    enum Action: Equatable {
        case run
        /// `keepSession`: the AR session goes on, so the next room is scanned in the same coordinates.
        case stop(keepSession: Bool)
    }
    var action: Action
    var token: Int
}

/// LiDAR room scan (Apple RoomPlan): walls, doors, windows and furniture → 2D plan + 3D model.
/// Several rooms in one go make an apartment: the AR session keeps running between rooms, so they share the
/// scan's coordinates and stand in their places on the apartment plan. iPhones without LiDAR get the AR contour.
struct RoomScanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .intro
    @State private var command = ScanCommand(action: .run, token: 0)
    @State private var error: String?
    /// Set when the user goes on to a next room: every room of this scan shares it.
    @State private var apartmentID: UUID?
    @State private var apartmentName = ""
    /// Rooms saved in this scan, in order.
    @State private var saved: [FloorPlan.ID] = []
    /// The room being processed is followed by another one.
    @State private var continuing = false

    enum Phase { case intro, scanning, processing, between }

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
                RoomCaptureRepresentable(command: command) { room, captureError in
                    handle(room: room, error: captureError)
                }
                .ignoresSafeArea()
            }
            #endif
            VStack {
                HStack {
                    Text(title.tr).font(.headline).tracking(2)
                    Spacer()
                    if phase == .scanning { TorchButton() }
                    // Closing after some rooms keeps them and opens what was scanned.
                    Button { if saved.isEmpty { dismiss() } else { finish() } } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Закрыть")
                }
                .padding(.horizontal, 20).padding(.top, 12)
                // While scanning, the controls stay at the top: the bottom of the screen shows the growing 3D model.
                if phase == .scanning {
                    VStack(spacing: 10) {
                        Text("Медленно обходите помещение, наводя камеру на стены, углы, окна и двери.").font(.footnote).multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            Button { finishRoom(next: false) } label: {
                                Label("Готово", systemImage: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onAccent)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.orange, in: Capsule())
                            }
                            Button { finishRoom(next: true) } label: {
                                Label("Следующая комната", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.accentTint, in: Capsule())
                            }
                        }
                    }
                    .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(.horizontal, 12)
                }
                Spacer()
                switch phase {
                case .intro: intro
                case .scanning:
                    EmptyView()
                case .processing:
                    HStack(spacing: 12) { ProgressView(); Text("Собираем стены, проёмы и мебель…").font(.subheadline) }
                        .padding(18).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 30)
                case .between:
                    VStack(spacing: 12) {
                        Text("Комната \(saved.count) сохранена. Перейдите в следующую комнату, не закрывая скан, — комнаты встанут на свои места на общем плане.")
                            .font(.footnote).multilineTextAlignment(.center)
                        PrimaryButton(title: "Сканировать комнату \(saved.count + 1)", icon: "viewfinder") { nextRoom() }
                        Button { finish() } label: { SecondaryActionLabel(title: "Закончить и открыть квартиру", icon: "checkmark") }
                            .buttonStyle(PremiumPressStyle())
                    }
                    .padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(12)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 20) }
            }
        }
        .preferredColorScheme(.light)
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "cube.transparent").font(.system(size: 52, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 96, height: 96).background(Theme.orange, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Text("Планировка за минуту").font(.system(.largeTitle, weight: .bold)).tracking(-1)
                Text("iPhone сканирует комнату лидаром: стены, окна, двери и мебель. Получите точный план сверху с размерами, 3D‑модель и дизайн‑проект от ИИ прямо по этой планировке.").foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Включите свет и откройте двери", systemImage: "lightbulb")
                    Label("Держите iPhone на уровне груди", systemImage: "iphone")
                    Label("Обойдите комнату по периметру за 1–2 минуты", systemImage: "figure.walk")
                    Label("Квартира целиком: после комнаты нажмите «Следующая комната» и идите дальше", systemImage: "square.split.2x2")
                }
                .font(.subheadline)
                if isSupported {
                    PrimaryButton(title: "Начать сканирование", icon: "viewfinder") {
                        error = nil
                        command = ScanCommand(action: .run, token: command.token + 1)
                        phase = .scanning
                        store.track("room_scan_start")
                    }
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

    private var title: String {
        switch phase {
        case .intro: return "СКАН КОМНАТЫ"
        case .between: return apartmentName.uppercased()
        case .scanning, .processing: return apartmentID == nil ? "СКАНИРОВАНИЕ" : "КОМНАТА \(saved.count + 1)"
        }
    }

    /// Stops the scan of this room; `next` keeps the AR session for the next room of the apartment.
    private func finishRoom(next: Bool) {
        if next && apartmentID == nil {
            apartmentID = UUID()
            apartmentName = "Квартира \(store.apartments.count + 1)"
        }
        continuing = next
        command = ScanCommand(action: .stop(keepSession: next), token: command.token + 1)
        phase = .processing
        Haptics.success()
    }

    private func nextRoom() {
        error = nil
        command = ScanCommand(action: .run, token: command.token + 1)
        phase = .scanning
        store.track("room_scan_next")
    }

    /// Opens what was scanned: the apartment, or the room when there is only one.
    private func finish() {
        if let apartmentID, saved.count < 2 { store.ungroupApartment(apartmentID) }
        let apartment = saved.count >= 2 ? apartmentID : nil
        let room = saved.first
        Haptics.success()
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if let apartment { store.apartmentToOpen = apartment } else if let room { store.planToOpen = room }
        }
    }

    #if canImport(RoomPlan)
    private func handle(room: CapturedRoom?, error captureError: Error?) {
        guard let room, captureError == nil else {
            error = "Скан не удался: \(captureError?.localizedDescription ?? "нет данных"). Попробуйте ещё раз при лучшем освещении."
            failed()
            return
        }
        let id = UUID()
        var modelName: String? = "room-\(id.uuidString).usdz"
        do {
            let url = try AppStore.planModelFolder().appendingPathComponent(modelName!)
            try room.export(to: url, exportOptions: .parametric)
        } catch { modelName = nil }
        let number = apartmentID == nil ? store.floorPlans.count + 1 : saved.count + 1
        var plan = FloorPlanBuilder.fromRoom(room, name: "Комната \(number)", modelFilename: modelName)
        plan.id = id
        plan.apartmentID = apartmentID
        plan.apartmentName = apartmentID == nil ? nil : apartmentName
        guard !plan.walls.isEmpty else {
            error = "Не удалось распознать стены. Обойдите комнату медленнее, захватывая углы."
            failed()
            return
        }
        store.savePlan(plan)
        saved.append(plan.id)
        store.track(apartmentID == nil ? "room_scan_saved" : "apartment_room_saved")
        Haptics.success()
        if continuing { phase = .between } else { finish() }
    }

    /// A room that did not work: scan it again in the same session, or start over when nothing is saved yet.
    private func failed() {
        if saved.isEmpty { phase = .intro }
        else if continuing { phase = .between }
        else { finish() }
    }
    #endif
}

#if canImport(RoomPlan)
/// Wraps Apple's RoomCaptureView (live scan UI with the growing 3D model).
struct RoomCaptureRepresentable: UIViewRepresentable {
    let command: ScanCommand
    let onResult: (CapturedRoom?, Error?) -> Void

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator() }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        context.coordinator.onResult = onResult
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.token = command.token
        context.coordinator.stopped = false
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        context.coordinator.onResult = onResult
        guard command.token != context.coordinator.token else { return }
        context.coordinator.token = command.token
        switch command.action {
        case .run:
            context.coordinator.stopped = false
            view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        case .stop(let keepSession):
            guard !context.coordinator.stopped else { return }
            context.coordinator.stopped = true
            // Keeping the AR session puts the next room in the same coordinates (RoomPlan, iOS 17).
            view.captureSession.stop(pauseARSession: !keepSession)
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomScanCoordinator) {
        if !coordinator.stopped { view.captureSession.stop() }
    }
}

final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate {
    var onResult: ((CapturedRoom?, Error?) -> Void)?
    var stopped = false
    /// The last command acted on.
    var token = 0

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
