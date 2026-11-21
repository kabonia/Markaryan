import Foundation

/// The room screen after the scan: measurements → design → result, with one main button on each step.
/// Pure logic, so it is tested on Linux; the view only draws it.
enum PlanStep: Int, CaseIterable, Identifiable, Hashable {
    case measure, design, result

    var id: Int { rawValue }
    var number: Int { rawValue + 1 }
    var title: String {
        switch self {
        case .measure: return "Обмер"
        case .design: return "Дизайн"
        case .result: return "Результат"
        }
    }
    var icon: String {
        switch self {
        case .measure: return "ruler"
        case .design: return "paintpalette"
        case .result: return "photo.on.rectangle.angled"
        }
    }
}

/// What the main button of a step does.
enum PlanAction: Equatable {
    /// Opens the design request (purpose, style, wishes).
    case createDesign
    /// Moves to another step.
    case goTo(PlanStep)
    /// Renders of the exact 3D model in the chosen style and the PDF.
    case buildPresentation
    /// Opens the finished PDF.
    case openPresentation
}

struct PlanMainButton: Equatable {
    let action: PlanAction
    let title: String
    let icon: String
}

struct PlanFlow {
    /// The plan has at least one concept.
    let hasConcepts: Bool
    /// A concept is selected and has a layout: a render makes sense.
    let conceptReady: Bool
    /// The selected concept has a presentation on the iPhone.
    let hasPresentation: Bool
    /// The AI can make photoreal renders (otherwise the result is the exact 3D model only).
    let canRender: Bool
    /// The plan or the furniture was corrected by hand after the presentation was made.
    let presentationOutdated: Bool

    init(plan: FloorPlan, proposal: DesignProposal?, hasPresentation: Bool, canRender: Bool) {
        hasConcepts = !plan.proposals.isEmpty
        conceptReady = proposal.map { !$0.furniture.isEmpty } ?? false
        self.hasPresentation = hasPresentation && proposal != nil
        self.canRender = canRender
        let edited = [plan.editedAt, proposal?.editedAt].compactMap { $0 }.max()
        if self.hasPresentation, let edited, let made = proposal?.presentation?.createdAt {
            presentationOutdated = made < edited
        } else {
            presentationOutdated = false
        }
    }

    /// Steps with a check mark.
    var done: Set<PlanStep> {
        var steps: Set<PlanStep> = [.measure]
        if hasConcepts { steps.insert(.design) }
        if hasPresentation && !presentationOutdated { steps.insert(.result) }
        return steps
    }

    /// Where the screen opens: a new scan on the measurements, a concept on the design, a finished one on the result.
    var initialStep: PlanStep {
        if !hasConcepts { return .measure }
        return hasPresentation ? .result : .design
    }

    func main(on step: PlanStep) -> PlanMainButton {
        let render = presentationOutdated
            ? PlanMainButton(action: .buildPresentation, title: "Обновить рендер и PDF", icon: "arrow.triangle.2.circlepath")
            : PlanMainButton(action: .buildPresentation, title: "Создать рендер и PDF", icon: "camera.aperture")
        let current = hasPresentation && !presentationOutdated
        let design = hasConcepts
            ? PlanMainButton(action: .createDesign, title: "Ещё вариант дизайна", icon: "wand.and.stars")
            : PlanMainButton(action: .createDesign, title: "Выбрать стиль и создать дизайн", icon: "wand.and.stars")
        switch step {
        case .measure:
            return hasConcepts ? PlanMainButton(action: .goTo(.design), title: "Дальше: дизайн", icon: "arrow.right") : design
        case .design:
            guard conceptReady else { return design }
            return current ? PlanMainButton(action: .goTo(.result), title: "Дальше: результат", icon: "arrow.right") : render
        case .result:
            guard conceptReady else { return design }
            return current ? PlanMainButton(action: .openPresentation, title: "Открыть PDF", icon: "doc.richtext") : render
        }
    }
}

/// One measurement of the room for «Все обмеры».
struct PlanMeasurement: Identifiable, Equatable {
    let group: String
    let title: String
    let value: Double
    let unit: String
    var id: String { group + "|" + title }
}

