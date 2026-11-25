import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

/// «Мои сканы дома»: статус обработки каждого скана на сервере; готовый — открывается макетом.
struct HouseScansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [HouseScanUploader.Remote] = []
    @State private var error: String?
    @State private var loaded = false
    /// Сканы, которые были в обработке при прошлом опросе: стали готовы — сообщаем.
    @State private var waiting: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !loaded { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                    if loaded && scans.isEmpty {
                        InfoNote(text: "Обмеров пока нет. Обойдите дом в разделе «3D‑обмер дома» — макет появится здесь через пару минут.")
                    }
                    ForEach(scans) { scan in
                        if scan.status == "ready", scan.result != nil {
                            NavigationLink { HouseResultView(scan: scan) } label: { HouseScanRow(scan: scan) }
                                .buttonStyle(PremiumCardPressStyle())
                        } else {
                            HouseScanRow(scan: scan)
                        }
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Мои обмеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .refreshable { await refresh() }
            .task {
                BackgroundAI.askForNotificationsOnce()
                // Пока экран открыт — обновляем каждые 10 с, если что-то в обработке.
                while !Task.isCancelled {
                    await refresh()
                    let busy = scans.contains { $0.status == "queued" || $0.status == "processing" }
                    try? await Task.sleep(for: .seconds(busy ? 10 : 60))
                }
            }
        }
    }

    private func refresh() async {
        guard let uploader = HouseScanUploader() else { error = "Сервер не настроен."; loaded = true; return }
        do {
            let fresh = try await uploader.list()
            for scan in fresh where waiting.contains(scan.id) && scan.status == "ready" {
                Haptics.success()
                BackgroundAI.notify(title: "Макет дома готов", body: "Откройте «Мои обмеры», чтобы посмотреть размеры и 3D‑модель.")
            }
            waiting = Set(fresh.filter { $0.status == "queued" || $0.status == "processing" }.map(\.id))
            scans = fresh
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

struct HouseScanRow: View {
    let scan: HouseScanUploader.Remote

    private var date: String {
        guard let raw = scan.createdAt, let date = ISO8601DateFormatter.withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "Скан" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var statusText: String {
        switch scan.status {
        case "uploading": return "Загрузка не закончена — откройте «3D‑обмер дома» и нажмите «Отправить»"
        case "queued": return scan.queuePosition.map { $0 > 1 ? "В очереди: \($0)-й" : "Скоро начнём" } ?? "В очереди"
        case "processing": return scan.message ?? "Обрабатываем…"
        case "ready":
            if let w = scan.result?.footprint?.gableWidth?.value, let l = scan.result?.footprint?.length?.value {
                return "Готово · \(ParcelRules.format(w, digits: 2)) × \(ParcelRules.format(l, digits: 2)) м"
            }
            return "Готово"
        case "failed": return scan.message ?? "Не получилось"
        default: return scan.message ?? scan.status
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: scan.status == "ready" ? "house.lodge.fill" : scan.status == "failed" ? "exclamationmark.triangle" : "hourglass")
                .font(.title3).foregroundStyle(scan.status == "failed" ? Theme.danger : Theme.gold).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(date).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(statusText).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                if scan.status == "processing", let p = scan.progress { ProgressView(value: p).tint(Theme.orange) }
            }
            Spacer(minLength: 0)
            if scan.status == "ready" { Image(systemName: "chevron.right").foregroundStyle(Theme.muted) }
        }
        .padding(16).panelCard(16)
    }
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Макет дома: 3D‑модель, размеры с метками достоверности, крыша, площади для сметы, проверка по участку.
struct HouseResultView: View {
    let scan: HouseScanUploader.Remote
    @State private var modelURL: URL?
    @State private var modelError: String?

    private var result: HouseResult { scan.result ?? HouseResult() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                model
                dimensions
                roof
                openings
                areas
                parcel
                quality
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Макет дома")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadModel() }
    }

    // MARK: 3D

    private var model: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.13, green: 0.17, blue: 0.16))
            if let modelURL {
                HouseModelView(url: modelURL).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let modelError {
                Text(modelError).font(.footnote).foregroundStyle(.white.opacity(0.8)).padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(height: 300)
        .overlay(alignment: .bottomLeading) {
            Text("Крутите пальцем, щипок — масштаб").font(.caption2).foregroundStyle(.white.opacity(0.7)).padding(10)
        }
    }

    private func loadModel() async {
        guard scan.hasModel, let uploader = HouseScanUploader() else { modelError = "3D‑модели нет — только размеры."; return }
        do { modelURL = try await uploader.model(scan.id) } catch { modelError = error.localizedDescription }
    }

    // MARK: Размеры

    private var dimensions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("РАЗМЕРЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            MeasureRow(title: "Ширина торца", measure: result.footprint?.gableWidth, unit: "м")
            MeasureRow(title: "Длина дома", measure: result.footprint?.length, unit: "м")
            MeasureRow(title: "Высота до карниза", measure: result.eaveHeight, unit: "м")
            MeasureRow(title: "Высота конька", measure: result.roof?.ridgeHeight, unit: "м")
            if result.hasOverhangs {
                MeasureRow(title: "Свес по карнизу", measure: result.roof?.overhangEave, unit: "м")
                MeasureRow(title: "Свес по фронтону", measure: result.roof?.overhangGable, unit: "м")
            }
            if let control = result.control, let tape = control.tape, let delta = control.deltaCm {
                HStack {
                    Image(systemName: abs(delta) <= 3 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(abs(delta) <= 3 ? Theme.success : Theme.gold)
                    Text("Рулетка \(ParcelRules.format(tape, digits: 2)) м — макет \(delta >= 0 ? "+" : "")\(ParcelRules.format(delta, digits: 1)) см")
                        .font(.footnote)
                }
            }
            if let side = result.blockedSide, let tape = side.tape, let delta = side.deltaCm {
                HStack {
                    Image(systemName: abs(delta) <= 5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(abs(delta) <= 5 ? Theme.success : Theme.gold)
                    Text("Недоступная сторона: введено \(ParcelRules.format(tape, digits: 2)) м — достроено \(delta >= 0 ? "+" : "")\(ParcelRules.format(delta, digits: 1)) см")
                        .font(.footnote)
                }
            }
            HStack(spacing: 14) {
                Legend(color: Theme.success, text: "измерено")
                Legend(color: Theme.gold, text: "по фото")
                Legend(color: Theme.muted, text: "предположение")
            }
            .padding(.top, 2)
        }
        .padding(16).panelCard(16)
    }

    // MARK: Крыша

    private var roof: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("КРЫША").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text(result.roofTitle).font(.system(.title3, design: .serif, weight: .bold))
            MeasureRow(title: "Уклон", measure: result.roof?.pitchDeg, unit: "°", digits: 1)
            if let left = result.roof?.pitchLeftDeg, let right = result.roof?.pitchRightDeg, result.roof?.symmetric == false {
                Text("Скаты разные: \(ParcelRules.format(left, digits: 1))° и \(ParcelRules.format(right, digits: 1))°").font(.footnote).foregroundStyle(Theme.muted)
            }
            if let photo = result.roof?.byPhoto {
                if let covering = photo.covering, !covering.isEmpty { infoLine("Покрытие", covering) }
                if let color = photo.color, !color.isEmpty { infoLine("Цвет", color) }
                let details = (photo.details ?? []).compactMap { d -> String? in
                    guard let ru = d.ru, !ru.isEmpty else { return nil }
                    let count = (d.count ?? 0) > 1 ? " ×\(Int(d.count ?? 0))" : ""
                    return d.seen == false ? "\(ru)\(count) (предположение)" : "\(ru)\(count)"
                }
                if !details.isEmpty { infoLine("Детали", details.joined(separator: ", ")) }
                if let hidden = photo.hidden, !hidden.isEmpty { infoLine("Не видно", hidden.joined(separator: "; ")) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    // MARK: Окна и двери

    @ViewBuilder private var openings: some View {
        let list = result.openings ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ОКНА И ДВЕРИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                if let s = result.openingsSummary {
                    Text("Окон: \(s.windows ?? 0) · дверей: \(s.doors ?? 0) · площадь проёмов \(ParcelRules.format(s.area ?? 0, digits: 1)) м²")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(list) { o in
                    HStack {
                        Circle().fill(o.source == "photo" ? Theme.gold : Theme.muted).frame(width: 8, height: 8)
                        Text(o.title).font(.footnote)
                        Spacer()
                        Text("\(ParcelRules.format(o.width ?? 0, digits: 2)) × \(ParcelRules.format(o.height ?? 0, digits: 2)) м")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                        if let sill = o.sill, sill > 0.15 {
                            Text("низ \(ParcelRules.format(sill, digits: 2))").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text("Размеры — по фото и стенам, снятым лидаром (±2–3 см). Окно, отмеченное на одном фото, — с серой меткой: проверьте рулеткой.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
        }
    }

    // MARK: Площади для сметы

    private var areas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПЛОЩАДИ ДЛЯ СМЕТЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            if let a = result.footprintArea { infoLine("Пятно застройки", "\(ParcelRules.format(a, digits: 1)) м²") }
            if let a = result.roofArea { infoLine(result.hasOverhangs ? "Кровля (со свесами)" : "Кровля (без свесов)", "\(ParcelRules.format(a, digits: 1)) м²") }
            if let a = result.facadeArea { infoLine("Фасады всего", "\(ParcelRules.format(a, digits: 1)) м²") }
            if !(result.openings ?? []).isEmpty, let a = result.facadeNetArea { infoLine("Фасады без окон и дверей", "\(ParcelRules.format(a, digits: 1)) м²") }
            if let g = result.gutterLength { infoLine("Водосточный жёлоб", "\(ParcelRules.format(g, digits: 1)) м") }
            if let facade = result.roof?.byPhoto?.facade, !facade.isEmpty { infoLine("Стены сейчас", facade) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    // MARK: Участок

    @ViewBuilder private var parcel: some View {
        if let stored = ParcelStore.load(), let building = result.siteBuilding(parcel: stored) {
            VStack(alignment: .leading, spacing: 10) {
                Text("УЧАСТОК \(stored.cadNumber)").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(ParcelRules.check(parcel: stored, buildings: [building])) { FindingRow(finding: $0) }
                Text("Предварительно: дом поставлен на карту по GPS и компасу (±5–15 м). Точная привязка — по двум углам участка, на этапе «Участок».")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let q = result.quality {
                Text("Кадров с лидаром: \(q.framesWithDepth ?? 0) из \(q.frames ?? 0); смазанных отброшено: \(q.rejectedBlurry ?? 0); обработка \(Int(q.seconds ?? 0)) с.")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.footnote).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).font(.footnote.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}

struct MeasureRow: View {
    let title: String
    let measure: HouseMeasure?
    let unit: String
    var digits = 2

    private var color: Color {
        switch measure?.trust ?? 2 {
        case 0: return Theme.success
        case 1: return Theme.gold
        default: return Theme.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.subheadline)
                Spacer()
                if let value = measure?.value {
                    Text("\(ParcelRules.format(value, digits: digits)) \(unit)").font(.subheadline.weight(.semibold).monospacedDigit())
                    if let sigma = measure?.sigma, unit == "м" {
                        Text("±\(ParcelRules.format(sigma * 100, digits: 0)) см").font(.caption2).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("—").foregroundStyle(Theme.muted)
                }
            }
            if let measure, measure.value != nil {
                Text(measure.note.map { "\(measure.sourceTitle): \($0)" } ?? measure.sourceTitle).font(.caption2).foregroundStyle(Theme.muted).padding(.leading, 16)
            }
        }
    }
}

struct Legend: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(text).font(.caption2).foregroundStyle(Theme.muted) }
    }
}

/// 3D‑модель дома (OBJ из обработчика) в SceneKit: вращение и масштаб пальцами.
struct HouseModelView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.13, green: 0.17, blue: 0.16, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        let (scene, camera) = Self.scene(from: url)
        view.scene = scene
        view.pointOfView = camera
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func scene(from url: URL) -> (SCNScene, SCNNode) {
        let asset = MDLAsset(url: url)
        let scene = SCNScene(mdlAsset: asset)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.90, green: 0.87, blue: 0.80, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.85
        material.isDoubleSided = true
        scene.rootNode.enumerateChildNodes { node, _ in node.geometry?.materials = [material] }
        // Камера — по габаритам модели, сбоку и сверху (ARKit: y — вверх).
        let (low, high) = scene.rootNode.boundingBox
        let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        let size = max(high.x - low.x, high.z - low.z, high.y - low.y, 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = Double(size * 20)
        camera.position = SCNVector3(center.x + size * 0.9, center.y + size * 0.7, center.z + size * 0.9)
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)
        return (scene, camera)
    }
}
