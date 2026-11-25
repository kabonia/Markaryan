import SwiftUI
import ARKit
import RealityKit

/// «Дом снаружи» → «Скан дома»: обход с подсказками и кольцом покрытия, запись кадров, глубины и поз ARKit,
/// упаковка и загрузка на сервер. Обработка в макет — на GPU (этап 1b), сюда придёт статус.
struct HouseScanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = HouseScanRecorder()
    @State private var phase: Phase = .intro
    @State private var controlText = ""
    @State private var uploadShare = 0.0
    @State private var uploadText = ""
    @State private var resultText: String?
    @State private var error: String?
    @State private var pending: [HouseScanStore.Pending] = []
    @State private var confirmCancel = false
    @State private var showParcel = false

    enum Phase { case intro, scanning, control, uploading, sent }

    /// «Готово» без предупреждения — от 60 % покрытия.
    private var enoughCoverage: Bool { recorder.coverage.total >= 0.6 }

    var body: some View {
        content
            .preferredColorScheme(colorScheme)
            .onAppear { pending = HouseScanStore.pending() }
            .onChange(of: phase) { _, value in phaseChanged(value) }
            .onDisappear { closed() }
            .confirmationDialog("Прервать скан? Снятые кадры удалятся.", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Прервать", role: .destructive) { abandon() }
                Button("Продолжить снимать", role: .cancel) {}
            }
    }

    private var showsCamera: Bool { phase == .scanning || phase == .control }
    private var colorScheme: ColorScheme { phase == .scanning ? .dark : .light }

    private var content: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if showsCamera {
                HouseARContainer(recorder: recorder).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                header
                phaseView
            }
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch phase {
        case .intro: intro
        case .scanning: scanningOverlay
        case .control: controlStep
        case .uploading: uploading
        case .sent: sent
        }
    }

    private func phaseChanged(_ value: Phase) {
        let busy: Bool = value == .scanning || value == .uploading
        UIApplication.shared.isIdleTimerDisabled = busy
    }

    private func abandon() {
        recorder.discard()
        dismiss()
    }

    private func closed() {
        UIApplication.shared.isIdleTimerDisabled = false
        // Скан, который не дошёл до сохранения (закрыли до отправки), не оставляет файлов.
        let saved: Bool = HouseScanStore.state(of: recorder.folder) != nil
        if !saved { recorder.discard() }
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline).tracking(2)
            Spacer()
            if phase == .scanning { TorchButton() }
            Button {
                if phase == .scanning && recorder.frameCount > 0 { confirmCancel = true } else { dismiss() }
            } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }
                .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private var title: String {
        switch phase {
        case .intro: return "ДОМ СНАРУЖИ"
        case .scanning: return "ОБХОД ДОМА"
        case .control: return "КОНТРОЛЬНЫЙ РАЗМЕР"
        case .uploading: return "ОТПРАВКА"
        case .sent: return "СКАН ОТПРАВЛЕН"
        }
    }

    // MARK: Интро

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "house.lodge").font(.system(size: 50, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 96, height: 96).background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.goldLight.opacity(0.5), lineWidth: 1))
                Text("Скан дома").font(.system(.largeTitle, design: .serif, weight: .bold)).tracking(-0.5)
                Text("Обойдите дом с iPhone — получите точный 3D‑макет дома с размерами стен, окон и крыши. Потом в нём можно менять крышу, фасад и окна и сразу видеть смету.")
                    .foregroundStyle(Theme.muted)
                accuracyNote
                VStack(alignment: .leading, spacing: 10) {
                    Label("Днём, лучше в пасмурную погоду — без резких теней", systemImage: "sun.haze")
                    Label("Обойдите дом по кругу в 4–8 м от стен", systemImage: "figure.walk.circle")
                    Label("Второй круг — дальше, с поднятой камерой: крыша и фронтоны", systemImage: "house")
                    Label("Идите медленно, 5–10 минут. Кольцо вверху покажет, что осталось", systemImage: "circle.dashed")
                }
                .font(.subheadline)
                parcelCard
                if HouseScanRecorder.isSupported {
                    PrimaryButton(title: "Начать обход", icon: "viewfinder") {
                        error = nil
                        recorder.parcel = ParcelStore.load()
                        recorder.start()
                        phase = .scanning
                        store.track("house_scan_start")
                    }
                } else {
                    InfoNote(text: "На этом устройстве нет AR‑камеры. Скан дома работает на iPhone XS и новее.")
                }
                if !pending.isEmpty { pendingList }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
            }
            .padding(24)
        }
    }

    /// Участок по кадастру — до скана: макет сразу встанет на свою границу.
    private var parcelCard: some View {
        Button { showParcel = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "map").font(.title3).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text(parcelTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("Граница, площадь, ВРИ из Росреестра и проверка отступов").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .padding(16).panelCard(16)
        }
        .buttonStyle(PremiumCardPressStyle())
        .sheet(isPresented: $showParcel) { ParcelView() }
    }

    private var parcelTitle: String {
        guard let parcel = ParcelStore.load() else { return "Участок по кадастру" }
        return "Участок \(parcel.cadNumber)"
    }

    private var accuracyNote: some View {
        let lidar = HouseScanRecorder.hasLiDAR
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: lidar ? "scope" : "ruler").font(.title3).foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 4) {
                Text(lidar ? "Есть лидар: точность до сантиметров" : "Без лидара: точность ±2–5 %").font(.subheadline.weight(.semibold))
                Text(lidar ? "Стены и проёмы измеряются лидаром, крыша — по фото и геометрии стен."
                           : "После обхода измерьте рулеткой одну стену — макет подгонится под этот размер.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("НЕОТПРАВЛЕННЫЕ И В ОБРАБОТКЕ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            ForEach(pending) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.state.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                        Text(statusText(item.state)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if item.state.status == "local" || item.state.status == "uploading" {
                        Button("Отправить") { Task { await upload(folder: item.folder, frames: item.state.frames) } }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(14).panelCard(14)
            }
        }
    }

    private func statusText(_ state: HouseScanStore.State) -> String {
        switch state.status {
        case "local": return "\(state.frames) кадров · не отправлен"
        case "uploading": return "Загрузка прервалась — продолжим с того же места"
        case "queued": return "Ждёт обработки на GPU"
        case "processing": return "Собираем макет…"
        case "failed": return state.message ?? "Ошибка обработки"
        default: return state.message ?? state.status
        }
    }

    // MARK: Обход

    private var scanningOverlay: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                CoverageRing(coverage: recorder.coverage).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Label(recorder.hint.text, systemImage: recorder.hint.icon)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .animation(.easeInOut(duration: 0.2), value: recorder.hint)
                    Text("Стены \(Int(recorder.coverage.wallShare * 100)) % · крыша \(Int(recorder.coverage.roofShare * 100)) %")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text("\(recorder.frameCount) кадров · \(HouseScanUploader.mb(recorder.bytesWritten))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(14).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12).padding(.top, 10)
            Spacer()
            HStack(spacing: 10) {
                Button { recorder.recording ? recorder.pause() : recorder.start() } label: {
                    Label(recorder.recording ? "Пауза" : "Дальше", systemImage: recorder.recording ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).background(.ultraThinMaterial, in: Capsule())
                }
                Button { finishScan() } label: {
                    Label("Готово", systemImage: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(doneFill, in: Capsule())
                }
                .disabled(recorder.frameCount < 10)
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
            if !enoughCoverage && recorder.frameCount >= 10 {
                Text("Снято меньше 60 % — макет будет неполным").font(.caption).foregroundStyle(.white.opacity(0.85)).padding(.bottom, 12)
            }
        }
    }

    private var doneFill: Color { enoughCoverage ? Theme.orange : Theme.orange.opacity(0.45) }

    private var controlHint: String {
        HouseScanRecorder.hasLiDAR
            ? "Длина любой стены дома по низу, в метрах. Это проверит масштаб макета."
            : "Длина любой стены дома по низу, в метрах. Это проверит масштаб макета и подгонит его."
    }

    private func finishScan() {
        recorder.pause()
        Haptics.success()
        store.track("house_scan_finish")
        phase = .control
    }

    // MARK: Контрольный размер

    private var controlStep: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(HouseScanRecorder.hasLiDAR ? "Контрольный размер (по желанию)" : "Измерьте рулеткой одну стену")
                    .font(.headline)
                Text(controlHint)
                    .font(.footnote).foregroundStyle(Theme.muted)
                TextField("Например, 9,42", text: $controlText)
                    .keyboardType(.decimalPad).padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                PrimaryButton(title: "Отправить на обработку", icon: "icloud.and.arrow.up") { Task { await sendScan() } }
                if HouseScanRecorder.hasLiDAR {
                    Button("Без размера") { controlText = ""; Task { await sendScan() } }.font(.subheadline).frame(maxWidth: .infinity)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
            }
            .padding(20).background(Theme.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).padding(12)
        }
    }

    private func sendScan() async {
        error = nil
        let meters = Double(controlText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        if !HouseScanRecorder.hasLiDAR && !(meters.map { $0 > 0.5 && $0 < 100 } ?? false) {
            error = "Введите длину стены в метрах — без неё размеры будут неточными."
            return
        }
        let control = meters.flatMap { $0 > 0.5 && $0 < 100 ? [HouseScanManifest.Control(kind: "wall_length", meters: $0, note: "рулетка")] : nil } ?? []
        do {
            let folder = try await recorder.finish(control: control)
            var state = HouseScanStore.State(frames: recorder.frameCount, bytes: recorder.bytesWritten)
            state.status = "local"
            HouseScanStore.save(state, in: folder)
            await upload(folder: folder, frames: recorder.frameCount)
        } catch {
            self.error = "Не удалось сохранить скан: \(error.localizedDescription)"
        }
    }

    // MARK: Загрузка

    private func upload(folder: URL, frames: Int) async {
        guard let uploader = HouseScanUploader() else {
            error = "Сервер ИИ не настроен — скан сохранён в телефоне, отправим позже."
            phase = .intro; pending = HouseScanStore.pending()
            return
        }
        phase = .uploading
        uploadShare = 0
        uploadText = "Готовим скан…"
        do {
            let remote = try await uploader.upload(folder: folder, frames: frames, lidar: HouseScanRecorder.hasLiDAR) { share, text in
                uploadShare = share; uploadText = text
            }
            resultText = remote.message
            store.track("house_scan_uploaded")
            Haptics.success()
            phase = .sent
        } catch {
            self.error = "Загрузка прервалась: \(error.localizedDescription). Скан сохранён — нажмите «Отправить», когда будет связь."
            pending = HouseScanStore.pending()
            phase = .intro
        }
    }

    private var uploading: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: uploadShare).tint(Theme.orange).padding(.horizontal, 40)
            Text(uploadText).font(.subheadline.monospacedDigit())
            Text("Не закрывайте приложение до конца загрузки. Если связь пропадёт — продолжим с того же места.")
                .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
        }
    }

    private var sent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.success)
            Text("Скан на обработке").font(.system(.title, design: .serif, weight: .bold))
            Text(resultText ?? "Макет будет готов через 15–30 минут — пришлём уведомление.").foregroundStyle(Theme.muted)
            PrimaryButton(title: "Готово", icon: "checkmark") { dismiss() }
            Spacer()
        }
        .padding(24)
    }
}

