import SwiftUI

// MARK: - Market estimate of a design project: every material and work at market prices with sources

struct MarketEstimateSource: Codable, Hashable {
    var title: String
    var url: String
    var price: Double?
}

struct MarketEstimateRow: Codable, Identifiable, Hashable {
    var id: String { name + "|" + kind }
    var name: String
    var kind: String
    var unit: String?
    var quantity: Double?
    var low: Double?
    var typical: Double?
    var high: Double?
    var example: String?
    var sources: [MarketEstimateSource]?
    var missing: Bool?

    var total: Double { (quantity ?? 0) * (typical ?? 0) }
    var totalLow: Double { (quantity ?? 0) * (low ?? typical ?? 0) }
    var totalHigh: Double { (quantity ?? 0) * (high ?? typical ?? 0) }
    var hasPrice: Bool { missing != true && (typical ?? 0) > 0 }
}

struct MarketEstimate: Codable {
    var city: String
    var updatedAt: String
    var items: [MarketEstimateRow]
}

/// What goes to the price search: name, amount and whether it is a material or a work.
struct MarketEstimateRequestItem {
    var name: String
    var kind: String
    var amount: String = ""
    var unit: String = ""
    var quantity: Double = 0
    var dictionary: [String: Any] { ["name": name, "kind": kind, "amount": amount, "unit": unit, "quantity": quantity] }

    /// Materials of the concept and the finishes with areas from the scan, plus the usual works.
    static func items(plan: FloorPlan, proposal: DesignProposal) -> [MarketEstimateRequestItem] {
        let floor = (plan.area * 10).rounded() / 10
        let openings = plan.windows.reduce(0) { $0 + $1.length * $1.height } + plan.doors.reduce(0) { $0 + $1.length * $1.height }
        let walls = max(0, (plan.perimeter * plan.ceilingHeight - openings) * 10).rounded() / 10
        let perimeter = (plan.perimeter * 10).rounded() / 10
        var list: [MarketEstimateRequestItem] = []
        func finish(_ value: DesignFinish, _ surface: String, _ area: Double) {
            guard !value.material.isEmpty, area > 0 else { return }
            list.append(.init(name: "\(value.material) — \(surface)", kind: "material", unit: "м²", quantity: (area * 1.1 * 10).rounded() / 10))
        }
        finish(proposal.floor, "пол", floor)
        finish(proposal.walls, "стены", walls)
        finish(proposal.ceiling, "потолок", floor)
        for material in proposal.materials.prefix(12) where !list.contains(where: { $0.name.hasPrefix(material.name) }) {
            list.append(.init(name: material.name, kind: "material", amount: material.amount))
        }
        list += [
            .init(name: "Подготовка и выравнивание пола", kind: "work", unit: "м²", quantity: floor),
            .init(name: "Укладка напольного покрытия\(proposal.floor.material.isEmpty ? "" : ": \(proposal.floor.material)")", kind: "work", unit: "м²", quantity: floor),
            .init(name: "Шпаклёвка и подготовка стен", kind: "work", unit: "м²", quantity: walls),
            .init(name: "Отделка стен\(proposal.walls.material.isEmpty ? "" : ": \(proposal.walls.material)")", kind: "work", unit: "м²", quantity: walls),
            .init(name: "Отделка потолка\(proposal.ceiling.material.isEmpty ? "" : ": \(proposal.ceiling.material)")", kind: "work", unit: "м²", quantity: floor),
            .init(name: "Монтаж плинтуса", kind: "work", unit: "м.п.", quantity: perimeter),
            .init(name: "Электромонтаж: розетки и выключатели", kind: "work", unit: "шт", quantity: max(4, (plan.perimeter / 3).rounded())),
        ]
        return list
    }
}

struct MarketEstimateView: View {
    @EnvironmentObject private var store: AppStore
    let plan: FloorPlan
    let proposal: DesignProposal
    @State private var estimate: MarketEstimate?
    @State private var loading = false
    @State private var error: String?

