import Foundation

// MARK: - Расчёт материалов комнаты по скану: плитка (по раскладке), клей, затирка, СВП, грунт, гидроизоляция,
// штукатурка по маякам, стяжка, наливной пол, шпаклёвка и краска, ламинат, плинтус.
// Нормы — типовые нормы расхода производителей (Ceresit, Knauf, Litokol, Bergauf…) и СП 71.13330.2017.
// Всё считается по точной геометрии: площадь пола по контуру, стены за вычетом дверей и окон, высота облицовки.

struct RoomWorks: Codable, Equatable {
    // Плитка
    var floorTiles = false
    var floorTileWidthMM = 600.0
    var floorTileLengthMM = 600.0
    var wallTiles = false
    var wallTileWidthMM = 600.0     // вдоль стены
    var wallTileLengthMM = 300.0    // вверх
    /// Высота облицовки стен, м (0 — до потолка).
    var wallTileHeight = 0.0
    var jointMM = 2.0
    var tileThicknessMM = 9.0
    // Санузел
    var waterproofing = false
    /// Душевая зона без поддона — две стены по 1,2 м на высоту 2 м под гидроизоляцию.
    var showerZone = false
    // Черновые
    var plaster = false
    var plasterThicknessMM = 15.0
    var plasterCement = false       // цементная (санузел) или гипсовая
    var screed = false
    var screedThicknessMM = 50.0
    var selfLeveling = false
    var selfLevelingMM = 5.0
    // Чистовые
    var paintWalls = false
    var paintCeiling = false
    var laminate = false
    var skirting = false

    /// Разумные работы по типу комнаты: санузел — плитка, гидроизоляция, цементная штукатурка; жилая — стяжка, покраска, ламинат.
    static func suggested(for room: RoomKind) -> RoomWorks {
        var w = RoomWorks()
        switch room {
        case .bathroom:
            w.floorTiles = true; w.wallTiles = true; w.waterproofing = true; w.showerZone = true
            w.plaster = true; w.plasterCement = true; w.screed = true; w.screedThicknessMM = 40; w.paintCeiling = true
            w.floorTileWidthMM = 300; w.floorTileLengthMM = 300
        case .kitchen:
            w.floorTiles = true; w.plaster = true; w.screed = true; w.paintWalls = true; w.paintCeiling = true
        case .garage, .warehouse:
            w.screed = true; w.screedThicknessMM = 70; w.paintWalls = true
        default:
            w.plaster = true; w.screed = true; w.selfLeveling = true; w.paintWalls = true; w.paintCeiling = true
            w.laminate = true; w.skirting = true
        }
        return w
    }
}

struct MaterialLine: Identifiable, Equatable {
    var id: String { name }
    var name: String
    /// Количество в расчётных единицах (кг, м², шт, л, м).
    var quantity: Double
    var unit: String
    /// Сколько покупать упаковками: «4 мешка по 25 кг».
    var packs: Int?
    var pack: String?
    /// Откуда норма: «5,5 кг/м² (гребёнка 10 мм)».
    var norm: String
}

struct MaterialGroup: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var lines: [MaterialLine]
}

struct RoomSurfaces: Equatable {
    var floor: Double
    var ceiling: Double
    var perimeter: Double
    var height: Double
    var wallsGross: Double
    var openings: Double
    var wallsNet: Double
    var doorsWidth: Double
    var doors: Int
    var windows: Int
}

enum RoomMaterials {
    /// Формат чисел в тексте норм: по умолчанию русский; приложение при запуске ставит язык пользователя.
    static var locale = Locale(identifier: "ru_RU")

    static func surfaces(_ plan: FloorPlan) -> RoomSurfaces {
        let doorsWidth = plan.doors.reduce(0) { $0 + $1.length }
        return RoomSurfaces(floor: plan.area, ceiling: plan.area, perimeter: plan.perimeter, height: plan.ceilingHeight,
                            wallsGross: plan.perimeter * plan.ceilingHeight, openings: plan.openingsArea, wallsNet: plan.netWallArea,
                            doorsWidth: doorsWidth, doors: plan.doors.count, windows: plan.windows.count)
    }

