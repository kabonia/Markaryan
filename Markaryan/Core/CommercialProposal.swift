import SwiftUI
import UIKit

// MARK: - Реквизиты исполнителя (шапка коммерческого предложения)

/// The person's own company for the header of a commercial proposal. Empty — the proposal goes out under «СметаПро».
/// Stored only on this iPhone. The layout of the document does not change, only the data in it.
struct ProposalProfile: Codable, Equatable {
    var company = ""          // ООО «Ромашка» / ИП Иванов Иван Иванович
    var inn = ""
    var kpp = ""
    var ogrn = ""             // ОГРН / ОГРНИП
    var address = ""
    var phone = ""
    var email = ""
    var website = ""
    var signerName = ""       // Иванов И. И.
    var signerPosition = "Генеральный директор"
    var bankName = ""
    var account = ""          // р/с
    var corrAccount = ""      // к/с
    var bik = ""
    var paymentTerms = "Аванс 30 % — до начала работ, далее — поэтапно по актам выполненных работ."
    var warranty = "Гарантия на выполненные работы — 24 месяца с даты подписания акта."
    var validityDays = 14
    var hasLogo = false

    var isFilled: Bool { !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {}

    // Every field is optional when reading: a later version may add fields without losing what was saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProposalProfile.blank
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        company = v(.company, d.company); inn = v(.inn, d.inn); kpp = v(.kpp, d.kpp); ogrn = v(.ogrn, d.ogrn)
        address = v(.address, d.address); phone = v(.phone, d.phone); email = v(.email, d.email); website = v(.website, d.website)
        signerName = v(.signerName, d.signerName); signerPosition = v(.signerPosition, d.signerPosition)
        bankName = v(.bankName, d.bankName); account = v(.account, d.account); corrAccount = v(.corrAccount, d.corrAccount); bik = v(.bik, d.bik)
        paymentTerms = v(.paymentTerms, d.paymentTerms); warranty = v(.warranty, d.warranty)
        validityDays = v(.validityDays, d.validityDays); hasLogo = v(.hasLogo, d.hasLogo)
    }

    private static let blank = ProposalProfile()
}

final class ProposalProfileStore: ObservableObject {
    static let shared = ProposalProfileStore()
    private static let key = "proposal.profile.v1"

    @Published var profile: ProposalProfile { didSet { save() } }

    private init() {
        profile = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ProposalProfile.self, from: $0) } ?? ProposalProfile()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    private static var logoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("proposal-logo.png")
    }

    var logo: UIImage? { profile.hasLogo ? UIImage(contentsOfFile: Self.logoURL.path) : nil }

    /// Logo for the header: kept at most 600 px on the long side (sharp in print, light in the PDF).
    func setLogo(_ image: UIImage?) {
        guard let image else {
            try? FileManager.default.removeItem(at: Self.logoURL)
            profile.hasLogo = false
            return
        }
        let scale = min(1, 600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        if let data = resized.pngData(), (try? data.write(to: Self.logoURL, options: .atomic)) != nil {
            profile.hasLogo = true
            objectWillChange.send()
        }
    }
}

/// What is asked for one proposal right before it is made.
struct ProposalDetails {
    var number: String
    var client = ""
    var address = ""
    var term = ""
    /// Works with their materials line by line; off — materials as one sum per section.
    var detailed = true

    static func defaultNumber(for r: DocEstimateResult, date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "yyMMdd"
        let tail = (r.title + r.createdAt).unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        return "КП-\(f.string(from: date))-\(String(format: "%03d", tail))"
    }
}

// MARK: - Сумма прописью

enum RussianAmount {
    /// «Один миллион двести тысяч рублей 00 копеек».
    static func words(_ value: Double) -> String {
        let kopecks = Int((max(value, 0) * 100).rounded())
        let rubles = kopecks / 100, kop = kopecks % 100
        var text = rubles == 0 ? "ноль" : spell(rubles)
        text = text.prefix(1).uppercased() + text.dropFirst()
        return "\(text) \(plural(rubles, "рубль", "рубля", "рублей")) \(String(format: "%02d", kop)) \(plural(kop, "копейка", "копейки", "копеек"))"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n100 = n % 100, n10 = n % 10
        if (11...14).contains(n100) { return many }
        if n10 == 1 { return one }
        if (2...4).contains(n10) { return few }
        return many
    }

