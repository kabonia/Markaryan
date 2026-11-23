import Foundation
import UIKit
import PDFKit
import UserNotifications

// MARK: - «Смета по документам»: models of the server's answer

struct DocPrice: Codable, Hashable {
    var low: Double = 0
    var typical: Double = 0
    var high: Double = 0
    var example: String? = nil
    var sources: [MarketEstimateSource]? = nil
    var missing: Bool? = nil
    /// No reliable market offer: the price auditor's expert price.
    var estimated: Bool? = nil
    /// Searched again after the price auditor found a problem.
    var rechecked: Bool? = nil
    var note: String? = nil
    var hasPrice: Bool { missing != true && typical > 0 }
}

struct DocResource: Codable, Hashable, Identifiable {
    var id: String { name + "|" + unit }
    var name: String
    var unit: String
    var norm: Double? = nil
    var waste: Double? = nil
    var quantity: Double
    var price: DocPrice? = nil
    var sum: Double? = nil
}

struct DocWork: Codable, Hashable, Identifiable {
    var id: String
    var section: String
    var name: String
    var unit: String
    var quantity: Double
    var basis: String? = nil
    var confidence: String? = nil
    var added: Bool? = nil
    var price: DocPrice? = nil
    var materials: [DocResource] = []
    var machines: [DocResource] = []
    var laborSum: Double? = nil
    var sum: Double? = nil
}

struct DocRange: Codable, Hashable { var low: Double = 0; var typical: Double = 0; var high: Double = 0 }

struct DocSection: Codable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var works: DocRange
    var materials: DocRange
    var machines: DocRange
    var items: [DocWork]
    var total: Double { works.typical + materials.typical + machines.typical }
}

struct DocTotals: Codable, Hashable {
    var works: Double = 0
    var materials: Double = 0
    var machines: Double = 0
    var delivery: Double = 0
    var contingency: Double = 0
    var subtotal: Double = 0
    var vat: Double = 0
    var total: Double = 0
}

struct DocPurchase: Codable, Hashable, Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var unit: String
    var quantity: Double
    var price: DocPrice? = nil
}

struct DocIssue: Codable, Hashable { var severity: String; var text: String }

struct DocEstimateResult: Codable, Hashable {
    struct Totals: Codable, Hashable { var typical: DocTotals; var low: DocTotals; var high: DocTotals }
    struct Options: Codable, Hashable { var vat: Bool = false; var vatPct: Double = 22; var deliveryPct: Double = 4; var contingencyPct: Double = 5 }
    struct Audit: Codable, Hashable { var verdict: String = ""; var issues: [DocIssue] = []; var added: Int = 0; var pricesChecked: Int? = nil; var pricesFixed: Int? = nil }
    struct ObjectInfo: Codable, Hashable { var name: String? = nil; var type: String? = nil; var area: Double? = nil; var floors: Double? = nil; var summary: String? = nil }
    struct Source: Codable, Hashable { var name: String; var kind: String; var pages: Int }

    var title: String
    var city: String
    var createdAt: String
    var object: ObjectInfo? = nil
    var sections: [DocSection]
    var materials: [DocPurchase] = []
    var machines: [DocPurchase] = []
    var totals: Totals
    var options: Options? = nil
    var assumptions: [String]? = nil
    var discrepancies: [String]? = nil
    var audit: Audit? = nil
    var sources: [Source]? = nil
    var unpriced: Int? = nil
}

struct DocJobStatus: Decodable {
    var id: String
    var status: String
    var stage: String?
    var stageTitle: String?
    var progress: Double?
    var error: String?
    var result: DocEstimateResult?
}

/// What the person attaches: a PDF (pages rendered to pictures + its text layer), photos of sheets or a text file.
enum DocKind: String, CaseIterable, Identifiable, Codable {
    case ar, kr, tz, smeta, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ar: "АР — архитектура"
        case .kr: "КР — конструктив"
        case .tz: "ТЗ"
        case .smeta: "Смета / ВОР на проверку"
        case .other: "Другое (ОВ, ВК, ЭОМ…)"
        }
    }
    var short: String {
        switch self {
        case .ar: "АР"
        case .kr: "КР"
        case .tz: "ТЗ"
        case .smeta: "Смета"
        case .other: "Другое"
        }
    }
    /// A guess from the file name: «АР», «КЖ», «ТЗ», «смета»…
    static func guess(_ name: String) -> DocKind {
        let n = name.lowercased()
        if n.contains("смет") || n.contains("вор") || n.contains("ведомост") { return .smeta }
        if n.contains("тз") || n.contains("задани") { return .tz }
        if n.contains("кж") || n.contains("кр") || n.contains("км") || n.contains("конструк") || n.contains("фундам") { return .kr }
        if n.contains("ар") || n.contains("архит") || n.contains("план") || n.contains("фасад") { return .ar }
        return .other
    }
}