/// «Все обмеры» on the «Обмер» step: everything a finisher or a buyer of materials asks for, counted from the scan.
enum PlanMeasurements {
    static func list(_ plan: FloorPlan) -> [PlanMeasurement] {
        let height = plan.ceilingHeight
        let doorWidth = plan.doors.reduce(0) { $0 + $1.length }
        let windows = plan.windows
        let windowArea = windows.reduce(0) { $0 + $1.length * $1.height }
        let doorArea = plan.doors.reduce(0) { $0 + $1.length * $1.height }
        // Window reveals: both sides and the top of every window, 0.25 m deep by default.
        let revealDepth = 0.25
        let revealLength = windows.reduce(0) { $0 + 2 * $1.height + $1.length }
        let sills = windows.reduce(0) { $0 + $1.length }
        let plinth = max(0, plan.perimeter - doorWidth)
        var rows: [PlanMeasurement] = [
            PlanMeasurement(group: "Пол и потолок", title: "Площадь пола", value: plan.area, unit: "м²"),
            PlanMeasurement(group: "Пол и потолок", title: "Площадь потолка", value: plan.area, unit: "м²"),
            PlanMeasurement(group: "Пол и потолок", title: "Высота потолка", value: height, unit: "м"),
            PlanMeasurement(group: "Пол и потолок", title: "Объём помещения", value: plan.area * height, unit: "м³"),
            PlanMeasurement(group: "Стены", title: "Периметр", value: plan.perimeter, unit: "м"),
            PlanMeasurement(group: "Стены", title: "Стены всего", value: plan.perimeter * height, unit: "м²"),
            PlanMeasurement(group: "Стены", title: "Стены без проёмов (покраска, обои)", value: plan.netWallArea, unit: "м²"),
            PlanMeasurement(group: "Стены", title: "Плинтус (без дверей)", value: plinth, unit: "м"),
            PlanMeasurement(group: "Стены", title: "Потолочный молдинг / карниз", value: plan.perimeter, unit: "м"),
            PlanMeasurement(group: "Проёмы", title: "Окна, площадь", value: windowArea, unit: "м²"),
            PlanMeasurement(group: "Проёмы", title: "Двери, площадь", value: doorArea, unit: "м²"),
            PlanMeasurement(group: "Проёмы", title: "Откосы окон, длина", value: revealLength, unit: "м"),
            PlanMeasurement(group: "Проёмы", title: "Откосы окон, площадь (25 см)", value: revealLength * revealDepth, unit: "м²"),
            PlanMeasurement(group: "Проёмы", title: "Подоконники, длина", value: sills, unit: "м"),
        ]
        // Tiles: the floor plus +10 % for cutting; in a bathroom also the walls to the ceiling.
        rows.append(PlanMeasurement(group: "Под отделку", title: "Плитка / ламинат на пол (+10 %)", value: plan.area * 1.1, unit: "м²"))
        rows.append(PlanMeasurement(group: "Под отделку", title: "Плитка на стены до потолка (+10 %)", value: plan.netWallArea * 1.1, unit: "м²"))
        rows.append(PlanMeasurement(group: "Под отделку", title: "Краска стен, 2 слоя (≈ 0,12 л/м²)", value: plan.netWallArea * 0.24, unit: "л"))
        rows.append(PlanMeasurement(group: "Под отделку", title: "Краска потолка, 2 слоя", value: plan.area * 0.24, unit: "л"))
        rows.append(PlanMeasurement(group: "Под отделку", title: "Наливной пол 1 см (≈ 16 кг/м²)", value: plan.area * 16, unit: "кг"))
        return rows
    }

    /// Wall by wall, numbered as on the plan.
    static func walls(_ plan: FloorPlan) -> [PlanMeasurement] {
        PlanWalls.numbered(plan).map { wall in
            PlanMeasurement(group: "По стенам", title: "Стена \(wall.number)", value: wall.length, unit: "м")
        }
    }
}

/// One calculator with the room's sizes filled in.
struct PlanCalculation: Identifiable {
    let kind: CalculationKind
    let title: String
    let values: [String: String]
    var id: String { title }
}

/// «Материалы и смета»: the finishing calculators that take their sizes from the plan.
enum PlanMaterials {
    static func calculations(_ plan: FloorPlan) -> [PlanCalculation] {
        func number(_ value: Double) -> String { String(format: "%.2f", max(0, value)) }
        let floor = number(plan.area)
        let walls = number(plan.perimeter * plan.ceilingHeight), openings = number(plan.openingsArea)
        return [
            PlanCalculation(kind: .tiles, title: "Пол: плитка / ламинат", values: ["area": floor]),
            PlanCalculation(kind: .screed, title: "Стяжка пола", values: ["area": floor]),
            PlanCalculation(kind: .paint, title: "Покраска стен", values: ["area": walls, "openings": openings]),
            PlanCalculation(kind: .plaster, title: "Штукатурка стен", values: ["area": walls, "openings": openings]),
            PlanCalculation(kind: .drywall, title: "Гипсокартон на стены", values: ["area": walls, "openings": openings]),
            PlanCalculation(kind: .paint, title: "Покраска потолка", values: ["area": floor, "openings": "0"])
        ]
    }
}
