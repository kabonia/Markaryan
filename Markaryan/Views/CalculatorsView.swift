import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI
import Photos

struct CalculatorsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""

    private var filtered: [CalculationKind] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalculationKind.allCases.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) || $0.category.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Расчёты и сметы", title: "Сначала цифры.\nПотом стройка.")
                Text("Полная смета объекта или \(CalculationKind.allCases.count) калькуляторов материалов — результат в PDF и с рыночными ценами вашего города.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                NavigationLink { DocEstimateHubView() } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "doc.text.magnifyingglass").font(.title3).foregroundStyle(Theme.orange).frame(width: 50, height: 50).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Смета по документам").font(.headline).foregroundStyle(.white)
                            Text("АР, КР, ТЗ, готовая смета или перечень работ — точный расчёт ИИ‑сметчиками").font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(18)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
                }
                .buttonStyle(PremiumCardPressStyle())

                NavigationLink { FullEstimateHubView() } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "house.and.flag.fill").font(.title3).foregroundStyle(Theme.onAccent).frame(width: 50, height: 50).background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Полная смета объекта").font(.headline).foregroundStyle(.white)
                            Text("Дом, навес, ангар, забор — по размерам, с работами, техникой и доставкой").font(.caption).foregroundStyle(.white.opacity(0.78))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.orange)
                    }
                    .padding(18)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.orange.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(PremiumCardPressStyle())

                HStack(spacing: 12) {
                    NavigationLink { CalculationHistoryView() } label: {
                        CompactEstimateCard(icon: "clock.arrow.circlepath", title: "Мои расчёты", caption: store.calculations.isEmpty ? "Пока пусто" : "Сохранено: \(store.calculations.count)")
                    }
                    NavigationLink { PhotoCountView() } label: {
                        CompactEstimateCard(icon: "camera.viewfinder", title: "Счёт по фото", caption: "Арматура, трубы, доски")
                    }
                }
                .buttonStyle(PremiumCardPressStyle())

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Найти: бетон, плитка, забор…", text: $search).submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.accessibilityLabel("Очистить поиск") }
                }
                .padding(14)
                .panelCard(15)

                ForEach(CalculationCategory.allCases) { category in
                    let kinds = filtered.filter { $0.category == category }
                    if !kinds.isEmpty {
                        Text(category.title.uppercased()).font(.caption.weight(.bold)).tracking(1.25).foregroundStyle(Theme.gold).padding(.top, 4)
                        ForEach(kinds) { kind in
                            NavigationLink { CalculatorView(kind: kind) } label: { CalculatorRow(kind: kind, used: store.lastInputs[kind.rawValue] != nil) }
                                .buttonStyle(PremiumCardPressStyle())
                        }
                    }
                }
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                InfoNote(text: "Объёмы и цены предварительные. Конструкции и нагрузки проверяются по проекту.")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .navigationTitle("Смета").helperScreen("Смета").featureIntro(.calculators)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CalculatorRow: View {
    let kind: CalculationKind
    let used: Bool
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: kind.icon).font(.title3).foregroundStyle(Theme.orange).frame(width: 44, height: 44)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.orange.opacity(0.12), lineWidth: 0.6))
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.system(.subheadline, design: .serif, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(kind.summary).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if used { Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(Theme.muted).accessibilityLabel("Есть сохранённые размеры") }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .panelCard(18)
    }
}

struct CompactEstimateCard: View {
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.gold)
                .frame(width: 40, height: 40).background(Theme.goldTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 2)
            Text(title.tr).font(.system(.subheadline, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
            Text(caption.tr).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 111, alignment: .topLeading)
        .padding(15)
        .panelCard(19)
    }
}

enum FullEstimateKind: String, CaseIterable, Identifiable {
    case house, metal
    var id: String { rawValue }
    var title: String { switch self { case .house: return "Дом"; case .metal: return "Металлоконструкции" } }
    var screenTitle: String { "Смета: \(title.lowercased())" }
    var subtitle: String { switch self { case .house: return "Фундамент, коробка, кровля, инженерия и отделка"; case .metal: return "Навесы, ангары и склады, заборы — по весу металла" } }
    var icon: String { switch self { case .house: return "house.and.flag.fill"; case .metal: return "wrench.and.screwdriver.fill" } }
    var startArea: String { switch self { case .house: return "150"; case .metal: return "30" } }
    var areaTitle: String { switch self { case .house: return "Площадь дома, м²"; case .metal: return "Площадь конструкции, м²" } }
    /// Sections that depend on the building footprint, not on the total floor area.
    var footprintSections: Set<String> { self == .house ? ["Фундамент", "Кровля"] : [] }
}

struct FullEstimateHubView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Прозрачная стоимость", title: "Смета для вашего объекта")
            Text("Выберите тип объекта. Внутри — все материалы, работы, техника и доставка по строкам.").font(.subheadline).foregroundStyle(Theme.muted)
            ForEach(FullEstimateKind.allCases) { kind in
                NavigationLink { if kind == .house { HouseEstimateParamsView() } else { MetalEstimateParamsView() } } label: {
                    HStack(spacing: 15) {
                        Image(systemName: kind.icon).font(.title2).foregroundStyle(Theme.onAccent).frame(width: 48, height: 48).background(Theme.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) { Text(kind.title).font(.headline).foregroundStyle(Theme.ink); Text(kind.subtitle).font(.caption).foregroundStyle(Theme.muted) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.orange)
                    }.padding(17).panelCard(20)
                }.buttonStyle(PremiumCardPressStyle())
            }
            InfoNote(text: "Наша цена формируется из актуального прайса. Она предварительная и уточняется после проекта и выезда на объект.")
        }.padding(20) }.background(Theme.background).navigationTitle("Полные сметы").helperScreen("Полные сметы").featureIntro(.fullEstimate).navigationBarTitleDisplayMode(.inline)
    }
}

struct HouseEstimateView: View {
    @EnvironmentObject private var store: AppStore
    /// The price file import is for the owner: it shows with the developer tools (five taps on the version in «Профиль»).
    @AppStorage("developerTools") private var developerTools = false
    let kind: FullEstimateKind
    @State private var area: String
    @State private var floors = "1"
    @State private var reserve = "10"
    @State private var excluded: Set<String> = []
    @State private var showImporter = false
    @State private var showServerSettings = false
    @State private var exportFile: SharedFile?
    @State private var budgetMessage: String?
    @FocusState private var focused: String?
    init(kind: FullEstimateKind = .house) { self.kind = kind; _area = State(initialValue: kind.startArea) }