    private static let unitsM = ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
    private static let unitsF = ["", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
    private static let teens = ["десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"]
    private static let tens = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто"]
    private static let hundreds = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот"]

    private static func triad(_ n: Int, feminine: Bool) -> [String] {
        var out: [String] = []
        let h = n / 100, t = (n / 10) % 10, u = n % 10
        if h > 0 { out.append(hundreds[h]) }
        if t == 1 {
            out.append(teens[u])
        } else {
            if t > 1 { out.append(tens[t]) }
            if u > 0 { out.append(feminine ? unitsF[u] : unitsM[u]) }
        }
        return out
    }

    private static func spell(_ n: Int) -> String {
        var parts: [String] = []
        let b = n / 1_000_000_000, m = (n / 1_000_000) % 1000, th = (n / 1000) % 1000, u = n % 1000
        if b > 0 { parts += triad(b, feminine: false) + [plural(b, "миллиард", "миллиарда", "миллиардов")] }
        if m > 0 { parts += triad(m, feminine: false) + [plural(m, "миллион", "миллиона", "миллионов")] }
        if th > 0 { parts += triad(th, feminine: true) + [plural(th, "тысяча", "тысячи", "тысяч")] }
        if u > 0 { parts += triad(u, feminine: false) }
        return parts.joined(separator: " ")
    }
}

// MARK: - PDF: коммерческое предложение + Приложение № 1 (смета)

enum CommercialProposalPDF {
    static func make(_ r: DocEstimateResult, profile: ProposalProfile, logo: UIImage?, details: ProposalDetails, date: Date = Date()) -> URL? {
        // Two passes: the first counts the pages, so the footer can say «стр. 2 из 5».
        let first = render(r, profile: profile, logo: logo, details: details, date: date, totalPages: 0)
        let data = render(r, profile: profile, logo: logo, details: details, date: date, totalPages: first.pages).data
        let name = "\(details.number) — \(String(r.title.prefix(40)))".replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static func render(_ r: DocEstimateResult, profile: ProposalProfile, logo: UIImage?, details: ProposalDetails, date: Date, totalPages: Int) -> (data: Data, pages: Int) {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Коммерческое предложение \(details.number)",
            kCGPDFContextAuthor as String: profile.isFilled ? profile.company : Brand.name,
            kCGPDFContextCreator as String: Brand.name,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: ProposalLayout.page, format: format)
        var pages = 0
        let data = renderer.pdfData { context in
            let layout = ProposalLayout(context: context, result: r, profile: profile, logo: logo, details: details, date: date, totalPages: totalPages)
            layout.draw()
            pages = layout.pageNumber
        }
        return (data, pages)
    }
}

private final class ProposalLayout {
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
    private let margin: CGFloat = 42
    private var width: CGFloat { Self.page.width - margin * 2 }
    private var bottom: CGFloat { Self.page.height - margin - 22 }

    // «Изумруд с золотом» — the app's palette on white paper.
    private let ink = UIColor(red: 0.086, green: 0.141, blue: 0.122, alpha: 1)
    private let emerald = UIColor(red: 0.059, green: 0.420, blue: 0.333, alpha: 1)
    private let gold = UIColor(red: 0.580, green: 0.435, blue: 0.157, alpha: 1)
    private let muted = UIColor(red: 0.400, green: 0.392, blue: 0.361, alpha: 1)
    private let goldTint = UIColor(red: 0.965, green: 0.925, blue: 0.835, alpha: 1)
    private let emeraldTint = UIColor(red: 0.867, green: 0.929, blue: 0.898, alpha: 1)
    private let ivory = UIColor(red: 0.972, green: 0.964, blue: 0.945, alpha: 1)
    private let hairline = UIColor(white: 0, alpha: 0.10)

    private let context: UIGraphicsPDFRendererContext
    private let r: DocEstimateResult
    private let profile: ProposalProfile
    private let logo: UIImage?
    private let details: ProposalDetails
    private let date: Date
    private let totalPages: Int

