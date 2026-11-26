import SwiftUI
import UIKit

// MARK: - Закупка объекта: материалы из всех комнат и расчётов одним списком

struct PurchaseLine: Identifiable, Hashable {
    var name: String
    var quantity: Double
    var unit: String
    var packs: Int?
    var pack: String?
    var from: [String]
    var id: String { name + "|" + unit + "|" + (pack ?? "") }
}

enum ObjectPurchase {
    /// Комнаты, где открывали расчёт материалов, + расчёты из калькуляторов, добавленные в объект. Одинаковое — складывается.
    @MainActor static func lines(store: AppStore) -> [PurchaseLine] {
        var merged: [String: PurchaseLine] = [:]
        func add(_ line: PurchaseLine) {
            if var old = merged[line.id] {
                old.quantity += line.quantity
                if let p = line.packs { old.packs = (old.packs ?? 0) + p }
                old.from += line.from.filter { !old.from.contains($0) }
                merged[line.id] = old
            } else { merged[line.id] = line }
        }
        for plan in store.floorPlans {
            guard let data = UserDefaults.standard.data(forKey: "roomWorks.\(plan.id.uuidString)"),
                  let works = try? JSONDecoder().decode(RoomWorks.self, from: data) else { continue }
            for group in RoomMaterials.calculate(plan, works: works) {
                for l in group.lines { add(PurchaseLine(name: l.name, quantity: l.quantity, unit: l.unit, packs: l.packs, pack: l.pack, from: [plan.name])) }
            }
        }
        if let object = store.activeProjectID {
            for link in ObjectLinks.shared.items(in: object, kind: .calculation) {
                guard let calc = store.calculations.first(where: { $0.id.uuidString == link.itemID }) else { continue }
                for l in calc.result.lines where !["м²", "м", "%", "мм", "°", ""].contains(l.unit) && l.value > 0 {
                    add(PurchaseLine(name: "\(calc.kind.title): \(l.label)", quantity: l.value, unit: l.unit, from: [calc.kind.title]))
                }
            }
        }
        return merged.values.sorted { $0.name < $1.name }
    }

    static func text(_ lines: [PurchaseLine], object: String, bought: Set<String>) -> String {
        var out = ["ЗАКУПКА · \(object.uppercased())"]
        for l in lines {
            let packs = l.packs.map { " → \($0) × \(l.pack ?? "")" } ?? ""
            out.append("\(bought.contains(l.id) ? "✓" : "•") \(l.name): \(CalculationEngine.format((l.quantity * 10).rounded() / 10)) \(l.unit)\(packs)")
        }
        out += ["", Brand.shareFooter]
        return out.joined(separator: "\n")
    }
}

