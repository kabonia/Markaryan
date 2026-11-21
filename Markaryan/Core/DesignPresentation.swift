import UIKit

/// Everything that goes into the client presentation of one design concept.
struct DesignPresentationContent {
    var projectName: String
    var plan: FloorPlan
    var proposal: DesignProposal
    var roomKind: RoomKind = .living
    /// Measured plan without furniture (walls, openings, three dimension chains).
    var measuredPlan: UIImage?
    /// Layout with numbered items.
    var planImage: UIImage?
    /// Water, drainage and sockets for the fixtures (bathroom / kitchen).
    var engineering: (image: UIImage, points: [DrawingsPDF.ConnectionPoint])? = nil
    var topRender: UIImage?
    var isoRender: UIImage?
    var interiorPhotos: [(title: String, image: UIImage)]
}

/// Landscape A4 PDF in the style of a professional interior design project:
/// cover, concept, plan, 3D layouts, interior visualisations, specification, materials and budget, contacts.
enum DesignPresentationPDF {
    private static let page = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let margin: CGFloat = 36
    private static let ink = UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
    private static let muted = UIColor(red: 0.45, green: 0.46, blue: 0.45, alpha: 1)
    private static let accent = UIColor(red: 0.85, green: 0.38, blue: 0.18, alpha: 1)
    private static let paper = UIColor(red: 0.975, green: 0.968, blue: 0.955, alpha: 1)