    private var rows: [MarketEstimateRow] { estimate?.items ?? [] }
    private var total: Double { rows.reduce(0) { $0 + $1.total } }
    private var low: Double { rows.reduce(0) { $0 + $1.totalLow } }
    private var high: Double { rows.reduce(0) { $0 + $1.totalHigh } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(eyebrow: "Смета по рынку", title: proposal.title)
                if let estimate {
                    totalCard(estimate)
                    section("МАТЕРИАЛЫ", rows.filter { $0.kind == "material" })
                    section("РАБОТЫ", rows.filter { $0.kind == "work" })
                    InfoNote(text: "Цены найдены в магазинах, на маркетплейсах и в прайсах мастеров вашего города: «обычно» — типичная цена, вилка — от недорогих до дорогих предложений. Нажмите на источник, чтобы проверить цену. Количество материалов — с запасом 10%.")
                    ShareLink(item: shareText(estimate)) { SecondaryActionLabel(title: "Отправить смету", icon: "square.and.arrow.up") }
                        .buttonStyle(PremiumPressStyle())
                    PartnerOfferSection(category: "finishing", summary: "Здравствуйте! Смета ремонта «\(plan.name)» по рыночным ценам: около \(CalculationEngine.money(total)). Подскажите вашу цену?")
                } else if loading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Ищем цены в магазинах и у мастеров \(store.projectCity)…").font(.subheadline).foregroundStyle(Theme.muted)
                        Text("Обычно 15–40 секунд. Можно свернуть приложение — пришлём уведомление.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger) }
                    PrimaryButton(title: "Посчитать по рыночным ценам", icon: "magnifyingglass") { Task { await load() } }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Смета по рынку").helperScreen("Смета дизайн‑проекта по рынку", details: estimate.map { shareText($0) } ?? "").featureIntro(.marketEstimate)
        .navigationBarTitleDisplayMode(.inline)
        .task { if estimate == nil && !loading { await load() } }
    }

    private func load() async {
        guard let base = AIServerConfig.marketURL else { error = "Поиск цен работает через сервер приложения — он не подключён в этой сборке."; return }
        loading = true; error = nil
        defer { loading = false }
        do {
            estimate = try await ServerAIClient(base: base).priceEstimate(city: store.projectCity, items: MarketEstimateRequestItem.items(plan: plan, proposal: proposal))
            Haptics.success()
        } catch {
            self.error = error.localizedDescription; HelperCenter.shared.failed(error, action: "Посчитать смету по рынку")
        }
    }

    private func totalCard(_ estimate: MarketEstimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("РЫНОК · \(estimate.city.uppercased())").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
            Text(CalculationEngine.money(total)).font(.system(size: 36, weight: .bold, design: .serif)).monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            if high > low { Text("Вилка: \(CalculationEngine.money(low)) – \(CalculationEngine.money(high))").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85)) }
            let materials = rows.filter { $0.kind == "material" }.reduce(0) { $0 + $1.total }
            HStack { Text("Материалы: \(CalculationEngine.money(materials))"); Spacer(); Text("Работы: \(CalculationEngine.money(total - materials))") }
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
    }

    private func section(_ title: String, _ items: [MarketEstimateRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                Text(title).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(items) { row in MarketEstimateRowCard(row: row) }
            }
        }
    }

    private func shareText(_ estimate: MarketEstimate) -> String {
        var lines = ["СМЕТА ПО РЫНОЧНЫМ ЦЕНАМ · \(plan.name)", "Город: \(estimate.city)", ""]
        for row in estimate.items where row.hasPrice {
            lines.append("\(row.name): \(CalculationEngine.format(row.quantity ?? 0)) \(row.unit ?? "") × \(CalculationEngine.money(row.typical ?? 0)) = \(CalculationEngine.money(row.total))")
        }
        lines += ["", "Итого: \(CalculationEngine.money(total)) (вилка \(CalculationEngine.money(low)) – \(CalculationEngine.money(high)))", "", Brand.shareFooter]
        return lines.joined(separator: "\n")
    }
}

/// One line of the estimate: price per unit, line total, the market range, a product example and sources.
struct MarketEstimateRowCard: View {
    let row: MarketEstimateRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if row.hasPrice { Text(CalculationEngine.money(row.total)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.ink) }
            }
            if row.hasPrice {
                Text("\(CalculationEngine.format(row.quantity ?? 0)) \(row.unit ?? "") × \(CalculationEngine.money(row.typical ?? 0))")
                    .font(.caption).foregroundStyle(Theme.muted)
                rangeBar
                if let example = row.example, !example.isEmpty {
                    Label(example, systemImage: "tag").font(.caption).foregroundStyle(Theme.ink).lineLimit(2)
                }
                if let sources = row.sources, !sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(sources, id: \.url) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        Label(source.title.isEmpty ? (url.host ?? "источник") : source.title, systemImage: "link")
                                            .font(.caption2.weight(.semibold)).lineLimit(1)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Theme.accentTint, in: Capsule()).foregroundStyle(Theme.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Нет надёжных рыночных данных — уточните цену у продавца.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .panelCard(18)
    }

    /// Low — typical — high on one line.
    private var rangeBar: some View {
        let low = row.low ?? row.typical ?? 0, high = row.high ?? row.typical ?? 0, typical = row.typical ?? 0
        let position = high > low ? (typical - low) / (high - low) : 0.5
        return VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panelRaised).frame(height: 6)
                    Capsule().fill(Theme.orangeSoft.opacity(0.5)).frame(height: 6)
                    Circle().fill(Theme.orange).frame(width: 12, height: 12).offset(x: max(0, min(proxy.size.width - 12, proxy.size.width * position - 6)))
                }
            }
            .frame(height: 12)
            HStack {
                Text(CalculationEngine.money(low)); Spacer(); Text("обычно \(CalculationEngine.money(typical))").fontWeight(.semibold); Spacer(); Text(CalculationEngine.money(high))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(Theme.muted)
        }
    }
}
