import Foundation

/// Type of room: decides what may stand in it, the drawing titles, the camera shots and what the image AI may show.
enum RoomKind: String, CaseIterable {
    case bathroom, kitchen, bedroom, kids, hall, office, living
    /// Not only homes: garages, shops, cafés, storerooms and anything else.
    case garage, shop, cafe, warehouse, other

    /// Room type from words: «Санузел», «Ванная», «Кухня‑гостиная», plan name…
    static func keyword(_ text: String) -> RoomKind? {
        let t = text.lowercased()
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if ["сануз", "с/у", "ванн", "туалет", "уборн", "душев", "bathroom", "toilet"].contains(where: { t.contains($0) }) { return .bathroom }
        if t.contains("детск") { return .kids }
        if t.contains("спальн") { return .bedroom }
        if t.contains("гараж") || t.contains("бокс") { return .garage }
        if ["магазин", "цвет", "бутик", "салон", "торгов", "шоурум", "аптек", "лавк", "павильон"].contains(where: { t.contains($0) }) { return .shop }
        if ["кафе", "кофейн", "ресторан", "бар", "столов", "пекарн", "пиццер"].contains(where: { t.contains($0) }) { return .cafe }
        if ["склад", "мастерск", "цех", "подсоб", "кладов"].contains(where: { t.contains($0) }) { return .warehouse }
        if t.contains("кабинет") || t.contains("офис") || t.contains("переговор") { return .office }
        if ["прихож", "коридор", "холл", "гардероб", "тамбур"].contains(where: { t.contains($0) }) { return .hall }
        if t.contains("кухн") && !t.contains("гостин") && !t.contains("студи") { return .kitchen }
        if ["гостин", "студи", "зал", "терраса", "living"].contains(where: { t.contains($0) }) { return .living }
        return nil
    }

    /// Room type from the LiDAR scan: plan name and the objects RoomPlan found (toilet, bathtub, stove, bed…).
    static func fromScan(_ plan: FloorPlan) -> RoomKind? {
        if let named = keyword(plan.name) { return named }
        let names = plan.objects.map { $0.name.lowercased() }
        func found(_ words: String...) -> Bool { names.contains { name in words.contains { name.contains($0) } } }
        if found("унитаз", "ванна") { return .bathroom }
        if found("плита", "духовка", "холодильник", "посудомойка") { return .kitchen }
        if found("раковина") && plan.area < 7 { return .bathroom }
        if found("кровать") { return .bedroom }
        if found("диван", "телевизор", "камин") { return .living }
        return nil
    }

    /// Why the scan suggests this type (shown to the user).
    static func scanReason(_ plan: FloorPlan) -> String? {
        let found = plan.objects.map(\.name).filter { ["Унитаз", "Ванна", "Раковина", "Плита", "Духовка", "Холодильник", "Посудомойка", "Кровать", "Диван", "Телевизор"].contains($0) }
        if !found.isEmpty { return "по скану найдено: " + Array(Set(found)).sorted().joined(separator: ", ").lowercased() }
        if keyword(plan.name) != nil { return "по названию «\(plan.name)»" }
        return nil
    }

    static func detect(plan: FloorPlan?, proposal: DesignProposal?) -> RoomKind {
        // 0) fixed when the concept was placed, 1) what the user chose, 2) the AI title, 3) the scan, 4) the items themselves
        if let stored = proposal?.roomKind.flatMap(RoomKind.init(rawValue:)) { return stored }
        if let chosen = keyword(proposal?.roomPurpose ?? "") ?? keyword(proposal?.title ?? "") { return chosen }
        if let plan, let scanned = fromScan(plan) { return scanned }
        let models = (proposal?.furniture ?? []).map(\.model)
        if models.filter({ ["toilet", "sink", "shower", "bathtub"].contains($0) }).count >= 2 { return .bathroom }
        if models.contains("kitchen") && !models.contains("sofa") { return .kitchen }
        if models.contains("bed") { return .bedroom }
        return .living
    }

    /// Chip title in the design sheet.
    var purposeTitle: String {
        switch self {
        case .bathroom: return "Санузел"
        case .kitchen: return "Кухня"
        case .bedroom: return "Спальня"
        case .kids: return "Детская"
        case .hall: return "Прихожая"
        case .office: return "Кабинет"
        case .living: return "Гостиная"
        case .garage: return "Гараж"
        case .shop: return "Магазин"
        case .cafe: return "Кафе"
        case .warehouse: return "Склад / мастерская"
        case .other: return "Другое"
        }
    }
    var russianName: String {
        switch self {
        case .bathroom: return "санузел (ванная комната)"
        case .kitchen: return "кухня"
        case .bedroom: return "спальня"
        case .kids: return "детская"
        case .hall: return "прихожая"
        case .office: return "кабинет"
        case .living: return "гостиная / жилая комната"
        case .garage: return "гараж"
        case .shop: return "торговое помещение (магазин)"
        case .cafe: return "кафе / общепит"
        case .warehouse: return "склад / мастерская"
        case .other: return "помещение"
        }
    }

