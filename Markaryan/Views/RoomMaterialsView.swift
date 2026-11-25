import SwiftUI

/// Расчёт материалов комнаты по скану: выбираете работы — получаете плитку по раскладке, клей, затирку, маяки,
/// штукатурку, стяжку, гидроизоляцию, краску… с упаковками и нормами; при желании — цены вашего города.
struct RoomMaterialsView: View {
    @EnvironmentObject private var store: AppStore
    let plan: FloorPlan
    @State private var works: RoomWorks
    @State private var room: RoomKind
    @State private var estimate: MarketEstimate?
    @State private var pricing = false
    @State private var priceError: String?

    private static let floorFormats = ["200×200", "300×300", "300×600", "600×600", "600×1200", "800×800"]
    private static let wallFormats = ["200×200", "200×400", "250×400", "300×600", "600×600", "600×1200"]

    init(plan: FloorPlan) {
        self.plan = plan
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                roomPicker
                worksSection
                results
                actions
                if let estimate { priceSection(estimate) }
                InfoNote(text: "Нормы — типовые нормы производителей (Ceresit, Knauf, Litokol) и СП 71.13330. Плитка посчитана раскладкой по вашей комнате, с запасом 10 %. Толщины слоёв зависят от кривизны стен и пола — проверьте их правилом перед закупкой.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Расчёт материалов")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: works) { _, value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "roomWorks.\(plan.id.uuidString)") }
            estimate = nil
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
                ShareLink(item: RoomMaterials.text(plan, groups: groups)) { SecondaryActionLabel(title: "Отправить список материалов", icon: "square.and.arrow.up") }
                    .buttonStyle(PremiumPressStyle())
                if estimate == nil {
                    PrimaryButton(title: pricing ? "Ищем цены…" : "Цены в вашем городе", icon: "rublesign.circle") { Task { await price() } }
                        .disabled(pricing)
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
            }
            Text("Цены из магазинов вашего города; нажмите «Отправить», чтобы переслать список.").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(16).panelCard(16)
    }
}
