import Foundation

// MARK: - 2D plan geometry (metres, x → right, y → down, origin at the top-left of the plan)

struct PlanPoint: Codable, Hashable {
    var x: Double
    var y: Double
    static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x - b.x, y: a.y - b.y) }
    func distance(to other: PlanPoint) -> Double { hypot(x - other.x, y - other.y) }
}

struct PlanSegment: Codable, Identifiable {
    enum Kind: String, Codable { case wall, door, window, opening }
    var id = UUID()
    var kind: Kind
    var start: PlanPoint
    var end: PlanPoint
    var height: Double
    var length: Double { start.distance(to: end) }
}

struct PlanObject: Codable, Identifiable {
    var id = UUID()
    var name: String
    var center: PlanPoint
    var width: Double
    var depth: Double
    /// Radians, clockwise in plan coordinates.
    var rotation: Double
}
