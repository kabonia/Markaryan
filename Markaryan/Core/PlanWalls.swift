import Foundation

/// A wall as the layout sees it: numbered, oriented clockwise on screen, with the side that faces the room
/// and the doors and windows that lie on it.
struct WallSide {
    struct Opening {
        /// Metres from `start` along the wall.
        let from: Double
        let to: Double
        let segment: PlanSegment
        var middle: Double { (from + to) / 2 }
    }

    /// 1, 2, 3… clockwise on screen, starting from the wall with the entrance door.
    let number: Int
    let segment: PlanSegment
    let start: PlanPoint
    let end: PlanPoint
    /// Unit vector from `start` to `end`.
    let direction: PlanPoint
    /// Unit vector into the room.
    let normal: PlanPoint
    let length: Double
    var doors: [Opening] = []
    var windows: [Opening] = []

    /// Point on the wall `distance` metres from its start, moved `offset` metres into the room.
    func point(_ distance: Double, offset: Double = 0) -> PlanPoint { start + direction * distance + normal * offset }
    /// Position of a point along the wall (metres from `start`) and its distance from the wall line (positive inside).
    func project(_ point: PlanPoint) -> (along: Double, offset: Double) { ((point - start).dot(direction), (point - start).dot(normal)) }
    /// Rotation (degrees) of an item whose back is against this wall and whose front faces the room.
    var itemRotation: Double { atan2(-normal.x, normal.y) * 180 / .pi }
}

enum PlanWalls {
    /// Walls shorter than this are scan fragments, not places for furniture.
    static let minimumLength = 0.3

    /// The room for the AI: numbered walls with their doors and windows and the fixtures the scan found — no coordinates,
    /// because the AI only says which wall or corner, and the layout engine does the geometry.
    static func aiDescription(_ plan: FloorPlan) -> String {
        let walls = numbered(plan)
        func r(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        let wallItems: [[String: Any]] = walls.map { wall in
            var item: [String: Any] = ["number": wall.number, "length": r(wall.length)]
            if !wall.doors.isEmpty {
                item["doors"] = wall.doors.map { ["type": $0.segment.kind == .door ? "дверь" : "проём без двери", "from": r($0.from), "to": r($0.to)] as [String: Any] }
            }
            if !wall.windows.isEmpty { item["windows"] = wall.windows.map { ["from": r($0.from), "to": r($0.to)] as [String: Any] } }
            return item
        }
        let objects: [[String: Any]] = plan.objects.map { object in
            let nearest = walls.min { PlanMath.distance(object.center, toSegment: $0.start, $0.end) < PlanMath.distance(object.center, toSegment: $1.start, $1.end) }
            return ["name": object.name, "nearWall": nearest?.number ?? 0]
        }
        let payload: [String: Any] = [
            "units": "метры",
            "floorArea": r(plan.area),
            "ceilingHeight": r(plan.ceilingHeight),
            "size": "\(r(plan.width)) × \(r(plan.depth))",
            "walls": wallItems,
            "wallNumbering": "по часовой стрелке на плане, стена 1 — с входной дверью (без дверей — верхняя); from/to — метры от начала стены по ходу нумерации",
            "scannedObjects": objects
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Walls numbered clockwise on screen from the entrance (the first door, or the top wall when there is no door).
    static func numbered(_ plan: FloorPlan) -> [WallSide] {
        let walls = plan.walls.filter { $0.length >= minimumLength }
        guard !walls.isEmpty else { return [] }
        let b = plan.bounds
        let center = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)

        // Orient every wall so that the room is on its right when walking from start to end (clockwise on screen).
        var sides: [(segment: PlanSegment, start: PlanPoint, end: PlanPoint, normal: PlanPoint)] = []
        for wall in walls {
            let d = wall.end - wall.start
            let unit = d * (1 / max(1e-9, d.length))
            var normal = PlanPoint(x: -unit.y, y: unit.x)
            let mid = (wall.start + wall.end) * 0.5
            if plan.contains(mid + normal * 0.2) {
                // keep
            } else if plan.contains(mid - normal * 0.2) {
                normal = normal * -1
            } else if (center - mid).dot(normal) < 0 {
                normal = normal * -1
            }
            let clockwise = PlanPoint(x: normal.y, y: -normal.x)
            let forward = (wall.end - wall.start).dot(clockwise) >= 0
            sides.append((wall, forward ? wall.start : wall.end, forward ? wall.end : wall.start, normal))
        }

        // Order along the outline, clockwise on screen.
        var outline = plan.floorPolygon.count >= 3 ? plan.floorPolygon : []
        if PlanMath.signedArea2(outline) < 0 { outline.reverse() }
        func key(_ point: PlanPoint) -> Double {
            guard outline.count >= 3 else {
                let angle = atan2(point.y - center.y, point.x - center.x)
                return angle < 0 ? angle + 2 * .pi : angle
            }
            var best = (distance: Double.infinity, position: 0.0)
            var walked = 0.0
            for i in outline.indices {
                let a = outline[i], c = outline[(i + 1) % outline.count]
                let edge = c - a, edgeLength = edge.length
                if edgeLength > 1e-9 {
                    let t = max(0, min(1, (point - a).dot(edge) / (edgeLength * edgeLength)))
                    let distance = point.distance(to: a + edge * t)
                    if distance < best.distance - 1e-9 { best = (distance, walked + t * edgeLength) }
                }
                walked += edgeLength
            }
            return best.position
        }
        sides.sort { key(($0.start + $0.end) * 0.5) < key(($1.start + $1.end) * 0.5) }

        // Doors and windows that lie on each wall.
        func openings(_ segments: [PlanSegment], on side: (segment: PlanSegment, start: PlanPoint, end: PlanPoint, normal: PlanPoint)) -> [WallSide.Opening] {
            let direction = (side.end - side.start) * (1 / max(1e-9, side.segment.length))
            return segments.compactMap { opening in
                let a = (opening.start - side.start), c = (opening.end - side.start)
                guard abs(a.dot(side.normal)) < 0.25, abs(c.dot(side.normal)) < 0.25 else { return nil }
                let from = max(0, min(a.dot(direction), c.dot(direction))), to = min(side.segment.length, max(a.dot(direction), c.dot(direction)))
                return to - from > 0.1 ? WallSide.Opening(from: from, to: to, segment: opening) : nil
            }.sorted { $0.from < $1.from }
        }

        // Wall 1 is the wall with the entrance; without doors — the top wall.
        let entrance = plan.doors.first { $0.kind == .door } ?? plan.doors.first
        var first = 0
        if let entrance {
            let mid = (entrance.start + entrance.end) * 0.5
            first = sides.indices.min { PlanMath.distance(mid, toSegment: sides[$0].start, sides[$0].end) < PlanMath.distance(mid, toSegment: sides[$1].start, sides[$1].end) } ?? 0
        } else {
            first = sides.indices.min { a, c in
                let ma = (sides[a].start + sides[a].end) * 0.5, mc = (sides[c].start + sides[c].end) * 0.5
                return abs(ma.y - mc.y) > 0.05 ? ma.y < mc.y : ma.x < mc.x
            } ?? 0
        }
        let ordered = Array(sides[first...] + sides[..<first])
        return ordered.enumerated().map { index, side in
            WallSide(number: index + 1, segment: side.segment, start: side.start, end: side.end,
                     direction: (side.end - side.start) * (1 / max(1e-9, side.segment.length)), normal: side.normal, length: side.segment.length,
                     doors: openings(plan.doors, on: side), windows: openings(plan.windows, on: side))
        }
    }
}