    /// Models that must never appear in this room.
    var forbiddenModels: Set<String> {
        switch self {
        case .bathroom: return ["sofa", "bed", "table", "desk", "chair", "kitchen", "tv", "appliance", "floorlamp"]
        case .kitchen: return ["toilet", "shower", "bathtub", "bed", "sink"]
        case .hall: return ["toilet", "shower", "bathtub", "bed", "kitchen", "sink"]
        case .bedroom, .kids, .office: return ["toilet", "shower", "bathtub", "sink", "kitchen", "washer", "boiler", "towel"]
        case .living: return ["toilet", "shower", "bathtub", "sink", "towel", "boiler"]
        case .garage, .warehouse: return ["sofa", "bed", "kitchen", "toilet", "shower", "bathtub", "tv", "floorlamp", "towel", "decor"]
        case .shop: return ["bed", "toilet", "shower", "bathtub", "kitchen", "towel"]
        case .cafe: return ["bed", "toilet", "shower", "bathtub", "towel"]
        case .other: return []
        }
    }
    func allows(_ model: String) -> Bool { !forbiddenModels.contains(model) }

    /// What the client will get in this room (shown in the design sheet).
    var allowedShort: String {
        switch self {
        case .bathroom: return "Унитаз, раковина с тумбой, душ или ванна, стиральная машина, зеркало, полотенцесушитель, шкаф, точки воды, канализации и розеток. Без кухни, дивана, кровати."
        case .kitchen: return "Гарнитур с мойкой и плитой, техника, обеденная зона, точки подключения. Без сантехники санузла и кровати."
        case .hall: return "Шкафы, обувница, банкетка, зеркало. Без сантехники и кухни."
        case .bedroom: return "Кровать, тумбы, шкаф, рабочее место. Без сантехники и кухни."
        case .kids: return "Кровать, стол, хранение, игровая зона. Без сантехники и кухни."
        case .office: return "Стол, кресло, стеллажи, хранение. Без сантехники и кухни."
        case .living: return "Мягкая мебель, ТВ‑зона, хранение (в кухне‑гостиной и студии — кухня). Без сантехники санузла."
        case .garage: return "Место под автомобиль, стеллажи, верстак, хранение шин и инструмента, освещение и розетки."
        case .shop: return "Торговое оборудование: стеллажи и витрины по стенам, прилавок с кассой, зона выкладки, растения и свет. Для цветочного — холодильная витрина и стол флориста."
        case .cafe: return "Столы и стулья для гостей, барная стойка или раздача, кухонное оборудование, зона хранения."
        case .warehouse: return "Стеллажи, верстак, рабочий стол, проходы для погрузки, хранение."
        case .other: return "Любое помещение: опишите назначение — подберём оборудование и отделку под задачу."
        }
    }

