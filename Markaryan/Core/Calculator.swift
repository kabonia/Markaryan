import Foundation

struct FieldSpec: Identifiable {
    let id: String
    let title: String
    let unit: String
    let initial: String
    var allowsZero = false
}

enum CalculationCategory: String, CaseIterable, Identifiable {
    case foundation, walls, roof, finishing, outdoor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundation: return "Фундамент и бетон"
        case .walls: return "Стены и каркас"
        case .roof: return "Кровля и утепление"
        case .finishing: return "Отделка"
        case .outdoor: return "Участок"
        }
    }
}

enum CalculationKind: String, CaseIterable, Codable, Identifiable {
    case slab, strip, piles, concreteMix, rebar, masonry, drywall, roof, insulation, screed, plaster, paint, tiles, fence
    var id: String { rawValue }
    var category: CalculationCategory {
        switch self {
        case .slab, .strip, .piles, .concreteMix, .rebar: return .foundation
        case .masonry, .drywall: return .walls
        case .roof, .insulation: return .roof
        case .screed, .plaster, .paint, .tiles: return .finishing
        case .fence: return .outdoor
        }
    }
    var title: String {
        switch self {
        case .slab: return "Фундаментная плита"
        case .strip: return "Ленточный фундамент"
        case .piles: return "Бетонные сваи"
        case .masonry: return "Кладка блоков"
        case .screed: return "Стяжка пола"
        case .plaster: return "Штукатурка"
        case .paint: return "Покраска"
        case .tiles: return "Плитка"
        case .rebar: return "Арматура"
        case .roof: return "Двускатная кровля"
        case .concreteMix: return "Бетон своими руками"
        case .drywall: return "Гипсокартон"
        case .insulation: return "Утеплитель"
        case .fence: return "Забор из профнастила"
        }
    }
    var icon: String {
        switch self {
        case .slab, .strip: return "square.3.layers.3d"
        case .piles: return "cylinder.split.1x2"
        case .masonry: return "square.grid.3x3"
        case .screed: return "square.stack.3d.down.right"
        case .plaster: return "rectangle.fill"
        case .paint: return "paintbrush.pointed"
        case .tiles: return "square.grid.2x2"
        case .rebar: return "line.3.horizontal"
        case .roof: return "house"
        case .concreteMix: return "drop.halffull"
        case .drywall: return "rectangle.split.3x1"
        case .insulation: return "thermometer.snowflake"
        case .fence: return "rectangle.split.3x3"
        }
    }
    var summary: String {
        switch self {
        case .slab, .strip: return "Объём бетона · опалубка · стоимость"
        case .piles: return "Объём бетона · запас · стоимость"
        case .masonry: return "Блоки · кубометры · клей или раствор"
        case .screed, .plaster: return "Толщина · расход · мешки смеси"
        case .paint: return "Слои · расход · упаковки"
        case .tiles: return "Упаковки · плиточный клей"
        case .rebar: return "Масса · прутки к покупке"
        case .roof: return "Площадь покрытия · конёк"
        case .concreteMix: return "Цемент · песок · щебень · вода на замес"
        case .drywall: return "Листы · слои · саморезы"
        case .insulation: return "Объём · толщина · упаковки"
        case .fence: return "Листы · столбы · лаги · бетон"
        }
    }
    var priceUnit: String {
        switch self {
        case .slab, .strip, .piles: return "₽/м³"
        case .masonry: return "₽/блок"
        case .screed, .plaster: return "₽/мешок"
        case .paint: return "₽/банка"
        case .tiles: return "₽/упаковка"
        case .rebar: return "₽/кг"
        case .roof: return "₽/м²"
        case .concreteMix: return "₽/мешок цемента"
        case .drywall, .fence: return "₽/лист"
        case .insulation: return "₽/упаковка"
        }
    }
    var note: String {
        switch self {
        case .slab: return "Прямоугольная плита постоянной толщины, без рёбер. Опалубка — торцы по периметру. Толщину и армирование задаёт проектировщик. Для заводского бетона обычно хватает запаса 3–5%."
        case .strip: return "Суммарная длина лент измеряется по осевым линиям, пересечения не должны учитываться дважды. Сечение постоянное; без ступеней и уширений. Опалубка — две боковые стороны на всю высоту."
        case .piles: return "Цилиндрические сваи одинакового диаметра без уширений. Ростверк рассчитывается отдельно."
        case .masonry: return "Кладка в один блок по толщине стены. Количество — по лицевой площади с учётом швов; без армопоясов и перемычек. Шов до 5 мм — клей (1,5 кг на 1 м² × 1 мм шва, ≈25–30 кг на 1 м³ газобетона), толще — цементно-песчаный раствор (1,8 кг)."
        case .screed, .plaster: return "Введите расход с упаковки вашей смеси на 1 м² при толщине 1 мм. Значение по умолчанию — пример, а не характеристика выбранного материала."
        case .paint: return "Введите расход краски на один слой с упаковки. Впитываемость основания может изменить фактический расход."
        case .tiles: return "Расчёт по площади, без раскладки. Для диагональной укладки и сложного рисунка увеличьте запас до 15%. Расход клея — с мешка: обычно 3–4 кг/м² при зубе 6 мм, 5–6 кг/м² при зубе 8–10 мм, 7–8 кг/м² для крупного формата."
        case .rebar: return "Теоретическая масса стержня (сталь 7850 кг/м³, совпадает с ГОСТ: Ø12 — 0,888 кг/м). Прутки к покупке считаются раскроем: сколько целых отрезков выходит из одного прутка; длинные стержни — со стыками. Нахлёсты включайте в длину стержня или в запас. Базы режут пруток 11,7 м пополам — по 5,85 м."
        case .roof: return "Симметричная двускатная крыша над прямоугольным планом. Свес вводится как горизонтальная проекция с каждой стороны. Без ендов, труб и окон. Нахлёсты листов закладывайте в запас: металлочерепица и профлист 10–15%, мягкая черепица 5–10%."
        case .concreteMix: return "Пропорции по массе; по умолчанию — ориентир М200 на цементе М400 (1 : 2,8 : 4,8, В/Ц 0,6). Расход цемента на 1 м³ считается из пропорций методом абсолютных объёмов (цемент 3100, песок и щебень 2650 кг/м³, воздух 2%), поэтому смесь всегда даёт ровно заданный объём. Песок и щебень — сухие; влажный песок тяжелее, воду тогда уменьшают. Для несущих конструкций — заводской бетон."
        case .drywall: return "Расчёт листов по площади обшивки с учётом слоёв. Каркас, подвесы и шпаклёвка считаются отдельно."
        case .insulation: return "Объём утеплителя по площади и толщине. Объём упаковки указан на этикетке (например, 0,288 м³ = 8 плит 1200 × 600 × 50 мм)."
        case .fence: return "Прямой забор без ворот и калиток. Длина столба = высота забора + заглубление (0,8–1,2 м, ниже глубины промерзания). Диаметр лунки 0 — столбы забиваются без бетона. Саморезы — ориентир: 6 на лист на каждый ряд лаг."
        }
    }
    var fields: [FieldSpec] {
        func f(_ id: String, _ title: String, _ unit: String, _ initial: String, _ zero: Bool = false) -> FieldSpec {
            FieldSpec(id: id, title: title, unit: unit, initial: initial, allowsZero: zero)
        }
        let reserve = f("reserve", "Запас материала", "%", "10", true)
        var result: [FieldSpec]
        switch self {
        case .slab: result = [f("length", "Длина", "м", "10"), f("width", "Ширина", "м", "8"), f("thickness", "Толщина", "мм", "250")]
        case .strip: result = [f("length", "Общая длина лент", "м", "40"), f("width", "Ширина ленты", "мм", "400"), f("height", "Полная высота ленты", "мм", "1200")]
        case .piles: result = [f("diameter", "Диаметр", "мм", "300"), f("height", "Длина сваи", "м", "3"), f("count", "Количество свай", "шт.", "12")]
        case .masonry: result = [f("length", "Общая длина стен", "м", "40"), f("height", "Высота стен", "м", "3"), f("openings", "Площадь проёмов", "м²", "18", true), f("blockLength", "Длина блока", "мм", "600"), f("blockHeight", "Высота блока", "мм", "200"), f("blockWidth", "Толщина блока (стены)", "мм", "300"), f("joint", "Толщина шва", "мм", "3", true)]
        case .screed: result = [f("area", "Площадь пола", "м²", "50"), f("thickness", "Толщина слоя", "мм", "50"), f("consumption", "Расход на 1 м² × 1 мм", "кг", "2"), f("package", "Масса мешка", "кг", "25")]
        case .plaster: result = [f("area", "Площадь стен", "м²", "100"), f("openings", "Площадь проёмов", "м²", "15", true), f("thickness", "Средняя толщина", "мм", "10"), f("consumption", "Расход на 1 м² × 1 мм", "кг", "0,85"), f("package", "Масса мешка", "кг", "30")]
        case .paint: result = [f("area", "Площадь поверхности", "м²", "100"), f("openings", "Площадь проёмов", "м²", "15", true), f("layers", "Количество слоёв", "шт.", "2"), f("consumption", "Расход на 1 м² на слой", "л", "0,15"), f("package", "Объём банки", "л", "10")]
        case .tiles: result = [f("area", "Площадь укладки", "м²", "25"), f("package", "Площадь в упаковке", "м²", "1,44"), f("glue", "Расход плиточного клея", "кг/м²", "5", true), f("glueBag", "Масса мешка клея", "кг", "25")]
        case .rebar: result = [f("diameter", "Диаметр стержня", "мм", "12"), f("length", "Длина одного стержня", "м", "5,85"), f("count", "Количество стержней", "шт.", "20"), f("stock", "Длина прутка при покупке", "м", "11,7")]
        case .roof: result = [f("length", "Длина дома", "м", "12"), f("width", "Ширина дома", "м", "8"), f("overhang", "Свес с каждой стороны", "м", "0,5", true), f("angle", "Угол ската", "°", "30")]
        case .concreteMix: result = [f("volume", "Объём бетона", "м³", "5"), f("sand", "Песок, частей на 1 часть цемента", "ч.", "2,8"), f("gravel", "Щебень, частей на 1 часть цемента", "ч.", "4,8"), f("water", "Водоцементное отношение", "В/Ц", "0,6"), f("package", "Масса мешка цемента", "кг", "50")]
        case .drywall: result = [f("area", "Площадь обшивки", "м²", "40"), f("openings", "Площадь проёмов", "м²", "4", true), f("layers", "Слоёв гипсокартона", "шт.", "1"), f("sheetLength", "Длина листа", "м", "2,5"), f("sheetWidth", "Ширина листа", "м", "1,2"), f("screws", "Саморезов на лист", "шт.", "30", true)]
        case .insulation: result = [f("area", "Площадь утепления", "м²", "100"), f("thickness", "Толщина слоя", "мм", "100"), f("package", "Объём упаковки", "м³", "0,288")]
        case .fence: result = [f("length", "Длина забора", "м", "30"), f("height", "Высота забора", "м", "2"), f("sheetWidth", "Полезная ширина листа", "м", "1,15"), f("postStep", "Шаг столбов", "м", "2,5"), f("rails", "Рядов лаг", "шт.", "2"), f("postDepth", "Заглубление столба", "м", "1"), f("hole", "Диаметр лунки под бетон", "мм", "200", true)]
        }
        result.append(reserve)
        result.append(f("price", "Цена материала (необязательно)", priceUnit, "", true))
        return result
    }
}

