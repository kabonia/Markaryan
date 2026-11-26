import SwiftUI
import SceneKit

/// Снимок 3D‑модели дома с текущего ракурса — основа для визуализации.
final class SceneSnapshotter {
    weak var view: SCNView?
    func image() -> UIImage? { view?.snapshot() }
}

extension HouseParams {
    /// Смета по размерам обмера: длина, ширина, этажность по высоте карниза, крыша и покрытие с фото.
    static func from(_ result: HouseResult) -> HouseParams {
        var p = HouseParams()
        if let length = result.footprint?.length?.value, let width = result.footprint?.gableWidth?.value {
            p.length = max(length, width).rounded(toPlaces: 1)
            p.width = min(length, width).rounded(toPlaces: 1)
        }
        if let eave = result.eaveHeight?.value { p.floors = min(3, max(1, Int((eave / 2.9).rounded()))) }
        switch result.roof?.type {
        case "hip": p.roof = "hip"
        case "flat": p.roof = "flat"
        default: p.roof = "gable"
        }
        if let pitch = result.roof?.pitchDeg?.value { p.pitch = min(45, max(15, (pitch / 5).rounded() * 5)) }
        let covering = (result.roof?.byPhoto?.covering ?? "").lowercased()
        if covering.contains("гибк") || covering.contains("мягк") || covering.contains("shingle") { p.roofCover = "softroof" }
        else if covering.contains("профн") || covering.contains("корруг") { p.roofCover = "profroof" }
        else if covering.contains("фальц") || covering.contains("seam") { p.roofCover = "seamroof" }
        else { p.roofCover = "metaltile" }
        let facade = (result.roof?.byPhoto?.facade ?? "").lowercased()
        if facade.contains("кирпич") || facade.contains("brick") { p.facade = "facing" }
        else if facade.contains("сайдинг") || facade.contains("siding") { p.facade = "siding" }
        else if facade.contains("штукатур") || facade.contains("plaster") { p.facade = "plaster" }
        return p
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double { let f = pow(10, Double(places)); return (self * f).rounded() / f }
}

/// Цвета для картинки дома — простые варианты.
struct HouseLook: Equatable {
    var wallColor = "white"
    var roofColor = "graphite"
    static let wallColors = [("white", "Белые"), ("beige", "Бежевые"), ("grey", "Серые"), ("brick", "Кирпич"), ("dark", "Тёмные")]
    static let roofColors = [("graphite", "Графит"), ("brown", "Коричневая"), ("red", "Красная"), ("green", "Зелёная")]

    func prompt(_ p: HouseParams) -> String {
        let wall = ["white": "warm white", "beige": "soft beige", "grey": "light grey", "brick": "red-brown", "dark": "dark graphite"][wallColor] ?? "white"
        let roofColor = ["graphite": "graphite grey", "brown": "chocolate brown", "red": "terracotta red", "green": "moss green"][roofColor] ?? "graphite"
        let facade = ["plaster": "smooth \(wall) facade plaster", "facing": "\(wall) facing brick", "siding": "\(wall) horizontal siding", "none": "\(wall) aerated concrete blocks"][p.facade] ?? "\(wall) facade"
        let cover = ["metaltile": "metal roof tiles", "softroof": "asphalt shingles", "profroof": "corrugated metal sheets", "seamroof": "standing seam metal roofing"][p.roofCover] ?? "metal roof"
        let roof = p.roof == "flat" ? "flat roof with a neat parapet" : "\(roofColor) \(cover), \(p.roof == "hip" ? "hip" : "gable") roof"
        return "Photorealistic exterior photograph of this exact house. Keep the shape, proportions, roof shape and pitch, and the positions of windows and doors exactly as in the image; do not add floors or extensions. Walls: \(facade). Roof: \(roof). White window frames, neat entrance, green lawn and a few shrubs, soft daylight, realistic architectural photography."
    }
}

/// Под макетом дома: смета по этим размерам, картинка с выбранной отделкой и «Отправить» — без переходов.
struct HouseNextSteps: View {
    @EnvironmentObject private var store: AppStore
    let result: HouseResult
    let snapshotter: SceneSnapshotter
    let hasModel: Bool
    @State private var params: HouseParams
    @State private var estimate: DocEstimateResult?
    @State private var estimating = false
    @State private var estimateError: String?

    init(result: HouseResult, snapshotter: SceneSnapshotter, hasModel: Bool) {
        self.result = result
        self.snapshotter = snapshotter
        self.hasModel = hasModel
        _params = State(initialValue: HouseParams.from(result))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            estimateCard
            HouseVisualCard(params: params, snapshotter: snapshotter, hasModel: hasModel)
            ShareLink(item: shareText) { SecondaryActionLabel(title: estimate == nil ? "Отправить размеры" : "Отправить размеры и смету", icon: "square.and.arrow.up") }
                .buttonStyle(PremiumPressStyle())
        }
        .onChange(of: params) { _, _ in estimate = nil }
    }

