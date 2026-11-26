import SwiftUI

/// Расчёт материалов комнаты по скану: выбираете работы — получаете плитку по раскладке, клей, затирку, маяки,
/// штукатурку, стяжку, гидроизоляцию, краску… с упаковками и нормами; при желании — цены вашего города.
struct RoomMaterialsView: View {
    @EnvironmentObject private var store: AppStore
    let plan: FloorPlan
    /// Встроено в страницу комнаты (без своей прокрутки и заголовка, размеры уже показаны выше).
    var embedded = false
    @State private var works: RoomWorks
    @State private var room: RoomKind
    @State private var estimate: MarketEstimate?
    @State private var pricing = false
    @State private var priceError: String?
    @State private var addedToBudget = false

    private static let floorFormats = ["200×200", "300×300", "300×600", "600×600", "600×1200", "800×800"]
    private static let wallFormats = ["200×200", "200×400", "250×400", "300×600", "600×600", "600×1200"]

    // Визуализация с этими материалами.
    @State private var look = RoomLook()
    @State private var rendering = false
    @State private var render: UIImage?
    @State private var renderError: String?
    @State private var openedRender = false

    init(plan: FloorPlan, embedded: Bool = false) {
        self.plan = plan
        self.embedded = embedded
        let kind = RoomKind.fromScan(plan) ?? RoomKind.keyword(plan.name) ?? .living
        _room = State(initialValue: kind)
        let key = "roomWorks.\(plan.id.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(RoomWorks.self, from: data) {
            _works = State(initialValue: saved)
        } else {
            _works = State(initialValue: RoomWorks.suggested(for: kind))
        }
    }

    private var groups: [MaterialGroup] { RoomMaterials.calculate(plan, works: works) }
    private var surfaces: RoomSurfaces { RoomMaterials.surfaces(plan) }

    @ViewBuilder var body: some View {
        if embedded {
            panel
        } else {
            ScrollView { panel.padding(20) }
                .background(Theme.background)
                .navigationTitle("Расчёт материалов")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded { summary }
            roomPicker
            worksSection
            results
            actions
            if let estimate { priceSection(estimate) }
            if !groups.isEmpty { visualSection }
            InfoNote(text: "Нормы — типовые нормы производителей (Ceresit, Knauf, Litokol) и СП 71.13330. Плитка посчитана раскладкой по вашей комнате, с запасом 10 %. Толщины слоёв зависят от кривизны стен и пола — проверьте их правилом перед закупкой.")
        }
        .onChange(of: works) { _, value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "roomWorks.\(plan.id.uuidString)") }
            estimate = nil
        }
        .onAppear { if render == nil { render = RoomLookStore.load(plan.id) } }
        .sheet(isPresented: $openedRender) {
            if let render { NavigationStack { RenderResultView(image: render, title: plan.name) } }
        }
    }

    // MARK: Размеры

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PlanStat(value: Units.area(surfaces.floor), title: "Пол")
            PlanStat(value: Units.area(surfaces.wallsNet), title: "Стены без проёмов")
            PlanStat(value: Units.length(surfaces.height), title: "Высота")
            PlanStat(value: Units.run(surfaces.perimeter), title: "Периметр")
            PlanStat(value: "\(surfaces.doors)", title: "Двери")
            PlanStat(value: "\(surfaces.windows)", title: "Окна")
        }
    }

    private var roomPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ТИП ПОМЕЩЕНИЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([RoomKind.bathroom, .kitchen, .living, .bedroom, .hall, .garage], id: \.self) { kind in
                        Button {
                            room = kind
                            works = RoomWorks.suggested(for: kind)
                        } label: {
                            Text(kind.purposeTitle.tr).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(room == kind ? Theme.onAccent : Theme.ink)
                                .background(room == kind ? Theme.orange : Theme.panel, in: Capsule())
                        }
                    }
                }
            }
            Text("Набор работ подставлен для этого помещения — включите или выключите нужное.").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Работы

    private var worksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("РАБОТЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            card {
                Toggle("Плитка на пол", isOn: $works.floorTiles)
                if works.floorTiles { formatPicker("Формат", formats: Self.floorFormats, width: $works.floorTileWidthMM, length: $works.floorTileLengthMM) }
                Divider()
                Toggle("Плитка на стены", isOn: $works.wallTiles)
                if works.wallTiles {
                    formatPicker("Формат", formats: Self.wallFormats, width: $works.wallTileWidthMM, length: $works.wallTileLengthMM)
                    stepper("Высота облицовки", value: $works.wallTileHeight, range: 0...max(0.5, plan.ceilingHeight), step: 0.1,
                            text: works.wallTileHeight < 0.3 ? "до потолка".tr : Units.length(works.wallTileHeight))
                }
                if works.floorTiles || works.wallTiles {
                    stepper("Шов", value: $works.jointMM, range: 1...10, step: 0.5, text: "\(ParcelRules.format(works.jointMM, digits: 1)) " + "мм".tr)
                }
            }
            card {
                Toggle("Гидроизоляция (санузел)", isOn: $works.waterproofing)
                if works.waterproofing { Toggle("Душевая зона без поддона", isOn: $works.showerZone).font(.subheadline) }
            }
            card {
                Toggle("Штукатурка стен по маякам", isOn: $works.plaster)
                if works.plaster {
                    Picker("Штукатурка", selection: $works.plasterCement) {
                        Text("Гипсовая").tag(false)
                        Text("Цементная").tag(true)
                    }
                    .pickerStyle(.segmented)
                    stepper("Средний слой", value: $works.plasterThicknessMM, range: 5...50, step: 5, text: "\(Int(works.plasterThicknessMM)) " + "мм".tr)
                }
                Divider()
                Toggle("Стяжка пола", isOn: $works.screed)
                if works.screed { stepper("Толщина", value: $works.screedThicknessMM, range: 30...100, step: 5, text: "\(Int(works.screedThicknessMM)) " + "мм".tr) }
                Toggle("Наливной пол", isOn: $works.selfLeveling)
                if works.selfLeveling { stepper("Толщина", value: $works.selfLevelingMM, range: 2...30, step: 1, text: "\(Int(works.selfLevelingMM)) " + "мм".tr) }
            }
            card {
                Toggle("Покраска стен", isOn: $works.paintWalls)
                Toggle("Покраска потолка", isOn: $works.paintCeiling)
                Toggle("Ламинат", isOn: $works.laminate).disabled(works.floorTiles)
                Toggle("Плинтус", isOn: $works.skirting)
            }
        }
        .tint(Theme.orange)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .font(.subheadline)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private func formatPicker(_ title: String, formats: [String], width: Binding<Double>, length: Binding<Double>) -> some View {
        let current = "\(Int(width.wrappedValue))×\(Int(length.wrappedValue))"
        return HStack {
            Text(title.tr).foregroundStyle(Theme.muted)
            Spacer()
            Menu {
                ForEach(formats, id: \.self) { format in
                    Button(format + " " + "мм".tr) {
                        let parts = format.split(separator: "×").compactMap { Double($0) }
                        if parts.count == 2 { width.wrappedValue = parts[1] >= parts[0] ? parts[1] : parts[0]; length.wrappedValue = min(parts[0], parts[1]) }
                    }
                }
            } label: {
                Label(current + " " + "мм".tr, systemImage: "chevron.up.chevron.down").font(.subheadline.weight(.semibold))
            }
        }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack { Text(title.tr).foregroundStyle(Theme.muted); Spacer(); Text(text).fontWeight(.semibold).monospacedDigit() }
        }
    }

    // MARK: Результат

    @ViewBuilder private var results: some View {
        if groups.isEmpty {
            InfoNote(text: "Включите хотя бы одну работу — материалы посчитаются сразу.")
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title.tr.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                    ForEach(group.lines) { line in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.name.tr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer(minLength: 10)
                                Text("\(ParcelRules.format(line.quantity, digits: line.quantity < 10 ? 1 : 0)) \(line.unit.tr)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            if let packs = line.packs, let pack = line.pack {
                                Text("Купить: \(packs) × \(pack.tr)").font(.caption.weight(.semibold)).foregroundStyle(Theme.orange)
                            }
                            Text(line.norm).font(.caption2).foregroundStyle(Theme.muted)
                        }
                        if line.id != group.lines.last?.id { Divider() }
                    }
                }
                .padding(16).panelCard(16)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !groups.isEmpty {
                ShareLink(item: shareText) {
                    SecondaryActionLabel(title: estimate == nil ? "Отправить список материалов" : "Отправить расчёт с ценами", icon: "square.and.arrow.up")
                }
                .buttonStyle(PremiumPressStyle())
                if estimate == nil {
                    PrimaryButton(title: pricing ? "Ищем цены…" : "Цены в вашем городе", icon: "rublesign.circle") { Task { await price() } }
                        .disabled(pricing)
                    PaidNote(kind: "priceEstimate10")
                }
                if let priceError { Label(priceError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
            }
        }
    }

    private func price() async {
        guard let base = AIServerConfig.marketURL else { priceError = "Поиск цен работает через сервер приложения."; return }
        pricing = true; priceError = nil
        defer { pricing = false }
        let items = groups.flatMap(\.lines).map { line -> MarketEstimateRequestItem in
            if let packs = line.packs, let pack = line.pack {
                return MarketEstimateRequestItem(name: "\(line.name) (\(pack))", kind: "material", unit: "шт", quantity: Double(packs))
            }
            return MarketEstimateRequestItem(name: line.name, kind: "material", unit: line.unit, quantity: (line.quantity * 10).rounded() / 10)
        }
        do {
            estimate = try await ServerAIClient(base: base).priceEstimate(city: store.projectCity, items: Array(items.prefix(40)))
            Haptics.success()
        } catch {
            priceError = error.localizedDescription
        }
    }

    /// Сумма материалов — в плановый бюджет объекта, статья «Отделка» (раздел «Проект»).
    private func addToBudget(_ total: Double) {
        guard total > 0 else { return }
        if let index = store.budgetItems.firstIndex(where: { $0.title == "Отделка" }) {
            store.budgetItems[index].planned += total.rounded()
        } else {
            var item = ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: "Отделка")
            item.planned = total.rounded()
            store.budgetItems.append(item)
        }
        addedToBudget = true
        Haptics.success()
    }

    private func priceSection(_ estimate: MarketEstimate) -> some View {
        let total = estimate.items.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 10) {
            Text("ЦЕНЫ · \(estimate.city.uppercased())").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text(CalculationEngine.money(total)).font(.system(.title, design: .serif, weight: .bold)).monospacedDigit()
            ForEach(estimate.items) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.footnote)
                        if let example = row.example { Text(example).font(.caption2).foregroundStyle(Theme.muted) }
                    }
                    Spacer()
                    Text(row.hasPrice ? CalculationEngine.money(row.total) : "—").font(.footnote.weight(.semibold).monospacedDigit())
                }
                PriceSourceLinks(sources: row.sources ?? [], hasPrice: row.hasPrice)
            }
            Button {
                addToBudget(total)
            } label: {
                SecondaryActionLabel(title: addedToBudget ? "Добавлено в бюджет «Отделка»" : "В бюджет объекта", icon: addedToBudget ? "checkmark" : "plus.circle")
            }
            .buttonStyle(PremiumPressStyle())
            .disabled(addedToBudget || total <= 0)
            Text("Цены — реальные предложения магазинов и маркетплейсов вашего города: ссылка под каждой позицией. «Ориентир» — проверенного предложения не нашлось, цена примерная. «Отправить» перешлёт расчёт с ценами и ссылками.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(16).panelCard(16)
    }

    // MARK: Отправить

    private var shareText: String {
        var text = RoomMaterials.text(plan, groups: groups)
        guard let estimate else { return text + "\n\n" + Brand.shareFooter }
        let total = estimate.items.reduce(0) { $0 + $1.total }
        text += "\n\nЦЕНЫ · \(estimate.city.uppercased())"
        for row in estimate.items {
            text += "\n• \(row.name): \(row.hasPrice ? CalculationEngine.money(row.total) : "нет цены")"
            if let url = row.sources?.first?.url, !url.isEmpty { text += " — \(url)" } else if row.hasPrice { text += " (ориентир)" }
        }
        text += "\nИТОГО материалы: \(CalculationEngine.money(total))\n\n" + Brand.shareFooter
        return text
    }

    // MARK: Визуализация с этими материалами

    private var visualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ВИЗУАЛИЗАЦИЯ С ЭТИМИ МАТЕРИАЛАМИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text("Покажем вашу комнату — точные стены, окна и двери из скана — с отделкой из расчёта. Цвета можно поменять.")
                .font(.caption).foregroundStyle(Theme.muted)
            OptionChips(RoomLook.floorTones, selection: $look.floorTone, title: works.floorTiles ? "Плитка на полу" : "Пол")
            if works.floorTiles || works.wallTiles { OptionChips(RoomLook.tileLooks, selection: $look.tileLook, title: "Вид плитки") }
            OptionChips(RoomLook.wallColors, selection: $look.wallColor, title: "Цвет стен")
            if let render {
                Button { openedRender = true } label: {
                    Image(uiImage: render).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PremiumCardPressStyle())
                ShareLink(item: Image(uiImage: render), preview: SharePreview(plan.name, image: Image(uiImage: render))) {
                    SecondaryActionLabel(title: "Отправить картинку", icon: "square.and.arrow.up")
                }
                .buttonStyle(PremiumPressStyle())
                SavePictureToObjectButton(image: render, title: "Комната «\(plan.name)» с отделкой")
            }
            if rendering {
                HStack(spacing: 10) { ProgressView(); Text("Рисуем комнату… около 1–2 минут").font(.subheadline).foregroundStyle(Theme.muted) }
                    .frame(maxWidth: .infinity).padding(12)
            } else {
                PrimaryButton(title: render == nil ? "Показать комнату с этой отделкой" : "Нарисовать заново", icon: "wand.and.stars") { Task { await visualize() } }
                    .disabled(!(store.photorealAvailable || store.usesAIServer))
                PaidNote(kind: "imageEdit")
            }
            if let renderError { Label(renderError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private func visualize() async {
        guard let base = Room3DBuilder.snapshot(plan: plan, proposal: nil, mode: .interior) else { renderError = "Не получилось построить вид комнаты."; return }
        rendering = true; renderError = nil
        defer { rendering = false }
        do {
            let result = try await store.photorealRender(base, prompt: look.prompt(works: works, room: room))
            render = result.image
            RoomLookStore.save(result.image, for: plan.id)
            Haptics.success()
        } catch {
            renderError = error.localizedDescription
            HelperCenter.shared.failed(error, action: "Визуализация комнаты")
        }
    }
}

/// Ссылки на предложения, по которым взята цена; без ссылки — пометка «ориентир».
struct PriceSourceLinks: View {
    let sources: [MarketEstimateSource]
    var hasPrice = true
    var body: some View {
        if !sources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sources.prefix(3), id: \.url) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                Label(source.title.isEmpty ? (url.host ?? "источник") : source.title, systemImage: "link").font(.caption2.weight(.semibold)).lineLimit(1)
                                    .padding(.horizontal, 9).padding(.vertical, 5).background(Theme.accentTint, in: Capsule()).foregroundStyle(Theme.orange)
                            }
                        }
                    }
                }
            }
        } else if hasPrice {
            Text("ориентир — без ссылки").font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold)
        }
    }
}