struct DocPage { var image: Data; var text: String }

struct DocAttachment: Identifiable {
    let id = UUID()
    var name: String
    var kind: DocKind
    var pages: [DocPage] = []
    var text: String = ""
    /// Excel workbook (.xlsx) as is: the server reads every sheet.
    var xlsx: Data? = nil
    var preview: UIImage? = nil
    var summary: String { xlsx != nil ? "таблица Excel · \(ByteCountFormatter.string(fromByteCount: Int64(xlsx?.count ?? 0), countStyle: .file))" : pages.isEmpty ? "текст · \(text.count) зн." : "\(pages.count) \(pages.count == 1 ? "лист" : (2...4).contains(pages.count % 10) && !(12...14).contains(pages.count % 100) ? "листа" : "листов")" }

    static let maxPages = 40

    /// PDF: every page as a JPEG (long side ~2000 px — dimensions stay readable) plus the text of the page.
    static func fromPDF(_ url: URL, kind: DocKind? = nil, pageBudget: Int) -> DocAttachment? {
        guard let document = PDFDocument(url: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        var item = DocAttachment(name: name, kind: kind ?? DocKind.guess(name))
        for index in 0..<min(document.pageCount, max(0, pageBudget)) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2000 / max(bounds.width, bounds.height), 3)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if index == 0 { item.preview = page.thumbnail(of: CGSize(width: 160, height: 160), for: .mediaBox) }
            if let jpeg = image.jpegData(compressionQuality: 0.6) { item.pages.append(DocPage(image: jpeg, text: page.string ?? "")) }
        }
        return item.pages.isEmpty ? nil : item
    }

    static func fromImage(_ image: UIImage, name: String, kind: DocKind) -> DocAttachment? {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 2200 / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.65) else { return nil }
        return DocAttachment(name: name, kind: kind, pages: [DocPage(image: jpeg, text: "")], preview: resized)
    }

    var payload: [String: Any] {
        var item: [String: Any] = ["name": name, "kind": kind.rawValue, "text": text,
                                   "pages": pages.map { ["image": $0.image.base64EncodedString(), "text": $0.text] }]
        if let xlsx { item["xlsx"] = xlsx.base64EncodedString() }
        return item
    }
}

// MARK: - Jobs: created on the server, followed while the app is open, long-polled in the background

@MainActor
final class DocEstimateCenter: ObservableObject {
    static let shared = DocEstimateCenter()