    private var allLines: [PriceLine] { store.priceBook.lines.filter { $0.scopes.contains(kind.rawValue) } }
    private var sections: [String] { var seen = Set<String>(); return allLines.map(\.section).filter { seen.insert($0).inserted } }
    /// Lines that are actually included in the estimate (sections can be switched off, e.g. «без отделки»).
    private var lines: [PriceLine] { allLines.filter { !excluded.contains($0.section) } }
    private var squareMeters: Double { min(100_000, max(0, CalculationEngine.parse(area) ?? 0)) }
    private var floorCount: Double { kind == .house ? min(5, max(1, (CalculationEngine.parse(floors) ?? 1).rounded())) : 1 }
    private var footprint: Double { squareMeters / floorCount }
    private var reserveFactor: Double { 1 + min(100, max(0, CalculationEngine.parse(reserve) ?? 0)) / 100 }
    private func quantity(_ line: PriceLine) -> Double {
        guard line.basis != "fixed" else { return 1 }
        let base = kind.footprintSections.contains(line.section) ? footprint : squareMeters
        return base * line.quantityPerSquareMeter
    }
    private func material(_ line: PriceLine) -> Double { quantity(line) * line.materialRate * reserveFactor }
    private func labor(_ line: PriceLine) -> Double { quantity(line) * line.laborRate }
    private func sectionTotal(_ section: String) -> Double { allLines.filter { $0.section == section }.reduce(0) { $0 + material($1) + labor($1) } }
    private var materialTotal: Double { lines.reduce(0) { $0 + material($1) } }
    private var laborTotal: Double { lines.reduce(0) { $0 + labor($1) } }
    private var total: Double { materialTotal + laborTotal }
    private var perSquareMeter: Double { squareMeters > 0 ? total / squareMeters : 0 }
    /// Market range of the whole estimate: P25 / P75 of real offers where known, the line price otherwise.
    private var totalLow: Double { lines.reduce(0) { $0 + quantity($1) * (($1.materialLow ?? $1.materialRate) * reserveFactor + ($1.laborLow ?? $1.laborRate)) } }
    private var totalHigh: Double { lines.reduce(0) { $0 + quantity($1) * (($1.materialHigh ?? $1.materialRate) * reserveFactor + ($1.laborHigh ?? $1.laborRate)) } }
    private var priceCity: String { store.priceBook.city ?? store.userRegion?.city ?? "" }
    private var isMarketPriced: Bool { store.priceBook.marketLineCount > 0 }
    private var partnerSummary: String {
        "Здравствуйте! Посчитал в приложении \(Brand.name) смету «\(kind.title)» на \(area) м²\(priceCity.isEmpty ? "" : ", \(priceCity)"): рыночная оценка \(CalculationEngine.money(total)). Подскажите вашу цену за эти работы?"
    }
    private var inputsDescription: String {
        var parts = ["Площадь: \(area) м²"]
        if kind == .house { parts.append("Этажей: \(Int(floorCount)) (пятно застройки ≈ \(CalculationEngine.format(footprint.rounded())) м²)") }
        parts.append("Запас материалов: \(reserve)%")
        if !excluded.isEmpty { parts.append("Без разделов: \(sections.filter { excluded.contains($0) }.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }
    private var report: String {
        var text = ["РЫНОЧНАЯ СМЕТА: \(kind.title.uppercased())", "Объект: \(store.projectDisplayName)", "Цены: \(priceCity.isEmpty ? "базовые ориентиры" : priceCity)", inputsDescription, ""]
        for section in sections where !excluded.contains(section) {
            let sectionLines = lines.filter { $0.section == section }
            guard !sectionLines.isEmpty else { continue }
            text.append(section.uppercased())
            for line in sectionLines { text.append("\(line.title): \(CalculationEngine.format(quantity(line))) \(line.unit) · материалы \(CalculationEngine.money(material(line))) · работа \(CalculationEngine.money(labor(line)))") }
            text.append("")
        }
        text += ["Материалы: \(CalculationEngine.money(materialTotal))", "Работа и техника: \(CalculationEngine.money(laborTotal))", "ИТОГО: \(CalculationEngine.money(total))", isMarketPriced ? "Рыночный диапазон: \(CalculationEngine.money(totalLow)) – \(CalculationEngine.money(totalHigh))" : "", "", "Расчёт предварительный, по рыночным ценам магазинов и мастеров. Окончательная стоимость зависит от проекта, участка, выбранных материалов и подрядчика.", "", Brand.shareFooter]
        return text.joined(separator: "\n")
    }
    private var assistantContext: AIAssistantContext {
        let assistantLines = lines.map { line in
            AIAssistantLine(id: line.code, section: line.section, title: line.title, quantity: quantity(line), unit: line.unit, material: material(line), labor: labor(line), total: material(line) + labor(line))
        }
        let context = AIAssistantContext(estimateType: kind.title, objectName: store.projectDisplayName, area: squareMeters, floors: Int(floorCount), reservePercent: CalculationEngine.parse(reserve), materialTotal: materialTotal, laborTotal: laborTotal, total: total, lines: assistantLines)
        return priceCity.isEmpty ? context : context.withCity(priceCity)
    }
    private var printableDocument: PrintableEstimate {
        PrintableEstimate(title: "Локальная смета: \(kind.title)", objectName: store.projectDisplayName, inputs: [inputsDescription], lines: lines.map { line in
            PrintableEstimateLine(section: line.section, title: line.title, quantity: quantity(line), unit: line.unit, material: material(line), labor: labor(line), total: material(line) + labor(line))
        }, materialTotal: materialTotal, laborTotal: laborTotal, total: total, note: "Рыночная оценка\(priceCity.isEmpty ? "" : " для города \(priceCity)") по ценам магазинов, маркетплейсов и мастеров. Окончательная стоимость уточняется после проекта и выбора подрядчика.")
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            SectionTitle(eyebrow: "Рыночная стоимость", title: "Полная смета: \(kind.title.lowercased())")
            RegionChip()
            HStack(spacing: 12) {
                estimateField("Площадь, м²", text: $area, id: "area")
                if kind == .house { estimateField("Этажей", text: $floors, id: "floors", type: .numberPad) }
                estimateField("Запас, %", text: $reserve, id: "reserve")
            }
            totalCard
            if store.priceAlert != nil { PriceAlertBanner(text: store.priceAlert ?? "") { store.priceAlert = nil } }
            ForEach(sections, id: \.self) { section in sectionCard(section) }

            HStack(spacing: 10) {
                Button { exportPDF() } label: { SecondaryActionLabel(title: "PDF", icon: "doc.richtext") }.buttonStyle(PremiumPressStyle())
                ShareLink(item: report) { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
            }
            HStack(spacing: 10) {
                NavigationLink { AIAssistantView(context: assistantContext) } label: { SecondaryActionLabel(title: "Спросить ИИ", icon: "sparkles") }.buttonStyle(PremiumPressStyle())
                Button { applyToBudget() } label: { SecondaryActionLabel(title: "В бюджет", icon: "chart.bar.doc.horizontal") }.buttonStyle(PremiumPressStyle())
            }
            if total > 0 { PartnerOfferSection(category: kind.rawValue, summary: partnerSummary) }
            PriceSourceNote()
        }.padding(20) }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background).navigationTitle(kind.screenTitle).helperScreen(kind.screenTitle, details: report).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = nil } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await store.refreshPriceBook() } } label: { Label("Обновить рыночные цены", systemImage: "arrow.clockwise") }
                        Button { store.showRegionPicker = true } label: { Label("Сменить город", systemImage: "mappin.and.ellipse") }
                        if developerTools {
                            Button { showImporter = true } label: { Label("Импортировать файл прайса", systemImage: "square.and.arrow.down") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Настройки прайса")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try store.importPriceBook(from: url)
                } catch { store.priceSyncMessage = "Не удалось импортировать прайс: \(error.localizedDescription)" }
            }
            .sheet(isPresented: $showServerSettings) { NavigationStack { PriceServerSettingsView() } }
            .sheet(item: $exportFile) { file in ActivityShareSheet(items: [file.url]) }
            .alert("Прайс", isPresented: Binding(get: { store.priceSyncMessage != nil && !showServerSettings }, set: { if !$0 { store.priceSyncMessage = nil } })) { Button("Понятно") { store.priceSyncMessage = nil } } message: { Text(store.priceSyncMessage ?? "") }
            .alert("Бюджет проекта", isPresented: Binding(get: { budgetMessage != nil }, set: { if !$0 { budgetMessage = nil } })) { Button("Понятно") { budgetMessage = nil } } message: { Text(budgetMessage ?? "") }
            .onAppear { store.track("estimate_open_\(kind.rawValue)"); if kind == .house, let saved = CalculationEngine.parse(store.passport.area), saved > 0 { area = store.passport.area } }
            .task { await store.ensureRegion() }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isMarketPriced ? "РЫНОЧНАЯ ЦЕНА · \(priceCity.uppercased())" : "ОРИЕНТИР · ПРЕДВАРИТЕЛЬНО").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
            Text(CalculationEngine.money(total)).font(.system(size: 38, weight: .bold, design: .serif)).foregroundStyle(.white).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).contentTransition(.numericText()).animation(.snappy, value: total)
            if perSquareMeter > 0 { Text("≈ \(CalculationEngine.money(perSquareMeter)) за м²").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85)) }
            if isMarketPriced, totalHigh > totalLow { Text("Рынок: \(CalculationEngine.money(totalLow)) – \(CalculationEngine.money(totalHigh))").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white) }
            HStack { Text("Материалы: \(CalculationEngine.money(materialTotal))"); Spacer(); Text("Работа: \(CalculationEngine.money(laborTotal))") }.font(.caption).foregroundStyle(.white.opacity(0.8))
            if total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.orange).frame(width: max(4, proxy.size.width * materialTotal / total))
                        Capsule().fill(Theme.sky)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.orange.opacity(0.2), lineWidth: 1))
    }

    private func sectionCard(_ section: String) -> some View {
        let isOn = !excluded.contains(section)
        let sectionLines = allLines.filter { $0.section == section }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { if isOn { excluded.insert(section) } else { excluded.remove(section) } }
            } label: {
                HStack {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square").foregroundStyle(isOn ? Theme.orange : Theme.muted)
                    Text(section.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(isOn ? Theme.orange : Theme.muted)
                    Spacer()
                    Text(CalculationEngine.money(sectionTotal(section))).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(isOn ? Theme.ink : Theme.muted).strikethrough(!isOn)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section): \(isOn ? "включён" : "исключён") в смету")
            .padding(.bottom, isOn ? 6 : 0)
            if isOn {
                ForEach(sectionLines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) { Text(line.title).font(.subheadline.weight(.medium)); Spacer(); Text(CalculationEngine.money(material(line) + labor(line))).font(.subheadline.bold()).monospacedDigit() }
                        Text("\(CalculationEngine.format(quantity(line))) \(line.unit) · материалы \(CalculationEngine.money(material(line))) · работа \(CalculationEngine.money(labor(line)))").font(.caption).foregroundStyle(Theme.muted)
                        if isMarketPriced { Text(line.hasMarketData ? (line.lowData == true ? "рынок · мало предложений" : "рынок · \((line.materialSources ?? 0) + (line.laborSources ?? 0)) предложений") : "ориентир · нет рыночных данных").font(.caption2.weight(.semibold)).foregroundStyle(line.hasMarketData && line.lowData != true ? Theme.success : Theme.orangeSoft) }
                    }.padding(.vertical, 11)
                    if line.id != sectionLines.last?.id { Divider() }
                }
            }
        }
        .padding(18)
        .panelCard(18)
        .opacity(isOn ? 1 : 0.7)
    }

    private func applyToBudget() {
        var sectionsToApply: [(title: String, amount: Double)] = []
        for section in sections where !excluded.contains(section) {
            let amount = lines.filter { $0.section == section }.reduce(0) { partial, line in partial + material(line) + labor(line) }
            sectionsToApply.append((title: section, amount: amount))
        }
        let count = store.applyEstimateToBudget(sectionsToApply)
        Haptics.success()
        budgetMessage = "Плановые суммы обновлены по \(count) статьям. Откройте «Проект → Бюджет», чтобы вносить фактические платежи."
    }
    private func exportPDF() {
        do { exportFile = SharedFile(url: try EstimatePDFRenderer.render(printableDocument)); store.registerMeaningfulAction(); store.track("pdf_estimate") }
        catch { store.priceSyncMessage = "Не удалось подготовить PDF: \(error.localizedDescription)" }
    }
    private func estimateField(_ title: String, text: Binding<String>, id: String, type: UIKeyboardType = .decimalPad) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title.tr).font(.caption).foregroundStyle(Theme.muted); TextField("0", text: text).keyboardType(type).focused($focused, equals: id).font(.headline.monospacedDigit()).padding(12).panelCard(12) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A generated file (PDF, image) waiting to be shared through the system share sheet.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct CalculatorView: View {
    @EnvironmentObject private var store: AppStore
    let kind: CalculationKind
    let measurementNote: String?
    private let initialValues: [String: String]
    @State private var values: [String: String]
    @State private var object = ""
    @State private var result: CalculationResult?
    @State private var error: String?
    @State private var saved = false
    @State private var exportFile: SharedFile?
    @State private var didLoad = false
    @State private var cityPrices: MarketEstimate?
    @State private var pricing = false
    @State private var priceError: String?
    @FocusState private var focusedField: String?
    init(kind: CalculationKind, initialValues: [String: String] = [:], measurementNote: String? = nil) {
        self.measurementNote = measurementNote
        self.kind = kind
        self.initialValues = initialValues
        var values = Dictionary(uniqueKeysWithValues: kind.fields.map { ($0.id, $0.initial) })
        values.merge(initialValues) { _, new in new }
        _values = State(initialValue: values)
        _result = State(initialValue: try? CalculationEngine.calculate(kind, values: values))
    }
    private var objectName: String { object.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? store.projectDisplayName : object }
    var snapshot: SavedCalculation? {
        result.map { SavedCalculation(id: UUID(), date: Date(), object: objectName, kind: kind, values: values, result: $0, measurementNote: measurementNote) }
    }
    private func assistantContext(for result: CalculationResult) -> AIAssistantContext {
        let contextLines = result.lines.enumerated().map { index, line in
            AIAssistantLine(id: "result-\(index)", section: "Результат расчёта", title: line.label, quantity: line.value, unit: line.unit, material: 0, labor: 0, total: 0)
        }
        return AIAssistantContext(estimateType: kind.title, objectName: objectName, area: nil, floors: nil, reservePercent: CalculationEngine.parse(values["reserve"] ?? ""), materialTotal: result.cost, laborTotal: nil, total: result.cost, lines: contextLines)
    }
    private func printableDocument(for result: CalculationResult) -> PrintableEstimate {
        let inputs = kind.fields.compactMap { field -> String? in
            guard let value = values[field.id], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "\(field.title): \(value) \(field.unit)"
        }
        return PrintableEstimate(title: "Строительный расчёт: \(kind.title)", objectName: objectName, inputs: inputs, lines: result.lines.map { line in
            PrintableEstimateLine(section: "Результат", title: line.label, quantity: line.value, unit: line.unit, material: nil, labor: nil, total: nil)
        }, materialTotal: result.cost, laborTotal: nil, total: result.cost, note: "Расчёт подготовлен по введённым данным. Формула: \(result.formula). Стоимость указана только при заполненной цене материала; работы и доставка рассчитываются отдельной сметой.")
    }
    private func update(_ id: String, _ text: String) {
        values[id] = text
        saved = false
        error = nil
        cityPrices = nil
        // Live result: show numbers as soon as the input is valid, without pressing the button.
        withAnimation(.snappy) { result = try? CalculationEngine.calculate(kind, values: values) }
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            SectionTitle(eyebrow: kind.category.title, title: kind.title)
            if let measurementNote { InfoNote(text: measurementNote) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Объект").font(.subheadline).foregroundStyle(Theme.muted)
                TextField(store.projectDisplayName, text: $object).textInputAutocapitalization(.sentences).padding(16).panelCard(14).onChange(of: object) { _, _ in saved = false }
            }
            ForEach(kind.fields) { field in
                VStack(alignment: .leading, spacing: 9) {
                    Text(field.title).font(.subheadline).foregroundStyle(Theme.muted)
                    HStack {
                        TextField(field.id == "price" ? "Не учитывать" : "0", text: Binding(get: { values[field.id] ?? "" }, set: { update(field.id, $0) }))
                            .keyboardType(.decimalPad).focused($focusedField, equals: field.id).font(.title3.monospacedDigit()).accessibilityLabel("\(field.title), \(field.unit)")
                        Text(field.unit).font(.subheadline).foregroundStyle(Theme.orange)
                    }.padding(16).panelCard(14)
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.danger).accessibilityLabel("Ошибка: \(error)") }
            if result == nil {
                PrimaryButton(title: "Рассчитать", icon: "equal") {
                    focusedField = nil
                    do { result = try CalculationEngine.calculate(kind, values: values); error = nil; saved = false }
                    catch { result = nil; self.error = error.localizedDescription; Haptics.warning() }
                }
            }
            if let result {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("РЕЗУЛЬТАТ").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.orange); Spacer(); Text("обновляется сразу").font(.caption2).foregroundStyle(Theme.muted) }
                    ForEach(result.lines) { line in
                        VStack(alignment: .leading, spacing: 4) { Text(line.label).font(.subheadline).foregroundStyle(Theme.muted); Text(line.formatted).font(.title2.bold()).monospacedDigit().contentTransition(.numericText()) }
                    }
                    if let cost = result.cost { Divider(); Text("Материалы: \(CalculationEngine.money(cost))").font(.title2.bold()); Text("По вашей цене. Без работ, доставки и сопутствующих материалов.").font(.caption).foregroundStyle(Theme.muted) }
                    DisclosureGroup("Как рассчитано") { Text(result.formula).font(.footnote).foregroundStyle(Theme.muted).padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading) }.tint(Theme.orange)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).panelCard(20)
                if let snapshot {
                    PrimaryButton(title: saved ? "Сохранено в «Мои расчёты»" : "Сохранить расчёт", icon: saved ? "checkmark" : "bookmark") {
                        if !saved { store.addCalculation(snapshot); store.rememberInputs(values, for: kind); saved = true; Haptics.success() }
                    }.disabled(saved)
                    HStack(spacing: 10) {
                        Button { exportPDF(result) } label: { SecondaryActionLabel(title: "PDF", icon: "doc.richtext") }.buttonStyle(PremiumPressStyle())
                        ShareLink(item: snapshot.report) { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
                    }
                    cityPricesCard(result)
                    NavigationLink { AIAssistantView(context: assistantContext(for: result)) } label: { SecondaryActionLabel(title: "Спросить ИИ", icon: "sparkles") }.buttonStyle(PremiumPressStyle())
                    PartnerOfferSection(category: kind.category.rawValue, summary: "Здравствуйте! Посчитал в приложении \(Brand.name): «\(kind.title)».\n" + result.lines.map { "\($0.label): \($0.formatted)" }.joined(separator: "\n") + "\nПодскажите вашу цену за эти работы?")
                }
            }
            InfoNote(text: kind.note)
            Text("Значения по умолчанию приведены для примера. Последние введённые размеры запоминаются при сохранении расчёта.").font(.caption).foregroundStyle(Theme.muted)
        }.padding(20) }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background).navigationTitle(kind.title).helperScreen("Калькулятор: \(kind.title)", details: kind.note).featureIntro(.calculator).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focusedField = nil } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { resetToDefaults() } label: { Label("Сбросить к примеру", systemImage: "arrow.counterclockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Действия")
                }
            }
            .sheet(item: $exportFile) { file in ActivityShareSheet(items: [file.url]) }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                // Restore the last sizes the user saved for this calculator (unless AR or history passed explicit values).
                if initialValues.isEmpty, let remembered = store.lastInputs[kind.rawValue] {
                    for field in kind.fields { if let value = remembered[field.id] { values[field.id] = value } }
                    result = try? CalculationEngine.calculate(kind, values: values)
                }
                store.track("calculator_\(kind.rawValue)")
            }
    }
    /// Цены материалов из расчёта в городе пользователя — с ссылками на предложения.
    @ViewBuilder private func cityPricesCard(_ result: CalculationResult) -> some View {
        if let cityPrices {
            let total = cityPrices.items.reduce(0) { $0 + $1.total }
            VStack(alignment: .leading, spacing: 10) {
                Text("ЦЕНЫ · \(cityPrices.city.uppercased())").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Text(CalculationEngine.money(total)).font(.system(.title2, design: .serif, weight: .bold)).monospacedDigit()
                ForEach(cityPrices.items) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).font(.footnote)
                        Spacer()
                        Text(row.hasPrice ? CalculationEngine.money(row.total) : "—").font(.footnote.weight(.semibold).monospacedDigit())
                    }
                    PriceSourceLinks(sources: row.sources ?? [], hasPrice: row.hasPrice)
                }
                ShareLink(item: (snapshot?.report ?? "") + "\n\nЦЕНЫ · \(cityPrices.city)\n" + cityPrices.items.map { "• \($0.name): \($0.hasPrice ? CalculationEngine.money($0.total) : "нет цены")\($0.sources?.first.map { " — " + $0.url } ?? "")" }.joined(separator: "\n") + "\nИтого: \(CalculationEngine.money(total))") {
                    SecondaryActionLabel(title: "Отправить расчёт с ценами", icon: "square.and.arrow.up")
                }
                .buttonStyle(PremiumPressStyle())
                Text("Реальные предложения магазинов вашего города; без ссылки — ориентир.").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
        } else if store.usesAIServer {
            Button { Task { await findPrices(result) } } label: {
                SecondaryActionLabel(title: pricing ? "Ищем цены…" : "Цены в вашем городе — со ссылками", icon: "rublesign.circle")
            }
            .buttonStyle(PremiumPressStyle()).disabled(pricing)
            PaidNote(kind: "priceEstimate10")
            if let priceError { Label(priceError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
        }
    }

    private func findPrices(_ result: CalculationResult) async {
        guard let base = AIServerConfig.marketURL else { return }
        pricing = true; priceError = nil
        defer { pricing = false }
        let items = result.lines.filter { !$0.unit.isEmpty && $0.value > 0 && !["%", "м²", "м", "мм", "°"].contains($0.unit) }
            .map { MarketEstimateRequestItem(name: "\(kind.title): \($0.label)", kind: "material", unit: $0.unit, quantity: ($0.value * 10).rounded() / 10) }
        guard !items.isEmpty else { priceError = "В этом расчёте нет материалов для поиска цен."; return }
        do {
            cityPrices = try await ServerAIClient(base: base).priceEstimate(city: store.projectCity, items: Array(items.prefix(20)))
            Haptics.success()
        } catch {
            priceError = error.localizedDescription
        }
    }

    private func resetToDefaults() {
        values = Dictionary(uniqueKeysWithValues: kind.fields.map { ($0.id, $0.initial) })
        result = try? CalculationEngine.calculate(kind, values: values)
        error = nil; saved = false
    }
    private func exportPDF(_ result: CalculationResult) {
        do { exportFile = SharedFile(url: try EstimatePDFRenderer.render(printableDocument(for: result))); store.registerMeaningfulAction(); store.track("pdf_calculation") }
        catch let renderError { error = "Не удалось подготовить PDF: \(renderError.localizedDescription)" }
    }
}
struct CalculationHistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.calculations.isEmpty { ContentUnavailableView("Пока нет расчётов", systemImage: "function", description: Text("Рассчитайте материалы и сохраните результат — он появится здесь.")) }
            ForEach(store.calculations) { item in
                NavigationLink { SavedCalculationView(item: item) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.icon).foregroundStyle(Theme.orange).frame(width: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.kind.title).font(.headline)
                            Text(item.object).font(.subheadline).foregroundStyle(Theme.muted)
                            HStack {
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                if let cost = item.result.cost { Text("· \(CalculationEngine.money(cost))") }
                            }.font(.caption).foregroundStyle(Theme.muted)
                        }
                    }.padding(.vertical, 4)
                }
            }.onDelete { store.calculations.remove(atOffsets: $0) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Мои расчёты").helperScreen("Мои расчёты").toolbar { if !store.calculations.isEmpty { EditButton() } }
    }
}
struct SavedCalculationView: View {
    @EnvironmentObject private var store: AppStore
    let item: SavedCalculation
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: item.date.formatted(date: .abbreviated, time: .shortened), title: item.kind.title)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(item.result.lines) { line in
                    HStack { Text(line.label).font(.subheadline).foregroundStyle(Theme.muted); Spacer(); Text(line.formatted).font(.subheadline.bold()).monospacedDigit() }
                }
                if let cost = item.result.cost { Divider(); HStack { Text("Материалы").font(.headline); Spacer(); Text(CalculationEngine.money(cost)).font(.headline) } }
            }.padding(18).panelCard(18)
            DisclosureGroup("Полный текст ведомости") { Text(item.report).font(.footnote).textSelection(.enabled).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading) }.tint(Theme.orange)
            NavigationLink { CalculatorView(kind: item.kind, initialValues: item.values, measurementNote: item.measurementNote) } label: { SecondaryActionLabel(title: "Пересчитать с новыми размерами", icon: "arrow.triangle.2.circlepath") }.buttonStyle(PremiumPressStyle())
            ShareLink(item: item.report) { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
            SaveToObjectButton(kind: .calculation, id: item.id.uuidString, title: item.kind.title, subtitle: item.result.lines.first.map { "\($0.label): \($0.formatted)" })
        }.padding(20) }.background(Theme.background).navigationTitle(item.object).helperScreen(item.object).navigationBarTitleDisplayMode(.inline)
    }
}

