import Foundation

// MARK: - 2D plan geometry (metres, x → right, y → down, origin at the top-left of the plan)

struct PlanPoint: Codable, Hashable {
    var x: Double
    var y: Double
    static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: PlanPoint, k: Double) -> PlanPoint { PlanPoint(x: a.x * k, y: a.y * k) }
    func distance(to other: PlanPoint) -> Double { hypot(x - other.x, y - other.y) }
    func dot(_ other: PlanPoint) -> Double { x * other.x + y * other.y }
    /// z of the cross product: > 0 when `other` is clockwise from this vector on screen (y points down).
    func cross(_ other: PlanPoint) -> Double { x * other.y - y * other.x }
    var length: Double { hypot(x, y) }
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

// MARK: - Turned rectangles (furniture footprints, door swings, clearances)

/// Rectangle turned in the plan: `width` along its own x axis, `depth` along its own y axis,
/// `rotation` in radians (x towards y — clockwise on screen). Same convention as `DesignFurniture`.
struct PlanRect: Hashable {
    var center: PlanPoint
    var width: Double
    var depth: Double
    var rotation: Double

    var axisX: PlanPoint { PlanPoint(x: cos(rotation), y: sin(rotation)) }
    var axisY: PlanPoint { PlanPoint(x: -sin(rotation), y: cos(rotation)) }
    /// Corners in order: back-left, back-right, front-right, front-left (front = +y of the rectangle).
    var corners: [PlanPoint] {
        let ax = axisX * (width / 2), ay = axisY * (depth / 2)
        return [center - ax - ay, center + ax - ay, center + ax + ay, center - ax + ay]
    }
    var edges: [(PlanPoint, PlanPoint)] { let c = corners; return (0..<4).map { (c[$0], c[($0 + 1) % 4]) } }

    /// The same rectangle grown (positive) or shrunk (negative) on every side.
    func grown(by amount: Double) -> PlanRect {
        PlanRect(center: center, width: max(0.001, width + amount * 2), depth: max(0.001, depth + amount * 2), rotation: rotation)
    }

    func contains(_ point: PlanPoint, margin: Double = 0) -> Bool {
        let d = point - center
        return abs(d.dot(axisX)) <= width / 2 + margin && abs(d.dot(axisY)) <= depth / 2 + margin
    }

    /// 0 inside, otherwise the shortest distance to the rectangle.
    func distance(to point: PlanPoint) -> Double {
        let d = point - center
        let ox = max(0, abs(d.dot(axisX)) - width / 2), oy = max(0, abs(d.dot(axisY)) - depth / 2)
        return hypot(ox, oy)
    }

    /// Interiors overlap (rectangles that only touch do not).
    func overlaps(_ other: PlanRect) -> Bool {
        for axis in [axisX, axisY, other.axisX, other.axisY] {
            let a = corners.map { $0.dot(axis) }, b = other.corners.map { $0.dot(axis) }
            if a.max()! <= b.min()! + 1e-9 || b.max()! <= a.min()! + 1e-9 { return false }
        }
        return true
    }

    func crosses(_ a: PlanPoint, _ b: PlanPoint) -> Bool {
        if contains(a, margin: -1e-9) || contains(b, margin: -1e-9) { return true }
        return edges.contains { PlanMath.segmentsCross($0.0, $0.1, a, b) }
    }
}

enum PlanMath {
    /// Even–odd rule; points exactly on the boundary may go either way.
    static func contains(_ polygon: [PlanPoint], _ point: PlanPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Twice the signed area: positive when the points go clockwise on screen (y down).
    static func signedArea2(_ polygon: [PlanPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        return polygon.indices.reduce(0) { sum, i in sum + polygon[i].cross(polygon[(i + 1) % polygon.count]) }
    }

    /// Proper crossing of two segments (touching at an end point does not count).
    static func segmentsCross(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint, _ d: PlanPoint) -> Bool {
        let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a)
        let d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
        return ((d1 > 1e-12 && d2 < -1e-12) || (d1 < -1e-12 && d2 > 1e-12)) && ((d3 > 1e-12 && d4 < -1e-12) || (d3 < -1e-12 && d4 > 1e-12))
    }

    static func distance(_ point: PlanPoint, toSegment a: PlanPoint, _ b: PlanPoint) -> Double {
        let ab = b - a
        let lengthSquared = ab.dot(ab)
        guard lengthSquared > 1e-12 else { return point.distance(to: a) }
        let t = max(0, min(1, (point - a).dot(ab) / lengthSquared))
        return point.distance(to: a + ab * t)
    }

    /// Interiors of two convex polygons overlap (separating axis test; touching does not count).
    static func convexOverlap(_ a: [PlanPoint], _ b: [PlanPoint]) -> Bool {
        guard a.count >= 3, b.count >= 3 else { return false }
        for polygon in [a, b] {
            for i in polygon.indices {
                let p = polygon[i], q = polygon[(i + 1) % polygon.count]
                let axis = PlanPoint(x: p.y - q.y, y: q.x - p.x)
                guard axis.length > 1e-12 else { continue }
                let pa = a.map { $0.dot(axis) }, pb = b.map { $0.dot(axis) }
                if pa.max()! <= pb.min()! + 1e-9 || pb.max()! <= pa.min()! + 1e-9 { return false }
            }
        }
        return true
    }

    /// The whole rectangle is inside the polygon: corners inside, no wall crosses it, no corner of the room pokes into it.
    static func polygon(_ polygon: [PlanPoint], contains rect: PlanRect) -> Bool {
        guard rect.corners.allSatisfy({ contains(polygon, $0) }) else { return false }
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if rect.contains(a, margin: -1e-6) { return false }
            if rect.edges.contains(where: { segmentsCross($0.0, $0.1, a, b) }) { return false }
        }
        return true
    }
}
