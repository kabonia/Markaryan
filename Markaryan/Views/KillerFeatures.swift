import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Проверка сметы подрядчика: фото или PDF чужой сметы → сверка с рынком, переплата, чего не хватает

struct QuoteLine: Codable, Identifiable, Hashable {
    var name: String
    var kind: String
    var unit: String
    var quantity: Double
    var price: Double
    var id: String { name + "|" + unit }
    var total: Double { quantity * price }
}

struct QuoteReading: Codable {
    var contractor: String?
    var total: Double?
    var lines: [QuoteLine]
    var possiblyMissing: [String]?
    var notes: String?
}

/// Вердикт по строке: цена подрядчика против рынка города.
struct QuoteVerdict: Identifiable {
    enum Level { case over, fair, cheap, unknown }
    let line: QuoteLine
    let market: MarketEstimateRow?
    var id: String { line.id }
    var marketUnit: Double? { (market?.hasPrice == true) ? market?.typical : nil }
    var level: Level {
        guard let typical = marketUnit, typical > 0, line.price > 0 else { return .unknown }
        let high = market?.high ?? typical * 1.2, low = market?.low ?? typical * 0.85
        if line.price > high * 1.1 { return .over }
        if line.price < low * 0.75 { return .cheap }
        return .fair
    }
    /// Сколько переплата по строке против обычной цены рынка.
    var overpay: Double { level == .over ? max(0, (line.price - (marketUnit ?? line.price)) * line.quantity) : 0 }
    var percent: Int { guard let m = marketUnit, m > 0 else { return 0 }; return Int(((line.price / m) - 1) * 100) }
}