    struct Running: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var startedAt: Date
        var stage: String = "queued"
        var stageTitle: String = "В очереди"
        var progress: Double = 0
        var error: String? = nil
    }

    struct Saved: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var city: String
        var total: Double
        var date: Date
    }

    @Published private(set) var running: [Running] = []
    @Published private(set) var saved: [Saved] = []
    private var followers: [String: Task<Void, Never>] = [:]

    private static let runningKey = "doc-estimate-running"
    private static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("doc-estimates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.runningKey), let list = try? JSONDecoder().decode([Running].self, from: data) { running = list }
        if let data = try? Data(contentsOf: Self.folder.appendingPathComponent("index.json")), let list = try? JSONDecoder().decode([Saved].self, from: data) { saved = list }
    }

    func resumeAll() { for job in running where job.error == nil { follow(job.id) } }

    func result(_ id: String) -> DocEstimateResult? {
        guard let data = try? Data(contentsOf: Self.folder.appendingPathComponent("\(id).json")) else { return nil }
        return try? JSONDecoder().decode(DocEstimateResult.self, from: data)
    }

    func delete(_ id: String) {
        saved.removeAll { $0.id == id }
        running.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(id).json"))
        persist()
    }

    /// Sends everything to the server and starts following the job.
    func start(title: String, city: String, text: String, docs: [DocAttachment], options: DocEstimateResult.Options) async throws -> String {
        guard let base = AIServerConfig.marketURL else { throw DocEstimateError.noServer }
        let body: [String: Any] = [
            "title": title, "city": city, "text": text, "docs": docs.map(\.payload),
            "options": ["vat": options.vat, "deliveryPct": options.deliveryPct, "contingencyPct": options.contingencyPct],
        ]
        var request = Self.request(base, "v1/ai/smeta", timeout: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = try Self.decode(data, response)
        running.insert(Running(id: status.id, title: title.isEmpty ? "Смета" : title, startedAt: Date()), at: 0)
        persist()
        BackgroundAI.askForNotificationsOnce()
        follow(status.id)
        return status.id
    }

    func follow(_ id: String) {
        guard followers[id] == nil, let base = AIServerConfig.marketURL else { return }
        followers[id] = Task { [weak self] in
            // Progress for the screen while the app is open…
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    if UIApplication.shared.applicationState == .active,
                       let answer = try? await URLSession.shared.data(for: Self.request(base, "v1/ai/smeta/\(id)", timeout: 20)),
                       let status = try? Self.decode(answer.0, answer.1) {
                        await self?.apply(status)
                        if status.status != "running" { return }
                    }
                    try? await Task.sleep(for: .seconds(4))
                }
            }
            // …and the end through the background session: iOS keeps the request while the app is minimised.
            var attempts = 0
            while !Task.isCancelled, attempts < 30 {
                attempts += 1
                var wait = Self.request(base, "v1/ai/smeta/\(id)/wait", timeout: 300)
                wait.httpMethod = "POST"
                wait.setValue("application/json", forHTTPHeaderField: "Content-Type")
                wait.httpBody = Data("{}".utf8)
                do {
                    let (data, response) = try await BackgroundAI.shared.send(wait, title: "Смета по документам")
                    let status = try Self.decode(data, response)
                    await self?.apply(status)
                    if status.status != "running" { break }
                } catch {
                    if let error = error as? DocEstimateError, case .server = error { await self?.fail(id, error.localizedDescription); break }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            progress.cancel()
            await MainActor.run { self?.followers[id] = nil }
        }
    }

    private func apply(_ status: DocJobStatus) {
        guard let index = running.firstIndex(where: { $0.id == status.id }) else { return }
        if status.status == "done", let result = status.result {
            if let data = try? JSONEncoder().encode(result) { try? data.write(to: Self.folder.appendingPathComponent("\(status.id).json"), options: .atomic) }
            let job = running.remove(at: index)
            saved.removeAll { $0.id == status.id }
            saved.insert(Saved(id: status.id, title: job.title, city: result.city, total: result.totals.typical.total, date: Date()), at: 0)
            Haptics.success()
        } else if status.status == "failed" {
            running[index].error = status.error ?? "Не удалось посчитать смету."
            HelperCenter.shared.failed(DocEstimateError.server(running[index].error ?? ""), action: "Смета по документам")
        } else {
            running[index].stage = status.stage ?? running[index].stage
            running[index].stageTitle = status.stageTitle ?? running[index].stageTitle
            running[index].progress = status.progress ?? running[index].progress
        }
        persist()
    }

    private func fail(_ id: String, _ message: String) {
        guard let index = running.firstIndex(where: { $0.id == id }) else { return }
        running[index].error = message
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(running) { UserDefaults.standard.set(data, forKey: Self.runningKey) }
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: Self.folder.appendingPathComponent("index.json"), options: .atomic) }
    }

    nonisolated private static func request(_ base: URL, _ path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = timeout
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated private static func decode(_ data: Data, _ response: URLResponse) throws -> DocJobStatus {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw DocEstimateError.server(message ?? "Сервер ответил с ошибкой \(code).")
        }
        return try JSONDecoder().decode(DocJobStatus.self, from: data)
    }
}

enum DocEstimateError: LocalizedError {
    case noServer
    case server(String)
    var errorDescription: String? {
        switch self {
        case .noServer: "Смета по документам считается на сервере приложения — он не подключён в этой сборке."
        case .server(let message): message
        }
    }
}

// MARK: - Export: PDF (as an estimator hands it over) and a table for Excel