struct AssistantChatMessage: Identifiable {
    enum Role { case client, assistant }
    let id = UUID()
    let role: Role
    var text: String
    let links: [AIAssistantLocalLink]
    var image: UIImage?

    init(role: Role, text: String, links: [AIAssistantLocalLink] = [], image: UIImage? = nil) {
        self.role = role
        self.text = text
        self.links = links
        self.image = image
    }
}

struct AIAssistantView: View {
    @EnvironmentObject private var store: AppStore
    let context: AIAssistantContext
    @State private var prompt = ""
    @State private var messages: [AssistantChatMessage] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var attachedPhoto: UIImage?
    @State private var streamingID: UUID?
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        if context.lines.isEmpty {
            return ["С чего начать стройку дома в Сочи?", "Какой фундамент выбрать на склоне?", "Как не переплатить подрядчику?", "Что проверить при приёмке работ?"]
        }
        return ["Объясни смету простыми словами", "Что можно оптимизировать без потери качества?", "Какие работы идут в первую очередь?", "Где найти поставщиков дешевле?"]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView { VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "СтройПомощник", title: context.estimateType)
                    Text(context.lines.isEmpty ? "Задайте вопрос о стройке, материалах или порядке работ. Помощник не заменяет проектировщика для несущих конструкций." : "Помощник видит параметры текущего расчёта и объясняет объёмы, смету и порядок работ. Он не заменяет проектировщика для несущих конструкций.").font(.footnote).foregroundStyle(Theme.muted)
                    if store.priceServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NavigationLink { PriceServerSettingsView() } label: { Label("Указать адрес сервера ИИ", systemImage: "gearshape").frame(maxWidth: .infinity).padding(14).foregroundStyle(Theme.onAccent).background(Theme.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }.buttonStyle(.plain)
                    }
                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Можно спросить").font(.headline)
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { send(suggestion) } label: { HStack { Text(suggestion); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.orange) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).panelCard(14) }.buttonStyle(.plain).disabled(isLoading)
                            }
                        }
                    }
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 11) {
                            if let photo = message.image {
                                Image(uiImage: photo).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Text(message.text.isEmpty && message.id == streamingID ? "…" : message.text)
                                .textSelection(.enabled)
                                .font(.body)
                                .foregroundStyle(message.role == .client ? Theme.onAccent : Theme.ink)
                            if message.role == .assistant && !message.links.isEmpty {
                                ForEach(message.links) { link in
                                    if let destination = link.destination {
                                        Link(destination: destination) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "mappin.and.ellipse")
                                                Text(link.title).lineLimit(2)
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.right")
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.orange)
                                            .padding(11)
                                            .background(Theme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }
                            if message.role == .assistant && message.id != streamingID {
                                HStack(spacing: 16) {
                                    Button { UIPasteboard.general.string = message.text; Haptics.success() } label: { Label("Копировать", systemImage: "doc.on.doc") }
                                    ShareLink(item: message.text + "\n\n" + Brand.shareFooter) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(message.role == .client ? Theme.orange : Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(message.role == .client ? .leading : .trailing, 28)
                        .id(message.id)
                    }
                    if isLoading && streamingID == nil { HStack(spacing: 10) { ProgressView(); Text(context.lines.isEmpty ? "СтройПомощник думает…" : "ИИ изучает расчёт…").font(.subheadline).foregroundStyle(Theme.muted) }.padding(15).panelCard(16).id("loading") }
                    if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger)
                            if let lastQuestion = messages.last(where: { $0.role == .client })?.text {
                                Button("Повторить вопрос") { retry(lastQuestion) }.font(.footnote.weight(.semibold))
                            }
                        }
                    }
                }.padding(20) }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                .onChange(of: messages.last?.text.count ?? 0) { _, _ in if let id = streamingID { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of: isLoading) { _, loading in if loading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } } }
            }
            Divider()
            if let attachedPhoto {
                HStack(spacing: 10) {
                    Image(uiImage: attachedPhoto).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Фото будет отправлено с вопросом").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Button { self.attachedPhoto = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.accessibilityLabel("Убрать фото")
                }
                .padding(.horizontal, 16).padding(.top, 10)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if store.usesClaude || store.usesAIServer {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.badge.plus").font(.title3).frame(width: 40, height: 46).foregroundStyle(Theme.orange)
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Прикрепить фото к вопросу")
                }
                TextField(attachedPhoto == nil ? "Напишите вопрос" : "Что спросить про фото?", text: $prompt, axis: .vertical).lineLimit(1...4).focused($inputFocused).padding(12).panelCard(15).disabled(isLoading)
                Button { send(prompt) } label: { Image(systemName: "arrow.up").accessibilityLabel("Отправить").font(.headline).frame(width: 46, height: 46).foregroundStyle(Theme.onAccent).background(Theme.orange, in: Circle()) }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .accessibilityLabel("Отправить вопрос")
            }.padding(16).background(Theme.background)
        }.background(Theme.background).navigationTitle("СтройПомощник").navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { attachedPhoto = image }
                photoItem = nil
            }
        }
    }
    private var conversationSummary: String {
        let dialogue = messages.map { ($0.role == .client ? "Вопрос: " : "Ответ ИИ: ") + $0.text }.joined(separator: "\n\n")
        return String(("Хочу обсудить с инженером вопрос из СтройПомощника.\n\n" + dialogue).prefix(1500))
    }
    private var history: [(question: String, answer: String)] {
        var pairs: [(question: String, answer: String)] = []
        var pendingQuestion: String?
        for message in messages {
            if message.role == .client { pendingQuestion = message.text }
            else if let question = pendingQuestion { pairs.append((question: question, answer: message.text)); pendingQuestion = nil }
        }
        return pairs
    }
    private func retry(_ question: String) {
        if let index = messages.lastIndex(where: { $0.role == .client }) { messages.remove(at: index) }
        send(question)
    }
    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }
        let previous = history
        let photo = attachedPhoto
        prompt = ""; error = nil; isLoading = true; inputFocused = false; attachedPhoto = nil
        messages.append(AssistantChatMessage(role: .client, text: question, image: photo))
        let city = store.passport.address
        let fullContext = context.withCity(city)
        Task {
            if let stream = store.streamAssistant(question: question, context: fullContext, history: previous, image: photo) {
                // Claude: the answer appears word by word.
                let answer = AssistantChatMessage(role: .assistant, text: "")
                messages.append(answer)
                streamingID = answer.id
                do {
                    for try await chunk in stream {
                        if let index = messages.firstIndex(where: { $0.id == answer.id }) { messages[index].text += chunk }
                    }
                    Haptics.success()
                } catch {
                    self.error = error.localizedDescription; HelperCenter.shared.failed(error)
                    if let index = messages.firstIndex(where: { $0.id == answer.id }), messages[index].text.isEmpty { messages.remove(at: index) }
                }
                streamingID = nil
            } else {
                do {
                    let reply = try await store.askAssistant(question: question, context: fullContext, history: previous)
                    messages.append(AssistantChatMessage(role: .assistant, text: reply.answer, links: reply.localLinks))
                    Haptics.success()
                } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
            }
            isLoading = false
        }
    }
}