struct ObjectPurchaseView: View {
    @EnvironmentObject private var store: AppStore
    @State private var bought: Set<String> = []
    @State private var prices: MarketEstimate?
    @State private var pricing = false
    @State private var error: String?
    private var key: String { "purchaseBought.\(store.activeProjectID?.uuidString ?? "")" }
    private var lines: [PurchaseLine] { ObjectPurchase.lines(store: store) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Материалы из всех комнат объекта (где открыт «Расчёт материалов») и из расчётов, добавленных в объект. Одинаковое сложено. Отмечайте купленное.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if lines.isEmpty {
                    InfoNote(text: "Пока пусто. Откройте «Материалы, цены и визуализация» в комнате или добавьте расчёт калькулятора в объект.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            Button { toggle(line) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: bought.contains(line.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                                        .foregroundStyle(bought.contains(line.id) ? Theme.success : Theme.muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.name.tr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).strikethrough(bought.contains(line.id))
                                        if let packs = line.packs, let pack = line.pack { Text("Купить: \(packs) × \(pack.tr)").font(.caption.weight(.semibold)).foregroundStyle(Theme.orange) }
                                        Text(line.from.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text("\(CalculationEngine.format((line.quantity * 10).rounded() / 10)) \(line.unit.tr)").font(.subheadline.weight(.bold).monospacedDigit())
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16).panelCard(16)
                    Text("Куплено \(bought.intersection(Set(lines.map(\.id))).count) из \(lines.count)").font(.caption).foregroundStyle(Theme.muted)
                    ShareLink(item: ObjectPurchase.text(lines, object: store.projectDisplayName, bought: bought)) { SecondaryActionLabel(title: "Отправить список", icon: "square.and.arrow.up") }
                        .buttonStyle(PremiumPressStyle())
                    if let prices { priceCard(prices) } else {
                        PrimaryButton(title: pricing ? "Ищем цены…" : "Цены в вашем городе — со ссылками", icon: "rublesign.circle") { Task { await findPrices() } }
                            .disabled(pricing)
                        PaidNote(kind: "priceEstimate10")
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Закупка объекта").navigationBarTitleDisplayMode(.inline).featureIntro(.purchase)
        .onAppear { bought = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    }

    private func toggle(_ line: PurchaseLine) {
        if bought.contains(line.id) { bought.remove(line.id) } else { bought.insert(line.id); Haptics.tap() }
        UserDefaults.standard.set(Array(bought), forKey: key)
    }

    private func priceCard(_ estimate: MarketEstimate) -> some View {
        let total = estimate.items.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 10) {
            Text("ЦЕНЫ · \(estimate.city.uppercased())").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            VariantsRow(low: estimate.items.reduce(0) { $0 + $1.totalLow }, typical: total, high: estimate.items.reduce(0) { $0 + $1.totalHigh })
            ForEach(estimate.items) { row in
                HStack { Text(row.name).font(.footnote); Spacer(); Text(row.hasPrice ? CalculationEngine.money(row.total) : "—").font(.footnote.weight(.semibold).monospacedDigit()) }
                PriceSourceLinks(sources: row.sources ?? [], hasPrice: row.hasPrice)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
    }

    private func findPrices() async {
        guard let base = AIServerConfig.marketURL else { return }
        pricing = true; error = nil
        defer { pricing = false }
        let items = lines.map { l -> MarketEstimateRequestItem in
            if let packs = l.packs, let pack = l.pack { return MarketEstimateRequestItem(name: "\(l.name) (\(pack))", kind: "material", unit: "шт", quantity: Double(packs)) }
            return MarketEstimateRequestItem(name: l.name, kind: "material", unit: l.unit, quantity: (l.quantity * 10).rounded() / 10)
        }
        do { prices = try await ServerAIClient(base: base).priceEstimate(city: store.projectCity, items: Array(items.prefix(40))); Haptics.success() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Эконом / средний / премиум

/// Три варианта одной закупки или сметы: дешёвые предложения рынка, обычные и дорогие.
struct VariantsRow: View {
    let low: Double
    let typical: Double
    let high: Double
    var body: some View {
        HStack(spacing: 8) {
            variant("Эконом", low, Theme.sage)
            variant("Средний", typical, Theme.orange)
            variant("Премиум", high, Theme.gold)
        }
    }
    private func variant(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.tr).font(.caption2.weight(.bold)).foregroundStyle(color)
            Text(CalculationEngine.money(value)).font(.subheadline.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Смета → план работ и бюджет объекта

struct EstimateToObjectButtons: View {
    @EnvironmentObject private var store: AppStore
    let result: DocEstimateResult
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { toBudget() } label: { SecondaryActionLabel(title: "В бюджет объекта", icon: "chart.pie") }.buttonStyle(PremiumPressStyle())
                Button { toTasks() } label: { SecondaryActionLabel(title: "План работ", icon: "checklist") }.buttonStyle(PremiumPressStyle())
            }
            if let done { Label(done, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.success) }
            else if !store.inObject { Text("Сейчас без объекта — бюджет и задачи попадут в «Без объекта». Выберите объект на главной.").font(.caption2).foregroundStyle(Theme.muted) }
        }
    }

    /// Каждый раздел сметы — строка бюджета (план), повторное нажатие обновляет сумму, а не дублирует.
    private func toBudget() {
        for section in result.sections where section.total > 0 {
            let id = "estimate-\(section.title)"
            if let index = store.budgetItems.firstIndex(where: { $0.id == id }) {
                store.budgetItems[index].planned = section.total.rounded()
            } else {
                var item = ProjectBudgetItem(id: id, title: section.title)
                item.planned = section.total.rounded()
                store.budgetItems.append(item)
            }
        }
        done = "Разделы сметы добавлены в бюджет «\(store.projectDisplayName)»"
        Haptics.success()
    }

    /// Разделы сметы по порядку — задачи со сроками по неделе на раздел.
    private func toTasks() {
        var date = Calendar.current.startOfDay(for: Date())
        let existing = Set(store.projectTasks.map(\.title))
        for section in result.sections where !existing.contains(section.title) {
            date = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
            store.projectTasks.append(ProjectTask(title: section.title, dueDate: date, notes: "Из сметы «\(result.title)»: \(CalculationEngine.money(section.total))"))
        }
        done = "План работ: \(result.sections.count) этапов в задачах объекта"
        Haptics.success()
    }
}

// MARK: - Ссылка для подрядчика

struct ContractorLinkButton: View {
    let title: String
    let text: () -> String
    var images: () -> [UIImage] = { [] }
    @State private var busy = false
    @State private var link: SharedLink?
    @State private var error: String?
    struct SharedLink: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { Task { await make() } } label: {
                SecondaryActionLabel(title: busy ? "Готовим ссылку…" : "Ссылка для подрядчика", icon: "link.badge.plus")
            }
            .buttonStyle(PremiumPressStyle()).disabled(busy)
            if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            else { Text("Откроется в браузере без приложения: размеры, смета и картинки. Действует 30 дней.").font(.caption2).foregroundStyle(Theme.muted) }
        }
        .sheet(item: $link) { item in ActivityShareSheet(items: [item.url]) }
    }

    private func make() async {
        guard let base = AIServerConfig.marketURL else { error = "Нет связи с сервером.".tr; return }
        busy = true; error = nil
        defer { busy = false }
        var request = URLRequest(url: base.appendingPathComponent("v1/share"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let pictures = images().prefix(4).compactMap { SupportCenter.jpeg($0)?.base64EncodedString() }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title, "text": text(), "images": pictures])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            guard (response as? HTTPURLResponse)?.statusCode == 200, let value = json["url"] as? String, let url = URL(string: value) else {
                error = (json["error"] as? String) ?? "Не получилось сделать ссылку.".tr; return
            }
            link = SharedLink(url: url)
            Haptics.success()
        } catch { self.error = "Нет интернета.".tr }
    }
}

// MARK: - Комплект объекта: всё одним PDF

@MainActor enum ObjectKit {
    /// Текст для подрядчика и для PDF: объект, комнаты, материалы, обмеры, сметы, бюджет.
    static func text(store: AppStore) -> String {
        var out = [store.projectDisplayName.uppercased()]
        if !store.passport.address.isEmpty { out.append(store.passport.address) }
        if !store.floorPlans.isEmpty {
            out += ["", "КОМНАТЫ"]
            for plan in store.floorPlans {
                out.append("\(plan.name): пол \(CalculationEngine.format((plan.area * 10).rounded() / 10)) м², периметр \(CalculationEngine.format((plan.perimeter * 10).rounded() / 10)) м, потолок \(CalculationEngine.format((plan.ceilingHeight * 100).rounded() / 100)) м")
            }
        }
        let purchase = ObjectPurchase.lines(store: store)
        if !purchase.isEmpty {
            out += ["", "МАТЕРИАЛЫ"]
            out += purchase.map { l in "\(l.name): \(CalculationEngine.format((l.quantity * 10).rounded() / 10)) \(l.unit)" + (l.packs.map { " (\($0) × \(l.pack ?? ""))" } ?? "") }
        }
        if let object = store.activeProjectID {
            for kind in [ObjectLinks.Kind.houseScan, .docEstimate, .calculation] {
                let items = ObjectLinks.shared.items(in: object, kind: kind)
                if !items.isEmpty { out += ["", kind.title.uppercased()] + items.map { "\($0.title)\($0.subtitle.map { " — " + $0 } ?? "")" } }
            }
        }
        let budget = store.budgetItems.filter { $0.included && $0.planned > 0 }
        if !budget.isEmpty {
            out += ["", "БЮДЖЕТ"] + budget.map { "\($0.title): план \(CalculationEngine.money($0.planned))" + ($0.actual > 0 ? ", факт \(CalculationEngine.money($0.actual))" : "") }
            out.append("Итого план: \(CalculationEngine.money(store.budgetPlanned))")
        }
        let profile = ProposalProfileStore.shared.profile
        if !profile.company.isEmpty { out += ["", "Подготовил: \(profile.company)\(profile.phone.isEmpty ? "" : ", " + profile.phone)"] }
        return out.joined(separator: "\n")
    }

    /// Картинки объекта: визуализации, добавленные в объект, и планы комнат.
    static func pictures(store: AppStore) -> [UIImage] {
        var list: [UIImage] = []
        if let object = store.activeProjectID {
            list += ObjectLinks.shared.items(in: object, kind: .picture).compactMap { ObjectPictures.load($0.itemID) }
        }
        for plan in store.floorPlans {
            if let look = RoomLookStore.load(plan.id) { list.append(look) }
            list.append(DrawingsPDF.planPicture(plan: plan, proposal: plan.proposals.last, furniture: true))
        }
        return list
    }

    static func pdf(store: AppStore) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let text = text(store: store)
        let images = pictures(store: store).prefix(12)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y: CGFloat = 0
            func newPage() { ctx.beginPage(); y = margin }
            func ensure(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }
            // Обложка
            ctx.beginPage()
            UIColor(red: 0.04, green: 0.26, blue: 0.21, alpha: 1).setFill()
            UIRectFill(page)
            let gold = UIColor(red: 0.90, green: 0.78, blue: 0.53, alpha: 1)
            ("КОМПЛЕКТ ОБЪЕКТА" as NSString).draw(at: CGPoint(x: margin, y: 220), withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: gold, .kern: 3])
            (store.projectDisplayName as NSString).draw(in: CGRect(x: margin, y: 245, width: page.width - 2 * margin, height: 120),
                                                        withAttributes: [.font: UIFont(name: "Georgia-Bold", size: 34) ?? UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.white])
            let sub = [store.passport.address, Date().formatted(date: .long, time: .omitted), ProposalProfileStore.shared.profile.company].filter { !$0.isEmpty }.joined(separator: " · ")
            (sub as NSString).draw(in: CGRect(x: margin, y: 380, width: page.width - 2 * margin, height: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: gold])
            (Brand.name as NSString).draw(at: CGPoint(x: margin, y: page.height - 60), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: gold])
            // Картинки по две на страницу
            for image in images {
                let w = page.width - 2 * margin
                let h = min(360, w * image.size.height / max(1, image.size.width))
                if y == 0 { newPage() }
                ensure(h + 12)
                image.draw(in: CGRect(x: margin, y: y, width: w, height: h))
                y += h + 16
            }
            // Текст
            newPage()
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor(red: 0.09, green: 0.14, blue: 0.12, alpha: 1)]
            let head: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: UIColor(red: 0.58, green: 0.44, blue: 0.16, alpha: 1)]
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                let isHead = line == line.uppercased() && line.count > 3 && line.rangeOfCharacter(from: .letters) != nil
                let attrs = isHead ? head : body
                let rect = (line as NSString).boundingRect(with: CGSize(width: page.width - 2 * margin, height: 1000), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                ensure(rect.height + (isHead ? 10 : 3))
                if isHead { y += 8 }
                (line as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - 2 * margin, height: rect.height + 2), withAttributes: attrs)
                y += rect.height + 3
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Объект — \(store.projectDisplayName).pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }
}

/// В разделе «Объекты»: закупка, комплект PDF и ссылка для подрядчика.
struct ObjectToolsSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var kit: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ВЕСЬ ОБЪЕКТ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            NavigationLink { ObjectPurchaseView() } label: {
                AppTabRow(icon: "cart.fill", title: "Закупка объекта", subtitle: "Материалы всех комнат и расчётов одним списком, с ценами и отметкой «куплено»")
            }
            .buttonStyle(PremiumCardPressStyle())
            Button { if let url = ObjectKit.pdf(store: store) { kit = SharedFile(url: url); Haptics.success() } } label: {
                AppTabRow(icon: "doc.richtext.fill", title: "Комплект объекта (PDF)", subtitle: "Картинки, планы, размеры, материалы, сметы и бюджет — одним файлом")
            }
            .buttonStyle(PremiumCardPressStyle())
            ContractorLinkButton(title: store.projectDisplayName, text: { ObjectKit.text(store: store) }, images: { Array(ObjectKit.pictures(store: store).prefix(4)) })
        }
        .sheet(item: $kit) { file in ActivityShareSheet(items: [file.url]) }
    }
}