    static func render(_ content: DesignPresentationContent) throws -> URL {
        let safe = content.proposal.title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-").prefix(40)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Дизайн-проект-\(safe.isEmpty ? "АртСтрой" : String(safe)).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: content.proposal.title, kCGPDFContextAuthor as String: "АртСтрой"]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        var pageNumber = 0

        try renderer.writePDF(to: url) { context in
            func newPage(dark: Bool = false) {
                context.beginPage(); pageNumber += 1
                (dark ? ink : paper).setFill(); context.fill(page)
            }
            @discardableResult
            func text(_ value: String, _ rect: CGRect, _ font: UIFont, _ color: UIColor = ink, _ alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 2) -> CGFloat {
                let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineSpacing = lineSpacing; style.lineBreakMode = .byWordWrapping
                let attributed = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
                attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            }
            func image(_ image: UIImage, in rect: CGRect, fill: Bool = true, radius: CGFloat = 6) {
                let size = image.size
                guard size.width > 0, size.height > 0 else { return }
                let scale = fill ? max(rect.width / size.width, rect.height / size.height) : min(rect.width / size.width, rect.height / size.height)
                let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
                let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
                let cg = context.cgContext
                cg.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
                image.draw(in: CGRect(origin: origin, size: drawSize))
                cg.restoreGState()
            }
            func header(_ eyebrow: String, _ title: String) {
                text(eyebrow.uppercased(), CGRect(x: margin, y: 28, width: 500, height: 14), .systemFont(ofSize: 8.5, weight: .bold), accent)
                text(title, CGRect(x: margin, y: 42, width: 700, height: 30), .systemFont(ofSize: 20, weight: .bold))
            }
            func footer(dark: Bool = false) {
                let color = dark ? UIColor(white: 1, alpha: 0.7) : muted
                text("АРТСТРОЙ · \(Brand.phoneDisplay) · \(Brand.site)", CGRect(x: margin, y: page.height - 24, width: 500, height: 12), .systemFont(ofSize: 7, weight: .medium), color)
                text("\(pageNumber)", CGRect(x: page.width - margin - 40, y: page.height - 24, width: 40, height: 12), .systemFont(ofSize: 7, weight: .medium), color, .right)
            }
            func imagePage(_ eyebrow: String, _ title: String, _ picture: UIImage, caption: String? = nil) {
                newPage()
                header(eyebrow, title)
                let rect = CGRect(x: margin, y: 80, width: page.width - margin * 2, height: page.height - 80 - (caption == nil ? 40 : 58))
                image(picture, in: rect, fill: false)
                if let caption { text(caption, CGRect(x: margin, y: rect.maxY + 6, width: rect.width, height: 16), .systemFont(ofSize: 8.5), muted) }
                footer()
            }

            let proposal = content.proposal
            let hero = content.interiorPhotos.first?.image ?? content.isoRender ?? content.topRender ?? content.measuredPlan

            // 1. Cover
            newPage(dark: true)
            if let hero {
                image(hero, in: page, fill: true, radius: 0)
                UIColor.black.withAlphaComponent(0.42).setFill()
                context.fill(CGRect(x: 0, y: page.height * 0.52, width: page.width, height: page.height * 0.48))
            }
            text("ДИЗАЙН‑ПРОЕКТ ИНТЕРЬЕРА", CGRect(x: margin, y: page.height * 0.56, width: 600, height: 16), .systemFont(ofSize: 10, weight: .bold), UIColor(red: 1, green: 0.62, blue: 0.42, alpha: 1))
            text(proposal.title, CGRect(x: margin, y: page.height * 0.56 + 20, width: page.width - margin * 2, height: 80), .systemFont(ofSize: 32, weight: .bold), .white)
            let subtitle = [content.projectName, proposal.roomPurpose, proposal.style, "\(CalculationEngine.format((content.plan.area * 10).rounded() / 10)) м²"].filter { !$0.isEmpty }.joined(separator: " · ")
            text(subtitle, CGRect(x: margin, y: page.height * 0.56 + 100, width: page.width - margin * 2, height: 20), .systemFont(ofSize: 12, weight: .medium), UIColor(white: 1, alpha: 0.85))
            text("АРТСТРОЙ · строим в Сочи с \(Brand.foundedYear) года · \(Date().formatted(date: .long, time: .omitted))", CGRect(x: margin, y: page.height - 40, width: 600, height: 14), .systemFont(ofSize: 9, weight: .medium), UIColor(white: 1, alpha: 0.75))

            // 2. Concept
            newPage()
            header("Концепция", proposal.title)
            var y: CGFloat = 86
            y += text(proposal.summary, CGRect(x: margin, y: y, width: 470, height: 200), .systemFont(ofSize: 11.5), ink, lineSpacing: 4) + 16
            if !proposal.lighting.isEmpty {
                text("СВЕТ", CGRect(x: margin, y: y, width: 200, height: 12), .systemFont(ofSize: 8, weight: .bold), accent); y += 14
                y += text(proposal.lighting, CGRect(x: margin, y: y, width: 470, height: 120), .systemFont(ofSize: 10), muted, lineSpacing: 3) + 14
            }
            if !proposal.tips.isEmpty {
                text("РЕШЕНИЯ", CGRect(x: margin, y: y, width: 200, height: 12), .systemFont(ofSize: 8, weight: .bold), accent); y += 14
                for tip in proposal.tips.prefix(5) { y += text("— " + tip, CGRect(x: margin, y: y, width: 470, height: 60), .systemFont(ofSize: 9.5), muted, lineSpacing: 2) + 4 }
            }
            text("ПАЛИТРА", CGRect(x: 560, y: 86, width: 200, height: 12), .systemFont(ofSize: 8, weight: .bold), accent)
            for (index, hex) in proposal.palette.prefix(6).enumerated() {
                let rect = CGRect(x: 560, y: 104 + CGFloat(index) * 62, width: 246, height: 52)
                (UIColor(hexString: hex) ?? .lightGray).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
                text(hex.uppercased(), CGRect(x: rect.minX + 10, y: rect.maxY - 18, width: 120, height: 12), .monospacedSystemFont(ofSize: 8, weight: .medium), UIColor(white: 1, alpha: 0.9))
            }
            footer()

            // Finishes: floor, walls, ceiling
            let finishes = [("Пол", proposal.floor), ("Стены", proposal.walls), ("Потолок", proposal.ceiling)].filter { !$0.1.isEmpty }
            if !finishes.isEmpty {
                newPage()
                header("Отделка поверхностей", "Пол, стены, потолок")
                let cardWidth = (page.width - margin * 2 - 24) / 3
                for (index, item) in finishes.enumerated() {
                    let x = margin + CGFloat(index) * (cardWidth + 12)
                    let swatch = CGRect(x: x, y: 86, width: cardWidth, height: 150)
                    (UIColor(hexString: item.1.color) ?? UIColor(white: 0.85, alpha: 1)).setFill()
                    UIBezierPath(roundedRect: swatch, cornerRadius: 8).fill()
                    text(item.0.uppercased(), CGRect(x: x, y: swatch.maxY + 14, width: cardWidth, height: 12), .systemFont(ofSize: 8, weight: .bold), accent)
                    var cardY = swatch.maxY + 28
                    cardY += text(item.1.material, CGRect(x: x, y: cardY, width: cardWidth, height: 60), .systemFont(ofSize: 12, weight: .semibold)) + 6
                    text(item.1.details, CGRect(x: x, y: cardY, width: cardWidth, height: 160), .systemFont(ofSize: 9.5), muted, lineSpacing: 3)
                }
                footer()
            }

            // 3. Measured plan as it is (no furniture)
            if let measured = content.measuredPlan {
                newPage()
                header("Обмерный план", "Существующее положение · размеры в мм")
                image(measured, in: CGRect(x: margin, y: 80, width: 540, height: page.height - 124), fill: false, radius: 0)
                var statY: CGFloat = 92
                let stats = [("Площадь", "\(CalculationEngine.format((content.plan.area * 100).rounded() / 100)) м²"), ("Периметр", "\(CalculationEngine.format((content.plan.perimeter * 100).rounded() / 100)) м"), ("Высота потолка", "\(CalculationEngine.format((content.plan.ceilingHeight * 100).rounded() / 100)) м"), ("Площадь стен за вычетом проёмов", "\(CalculationEngine.format((content.plan.netWallArea * 10).rounded() / 10)) м²"), ("Окна / двери", "\(content.plan.windows.count) / \(content.plan.doors.count)")]
                for (label, value) in stats {
                    text(label.uppercased(), CGRect(x: 600, y: statY, width: 206, height: 12), .systemFont(ofSize: 7.5, weight: .bold), muted)
                    text(value, CGRect(x: 600, y: statY + 12, width: 206, height: 22), .systemFont(ofSize: 16, weight: .bold))
                    statY += 46
                }
                text("Размеры — по лидар‑скану, мм. Перед заказом мебели и сантехники проверьте ключевые размеры рулеткой.", CGRect(x: 600, y: statY + 4, width: 206, height: 60), .systemFont(ofSize: 8), muted, lineSpacing: 2)
                footer()
            }

            // 4. Layout
            if let planImage = content.planImage {
                newPage()
                header("Планировочное решение", content.roomKind.furniturePlanTitle)
                image(planImage, in: CGRect(x: margin, y: 80, width: 540, height: page.height - 124), fill: false, radius: 0)
                text("ЭКСПЛИКАЦИЯ", CGRect(x: 600, y: 86, width: 206, height: 12), .systemFont(ofSize: 7.5, weight: .bold), accent)
                var listY: CGFloat = 102
                for (index, item) in proposal.furniture.enumerated() {
                    if listY > page.height - 60 { text("… полный список — в спецификации", CGRect(x: 600, y: listY, width: 206, height: 12), .systemFont(ofSize: 8), muted); break }
                    let size = "\(Int((item.width * 1000).rounded()))×\(Int((item.depth * 1000).rounded()))"
                    listY += text("\(index + 1). \(item.name) — \(size)", CGRect(x: 600, y: listY, width: 206, height: 30), .systemFont(ofSize: 8.5), ink, lineSpacing: 1) + 4
                }
                footer()
            }

            // Engineering: what each fixture needs and where
            if let engineering = content.engineering {
                newPage()
                header("Инженерные решения", content.roomKind == .bathroom ? "Сантехника: что, где и на какой высоте" : "Точки подключения оборудования")
                image(engineering.image, in: CGRect(x: margin, y: 80, width: 540, height: page.height - 124), fill: false, radius: 0)
                var listY: CGFloat = 86
                for (index, point) in engineering.points.enumerated() {
                    if listY > page.height - 70 { text("… полный список — в чертежах (раздел АР)", CGRect(x: 600, y: listY, width: 206, height: 12), .systemFont(ofSize: 8), muted); break }
                    listY += text("\(index + 1). \(point.fixture)", CGRect(x: 600, y: listY, width: 206, height: 14), .systemFont(ofSize: 9, weight: .semibold)) + 1
                    for row in point.rows {
                        let height = row.height == "—" ? "" : (Int(row.height) != nil ? " · h \(row.height) мм" : " · \(row.height)")
                        listY += text("\(row.net) — \(row.spec)\(height)", CGRect(x: 610, y: listY, width: 196, height: 24), .systemFont(ofSize: 8), muted, lineSpacing: 1) + 1
                    }
                    listY += 4
                }
                if content.roomKind == .bathroom {
                    text("В1 — холодная вода, Т3 — горячая, К1 — канализация. Пунктир — зона 2 (0,6 м): без розеток и выключателей. Выключатель — снаружи у двери.", CGRect(x: margin, y: page.height - 40, width: 540, height: 20), .systemFont(ofSize: 7.5), muted)
                }
                footer()
            }

            // 5–6. 3D layouts (exact model)
            if let top = content.topRender { imagePage("3D‑планировка", "Вид сверху", top, caption: "Точная 3D‑модель по скану: стены, проёмы и расстановка — 1:1 с обмерным планом") }
            if let iso = content.isoRender { imagePage("3D‑планировка", "Объёмный вид", iso, caption: "Изометрия точной 3D‑модели помещения в выбранной концепции") }

            // 6+. Interior visualisations
            for (index, photo) in content.interiorPhotos.enumerated() {
                newPage(dark: true)
                image(photo.image, in: page, fill: true, radius: 0)
                UIColor.black.withAlphaComponent(0.45).setFill()
                context.fill(CGRect(x: 0, y: page.height - 46, width: page.width, height: 46))
                text("ВИЗУАЛИЗАЦИЯ \(index + 1) · \(photo.title.uppercased())", CGRect(x: margin, y: page.height - 32, width: 600, height: 14), .systemFont(ofSize: 9, weight: .bold), .white)
                text("\(pageNumber)", CGRect(x: page.width - margin - 40, y: page.height - 32, width: 40, height: 14), .systemFont(ofSize: 9, weight: .bold), .white, .right)
            }

            // Specification
            if !proposal.furniture.isEmpty {
                newPage()
                header("Спецификация", content.roomKind.specificationTitle)
                var rowY: CGFloat = 86
                let columns: [(String, CGFloat, CGFloat)] = [("№", margin, 26), ("Наименование", margin + 30, 430), ("Размер, м", margin + 470, 120), ("Зона / тип", margin + 600, 170)]
                for column in columns { text(column.0.uppercased(), CGRect(x: column.1, y: rowY, width: column.2, height: 12), .systemFont(ofSize: 7.5, weight: .bold), muted) }
                rowY += 18
                for (index, item) in proposal.furniture.enumerated() {
                    if rowY > page.height - 50 { footer(); newPage(); header("Спецификация", content.roomKind.specificationTitle + " (продолжение)"); rowY = 86 }
                    if index % 2 == 0 { UIColor(white: 0, alpha: 0.035).setFill(); context.fill(CGRect(x: margin - 4, y: rowY - 3, width: page.width - margin * 2 + 8, height: 18)) }
                    text("\(index + 1)", CGRect(x: columns[0].1, y: rowY, width: columns[0].2, height: 14), .systemFont(ofSize: 9))
                    text(item.name, CGRect(x: columns[1].1, y: rowY, width: columns[1].2, height: 14), .systemFont(ofSize: 9, weight: .medium))
                    text(String(format: "%.2f × %.2f", item.width, item.depth).replacingOccurrences(of: ".", with: ","), CGRect(x: columns[2].1, y: rowY, width: columns[2].2, height: 14), .monospacedDigitSystemFont(ofSize: 9, weight: .regular))
                    text(FurnitureStyle.title(item.model), CGRect(x: columns[3].1, y: rowY, width: columns[3].2, height: 14), .systemFont(ofSize: 9), muted)
                    rowY += 18
                }
                footer()
            }

            // Materials and budget
            newPage()
            header("Отделка и бюджет", "Материалы проекта")
            var materialY: CGFloat = 86
            for material in proposal.materials {
                if materialY > page.height - 60 { break }
                text(material.name, CGRect(x: margin, y: materialY, width: 480, height: 14), .systemFont(ofSize: 10, weight: .semibold))
                materialY += 14
                materialY += text("\(material.where) · \(material.amount)", CGRect(x: margin, y: materialY, width: 480, height: 30), .systemFont(ofSize: 9), muted) + 8
            }
            if proposal.budgetMax > 0 {
                let box = CGRect(x: 560, y: 86, width: 246, height: 130)
                accent.withAlphaComponent(0.1).setFill(); UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
                text("ОРИЕНТИР БЮДЖЕТА", CGRect(x: box.minX + 16, y: box.minY + 16, width: 214, height: 12), .systemFont(ofSize: 8, weight: .bold), accent)
                text("\(CalculationEngine.money(proposal.budgetMin))\n– \(CalculationEngine.money(proposal.budgetMax))", CGRect(x: box.minX + 16, y: box.minY + 34, width: 214, height: 60), .systemFont(ofSize: 18, weight: .bold))
                text("Отделка и мебель, Сочи. Точная смета — после замера.", CGRect(x: box.minX + 16, y: box.minY + 96, width: 214, height: 30), .systemFont(ofSize: 8), muted)
            }
            footer()

            // Contacts
            newPage(dark: true)
            text("Реализуем этот проект под ключ", CGRect(x: margin, y: 150, width: 520, height: 80), .systemFont(ofSize: 28, weight: .bold), .white)
            text("Замер, рабочая документация, смета, черновая и чистовая отделка, мебель и комплектация. Этапы по актам и фотоотчётам.", CGRect(x: margin, y: 240, width: 470, height: 60), .systemFont(ofSize: 12), UIColor(white: 1, alpha: 0.8), lineSpacing: 4)
            text("\(Brand.phoneDisplay)\nWhatsApp · \(Brand.site)\nАртСтрой · Сочи", CGRect(x: margin, y: 320, width: 470, height: 70), .systemFont(ofSize: 13, weight: .semibold), .white, lineSpacing: 5)
            if let qr = BrandGraphics.qrCode(Brand.whatsAppURL(text: "Здравствуйте! Хочу реализовать дизайн‑проект «\(proposal.title)».").absoluteString, size: 300) {
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 600, y: 150, width: 200, height: 200), cornerRadius: 10).fill()
                qr.draw(in: CGRect(x: 612, y: 162, width: 176, height: 176))
                text("Наведите камеру — откроется WhatsApp", CGRect(x: 600, y: 360, width: 200, height: 30), .systemFont(ofSize: 8.5), UIColor(white: 1, alpha: 0.7), .center)
            }
            footer(dark: true)
        }
        return url
    }
}

extension UIColor {
    convenience init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