enum VisualizationStyle: String, CaseIterable, Identifiable {
    case object
    case space

    var id: String { rawValue }

    var title: String {
        switch self {
        case .object: return "Объект целиком"
        case .space: return "Детали и окружение"
        }
    }

    var subtitle: String {
        switch self {
        case .object: return "Дом, баня, беседка, кровля, фасад и участок как единый образ."
        case .space: return "Интерьер, мебель, свет, терраса, дорожки и благоустройство."
        }
    }

    var promptHint: String {
        switch self {
        case .object: return "Например: современный одноэтажный дом, тёплый фасад, терраса и озеленение участка."
        case .space: return "Например: светлый интерьер, мебель из дуба, чёрные акценты, дорожки и мягкая подсветка."
        }
    }

    var icon: String {
        switch self {
        case .object: return "house.and.flag.fill"
        case .space: return "square.3.layers.3d.fill"
        }
    }
}

struct AIVisionStudioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var style: VisualizationStyle
    @State private var brief = ""
    @State private var item: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var result: UIImage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var shareFile: SharedFile?
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var savedToPhotos = false
    @State private var addedToProject = false
    @State private var showModels = false

    init(initialStyle: VisualizationStyle = .object) {
        _style = State(initialValue: initialStyle)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Визуализатор объекта", title: "Опишите идею —\nувидьте результат")
                Text("Один запрос, как в чате: выберите сценарий, добавьте фото или снимите объект камерой и опишите пожелания.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                visualPromptComposer
                if store.photorealAvailable || store.picturesByDescriptionAvailable {
                    AIModelsRow(value: store.renderModel.title, title: "Модель ИИ") { showModels = true }
                }
                ApplePlaygroundButton(prompt: brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? style.subtitle : brief) { image in
                    result = image
                    error = nil
                    Haptics.success()
                }

                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Создаём визуализацию").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("ИИ подбирает материалы, свет и композицию…").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelCard(17)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if savedToPhotos {
                    Label("Концепт сохранён в Фото", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }

                if let result {
                    generatedConcept(result)
                }

                InfoNote(text: "Концепт помогает обсудить образ объекта. Реальные материалы, размеры, стоимость и рабочие решения уточняются по проекту и смете.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Визуализация ИИ").helperScreen("Визуализация ИИ").featureIntro(.facade)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, item in Task { await loadPhoto(item) } }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { importImage($0) }
        .sheet(isPresented: $showCamera) { CameraCaptureView(image: $source) }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .sheet(isPresented: $showModels) { NavigationStack { AIModelsView(showsDesign: false) }.presentationDetents([.medium, .large]) }
    }

    private var visualPromptComposer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(VisualizationStyle.allCases) { option in
                        Button {
                            withAnimation(.snappy) { style = option }
                        } label: {
                            Label(option.title, systemImage: option.icon)
                        }
                    }
                } label: {
                    Label(style.title, systemImage: style.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.orange, in: Capsule())
                }

                Spacer(minLength: 0)

                if source != nil {
                    Label("Фото", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(style.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.muted)

            if let source {
                HStack(spacing: 12) {
                    Image(uiImage: source)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 58)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Исходное фото добавлено").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("ИИ сохранит важные особенности объекта.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Button {
                        self.source = nil
                        item = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(Theme.background, in: Circle())
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("Убрать фото")
                }
                .padding(10)
                .background(Theme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 15))
            }

            ZStack(alignment: .topLeading) {
                if brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(style.promptHint)
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $brief)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 102)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
            }

            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    Image(systemName: "camera.fill")
                        .frame(width: 38, height: 38)
                        .background(Theme.background, in: Circle())
                }
                .foregroundStyle(Theme.ink)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityLabel("Снять камерой")

                PhotosPicker(selection: $item, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .frame(width: 38, height: 38)
                        .background(Theme.background, in: Circle())
                }
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Выбрать фото из галереи")

                Button { showFilePicker = true } label: {
                    Image(systemName: "folder")
                        .frame(width: 38, height: 38)
                        .background(Theme.background, in: Circle())
                }
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Выбрать изображение из файлов")

                Spacer(minLength: 0)

                Button { generate() } label: {
                    HStack(spacing: 7) {
                        if isLoading { ProgressView().tint(.black) }
                        else { Image(systemName: "arrow.up").font(.headline.weight(.bold)) }
                        Text(isLoading ? "" : "Создать").font(.subheadline.weight(.bold))
                    }
                    .frame(minWidth: 50, minHeight: 42)
                    .padding(.horizontal, isLoading ? 0 : 13)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.orange, in: Capsule())
                }
                .disabled(isLoading)
                .accessibilityLabel("Создать визуализацию")
            }
        }
        .padding(16)
        .panelCard(22)
    }

    private func generatedConcept(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ВАШ КОНЦЕПТ").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.gold)
                    Text(style.title).font(.headline).foregroundStyle(Theme.ink)
                }
                Spacer()
                Image(systemName: "sparkles").foregroundStyle(Theme.orange)
            }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20))
            HStack(spacing: 10) {
                Button { addToDiary(image) } label: {
                    Label(addedToProject ? "В проекте" : "В проект", systemImage: addedToProject ? "checkmark" : "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(13)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)

                Button { saveToPhotos(image) } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 46, height: 46)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Сохранить в Фото")

                Button { share(image) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 46, height: 46)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PremiumPressStyle())
                .foregroundStyle(Theme.onAccent)
                .accessibilityLabel("Поделиться")
            }
        }
        .padding(15)
        .panelCard(22)
    }


    private func loadPhoto(_ selection: PhotosPickerItem?) async {
        guard let selection else { return }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw VisualizationError.imagePreparation
            }
            source = image
            item = nil
            error = nil
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }

    private func importImage(_ importResult: Result<URL, Error>) {
        do {
            let url = try importResult.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let image = UIImage(data: try Data(contentsOf: url)) else { throw VisualizationError.imagePreparation }
            source = image
            error = nil
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }

    private func generate() {
        error = nil
        savedToPhotos = false
        addedToProject = false
        isLoading = true
        Task {
            do {
                let wishes = brief.trimmingCharacters(in: .whitespacesAndNewlines)
                if let source, store.photorealAvailable {
                    // The server's picture engines edit the source photo.
                    let english = await store.englishPrompt(wishes.isEmpty ? style.subtitle : wishes)
                    let prompt = "Transform this photo into a professional photorealistic architectural visualization. \(english). Keep the same camera angle, perspective and main geometry of the scene. Natural daylight, realistic materials and textures, high detail, magazine-quality architectural photography."
                    result = try await store.photorealRender(source, prompt: prompt).image
                } else if source == nil, store.picturesByDescriptionAvailable {
                    // No photo: a picture by description from the same engines.
                    let english = await store.englishPrompt(wishes.isEmpty ? style.subtitle : wishes)
                    let prompt = "Professional photorealistic architectural visualization: \(english). Realistic materials, natural daylight, every detail rendered, magazine-quality architectural photography, wide-angle lens, no people, no text."
                    result = try await store.pictureByDescription(prompt)
                } else {
                    result = try await store.createVisualization(style: style.rawValue, brief: wishes, source: source)
                }
                store.track("visualization_created")
                store.registerMeaningfulAction()
                Haptics.success()
            } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
            isLoading = false
        }
    }

    private func addToDiary(_ image: UIImage) {
        do {
            try store.addProjectPhoto(image, caption: "ИИ‑концепт: \(style.title.lowercased())")
            error = nil
            addedToProject = true
            Haptics.success()
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { error = "Разрешите приложению сохранять изображения в Фото." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, saveError in
                DispatchQueue.main.async {
                    if success { savedToPhotos = true; error = nil }
                    else { error = saveError?.localizedDescription ?? "Не удалось сохранить изображение." }
                }
            }
        }
    }

    private func share(_ image: UIImage) {
        // Shared concepts carry a discreet app caption.
        guard let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.9) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Концепт-\(Brand.name)-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            shareFile = SharedFile(url: url)
            store.track("visualization_shared")
        } catch let shareError { error = shareError.localizedDescription }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}