struct ResultLine: Codable, Identifiable {
    var id: String { label }
    let label: String
    let value: Double
    let unit: String
    var formatted: String { "\(CalculationEngine.format(value)) \(unit)" }
}
struct CalculationResult: Codable {
    let lines: [ResultLine]
    let formula: String
    let cost: Double?
}
struct CalculationFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum CalculationEngine {
    /// NumberFormatter is expensive to create; long estimates format hundreds of values per render.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()
    /// Whole rubles for money values.
    static func money(_ value: Double) -> String {
        "\(formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))) ₽"
    }
    static func parse(_ text: String) -> Double? {
        let clean = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: "\u{202f}", with: "").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(clean), value.isFinite else { return nil }
        return value
    }
    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    static func calculate(_ kind: CalculationKind, values: [String: String]) throws -> CalculationResult {
        var numbers: [String: Double] = [:]
        for field in kind.fields {
            let raw = values[field.id] ?? ""
            if field.id == "price" && raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let value = parse(raw), value >= 0, (field.allowsZero || value > 0), value <= 1_000_000_000 else {
                throw CalculationFailure(message: "Проверьте поле «\(field.title)»: введите \(field.allowsZero ? "неотрицательное" : "положительное") число.")
            }
            if ["count", "layers", "rails"].contains(field.id) && value.rounded() != value {
                throw CalculationFailure(message: "«\(field.title)» должно быть целым числом.")
            }
            numbers[field.id] = value
        }
        func v(_ key: String) -> Double { numbers[key] ?? 0 }
        guard v("reserve") <= 100 else { throw CalculationFailure(message: "Запас должен быть от 0 до 100%.") }
        let factor = 1 + v("reserve") / 100
        var lines: [ResultLine] = []
        var quantity: Double = 0
        var formula = ""
        func add(_ label: String, _ value: Double, _ unit: String) { lines.append(ResultLine(label: label, value: value, unit: unit)) }
        switch kind {
        case .slab, .strip, .piles:
            let base: Double
            if kind == .slab { base = v("length") * v("width") * v("thickness") / 1000; formula = "V = длина × ширина × толщина" }
            else if kind == .strip { base = v("length") * v("width") / 1000 * v("height") / 1000; formula = "V = общая длина × ширина × высота" }
            else { base = Double.pi * pow(v("diameter") / 2000, 2) * v("height") * v("count"); formula = "V = π × (диаметр / 2)² × длина × количество" }
            quantity = base * factor
            add("Объём по геометрии", base, "м³"); add("Бетон с запасом", quantity, "м³")
            if kind == .slab { add("Опалубка по периметру", 2 * (v("length") + v("width")) * v("thickness") / 1000, "м²") }
            if kind == .strip { add("Опалубка, две стороны", 2 * v("length") * v("height") / 1000, "м²") }
        case .masonry:
            let area = v("length") * v("height") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше общей площади стен.") }
            let face = (v("blockLength") + v("joint")) * (v("blockHeight") + v("joint")) / 1_000_000
            quantity = ceil(area / face * factor)
            add("Площадь кладки", area, "м²"); add("Блоки с запасом", quantity, "шт.")
            let width = v("blockWidth") / 1000
            let blockVolume = v("blockLength") * v("blockHeight") / 1_000_000 * width
            add("Блоки, объём к покупке", quantity * blockVolume, "м³")
            if v("joint") > 0 {
                // Joint share of the wall: everything that is not block face, times wall thickness.
                let joints = area * width * (1 - v("blockLength") * v("blockHeight") / 1_000_000 / face)
                let isGlue = v("joint") <= 5
                let mix = joints * (isGlue ? 1500 : 1800) * factor
                add(isGlue ? "Клей для блоков" : "Сухая смесь для раствора", mix, "кг")
                add("Мешки по 25 кг", ceil(mix / 25), "шт.")
            }
            formula = "N = площадь без проёмов / ((длина блока + шов) × (высота блока + шов)) × запас, вверх. Клей/раствор = объём швов × 1500 (клей, шов до 5 мм) или 1800 кг/м³ (раствор) × запас"
        case .screed, .plaster:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади поверхности.") }
            let mass = area * v("thickness") * v("consumption") * factor
            quantity = ceil(mass / v("package"))
            add("Рабочая площадь", area, "м²"); add("Геометрический объём слоя", area * v("thickness") / 1000, "м³")
            add("Сухая смесь с запасом", mass, "кг"); add("Мешки к покупке", quantity, "шт.")
            formula = "Масса = площадь × толщина в мм × расход × запас. Мешки = масса / масса мешка, вверх"
        case .paint:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади поверхности.") }
            let liters = area * v("layers") * v("consumption") * factor
            quantity = ceil(liters / v("package"))
            add("Рабочая площадь", area, "м²"); add("Краска с запасом", liters, "л"); add("Банки к покупке", quantity, "шт.")
            formula = "Литры = площадь × слои × расход × запас. Банки округляются вверх"
        case .tiles:
            let area = v("area") * factor
            quantity = ceil(area / v("package"))
            add("Площадь с запасом", area, "м²"); add("Упаковки к покупке", quantity, "шт."); add("Площадь в упаковках", quantity * v("package"), "м²")
            if v("glue") > 0 {
                let glue = v("area") * v("glue") * factor
                add("Плиточный клей", glue, "кг"); add("Мешки клея", ceil(glue / v("glueBag")), "шт.")
            }
            formula = "Упаковки = площадь × запас / площадь упаковки, вверх. Клей = площадь × расход × запас"
        case .rebar:
            let length = v("length") * v("count")
            let kgPerMeter = Double.pi * pow(v("diameter") / 2000, 2) * 7850
            let mass = length * kgPerMeter * factor
            add("Общая длина без запаса", length, "м"); add("Масса одного метра", kgPerMeter, "кг/м"); add("Масса с запасом", mass, "кг")
            // Cutting: whole pieces from one stock bar; pieces longer than the bar are joined, so they go by length.
            let piecesPerBar = floor(v("stock") / v("length") + 1e-9)
            let bars = piecesPerBar >= 1
                ? ceil(ceil(v("count") * factor - 1e-9) / piecesPerBar)
                : ceil(length * factor / v("stock"))
            quantity = bars * v("stock") * kgPerMeter
            add("Прутков к покупке", bars, "шт."); add("Масса к покупке", quantity, "кг")
            formula = "Масса = π × (диаметр / 2)² × 7850 кг/м³ × длина × количество × запас. Прутки = стержни с запасом / целых отрезков из прутка, вверх; цена — по массе целых прутков"
        case .roof:
            guard v("angle") > 0 && v("angle") < 75 else { throw CalculationFailure(message: "Для этого расчёта угол ската должен быть больше 0° и меньше 75°.") }
            let slope = (v("width") / 2 + v("overhang")) / cos(v("angle") * Double.pi / 180)
            let area = 2 * slope * (v("length") + 2 * v("overhang"))
            quantity = area * factor
            add("Длина ската со свесом", slope, "м"); add("Площадь двух скатов", area, "м²"); add("Покрытие с запасом", quantity, "м²")
            add("Длина конька", v("length") + 2 * v("overhang"), "м")
            add("Высота конька над стенами", v("width") / 2 * tan(v("angle") * Double.pi / 180), "м")
            formula = "Площадь = (длина + 2 × свес) × (ширина + 2 × свес) / cos(угол)"
        case .concreteMix:
            let volume = v("volume") * factor
            // Absolute volumes: 1 kg of cement brings cement, sand, gravel and water; 2% of the volume is air.
            let litersPerKgCement = 1 / 3.1 + (v("sand") + v("gravel")) / 2.65 + v("water")
            let cementPerCubicMeter = 980 / litersPerKgCement
            let cement = volume * cementPerCubicMeter
            quantity = ceil(cement / v("package"))
            add("Бетон с запасом", volume, "м³"); add("Цемент", cement, "кг"); add("Мешки цемента", quantity, "шт.")
            add("Песок", cement * v("sand"), "кг"); add("Песок, насыпной объём ≈", cement * v("sand") / 1500, "м³")
            add("Щебень", cement * v("gravel"), "кг"); add("Щебень, насыпной объём ≈", cement * v("gravel") / 1450, "м³")
            add("Вода", cement * v("water"), "л")
            add("Цемент на 1 м³ по пропорциям", cementPerCubicMeter, "кг")
            formula = "Цемент на 1 м³ = 980 л / (1/3,1 + (песок + щебень)/2,65 + В/Ц); песок и щебень = цемент × части; вода = цемент × В/Ц. Насыпная плотность: песок 1500, щебень 1450 кг/м³"
        case .drywall:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади обшивки.") }
            let sheetArea = v("sheetLength") * v("sheetWidth")
            quantity = ceil(area * v("layers") * factor / sheetArea)
            add("Площадь обшивки", area, "м²"); add("Листы с запасом", quantity, "шт."); add("Саморезы", quantity * v("screws"), "шт.")
            formula = "Листы = площадь без проёмов × слои × запас / площадь листа, вверх. Саморезы = листы × саморезы на лист"
        case .insulation:
            let volume = v("area") * v("thickness") / 1000 * factor
            quantity = ceil(volume / v("package"))
            add("Объём утеплителя с запасом", volume, "м³"); add("Упаковки к покупке", quantity, "шт.")
            formula = "Объём = площадь × толщина × запас. Упаковки = объём / объём упаковки, вверх"
        case .fence:
            quantity = ceil(v("length") / v("sheetWidth") * factor)
            let posts = ceil(v("length") / v("postStep")) + 1
            add("Площадь забора", v("length") * v("height"), "м²"); add("Листы профнастила", quantity, "шт.")
            add("Столбы", posts, "шт."); add("Лаги (профтруба)", v("length") * v("rails") * factor, "м")
            add("Труба на столбы", posts * (v("height") + v("postDepth")), "м")
            if v("hole") > 0 { add("Бетон для столбов", Double.pi * pow(v("hole") / 2000, 2) * v("postDepth") * posts * factor, "м³") }
            add("Кровельные саморезы ≈", quantity * v("rails") * 6, "шт.")
            formula = "Листы = длина / полезная ширина × запас, вверх. Столбы = длина / шаг, вверх, + 1. Лаги = длина × ряды × запас. Бетон = π × (лунка / 2)² × заглубление × столбы × запас"
        }
        let cost = numbers["price"].map { $0 * quantity }
        guard lines.allSatisfy({ $0.value.isFinite && $0.value < 1e15 }), cost == nil || (cost!.isFinite && cost! < 1e15) else {
            throw CalculationFailure(message: "Получились слишком большие значения. Проверьте размеры и единицы измерения.")
        }
        return CalculationResult(lines: lines, formula: formula, cost: cost)
    }
}

struct SavedCalculation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let object: String
    let kind: CalculationKind
    let values: [String: String]
    let result: CalculationResult
    var measurementNote: String? = nil
    var report: String {
        var parts = ["АРТСТРОЙ · СТРОИТЕЛЬНЫЙ РАСЧЁТ", object, kind.title, date.formatted(date: .numeric, time: .shortened), "", "ИСХОДНЫЕ ДАННЫЕ"]
        parts += kind.fields.compactMap { field in
            guard let value = values[field.id], !value.isEmpty else { return nil }
            return "\(field.title): \(value) \(field.unit)"
        }
        if let measurementNote { parts += ["", measurementNote] }
        parts += ["", "РЕЗУЛЬТАТ"] + result.lines.map { "\($0.label): \($0.formatted)" }
        if let cost = result.cost { parts.append("Материалы: \(CalculationEngine.format(cost)) ₽") }
        parts += ["", "Стоимость только материалов по введённой цене, без работ и доставки.", kind.note, "Оценка количества материалов, не проектный расчёт несущих конструкций.", "", "—", "АртСтрой · строим в Сочи с 2012 года", "+7 928 233-03-33 · WhatsApp: wa.me/79282330333 · sochi-art.com"]
        return parts.joined(separator: "\n")
    }
}
