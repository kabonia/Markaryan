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

/// Maps the room's own plan coordinates to the scan (apartment) coordinates:
/// turn by `rotation` (radians, x towards y — clockwise on screen) about the origin, then move by (x, y).
struct PlanPlacement: Codable, Hashable {
    var x: Double
    var y: Double
    var rotation: Double

    static let identity = PlanPlacement(x: 0, y: 0, rotation: 0)

    func apply(_ point: PlanPoint) -> PlanPoint {
        let c = cos(rotation), s = sin(rotation)
        return PlanPoint(x: point.x * c - point.y * s + x, y: point.x * s + point.y * c + y)
    }

    /// Placement after the room's coordinates were turned by `angle` and then moved by `shift`.
    func undoing(rotation angle: Double, thenShift shift: PlanPoint) -> PlanPlacement {
        // new = R(angle)·old + shift  →  old = R(−angle)·(new − shift)  →  scan = R(rotation − angle)·(new − shift) + (x, y)
        let turn = rotation - angle
        let c = cos(turn), s = sin(turn)
        return PlanPlacement(x: x - (shift.x * c - shift.y * s), y: y - (shift.x * s + shift.y * c), rotation: turn)
    }
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
