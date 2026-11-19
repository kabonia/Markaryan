import Foundation

/// The plan screen in three steps: measure → design → result, with one main button on each step.
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
}

/// What the main button of a step does.
enum PlanAction: Equatable {
    /// Opens the design request (purpose, style, wishes).
    case createDesign
    /// Moves to another step.
    case goTo(PlanStep)
    /// Exact 3D model, photoreal views and the PDF for the selected concept.
    case buildPresentation
    /// Request for the renovation of this room.
    case orderRenovation
}

struct PlanMainButton: Equatable {
    let action: PlanAction
    let title: String
    let icon: String
}

struct PlanFlow {
    /// The plan has at least one concept.
    let hasConcepts: Bool
    /// A concept is selected and has a layout: a presentation makes sense.
    let conceptReady: Bool
    /// The selected concept has a presentation on the iPhone.
    let hasPresentation: Bool
    /// The app can build a presentation (AI server or picture keys).
    let canRender: Bool

    init(plan: FloorPlan, proposal: DesignProposal?, hasPresentation: Bool, canRender: Bool) {
        hasConcepts = !plan.proposals.isEmpty
        conceptReady = proposal.map { !$0.furniture.isEmpty } ?? false
        self.hasPresentation = hasPresentation && proposal != nil
        self.canRender = canRender
    }

    /// Steps with a check mark.
    var done: Set<PlanStep> {
        var steps: Set<PlanStep> = [.measure]
        if hasConcepts { steps.insert(.design) }
        if hasPresentation { steps.insert(.result) }
        return steps
    }

    /// Where the screen opens: a new scan on the measurements, a concept on the design, a finished one on the result.
    var initialStep: PlanStep {
        if !hasConcepts { return .measure }
        return hasPresentation ? .result : .design
    }

    func main(on step: PlanStep) -> PlanMainButton {
        let next = PlanMainButton(action: .goTo(.result), title: "Дальше: результат", icon: "arrow.right")
        let order = PlanMainButton(action: .orderRenovation, title: "Ремонт этой комнаты под ключ", icon: "paperplane.fill")
        let present = PlanMainButton(action: .buildPresentation, title: "Создать дизайн‑презентацию", icon: "rectangle.stack.badge.play")
        let design = hasConcepts
            ? PlanMainButton(action: .createDesign, title: "Ещё вариант дизайна", icon: "wand.and.stars")
            : PlanMainButton(action: .createDesign, title: "Создать дизайн по плану", icon: "wand.and.stars")
        switch step {
        case .measure:
            return hasConcepts ? PlanMainButton(action: .goTo(.design), title: "Дальше: дизайн", icon: "arrow.right") : design
        case .design:
            guard conceptReady else { return design }
            if hasPresentation || !canRender { return next }
            return present
        case .result:
            guard conceptReady else { return design }
            return hasPresentation || !canRender ? order : present
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
