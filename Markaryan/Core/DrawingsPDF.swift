import UIKit

/// Рабочие чертежи раздела АР по ГОСТ Р 21.101‑2020 / ГОСТ 21.501‑2018 (лист А3, альбомный):
/// 1. Общие данные (ведомость листов, указания, экспликация, условные обозначения)
/// 2. Обмерный план (существующее положение, без мебели) — оси, три цепочки размеров, марки проёмов, отметки
/// 3. План расстановки мебели / сантехники (по типу помещения)  4. Точки подключения  5. План полов
/// 6. Раскладка плитки (если пол плиточный)  7. План потолка и светильников  8. Электрооборудование (ГОСТ 21.210)
/// 9. Развёртки стен (с плиткой в санузле)  10. Ведомость отделки и спецификация материалов.
/// Стены — замкнутым контуром наружу от линии скана (`WallBody`).
enum DrawingsPDF {
    // MARK: Paper and pens

    private static let sheet = CGRect(x: 0, y: 0, width: 1190.55, height: 841.89)
    static func mm(_ value: CGFloat) -> CGFloat { value * 72 / 25.4 }
    private static let ink = UIColor.black
    /// Line weights per ГОСТ 2.303 (s ≈ 0.7 mm main line).
    private static let s3: CGFloat = 0.25 * 72 / 25.4   // thin
    private static let s2: CGFloat = 0.4 * 72 / 25.4    // medium
    private static let s1: CGFloat = 0.7 * 72 / 25.4    // main (cut walls)