struct QuoteCheckView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pages: [UIImage] = []
    @State private var importingPDF = false
    @State private var stage: String?
    @State private var error: String?
    @State private var reading: QuoteReading?
    @State private var verdicts: [QuoteVerdict] = []
    @State private var city = ""

    private var quoteTotal: Double { reading?.total ?? verdicts.reduce(0) { $0 + $1.line.total } }
    private var marketTotal: Double { verdicts.reduce(0) { $0 + (($1.marketUnit ?? $1.line.price) * $1.line.quantity) } }
    private var overpay: Double { verdicts.reduce(0) { $0 + $1.overpay } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ПРОВЕРКА СМЕТЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.goldLight)
                    Text("Не переплачивайте подрядчику").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.white)
                    Text("Сфотографируйте смету или загрузите PDF. Сверим каждую строку с ценами вашего города — со ссылками на предложения — и покажем, где завышено и что забыли.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if reading == nil { inputCard }
                if let stage {
                    HStack(spacing: 10) { ProgressView(); Text(stage).font(.subheadline).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity).padding(14)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                if let reading { resultView(reading) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Проверка сметы").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in Task { await loadPhotos(items) } }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { loadPDF(url) }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !pages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { i in
                            Image(uiImage: pages[i]).resizable().scaledToFill().frame(width: 80, height: 110).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button { pages.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Theme.danger) }.padding(3)
                                }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                    SecondaryActionLabel(title: "Фото сметы", icon: "camera.fill")
                }
                Button { importingPDF = true } label: { SecondaryActionLabel(title: "PDF", icon: "doc.fill") }
            }
            .buttonStyle(PremiumPressStyle())
            Text("До 4 страниц. Лучше ровно, при хорошем свете.").font(.caption).foregroundStyle(Theme.muted)
            PrimaryButton(title: "Проверить смету", icon: "checkmark.shield") { Task { await check() } }
                .disabled(pages.isEmpty || stage != nil).opacity(pages.isEmpty ? 0.5 : 1)
            HStack(spacing: 6) { PaidNote(kind: "vision"); PaidNote(kind: "priceEstimate10") }
        }
        .padding(16).panelCard(18)
    }

    @ViewBuilder private func resultView(_ reading: QuoteReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reading.contractor.map { "СМЕТА · \($0.uppercased())" } ?? "СМЕТА ПОДРЯДЧИКА").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            HStack {
                PlanStat(value: CalculationEngine.money(quoteTotal), title: "У подрядчика")
                PlanStat(value: CalculationEngine.money(marketTotal), title: "По рынку \(city)")
            }
            if overpay > 0 {
                Label("Переплата ≈ \(CalculationEngine.money(overpay)) (\(Int(overpay / max(1, quoteTotal) * 100)) %) — по \(verdicts.filter { $0.level == .over }.count) позициям", systemImage: "exclamationmark.octagon.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
            } else {
                Label("Цены в рынке — переплаты не нашли", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.success)
            }
            let cheap = verdicts.filter { $0.level == .cheap }.count
            if cheap > 0 { Label("Подозрительно дёшево: \(cheap) поз. — уточните, что входит (материалы, вывоз, гарантия)", systemImage: "questionmark.circle.fill").font(.caption).foregroundStyle(Theme.gold) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)

        ForEach(verdicts.sorted { $0.overpay > $1.overpay }) { v in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(v.line.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    badge(v)
                }
                Text("\(CalculationEngine.format(v.line.quantity)) \(v.line.unit) × \(CalculationEngine.money(v.line.price))" + (v.marketUnit.map { " · рынок \(CalculationEngine.money($0))" } ?? ""))
                    .font(.caption).foregroundStyle(Theme.muted)
                if v.overpay > 0 { Text("Переплата \(CalculationEngine.money(v.overpay))").font(.caption.weight(.semibold)).foregroundStyle(Theme.danger) }
                PriceSourceLinks(sources: v.market?.sources ?? [], hasPrice: v.marketUnit != nil)
            }
            .padding(14).panelCard(16)
        }

        if let missing = reading.possiblyMissing, !missing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ВОЗМОЖНО, ЗАБЫЛИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(missing, id: \.self) { Label($0, systemImage: "plus.circle").font(.footnote) }
                Text("Спросите подрядчика: входит ли это в цену или будет доплатой потом.").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
        }

        ShareLink(item: report(reading)) { SecondaryActionLabel(title: "Отправить разбор", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
        Button { self.reading = nil; verdicts = []; pages = []; pickerItems = [] } label: { SecondaryActionLabel(title: "Проверить другую смету", icon: "arrow.counterclockwise") }
            .buttonStyle(PremiumPressStyle())
        Text("Сверка — ориентир по открытым предложениям магазинов и мастеров. Цена бригады зависит от сложности, сроков и гарантии.").font(.caption2).foregroundStyle(Theme.muted)
    }

    private func badge(_ v: QuoteVerdict) -> some View {
        let (text, color): (String, Color) = switch v.level {
        case .over: ("+\(v.percent) %", Theme.danger)
        case .fair: ("в рынке", Theme.success)
        case .cheap: ("\(v.percent) %", Theme.gold)
        case .unknown: ("нет данных", Theme.muted)
        }
        return Text(text.tr).font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.14), in: Capsule()).foregroundStyle(color)
    }

    private func report(_ reading: QuoteReading) -> String {
        var out = ["ПРОВЕРКА СМЕТЫ\(reading.contractor.map { " · " + $0 } ?? "")",
                   "У подрядчика: \(CalculationEngine.money(quoteTotal)) · по рынку (\(city)): \(CalculationEngine.money(marketTotal))",
                   overpay > 0 ? "Переплата ≈ \(CalculationEngine.money(overpay))" : "Переплаты не нашли", ""]
        for v in verdicts.sorted(by: { $0.overpay > $1.overpay }) {
            let mark = v.level == .over ? "▲ +\(v.percent) %" : v.level == .cheap ? "▼ \(v.percent) %" : v.level == .fair ? "✓" : "?"
            out.append("\(mark) \(v.line.name): \(CalculationEngine.money(v.line.price))/\(v.line.unit)" + (v.marketUnit.map { ", рынок \(CalculationEngine.money($0))" } ?? "") + (v.market?.sources?.first.map { " — \($0.url)" } ?? ""))
        }
        if let missing = reading.possiblyMissing, !missing.isEmpty { out += ["", "Возможно, забыли:"] + missing.map { "• " + $0 } }
        out += ["", Brand.shareFooter]
        return out.joined(separator: "\n")
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { loaded.append(image) } }
        pages = Array((pages + loaded).prefix(4))
    }

    private func loadPDF(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { error = "Не получилось открыть PDF."; return }
        var images: [UIImage] = []
        for index in 0..<min(4, document.pageCount) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1600 / max(bounds.width, bounds.height)
            images.append(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
        }
        pages = Array((pages + images).prefix(4))
    }

    private func check() async {
        guard let base = AIServerConfig.baseURL, let market = AIServerConfig.marketURL else { error = "Проверка работает через сервер приложения."; return }
        error = nil
        city = store.projectCity
        stage = "Читаем смету…"
        defer { stage = nil }
        let schema: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(#"""
        {"type":"object","properties":{
          "contractor":{"type":"string"},
          "total":{"type":"number"},
          "lines":{"type":"array","items":{"type":"object","properties":{
            "name":{"type":"string"},"kind":{"type":"string","enum":["work","material"]},
            "unit":{"type":"string"},"quantity":{"type":"number"},"price":{"type":"number"}},
            "required":["name","kind","unit","quantity","price"]}},
          "possiblyMissing":{"type":"array","items":{"type":"string"}},
          "notes":{"type":"string"}},"required":["lines","possiblyMissing"]}
        """#.utf8))) as? [String: Any] ?? [:]
        let system = """
        Ты — опытный сметчик. На фото — смета или коммерческое предложение подрядчика (ремонт, стройка). Перепиши каждую строку:
        название работы или материала, вид (work/material), единицу (м², м, шт, м³, т, компл.), количество и цену за единицу в рублях.
        Если указана только сумма — цена = сумма / количество. Итог сметы — в total, название фирмы — в contractor.
        В possiblyMissing перечисли 3–8 обычных для такого объёма работ позиций, которых нет в смете (грунтовка, вывоз мусора, расходники, демонтаж…).
        Ничего не выдумывай: нечитаемую строку пропусти. Ответ — на языке пользователя.
        """
        do {
            var turns = pages.map { ClaudeTurn(role: .user, text: "Страница сметы", image: $0) }
            turns.append(ClaudeTurn(role: .user, text: "Перепиши смету по схеме."))
            let data = try await ServerAIClient(base: base).structured(system: system, turns: turns, toolName: "quote", toolDescription: "Строки сметы подрядчика", schema: schema, maxTokens: 8000)
            let parsed = try JSONDecoder().decode(QuoteReading.self, from: data)
            guard !parsed.lines.isEmpty else { error = "Не нашли строк сметы на фото — снимите ровнее и ближе."; return }
            stage = "Сверяем \(parsed.lines.count) позиций с рынком \(city)…"
            let items = parsed.lines.prefix(40).map { MarketEstimateRequestItem(name: $0.name, kind: $0.kind, unit: $0.unit, quantity: $0.quantity) }
            let estimate = try await ServerAIClient(base: market).priceEstimate(city: city, items: Array(items))
            verdicts = parsed.lines.map { line in
                QuoteVerdict(line: line, market: estimate.items.first { $0.name.lowercased() == line.name.lowercased() } ?? estimate.items.first { $0.name.lowercased().hasPrefix(String(line.name.lowercased().prefix(18))) })
            }
            reading = parsed
            Haptics.success()
            store.track("quote_check")
        } catch {
            self.error = error.localizedDescription
            HelperCenter.shared.failed(error, action: "Проверка сметы")
        }
    }
}

// MARK: - Чек → в бюджет: фото чека, сумма сама в факт нужной статьи

struct ReceiptReading: Codable {
    var store: String?
    var date: String?
    var total: Double
    var items: [Item]?
    var category: String?
    struct Item: Codable, Hashable { var name: String; var sum: Double }
}

struct ReceiptScanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var reading: ReceiptReading?
    @State private var category = ""
    @State private var busy = false
    @State private var error: String?
    @State private var added = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Сфотографируйте чек из магазина — сумма сама попадёт в «Потрачено» нужной статьи бюджета объекта. Перерасход будет виден сразу.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                HStack(spacing: 10) {
                    Button { showCamera = true } label: { SecondaryActionLabel(title: "Снять чек", icon: "camera.fill") }
                    PhotosPicker(selection: $pickerItem, matching: .images) { SecondaryActionLabel(title: "Из фото", icon: "photo") }
                }
                .buttonStyle(PremiumPressStyle())
                if busy { HStack(spacing: 10) { ProgressView(); Text("Читаем чек…").foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity) }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                if let reading { resultCard(reading) }
                if reading == nil && photo != nil && !busy {
                    PrimaryButton(title: "Прочитать чек", icon: "text.viewfinder") { Task { await read() } }
                    PaidNote(kind: "vision")
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Чек → в бюджет").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data); reading = nil; added = false } } }
        .fullScreenCover(isPresented: $showCamera) { CameraCaptureView(image: $photo).ignoresSafeArea() }
        .onChange(of: photo) { _, _ in reading = nil; added = false }
    }

    private func resultCard(_ r: ReceiptReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((r.store ?? "ЧЕК").uppercased() + (r.date.map { " · \($0)" } ?? "")).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Text(CalculationEngine.money(r.total)).font(.system(.title, design: .serif, weight: .bold)).monospacedDigit()
            ForEach((r.items ?? []).prefix(8), id: \.self) { item in
                HStack { Text(item.name).font(.caption).lineLimit(1); Spacer(); Text(CalculationEngine.money(item.sum)).font(.caption.monospacedDigit()) }
            }
            Picker("Статья бюджета", selection: $category) {
                ForEach(store.budgetItems.map(\.title), id: \.self) { Text($0.tr).tag($0) }
            }
            .pickerStyle(.menu)
            if added {
                Label("Добавлено в «\(category)» · \(store.projectDisplayName)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.subheadline.weight(.semibold))
                Button("Готово") { dismiss() }.frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "Добавить в «Потрачено»", icon: "plus.circle") { add(r) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    private func add(_ r: ReceiptReading) {
        if let i = store.budgetItems.firstIndex(where: { $0.title == category }) { store.budgetItems[i].actual += r.total.rounded() }
        else { var item = ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: category.isEmpty ? "Отделка" : category); item.actual = r.total.rounded(); store.budgetItems.append(item) }
        store.addDiary("Чек \(r.store ?? ""): \(CalculationEngine.money(r.total)) → «\(category)»")
        added = true
        Haptics.success()
    }

    private func read() async {
        guard let base = AIServerConfig.baseURL, let photo else { error = "Чтение чеков работает через сервер приложения."; return }
        busy = true; error = nil
        defer { busy = false }
        let titles = store.budgetItems.map(\.title).joined(separator: ", ")
        let schema: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(#"""
        {"type":"object","properties":{"store":{"type":"string"},"date":{"type":"string"},"total":{"type":"number"},
          "category":{"type":"string"},
          "items":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"sum":{"type":"number"}},"required":["name","sum"]}}},
          "required":["total"]}
        """#.utf8))) as? [String: Any] ?? [:]
        let system = "На фото — кассовый чек или накладная строительного магазина. Верни магазин, дату (ДД.ММ.ГГГГ), итоговую сумму в рублях, позиции с суммами и одну статью бюджета из списка, к которой относится покупка: \(titles)."
        do {
            let data = try await ServerAIClient(base: base).structured(system: system, turns: [ClaudeTurn(role: .user, text: "Прочитай чек.", image: photo)], toolName: "receipt", toolDescription: "Данные чека", schema: schema, maxTokens: 3000)
            let r = try JSONDecoder().decode(ReceiptReading.self, from: data)
            guard r.total > 0 else { error = "Не нашли итог на чеке — снимите ровнее, чтобы была видна сумма."; return }
            reading = r
            category = store.budgetItems.first { $0.title == r.category }?.title ?? store.budgetItems.first?.title ?? "Отделка"
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Ремонт по фото: без лидара — размеры комнаты по снимку, дальше материалы, цены и визуализация

struct PhotoRoomReading: Codable {
    var room: String?
    var length: Double
    var width: Double
    var height: Double
    var windows: Int?
    var doors: Int?
    var confidence: String?
    var notes: String?
}

struct PhotoRoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var reading: PhotoRoomReading?
    @State private var length = ""
    @State private var width = ""
    @State private var height = ""
    @State private var name = "Комната"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Нет лидара — не беда. Сфотографируйте комнату из угла (1–3 фото, чтобы были видны пол, потолок и дверь). ИИ оценит размеры по двери и потолку, вы поправите цифры — и получите материалы, цены и визуализацию.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(photos.indices, id: \.self) { Image(uiImage: photos[$0]).resizable().scaledToFill().frame(width: 110, height: 140).clipShape(RoundedRectangle(cornerRadius: 12)) } }
                    }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 3, matching: .images) { SecondaryActionLabel(title: photos.isEmpty ? "Выбрать фото комнаты" : "Другие фото", icon: "photo.on.rectangle") }
                    .buttonStyle(PremiumPressStyle())
                if busy { HStack(spacing: 10) { ProgressView(); Text("Оцениваем размеры…").foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity) }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                if reading == nil && !photos.isEmpty && !busy {
                    PrimaryButton(title: "Оценить размеры", icon: "ruler") { Task { await read() } }
                    PaidNote(kind: "vision")
                }
                if let reading { sizesCard(reading) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Ремонт по фото").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in
            Task {
                var loaded: [UIImage] = []
                for item in items { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { loaded.append(image) } }
                photos = loaded; reading = nil
            }
        }
    }

    private func sizesCard(_ r: PhotoRoomReading) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("РАЗМЕРЫ ПО ФОТО").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            TextField("Название", text: $name).padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                field("Длина, м", $length); field("Ширина, м", $width); field("Высота, м", $height)
            }
            Text("Окон: \(r.windows ?? 0) · дверей: \(r.doors ?? 1)" + (r.confidence.map { " · точность: \($0)" } ?? "")).font(.caption).foregroundStyle(Theme.muted)
            if let notes = r.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundStyle(Theme.muted) }
            Label("Это оценка ±5–10 %. Для точной закупки измерьте рулеткой одну стену и поправьте цифру.", systemImage: "ruler").font(.caption).foregroundStyle(Theme.gold)
            PrimaryButton(title: "Создать комнату и посчитать", icon: "arrow.right.circle") { create() }
                .disabled(value(length) < 0.8 || value(width) < 0.8 || value(height) < 1.8)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.tr).font(.caption2).foregroundStyle(Theme.muted)
            TextField("0", text: text).keyboardType(.decimalPad).font(.headline.monospacedDigit())
                .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func value(_ text: String) -> Double { CalculationEngine.parse(text) ?? 0 }

    private func create() {
        let l = Float(value(length)), w = Float(value(width))
        let points: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(l, 0, 0), SIMD3(l, 0, w), SIMD3(0, 0, w)]
        guard let plan = FloorPlanBuilder.fromContour(points, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Комната" : name, ceilingHeight: value(height)) else { return }
        store.floorPlans.append(plan)
        store.track("photo_room_created")
        Haptics.success()
        store.planToOpen = plan.id
        store.tab = 2
        dismiss()
    }

    private func read() async {
        guard let base = AIServerConfig.baseURL else { error = "Работает через сервер приложения."; return }
        busy = true; error = nil
        defer { busy = false }
        let schema: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(#"""
        {"type":"object","properties":{"room":{"type":"string"},"length":{"type":"number"},"width":{"type":"number"},"height":{"type":"number"},
          "windows":{"type":"integer"},"doors":{"type":"integer"},"confidence":{"type":"string"},"notes":{"type":"string"}},
          "required":["length","width","height"]}
        """#.utf8))) as? [String: Any] ?? [:]
        let system = """
        Ты — замерщик. По фото комнаты оцени её размеры в метрах: длину (большая сторона), ширину и высоту потолка.
        Опоры масштаба: межкомнатная дверь 2,0–2,1 м высотой и 0,8 м шириной, розетка 0,3 м от пола, подоконник 0,8–0,9 м,
        плитка 60×60 или 30×30 см, ламинат — доска 19–20 см шириной, типовой потолок 2,5–2,8 м. Сосчитай окна и двери.
        room — тип помещения по‑русски (кухня, санузел, спальня…). confidence — «высокая», «средняя» или «низкая». notes — что мешало, одним предложением.
        """
        do {
            var turns = photos.map { ClaudeTurn(role: .user, text: "Фото комнаты", image: $0) }
            turns.append(ClaudeTurn(role: .user, text: "Оцени размеры комнаты."))
            let data = try await ServerAIClient(base: base).structured(system: system, turns: turns, toolName: "room_size", toolDescription: "Размеры комнаты по фото", schema: schema, maxTokens: 2000)
            let r = try JSONDecoder().decode(PhotoRoomReading.self, from: data)
            reading = r
            length = CalculationEngine.format((r.length * 10).rounded() / 10)
            width = CalculationEngine.format((r.width * 10).rounded() / 10)
            height = CalculationEngine.format((r.height * 100).rounded() / 100)
            if let room = r.room, !room.isEmpty { name = room.prefix(1).uppercased() + room.dropFirst() }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
