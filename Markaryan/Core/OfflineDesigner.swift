import Foundation

/// Built‑in designer: works on the iPhone without any AI or internet.
/// Chooses real‑size furniture and fixtures for the room type and the client's wishes, says where they belong
/// (against a wall, in a corner, next to the bed…) and lets `LayoutEngine` place them by the same rules as AI concepts;
/// finishes, palette, materials and budget come from the chosen style.
enum OfflineDesigner {
    // MARK: What goes into the room

    private static func items(_ room: RoomKind, plan: FloorPlan, wishes: String, purpose: String) -> [DesignBrief.Item] {
        let w = wishes.lowercased(), p = purpose.lowercased()
        let area = plan.area
        let narrow = min(plan.width, plan.depth)
        var list: [DesignBrief.Item] = []
        /// Adds an item and returns its number in the brief (from 1) for relations.
        @discardableResult
        func add(_ name: String, _ kind: String, _ width: Double, _ depth: Double, _ placement: DesignBrief.Placement = .wall,
                 relation: DesignBrief.Relation = .none, to target: Int = 0, prefer: DesignBrief.Preference = .none,
                 optional: Bool = false, count: Int = 1, zone: String = "") -> Int {
            list.append(DesignBrief.Item(name: name, kind: kind, width: width, depth: depth, count: count, placement: placement,
                                         relation: relation, target: target, prefer: prefer, optional: optional, zone: zone))
            return list.count
        }
        switch room {
        case .bathroom:
            let wantsBath = w.contains("ванн") && !w.contains("без ванн")
            let compact = narrow < 1.7 || area < 4
            if wantsBath {
                add("Ванна акриловая 1700×750", "bathtub", 1.7, 0.75, .corner, prefer: .farFromDoor)
            } else {
                add(compact ? "Душевая зона 800×800 с трапом" : "Душевая зона с трапом и стеклянной перегородкой", "shower", compact ? 0.8 : 0.9, compact ? 0.8 : 0.9, .corner, prefer: .farFromDoor)
            }
            add("Унитаз подвесной на инсталляции", "toilet", 0.4, 0.55, prefer: .water)
            let sink = add(compact ? "Тумба с раковиной 500 и зеркало" : "Тумба с раковиной 600 и зеркало", "sink", compact ? 0.5 : 0.6, compact ? 0.42 : 0.47, prefer: .water)
            if area >= 3.8 && !w.contains("без стирал") { add("Стиральная машина", "washer", 0.6, 0.6, relation: .nextTo, to: sink, optional: true) }
            add("Полотенцесушитель водяной", "towel", 0.5, 0.1, .mounted, prefer: .water, optional: true)
            if area >= 4.5 { add("Шкаф‑пенал", "storage", 0.4, 0.35, optional: true) }
        case .kitchen:
            // Leaves room for the fridge on the same wall: round the corner it often lands in front of the window.
            let longest = PlanWalls.numbered(plan).map(\.length).max() ?? 3
            let run = add("Кухонный гарнитур с мойкой и варочной панелью", "kitchen", max(1.8, min(3.0, area.squareRoot() * 0.9, longest - 0.7)), 0.6, .corner)
            add("Холодильник", "appliance", 0.6, 0.65, relation: .nextTo, to: run, optional: true)
            if area >= 6 {
                let table = add("Обеденный стол", "table", area > 10 ? 1.2 : 0.9, 0.8, .free, optional: true)
                add("Стул", "chair", 0.45, 0.5, relation: .around, to: table, optional: true, count: area > 10 ? 4 : 2)
            }
            add("Растение в кашпо", "plant", 0.4, 0.4, .corner, optional: true)
        case .bedroom:
            let bedWidth = area > 11 ? 1.6 : 1.4
            let bed = add(bedWidth > 1.5 ? "Кровать 1600×2000" : "Кровать 1400×2000", "bed", bedWidth, 2.05, prefer: .farFromDoor)
            add("Прикроватная тумба", "storage", 0.45, 0.4, relation: .nextTo, to: bed, optional: true, count: 2)
            add("Шкаф для одежды", "storage", area > 12 ? 1.8 : 1.2, 0.6, .corner, optional: true)
            let desk = add("Рабочий стол", "desk", 1.2, 0.6, prefer: .window, optional: true)
            add("Рабочее кресло", "chair", 0.55, 0.55, relation: .front, to: desk, optional: true)
            add("Растение в кашпо", "plant", 0.4, 0.4, .corner, optional: true)
        case .kids:
            add("Кровать 900×2000", "bed", 0.9, 2.05, .corner, prefer: .farFromDoor)
            let desk = add("Письменный стол", "desk", 1.2, 0.6, prefer: .window)
            add("Рабочее кресло", "chair", 0.5, 0.5, relation: .front, to: desk)
            add("Шкаф", "storage", 1.2, 0.6, .corner, optional: true)
            add("Стеллаж для игрушек", "storage", 0.8, 0.35, optional: true)
            add("Игровой коврик", "decor", 1.4, 1.0, .free, optional: true)
        case .office:
            let desk = add("Рабочий стол", "desk", 1.4, 0.7, prefer: .window)
            add("Рабочее кресло", "chair", 0.55, 0.55, relation: .front, to: desk)
            add("Стеллаж", "storage", 1.2, 0.4, .corner, optional: true)
            add("Кресло для отдыха", "chair", 0.8, 0.8, .corner, optional: true)
            add("Растение в кашпо", "plant", 0.4, 0.4, .corner, optional: true)
        case .hall:
            add("Шкаф‑купе", "storage", min(1.8, max(1.0, area.squareRoot())), 0.6, .corner)
            let shoes = add("Обувница", "storage", 0.8, 0.35, prefer: .door, optional: true)
            add("Банкетка", "chair", 0.8, 0.4, relation: .nextTo, to: shoes, optional: true)
            add("Зеркало в полный рост", "mirror", 0.6, 0.03, .mounted, prefer: .door, optional: true)
        case .living:
            let withKitchen = p.contains("кухн") || p.contains("студи")
            let zone = withKitchen ? "Гостиная" : ""
            if withKitchen {
                add("Кухонный гарнитур с мойкой и варочной панелью", "kitchen", min(3.0, max(1.8, area.squareRoot() * 0.6)), 0.6, .corner, zone: "Кухня")
                if area >= 9 {
                    let table = add("Обеденный стол", "table", 1.2, 0.8, .free, optional: true, zone: "Кухня")
                    add("Стул", "chair", 0.45, 0.5, relation: .around, to: table, optional: true, count: 4, zone: "Кухня")
                }
            }
            let sofa = add(area > 18 ? "Диван 2400" : "Диван 2000", "sofa", area > 18 ? 2.4 : 2.0, 0.95, zone: zone)
            add("Журнальный столик", "table", 1.0, 0.55, relation: .front, to: sofa, optional: true, zone: zone)
            add("ТВ‑зона с тумбой", "tv", 1.6, 0.45, relation: .opposite, to: sofa, optional: true, zone: zone)
            add("Стеллаж для хранения", "storage", 1.2, 0.4, .corner, optional: true, zone: zone)
            add("Растение в кашпо", "plant", 0.45, 0.45, .corner, optional: true, zone: zone)
        case .garage:
            add("Стеллаж металлический", "storage", 1.5, 0.5, .corner)
            add("Верстак", "desk", 1.5, 0.7, optional: true)
            add("Стеллаж для шин", "storage", 1.0, 0.45, optional: true)
        case .shop:
            let counter = add("Прилавок с кассой", "desk", 1.4, 0.6, prefer: .door)
            add("Стеллаж торговый", "storage", 1.2, 0.45, count: max(2, Int(area / 8)))
            add("Витрина", "storage", 1.0, 0.5, optional: true)
            add("Стол выкладки", "table", 1.2, 0.8, .free, optional: true)
            add("Стул продавца", "chair", 0.45, 0.5, relation: .nextTo, to: counter, optional: true)
            add("Растение в кашпо", "plant", 0.45, 0.45, .corner, optional: true)
        case .cafe:
            add("Барная стойка", "desk", min(3.0, max(1.6, area.squareRoot() * 0.6)), 0.6, prefer: .farFromDoor)
            let table = add("Стол для гостей", "table", 0.8, 0.8, .free, count: max(2, Int(area / 6)))
            add("Стул", "chair", 0.45, 0.5, relation: .around, to: table, count: 4)
            add("Холодильник", "appliance", 0.6, 0.65, optional: true)
        case .warehouse:
            add("Стеллаж складской", "storage", 1.8, 0.6, .corner, count: max(2, Int(area / 10)))
            add("Верстак", "desk", 1.5, 0.7, optional: true)
            add("Рабочий стол", "table", 1.2, 0.7, optional: true)
        case .other:
            add("Стеллаж", "storage", 1.0, 0.4, .corner, optional: true)
            let table = add("Стол", "table", 1.2, 0.7, .free, optional: true)
            add("Стул", "chair", 0.45, 0.5, relation: .around, to: table, optional: true, count: 2)
        }
        return list
    }