    /// ГОСТ 2.304 type B italic look-alike.
    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "AvenirNextCondensed-DemiBoldItalic" : "AvenirNextCondensed-MediumItalic", size: size)
            ?? UIFont.italicSystemFont(ofSize: size)
    }

    struct Transform {
        let scale: CGFloat
        let origin: CGPoint
        let minX: Double, minY: Double
        var ppm: CGFloat { 1000 / scale * 72 / 25.4 }
        func p(_ point: PlanPoint) -> CGPoint { CGPoint(x: origin.x + CGFloat(point.x - minX) * ppm, y: origin.y + CGFloat(point.y - minY) * ppm) }
        func p(_ x: Double, _ y: Double) -> CGPoint { p(PlanPoint(x: x, y: y)) }
        func len(_ meters: Double) -> CGFloat { CGFloat(meters) * ppm }
    }

    private struct Sheet {
        let title: String
        let usesScale: Bool
        let draw: (CGContext) -> Void
    }

    private static let wallThickness = WallBody.standardThickness
    private static let axisLetters = ["А", "Б", "В", "Г", "Д", "Е", "Ж", "И", "К", "Л", "М", "Н", "П", "Р", "С", "Т", "У", "Ф", "Ш", "Э", "Ю", "Я"]

    // MARK: Entry point

    static func render(plan: FloorPlan, proposal original: DesignProposal?, projectName: String) throws -> URL {
        let proposal = original?.placed(in: plan)
        let room = RoomKind.detect(plan: plan, proposal: proposal)
        let safe = plan.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("АР-\(safe.isEmpty ? "помещение" : safe).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Раздел АР · \(plan.name)", kCGPDFContextAuthor as String: "АртСтрой"]

        let frame = CGRect(x: mm(20), y: mm(5), width: sheet.width - mm(25), height: sheet.height - mm(10))
        let stamp = CGRect(x: frame.maxX - mm(185), y: frame.maxY - mm(55), width: mm(185), height: mm(55))
        // Drawing field: leave room for three dimension chains, axes and a side table.
        let field = CGRect(x: frame.minX + mm(42), y: frame.minY + mm(42), width: frame.width - mm(42) - mm(105), height: frame.height - mm(42) - mm(62))
        let sideX = frame.maxX - mm(98)
        let code = "АС‑\(Calendar.current.component(.year, from: .now))‑\(String(plan.id.uuidString.prefix(4)))‑АР"

        let b = plan.bounds
        let widthM = max(0.5, b.maxX - b.minX), depthM = max(0.5, b.maxY - b.minY)
        let scale: CGFloat = [20, 25, 50, 75, 100, 150, 200].first { s in
            let ppm = 1000 / s * 72 / 25.4
            return CGFloat(widthM) * ppm <= field.width && CGFloat(depthM) * ppm <= field.height
        } ?? 200
        let ppm = 1000 / scale * 72 / 25.4
        let t = Transform(scale: scale, origin: CGPoint(x: field.midX - CGFloat(widthM) * ppm / 2, y: field.midY - CGFloat(depthM) * ppm / 2), minX: b.minX, minY: b.minY)

        // Same numbering as the AI uses (clockwise from the entrance); each wall runs left to right as seen from inside.
        let walls = PlanWalls.numbered(plan).map { side -> PlanSegment in var wall = side.segment; wall.start = side.start; wall.end = side.end; return wall }
        let doors = plan.doors, windows = plan.windows
        let roomName = plan.name

        var sheets: [Sheet] = []
        sheets.append(Sheet(title: "Общие данные", usesScale: false) { _ in })   // drawn later (needs the sheet list)
        sheets.append(Sheet(title: "Обмерный план. Существующее положение", usesScale: true) { cg in
            Self.drawAxes(cg, plan: plan, t: t)
            Self.drawWalls(cg, plan: plan, t: t, hatch: true)
            Self.drawOpeningMarks(cg, plan: plan, t: t)
            Self.drawWallNumbers(cg, walls: walls, plan: plan, t: t)
            Self.drawDimensionChains(cg, plan: plan, t: t)
            Self.drawInnerDimensions(cg, plan: plan, t: t)
            Self.drawRoomMarker(cg, plan: plan, t: t, number: "1", name: roomName)
            Self.drawLevelMark(cg, at: t.p((b.minX + b.maxX) / 2 + min(1.2, widthM * 0.25), (b.minY + b.maxY) / 2 + min(0.9, depthM * 0.22)), value: "±0,000")
            Self.drawNorthArrow(cg, at: CGPoint(x: sideX + mm(84), y: field.minY + mm(4)))
            Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY + mm(20)), title: "Ведомость проёмов",
                           columns: [("Марка", 14), ("Тип", 26), ("Размер, мм", 26), ("Кол.", 12)],
                           rows: Self.openingRows(doors: doors, windows: windows))
        })
        if let proposal, !proposal.furniture.isEmpty {
            sheets.append(Sheet(title: room.furniturePlanTitle, usesScale: true) { cg in
                Self.drawWalls(cg, plan: plan, t: t, hatch: false)
                for (index, item) in proposal.furniture.enumerated() { Self.drawFurniture(cg, item: item, number: index + 1, t: t) }
                Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
                Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Экспликация: " + room.specificationTitle.lowercased(),
                               columns: [("Поз.", 10), ("Наименование", 48), ("Размер, мм", 20)],
                               rows: proposal.furniture.enumerated().map { ["\($0.offset + 1)", $0.element.name, "\(Int(($0.element.width * 1000).rounded()))×\(Int(($0.element.depth * 1000).rounded()))"] })
            })
        }
        let points = Self.connections(plan: plan, proposal: proposal, room: room)
        if !points.isEmpty {
            sheets.append(Sheet(title: room == .bathroom ? "План сантехнических приборов и точек подключения" : "План точек подключения оборудования", usesScale: true) { cg in
                Self.drawEngineering(cg, plan: plan, proposal: proposal, points: points, room: room, t: t)
                Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
                var rows: [[String]] = []
                for (index, point) in points.enumerated() {
                    for (rowIndex, row) in point.rows.enumerated() {
                        rows.append([rowIndex == 0 ? "\(index + 1)" : "", rowIndex == 0 ? point.fixture : "", row.net, row.spec, row.height])
                    }
                }
                Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Ведомость точек подключения",
                               columns: [("№", 7), ("Прибор", 24), ("Сеть", 24), ("Параметры", 28), ("h, мм", 11)], rows: rows)
                let notesY = field.minY + mm(6) + mm(9) + mm(6) * CGFloat(min(rows.count, 38)) + mm(8)
                Self.drawNotes(cg, at: CGPoint(x: sideX, y: notesY), width: mm(94), title: "Указания", notes: Self.engineeringNotes(room))
            })
        }
        sheets.append(Sheet(title: "План полов", usesScale: true) { cg in
            Self.drawFloorHatch(cg, plan: plan, t: t, tiled: Self.isTiledFloor(room, proposal?.floor))
            Self.drawWalls(cg, plan: plan, t: t, hatch: false)
            Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
            Self.drawRoomMarker(cg, plan: plan, t: t, number: "1", name: roomName, typeMark: "1")
            let finish = proposal?.floor
            Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Экспликация полов",
                           columns: [("Пом.", 10), ("Тип", 10), ("Покрытие пола", 42), ("Пл., м²", 16)],
                           rows: [["1", "1", [finish?.material ?? "", finish?.details ?? ""].filter { !$0.isEmpty }.joined(separator: ". ").orDefault("По проекту"), Self.area(plan.area)]])
            Self.drawHatchLegend(cg, at: CGPoint(x: sideX, y: field.minY + mm(40)), title: "Тип 1", tiled: Self.isTiledFloor(room, proposal?.floor))
        })
        // Tiles: the floor when it is tiled, the walls of a bathroom; sizes from the finishes when they name one.
        let floorTiled = Self.isTiledFloor(room, proposal?.floor)
        let wallsTiled = room == .bathroom && TileLayout.isTiled(.bathroom, proposal?.walls)
        let floorTiles = floorTiled ? TileLayout.floor(plan, tile: TileSize.parse((proposal?.floor.material ?? "") + " " + (proposal?.floor.details ?? "")) ?? .floor) : nil
        let wallTiles = wallsTiled ? TileLayout.walls(plan, tile: TileSize.parse((proposal?.walls.material ?? "") + " " + (proposal?.walls.details ?? "")) ?? .wall) : []
        if let floorTiles {
            sheets.append(Sheet(title: "Раскладка плитки на полу", usesScale: true) { cg in
                Self.drawTiles(cg, layout: floorTiles, t: t)
                Self.drawWalls(cg, plan: plan, t: t, hatch: false)
                Self.drawTileStart(cg, layout: floorTiles, plan: plan, t: t)
                Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
                let rows = Self.tileRows(floor: floorTiles, walls: wallTiles)
                Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Расход плитки", columns: [("Показатель", 50), ("Значение", 44)], rows: rows)
                Self.drawNotes(cg, at: CGPoint(x: sideX, y: field.minY + mm(6) + mm(9) + mm(6) * CGFloat(rows.count) + mm(8)), width: mm(94), title: "Указания", notes: [
                    "1. Раскладку начинать от линий начала (штрихпунктир) целой плиткой; шов \(Int((floorTiles.joint * 1000).rounded())) мм.",
                    "2. Подрезанные плитки показаны серым; самая узкая подрезка указана в таблице.",
                    "3. Запас 10 % — на подрезку и бой; при диагональной раскладке — 15 %.",
                    "4. Количество уточнить по размеру плитки в коробке и партии."
                ])
            })
        }
        sheets.append(Sheet(title: "План потолка. Размещение светильников", usesScale: true) { cg in
            Self.drawWalls(cg, plan: plan, t: t, hatch: false, openings: false)
            let lights = ElectricPlanner.spotLights(plan)
            for light in lights { Self.drawLightSymbol(cg, at: t.p(light)) }
            Self.drawLightSettingOut(cg, lights: lights, plan: plan, t: t)
            Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
            Self.drawLevelMark(cg, at: t.p((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2), value: "+\(Self.meters3(plan.ceilingHeight))", label: "низ потолка")
            let finish = proposal?.ceiling
            Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Ведомость потолка и светильников",
                           columns: [("Поз.", 10), ("Наименование", 48), ("Кол.", 20)],
                           rows: [["1", (finish?.material ?? "").orDefault("Потолок по проекту"), Self.area(plan.area) + " м²"],
                                  ["2", "Светильник точечный встраиваемый", "\(lights.count) шт."]]
                                 + ((finish?.details.isEmpty ?? true) ? [] : [["", finish?.details ?? "", ""]]))
            Self.drawLightLegend(cg, at: CGPoint(x: sideX, y: field.minY + mm(48)))
        })
        let power = ElectricPlanner.plan(for: plan, proposal: proposal, room: room)
        sheets.append(Sheet(title: "План электрооборудования: розетки, выключатели, свет", usesScale: true) { cg in
            Self.drawWalls(cg, plan: plan, t: t, hatch: false)
            for item in proposal?.furniture ?? [] where item.blocksFloor { Self.drawGhost(cg, item: item, t: t) }
            Self.drawElectric(cg, power: power, t: t)
            Self.drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
            let rows = Self.electricRows(power)
            Self.drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Ведомость электроустановочных изделий",
                           columns: [("Наименование", 50), ("Кол.", 12), ("h, мм", 32)], rows: rows)
            let groupsY = field.minY + mm(6) + mm(9) + mm(6) * CGFloat(rows.count) + mm(8)
            Self.drawTable(cg, at: CGPoint(x: sideX, y: groupsY), title: "Группы щита",
                           columns: [("Гр.", 8), ("Назначение", 34), ("Автомат", 26), ("Кабель", 26)],
                           rows: power.circuits.map { ["\($0.number)", $0.title, $0.breaker, $0.cable] })
            let legendY = groupsY + mm(6) + mm(9) + mm(6) * CGFloat(power.circuits.count) + mm(8)
            Self.drawElectricLegend(cg, at: CGPoint(x: sideX, y: legendY), kinds: ElectricPoint.Kind.allCases.filter { power.count($0) > 0 })
            Self.drawNotes(cg, at: CGPoint(x: frame.minX + mm(15), y: field.maxY + mm(10)), width: frame.width - mm(200), title: "Указания", notes: power.notes)
        })
        if !walls.isEmpty && walls.count <= 16 {
            sheets.append(Sheet(title: "Развёртки стен", usesScale: false) { cg in
                Self.drawElevations(cg, plan: plan, walls: walls, tiles: wallTiles, in: CGRect(x: frame.minX + mm(15), y: frame.minY + mm(28), width: frame.width - mm(30), height: frame.height - mm(28) - mm(62)))
            })
        }
        sheets.append(Sheet(title: "Ведомость отделки помещений", usesScale: false) { cg in
            Self.drawFinishSchedule(cg, origin: CGPoint(x: frame.minX + mm(15), y: frame.minY + mm(28)), plan: plan, proposal: proposal)
        })

        let titles = sheets.map(\.title)
        let renderer = UIGraphicsPDFRenderer(bounds: sheet, format: format)
        try renderer.writePDF(to: url) { context in
            for (index, item) in sheets.enumerated() {
                context.beginPage()
                let cg = context.cgContext
                UIColor.white.setFill(); cg.fill(sheet)
                drawFrame(cg, frame: frame)
                if index == 0 {
                    drawGeneralData(cg, frame: frame, titles: titles, plan: plan, proposal: proposal, projectName: projectName)
                } else {
                    item.draw(cg)
                }
                text(item.title, at: CGPoint(x: frame.minX + mm(15), y: frame.minY + mm(8)), font: font(15, bold: true))
                if item.usesScale {
                    text("М 1:\(Int(scale))", at: CGPoint(x: frame.minX + mm(15), y: frame.minY + mm(16)), font: font(10))
                    drawScaleBar(cg, at: CGPoint(x: frame.minX + mm(38), y: frame.minY + mm(18.5)), t: t)
                }
                drawStamp(cg, rect: stamp, code: code, object: "\(projectName). \(plan.name)", sheetTitle: item.title, sheetNumber: index + 1, sheetsCount: sheets.count)
                text("Формат А3", at: CGPoint(x: frame.maxX - mm(20), y: frame.maxY + mm(1)), font: font(7))
            }
        }
        return url
    }

    // MARK: Apartment

    /// The apartment on one sheet: every room where the scan saw it, partitions and doors once, room numbers, names
    /// and areas, the overall dimensions and the room schedule (экспликация помещений).
    static func render(apartment: ApartmentLayout, name: String, projectName: String) throws -> URL {
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("АР-\(safe.isEmpty ? "квартира" : safe).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Раздел АР · \(name)", kCGPDFContextAuthor as String: "АртСтрой"]
        let frame = CGRect(x: mm(20), y: mm(5), width: sheet.width - mm(25), height: sheet.height - mm(10))
        let stamp = CGRect(x: frame.maxX - mm(185), y: frame.maxY - mm(55), width: mm(185), height: mm(55))
        let field = CGRect(x: frame.minX + mm(34), y: frame.minY + mm(36), width: frame.width - mm(34) - mm(105), height: frame.height - mm(36) - mm(62))
        let sideX = frame.maxX - mm(98)
        let code = "АС‑\(Calendar.current.component(.year, from: .now))‑\(String((apartment.rooms.first?.id.uuidString ?? "0000").prefix(4)))‑АР"
        let widthM = max(0.5, apartment.width), depthM = max(0.5, apartment.depth)
        let scale: CGFloat = [20, 25, 50, 75, 100, 150, 200].first { s in
            let ppm = 1000 / s * 72 / 25.4
            return CGFloat(widthM) * ppm <= field.width && CGFloat(depthM) * ppm <= field.height
        } ?? 200
        let ppm = 1000 / scale * 72 / 25.4
        let t = Transform(scale: scale, origin: CGPoint(x: field.midX - CGFloat(widthM) * ppm / 2, y: field.midY - CGFloat(depthM) * ppm / 2), minX: 0, minY: 0)
        // All rooms as one plan, for the overall dimension chains.
        let whole = FloorPlan(name: name, source: .lidar, segments: apartment.rooms.flatMap { $0.plan.segments }, objects: [], floorPolygon: [],
                              ceilingHeight: apartment.rooms.first?.plan.ceilingHeight ?? 2.7, modelFilename: nil)
        let title = "План квартиры"
        let renderer = UIGraphicsPDFRenderer(bounds: sheet, format: format)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let cg = context.cgContext
            UIColor.white.setFill(); cg.fill(sheet)
            drawFrame(cg, frame: frame)
            drawBodies(cg, apartment.wallBodies(thickness: wallThickness), t: t, hatch: true, doors: Set(apartment.doors.map(\.door.id)))
            for room in apartment.rooms {
                drawRoomMarker(cg, plan: room.plan, t: t, number: "\(room.number)", name: room.name, at: room.labelPoint)
            }
            drawDimensionChains(cg, plan: whole, t: t, onlyOverall: true)
            let rows = apartment.rooms.map { ["\($0.number)", $0.name, area($0.area)] } + [["", "Итого", area(apartment.area)]]
            drawTable(cg, at: CGPoint(x: sideX, y: field.minY), title: "Экспликация помещений", columns: [("№", 10), ("Наименование", 56), ("Площадь, м²", 28)], rows: rows)
            drawNotes(cg, at: CGPoint(x: sideX, y: field.minY + mm(6) + mm(9) + mm(6) * CGFloat(rows.count) + mm(8)), width: mm(94), title: "Указания", notes: [
                "1. Комнаты сняты одним сканом и поставлены на свои места; перегородки — по фактическому зазору между комнатами.",
                "2. Наружные стены показаны условной толщины 150 мм.",
                "3. Чертежи каждой комнаты (расстановка, полы, потолок, электрика, плитка) — в её разделе АР."
            ])
            text(title, at: CGPoint(x: frame.minX + mm(15), y: frame.minY + mm(8)), font: font(15, bold: true))
            text("М 1:\(Int(scale))", at: CGPoint(x: frame.minX + mm(15), y: frame.minY + mm(16)), font: font(10))
            drawScaleBar(cg, at: CGPoint(x: frame.minX + mm(38), y: frame.minY + mm(18.5)), t: t)
            drawStamp(cg, rect: stamp, code: code, object: "\(projectName). \(name)", sheetTitle: title, sheetNumber: 1, sheetsCount: 1)
            text("Формат А3", at: CGPoint(x: frame.maxX - mm(20), y: frame.maxY + mm(1)), font: font(7))
        }
        return url
    }

    // MARK: Text and lines

    static func text(_ value: String, at point: CGPoint, font: UIFont, centered: Bool = false, angle: CGFloat = 0, maxWidth: CGFloat? = nil, rightAligned: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let string = value as NSString
        var size = string.size(withAttributes: attributes)
        if let maxWidth { size.width = min(size.width, maxWidth) }
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y)
        cg.rotate(by: angle)
        let x: CGFloat = centered ? -size.width / 2 : (rightAligned ? -size.width : 0)
        let y: CGFloat = centered ? -size.height / 2 : 0
        string.draw(with: CGRect(x: x, y: y, width: maxWidth ?? size.width + 1, height: size.height + 1), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
        cg.restoreGState()
    }

    private static func line(_ cg: CGContext, _ points: [CGPoint], _ width: CGFloat, dash: [CGFloat] = []) {
        guard points.count > 1 else { return }
        cg.saveGState()
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(width); cg.setLineDash(phase: 0, lengths: dash); cg.setLineCap(.butt)
        cg.move(to: points[0]); points.dropFirst().forEach { cg.addLine(to: $0) }
        cg.strokePath()
        cg.restoreGState()
    }

    static func meters(_ value: Double) -> String { String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") }
    static func meters3(_ value: Double) -> String { String(format: "%.3f", value).replacingOccurrences(of: ".", with: ",") }
    static func area(_ value: Double) -> String { String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") }

    // MARK: Frame and title block (ГОСТ Р 21.101 form 3 + additional columns)

    private static func drawFrame(_ cg: CGContext, frame: CGRect) {
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(s3); cg.stroke(sheet.insetBy(dx: 0.3, dy: 0.3))
        cg.setLineWidth(s1); cg.stroke(frame)
        // Additional columns on the left margin: Инв. № подл. / Подп. и дата / Взам. инв. №
        let column = CGRect(x: frame.minX - mm(12), y: frame.maxY - mm(85), width: mm(12), height: mm(85))
        cg.setLineWidth(s2); cg.stroke(column)
        let splits: [CGFloat] = [25, 60]
        for value in splits { line(cg, [CGPoint(x: column.minX, y: column.minY + mm(value)), CGPoint(x: column.maxX, y: column.minY + mm(value))], s2) }
        line(cg, [CGPoint(x: column.minX + mm(5), y: column.minY), CGPoint(x: column.minX + mm(5), y: column.maxY)], s3)
        let labels = [("Взам. инв. №", 12.5), ("Подп. и дата", 42.5), ("Инв. № подл.", 72.5)]
        for label in labels { text(label.0, at: CGPoint(x: column.minX + mm(2.5), y: column.minY + mm(CGFloat(label.1))), font: font(6.5), centered: true, angle: -.pi / 2) }
    }

    private static func drawStamp(_ cg: CGContext, rect: CGRect, code: String, object: String, sheetTitle: String, sheetNumber: Int, sheetsCount: Int) {
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s1); cg.stroke(rect)
        let left = mm(65)
        let colWidths: [CGFloat] = [7, 10, 10, 10, 15, 10].map { mm($0) }
        let row = mm(5)
        // Vertical lines of the signature block
        var x = rect.minX
        for (index, width) in colWidths.enumerated() {
            x += width
            line(cg, [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: index < 2 || index == 3 ? rect.minY + row * 5 : rect.maxY)], index == colWidths.count - 1 ? s1 : s2)
        }
        for index in 1..<11 {
            let y = rect.minY + row * CGFloat(index)
            line(cg, [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.minX + left, y: y)], index == 5 ? s1 : s3)
        }
        let headers = ["Изм.", "Кол.уч.", "Лист", "№ док.", "Подп.", "Дата"]
        var hx = rect.minX
        for (index, header) in headers.enumerated() { text(header, at: CGPoint(x: hx + colWidths[index] / 2, y: rect.minY + row * 4.5), font: font(6.5), centered: true); hx += colWidths[index] }
        let roles = [("Разраб.", "АртСтрой"), ("Пров.", ""), ("ГИП", ""), ("Н.контр.", ""), ("Утв.", "")]
        for (index, role) in roles.enumerated() {
            let y = rect.minY + row * (CGFloat(index) + 5.5)
            text(role.0, at: CGPoint(x: rect.minX + mm(1), y: y - mm(1.8)), font: font(6.5))
            text(role.1, at: CGPoint(x: rect.minX + colWidths[0] + colWidths[1] + mm(1), y: y - mm(1.8)), font: font(6.5), maxWidth: colWidths[2] + colWidths[3] - mm(1))
            text(Date().formatted(.dateTime.month(.twoDigits).year(.twoDigits)), at: CGPoint(x: rect.minX + left - colWidths[5] / 2, y: y), font: font(6), centered: true)
        }
        // Right part
        let r = CGRect(x: rect.minX + left, y: rect.minY, width: rect.width - left, height: rect.height)
        let infoX = r.maxX - mm(50)
        line(cg, [CGPoint(x: r.minX, y: r.minY + mm(15)), CGPoint(x: r.maxX, y: r.minY + mm(15))], s1)
        line(cg, [CGPoint(x: r.minX, y: r.minY + mm(30)), CGPoint(x: r.maxX, y: r.minY + mm(30))], s1)
        line(cg, [CGPoint(x: infoX, y: r.minY + mm(15)), CGPoint(x: infoX, y: r.maxY)], s1)
        line(cg, [CGPoint(x: infoX, y: r.minY + mm(20)), CGPoint(x: r.maxX, y: r.minY + mm(20))], s2)
        for k in 1...2 { line(cg, [CGPoint(x: infoX + mm(50) / 3 * CGFloat(k), y: r.minY + mm(15)), CGPoint(x: infoX + mm(50) / 3 * CGFloat(k), y: r.minY + mm(30))], s2) }
        text(code, at: CGPoint(x: r.midX, y: r.minY + mm(7.5)), font: font(12, bold: true), centered: true)
        text(object, at: CGPoint(x: r.minX + mm(2), y: r.minY + mm(18)), font: font(8.5), maxWidth: infoX - r.minX - mm(4))
        text(sheetTitle, at: CGPoint(x: r.minX + mm(2), y: r.minY + mm(36)), font: font(10, bold: true), maxWidth: infoX - r.minX - mm(4))
        let cells = [("Стадия", "Р"), ("Лист", "\(sheetNumber)"), ("Листов", "\(sheetsCount)")]
        for (index, cell) in cells.enumerated() {
            let cx = infoX + mm(50) / 3 * (CGFloat(index) + 0.5)
            text(cell.0, at: CGPoint(x: cx, y: r.minY + mm(17.5)), font: font(6.5), centered: true)
            text(cell.1, at: CGPoint(x: cx, y: r.minY + mm(25)), font: font(10, bold: true), centered: true)
        }
        text("АРТСТРОЙ", at: CGPoint(x: infoX + mm(25), y: r.minY + mm(39)), font: font(12, bold: true), centered: true)
        text("АртСтрой, г. Сочи", at: CGPoint(x: infoX + mm(25), y: r.minY + mm(45)), font: font(7), centered: true)
        text("\(Brand.phoneDisplay)", at: CGPoint(x: infoX + mm(25), y: r.minY + mm(50)), font: font(7), centered: true)
    }

    private static func drawScaleBar(_ cg: CGContext, at point: CGPoint, t: Transform) {
        let step = t.len(1)
        for index in 0..<5 {
            let rect = CGRect(x: point.x + step * CGFloat(index), y: point.y - mm(0.8), width: step, height: mm(1.6))
            cg.setFillColor((index % 2 == 0 ? UIColor.black : UIColor.white).cgColor); cg.fill(rect)
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3); cg.stroke(rect)
            text("\(index)", at: CGPoint(x: rect.minX, y: rect.maxY + mm(2.2)), font: font(6), centered: true)
        }
        text("5 м", at: CGPoint(x: point.x + step * 5 + mm(1), y: point.y + mm(2.2)), font: font(6), centered: true)
    }

    // MARK: Walls (cut, hatched) and openings

    /// Walls as one closed contour: the scanned line is the inner face, the wall goes outward (`WallBody`),
    /// corners are mitred, doors and windows are gaps with jambs.
    private static func drawWalls(_ cg: CGContext, plan: FloorPlan, t: Transform, hatch: Bool, openings: Bool = true) {
        drawBodies(cg, [WallBody(plan: plan, thickness: wallThickness)], t: t, hatch: hatch, openings: openings)
    }

    /// The walls of one room or of all rooms of an apartment, filled and hatched together: the middle of a partition
    /// is not drawn, and only the doors in `doors` get a leaf (nil — every door).
    private static func drawBodies(_ cg: CGContext, _ bodies: [WallBody], t: Transform, hatch: Bool, openings: Bool = true, doors: Set<UUID>? = nil) {
        let pieces = bodies.flatMap(\.pieces)
        let polygons = pieces.map { $0.polygon.map { t.p($0) } }
        // Fill + 45° hatching for cut walls (ГОСТ 2.306), or solid poché on design sheets.
        cg.saveGState()
        for polygon in polygons { cg.addLines(between: polygon); cg.closePath() }
        if hatch {
            cg.setFillColor(UIColor.white.cgColor); cg.fillPath()
            for polygon in polygons { cg.addLines(between: polygon); cg.closePath() }
            cg.clip()
            let box = polygons.flatMap { $0 }.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
            var x = box.minX - box.height
            while x < box.maxX { cg.move(to: CGPoint(x: x, y: box.maxY)); cg.addLine(to: CGPoint(x: x + box.height, y: box.minY)); x += mm(1.6) }
            cg.strokePath()
        } else {
            cg.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor); cg.fillPath()
        }
        cg.restoreGState()
        // Contour: inner and outer faces, jambs at openings and free ends; no seams at the corners or in partitions.
        for piece in pieces {
            line(cg, [t.p(piece.innerStart), t.p(piece.innerEnd)], s1)
            if !piece.shared { line(cg, [t.p(piece.outerStart), t.p(piece.outerEnd)], s1) }
            if piece.capStart { line(cg, [t.p(piece.innerStart), t.p(piece.outerStart)], s1) }
            if piece.capEnd { line(cg, [t.p(piece.innerEnd), t.p(piece.outerEnd)], s1) }
        }
        guard openings else { return }
        for gap in bodies.flatMap(\.gaps) {
            let opening = gap.opening
            if opening.kind == .window {
                // Window per ГОСТ 21.201: frame lines on both faces and the glass inside the wall.
                for k in [0.0, 0.4, 0.6, 1.0] {
                    let shift = gap.outward * (gap.thickness * k)
                    line(cg, [t.p(gap.innerStart + shift), t.p(gap.innerEnd + shift)], k == 0 || k == 1 ? s2 : s3)
                }
            } else if opening.kind == .door, doors.map({ $0.contains(opening.id) }) ?? true {
                // Leaf opens into the room (same rule as the plan screen and the 3D model), hinged at the start of the door.
                let hinge = gap.innerStart.distance(to: opening.start) <= gap.innerEnd.distance(to: opening.start) ? gap.innerStart : gap.innerEnd
                let latch = hinge == gap.innerStart ? gap.innerEnd : gap.innerStart
                let a = t.p(hinge), c = t.p(latch)
                let leaf = t.p(hinge + gap.outward * -hinge.distance(to: latch))
                line(cg, [a, leaf], s2)
                let radius = hypot(c.x - a.x, c.y - a.y)
                let start = atan2(c.y - a.y, c.x - a.x), finish = atan2(leaf.y - a.y, leaf.x - a.x)
                var sweep = finish - start
                if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
                line(cg, (0...24).map { step in
                    let angle = start + sweep * CGFloat(step) / 24
                    return CGPoint(x: a.x + cos(angle) * radius, y: a.y + sin(angle) * radius)
                }, s3)
            }
        }
    }

    private static func openingRows(doors: [PlanSegment], windows: [PlanSegment]) -> [[String]] {
        var rows: [[String]] = []
        for (index, door) in doors.enumerated() {
            rows.append(["Д\(index + 1)", door.kind == .door ? "Дверной блок" : "Проём", "\(Int((door.length * 1000).rounded()))×\(Int((min(door.height, 2.3) * 1000).rounded()))", "1"])
        }
        for (index, window) in windows.enumerated() {
            rows.append(["ОК\(index + 1)", "Оконный блок", "\(Int((window.length * 1000).rounded()))×\(Int((window.height * 1000).rounded()))", "1"])
        }
        return rows.isEmpty ? [["—", "Проёмы не выявлены", "", ""]] : rows
    }

    private static func drawOpeningMarks(_ cg: CGContext, plan: FloorPlan, t: Transform) {
        let center = PlanPoint(x: (plan.bounds.minX + plan.bounds.maxX) / 2, y: (plan.bounds.minY + plan.bounds.maxY) / 2)
        func mark(_ label: String, _ segment: PlanSegment) {
            let mid = PlanPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
            let dx = center.x - mid.x, dy = center.y - mid.y, length = max(0.001, hypot(dx, dy))
            let p = t.p(mid.x + dx / length * 0.45, mid.y + dy / length * 0.45)
            text(label, at: p, font: font(8, bold: true), centered: true)
        }
        for (index, door) in plan.doors.enumerated() { mark("Д\(index + 1)", door) }
        for (index, window) in plan.windows.enumerated() { mark("ОК\(index + 1)", window) }
    }

    private static func drawWallNumbers(_ cg: CGContext, walls: [PlanSegment], plan: FloorPlan, t: Transform) {
        guard walls.count <= 16 else { return }
        let center = PlanPoint(x: (plan.bounds.minX + plan.bounds.maxX) / 2, y: (plan.bounds.minY + plan.bounds.maxY) / 2)
        for (index, wall) in walls.enumerated() where wall.length > 0.4 {
            let mid = PlanPoint(x: (wall.start.x + wall.end.x) / 2, y: (wall.start.y + wall.end.y) / 2)
            let dx = center.x - mid.x, dy = center.y - mid.y, length = max(0.001, hypot(dx, dy))
            let p = t.p(mid.x + dx / length * 0.28, mid.y + dy / length * 0.28)
            let r = mm(2.4)
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
            cg.stroke(CGRect(x: p.x - r * 1.3, y: p.y - r * 0.8, width: r * 2.6, height: r * 1.6))
            text("С\(index + 1)", at: p, font: font(6.5), centered: true)
        }
    }

    // MARK: Axes (ГОСТ 21.101: digits horizontally, letters vertically)

    private static func axisCoordinates(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() where result.last.map({ value - $0 > 0.3 }) ?? true { result.append(value) }
        return result
    }

    private static func drawAxes(_ cg: CGContext, plan: FloorPlan, t: Transform) {
        let b = plan.bounds
        let vertical = plan.walls.filter { abs($0.end.x - $0.start.x) < 0.08 * max(0.01, $0.length) }
        let horizontal = plan.walls.filter { abs($0.end.y - $0.start.y) < 0.08 * max(0.01, $0.length) }
        var xs = axisCoordinates(vertical.flatMap { [$0.start.x, $0.end.x] })
        var ys = axisCoordinates(horizontal.flatMap { [$0.start.y, $0.end.y] })
        if xs.count < 2 { xs = [b.minX, b.maxX] }
        if ys.count < 2 { ys = [b.minY, b.maxY] }
        xs = Array(xs.prefix(12)); ys = Array(ys.prefix(axisLetters.count))
        let wall = t.len(wallThickness)
        let top = t.p(0, b.minY).y - wall - mm(32), bottom = t.p(0, b.maxY).y + wall + mm(4)
        let leftX = t.p(b.minX, 0).x - wall - mm(32), rightX = t.p(b.maxX, 0).x + wall + mm(4)
        let radius = mm(4)
        for (index, x) in xs.enumerated() {
            let px = t.p(x, 0).x
            line(cg, [CGPoint(x: px, y: top + radius), CGPoint(x: px, y: bottom)], s3, dash: [mm(6), mm(1.5), mm(0.5), mm(1.5)])
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: px - radius, y: top - radius, width: radius * 2, height: radius * 2))
            cg.strokeEllipse(in: CGRect(x: px - radius, y: top - radius, width: radius * 2, height: radius * 2))
            text("\(index + 1)", at: CGPoint(x: px, y: top), font: font(9, bold: true), centered: true)
        }
        for (index, y) in ys.enumerated() {
            let py = t.p(0, y).y
            line(cg, [CGPoint(x: leftX + radius, y: py), CGPoint(x: rightX, y: py)], s3, dash: [mm(6), mm(1.5), mm(0.5), mm(1.5)])
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: leftX - radius, y: py - radius, width: radius * 2, height: radius * 2))
            cg.strokeEllipse(in: CGRect(x: leftX - radius, y: py - radius, width: radius * 2, height: radius * 2))
            text(axisLetters[index], at: CGPoint(x: leftX, y: py), font: font(9, bold: true), centered: true)
        }
    }

    // MARK: Dimensions (ГОСТ 2.307 / 21.501: three chains outside, 45° ticks)

    private static func tickDimension(_ cg: CGContext, from a: CGPoint, to b: CGPoint, lineOffset: CGPoint, label: String, extensionFrom: (CGPoint, CGPoint)? = nil) {
        let a2 = CGPoint(x: a.x + lineOffset.x, y: a.y + lineOffset.y), b2 = CGPoint(x: b.x + lineOffset.x, y: b.y + lineOffset.y)
        let dx = b2.x - a2.x, dy = b2.y - a2.y, length = max(0.001, hypot(dx, dy))
        let ux = dx / length, uy = dy / length
        // extension lines from the object to 2 mm beyond the dimension line
        let off = hypot(lineOffset.x, lineOffset.y)
        if off > 0.5 {
            let nx = lineOffset.x / off, ny = lineOffset.y / off
            let startA = extensionFrom?.0 ?? a, startB = extensionFrom?.1 ?? b
            line(cg, [CGPoint(x: startA.x + nx * mm(1), y: startA.y + ny * mm(1)), CGPoint(x: a2.x + nx * mm(2), y: a2.y + ny * mm(2))], s3)
            line(cg, [CGPoint(x: startB.x + nx * mm(1), y: startB.y + ny * mm(1)), CGPoint(x: b2.x + nx * mm(2), y: b2.y + ny * mm(2))], s3)
        }
        line(cg, [CGPoint(x: a2.x - ux * mm(2), y: a2.y - uy * mm(2)), CGPoint(x: b2.x + ux * mm(2), y: b2.y + uy * mm(2))], s3)
        let tick = mm(1.4)
        for p in [a2, b2] {
            let tx = (ux - uy) * tick / sqrt(2) * 1.4, ty = (uy + ux) * tick / sqrt(2) * 1.4
            line(cg, [CGPoint(x: p.x - tx, y: p.y - ty), CGPoint(x: p.x + tx, y: p.y + ty)], s1)
        }
        var angle = atan2(dy, dx)
        if angle > .pi / 2 + 0.01 { angle -= .pi } else if angle < -.pi / 2 - 0.01 { angle += .pi }
        let mid = CGPoint(x: (a2.x + b2.x) / 2, y: (a2.y + b2.y) / 2)
        // Text sits above the line (towards the top / left of the sheet).
        let up = CGPoint(x: sin(angle), y: -cos(angle))
        let fits = length > mm(7)
        let position = CGPoint(x: mid.x + up.x * mm(2.2), y: mid.y + up.y * mm(2.2))
        text(label, at: fits ? position : CGPoint(x: position.x + ux * mm(6), y: position.y + uy * mm(6)), font: font(7.5), centered: true, angle: angle)
    }

    private static func merged(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() where result.last.map({ value - $0 > 0.015 }) ?? true { result.append(value) }
        return result
    }

    /// Three projected chains on every side where there are walls: openings & piers, walls/axes, overall.
    private static func drawDimensionChains(_ cg: CGContext, plan: FloorPlan, t: Transform, onlyOverall: Bool = false) {
        let b = plan.bounds
        let midY = (b.minY + b.maxY) / 2, midX = (b.minX + b.maxX) / 2
        func horizontal(_ s: PlanSegment) -> Bool { abs(s.end.y - s.start.y) < 0.15 * max(0.01, s.length) }
        func vertical(_ s: PlanSegment) -> Bool { abs(s.end.x - s.start.x) < 0.15 * max(0.01, s.length) }
        let openings = plan.doors + plan.windows

        func chain(_ values: [Double], side: Int, level: Int) {
            let coords = merged(values)
            guard coords.count > 1 else { return }
            let gap = t.len(wallThickness) + mm(6) + mm(8) * CGFloat(level)
            for (index, value) in coords.dropLast().enumerated() {
                let next = coords[index + 1]
                let label = "\(Int(((next - value) * 1000).rounded()))"
                switch side {
                case 0: // top
                    let y = t.p(0, b.minY).y
                    tickDimension(cg, from: CGPoint(x: t.p(value, 0).x, y: y), to: CGPoint(x: t.p(next, 0).x, y: y), lineOffset: CGPoint(x: 0, y: -gap), label: label)
                case 1: // bottom
                    let y = t.p(0, b.maxY).y
                    tickDimension(cg, from: CGPoint(x: t.p(value, 0).x, y: y), to: CGPoint(x: t.p(next, 0).x, y: y), lineOffset: CGPoint(x: 0, y: gap), label: label)
                case 2: // left
                    let x = t.p(b.minX, 0).x
                    tickDimension(cg, from: CGPoint(x: x, y: t.p(0, next).y), to: CGPoint(x: x, y: t.p(0, value).y), lineOffset: CGPoint(x: -gap, y: 0), label: label)
                default: // right
                    let x = t.p(b.maxX, 0).x
                    tickDimension(cg, from: CGPoint(x: x, y: t.p(0, next).y), to: CGPoint(x: x, y: t.p(0, value).y), lineOffset: CGPoint(x: gap, y: 0), label: label)
                }
            }
        }

        if !onlyOverall {
            let topWalls = plan.walls.filter { horizontal($0) && ($0.start.y + $0.end.y) / 2 < midY }
            let bottomWalls = plan.walls.filter { horizontal($0) && ($0.start.y + $0.end.y) / 2 >= midY }
            let leftWalls = plan.walls.filter { vertical($0) && ($0.start.x + $0.end.x) / 2 < midX }
            let rightWalls = plan.walls.filter { vertical($0) && ($0.start.x + $0.end.x) / 2 >= midX }
            let topOpenings = openings.filter { horizontal($0) && ($0.start.y + $0.end.y) / 2 < midY }
            let bottomOpenings = openings.filter { horizontal($0) && ($0.start.y + $0.end.y) / 2 >= midY }
            let leftOpenings = openings.filter { vertical($0) && ($0.start.x + $0.end.x) / 2 < midX }
            let rightOpenings = openings.filter { vertical($0) && ($0.start.x + $0.end.x) / 2 >= midX }
            let allXs = plan.walls.flatMap { [$0.start.x, $0.end.x] }
            let allYs = plan.walls.flatMap { [$0.start.y, $0.end.y] }
            // Chain 1: piers and openings
            chain(topWalls.flatMap { [$0.start.x, $0.end.x] } + topOpenings.flatMap { [$0.start.x, $0.end.x] }, side: 0, level: 0)
            chain(bottomWalls.flatMap { [$0.start.x, $0.end.x] } + bottomOpenings.flatMap { [$0.start.x, $0.end.x] }, side: 1, level: 0)
            chain(leftWalls.flatMap { [$0.start.y, $0.end.y] } + leftOpenings.flatMap { [$0.start.y, $0.end.y] }, side: 2, level: 0)
            chain(rightWalls.flatMap { [$0.start.y, $0.end.y] } + rightOpenings.flatMap { [$0.start.y, $0.end.y] }, side: 3, level: 0)
            // Chain 2: all wall breaks (between axes)
            chain(allXs, side: 0, level: 1)
            chain(allYs, side: 2, level: 1)
        }
        // Chain 3: overall
        chain([b.minX, b.maxX], side: 0, level: onlyOverall ? 0 : 2)
        chain([b.minY, b.maxY], side: 2, level: onlyOverall ? 0 : 2)
    }

    /// Clear internal dimensions through the centre of the room.
    private static func drawInnerDimensions(_ cg: CGContext, plan: FloorPlan, t: Transform) {
        let b = plan.bounds
        let cx = (b.minX + b.maxX) / 2, cy = (b.minY + b.maxY) / 2
        func crossings(horizontalAt y: Double) -> [Double] {
            plan.walls.compactMap { w in
                guard (w.start.y - y) * (w.end.y - y) <= 0, abs(w.end.y - w.start.y) > 0.01 else { return nil }
                let k = (y - w.start.y) / (w.end.y - w.start.y)
                return w.start.x + (w.end.x - w.start.x) * k
            }.sorted()
        }
        func crossings(verticalAt x: Double) -> [Double] {
            plan.walls.compactMap { w in
                guard (w.start.x - x) * (w.end.x - x) <= 0, abs(w.end.x - w.start.x) > 0.01 else { return nil }
                let k = (x - w.start.x) / (w.end.x - w.start.x)
                return w.start.y + (w.end.y - w.start.y) * k
            }.sorted()
        }
        let xs = crossings(horizontalAt: cy + 0.35)
        if let left = xs.last(where: { $0 < cx }), let right = xs.first(where: { $0 > cx }), right - left > 0.6 {
            tickDimension(cg, from: t.p(left, cy + 0.35), to: t.p(right, cy + 0.35), lineOffset: .zero, label: "\(Int(((right - left) * 1000).rounded()))")
        }
        let ys = crossings(verticalAt: cx - 0.35)
        if let top = ys.last(where: { $0 < cy }), let bottom = ys.first(where: { $0 > cy }), bottom - top > 0.6 {
            tickDimension(cg, from: t.p(cx - 0.35, bottom), to: t.p(cx - 0.35, top), lineOffset: .zero, label: "\(Int(((bottom - top) * 1000).rounded()))")
        }
    }

    // MARK: Room marker, levels, north arrow

    private static func drawRoomMarker(_ cg: CGContext, plan: FloorPlan, t: Transform, number: String, name: String, typeMark: String? = nil, at point: PlanPoint? = nil) {
        let b = plan.bounds
        let c = point.map { t.p($0) } ?? t.p((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2 - min(0.6, (b.maxY - b.minY) * 0.15))
        // Room number in an oval, name, area underlined (ГОСТ 21.501)
        let oval = CGRect(x: c.x - mm(5), y: c.y - mm(9), width: mm(10), height: mm(6))
        cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: oval)
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3); cg.strokeEllipse(in: oval)
        text(number, at: CGPoint(x: oval.midX, y: oval.midY), font: font(8, bold: true), centered: true)
        text(name, at: CGPoint(x: c.x, y: c.y + mm(1.5)), font: font(8.5), centered: true)
        let areaText = "\(area(plan.area))"
        text(areaText, at: CGPoint(x: c.x, y: c.y + mm(6.5)), font: font(9, bold: true), centered: true)
        let w = (areaText as NSString).size(withAttributes: [.font: font(9, bold: true)]).width
        line(cg, [CGPoint(x: c.x - w / 2, y: c.y + mm(8.8)), CGPoint(x: c.x + w / 2, y: c.y + mm(8.8))], s2)
        if let typeMark {
            let box = CGRect(x: c.x + w / 2 + mm(3), y: c.y + mm(3.5), width: mm(6), height: mm(6))
            cg.stroke(box.insetBy(dx: 0, dy: 0))
            text(typeMark, at: CGPoint(x: box.midX, y: box.midY), font: font(8, bold: true), centered: true)
        }
    }

    private static func drawLevelMark(_ cg: CGContext, at point: CGPoint, value: String, label: String? = nil) {
        // Height mark: triangle with a leader and the value (ГОСТ 21.101 п. 5.6)
        let size = mm(2.2)
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s2)
        cg.move(to: CGPoint(x: point.x - size, y: point.y - size)); cg.addLine(to: CGPoint(x: point.x, y: point.y)); cg.addLine(to: CGPoint(x: point.x + size, y: point.y - size)); cg.strokePath()
        line(cg, [CGPoint(x: point.x - size, y: point.y - size), CGPoint(x: point.x + mm(16), y: point.y - size)], s3)
        text(value, at: CGPoint(x: point.x + mm(1), y: point.y - size - mm(4)), font: font(8, bold: true))
        if let label { text(label, at: CGPoint(x: point.x + mm(1), y: point.y - size + mm(0.8)), font: font(6.5)) }
    }

    private static func drawNorthArrow(_ cg: CGContext, at point: CGPoint) {
        let r = mm(5)
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
        cg.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        cg.setFillColor(ink.cgColor)
        cg.move(to: CGPoint(x: point.x, y: point.y - r * 1.2)); cg.addLine(to: CGPoint(x: point.x - r * 0.35, y: point.y + r * 0.6)); cg.addLine(to: CGPoint(x: point.x, y: point.y + r * 0.3)); cg.closePath(); cg.fillPath()
        text("С", at: CGPoint(x: point.x, y: point.y - r - mm(3)), font: font(7, bold: true), centered: true)
        text("условно", at: CGPoint(x: point.x, y: point.y + r + mm(2.5)), font: font(5.5), centered: true)
    }

    // MARK: Furniture, floor, ceiling

    private static func drawFurniture(_ cg: CGContext, item: DesignFurniture, number: Int, t: Transform, numbered: Bool = true) {
        let model = item.model
        guard model != "hiddenlight" else { return } // LED strips / spots are on the ceiling sheet
        let center = t.p(item.x, item.y)
        let w = t.len(item.width), d = t.len(item.depth)
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: CGFloat(item.rotation * .pi / 180))
        let rect = CGRect(x: -w / 2, y: -d / 2, width: w, height: d)
        func stroke(_ path: UIBezierPath) { cg.addPath(path.cgPath); cg.strokePath() }
        func segment(_ a: CGPoint, _ b: CGPoint) { cg.move(to: a); cg.addLine(to: b); cg.strokePath() }
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s2)
        switch model {
        case "toilet":
            // Cistern / installation at the wall + oval bowl (ГОСТ 21.205 style)
            let back = d * 0.24
            cg.stroke(CGRect(x: rect.minX + w * 0.05, y: rect.minY, width: w * 0.9, height: back))
            stroke(UIBezierPath(ovalIn: CGRect(x: rect.minX + w * 0.08, y: rect.minY + back, width: w * 0.84, height: d - back)))
            cg.setLineWidth(s3)
            stroke(UIBezierPath(ovalIn: CGRect(x: rect.minX + w * 0.22, y: rect.minY + back + (d - back) * 0.15, width: w * 0.56, height: (d - back) * 0.6)))
        case "sink":
            cg.stroke(rect)
            cg.setLineWidth(s3)
            stroke(UIBezierPath(ovalIn: CGRect(x: rect.midX - w * 0.3, y: rect.minY + d * 0.22, width: w * 0.6, height: d * 0.62)))
            let faucet = CGRect(x: rect.midX - mm(0.8), y: rect.minY + d * 0.08, width: mm(1.6), height: mm(1.6))
            cg.strokeEllipse(in: faucet)
        case "shower":
            cg.stroke(rect)
            cg.setLineWidth(s3)
            segment(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            segment(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
            let r = min(w, d) * 0.06
            cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case "bathtub":
            cg.stroke(rect)
            cg.setLineWidth(s3)
            stroke(UIBezierPath(roundedRect: rect.insetBy(dx: w * 0.06, dy: d * 0.12), cornerRadius: min(w, d) * 0.3))
            let r = min(w, d) * 0.05
            cg.strokeEllipse(in: CGRect(x: rect.maxX - w * 0.14 - r, y: -r, width: r * 2, height: r * 2))
        case "washer":
            cg.stroke(rect)
            cg.setLineWidth(s3)
            let r = min(w, d) * 0.33
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case "boiler":
            cg.stroke(rect)
            cg.setLineWidth(s3)
            let r = min(w, d) * 0.45
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case "mirror", "towel", "accessory":
            cg.setLineWidth(s3); cg.stroke(rect)
            segment(CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY))
        case "pendant", "sconce", "floorlamp":
            cg.setLineWidth(s3)
            let r = mm(2)
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            segment(CGPoint(x: -r * 0.7, y: -r * 0.7), CGPoint(x: r * 0.7, y: r * 0.7))
            segment(CGPoint(x: r * 0.7, y: -r * 0.7), CGPoint(x: -r * 0.7, y: r * 0.7))
        case "sofa":
            cg.stroke(rect); cg.setLineWidth(s3)
            cg.stroke(CGRect(x: rect.minX, y: rect.minY, width: w, height: d * 0.25))
            cg.stroke(CGRect(x: rect.minX, y: rect.minY, width: w * 0.1, height: d)); cg.stroke(CGRect(x: rect.maxX - w * 0.1, y: rect.minY, width: w * 0.1, height: d))
        case "bed":
            cg.stroke(rect); cg.setLineWidth(s3)
            cg.stroke(CGRect(x: rect.minX, y: rect.minY, width: w, height: d * 0.07))
            cg.stroke(CGRect(x: rect.minX + w * 0.07, y: rect.minY + d * 0.11, width: w * 0.4, height: d * 0.14)); cg.stroke(CGRect(x: rect.midX + w * 0.03, y: rect.minY + d * 0.11, width: w * 0.4, height: d * 0.14))
            segment(CGPoint(x: rect.minX, y: rect.minY + d * 0.35), CGPoint(x: rect.maxX, y: rect.minY + d * 0.35))
        case "kitchen", "storage":
            cg.stroke(rect); cg.setLineWidth(s3)
            segment(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            segment(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
        case "appliance":
            cg.stroke(rect); cg.setLineWidth(s3)
            cg.stroke(rect.insetBy(dx: w * 0.12, dy: d * 0.12))
        case "table", "desk":
            cg.stroke(rect); cg.setLineWidth(s3)
            cg.stroke(rect.insetBy(dx: min(w, d) * 0.06, dy: min(w, d) * 0.06))
        case "chair":
            cg.stroke(rect); cg.setLineWidth(s3)
            cg.stroke(CGRect(x: rect.minX, y: rect.minY, width: w, height: d * 0.2))
        case "plant":
            cg.setLineWidth(s3)
            cg.strokeEllipse(in: rect.insetBy(dx: w * 0.05, dy: d * 0.05))
        default:
            cg.setLineWidth(s3); cg.stroke(rect)
        }
        cg.restoreGState()
        guard numbered else { return }
        // Position number on a leader so it never covers the symbol
        let r = mm(2.2)
        let small = w < mm(10) || d < mm(10)
        let bubble = small ? CGPoint(x: center.x + mm(5), y: center.y - mm(5)) : center
        if bubble != center { line(cg, [center, bubble], s3) }
        cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: CGRect(x: bubble.x - r, y: bubble.y - r, width: r * 2, height: r * 2))
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3); cg.strokeEllipse(in: CGRect(x: bubble.x - r, y: bubble.y - r, width: r * 2, height: r * 2))
        text("\(number)", at: bubble, font: font(6.5, bold: true), centered: true)
    }

    // MARK: Engineering: water (В1, Т3), drainage (К1), sockets, wet zones (ГОСТ 21.601, ГОСТ Р 50571.7.701)

    struct ConnectionPoint {
        let fixture: String
        let at: PlanPoint
        let rows: [(net: String, spec: String, height: String)]
    }

    /// Point on the wall behind an item (its back side, local −z).
    private static func backPoint(_ item: DesignFurniture) -> PlanPoint {
        let angle = item.rotation * .pi / 180
        return PlanPoint(x: item.x + item.depth / 2 * sin(angle), y: item.y - item.depth / 2 * cos(angle))
    }

    /// What every fixture needs and at what height (typical values; refine with the chosen models).
    static func connections(plan: FloorPlan, proposal: DesignProposal?, room: RoomKind) -> [ConnectionPoint] {
        guard let proposal else { return [] }
        var points: [ConnectionPoint] = []
        for item in proposal.furniture {
            let name = item.name.lowercased()
            func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
            let back = backPoint(item)
            switch item.model {
            case "toilet":
                if has("биде") {
                    points.append(ConnectionPoint(fixture: "Биде", at: back, rows: [("В1, Т3", "Ø15", "250"), ("К1", "Ø50", "200")]))
                } else if has("напольн", "компакт") {
                    points.append(ConnectionPoint(fixture: "Унитаз напольный", at: back, rows: [("В1", "Ø15, кран", "200"), ("К1", "Ø110", "180")]))
                } else {
                    points.append(ConnectionPoint(fixture: "Унитаз подвесной", at: back, rows: [("В1", "Ø15, в инсталляции", "750"), ("К1", "Ø110", "230"), ("Инсталляция", "высота рамы 1120", "—")]))
                }
            case "sink":
                var rows: [(net: String, spec: String, height: String)] = [("В1, Т3", "Ø15, разнос 150", "850"), ("К1", "Ø50", "550")]
                if has("подсвет") { rows.append(("Кабель", "подсветка зеркала, IP44", "1800")) }
                points.append(ConnectionPoint(fixture: "Раковина", at: back, rows: rows))
            case "shower":
                points.append(ConnectionPoint(fixture: "Душ", at: back, rows: [("В1, Т3", "смеситель, разнос 150", "1100"), ("Верхний душ", "вывод Ø15", "2100")]))
                points.append(ConnectionPoint(fixture: "Трап", at: PlanPoint(x: (item.x + back.x) / 2, y: (item.y + back.y) / 2), rows: [("К1", "трап Ø50, уклон 1–2 %", "0")]))
            case "bathtub":
                points.append(ConnectionPoint(fixture: "Ванна", at: back, rows: [("В1, Т3", "Ø15, разнос 150", "800"), ("К1", "Ø50, слив‑перелив", "50")]))
            case "washer":
                points.append(ConnectionPoint(fixture: "Стиральная машина", at: back, rows: [("В1", "Ø15, кран", "600"), ("К1", "Ø50, сифон", "600"), ("Розетка IP44", "16 А, УЗО 30 мА", "1000")]))
            case "towel":
                points.append(has("электр")
                    ? ConnectionPoint(fixture: "Полотенцесушитель", at: back, rows: [("Вывод кабеля", "IP44, УЗО 30 мА", "1000")])
                    : ConnectionPoint(fixture: "Полотенцесушитель", at: back, rows: [("Т3", "межосевое 500", "900")]))
            case "boiler":
                points.append(ConnectionPoint(fixture: "Водонагреватель", at: back, rows: [("В1 / Т3", "вход / выход Ø15", "1300"), ("Розетка IP44", "16 А, УЗО 30 мА", "1800")]))
            case "kitchen":
                if has("мойк", "раковин") || room == .kitchen {
                    points.append(ConnectionPoint(fixture: "Мойка", at: back, rows: [("В1, Т3", "Ø15", "550"), ("К1", "Ø50", "450")]))
                }
                if has("плит", "вароч", "индукц") {
                    points.append(ConnectionPoint(fixture: "Варочная панель", at: back, rows: [("Силовая розетка", "32 А, отд. линия", "150")]))
                }
            case "appliance":
                if has("посудомо") {
                    points.append(ConnectionPoint(fixture: "Посудомоечная машина", at: back, rows: [("В1", "Ø15, кран", "450"), ("К1", "Ø50", "450"), ("Розетка", "16 А, УЗО", "300")]))
                } else if has("холод") {
                    points.append(ConnectionPoint(fixture: "Холодильник", at: back, rows: [("Розетка", "16 А", "300")]))
                } else if has("духов") {
                    points.append(ConnectionPoint(fixture: "Духовой шкаф", at: back, rows: [("Розетка", "16 А, отд. линия", "150")]))
                } else if has("вытяж") {
                    points.append(ConnectionPoint(fixture: "Вытяжка", at: back, rows: [("Розетка", "16 А", "2100")]))
                }
            case "mirror":
                if has("подсвет") { points.append(ConnectionPoint(fixture: "Зеркало с подсветкой", at: back, rows: [("Кабель", "IP44", "1800")])) }
            default:
                break
            }
        }
        // Bathroom extraction fan: on the wall nearest to the shower / toilet, under the ceiling.
        if room == .bathroom, !points.isEmpty {
            let wet = proposal.furniture.filter { ["shower", "bathtub", "toilet"].contains($0.model) }
            let target = wet.isEmpty ? PlanPoint(x: (plan.bounds.minX + plan.bounds.maxX) / 2, y: (plan.bounds.minY + plan.bounds.maxY) / 2)
                                     : PlanPoint(x: wet.map(\.x).reduce(0, +) / Double(wet.count), y: wet.map(\.y).reduce(0, +) / Double(wet.count))
            if let wall = nearestWallPoint(plan, to: target) {
                points.append(ConnectionPoint(fixture: "Вытяжной вентилятор", at: wall, rows: [("Вентиляция", "Ø100, обратный клапан", "под потол.")]))
            }
        }
        return points
    }

    private static func nearestWallPoint(_ plan: FloorPlan, to p: PlanPoint) -> PlanPoint? {
        var best: (point: PlanPoint, distance: Double)?
        for wall in plan.walls where wall.length > 0.3 {
            let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y
            let k = max(0.1, min(0.9, ((p.x - wall.start.x) * dx + (p.y - wall.start.y) * dy) / (dx * dx + dy * dy)))
            let q = PlanPoint(x: wall.start.x + dx * k, y: wall.start.y + dy * k)
            let d = q.distance(to: p)
            if d < (best?.distance ?? .infinity) { best = (q, d) }
        }
        return best?.point
    }

    static func engineeringNotes(_ room: RoomKind) -> [String] {
        var notes = [
            "1. Обозначения сетей по ГОСТ 21.601: В1 — холодная вода, Т3 — горячая вода, К1 — бытовая канализация.",
            "2. Высоты выводов — от уровня чистого пола; уточнить по паспортам выбранных приборов.",
            "3. Все розетки — с УЗО 30 мА и заземлением; в помещении с повышенной влажностью — не ниже IP44."
        ]
        if room == .bathroom {
            notes += [
                "4. Зона 2 (0,6 м от душа/ванны, пунктир): розетки, выключатели и распаячные коробки не устанавливать (ГОСТ Р 50571.7.701).",
                "5. Светильники — не ниже IP44, в зоне 1 — IP45; выключатель освещения — снаружи помещения у двери, h 900.",
                "6. Гидроизоляция пола с заведением на стены 200 мм, в душевой зоне — на высоту 2000 мм.",
                "7. Уклон пола к трапу 1–2 %; канализацию Ø50 прокладывать с уклоном не менее 2 %, Ø110 — 1–2 %.",
                "8. Вентиляция: вытяжной вентилятор с обратным клапаном; подрез двери 20 мм для притока воздуха."
            ]
        } else {
            notes.append("4. Мойку размещать не далее 3 м от стояка; варочную панель — на отдельной линии 32 А.")
        }
        return notes
    }

    private static func drawNotes(_ cg: CGContext, at origin: CGPoint, width: CGFloat, title: String, notes: [String]) {
        text(title, at: origin, font: font(9, bold: true))
        var y = origin.y + mm(6)
        for note in notes {
            let attributed = NSAttributedString(string: note, attributes: [.font: font(7.5), .foregroundColor: ink])
            let rect = CGRect(x: origin.x, y: y, width: width, height: mm(30))
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
            y += ceil(attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil).height) + mm(1.2)
        }
    }

    /// Fixtures (thin), wet zones, connection points with numbers.
    private static func drawEngineering(_ cg: CGContext, plan: FloorPlan, proposal: DesignProposal?, points: [ConnectionPoint], room: RoomKind, t: Transform) {
        drawWalls(cg, plan: plan, t: t, hatch: false)
        let items = proposal?.furniture ?? []
        // Electrical zone 2 around shower / bathtub: 0.6 m (dashed), clipped to the room
        if room == .bathroom {
            let polygon = outline(plan).map { t.p($0) }
            for item in items where item.model == "shower" || item.model == "bathtub" {
                var zone = item
                zone.width += 1.2; zone.depth += 1.2
                cg.saveGState()
                cg.addLines(between: polygon); cg.closePath(); cg.clip()
                let corners = zone.corners.map { t.p($0) }
                cg.setFillColor(UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 0.06).cgColor)
                cg.addLines(between: corners); cg.closePath(); cg.fillPath()
                line(cg, corners + [corners[0]], s3, dash: [mm(2), mm(1)])
                cg.restoreGState()
                let label = t.p(zone.corners[0])
                text("зона 2", at: CGPoint(x: label.x + mm(1.5), y: label.y + mm(1)), font: font(6.5))
            }
        }
        for (index, item) in items.enumerated() where item.model != "hiddenlight" { drawFurniture(cg, item: item, number: index + 1, t: t, numbered: false) }
        let center = t.p((plan.bounds.minX + plan.bounds.maxX) / 2, (plan.bounds.minY + plan.bounds.maxY) / 2)
        for (index, point) in points.enumerated() {
            let p = t.p(point.at)
            // Connection point: filled dot on the wall; number in a square on a leader towards the room centre
            cg.setFillColor(ink.cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - mm(0.9), y: p.y - mm(0.9), width: mm(1.8), height: mm(1.8)))
            let dx = center.x - p.x, dy = center.y - p.y, length = max(0.001, hypot(dx, dy))
            let tag = CGPoint(x: p.x + dx / length * mm(7), y: p.y + dy / length * mm(7))
            line(cg, [p, tag], s3)
            let box = CGRect(x: tag.x - mm(2.4), y: tag.y - mm(2.4), width: mm(4.8), height: mm(4.8))
            cg.setFillColor(UIColor.white.cgColor); cg.fill(box)
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s2); cg.stroke(box)
            text("\(index + 1)", at: tag, font: font(7, bold: true), centered: true)
        }
    }

    /// Engineering plan for the presentation (only when there are fixtures to connect).
    static func engineeringPicture(plan: FloorPlan, proposal original: DesignProposal?, size: CGSize = CGSize(width: 540, height: 470)) -> (image: UIImage, points: [ConnectionPoint])? {
        let proposal = original?.placed(in: plan)
        let room = RoomKind.detect(plan: plan, proposal: proposal)
        let points = connections(plan: plan, proposal: proposal, room: room)
        guard !points.isEmpty else { return nil }
        let b = plan.bounds
        let widthM = max(0.5, b.maxX - b.minX), depthM = max(0.5, b.maxY - b.minY)
        let margin = mm(20)
        let ppm = min((size.width - margin * 2) / CGFloat(widthM), (size.height - margin * 2) / CGFloat(depthM))
        let t = Transform(scale: 1000 * 72 / 25.4 / ppm, origin: CGPoint(x: (size.width - CGFloat(widthM) * ppm) / 2 + margin * 0.25, y: (size.height - CGFloat(depthM) * ppm) / 2 + margin * 0.25), minX: b.minX, minY: b.minY)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor.white.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            drawEngineering(cg, plan: plan, proposal: proposal, points: points, room: room, t: t)
            drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
        }
        return (image, points)
    }

    // MARK: Picture for the client presentation (same pens and symbols as the drawings)

    /// Clean architectural plan: without furniture — measured plan with three dimension chains; with furniture — layout with positions.
    static func planPicture(plan: FloorPlan, proposal original: DesignProposal?, furniture: Bool, size: CGSize = CGSize(width: 540, height: 470)) -> UIImage {
        let proposal = original?.placed(in: plan)
        let b = plan.bounds
        let widthM = max(0.5, b.maxX - b.minX), depthM = max(0.5, b.maxY - b.minY)
        let margin = mm(furniture ? 20 : 32)
        let ppm = min((size.width - margin * 2) / CGFloat(widthM), (size.height - margin * 2) / CGFloat(depthM))
        let scale = 1000 * 72 / 25.4 / ppm
        // Shift right/down a little: dimension chains are on the top and the left.
        let origin = CGPoint(x: (size.width - CGFloat(widthM) * ppm) / 2 + margin * 0.25, y: (size.height - CGFloat(depthM) * ppm) / 2 + margin * 0.25)
        let t = Transform(scale: scale, origin: origin, minX: b.minX, minY: b.minY)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor.white.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            if furniture, let proposal, !proposal.furniture.isEmpty {
                drawWalls(cg, plan: plan, t: t, hatch: false)
                for (index, item) in proposal.furniture.enumerated() { drawFurniture(cg, item: item, number: index + 1, t: t) }
                drawDimensionChains(cg, plan: plan, t: t, onlyOverall: true)
            } else {
                drawWalls(cg, plan: plan, t: t, hatch: true)
                drawOpeningMarks(cg, plan: plan, t: t)
                drawDimensionChains(cg, plan: plan, t: t)
                drawInnerDimensions(cg, plan: plan, t: t)
                drawRoomMarker(cg, plan: plan, t: t, number: "1", name: plan.name)
            }
        }
    }

    private static func outline(_ plan: FloorPlan) -> [PlanPoint] {
        let b = plan.bounds
        return plan.floorPolygon.count >= 3 ? plan.floorPolygon : [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
    }

    /// Tiles (bathroom, porcelain stoneware) or boards (parquet, laminate) — chosen from the room and the floor material.
    static func isTiledFloor(_ room: RoomKind, _ finish: DesignFinish?) -> Bool { TileLayout.isTiled(room, finish) }

    private static func drawFloorHatch(_ cg: CGContext, plan: FloorPlan, t: Transform, tiled: Bool = false) {
        let points = outline(plan).map { t.p($0) }
        cg.saveGState()
        cg.addLines(between: points); cg.closePath(); cg.clip()
        cg.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor); cg.setLineWidth(s3)
        let b = plan.bounds
        if tiled {
            // Tiles 600 × 600 mm from the room corner
            var x = b.minX; while x <= b.maxX { line(cg, [t.p(x, b.minY), t.p(x, b.maxY)], s3); x += 0.6 }
            var y = b.minY; while y <= b.maxY { line(cg, [t.p(b.minX, y), t.p(b.maxX, y)], s3); y += 0.6 }
            cg.restoreGState()
            return
        }
        // Parquet / laminate pattern: boards 1.2 × 0.2 m in a staggered layout
        var y = b.minY, row = 0
        while y < b.maxY {
            line(cg, [t.p(b.minX, y), t.p(b.maxX, y)], s3)
            var x = b.minX + (row % 2 == 0 ? 0 : 0.6)
            while x < b.maxX { line(cg, [t.p(x, y), t.p(x, y + 0.2)], s3); x += 1.2 }
            y += 0.2; row += 1
        }
        cg.restoreGState()
    }

    private static func drawHatchLegend(_ cg: CGContext, at origin: CGPoint, title: String, tiled: Bool = false) {
        let box = CGRect(x: origin.x, y: origin.y, width: mm(18), height: mm(10))
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3); cg.stroke(box)
        if tiled {
            var x = box.minX + mm(4.5); while x < box.maxX { line(cg, [CGPoint(x: x, y: box.minY), CGPoint(x: x, y: box.maxY)], s3); x += mm(4.5) }
            line(cg, [CGPoint(x: box.minX, y: box.midY), CGPoint(x: box.maxX, y: box.midY)], s3)
            text("— \(title): плитка 600×600 по экспликации", at: CGPoint(x: box.maxX + mm(3), y: box.minY + mm(3)), font: font(7.5))
            return
        }
        var y = box.minY + mm(2.5), row = 0
        while y < box.maxY { line(cg, [CGPoint(x: box.minX, y: y), CGPoint(x: box.maxX, y: y)], s3); var x = box.minX + (row % 2 == 0 ? mm(3) : mm(9)); while x < box.maxX { line(cg, [CGPoint(x: x, y: y - mm(2.5)), CGPoint(x: x, y: y)], s3); x += mm(12) }; y += mm(2.5); row += 1 }
        text("— \(title): покрытие пола по экспликации", at: CGPoint(x: box.maxX + mm(3), y: box.minY + mm(3)), font: font(7.5))
    }

    // MARK: Tiles

    private static func drawTiles(_ cg: CGContext, layout: TileLayout, t: Transform) {
        for piece in layout.pieces {
            let points = piece.polygon.map { t.p($0) }
            guard points.count >= 3 else { continue }
            if !piece.whole {
                cg.setFillColor(UIColor(white: 0.86, alpha: 1).cgColor)
                cg.addLines(between: points); cg.closePath(); cg.fillPath()
            }
            cg.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor); cg.setLineWidth(s3)
            cg.addLines(between: points); cg.closePath(); cg.strokePath()
        }
    }

    /// Start lines of the layout (the first whole row and column) with their distance from the walls.
    private static func drawTileStart(_ cg: CGContext, layout: TileLayout, plan: FloorPlan, t: Transform) {
        let b = plan.bounds
        let mx = layout.tile.width + layout.joint, my = layout.tile.length + layout.joint
        let x0 = b.minX + TileLayout.positiveRemainder(layout.origin.x - b.minX, mx)
        let y0 = b.minY + TileLayout.positiveRemainder(layout.origin.y - b.minY, my)
        line(cg, [t.p(x0, b.minY), t.p(x0, b.maxY)], s2, dash: [mm(6), mm(1.5), mm(0.5), mm(1.5)])
        line(cg, [t.p(b.minX, y0), t.p(b.maxX, y0)], s2, dash: [mm(6), mm(1.5), mm(0.5), mm(1.5)])
        if x0 - b.minX > 0.005 {
            tickDimension(cg, from: t.p(b.minX, y0 + 0.25), to: t.p(x0, y0 + 0.25), lineOffset: .zero, label: "\(Int(((x0 - b.minX) * 1000).rounded()))")
        }
        if y0 - b.minY > 0.005 {
            tickDimension(cg, from: t.p(x0 + 0.25, y0), to: t.p(x0 + 0.25, b.minY), lineOffset: .zero, label: "\(Int(((y0 - b.minY) * 1000).rounded()))")
        }
        text("начало раскладки", at: CGPoint(x: t.p(x0, y0).x + mm(1.5), y: t.p(x0, y0).y + mm(1.5)), font: font(6.5))
    }

    private static func tileRows(floor: TileLayout, walls: [TileLayout]) -> [[String]] {
        func narrowest(_ layout: TileLayout) -> String { layout.narrowestCut.map { "\(Int(($0 * 1000).rounded())) мм" } ?? "без подрезки" }
        var rows: [[String]] = [
            ["Плитка пола", floor.tile.title],
            ["Шов", "\(Int((floor.joint * 1000).rounded())) мм"],
            ["Площадь пола", "\(area(floor.area)) м²"],
            ["Целых / подрезанных", "\(floor.whole) / \(floor.cut)"],
            ["Самая узкая подрезка", narrowest(floor)],
            ["Купить с запасом 10 %", "\(floor.toBuy) шт. · \(area(floor.buyArea)) м²"]
        ]
        if let first = walls.first {
            let whole = walls.reduce(0) { $0 + $1.whole }, cut = walls.reduce(0) { $0 + $1.cut }, buy = walls.reduce(0) { $0 + $1.toBuy }
            let smallest = walls.compactMap(\.narrowestCut).min()
            rows += [
                ["Плитка стен", first.tile.title],
                ["Площадь облицовки стен", "\(area(walls.reduce(0) { $0 + $1.area })) м²"],
                ["Целых / подрезанных (стены)", "\(whole) / \(cut)"],
                ["Самая узкая подрезка (стены)", smallest.map { "\(Int(($0 * 1000).rounded())) мм" } ?? "без подрезки"],
                ["Купить для стен с запасом 10 %", "\(buy) шт. · \(area(Double(buy) * first.tile.width * first.tile.length)) м²"]
            ]
        }
        return rows
    }

    // MARK: Electrics (ГОСТ 21.210: sockets, switches, lights)

    /// Furniture as a thin grey outline: where the sockets go is clear without the numbers of the layout sheet.
    private static func drawGhost(_ cg: CGContext, item: DesignFurniture, t: Transform) {
        let corners = item.footprint.corners.map { t.p($0) }
        cg.setStrokeColor(UIColor(white: 0.62, alpha: 1).cgColor); cg.setLineWidth(s3)
        cg.addLines(between: corners); cg.closePath(); cg.strokePath()
    }

    private static func drawElectric(_ cg: CGContext, power: ElectricPlan, t: Transform) {
        // Control lines: every switch to its nearest light.
        let lights = power.lights.map { t.p($0.position) }
        for device in power.switches {
            let p = t.p(device.position)
            if let light = lights.min(by: { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }) {
                line(cg, [p, light], s3, dash: [mm(1.5), mm(1)])
            }
        }
        for device in power.points {
            let p = t.p(device.position)
            let facing = CGPoint(x: device.facing.x, y: device.facing.y)
            drawElectricSymbol(cg, device.kind, at: p, facing: facing)
            if device.wall != nil {
                // Height of the device, a little into the room.
                text("\(Int((device.height * 1000).rounded()))", at: CGPoint(x: p.x + facing.x * mm(6), y: p.y + facing.y * mm(6)), font: font(6), centered: true)
            }
        }
    }

    /// A symbol at `point`; wall devices sit on the wall and look along `facing` (into the room).
    private static func drawElectricSymbol(_ cg: CGContext, _ kind: ElectricPoint.Kind, at point: CGPoint, facing: CGPoint) {
        if kind == .ceilingLight { drawLightSymbol(cg, at: point); return }
        let r = mm(1.6)
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y)
        cg.rotate(by: atan2(facing.y, facing.x))
        cg.setStrokeColor(ink.cgColor); cg.setFillColor(ink.cgColor); cg.setLineWidth(s2)
        func segment(_ a: CGPoint, _ b: CGPoint) { cg.move(to: a); cg.addLine(to: b); cg.strokePath() }
        switch kind {
        case .socket, .doubleSocket, .wetSocket, .powerSocket, .tvBlock:
            // Semicircle on the wall; the contact line with the earth bar points into the room.
            cg.addArc(center: .zero, radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            cg.closePath()
            if kind == .wetSocket || kind == .powerSocket { cg.fillPath() } else { cg.strokePath() }
            let offsets: [CGFloat] = kind == .doubleSocket || kind == .tvBlock ? [-r * 0.4, r * 0.4] : [0]
            for y in offsets {
                segment(CGPoint(x: sqrt(max(0, r * r - y * y)), y: y), CGPoint(x: r * 1.9, y: y))
                segment(CGPoint(x: r * 1.9, y: y - r * 0.35), CGPoint(x: r * 1.9, y: y + r * 0.35))
            }
            if kind == .powerSocket { text("32А", at: CGPoint(x: -r * 0.2, y: -r * 2.2), font: font(5.5, bold: true), centered: true) }
            if kind == .tvBlock { text("ТВ", at: CGPoint(x: -r * 0.2, y: -r * 2.2), font: font(5.5, bold: true), centered: true) }
        case .switchOne, .switchTwo:
            let center = CGPoint(x: r * 0.9, y: 0), radius = r * 0.5
            cg.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let direction = CGPoint(x: cos(CGFloat.pi / 4), y: -sin(CGFloat.pi / 4))
            let tip = CGPoint(x: center.x + direction.x * r * 2.2, y: center.y + direction.y * r * 2.2)
            segment(CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius), tip)
            let tick = CGPoint(x: direction.y * r * 0.5, y: -direction.x * r * 0.5)
            for step in kind == .switchTwo ? [0, 0.45] as [CGFloat] : [0] {
                let base = CGPoint(x: tip.x - direction.x * r * step, y: tip.y - direction.y * r * step)
                segment(base, CGPoint(x: base.x + tick.x, y: base.y + tick.y))
            }
        case .pendant:
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            cg.fillEllipse(in: CGRect(x: -r * 0.35, y: -r * 0.35, width: r * 0.7, height: r * 0.7))
        case .wallLight:
            cg.addArc(center: .zero, radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            cg.closePath(); cg.strokePath()
            cg.fillEllipse(in: CGRect(x: r * 0.2, y: -r * 0.3, width: r * 0.6, height: r * 0.6))
        case .ceilingLight:
            break
        }
        cg.restoreGState()
    }

    /// Kind, how many and at what heights (mm), for the schedule.
    private static func electricRows(_ power: ElectricPlan) -> [[String]] {
        ElectricPoint.Kind.allCases.compactMap { kind in
            let items = power.points.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            let heights = Set(items.map { Int(($0.height * 1000).rounded()) }).sorted()
            let shown = kind.isLight && items.allSatisfy({ $0.wall == nil }) ? "потолок" : heights.map(String.init).joined(separator: ", ")
            return [kind.title, "\(items.count)", shown]
        }
    }

    private static func drawElectricLegend(_ cg: CGContext, at origin: CGPoint, kinds: [ElectricPoint.Kind]) {
        text("Условные обозначения", at: origin, font: font(8.5, bold: true))
        for (index, kind) in kinds.enumerated() {
            let y = origin.y + mm(9) + mm(6) * CGFloat(index)
            drawElectricSymbol(cg, kind, at: CGPoint(x: origin.x + mm(3), y: y), facing: CGPoint(x: 1, y: 0))
            text("— " + kind.title.lowercased(), at: CGPoint(x: origin.x + mm(11), y: y - mm(1.8)), font: font(7.5))
        }
    }

    private static func drawLightSymbol(_ cg: CGContext, at point: CGPoint) {
        let r = mm(1.8)
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3)
        cg.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        cg.move(to: CGPoint(x: point.x - r * 0.7, y: point.y - r * 0.7)); cg.addLine(to: CGPoint(x: point.x + r * 0.7, y: point.y + r * 0.7))
        cg.move(to: CGPoint(x: point.x + r * 0.7, y: point.y - r * 0.7)); cg.addLine(to: CGPoint(x: point.x - r * 0.7, y: point.y + r * 0.7))
        cg.strokePath()
    }

    private static func drawLightLegend(_ cg: CGContext, at origin: CGPoint) {
        text("Условные обозначения", at: origin, font: font(8.5, bold: true))
        drawLightSymbol(cg, at: CGPoint(x: origin.x + mm(4), y: origin.y + mm(9)))
        text("— светильник точечный встраиваемый", at: CGPoint(x: origin.x + mm(9), y: origin.y + mm(7.2)), font: font(7.5))
        drawLevelMark(cg, at: CGPoint(x: origin.x + mm(4), y: origin.y + mm(19)), value: "+0,000")
        text("— отметка низа потолка от чистого пола", at: CGPoint(x: origin.x + mm(22), y: origin.y + mm(13.5)), font: font(7.5))
    }

    /// Setting-out chains for the fixtures: first row along X, first column along Y.
    private static func drawLightSettingOut(_ cg: CGContext, lights: [PlanPoint], plan: FloorPlan, t: Transform) {
        guard let firstY = lights.map(\.y).min(), let firstX = lights.map(\.x).min() else { return }
        let b = plan.bounds
        let row = merged(lights.filter { abs($0.y - firstY) < 0.01 }.map(\.x))
        var xs = [b.minX] + row
        xs = merged(xs)
        for (index, x) in xs.dropLast().enumerated() {
            tickDimension(cg, from: t.p(x, firstY), to: t.p(xs[index + 1], firstY), lineOffset: CGPoint(x: 0, y: -mm(5)), label: "\(Int(((xs[index + 1] - x) * 1000).rounded()))", extensionFrom: (t.p(x, firstY), t.p(xs[index + 1], firstY)))
        }
        let column = merged(lights.filter { abs($0.x - firstX) < 0.01 }.map(\.y))
        let ys = merged([b.minY] + column)
        for (index, y) in ys.dropLast().enumerated() {
            tickDimension(cg, from: t.p(firstX, ys[index + 1]), to: t.p(firstX, y), lineOffset: CGPoint(x: -mm(5), y: 0), label: "\(Int(((ys[index + 1] - y) * 1000).rounded()))")
        }
    }

    // MARK: Wall elevations

    private static func drawElevations(_ cg: CGContext, plan: FloorPlan, walls: [PlanSegment], tiles: [TileLayout] = [], in area: CGRect) {
        let height = max(2.2, plan.ceilingHeight)
        let gap = mm(16)
        // Choose the largest standard scale at which all elevations fit in rows.
        var chosen: CGFloat = 200
        for s: CGFloat in [25, 50, 75, 100, 150, 200] {
            let ppm = 1000 / s * 72 / 25.4
            var x: CGFloat = 0, rows = 1
            for wall in walls {
                let w = CGFloat(wall.length) * ppm
                if x + w > area.width { rows += 1; x = 0 }
                x += w + gap
            }
            if CGFloat(rows) * (CGFloat(height) * ppm + mm(26)) <= area.height { chosen = s; break }
        }
        let ppm = 1000 / chosen * 72 / 25.4
        text("М 1:\(Int(chosen))", at: CGPoint(x: area.minX, y: area.minY - mm(12)), font: font(10))
        var x = area.minX, y = area.minY + mm(8)
        let rowHeight = CGFloat(height) * ppm + mm(26)
        let openings = plan.doors + plan.windows
        for (index, wall) in walls.enumerated() {
            let w = CGFloat(wall.length) * ppm, h = CGFloat(height) * ppm
            if x + w > area.maxX { x = area.minX; y += rowHeight }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if index < tiles.count {
                // Wall tiles: rows from the floor, cut pieces in grey.
                for piece in tiles[index].pieces {
                    let p = piece.polygon
                    let r = CGRect(x: rect.minX + CGFloat(p[0].x) * ppm, y: rect.maxY - CGFloat(p[2].y) * ppm, width: CGFloat(p[1].x - p[0].x) * ppm, height: CGFloat(p[2].y - p[1].y) * ppm)
                    if !piece.whole { cg.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor); cg.fill(r) }
                    cg.setStrokeColor(UIColor(white: 0.45, alpha: 1).cgColor); cg.setLineWidth(s3); cg.stroke(r)
                }
            }
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s1); cg.stroke(rect)
            line(cg, [CGPoint(x: rect.minX, y: rect.maxY - mm(0.6)), CGPoint(x: rect.maxX, y: rect.maxY - mm(0.6))], s3) // skirting
            // Openings that lie on this wall
            let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y, length = max(0.001, hypot(dx, dy))
            for opening in openings {
                func along(_ p: PlanPoint) -> Double { ((p.x - wall.start.x) * dx + (p.y - wall.start.y) * dy) / length }
                func distance(_ p: PlanPoint) -> Double { abs((p.x - wall.start.x) * dy - (p.y - wall.start.y) * dx) / length }
                guard distance(opening.start) < 0.25, distance(opening.end) < 0.25 else { continue }
                let s0 = max(0, min(along(opening.start), along(opening.end))), s1v = min(wall.length, max(along(opening.start), along(opening.end)))
                guard s1v - s0 > 0.1 else { continue }
                // Window sill as scanned (0.85 m when unknown), kept low enough for the window to show.
                let bottom: Double = opening.kind == .window ? min(max(0, opening.elevation ?? 0.85), height - 0.5) : 0
                let top: Double = opening.kind == .window ? min(height - 0.2, bottom + max(0.6, opening.height)) : min(height - 0.1, opening.height > 1.5 ? opening.height : 2.1)
                let o = CGRect(x: rect.minX + CGFloat(s0) * ppm, y: rect.maxY - CGFloat(top) * ppm, width: CGFloat(s1v - s0) * ppm, height: CGFloat(top - bottom) * ppm)
                cg.setFillColor(UIColor.white.cgColor); cg.fill(o)
                cg.setLineWidth(s2); cg.stroke(o)
                if opening.kind == .window {
                    line(cg, [CGPoint(x: o.minX, y: o.minY), CGPoint(x: o.midX, y: o.maxY), CGPoint(x: o.maxX, y: o.minY)], s3, dash: [mm(2), mm(1)])
                } else {
                    line(cg, [CGPoint(x: o.minX, y: o.maxY), CGPoint(x: o.maxX, y: o.minY + o.height / 2), CGPoint(x: o.minX, y: o.minY)], s3, dash: [mm(2), mm(1)])
                }
                tickDimension(cg, from: CGPoint(x: o.minX, y: rect.maxY), to: CGPoint(x: o.maxX, y: rect.maxY), lineOffset: CGPoint(x: 0, y: mm(5)), label: "\(Int(((s1v - s0) * 1000).rounded()))")
            }
            tickDimension(cg, from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.maxY), lineOffset: CGPoint(x: 0, y: mm(11)), label: "\(Int((wall.length * 1000).rounded()))")
            tickDimension(cg, from: CGPoint(x: rect.maxX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY), lineOffset: CGPoint(x: mm(5), y: 0), label: "\(Int((height * 1000).rounded()))")
            text("Развёртка стены С\(index + 1)", at: CGPoint(x: rect.minX, y: rect.minY - mm(6)), font: font(8.5, bold: true))
            x += w + gap
        }
    }

    // MARK: Tables

    private static func drawTable(_ cg: CGContext, at origin: CGPoint, title: String, columns: [(String, CGFloat)], rows: [[String]]) {
        let rowHeight = mm(6), headerHeight = mm(9)
        let widths = columns.map { mm($0.1) }
        let width = widths.reduce(0, +)
        text(title, at: CGPoint(x: origin.x, y: origin.y), font: font(9, bold: true))
        var y = origin.y + mm(6)
        func drawRow(_ values: [String], header: Bool) {
            let h = header ? headerHeight : rowHeight
            var x = origin.x
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(header ? s1 : s3)
            cg.stroke(CGRect(x: origin.x, y: y, width: width, height: h))
            for (index, columnWidth) in widths.enumerated() {
                if index > 0 { line(cg, [CGPoint(x: x, y: y), CGPoint(x: x, y: y + h)], header ? s1 : s3) }
                let value = index < values.count ? values[index] : ""
                if header { text(value, at: CGPoint(x: x + columnWidth / 2, y: y + h / 2), font: font(7, bold: true), centered: true) }
                else { text(value, at: CGPoint(x: x + mm(1), y: y + mm(1.3)), font: font(7.5), maxWidth: columnWidth - mm(2)) }
                x += columnWidth
            }
            y += h
        }
        drawRow(columns.map(\.0), header: true)
        for row in rows.prefix(38) { drawRow(row, header: false) }
        cg.setLineWidth(s1); cg.stroke(CGRect(x: origin.x, y: origin.y + mm(6), width: width, height: y - origin.y - mm(6)))
    }

    private static func drawGeneralData(_ cg: CGContext, frame: CGRect, titles: [String], plan: FloorPlan, proposal: DesignProposal?, projectName: String) {
        let x0 = frame.minX + mm(15), y0 = frame.minY + mm(28)
        drawTable(cg, at: CGPoint(x: x0, y: y0), title: "Ведомость рабочих чертежей основного комплекта",
                  columns: [("Лист", 15), ("Наименование", 120), ("Примечание", 45)],
                  rows: titles.enumerated().map { ["\($0.offset + 1)", $0.element, $0.offset == 0 ? "" : "А3"] })
        drawTable(cg, at: CGPoint(x: x0, y: y0 + mm(70)), title: "Экспликация помещений",
                  columns: [("Номер", 15), ("Наименование", 80), ("Площадь, м²", 30), ("Высота, м", 25), ("Кат.", 15)],
                  rows: [["1", plan.name, area(plan.area), meters(plan.ceilingHeight), "—"]])
        let notesX = x0 + mm(200)
        text("Общие указания", at: CGPoint(x: notesX, y: y0), font: font(9, bold: true))
        let notes = [
            "1. Рабочие чертежи разработаны на основании обмеров помещения, выполненных лазерным сканированием (LiDAR) с последующей обработкой.",
            "2. Размеры даны в миллиметрах, отметки — в метрах. За отметку ±0,000 принят уровень чистого пола помещения.",
            "3. Погрешность обмера — не более 10–20 мм на 1 м. До начала работ размеры и отметки уточнить по месту.",
            "4. Толщина стен показана условно (150 мм) и подлежит уточнению вскрытием.",
            "5. Отделочные материалы — по ведомости отделки помещений и спецификации. Допускается замена на аналоги по согласованию с заказчиком.",
            "6. Расположение светильников — ориентировочное; электротехнические решения выполнить по разделу ЭМ.",
            "7. Работы выполнять в соответствии с СП 71.13330.2017 «Изоляционные и отделочные покрытия»."
        ]
        var y = y0 + mm(7)
        for note in notes {
            let attributed = NSAttributedString(string: note, attributes: [.font: font(8)])
            let rect = CGRect(x: notesX, y: y, width: mm(170), height: mm(30))
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
            y += ceil(attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil).height) + mm(2)
        }
        // Legend of the drawings
        y += mm(6)
        text("Условные обозначения", at: CGPoint(x: notesX, y: y), font: font(9, bold: true))
        y += mm(8)
        let wallBox = CGRect(x: notesX, y: y, width: mm(14), height: mm(5))
        cg.saveGState(); cg.addRect(wallBox); cg.clip()
        var hx = wallBox.minX - wallBox.height
        while hx < wallBox.maxX { cg.move(to: CGPoint(x: hx, y: wallBox.maxY)); cg.addLine(to: CGPoint(x: hx + wallBox.height, y: wallBox.minY)); hx += mm(1.6) }
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(s3); cg.strokePath(); cg.restoreGState()
        cg.setLineWidth(s1); cg.stroke(wallBox)
        text("— стены существующие (в разрезе)", at: CGPoint(x: wallBox.maxX + mm(3), y: wallBox.minY + mm(0.5)), font: font(7.5))
        y += mm(9)
        text("Д1, ОК1 — марки дверных и оконных проёмов;   С1 — номер стены (см. развёртки)", at: CGPoint(x: notesX, y: y), font: font(7.5))
        y += mm(6)
        text("1 — номер помещения;   площадь, м² — под чертой", at: CGPoint(x: notesX, y: y), font: font(7.5))
        if let proposal {
            y += mm(10)
            text("Концепция интерьера: \(proposal.title) (\(proposal.style))", at: CGPoint(x: notesX, y: y), font: font(8.5, bold: true), maxWidth: mm(170))
        }
        _ = projectName
    }

    private static func drawFinishSchedule(_ cg: CGContext, origin: CGPoint, plan: FloorPlan, proposal: DesignProposal?) {
        func describe(_ finish: DesignFinish?) -> String {
            guard let finish, !finish.isEmpty else { return "По проекту" }
            return [finish.material, finish.details].filter { !$0.isEmpty }.joined(separator: ". ")
        }
        let skirting = max(0, plan.perimeter - plan.doors.reduce(0) { $0 + $1.length })
        // ГОСТ 21.501 form: room | ceiling | area | walls | area | skirting | area | note
        drawTable(cg, at: origin, title: "Ведомость отделки помещений",
                  columns: [("Наименование помещения", 38), ("Потолок", 62), ("Пл., м²", 16), ("Стены и перегородки", 62), ("Пл., м²", 16), ("Плинтус / низ стен", 36), ("Кол., п.м", 16), ("Примечание", 34)],
                  rows: [[plan.name, describe(proposal?.ceiling), area(plan.area), describe(proposal?.walls), area(plan.netWallArea), "Плинтус напольный", meters(skirting), "Пол — см. экспликацию полов"]])
        if let proposal, !proposal.materials.isEmpty {
            drawTable(cg, at: CGPoint(x: origin.x, y: origin.y + mm(50)), title: "Спецификация отделочных материалов",
                      columns: [("Поз.", 12), ("Наименование", 95), ("Место применения", 110), ("Кол-во", 45)],
                      rows: proposal.materials.enumerated().map { ["\($0.offset + 1)", $0.element.name, $0.element.where, $0.element.amount] })
        }
    }
}

private extension String {
    func orDefault(_ fallback: String) -> String { trimmingCharacters(in: .whitespaces).isEmpty ? fallback : self }
}
