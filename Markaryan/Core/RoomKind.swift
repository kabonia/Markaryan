import Foundation

/// Type of room: decides what may stand in it, the drawing titles, the camera shots and what the image AI may show.
enum RoomKind: String, CaseIterable {
    case bathroom, kitchen, bedroom, kids, hall, office, living

    /// Room type from words: «Санузел», «Ванная», «Кухня‑гостиная», plan name…
    static func keyword(_ text: String) -> RoomKind? {
        let t = text.lowercased()
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if ["сануз", "с/у", "ванн", "туалет", "уборн", "душев", "bathroom", "toilet"].contains(where: { t.contains($0) }) { return .bathroom }
        if t.contains("детск") { return .kids }
        if t.contains("спальн") { return .bedroom }
        if t.contains("кабинет") { return .office }
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
        }
    }
}