    // MARK: Смета

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("СМЕТА ПО ЭТИМ РАЗМЕРАМ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text("Дом \(CalculationEngine.format(params.length)) × \(CalculationEngine.format(params.width)) м, \(params.floors) эт., кровля \(Int(params.pitch))° — из обмера. Выберите материалы:")
                .font(.caption).foregroundStyle(Theme.muted)
            OptionChips(HouseOptions.walls, selection: $params.walls, title: "Стены")
            OptionChips(HouseOptions.facade, selection: $params.facade, title: "Фасад")
            if params.roof != "flat" { OptionChips(HouseOptions.roofCover, selection: $params.roofCover, title: "Кровля") }
            OptionChips(HouseOptions.foundation, selection: $params.foundation, title: "Фундамент")
            OptionChips(HouseOptions.finish, selection: $params.finish, title: "Готовность")
            Stepper("Этажей: \(params.floors)", value: $params.floors, in: 1...3).font(.subheadline)
            if let estimate {
                estimateSummary(estimate)
            } else if estimating {
                HStack(spacing: 10) { ProgressView(); Text("Считаем объёмы и цены…").font(.subheadline).foregroundStyle(Theme.muted) }
                    .frame(maxWidth: .infinity).padding(10)
            } else {
                PrimaryButton(title: "Посчитать смету", icon: "rublesign.circle") { Task { await calculate() } }
                    .disabled(params.foundation == "piles" && params.heavyWalls)
            }
            if let estimateError { Label(estimateError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private func estimateSummary(_ r: DocEstimateResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CalculationEngine.money(r.totals.typical.total)).font(.system(.title, design: .serif, weight: .bold)).monospacedDigit()
            Text("Диапазон рынка: \(CalculationEngine.money(r.totals.low.total)) – \(CalculationEngine.money(r.totals.high.total))")
                .font(.caption).foregroundStyle(Theme.muted)
            HStack {
                PlanStat(value: CalculationEngine.money(r.totals.typical.materials), title: "Материалы")
                PlanStat(value: CalculationEngine.money(r.totals.typical.works + r.totals.typical.machines), title: "Работа и техника")
            }
            sourcesBlock(r)
            NavigationLink { DocEstimateResultView(result: r) } label: { SecondaryActionLabel(title: "Подробная смета по позициям", icon: "list.bullet.rectangle") }
                .buttonStyle(PremiumPressStyle())
        }
    }

    /// Откуда цены: сколько позиций со ссылками на реальные предложения и сами сайты.
    private func sourcesBlock(_ r: DocEstimateResult) -> some View {
        let prices = r.sections.flatMap(\.items).compactMap(\.price) + r.materials.compactMap(\.price)
        let priced = prices.filter(\.hasPrice)
        let linked = priced.filter { !($0.sources ?? []).isEmpty }
        var seen = Set<String>()
        let sites = linked.flatMap { $0.sources ?? [] }.compactMap { source -> (String, URL)? in
            guard let url = URL(string: source.url), let host = url.host?.replacingOccurrences(of: "www.", with: ""), seen.insert(host).inserted else { return nil }
            return (host, url)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Label("Цены: \(linked.count) из \(priced.count) позиций — реальные предложения \(r.city), остальные — ориентир", systemImage: "link")
                .font(.caption).foregroundStyle(Theme.muted)
            if !sites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sites.prefix(6), id: \.0) { site in
                            Link(destination: site.1) {
                                Text(site.0).font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Theme.accentTint, in: Capsule()).foregroundStyle(Theme.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private func calculate() async {
        estimating = true; estimateError = nil
        defer { estimating = false }
        do {
            estimate = try await HouseEstimateAPI.estimate(params, city: store.projectCity, region: store.userRegion)
            Haptics.success()
        } catch {
            estimateError = error.localizedDescription
        }
    }

    // MARK: Отправить

    private var shareText: String {
        var lines = ["3D‑ОБМЕР ДОМА"]
        if let l = result.footprint?.length?.value, let w = result.footprint?.gableWidth?.value { lines.append("Размеры: \(Units.length(l)) × \(Units.length(w))") }
        if let e = result.eaveHeight?.value { lines.append("Высота до карниза: \(Units.length(e))") }
        if let r = result.roof?.ridgeHeight?.value { lines.append("Высота конька: \(Units.length(r))") }
        if let p = result.roof?.pitchDeg?.value { lines.append("Уклон крыши: \(Int(p.rounded()))°") }
        if let a = result.footprintArea { lines.append("Пятно застройки: \(Units.area(a))") }
        if let a = result.roofArea { lines.append("Кровля: \(Units.area(a))") }
        if let a = result.facadeNetArea ?? result.facadeArea { lines.append("Фасады: \(Units.area(a))") }
        if let s = result.openingsSummary { lines.append("Окон: \(s.windows ?? 0), дверей: \(s.doors ?? 0)") }
        if let r = estimate {
            lines += ["", "СМЕТА · \(r.city)", "Итого: \(CalculationEngine.money(r.totals.typical.total)) (рынок \(CalculationEngine.money(r.totals.low.total)) – \(CalculationEngine.money(r.totals.high.total)))",
                      "Материалы: \(CalculationEngine.money(r.totals.typical.materials))", "Работа и техника: \(CalculationEngine.money(r.totals.typical.works + r.totals.typical.machines))",
                      "Цены — реальные предложения магазинов и подрядчиков города; ссылки — в подробной смете."]
        }
        lines += ["", Brand.shareFooter]
        return lines.joined(separator: "\n")
    }
}


/// «Дом с этой отделкой»: картинка по 3D‑модели (или по размерам) с фасадом и кровлей из сметы.
struct HouseVisualCard: View {
    @EnvironmentObject private var store: AppStore
    let params: HouseParams
    var snapshotter: SceneSnapshotter? = nil
    var hasModel = false
    @State private var look = HouseLook()
    @State private var picture: UIImage?
    @State private var drawing = false
    @State private var pictureError: String?
    @State private var openedPicture = false

    var body: some View {
        visualCard
            .sheet(isPresented: $openedPicture) {
                if let picture { NavigationStack { RenderResultView(image: picture, title: "Дом") } }
            }
    }


    private var visualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ДОМ С ЭТОЙ ОТДЕЛКОЙ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text(hasModel ? "Нарисуем ваш дом по 3D‑модели — с фасадом и кровлей из сметы. Поверните модель выше, чтобы выбрать ракурс."
                          : "Нарисуем дом по размерам обмера — с фасадом и кровлей из сметы.")
                .font(.caption).foregroundStyle(Theme.muted)
            OptionChips(HouseLook.wallColors, selection: $look.wallColor, title: "Цвет стен")
            if params.roof != "flat" { OptionChips(HouseLook.roofColors, selection: $look.roofColor, title: "Цвет кровли") }
            if let picture {
                Button { openedPicture = true } label: {
                    Image(uiImage: picture).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PremiumCardPressStyle())
                ShareLink(item: Image(uiImage: picture), preview: SharePreview("Дом", image: Image(uiImage: picture))) {
                    SecondaryActionLabel(title: "Отправить картинку", icon: "square.and.arrow.up")
                }
                .buttonStyle(PremiumPressStyle())
                SavePictureToObjectButton(image: picture, title: "Дом с отделкой")
            }
            if drawing {
                HStack(spacing: 10) { ProgressView(); Text("Рисуем дом… около 1–2 минут").font(.subheadline).foregroundStyle(Theme.muted) }
                    .frame(maxWidth: .infinity).padding(10)
            } else {
                PrimaryButton(title: picture == nil ? "Показать дом с этой отделкой" : "Нарисовать заново", icon: "wand.and.stars") { Task { await draw() } }
                PaidNote(kind: "imageEdit")
            }
            if let pictureError { Label(pictureError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private func draw() async {
        drawing = true; pictureError = nil
        defer { drawing = false }
        let prompt = look.prompt(params)
        do {
            if let base = snapshotter?.image() {
                picture = try await store.photorealRender(base, prompt: prompt).image
            } else {
                let size = "A \(params.floors)-storey house \(CalculationEngine.format(params.length)) by \(CalculationEngine.format(params.width)) m. "
                picture = try await store.pictureByDescription(size + prompt)
            }
            Haptics.success()
        } catch {
            pictureError = error.localizedDescription
            HelperCenter.shared.failed(error, action: "Визуализация дома")
        }
    }

}

/// «Мои обмеры» прямо на странице обмера: статус обработки, готовый макет открывается здесь же.
struct HouseScansInline: View {
    @State private var scans: [HouseScanUploader.Remote] = []
    @State private var opened: HouseScanUploader.Remote?
    @State private var loaded = false
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !scans.isEmpty {
                HStack {
                    Text("МОИ ОБМЕРЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                    Spacer()
                    if scans.count > 3 { Button("Все") { showAll = true }.font(.caption.weight(.semibold)) }
                }
                ForEach(scans.prefix(3)) { scan in
                    if scan.status == "ready", scan.result != nil {
                        Button { opened = scan } label: { HouseScanRow(scan: scan) }.buttonStyle(PremiumCardPressStyle())
                    } else {
                        HouseScanRow(scan: scan)
                    }
                }
            }
        }
        .sheet(item: $opened) { scan in
            NavigationStack {
                HouseResultView(scan: scan)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { opened = nil } } }
            }
        }
        .sheet(isPresented: $showAll) { HouseScansView() }
        .task {
            while !Task.isCancelled {
                await refresh()
                let busy = scans.contains { $0.status == "queued" || $0.status == "processing" }
                try? await Task.sleep(for: .seconds(busy ? 8 : 60))
            }
        }
    }

    private func refresh() async {
        guard let uploader = HouseScanUploader(), let fresh = try? await uploader.list() else { loaded = true; return }
        let wasBusy = Set(scans.filter { $0.status == "queued" || $0.status == "processing" }.map(\.id))
        withAnimation { scans = fresh }
        if let ready = fresh.first(where: { wasBusy.contains($0.id) && $0.status == "ready" && $0.result != nil }) {
            Haptics.success()
            opened = ready
        }
        loaded = true
    }
}