/// Кольцо покрытия: внешнее кольцо — стены, внутреннее — крыша; белая риска — где вы сейчас.
struct CoverageRing: View {
    let coverage: HouseCoverage

    var body: some View {
        Canvas { canvas, size in
            let context = canvas
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let n = HouseCoverage.sectors
            let step = 2 * Double.pi / Double(n)
            func ring(_ values: [Int], outer: CGFloat, width: CGFloat, color: Color) {
                for i in 0..<n {
                    let start = Angle(radians: Double(i) * step + 0.03)
                    let end = Angle(radians: Double(i + 1) * step - 0.03)
                    var path = Path()
                    path.addArc(center: center, radius: outer - width / 2, startAngle: start, endAngle: end, clockwise: false)
                    context.stroke(path, with: .color(values[i] > 0 ? color : .white.opacity(0.18)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                }
            }
            ring(coverage.walls, outer: radius, width: radius * 0.22, color: Theme.orangeSoft)
            ring(coverage.roof, outer: radius * 0.74, width: radius * 0.16, color: Theme.goldLight)
            if let current = coverage.current {
                let angle = (Double(current) + 0.5) * step
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.5, y: center.y + sin(angle) * radius * 0.5))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 1.02, y: center.y + sin(angle) * radius * 1.02))
                context.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .overlay {
            Text("\(Int(coverage.total * 100))%").font(.system(.headline, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .accessibilityElement()
        .accessibilityLabel("Снято \(Int(coverage.total * 100)) процентов")
    }
}

/// Камера ARKit; с лидаром поверх видна растущая сетка — сразу понятно, что уже снято.
struct HouseARContainer: UIViewRepresentable {
    let recorder: HouseScanRecorder

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion, .disableHDR]
        if HouseScanRecorder.hasLiDAR { view.debugOptions.insert(.showSceneUnderstanding) }
        view.session.delegate = recorder
        recorder.session = view.session
        view.session.run(HouseScanRecorder.configuration(), options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}

    static func dismantleUIView(_ view: ARView, coordinator: ()) { view.session.pause() }
}