struct PrintableEstimateLine {
    let section: String
    let title: String
    let quantity: Double
    let unit: String
    let material: Double?
    let labor: Double?
    let total: Double?
}

struct PrintableEstimate {
    let title: String
    let objectName: String
    let inputs: [String]
    let lines: [PrintableEstimateLine]
    let materialTotal: Double?
    let laborTotal: Double?
    let total: Double?
    let note: String
}

enum EstimatePDFRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let left: CGFloat = 32
    private static let width: CGFloat = 531
    private static let accent = UIColor(red: 0.95, green: 0.42, blue: 0.22, alpha: 1)
    private static let accentDark = UIColor(red: 0.75, green: 0.29, blue: 0.12, alpha: 1)
    private static let columnsX: [CGFloat] = [left, left + 22, left + 210, left + 252, left + 310, left + 385, left + 458]
    private static let columnsWidth: [CGFloat] = [20, 184, 40, 55, 70, 70, 73]
    private static let contentBottom: CGFloat = 770

    static func render(_ estimate: PrintableEstimate) throws -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day()).replacingOccurrences(of: "-", with: "")
        let safeTitle = estimate.objectName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-").prefix(40)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Смета-\(Brand.name)-\(safeTitle.isEmpty ? "объект" : String(safeTitle))-\(stamp).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: estimate.title, kCGPDFContextAuthor as String: Brand.name, kCGPDFContextCreator as String: "Приложение \(Brand.name)"]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        try renderer.writePDF(to: url) { rendererContext in
            var y: CGFloat = 0
            var number = 0
            var pageNumber = 0
            var currentSection = ""
            @discardableResult
            func text(_ value: String, _ rect: CGRect, _ font: UIFont, _ color: UIColor = .black, _ alignment: NSTextAlignment = .left) -> CGFloat {
                let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byWordWrapping
                let attributed = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
                attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            }
            func line(_ from: CGPoint, _ to: CGPoint, _ color: UIColor = UIColor(white: 0.82, alpha: 1), _ widthValue: CGFloat = 0.5) {
                let context = rendererContext.cgContext; context.setStrokeColor(color.cgColor); context.setLineWidth(widthValue); context.move(to: from); context.addLine(to: to); context.strokePath()
            }
            func footer() {
                let footerY = page.height - 46
                line(CGPoint(x: left, y: footerY), CGPoint(x: left + width, y: footerY))
                text("\(Brand.name) · \(Brand.tagline)", CGRect(x: left, y: footerY + 8, width: 440, height: 14), UIFont.systemFont(ofSize: 7), UIColor.darkGray)
                text("Стр. \(pageNumber)", CGRect(x: left + width - 80, y: footerY + 8, width: 80, height: 14), UIFont.systemFont(ofSize: 7), UIColor.darkGray, .right)
            }
            func header(_ continuation: Bool) {
                if pageNumber > 0 { footer() }
                rendererContext.beginPage(); pageNumber += 1; y = 34
                text(Brand.name.uppercased(), CGRect(x: left, y: y, width: 300, height: 20), UIFont.boldSystemFont(ofSize: 14), UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1))
                text(Brand.tagline.uppercased(), CGRect(x: left, y: y + 20, width: 400, height: 16), UIFont.systemFont(ofSize: 8, weight: .semibold), UIColor.darkGray)
                y += 52; line(CGPoint(x: left, y: y), CGPoint(x: left + width, y: y), accent, 1); y += 14
                if continuation { text("Продолжение", CGRect(x: left, y: y, width: width, height: 18), UIFont.boldSystemFont(ofSize: 11)); y += 24 }
            }
            func tableHeader() {
                // Fill first, then draw the white labels on top (previously the fill covered the labels).
                rendererContext.cgContext.setFillColor(UIColor(red: 0.19, green: 0.21, blue: 0.20, alpha: 1).cgColor)
                rendererContext.cgContext.fill(CGRect(x: left, y: y, width: width, height: 26))
                let labels = ["№", "Работы и материалы", "Ед.", "Кол-во", "Материалы", "Работы", "Всего"]
                for index in labels.indices { text(labels[index], CGRect(x: columnsX[index] + 2, y: y + 8, width: columnsWidth[index] - 4, height: 14), UIFont.systemFont(ofSize: 7, weight: .bold), .white, index == 1 ? .left : .center) }
                y += 26
            }
            func money(_ value: Double?) -> String { value.map { CalculationEngine.money($0) } ?? "—" }

            header(false)
            y += text(estimate.title.uppercased(), CGRect(x: left, y: y, width: width, height: 48), UIFont.boldSystemFont(ofSize: 18)) + 6
            y += text("Объект: \(estimate.objectName)\nДата: \(Date().formatted(date: .long, time: .omitted))", CGRect(x: left, y: y, width: 380, height: 32), UIFont.systemFont(ofSize: 9), UIColor.darkGray) + 8
            if !estimate.inputs.isEmpty { y += text(estimate.inputs.joined(separator: " · "), CGRect(x: left, y: y, width: width, height: 60), UIFont.systemFont(ofSize: 8.5), UIColor.darkGray) + 12 }
            tableHeader()
            for row in estimate.lines {
                if row.section != currentSection {
                    currentSection = row.section
                    if y + 50 > contentBottom { header(true); tableHeader() }
                    text(currentSection.uppercased(), CGRect(x: left, y: y + 8, width: width, height: 15), UIFont.systemFont(ofSize: 8, weight: .bold), accentDark)
                    y += 24
                }
                let titleHeight = (row.title as NSString).boundingRect(with: CGSize(width: columnsWidth[1] - 4, height: 120), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: 8)], context: nil).height
                let rowHeight = max(24, ceil(titleHeight) + 12)
                if y + rowHeight > contentBottom { header(true); tableHeader() }
                number += 1
                if number % 2 == 0 {
                    rendererContext.cgContext.setFillColor(UIColor(white: 0.965, alpha: 1).cgColor)
                    rendererContext.cgContext.fill(CGRect(x: left, y: y, width: width, height: rowHeight))
                }
                let values = ["\(number)", row.title, row.unit, CalculationEngine.format(row.quantity), money(row.material), money(row.labor), money(row.total)]
                for index in values.indices { text(values[index], CGRect(x: columnsX[index] + 2, y: y + 6, width: columnsWidth[index] - 4, height: rowHeight - 7), UIFont.systemFont(ofSize: index == 1 ? 8 : 7.2), UIColor.black, index == 1 ? .left : .center) }
                line(CGPoint(x: left, y: y + rowHeight), CGPoint(x: left + width, y: y + rowHeight)); y += rowHeight
            }
            if y + 190 > contentBottom { header(true) }
            y += 18
            let totals = [("Материалы", estimate.materialTotal), ("Работы и техника", estimate.laborTotal), ("НАША ЦЕНА", estimate.total)].filter { $0.1 != nil }
            for (label, amount) in totals {
                let isTotal = label == "НАША ЦЕНА"
                text(label, CGRect(x: 330, y: y, width: 115, height: 18), UIFont.systemFont(ofSize: isTotal ? 10 : 8, weight: isTotal ? .bold : .regular), isTotal ? accentDark : UIColor.darkGray)
                text(money(amount), CGRect(x: 445, y: y - (isTotal ? 1 : 0), width: 118, height: 18), UIFont.systemFont(ofSize: isTotal ? 12 : 8, weight: .bold), .black, .right)
                y += isTotal ? 24 : 18
            }
            y += 10
            y += text(estimate.note, CGRect(x: left, y: y, width: width, height: 60), UIFont.systemFont(ofSize: 7.5), UIColor.darkGray) + 16
            // How to use the estimate: neutral advice, no company contacts.
            let boxHeight: CGFloat = 58
            let box = CGRect(x: left, y: y, width: width, height: boxHeight)
            rendererContext.cgContext.setFillColor(UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1).cgColor)
            rendererContext.cgContext.fill(box)
            text("Как пользоваться сметой", CGRect(x: box.minX + 14, y: box.minY + 12, width: width - 28, height: 16), UIFont.boldSystemFont(ofSize: 10.5))
            text("Покажите её 2–3 подрядчикам и сравните их цены с рыночной оценкой построчно. Объёмы перед закупкой перепроверьте по проекту.", CGRect(x: box.minX + 14, y: box.minY + 30, width: width - 28, height: 28), UIFont.systemFont(ofSize: 8), UIColor.darkGray)
            y += boxHeight + 22
            if y + 20 > contentBottom { header(true) }
            text("Заказчик ____________________    Исполнитель ____________________", CGRect(x: left, y: y, width: width, height: 20), UIFont.systemFont(ofSize: 8), UIColor.darkGray)
            footer()
        }
        return url
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