enum DocEstimateExport {
    static func csv(_ r: DocEstimateResult) -> URL? {
        func cell(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func n(_ x: Double) -> String { String(format: "%.2f", x).replacingOccurrences(of: ".", with: ",") }
        var rows = ["№;Раздел;Наименование;Ед.;Кол-во;Цена за ед., ₽;Сумма, ₽;Обоснование"]
        for section in r.sections {
            for w in section.items {
                rows.append([w.id, section.title, "Работа: " + w.name, w.unit, n(w.quantity), n(w.price?.typical ?? 0), n(w.laborSum ?? 0), w.basis ?? ""].map(cell).joined(separator: ";"))
                for m in w.materials { rows.append(["", section.title, "  Материал: " + m.name, m.unit, n(m.quantity), n(m.price?.typical ?? 0), n(m.sum ?? 0), "норма \(n(m.norm ?? 0)) + \(n(m.waste ?? 0))% отходов"].map(cell).joined(separator: ";")) }
                for m in w.machines { rows.append(["", section.title, "  Техника: " + m.name, m.unit, n(m.quantity), n(m.price?.typical ?? 0), n(m.sum ?? 0), ""].map(cell).joined(separator: ";")) }
            }
        }
        let t = r.totals.typical
        rows += ["", ";;Работы;;;;\(n(t.works))", ";;Материалы;;;;\(n(t.materials))", ";;Техника;;;;\(n(t.machines))", ";;Доставка материалов;;;;\(n(t.delivery))", ";;Непредвиденные;;;;\(n(t.contingency))"]
        if t.vat > 0 { rows.append(";;НДС;;;;\(n(t.vat))") }
        rows.append(";;ИТОГО;;;;\(n(t.total))")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Смета-\(safe(r.title)).csv")
        // BOM: Excel opens Cyrillic correctly.
        guard (try? (Data([0xEF, 0xBB, 0xBF]) + Data(rows.joined(separator: "\r\n").utf8)).write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    static func pdf(_ r: DocEstimateResult) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape
        let margin: CGFloat = 32
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Смета-\(safe(r.title)).pdf")
        let columns: [(String, CGFloat, NSTextAlignment)] = [("№", 40, .left), ("Наименование работ и материалов", 330, .left), ("Ед.", 50, .center), ("Кол-во", 70, .right), ("Цена, ₽", 90, .right), ("Сумма, ₽", 100, .right), ("Основание", 98, .left)]
        let ink = UIColor(red: 0.11, green: 0.16, blue: 0.15, alpha: 1)
        let accent = UIColor(red: 0.067, green: 0.525, blue: 0.416, alpha: 1)
        let muted = UIColor(red: 0.37, green: 0.42, blue: 0.40, alpha: 1)
        func attrs(_ size: CGFloat, _ weight: UIFont.Weight = .regular, _ color: UIColor = ink, _ align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping
            return [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        }
        func money(_ x: Double) -> String { CalculationEngine.money(x).replacingOccurrences(of: " ₽", with: "") }
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { context in
                var y: CGFloat = 0
                var pageNumber = 0
                func newPage() {
                    context.beginPage(); pageNumber += 1; y = margin
                    ("\(Brand.name) · Смета «\(r.title)» · \(r.city)" as NSString).draw(at: CGPoint(x: margin, y: page.height - 22), withAttributes: attrs(7, .regular, muted))
                    ("стр. \(pageNumber)" as NSString).draw(at: CGPoint(x: page.width - margin - 30, y: page.height - 22), withAttributes: attrs(7, .regular, muted))
                }
                func ensure(_ h: CGFloat) { if y + h > page.height - margin - 14 { newPage(); header() } }
                func header() {
                    var x = margin
                    UIColor(red: 0.84, green: 0.92, blue: 0.89, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: page.width - margin * 2, height: 18))
                    for c in columns { (c.0 as NSString).draw(in: CGRect(x: x + 3, y: y + 4, width: c.1 - 6, height: 12), withAttributes: attrs(7, .semibold, ink, c.2)); x += c.1 }
                    y += 20
                }
                func row(_ values: [String], size: CGFloat = 7.5, weight: UIFont.Weight = .regular, color: UIColor = ink) {
                    let heights = zip(values, columns).map { v, c in (v as NSString).boundingRect(with: CGSize(width: c.1 - 6, height: 400), options: .usesLineFragmentOrigin, attributes: attrs(size, weight), context: nil).height }
                    let h = (heights.max() ?? 10) + 5
                    ensure(h)
                    var x = margin
                    for (v, c) in zip(values, columns) { (v as NSString).draw(in: CGRect(x: x + 3, y: y + 2, width: c.1 - 6, height: h), withAttributes: attrs(size, weight, color, c.2)); x += c.1 }
                    UIColor(white: 0, alpha: 0.06).setFill(); UIRectFill(CGRect(x: margin, y: y + h, width: page.width - margin * 2, height: 0.5))
                    y += h + 1
                }
                newPage()
                ("ЛОКАЛЬНЫЙ СМЕТНЫЙ РАСЧЁТ ПО РЫНОЧНЫМ ЦЕНАМ" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(9, .bold, accent)); y += 16
                (r.title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(18, .bold)); y += 26
                var meta = "Город: \(r.city) · Дата: \(String(r.createdAt.prefix(10)))"
                if let s = r.sources, !s.isEmpty { meta += " · Документы: " + s.map { "\($0.name) (\($0.kind.uppercased()), \($0.pages) л.)" }.joined(separator: ", ") }
                (meta as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: 30), withAttributes: attrs(8, .regular, muted)); y += 22
                let t = r.totals.typical
                ("ИТОГО: \(CalculationEngine.money(t.total))   ·   рынок: \(CalculationEngine.money(r.totals.low.total)) – \(CalculationEngine.money(r.totals.high.total))" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(12, .bold, accent)); y += 24
                header()
                for (index, section) in r.sections.enumerated() {
                    ensure(30)
                    row(["\(index + 1)", section.title.uppercased(), "", "", "", money(section.total), ""], size: 8, weight: .bold, color: accent)
                    for w in section.items {
                        row([w.id, (w.added == true ? "[доб. проверкой] " : "") + w.name, w.unit, CalculationEngine.format(w.quantity), money(w.price?.typical ?? 0), money(w.laborSum ?? 0), (w.basis ?? "") + (w.price?.estimated == true ? " · экспертная цена" : "")], weight: .semibold)
                        for m in w.materials { row(["", "   " + m.name, m.unit, CalculationEngine.format(m.quantity), money(m.price?.typical ?? 0), money(m.sum ?? 0), "норма \(CalculationEngine.format(m.norm ?? 0)), отх. \(CalculationEngine.format(m.waste ?? 0))%"], size: 7, color: muted) }
                        for m in w.machines { row(["", "   ⚙ " + m.name, m.unit, CalculationEngine.format(m.quantity), money(m.price?.typical ?? 0), money(m.sum ?? 0), ""], size: 7, color: muted) }
                    }
                }
                ensure(150)
                y += 8
                var lines: [(String, Double)] = [("Работы", t.works), ("Материалы", t.materials), ("Машины и механизмы", t.machines), ("Доставка и разгрузка материалов (\(CalculationEngine.format(r.options?.deliveryPct ?? 4))%)", t.delivery), ("Непредвиденные расходы (\(CalculationEngine.format(r.options?.contingencyPct ?? 5))%)", t.contingency)]
                if t.vat > 0 { lines.append(("НДС \(CalculationEngine.format(r.options?.vatPct ?? 22))%", t.vat)) }
                lines.append(("ВСЕГО ПО СМЕТЕ", t.total))
                for (i, line) in lines.enumerated() {
                    let last = i == lines.count - 1
                    (line.0 as NSString).draw(at: CGPoint(x: page.width - margin - 420, y: y), withAttributes: attrs(last ? 11 : 9, last ? .bold : .regular))
                    (CalculationEngine.money(line.1) as NSString).draw(in: CGRect(x: page.width - margin - 160, y: y, width: 160, height: 16), withAttributes: attrs(last ? 11 : 9, last ? .bold : .semibold, last ? accent : ink, .right))
                    y += last ? 18 : 14
                }
                if let audit = r.audit, !audit.verdict.isEmpty || !audit.issues.isEmpty {
                    ensure(60); y += 10
                    ("ЗАКЛЮЧЕНИЕ ПРОВЕРКИ" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(9, .bold, accent)); y += 14
                    for text in [audit.verdict] + audit.issues.map({ "• " + $0.text }) where !text.isEmpty {
                        let h = (text as NSString).boundingRect(with: CGSize(width: page.width - margin * 2, height: 400), options: .usesLineFragmentOrigin, attributes: attrs(8), context: nil).height + 4
                        ensure(h); (text as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: h), withAttributes: attrs(8)); y += h
                    }
                }
                if let assumptions = r.assumptions, !assumptions.isEmpty {
                    ensure(40); y += 8
                    ("ДОПУЩЕНИЯ" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(9, .bold, accent)); y += 14
                    for text in assumptions.map({ "• " + $0 }) {
                        let h = (text as NSString).boundingRect(with: CGSize(width: page.width - margin * 2, height: 400), options: .usesLineFragmentOrigin, attributes: attrs(8), context: nil).height + 4
                        ensure(h); (text as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: h), withAttributes: attrs(8, .regular, muted)); y += h
                    }
                }
                ensure(30); y += 10
                ("Цены — рыночные предложения магазинов, маркетплейсов и подрядчиков города на дату расчёта (ссылки — в приложении). Объёмы сняты с документов ИИ‑агентами и сверены двумя независимыми чтениями. Смета не заменяет проектно‑сметную документацию по ГрК РФ." as NSString)
                    .draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: 40), withAttributes: attrs(7, .regular, muted))
            }
            return url
        } catch { return nil }
    }

    private static func safe(_ s: String) -> String { String(s.prefix(40)).replacingOccurrences(of: "/", with: "-") }
}