/// Цвета и вид отделки для картинки — простые варианты, без каталога.
struct RoomLook: Equatable {
    var floorTone = "light"
    var tileLook = "stone"
    var wallColor = "white"

    static let floorTones = [("light", "Светлый"), ("medium", "Средний"), ("dark", "Тёмный")]
    static let tileLooks = [("stone", "Под камень"), ("concrete", "Под бетон"), ("wood", "Под дерево"), ("plain", "Однотонная")]
    static let wallColors = [("white", "Белые"), ("beige", "Бежевые"), ("grey", "Серые"), ("warm", "Тёплые"), ("green", "Шалфей")]

    func prompt(works: RoomWorks, room: RoomKind) -> String {
        let tone = ["light": "light", "medium": "medium-tone", "dark": "dark"][floorTone] ?? "light"
        let tile = ["stone": "marble-look", "concrete": "concrete-look", "wood": "wood-look", "plain": "plain matte"][tileLook] ?? "matte"
        let wall = ["white": "warm white", "beige": "soft beige", "grey": "light grey", "warm": "warm sand", "green": "muted sage green"][wallColor] ?? "white"
        var floor: String
        if works.floorTiles {
            floor = "\(tone) \(tile) porcelain floor tiles \(Int(works.floorTileLengthMM))x\(Int(works.floorTileWidthMM)) mm with thin \(Int(works.jointMM)) mm grout lines"
        } else if works.laminate {
            floor = "\(tone) oak laminate flooring"
        } else {
            floor = "\(tone) smooth floor finish"
        }
        var walls: String
        if works.wallTiles {
            let height = works.wallTileHeight < 0.3 ? "floor to ceiling" : "up to \(String(format: "%.1f", works.wallTileHeight)) m, \(wall) matte paint above"
            walls = "\(tile) wall tiles \(Int(works.wallTileWidthMM))x\(Int(works.wallTileLengthMM)) mm \(height)"
        } else {
            walls = "smooth walls painted matte \(wall)"
        }
        let skirting = works.skirting ? " Neat skirting boards." : ""
        let kind = room == .bathroom ? "bathroom" : room == .kitchen ? "kitchen" : "room"
        return "Photorealistic interior photograph of this exact \(kind) right after renovation. Keep the walls, windows, doors, ceiling height and camera exactly as in the image; do not add, remove or move walls or openings. Empty room, no furniture. Floor: \(floor). Walls: \(walls). Ceiling: flat, painted matte white.\(skirting) Soft natural daylight from the windows, realistic textures, architectural photography."
    }
}

/// Последняя картинка комнаты с отделкой — в телефоне, чтобы не рисовать заново.
enum RoomLookStore {
    private static func url(_ id: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("RoomLooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(id.uuidString).jpg")
    }
    static func load(_ id: UUID) -> UIImage? { url(id).flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:)) }
    static func save(_ image: UIImage, for id: UUID) { if let url = url(id), let data = image.jpegData(compressionQuality: 0.85) { try? data.write(to: url) } }
}