    // MARK: Style

    private struct Style {
        let palette: [String]
        let floor: (String, String, String, String)   // material, color, details, english
        let walls: (String, String, String, String)
        let ceiling: (String, String, String, String)
        let english: String
        let rate: (Double, Double)                     // ₽ per m² (finish + furniture), living rooms
    }

    private static func style(_ name: String, room: RoomKind) -> Style {
        let n = name.lowercased()
        var s: Style
        if n.contains("лофт") {
            s = Style(palette: ["#8A8A86", "#5B4636", "#2E2E2E", "#C2703D", "#E7E2DA"],
                      floor: ("Инженерная доска дуб, тёмный тон", "#5B4636", "Укладка вдоль длинной стены, чёрный теневой плинтус 60 мм", "dark oak engineered wood floor"),
                      walls: ("Декоративная штукатурка под бетон", "#8A8A86", "Акцентная стена под кирпич, чёрные металлические детали", "concrete-look decorative plaster walls with one brick accent wall"),
                      ceiling: ("Натяжной матовый потолок, тёмно‑серый", "#3A3A3A", "Чёрные трековые светильники, теневой профиль", "dark grey matte ceiling with black track lights"),
                      english: "industrial loft interior, concrete, black metal, warm wood", rate: (22_000, 45_000))
        } else if n.contains("скандин") {
            s = Style(palette: ["#F2EFEA", "#D9C7A7", "#A7B5A0", "#3F4A52", "#FFFFFF"],
                      floor: ("Ламинат 33 класса, светлый дуб", "#D9C7A7", "Укладка вдоль света из окна, белый плинтус 80 мм", "light oak laminate floor"),
                      walls: ("Моющаяся краска, тёплый белый", "#F2EFEA", "Без молдингов, акцент шалфейного цвета за мебелью", "warm white painted walls with a sage green accent"),
                      ceiling: ("Натяжной матовый белый", "#FFFFFF", "Встроенные споты и подвес над главной зоной", "white matte ceiling with recessed spots"),
                      english: "scandinavian interior, light wood, white, sage green, textiles", rate: (15_000, 32_000))
        } else if n.contains("минимал") {
            s = Style(palette: ["#F5F5F3", "#CFCAC2", "#9A958D", "#1F1F1F", "#E8E4DD"],
                      floor: ("Керамогранит 1200×600, светло‑серый", "#CFCAC2", "Раскладка от центра, скрытый плинтус", "large light grey porcelain tiles"),
                      walls: ("Краска матовая, светло‑серая", "#F5F5F3", "Скрытые двери в цвет стен, без декора", "smooth light grey matte walls"),
                      ceiling: ("Гипсокартон с теневым примыканием", "#FFFFFF", "Линейные светодиодные светильники", "white ceiling with shadow gap and linear LED lights"),
                      english: "minimalist interior, clean lines, neutral colours, hidden storage", rate: (18_000, 40_000))
        } else if n.contains("японди") {
            s = Style(palette: ["#EDE6DA", "#B89F80", "#6E5B48", "#2F2B27", "#8C8F7A"],
                      floor: ("Паркетная доска ясень, натуральный", "#B89F80", "Широкая доска, плинтус в цвет пола", "natural ash wide-plank floor"),
                      walls: ("Минеральная штукатурка, песочная", "#EDE6DA", "Деревянные рейки на акцентной стене", "sand colour mineral plaster with wooden slats"),
                      ceiling: ("Натяжной матовый, тёплый белый", "#F7F3EC", "Рассеянный свет, бумажные подвесы", "warm white ceiling with paper pendant lights"),
                      english: "japandi interior, natural wood, linen, calm earthy tones", rate: (20_000, 42_000))
        } else if n.contains("неоклас") {
            s = Style(palette: ["#EFE8DD", "#C9B79C", "#8D7B68", "#2E3A46", "#C8A96A"],
                      floor: ("Паркет ёлочкой, дуб натуральный", "#C9B79C", "Высокий плинтус 120 мм под покраску", "oak herringbone parquet floor"),
                      walls: ("Краска + молдинги", "#EFE8DD", "Классические молдинги, латунные детали", "light beige walls with classic mouldings"),
                      ceiling: ("Гипсокартон с карнизом", "#FFFFFF", "Потолочный карниз, люстра в центре", "white ceiling with cornice and chandelier"),
                      english: "neoclassical interior, mouldings, herringbone parquet, brass accents", rate: (28_000, 60_000))
        } else if n.contains("средизем") {
            s = Style(palette: ["#F4EEE4", "#D8C3A5", "#3E6E8E", "#B8653F", "#FFFFFF"],
                      floor: ("Керамогранит под терракоту", "#C98A63", "Раскладка вразбежку, плинтус керамический", "terracotta-look porcelain tiles"),
                      walls: ("Фактурная штукатурка, белая", "#F4EEE4", "Синие акценты, дерево, лён", "textured white plaster walls"),
                      ceiling: ("Натяжной матовый, белый", "#FFFFFF", "Декоративные балки, тёплый свет", "white ceiling with wooden beams"),
                      english: "mediterranean interior, white plaster, terracotta, blue accents", rate: (18_000, 38_000))
        } else if n.contains("эко") {
            s = Style(palette: ["#EFEBE3", "#A9876A", "#6B7B5C", "#3D3A35", "#D9CFC0"],
                      floor: ("Массивная доска дуб, масло", "#A9876A", "Натуральное масло, деревянный плинтус", "oiled solid oak floor"),
                      walls: ("Глиняная штукатурка", "#EFEBE3", "Фитостена или живые растения", "natural clay plaster walls with plants"),
                      ceiling: ("Натяжной матовый, тёплый белый", "#F7F3EC", "Тёплый свет 2700 K", "warm white ceiling, warm light"),
                      english: "eco interior, natural wood, clay plaster, plants, linen", rate: (20_000, 40_000))
        } else {
            s = Style(palette: ["#EEEBE6", "#BFA78A", "#6F7B85", "#2B2D30", "#D6CBBE"],
                      floor: ("Кварцвинил, дуб натуральный", "#BFA78A", "Замковое соединение, плинтус МДФ 80 мм в цвет стен", "natural oak luxury vinyl floor"),
                      walls: ("Моющаяся краска, светло‑серый тёплый", "#EEEBE6", "Акцентная стена графитового цвета", "warm light grey painted walls with a graphite accent wall"),
                      ceiling: ("Натяжной матовый белый", "#FFFFFF", "Теневой профиль, встроенные споты", "white matte ceiling with shadow gap and spots"),
                      english: "modern contemporary interior, warm neutrals, graphite accents", rate: (16_000, 35_000))
        }
        // Wet and kitchen rooms get water‑proof finishes in the same colours.
        if room == .bathroom {
            s = Style(palette: s.palette,
                      floor: ("Керамогранит 600×600, противоскользящий", s.floor.1, "Уклон 1–2 % к трапу, гидроизоляция с заведением на стены 200 мм", "anti-slip porcelain floor tiles 600x600"),
                      walls: ("Керамическая плитка / керамогранит 1200×600", s.walls.1, "Мокрая зона до потолка, остальное — влагостойкая краска; гидроизоляция в душе на 2 м", "large format porcelain wall tiles in the wet zone"),
                      ceiling: ("Натяжной влагостойкий потолок", s.ceiling.1, "Светильники IP44, вытяжной вентилятор с обратным клапаном", "moisture resistant white ceiling with IP44 spotlights"),
                      english: s.english + ", bathroom", rate: (35_000, 75_000))
        } else if room == .kitchen {
            s = Style(palette: s.palette, floor: ("Керамогранит 600×600", s.floor.1, "Под гарнитуром — тоже плитка", "porcelain floor tiles"),
                      walls: s.walls, ceiling: s.ceiling, english: s.english + ", kitchen", rate: (25_000, 55_000))
        }
        return s
    }

