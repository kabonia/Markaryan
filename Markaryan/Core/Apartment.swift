import Foundation

extension FloorPlan {
    /// The same room turned by `turn` radians (x towards y — clockwise on screen) about the origin, then moved by
    /// `shift`. Walls, openings, the floor, scanned objects and the furniture of every concept go with it, and
    /// `placement` still maps the room back to the scan.
    func moved(turn: Double, shift: PlanPoint) -> FloorPlan {
        let c = cos(turn), s = sin(turn)
        func move(_ p: PlanPoint) -> PlanPoint { PlanPoint(x: p.x * c - p.y * s + shift.x, y: p.x * s + p.y * c + shift.y) }
        let quarter = abs(remainder(turn, .pi / 2)) < 1e-9
        let odd = quarter && Int((turn / (.pi / 2)).rounded()) % 2 != 0
        var plan = self
        plan.segments = segments.map { var segment = $0; segment.start = move(segment.start); segment.end = move(segment.end); return segment }
        plan.floorPolygon = floorPolygon.map(move)
        plan.objects = objects.map { var object = $0; object.center = move(object.center); object.rotation += turn; return object }
        plan.proposals = proposals.map { proposal in
            var moved = proposal
            moved.furniture = proposal.furniture.map { item in
                var f = item
                let p = move(PlanPoint(x: f.x, y: f.y))
                f.x = p.x; f.y = p.y
                f.rotation = FurnitureEditor.normalized(f.rotation + turn * 180 / .pi)
                return f
            }
            // Zones are rectangles along the axes: they survive quarter turns only.
            moved.zones = quarter ? proposal.zones.map { zone in
                var z = zone
                let p = move(PlanPoint(x: z.x, y: z.y))
                z.x = p.x; z.y = p.y
                if odd { swap(&z.width, &z.depth) }
                return z
            } : []
            return moved
        }
        plan.placement = (placement ?? .identity).undoing(rotation: turn, thenShift: shift)
        return plan
    }
}

/// Rooms scanned in one go share the scan's coordinates (each room's `placement`), so they make one plan.
struct Apartment: Identifiable {
    let id: UUID
    var name: String
    /// In scan order.
    var rooms: [FloorPlan]
    var area: Double { rooms.reduce(0) { $0 + $1.area } }

    /// Apartments among the plans, in the order of their first rooms; rooms without an apartment are left out.
    static func group(_ plans: [FloorPlan]) -> [Apartment] {
        var order: [UUID] = []
        var rooms: [UUID: [FloorPlan]] = [:]
        for plan in plans {
            guard let id = plan.apartmentID else { continue }
            if rooms[id] == nil { order.append(id) }
            rooms[id, default: []].append(plan)
        }
        return order.map { id in
            let sorted = (rooms[id] ?? []).sorted { $0.createdAt < $1.createdAt }
            return Apartment(id: id, name: sorted.compactMap(\.apartmentName).first ?? "Квартира", rooms: sorted)
        }
    }

    var layout: ApartmentLayout { ApartmentLayout(self) }
}

/// Every room of an apartment in the apartment's own coordinates: the scan's frame turned so the longest wall runs
/// along x and moved to the origin — the way a single room is normalised.
struct ApartmentLayout {
    struct Room: Identifiable {
        /// The id of the room's own plan.
        let id: UUID
        let number: Int
        let name: String
        /// The room in apartment coordinates.
        let plan: FloorPlan
        var area: Double { plan.area }

        /// A point well inside the room for its number and name (the middle of an L is outside it).
        var labelPoint: PlanPoint {
            let outline = plan.outline
            let b = plan.bounds
            let middle = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
            func clearance(_ p: PlanPoint) -> Double {
                outline.indices.map { PlanMath.distance(p, toSegment: outline[$0], outline[($0 + 1) % outline.count]) }.min() ?? 0
            }
            if PlanMath.contains(outline, middle), clearance(middle) > 0.5 { return middle }
            var best = (point: middle, clearance: -1.0)
            for i in 0...12 {
                for j in 0...12 {
                    let p = PlanPoint(x: b.minX + (b.maxX - b.minX) * Double(i) / 12, y: b.minY + (b.maxY - b.minY) * Double(j) / 12)
                    guard PlanMath.contains(outline, p) else { continue }
                    let value = clearance(p)
                    if value > best.clearance { best = (p, value) }
                }
            }
            return best.point
        }
    }

    let rooms: [Room]
    let bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    var width: Double { bounds.maxX - bounds.minX }
    var depth: Double { bounds.maxY - bounds.minY }
    var area: Double { rooms.reduce(0) { $0 + $1.area } }

    init(_ apartment: Apartment) {
        let scanned = apartment.rooms.map { room -> FloorPlan in
            let placement = room.placement ?? .identity
            return room.moved(turn: placement.rotation, shift: PlanPoint(x: placement.x, y: placement.y))
        }
        let longest = scanned.flatMap(\.walls).max { $0.length < $1.length }
        let angle = longest.map { -atan2($0.end.y - $0.start.y, $0.end.x - $0.start.x) } ?? 0
        let turned = scanned.map { $0.moved(turn: angle, shift: PlanPoint(x: 0, y: 0)) }
        let boxes = turned.map(\.bounds)
        let minX = boxes.map(\.minX).min() ?? 0, minY = boxes.map(\.minY).min() ?? 0
        let maxX = boxes.map(\.maxX).max() ?? 1, maxY = boxes.map(\.maxY).max() ?? 1
        let shift = PlanPoint(x: -minX, y: -minY)
        rooms = turned.enumerated().map { index, plan in
            Room(id: apartment.rooms[index].id, number: index + 1, name: apartment.rooms[index].name, plan: plan.moved(turn: 0, shift: shift))
        }
        bounds = (0, 0, maxX - minX, maxY - minY)
    }

    /// Walls of every room; between two rooms each fills half of the real partition.
    func wallBodies(thickness: Double = WallBody.standardThickness, cut: Set<PlanSegment.Kind> = [.door, .opening, .window]) -> [WallBody] {
        let outlines = rooms.map { WallBody.outline(of: $0.plan) }
        return rooms.indices.map { index in
            WallBody(plan: rooms[index].plan, thickness: thickness, cut: cut, neighbours: outlines.enumerated().filter { $0.offset != index }.map(\.element))
        }
    }

    /// The room under a point (a finger on the plan).
    func room(at point: PlanPoint) -> Room? { rooms.first { $0.plan.contains(point) } }

    /// Doors and openings once each: a door between two rooms is seen from both; the first room keeps it.
    var doors: [(room: Int, door: PlanSegment)] {
        var result: [(room: Int, door: PlanSegment)] = []
        for (index, room) in rooms.enumerated() {
            for door in room.plan.doors {
                let middle = (door.start + door.end) * 0.5
                let seen = result.contains { other in
                    other.room != index && ((other.door.start + other.door.end) * 0.5).distance(to: middle) < 0.4
                }
                if !seen { result.append((index, door)) }
            }
        }
        return result
    }
}