    /// Клей для плитки, кг/м²: чем крупнее плитка, тем крупнее гребёнка (нормы Ceresit CM 11/CM 17, Litokol).
    static func adhesiveRate(longSide: Double) -> (rate: Double, comb: Int) {
        switch longSide {
        case ..<0.15: return (2.5, 6)
        case ..<0.35: return (4.0, 8)
        case ..<0.65: return (5.5, 10)
        default: return (7.5, 12)
        }
    }

    /// Затирка, кг/м²: (A + B) / (A × B) × толщина × ширина шва × 1,6 (A, B, толщина, шов — мм), +10 %.
    static func groutRate(widthMM: Double, lengthMM: Double, thicknessMM: Double, jointMM: Double) -> Double {
        (widthMM + lengthMM) / (widthMM * lengthMM) * thicknessMM * jointMM * 1.6 * 1.1
    }

    private static func packs(_ quantity: Double, per pack: Double) -> Int { max(1, Int((quantity / pack).rounded(.up))) }
    private static func fmt(_ v: Double, _ digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.minimumFractionDigits = digits; f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Облицовка стен на высоту `height` (doors/windows вычтены) — раскладкой, как на чертежах.
    static func wallTiles(_ plan: FloorPlan, tile: TileSize, joint: Double, height: Double) -> [TileLayout] {
        PlanWalls.numbered(plan).map { side in
            var holes: [(Double, Double, Double, Double)] = []
            for door in side.doors { holes.append((door.from, 0, door.to, min(height, door.segment.height > 1.5 ? door.segment.height : 2.1))) }
            for window in side.windows {
                let sill = min(max(0, window.segment.elevation ?? 0.85), plan.ceilingHeight - 0.3)
                if sill < height { holes.append((window.from, sill, window.to, min(height, sill + max(0.3, window.segment.height)))) }
            }
            return TileLayout.wall(length: side.length, height: height, holes: holes, tile: tile, joint: joint)
        }
    }

    static func calculate(_ plan: FloorPlan, works w: RoomWorks) -> [MaterialGroup] {
        let s = surfaces(plan)
        var groups: [MaterialGroup] = []
        let joint = w.jointMM / 1000

        // ---------- Плитка ----------
        var tiled: [MaterialLine] = []
        var tiledArea = 0.0
        var tilesForClips = 0
        func tileLines(_ layouts: [TileLayout], _ tile: TileSize, surface: String) {
            let pieces = layouts.reduce(0) { $0 + $1.pieces.count }
            let area = layouts.reduce(0) { $0 + $1.area }
            guard pieces > 0 else { return }
            let buy = Int((Double(pieces) * 1.1).rounded(.up))
            let cut = layouts.reduce(0) { $0 + $1.cut }
            let perBox = boxArea(tile)
            let buyArea = Double(buy) * tile.width * tile.length
            tiled.append(MaterialLine(name: "Плитка \(tile.title) — \(surface)", quantity: buyArea, unit: "м²",
                                      packs: packs(buyArea, per: perBox), pack: "коробка ≈ \(fmt(perBox, 2)) м²",
                                      norm: "\(buy) шт по раскладке (\(pieces) + 10 % запас; подрезок \(cut))"))
            tiledArea += area
            if max(tile.width, tile.length) >= 0.3 { tilesForClips += buy }
            let adhesive = adhesiveRate(longSide: max(tile.width, tile.length))
            let kg = area * adhesive.rate
            tiled.append(MaterialLine(name: "Плиточный клей — \(surface)", quantity: kg, unit: "кг", packs: packs(kg, per: 25), pack: "мешок 25 кг",
                                      norm: "\(fmt(adhesive.rate)) кг/м², гребёнка \(adhesive.comb) мм"))
            let grout = groutRate(widthMM: tile.width * 1000, lengthMM: tile.length * 1000, thicknessMM: w.tileThicknessMM, jointMM: w.jointMM) * area
            tiled.append(MaterialLine(name: "Затирка — \(surface)", quantity: grout, unit: "кг", packs: packs(grout, per: 2), pack: "упаковка 2 кг",
                                      norm: "шов \(fmt(w.jointMM, 0)) мм, плитка \(fmt(w.tileThicknessMM, 0)) мм"))
        }
        if w.floorTiles {
            let tile = TileSize(width: w.floorTileWidthMM / 1000, length: w.floorTileLengthMM / 1000)
            tileLines([TileLayout.floor(plan, tile: tile, joint: joint)], tile, surface: "пол")
        }
        if w.wallTiles {
            let tile = TileSize(width: w.wallTileWidthMM / 1000, length: w.wallTileLengthMM / 1000)
            let height = w.wallTileHeight > 0.3 ? min(w.wallTileHeight, s.height) : s.height
            tileLines(wallTiles(plan, tile: tile, joint: joint, height: height), tile, surface: "стены до \(fmt(height, 2)) м")
        }
        if tilesForClips > 0 {
            tiled.append(MaterialLine(name: "СВП: клипсы", quantity: Double(tilesForClips * 3), unit: "шт", packs: packs(Double(tilesForClips * 3), per: 100),
                                      pack: "упаковка 100 шт", norm: "≈3 клипсы на плитку от 30 см; клинья многоразовые — 1 набор"))
        }
        if tiledArea > 0 {
            let primer = tiledArea * 0.15
            tiled.append(MaterialLine(name: "Грунт глубокого проникновения под плитку", quantity: primer, unit: "л", packs: packs(primer, per: 10),
                                      pack: "канистра 10 л", norm: "0,15 л/м², 1 слой"))
            tiled.append(MaterialLine(name: "Крестики или клинья для шва", quantity: 1, unit: "набор", packs: nil, pack: nil, norm: "шов \(fmt(w.jointMM, 0)) мм"))
        }
        if !tiled.isEmpty { groups.append(MaterialGroup(title: "Плитка", lines: tiled)) }

        // ---------- Гидроизоляция ----------
        if w.waterproofing {
            let walls = s.perimeter * 0.3 + (w.showerZone ? 2 * 1.2 * 2.0 : 0)
            let area = s.floor + walls
            let kg = area * 1.5
            let tape = s.perimeter * 1.1 + 4 * 0.3 + (w.showerZone ? 2 * 2.0 : 0)
            groups.append(MaterialGroup(title: "Гидроизоляция", lines: [
                MaterialLine(name: "Обмазочная гидроизоляция", quantity: kg, unit: "кг", packs: packs(kg, per: 15), pack: "ведро 15 кг",
                             norm: "1,5 кг/м² в 2 слоя: пол \(fmt(s.floor)) м² + стены \(fmt(walls)) м² (заход 30 см\(w.showerZone ? ", душевая зона 2 м" : ""))"),
                MaterialLine(name: "Гидроизоляционная лента", quantity: tape, unit: "м", packs: packs(tape, per: 10), pack: "рулон 10 м",
                             norm: "стык пола и стен, углы\(w.showerZone ? ", углы душевой" : "")"),
                MaterialLine(name: "Манжеты для труб и трапа", quantity: 3, unit: "шт", packs: nil, pack: nil, norm: "по числу выводов — уточните"),
                MaterialLine(name: "Грунт под гидроизоляцию", quantity: area * 0.15, unit: "л", packs: packs(area * 0.15, per: 5), pack: "канистра 5 л", norm: "0,15 л/м²"),
            ]))
        }

        // ---------- Штукатурка по маякам ----------
        if w.plaster {
            let rate = (w.plasterCement ? 1.7 : 0.85) * w.plasterThicknessMM   // кг/м² на мм: цементная 17, гипсовая 8,5 кг/м² на 10 мм
            let kg = s.wallsNet * rate
            let walls = PlanWalls.numbered(plan)
            let rows = max(1, Int((s.height / 3.0).rounded(.up)))
            let beacons = walls.reduce(0) { $0 + (Int(($1.length / 1.3).rounded(.up)) + 1) * rows }
            let beaconSize = w.plasterThicknessMM >= 12 ? 10 : 6
            groups.append(MaterialGroup(title: "Штукатурка стен по маякам", lines: [
                MaterialLine(name: w.plasterCement ? "Цементная штукатурка" : "Гипсовая штукатурка", quantity: kg, unit: "кг",
                             packs: packs(kg, per: w.plasterCement ? 25 : 30), pack: w.plasterCement ? "мешок 25 кг" : "мешок 30 кг",
                             norm: "\(fmt(rate * 10, 1)) кг/м² на 10 мм × \(fmt(w.plasterThicknessMM, 0)) мм, стены \(fmt(s.wallsNet)) м² без проёмов"),
                MaterialLine(name: "Маяки штукатурные \(beaconSize) мм, 3 м", quantity: Double(beacons), unit: "шт", packs: nil, pack: nil,
                             norm: "шаг ≤ 1,3 м по каждой стене, \(rows) ряд(а) по высоте"),
                MaterialLine(name: "Грунт перед штукатуркой", quantity: s.wallsNet * 0.15, unit: "л", packs: packs(s.wallsNet * 0.15, per: 10), pack: "канистра 10 л", norm: "0,15 л/м²"),
                MaterialLine(name: "Уголки для откосов и углов", quantity: Double(s.doors * 2 + s.windows * 3 + 4), unit: "шт (3 м)", packs: nil, pack: nil,
                             norm: "двери ×2, окна ×3, наружные углы — уточните"),
            ]))
        }

        // ---------- Стяжка ----------
        if w.screed {
            let kg = s.floor * w.screedThicknessMM * 2.0          // ЦПС ≈ 2 кг/м² на 1 мм
            let rows = Int((plan.depth / 1.3).rounded(.up)) + 1
            let beaconMeters = Double(rows) * plan.width
            let volume = s.floor * w.screedThicknessMM / 1000
            groups.append(MaterialGroup(title: "Стяжка пола", lines: [
                MaterialLine(name: "Пескобетон / ЦПС М150", quantity: kg, unit: "кг", packs: packs(kg, per: 40), pack: "мешок 40 кг",
                             norm: "2 кг/м² на 1 мм × \(fmt(w.screedThicknessMM, 0)) мм, пол \(fmt(s.floor)) м²"),
                MaterialLine(name: "Маяки для стяжки 10 мм, 3 м", quantity: Double(Int((beaconMeters / 3).rounded(.up))), unit: "шт", packs: nil, pack: nil,
                             norm: "\(rows) ряд(ов) через ≤ 1,3 м"),
                MaterialLine(name: "Демпферная лента", quantity: s.perimeter * 1.05, unit: "м", packs: packs(s.perimeter * 1.05, per: 25), pack: "рулон 25 м", norm: "по периметру"),
                MaterialLine(name: "Фиброволокно", quantity: volume * 0.9, unit: "кг", packs: nil, pack: nil, norm: "0,9 кг на 1 м³ раствора"),
                MaterialLine(name: "Плёнка полиэтиленовая 200 мкм", quantity: s.floor * 1.15, unit: "м²", packs: nil, pack: nil, norm: "с нахлёстом 15 %"),
            ]))
        }
        if w.selfLeveling {
            let kg = s.floor * w.selfLevelingMM * 1.6
            groups.append(MaterialGroup(title: "Наливной пол", lines: [
                MaterialLine(name: "Наливной пол (финишный)", quantity: kg, unit: "кг", packs: packs(kg, per: 25), pack: "мешок 25 кг",
                             norm: "1,6 кг/м² на 1 мм × \(fmt(w.selfLevelingMM, 0)) мм"),
                MaterialLine(name: "Грунт перед наливным полом", quantity: s.floor * 0.15, unit: "л", packs: packs(s.floor * 0.15, per: 10), pack: "канистра 10 л", norm: "0,15 л/м²"),
            ]))
        }

        // ---------- Покраска ----------
        let paintArea = (w.paintWalls ? max(0, s.wallsNet - (w.wallTiles ? tiledAreaWalls(plan, w) : 0)) : 0) + (w.paintCeiling ? s.ceiling : 0)
        if paintArea > 0 {
            let putty = paintArea * 1.2
            let liters = paintArea * 0.24
            let paint = [
                MaterialLine(name: "Шпаклёвка финишная", quantity: putty, unit: "кг", packs: packs(putty, per: 20), pack: "мешок 20 кг", norm: "1,2 кг/м² (слой ~1 мм)"),
                MaterialLine(name: "Грунт под покраску", quantity: paintArea * 0.12, unit: "л", packs: packs(paintArea * 0.12, per: 10), pack: "канистра 10 л", norm: "0,12 л/м²"),
                MaterialLine(name: "Краска интерьерная", quantity: liters, unit: "л", packs: packs(liters, per: 9), pack: "ведро 9 л",
                             norm: "0,12 л/м² × 2 слоя, площадь \(fmt(paintArea)) м²"),
                MaterialLine(name: "Сетка (серпянка) и шкурка", quantity: 1, unit: "набор", packs: nil, pack: nil, norm: "по углам и стыкам"),
            ]
            groups.append(MaterialGroup(title: "Шпаклёвка и покраска", lines: paint))
        }

        // ---------- Пол: ламинат и плинтус ----------
        var floor: [MaterialLine] = []
        if w.laminate && !w.floorTiles {
            let area = s.floor * 1.07
            floor.append(MaterialLine(name: "Ламинат", quantity: area, unit: "м²", packs: packs(area, per: 2.0), pack: "упаковка ≈ 2 м²", norm: "площадь + 7 % на подрезку"))
            floor.append(MaterialLine(name: "Подложка", quantity: s.floor * 1.05, unit: "м²", packs: packs(s.floor * 1.05, per: 10), pack: "рулон 10 м²", norm: "+5 %"))
        }
        if w.skirting {
            let length = max(0, s.perimeter - s.doorsWidth) * 1.05
            floor.append(MaterialLine(name: "Плинтус напольный", quantity: length, unit: "м", packs: packs(length, per: 2.5), pack: "планка 2,5 м",
                                      norm: "периметр без дверей + 5 %"))
            floor.append(MaterialLine(name: "Углы и заглушки плинтуса", quantity: Double(max(4, plan.walls.count) + s.doors * 2), unit: "шт", packs: nil, pack: nil,
                                      norm: "по углам комнаты и у дверей"))
        }
        if !floor.isEmpty { groups.append(MaterialGroup(title: "Напольное покрытие", lines: floor)) }
        return groups
    }

    /// Площадь стен под плиткой (чтобы не красить то, что облицовано).
    static func tiledAreaWalls(_ plan: FloorPlan, _ w: RoomWorks) -> Double {
        guard w.wallTiles else { return 0 }
        let tile = TileSize(width: w.wallTileWidthMM / 1000, length: w.wallTileLengthMM / 1000)
        let height = w.wallTileHeight > 0.3 ? min(w.wallTileHeight, plan.ceilingHeight) : plan.ceilingHeight
        return wallTiles(plan, tile: tile, joint: w.jointMM / 1000, height: height).reduce(0) { $0 + $1.area }
    }

    /// Типовая площадь коробки по формату плитки, м².
    static func boxArea(_ tile: TileSize) -> Double {
        let a = tile.width * tile.length
        switch a {
        case ..<0.05: return 1.0          // мелкий формат
        case ..<0.1: return 1.08          // 20×40, 30×30
        case ..<0.2: return 1.08          // 30×60
        case ..<0.4: return 1.44          // 60×60
        default: return a * 2             // 60×120 и крупнее — 2 шт в коробке
        }
    }

    /// Текст для «Поделиться» и для поиска цен.
    static func text(_ plan: FloorPlan, groups: [MaterialGroup]) -> String {
        var lines = ["Материалы: \(plan.name) — пол \(fmt(plan.area)) м², стены \(fmt(plan.netWallArea)) м², потолок \(fmt(plan.ceilingHeight, 2)) м"]
        for group in groups {
            lines.append("\n\(group.title.uppercased())")
            for line in group.lines {
                let packs = line.packs.map { " → \($0) × \(line.pack ?? "")" } ?? ""
                lines.append("• \(line.name): \(fmt(line.quantity)) \(line.unit)\(packs)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