    /// Rules for the design AI, in Russian.
    var rulesRussian: String {
        switch self {
        case .bathroom:
            return "Это САНУЗЕЛ. Ставь только: унитаз (kind toilet; лучше подвесной на инсталляции у стены со стояком), раковину с тумбой (sink), душевую с трапом или ванну (shower / bathtub), стиральную машину (washer — не ближе 0,6 м от душа/ванны), зеркало (mirror), полотенцесушитель (towel), шкаф или пенал (storage), бра и подсветку (light). Запрещено: кухня, плита, холодильник, диван, кровать, стол, стулья, ТВ, ковры, торшеры. Перед унитазом и раковиной свободно не менее 0,6 м, дверь открывается свободно."
        case .kitchen:
            return "Это КУХНЯ. Ставь кухонный гарнитур (kitchen) с мойкой, варочной панелью и духовкой, технику (appliance), обеденный стол и стулья. Запрещено: унитаз, душ, ванна, раковина санузла, кровать. Мойку не ставь дальше 3 м от стояка, плиту — не вплотную к окну и мойке."
        case .hall:
            return "Это ПРИХОЖАЯ. Ставь шкафы и системы хранения, обувницу, банкетку, зеркало. Запрещено: сантехника, кровать, кухня."
        case .bedroom, .kids, .office:
            return "Это \(russianName.uppercased()). Запрещено: сантехника санузла (унитаз, душ, ванна, раковина), кухня, бойлер."
        case .living:
            return "Это ЖИЛАЯ КОМНАТА. Запрещено: сантехника санузла (унитаз, душ, ванна, раковина санузла), полотенцесушитель."
        case .garage:
            return "Это ГАРАЖ. Оставь место под автомобиль (не менее 2,5×5 м и проход 0,6 м вокруг), по стенам — стеллажи (storage), верстак (desk), хранение шин. Отделка — износостойкая: наливной или бетонный пол, моющиеся стены, яркий свет. Запрещено: диван, кровать, кухня, сантехника, ковры."
        case .shop:
            return "Это ТОРГОВОЕ ПОМЕЩЕНИЕ. Ставь стеллажи и витрины по стенам (storage), прилавок с кассой у входа (desk), зону выкладки в центре (table), растения и акцентный свет (light). Проходы для покупателей не уже 1,2 м, вход свободен. Для цветочного магазина — холодильная витрина (appliance) и стол флориста (table). Запрещено: кровать, сантехника, бытовая кухня."
        case .cafe:
            return "Это КАФЕ. Ставь столы (table) со стульями (chair) для гостей, барную стойку или раздачу (desk), кухонное оборудование (kitchen, appliance) в рабочей зоне, хранение (storage). Проходы не уже 0,9 м. Запрещено: кровать, сантехника санузла в зале."
        case .warehouse:
            return "Это СКЛАД / МАСТЕРСКАЯ. Ставь стеллажи (storage) по стенам, верстак и рабочий стол (desk), оставь проходы не уже 1 м. Отделка — износостойкая. Запрещено: диван, кровать, бытовая кухня, сантехника."
        case .other:
            return "Это ПОМЕЩЕНИЕ с назначением, которое указал пользователь. Подбери оборудование и отделку строго под это назначение; не добавляй предметы, которые ему не нужны."
        }
    }

    var furniturePlanTitle: String {
        switch self {
        case .bathroom: return "План расстановки сантехники и оборудования"
        case .kitchen: return "План расстановки кухонной мебели и техники"
        default: return "План расстановки мебели и оборудования"
        }
    }
    var specificationTitle: String {
        switch self {
        case .bathroom: return "Сантехника и оборудование"
        case .kitchen: return "Кухонная мебель и техника"
        default: return "Мебель и оборудование"
        }
    }
    var english: String {
        switch self {
        case .bathroom: return "bathroom"
        case .kitchen: return "kitchen"
        case .bedroom: return "bedroom"
        case .kids: return "children's room"
        case .hall: return "entrance hall"
        case .office: return "home office"
        case .living: return "living room"
        case .garage: return "garage"
        case .shop: return "retail shop"
        case .cafe: return "cafe"
        case .warehouse: return "workshop and storage room"
        case .other: return "room"
        }
    }
    /// What the image AI must never invent in this room.
    var rulesEnglish: String {
        switch self {
        case .bathroom: return "This room is a BATHROOM, not an apartment: show only bathroom fixtures and bathroom furniture that are in the render (toilet, washbasin with vanity, mirror, shower or bathtub, towel warmer, washing machine, bathroom cabinets) and ceramic tiles. Absolutely no kitchen, no cooktop, no oven, no fridge, no sofa, no bed, no dining table, no TV, no rug."
        case .kitchen: return "This room is a KITCHEN: no bed, no sofa unless it is in the render, no bathroom fixtures."
        case .bedroom, .kids: return "This room is a \(english.uppercased()): no kitchen units, no bathroom fixtures."
        case .hall: return "This room is an ENTRANCE HALL: no kitchen, no bed, no bathroom fixtures."
        case .office, .living: return "This room is a \(english.uppercased()): no bathroom fixtures (no toilet, shower or bathtub), no bed unless it is in the render."
        case .garage, .warehouse: return "This room is a \(english.uppercased()): utilitarian finishes, shelving and workbench; no sofa, no bed, no kitchen, no bathroom fixtures."
        case .shop: return "This room is a RETAIL SHOP: shelving, display cases and a cashier counter; no bed, no home kitchen, no bathroom fixtures."
        case .cafe: return "This room is a CAFE: guest tables and chairs, a bar counter; no bed, no bathroom fixtures in the hall."
        case .other: return "Show only what fits the purpose given by the user; no bathroom fixtures unless they are in the render."
        }
    }
}