    // MARK: Proposal

    static func propose(plan: FloorPlan, style styleName: String, purpose: String, wishes: String) -> DesignProposal? {
        let room = RoomKind.keyword(purpose) ?? RoomKind.fromScan(plan) ?? .living
        let s = style(styleName, room: room)
        let area = plan.area
        let wallArea = plan.netWallArea
        func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        let budgetMin = (area * s.rate.0 / 10_000).rounded() * 10_000
        let budgetMax = (area * s.rate.1 / 10_000).rounded() * 10_000

        var materials: [[String: Any]] = [
            ["name": s.floor.0, "where": "Пол", "amount": "\(CalculationEngine.format(r(area * 1.08))) м² (с запасом 8 %)"],
            ["name": s.walls.0, "where": "Стены", "amount": "\(CalculationEngine.format(r(wallArea * 1.1))) м² (с запасом 10 %)"],
            ["name": s.ceiling.0, "where": "Потолок", "amount": "\(CalculationEngine.format(r(area))) м²"]
        ]
        if room == .bathroom {
            materials.append(["name": "Обмазочная гидроизоляция + лента", "where": "Пол и мокрая зона", "amount": "\(CalculationEngine.format(r(area + plan.perimeter * 0.2 + 2.5))) м²"])
            materials.append(["name": "Плиточный клей С2", "where": "Пол и стены", "amount": "≈ \(Int((area + wallArea * 0.6) * 5 / 25 + 1)) меш. по 25 кг"])
        }
        materials.append(["name": "Грунтовка глубокого проникновения", "where": "Все поверхности", "amount": "\(Int(((area * 2 + wallArea) * 0.15 / 10).rounded(.up))) канистр по 10 л"])

        let lighting: String = room == .bathroom
            ? "Встроенные споты IP44 по сетке, подсветка зеркала, выключатель снаружи у двери."
            : "Споты по сетке 1,2 м для общего света, подвесной светильник над главной зоной, тёплый свет 3000 K."
        let tips: [String] = room == .bathroom
            ? ["Проверьте расстояние до стояка: унитаз ставьте у стены со стояком.", "Розетку стиральной машины — с УЗО, не ближе 0,6 м от душа.", "Трап и уклон пола делайте до укладки плитки.", "Вентиляцию с обратным клапаном ставьте над душем или унитазом."]
            : ["Проходы оставлены не уже 0,7 м, зона открывания двери свободна.", "Розетки планируйте по расстановке мебели до чистовой отделки.", "Размеры проверьте рулеткой перед заказом мебели."]
        let body: [String: Any] = [
            "title": "\(styleName): \(room.purposeTitle.lowercased())",
            "style": styleName,
            "summary": "",
            "roomPurpose": purpose.isEmpty ? room.purposeTitle : purpose,
            "zones": [],
            "furniture": [] as [Any],
            "palette": s.palette,
            "materials": materials,
            "lighting": lighting,
            "tips": tips,
            "budgetMin": budgetMin,
            "budgetMax": max(budgetMax, budgetMin + 10_000),
            "renderPrompt": "\(styleName), \(room.russianName)",
            "renderPromptEnglish": s.english,
            "floor": ["material": s.floor.0, "color": s.floor.1, "details": s.floor.2, "english": s.floor.3],
            "walls": ["material": s.walls.0, "color": s.walls.1, "details": s.walls.2, "english": s.walls.3],
            "ceiling": ["material": s.ceiling.0, "color": s.ceiling.1, "details": s.ceiling.2, "english": s.ceiling.3]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body), let base = try? JSONDecoder().decode(DesignProposal.self, from: data) else { return nil }
        let brief = DesignBrief(items: items(room, plan: plan, wishes: wishes, purpose: purpose))
        var proposal = DesignComposer.compose(base, brief: brief, plan: plan, room: room)
        let names = proposal.furniture.map(\.name).joined(separator: ", ")
        proposal.summary = "Концепция собрана встроенным дизайнером приложения по скану: \(names.isEmpty ? "расстановка без мебели" : names.lowercased()). Предметы расставлены по правилам: дверь открывается свободно, проходы не уже 0,7 м, перед сантехникой и кухней есть место. Отделка — в стиле «\(styleName)»."
        return proposal
    }

    /// English names for photo prompts when no AI translator is available.
    static func englishNames(_ items: [DesignFurniture]) -> String {
        let map: [String: String] = [
            "toilet": "wall-hung toilet", "sink": "vanity with washbasin and mirror", "shower": "walk-in shower with glass screen",
            "bathtub": "bathtub", "washer": "washing machine", "towel": "towel warmer", "mirror": "mirror", "boiler": "water heater",
            "sofa": "sofa", "bed": "bed", "table": "table", "desk": "desk", "chair": "chair", "storage": "cabinet",
            "kitchen": "kitchen units with sink and cooktop", "appliance": "fridge", "tv": "TV unit", "plant": "plant in a pot"
        ]
        return Array(Set(items.compactMap { map[$0.model] })).sorted().joined(separator: ", ")
    }
}