    private(set) var pageNumber = 0
    private var y: CGFloat = 0
    /// Drawn again at the top of a new page while a table is running.
    private var repeatHeader: (() -> Void)?

    init(context: UIGraphicsPDFRendererContext, result: DocEstimateResult, profile: ProposalProfile, logo: UIImage?, details: ProposalDetails, date: Date, totalPages: Int) {
        self.context = context; self.r = result; self.profile = profile; self.logo = logo
        self.details = details; self.date = date; self.totalPages = totalPages
    }

    // MARK: Data

    private var companyName: String { profile.isFilled ? profile.company.trimmed : Brand.name }
    private var totals: DocTotals { r.totals.typical }
    private var vat: Bool { (r.options?.vat ?? false) && totals.vat > 0 }
    private var dateText: String { Self.longDate(date) }
    private var anyEstimated: Bool {
        r.sections.contains { s in s.items.contains { $0.price?.estimated == true || $0.materials.contains { $0.price?.estimated == true } } }
    }

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM yyyy 'г.'"
        return f.string(from: d)
    }

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU"); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        f.groupingSeparator = "\u{00A0}"; f.decimalSeparator = ","
        return f
    }()
    private func money(_ x: Double) -> String { Self.moneyFormatter.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x) }
    private func rub(_ x: Double) -> String { money(x) + "\u{00A0}₽" }

    // MARK: Text

    private func serif(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: d, size: size)
    }
    private func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: size, weight: weight) }

    private func attrs(_ font: UIFont, _ color: UIColor, _ align: NSTextAlignment = .left, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping; p.lineSpacing = 1.5
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        if kern != 0 { a[.kern] = kern }
        return a
    }
    private func height(_ s: String, _ a: [NSAttributedString.Key: Any], _ w: CGFloat) -> CGFloat {
        ceil((s as NSString).boundingRect(with: CGSize(width: w, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: a, context: nil).height)
    }
    @discardableResult
    private func text(_ s: String, x: CGFloat, y top: CGFloat, w: CGFloat, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
        let h = height(s, a, w)
        (s as NSString).draw(with: CGRect(x: x, y: top, width: w, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: a, context: nil)
        return h
    }
    private func line(_ x: CGFloat, _ yy: CGFloat, _ w: CGFloat, _ color: UIColor, _ thickness: CGFloat = 0.5) {
        color.setFill(); UIRectFill(CGRect(x: x, y: yy, width: w, height: thickness))
    }
    private func eyebrow(_ s: String) {
        ensure(30)
        text(s.uppercased(), x: margin, y: y, w: width, attrs(sans(8, .bold), gold, kern: 1.4))
        y += 14
    }

    // MARK: Pages

    private func newPage() {
        context.beginPage()
        pageNumber += 1
        footer()
        if pageNumber > 1 {
            runningHeader()
            y = margin + 28
        } else {
            y = margin
        }
    }

    private func ensure(_ h: CGFloat) {
        if y + h > bottom {
            newPage()
            repeatHeader?()
        }
    }

    private func footer() {
        let yy = Self.page.height - margin + 2
        line(margin, yy - 6, width, hairline)
        let left: String
        if profile.isFilled {
            left = [companyName, profile.phone.trimmed, profile.email.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
        } else {
            left = "Подготовлено в приложении \(Brand.name)"
        }
        text(left, x: margin, y: yy, w: width - 90, attrs(sans(7), muted))
        let pages = totalPages > 0 ? "Стр. \(pageNumber) из \(totalPages)" : "Стр. \(pageNumber)"
        text(pages, x: margin + width - 90, y: yy, w: 90, attrs(sans(7), muted, .right))
    }

    private func runningHeader() {
        text(companyName, x: margin, y: margin, w: width / 2, attrs(sans(7.5, .semibold), muted))
        text("Коммерческое предложение № \(details.number) от \(dateText)", x: margin + width / 2, y: margin, w: width / 2, attrs(sans(7.5), muted, .right))
        line(margin, margin + 14, width, gold, 0.6)
    }

    // MARK: Document

    func draw() {
        newPage()
        letterhead()
        titleBlock()
        parties()
        intro()
        costBox()
        compositionTable()
        conditions()
        signatures()
        appendix()
    }

    private func letterhead() {
        let mark: UIImage? = profile.isFilled ? logo : UIImage(named: "BrandMark")
        var textX = margin
        let box = CGRect(x: margin, y: y, width: 58, height: 58)
        if let mark {
            let s = min(box.width / mark.size.width, box.height / mark.size.height)
            let rect = CGRect(x: box.minX, y: box.minY + (box.height - mark.size.height * s) / 2, width: mark.size.width * s, height: mark.size.height * s)
            if profile.isFilled {
                mark.draw(in: rect)
            } else if let g = UIGraphicsGetCurrentContext() {
                g.saveGState(); UIBezierPath(roundedRect: rect, cornerRadius: 12).addClip(); mark.draw(in: rect); g.restoreGState()
            }
            textX = margin + 72
        }
        let w = margin + width - textX
        var ty = y + 2
        ty += text(companyName, x: textX, y: ty, w: w, attrs(serif(17), ink)) + 3
        var lines: [String] = []
        if profile.isFilled {
            let legal = [profile.inn.trimmed.isEmpty ? "" : "ИНН \(profile.inn.trimmed)",
                         profile.kpp.trimmed.isEmpty ? "" : "КПП \(profile.kpp.trimmed)",
                         profile.ogrn.trimmed.isEmpty ? "" : (profile.ogrn.trimmed.count > 13 ? "ОГРНИП \(profile.ogrn.trimmed)" : "ОГРН \(profile.ogrn.trimmed)")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            lines = [legal, profile.address.trimmed,
                     [profile.phone.trimmed, profile.email.trimmed, profile.website.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")]
        } else {
            lines = [Brand.tagline]
        }
        for l in lines where !l.isEmpty { ty += text(l, x: textX, y: ty, w: w, attrs(sans(8), muted)) + 1 }
        y = max(y + 58, ty) + 12
        line(margin, y, width, gold, 1.2)
        line(margin, y + 2.6, width, gold, 0.4)
        y += 24
    }

    private func titleBlock() {
        y += text("КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ", x: margin, y: y, w: width, attrs(serif(21), emerald, kern: 0.8)) + 4
        y += text("№ \(details.number) от \(dateText)", x: margin, y: y, w: width, attrs(sans(10), muted)) + 18
    }

    private func parties() {
        var rows: [(String, String)] = [
            ("Заказчик", details.client.trimmed.isEmpty ? "________________________________" : details.client.trimmed),
            ("Объект", r.title),
            ("Адрес объекта", details.address.trimmed.isEmpty ? "г. \(r.city)" : details.address.trimmed),
            ("Исполнитель", companyName),
        ]
        if !details.term.trimmed.isEmpty { rows.append(("Срок выполнения работ", details.term.trimmed)) }
        let keyW: CGFloat = 132
        for (key, value) in rows {
            let h = max(height(value, attrs(sans(10, .semibold), ink), width - keyW), 13) + 7
            ensure(h)
            text(key, x: margin, y: y + 1, w: keyW - 8, attrs(sans(9), muted))
            text(value, x: margin + keyW, y: y, w: width - keyW, attrs(sans(10, .semibold), ink))
            y += h
            line(margin, y - 3, width, hairline)
        }
        y += 12
    }

    private func intro() {
        let s = "Благодарим за интерес к сотрудничеству. Предлагаем выполнить работы по объекту «\(r.title)» на условиях, изложенных ниже. "
            + "Стоимость рассчитана по рыночным ценам на работы, материалы и технику в г. \(r.city) на дату предложения; "
            + "подробная смета с объёмами и ценами приведена в Приложении № 1."
        let a = attrs(sans(10), ink)
        ensure(height(s, a, width) + 16)
        y += text(s, x: margin, y: y, w: width, a) + 16
    }

    private func costRows() -> [(String, Double)] {
        let t = totals
        var rows: [(String, Double)] = [("Работы", t.works), ("Материалы", t.materials)]
        if t.machines > 0.5 { rows.append(("Техника и механизмы", t.machines)) }
        if t.delivery > 0.5 {
            let percent = r.options?.deliveryAsPercent ?? true
            rows.append((percent ? "Доставка материалов (\(CalculationEngine.format(r.options?.deliveryPct ?? 4)) % от стоимости)" : "Доставка материалов", t.delivery))
        }
        if t.contingency > 0.5 { rows.append(("Непредвиденные расходы (\(CalculationEngine.format(r.options?.contingencyPct ?? 5)) %)", t.contingency)) }
        if vat {
            rows.append(("Итого без НДС", t.subtotal))
            rows.append(("НДС \(CalculationEngine.format(r.options?.vatPct ?? 22)) %", t.vat))
        }
        return rows
    }

    private func costBox() {
        let rows = costRows()
        let inner = width - 36
        let words = "Сумма прописью: \(RussianAmount.words(totals.total))\(vat ? ", в том числе НДС" : ", без НДС")."
        let wordsH = height(words, attrs(sans(8.5), muted), inner)
        let h = 34 + CGFloat(rows.count) * 17 + 12 + 30 + wordsH + 14
        ensure(h + 16)
        let rect = CGRect(x: margin, y: y, width: width, height: h)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        goldTint.setFill(); path.fill()
        gold.withAlphaComponent(0.55).setStroke(); path.lineWidth = 0.6; path.stroke()
        var yy = y + 14
        text("СТОИМОСТЬ РАБОТ", x: margin + 18, y: yy, w: inner, attrs(sans(8, .bold), gold, kern: 1.4))
        yy += 20
        for (label, value) in rows {
            text(label, x: margin + 18, y: yy, w: inner - 150, attrs(sans(9.5), ink))
            text(rub(value), x: margin + 18 + inner - 150, y: yy, w: 150, attrs(sans(9.5, .semibold), ink, .right))
            yy += 17
        }
        line(margin + 18, yy + 3, inner, gold.withAlphaComponent(0.5), 0.6)
        yy += 12
        text(vat ? "ИТОГО, включая НДС" : "ИТОГО", x: margin + 18, y: yy + 4, w: inner - 200, attrs(serif(13), ink))
        text(rub(totals.total), x: margin + 18 + inner - 220, y: yy, w: 220, attrs(serif(19), emerald, .right))
        yy += 30
        text(words, x: margin + 18, y: yy, w: inner, attrs(sans(8.5), muted))
        y += h + 22
    }

    private func compositionTable() {
        eyebrow("Состав работ по разделам")
        let cols: [(String, CGFloat, NSTextAlignment)] = [("№", 24, .left), ("Раздел", width - 24 - 76 * 3 - 86, .left), ("Работы", 76, .right), ("Материалы", 76, .right), ("Техника", 76, .right), ("Всего, ₽", 86, .right)]
        let head = { [self] in tableHeader(cols) }
        head()
        repeatHeader = head
        for (i, s) in r.sections.enumerated() {
            tableRow(cols, ["\(i + 1)", s.title, money(s.works.typical), money(s.materials.typical), money(s.machines.typical), money(s.total)], font: sans(8.5), color: ink)
        }
        tableRow(cols, ["", "Итого по разделам", money(r.sections.reduce(0) { $0 + $1.works.typical }), money(r.sections.reduce(0) { $0 + $1.materials.typical }),
                        money(r.sections.reduce(0) { $0 + $1.machines.typical }), money(r.sections.reduce(0) { $0 + $1.total })], font: sans(8.5, .bold), color: ink, fill: ivory)
        repeatHeader = nil
        y += 6
        let note = "Доставка, непредвиденные расходы\(vat ? " и НДС" : "") начисляются сверху — см. «Стоимость работ»."
        y += text(note, x: margin, y: y, w: width, attrs(sans(7.5), muted)) + 18
    }

    private func conditions() {
        eyebrow("Условия")
        let validUntil = Calendar.current.date(byAdding: .day, value: max(profile.validityDays, 1), to: date) ?? date
        var rows: [(String, String)] = [("Срок действия предложения", "\(max(profile.validityDays, 1)) дн. — до \(Self.longDate(validUntil))")]
        if !details.term.trimmed.isEmpty { rows.append(("Сроки выполнения", details.term.trimmed)) }
        if !profile.paymentTerms.trimmed.isEmpty { rows.append(("Порядок оплаты", profile.paymentTerms.trimmed)) }
        if !profile.warranty.trimmed.isEmpty { rows.append(("Гарантия", profile.warranty.trimmed)) }
        rows.append(("Цены", "в рублях\(vat ? ", включая НДС" : ", без НДС"); материалы — с учётом норм расхода и отходов, по рыночным ценам г. \(r.city). Окончательная стоимость фиксируется в договоре."))
        if !profile.account.trimmed.isEmpty {
            let bank = ["р/с \(profile.account.trimmed)", profile.bankName.trimmed.isEmpty ? "" : "в \(profile.bankName.trimmed)",
                        profile.bik.trimmed.isEmpty ? "" : "БИК \(profile.bik.trimmed)", profile.corrAccount.trimmed.isEmpty ? "" : "к/с \(profile.corrAccount.trimmed)"]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            rows.append(("Банковские реквизиты", bank))
        }
        let keyW: CGFloat = 150
        for (key, value) in rows {
            let a = attrs(sans(9), ink)
            let h = max(height(value, a, width - keyW), 12) + 7
            ensure(h)
            text(key, x: margin, y: y, w: keyW - 10, attrs(sans(9, .semibold), ink))
            text(value, x: margin + keyW, y: y, w: width - keyW, a)
            y += h
        }
        y += 18
    }

    private func signatures() {
        ensure(118)
        let colW = (width - 30) / 2
        let top = y
        func block(_ x: CGFloat, _ title: String, _ lines: [String]) {
            var yy = top
            yy += text(title.uppercased(), x: x, y: yy, w: colW, attrs(sans(8, .bold), gold, kern: 1.4)) + 6
            for l in lines { yy += text(l, x: x, y: yy, w: colW, attrs(sans(9), ink)) + 8 }
        }
        let signer = profile.signerName.trimmed.isEmpty ? "________________" : profile.signerName.trimmed
        let position = profile.isFilled ? (profile.signerPosition.trimmed.isEmpty ? "Руководитель" : profile.signerPosition.trimmed) : "Исполнитель"
        block(margin, "Исполнитель", [companyName, position, "______________ / \(signer) /", "М.П."])
        block(margin + colW + 30, "Заказчик", ["С предложением ознакомлен(а)", "", "______________ / ________________ /", "«____» ______________ 20___ г."])
        y = top + 118
    }

    // MARK: Приложение № 1

    private func appendix() {
        newPage()
        text("ПРИЛОЖЕНИЕ № 1", x: margin, y: y, w: width, attrs(sans(8, .bold), gold, kern: 1.4))
        y += 13
        y += text("к коммерческому предложению № \(details.number) от \(dateText)", x: margin, y: y, w: width, attrs(sans(8.5), muted)) + 8
        y += text("Смета: \(r.title)", x: margin, y: y, w: width, attrs(serif(16), ink)) + 4
        var meta = "г. \(r.city)"
        if let s = r.sources, !s.isEmpty { meta += " · по документам: " + s.map { "\($0.name) (\($0.kind.uppercased()), \($0.pages) л.)" }.joined(separator: ", ") }
        y += text(meta, x: margin, y: y, w: width, attrs(sans(8), muted)) + 14

        let cols: [(String, CGFloat, NSTextAlignment)] = [("№", 30, .left), ("Наименование работ и материалов", width - 30 - 40 - 54 - 74 - 86, .left), ("Ед.", 40, .center), ("Кол-во", 54, .right), ("Цена, ₽", 74, .right), ("Сумма, ₽", 86, .right)]
        let head = { [self] in tableHeader(cols) }
        head()
        repeatHeader = head
        for (i, s) in r.sections.enumerated() {
            ensure(40)
            tableRow(cols, ["\(i + 1)", s.title.uppercased(), "", "", "", ""], font: sans(8.5, .bold), color: emerald, fill: emeraldTint.withAlphaComponent(0.45))
            for w in s.items {
                let star = w.price?.estimated == true ? "*" : ""
                tableRow(cols, [w.id, w.name, w.unit, CalculationEngine.format(w.quantity), money(w.price?.typical ?? 0) + star, money(w.laborSum ?? 0)], font: sans(8.5), color: ink)
                if details.detailed {
                    for m in w.materials {
                        let mStar = m.price?.estimated == true ? "*" : ""
                        tableRow(cols, ["", "— \(m.name)", m.unit, CalculationEngine.format(m.quantity), money(m.price?.typical ?? 0) + mStar, money(m.sum ?? 0)], font: sans(7.5), color: muted)
                    }
                    for m in w.machines {
                        tableRow(cols, ["", "— техника: \(m.name)", m.unit, CalculationEngine.format(m.quantity), money(m.price?.typical ?? 0), money(m.sum ?? 0)], font: sans(7.5), color: muted)
                    }
                }
            }
            if !details.detailed && s.materials.typical > 0.5 {
                tableRow(cols, ["", "Материалы по разделу", "", "", "", money(s.materials.typical)], font: sans(8.5), color: ink)
            }
            if !details.detailed && s.machines.typical > 0.5 && s.title != "Техника и доставка" {
                tableRow(cols, ["", "Техника по разделу", "", "", "", money(s.machines.typical)], font: sans(8.5), color: ink)
            }
            tableRow(cols, ["", "Итого по разделу «\(s.title)»", "", "", "", money(s.total)], font: sans(8.5, .bold), color: ink, fill: ivory)
        }
        repeatHeader = nil
        y += 14

        // Totals again, under the table.
        let rows = costRows() + [(vat ? "ИТОГО, включая НДС" : "ИТОГО", totals.total)]
        ensure(CGFloat(rows.count) * 16 + 40)
        let labelW: CGFloat = 300, valueW: CGFloat = 130
        let x0 = margin + width - labelW - valueW
        for (i, row) in rows.enumerated() {
            let last = i == rows.count - 1
            if last { line(x0, y + 1, labelW + valueW, gold, 0.8); y += 6 }
            text(row.0, x: x0, y: y, w: labelW - 10, attrs(last ? serif(12) : sans(9), ink))
            text(rub(row.1), x: x0 + labelW, y: y, w: valueW, attrs(last ? serif(13) : sans(9, .semibold), last ? emerald : ink, .right))
            y += last ? 20 : 15
        }
        y += text("\(RussianAmount.words(totals.total))\(vat ? ", в том числе НДС" : ", без НДС").", x: x0, y: y, w: labelW + valueW, attrs(sans(8), muted)) + 18

        // Notes.
        var notes = (r.assumptions ?? []).filter { !$0.trimmed.isEmpty }
        if anyEstimated { notes.append("* — цена экспертной оценки: конкретное предложение со ссылкой на дату расчёта не найдено.") }
        notes.append("Расчёт выполнен по рыночным ценам на дату предложения. Документ является коммерческим предложением и не заменяет проектно‑сметную документацию по Градостроительному кодексу РФ.")
        eyebrow("Примечания")
        for n in notes {
            let s = "•  \(n)"
            let a = attrs(sans(8), muted)
            let h = height(s, a, width) + 4
            ensure(h)
            y += text(s, x: margin, y: y, w: width, a) + 4
        }
    }

    // MARK: Tables

    private func tableHeader(_ cols: [(String, CGFloat, NSTextAlignment)]) {
        ensure(22)
        emeraldTint.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: width, height: 20))
        var x = margin
        for c in cols {
            text(c.0, x: x + 4, y: y + 5, w: c.1 - 8, attrs(sans(7.5, .semibold), ink, c.2))
            x += c.1
        }
        y += 22
    }

    private func tableRow(_ cols: [(String, CGFloat, NSTextAlignment)], _ values: [String], font: UIFont, color: UIColor, fill: UIColor? = nil) {
        let h = zip(values, cols).map { v, c in height(v, attrs(font, color, c.2), c.1 - 8) }.max().map { max($0, 10) + 7 } ?? 17
        ensure(h)
        if let fill { fill.setFill(); UIRectFill(CGRect(x: margin, y: y, width: width, height: h)) }
        var x = margin
        for (v, c) in zip(values, cols) {
            text(v, x: x + 4, y: y + 3.5, w: c.1 - 8, attrs(font, color, c.2))
            x += c.1
        }
        y += h
        line(margin, y, width, hairline)
        y += 0.5
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
