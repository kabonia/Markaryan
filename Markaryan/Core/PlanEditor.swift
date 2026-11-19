import Foundation

/// Corrections of a plan after the scan: wall lengths, the ceiling, doors and windows, square corners.
/// Every edit carries along what stands on the plan — doors, windows, scanned objects, the furniture and zones of
/// every concept — and is refused when the outline would cross itself.
enum PlanEditor {
    enum EditError: LocalizedError, Equatable {
        case noWall
        case value(String)
        case outline
        case opening(String)

        var errorDescription: String? {
            switch self {
            case .noWall: return "Такой стены нет на плане."
            case .value(let text), .opening(let text): return text
            case .outline: return "После такой правки стены пересекутся. Возьмите значение поменьше."
            }
        }
    }

    /// An opening as the editor shows it: on which numbered wall, where and how big.
    struct OpeningSpec: Equatable {
        var kind: PlanSegment.Kind
        /// `PlanWalls` number.
        var wall: Int
        /// Metres from the start of the wall (walls run clockwise on the plan).
        var from: Double
        var width: Double
        var height: Double
        /// Windows: metres from the floor to the bottom of the window.
        var sill: Double
        /// Doors: the leaf hangs at the far end of the opening (the door opens the other way).
        var hingeAtEnd = false

        static func door(wall: Int, from: Double) -> OpeningSpec { OpeningSpec(kind: .door, wall: wall, from: from, width: 0.8, height: 2.1, sill: 0) }
        static func window(wall: Int, from: Double) -> OpeningSpec { OpeningSpec(kind: .window, wall: wall, from: from, width: 1.2, height: 1.5, sill: 0.85) }
    }

    // MARK: Wall length

    /// Gives wall `number` a new length. The part of the room beyond the end of the wall moves along it, so the walls
    /// parallel to it grow or shrink with it and right angles stay right. Doors and windows keep their distance to the
    /// nearer corner of their wall; furniture and scanned objects beyond the middle of the wall move with the far part.
    static func setWallLength(_ plan: FloorPlan, wall number: Int, to length: Double) throws -> FloorPlan {
        guard let side = PlanWalls.numbered(plan).first(where: { $0.number == number }) else { throw EditError.noWall }
        guard length.isFinite, length >= 0.3, length <= 30 else { throw EditError.value("Длина стены — от 0,3 до 30 м.") }
        let delta = length - side.length
        guard abs(delta) >= 0.0005 else { return plan }
        let direction = side.direction, shift = direction * delta
        // Corners at the end of the wall (scanned walls rarely meet exactly) and beyond it move.
        let endLine = side.end.dot(direction) - min(0.15, side.length / 3)
        let middleLine = (side.start.dot(direction) + side.end.dot(direction)) / 2
        func corner(_ p: PlanPoint) -> PlanPoint { p.dot(direction) >= endLine ? p + shift : p }
        func item(_ p: PlanPoint) -> PlanPoint { p.dot(direction) > middleLine ? p + shift : p }

        var edited = plan
        edited.floorPolygon = plan.floorPolygon.map(corner)
        var walls: [UUID: PlanSegment] = [:]
        edited.segments = plan.segments.map { segment in
            guard segment.kind == .wall else { return segment }
            var wall = segment
            wall.start = corner(segment.start); wall.end = corner(segment.end)
            walls[wall.id] = wall
            return wall
        }
        try checkNoFlips(old: plan.walls.map { ($0.start, $0.end) }, new: plan.walls.compactMap { walls[$0.id].map { ($0.start, $0.end) } })
        try checkNoFlips(old: edges(plan.floorPolygon), new: edges(edited.floorPolygon))
        guard isValidOutline(edited) else { throw EditError.outline }

        edited.segments = try edited.segments.map { segment in
            guard segment.kind != .wall else { return segment }
            return try carried(segment, from: plan, to: walls, otherwise: item)
        }
        edited.objects = plan.objects.map { object in var o = object; o.center = item(object.center); return o }
        edited.proposals = plan.proposals.map { proposal in
            var p = proposal
            p.furniture = proposal.furniture.map { furniture in
                var f = furniture
                let moved = item(PlanPoint(x: f.x, y: f.y)); f.x = moved.x; f.y = moved.y
                return f
            }
            p.zones = proposal.zones.map { zone in
                var z = zone
                let moved = item(PlanPoint(x: z.x, y: z.y)); z.x = moved.x; z.y = moved.y
                return z
            }
            return p
        }
        edited.editedAt = Date()
        return edited
    }

    // MARK: Ceiling

    /// New ceiling height for the room and its walls; doors and windows that would reach it are made lower.
    static func setCeilingHeight(_ plan: FloorPlan, to height: Double) throws -> FloorPlan {
        guard height.isFinite, height >= 1.8, height <= 6 else { throw EditError.value("Высота потолка — от 1,8 до 6 м.") }
        var edited = plan
        edited.ceilingHeight = height
        edited.segments = plan.segments.map { segment in
            var s = segment
            switch s.kind {
            case .wall:
                s.height = height
            case .door, .opening:
                s.height = min(s.height, height - 0.05)
            case .window:
                if let sill = s.elevation, sill > height - 0.4 { s.elevation = max(0, height - 0.4) }
                let sill = s.elevation ?? 0.85
                s.height = max(0.3, min(s.height, height - 0.05 - sill))
            }
            return s
        }
        edited.editedAt = Date()
        return edited
    }

    // MARK: Doors and windows

    /// Where an opening is on its wall, as the editor shows it; nil when it lies on no wall.
    static func spec(of id: UUID, in plan: FloorPlan) -> OpeningSpec? {
        for wall in PlanWalls.numbered(plan) {
            guard let opening = (wall.doors + wall.windows).first(where: { $0.segment.id == id }) else { continue }
            let segment = opening.segment
            let hingeAtEnd = segment.kind != .window && wall.project(segment.start).along > wall.project(segment.end).along
            // Millimetres are enough for the editor.
            func mm(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
            return OpeningSpec(kind: segment.kind, wall: wall.number, from: mm(opening.from), width: mm(opening.to - opening.from),
                               height: mm(segment.height), sill: segment.kind == .window ? mm(segment.elevation ?? 0.85) : 0, hingeAtEnd: hingeAtEnd)
        }
        return nil
    }

    /// Adds a door, an opening without a door or a window (plans from the AR contour have none of them).
    static func addOpening(_ plan: FloorPlan, _ spec: OpeningSpec) throws -> (plan: FloorPlan, id: UUID) {
        let segment = try opening(spec, id: UUID(), in: plan, ignoring: nil)
        var edited = plan
        edited.segments.append(segment)
        edited.editedAt = Date()
        return (edited, segment.id)
    }

    static func updateOpening(_ plan: FloorPlan, id: UUID, to spec: OpeningSpec) throws -> FloorPlan {
        guard let index = plan.segments.firstIndex(where: { $0.id == id && $0.kind != .wall }) else { throw EditError.opening("Этого проёма уже нет на плане.") }
        var edited = plan
        edited.segments[index] = try opening(spec, id: id, in: plan, ignoring: id)
        edited.editedAt = Date()
        return edited
    }

    static func removeOpening(_ plan: FloorPlan, id: UUID) -> FloorPlan {
        var edited = plan
        edited.segments.removeAll { $0.id == id && $0.kind != .wall }
        edited.editedAt = Date()
        return edited
    }

    private static func opening(_ spec: OpeningSpec, id: UUID, in plan: FloorPlan, ignoring: UUID?) throws -> PlanSegment {
        guard spec.kind != .wall else { throw EditError.opening("Выберите дверь, проём или окно.") }
        guard let wall = PlanWalls.numbered(plan).first(where: { $0.number == spec.wall }) else { throw EditError.noWall }
        let name = spec.kind == .window ? "Окно" : (spec.kind == .door ? "Дверь" : "Проём")
        guard [spec.from, spec.width, spec.height, spec.sill].allSatisfy(\.isFinite) else { throw EditError.value("Введите размеры числами.") }
        guard spec.width >= 0.3, spec.width <= 6 else { throw EditError.opening("Ширина — от 0,3 до 6 м.") }
        guard spec.from >= -0.001, spec.from + spec.width <= wall.length + 0.001 else {
            throw EditError.opening("\(name) выходит за стену \(wall.number): её длина \(meters(wall.length)) м.")
        }
        let top = spec.kind == .window ? spec.sill + spec.height : spec.height
        guard spec.height >= 0.3, top <= plan.ceilingHeight + 0.001, spec.sill >= 0 else {
            throw EditError.opening("\(name) не помещается по высоте: потолок \(meters(plan.ceilingHeight)) м.")
        }
        let from = max(0, spec.from), to = min(wall.length, spec.from + spec.width)
        for other in wall.doors + wall.windows where other.segment.id != ignoring {
            if min(to, other.to) - max(from, other.from) > 0.01 {
                throw EditError.opening("\(name) заходит на другой проём этой стены (\(meters(other.from))–\(meters(other.to)) м от начала).")
            }
        }
        let a = wall.point(from), b = wall.point(to)
        let hingeAtEnd = spec.kind != .window && spec.hingeAtEnd
        return PlanSegment(id: id, kind: spec.kind, start: hingeAtEnd ? b : a, end: hingeAtEnd ? a : b, height: spec.height,
                           elevation: spec.kind == .window ? spec.sill : 0)
    }

    // MARK: Square corners

    /// Squares corners that are a few degrees off: every outline edge within `tolerance` degrees of the plan axes is
    /// turned onto the axis, the corners are recomputed, and walls, doors, windows, objects and furniture follow
    /// their nearest edge. Returns the plan and how many corners moved (0 — the corners were already square).
    static func straightened(_ plan: FloorPlan, tolerance: Double = 12) throws -> (plan: FloorPlan, corners: Int) {
        guard plan.floorPolygon.count >= 3 else { throw EditError.value("В этом плане нет контура пола — выпрямлять нечего.") }
        // Edges whose ends are nearly in line are one edge.
        var old = plan.floorPolygon
        var merged = true
        while merged && old.count > 3 {
            merged = false
            for i in old.indices {
                let a = old[(i + old.count - 1) % old.count], b = old[i], c = old[(i + 1) % old.count]
                let ab = b - a, bc = c - b
                guard ab.length > 1e-9, bc.length > 1e-9 else { old.remove(at: i); merged = true; break }
                if abs(ab.cross(bc)) / (ab.length * bc.length) < sin(2 * .pi / 180), ab.dot(bc) > 0 { old.remove(at: i); merged = true; break }
            }
        }
        let limit = tolerance * .pi / 180
        let lines: [(point: PlanPoint, direction: PlanPoint)] = old.indices.map { i in
            let a = old[i], b = old[(i + 1) % old.count]
            let angle = atan2(b.y - a.y, b.x - a.x)
            let axis = (angle / (.pi / 2)).rounded() * (.pi / 2)
            let turned = abs(angle - axis) <= limit ? axis : angle
            return ((a + b) * 0.5, PlanPoint(x: cos(turned), y: sin(turned)))
        }
        var corners: [PlanPoint] = []
        for i in old.indices {
            let previous = lines[(i + old.count - 1) % old.count], next = lines[i]
            let denominator = previous.direction.cross(next.direction)
            guard abs(denominator) > 1e-6 else { corners.append(old[i]); continue }
            let t = (next.point - previous.point).cross(next.direction) / denominator
            corners.append(previous.point + previous.direction * t)
        }
        let moved = zip(old, corners).filter { $0.distance(to: $1) > 0.005 }.count
        guard moved > 0 || old.count != plan.floorPolygon.count else { return (plan, 0) }
        guard zip(old, corners).allSatisfy({ $0.distance(to: $1) < 0.4 }), PlanMath.isSimple(corners),
              abs(abs(PlanMath.signedArea2(corners)) - abs(PlanMath.signedArea2(old))) <= abs(PlanMath.signedArea2(old)) * 0.1 else {
            throw EditError.value("Не удалось выпрямить: углы этого плана слишком далеки от прямых.")
        }

        // Everything follows its nearest edge: the same distance along it and from it, turned with it.
        let oldEdges = old.indices.map { (old[$0], old[($0 + 1) % old.count]) }
        let newEdges = corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
        func nearest(_ p: PlanPoint) -> Int {
            oldEdges.indices.min { PlanMath.distance(p, toSegment: oldEdges[$0].0, oldEdges[$0].1) < PlanMath.distance(p, toSegment: oldEdges[$1].0, oldEdges[$1].1) } ?? 0
        }
        func frame(_ edge: (PlanPoint, PlanPoint)) -> (origin: PlanPoint, x: PlanPoint, y: PlanPoint, length: Double) {
            let d = edge.1 - edge.0, length = max(1e-9, d.length)
            let x = d * (1 / length)
            return (edge.0, x, PlanPoint(x: -x.y, y: x.x), length)
        }
        func map(_ p: PlanPoint, edge index: Int) -> PlanPoint {
            let from = frame(oldEdges[index]), to = frame(newEdges[index])
            let along = (p - from.origin).dot(from.x) / from.length, across = (p - from.origin).dot(from.y)
            return to.origin + to.x * (along * to.length) + to.y * across
        }
        func map(_ p: PlanPoint) -> PlanPoint { map(p, edge: nearest(p)) }
        func turn(_ p: PlanPoint) -> Double {
            let index = nearest(p)
            let a = oldEdges[index].1 - oldEdges[index].0, b = newEdges[index].1 - newEdges[index].0
            return atan2(a.cross(b), a.dot(b))
        }

        var edited = plan
        edited.floorPolygon = corners
        edited.segments = plan.segments.map { segment in
            var s = segment
            s.start = map(segment.start); s.end = map(segment.end)
            return s
        }
        edited.objects = plan.objects.map { object in
            var o = object
            o.rotation += turn(object.center); o.center = map(object.center)
            return o
        }
        edited.proposals = plan.proposals.map { proposal in
            var p = proposal
            p.furniture = proposal.furniture.map { furniture in
                var f = furniture
                let center = PlanPoint(x: f.x, y: f.y), moved = map(center)
                f.rotation = FurnitureEditor.normalized(f.rotation + turn(center) * 180 / .pi)
                f.x = moved.x; f.y = moved.y
                return f
            }
            p.zones = proposal.zones.map { zone in
                var z = zone
                let moved = map(PlanPoint(x: z.x, y: z.y)); z.x = moved.x; z.y = moved.y
                return z
            }
            return p
        }
        edited.editedAt = Date()
        return (edited, max(moved, plan.floorPolygon.count - old.count))
    }

    // MARK: Helpers

    /// The opening after its wall changed: the same distance to the nearer corner of the wall, kept on the wall.
    private static func carried(_ opening: PlanSegment, from plan: FloorPlan, to walls: [UUID: PlanSegment], otherwise move: (PlanPoint) -> PlanPoint) throws -> PlanSegment {
        var result = opening
        let host = plan.walls.filter { wall in
            [opening.start, opening.end].allSatisfy { PlanMath.distance($0, toSegment: wall.start, wall.end) < 0.25 }
        }.min { a, b in
            PlanMath.distance((opening.start + opening.end) * 0.5, toSegment: a.start, a.end) < PlanMath.distance((opening.start + opening.end) * 0.5, toSegment: b.start, b.end)
        }
        guard let host, let new = walls[host.id], host.length > 1e-6, new.length > 1e-6 else {
            let mid = (opening.start + opening.end) * 0.5, shift = move(mid) - mid
            result.start = opening.start + shift; result.end = opening.end + shift
            return result
        }
        let u = (host.end - host.start) * (1 / host.length), n = PlanPoint(x: -u.y, y: u.x)
        let u2 = (new.end - new.start) * (1 / new.length), n2 = PlanPoint(x: -u2.y, y: u2.x)
        var a0 = (opening.start - host.start).dot(u), a1 = (opening.end - host.start).dot(u)
        let o0 = (opening.start - host.start).dot(n), o1 = (opening.end - host.start).dot(n)
        if (a0 + a1) / 2 > host.length / 2 {
            // Keeps its distance to the end of the wall.
            a0 += new.length - host.length; a1 += new.length - host.length
        }
        let low = min(a0, a1), high = max(a0, a1)
        guard high - low <= new.length + 1e-6 else {
            throw EditError.opening("Проём шириной \(meters(high - low)) м не помещается на стене длиной \(meters(new.length)) м.")
        }
        let slide = low < 0 ? -low : (high > new.length ? new.length - high : 0)
        a0 += slide; a1 += slide
        result.start = new.start + u2 * a0 + n2 * o0
        result.end = new.start + u2 * a1 + n2 * o1
        return result
    }

    private static func edges(_ polygon: [PlanPoint]) -> [(PlanPoint, PlanPoint)] {
        polygon.count >= 3 ? polygon.indices.map { (polygon[$0], polygon[($0 + 1) % polygon.count]) } : []
    }

    /// Lines keep their direction and some length: a wall shortened past its other end would turn inside out.
    private static func checkNoFlips(old: [(PlanPoint, PlanPoint)], new: [(PlanPoint, PlanPoint)]) throws {
        for (before, after) in zip(old, new) where before.0 != after.0 || before.1 != after.1 {
            let a = before.1 - before.0, b = after.1 - after.0
            if a.length < 1e-6 { continue }
            if b.length < min(0.05, a.length / 2) || a.dot(b) <= 0 { throw EditError.outline }
        }
    }

    private static func isValidOutline(_ plan: FloorPlan) -> Bool {
        guard plan.floorPolygon.count >= 3 else { return true }
        return PlanMath.isSimple(plan.floorPolygon) && plan.area >= 0.5
    }

    /// A size typed by hand: «3,42», «3.42 м», centimetres «342» or «342 см», millimetres «3420 мм»; nil when it is no number.
    static func parseMeters(_ text: String) -> Double? {
        let lower = text.lowercased()
        let digits = String(lower.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." })
        guard !digits.isEmpty, let value = Double(digits), value.isFinite else { return nil }
        if lower.contains("мм") || lower.contains("mm") { return value / 1000 }
        if lower.contains("см") || lower.contains("cm") { return value / 100 }
        if value > 3000 { return value / 1000 }
        if value > 30 { return value / 100 }
        return value
    }

    static func meters(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}

extension PlanMath {
    /// No two edges of the closed polygon cross or touch, except neighbours at their shared corner.
    static func isSimple(_ polygon: [PlanPoint]) -> Bool {
        let n = polygon.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            if a.distance(to: b) < 1e-9 { return false }
            for j in (i + 1)..<n {
                let adjacent = j == i + 1 || (i == 0 && j == n - 1)
                let c = polygon[j], d = polygon[(j + 1) % n]
                if adjacent {
                    // Neighbours must not fold back onto each other.
                    let shared = j == i + 1 ? b : a
                    let first = j == i + 1 ? a : b, second = j == i + 1 ? d : c
                    let u = first - shared, v = second - shared
                    if abs(u.cross(v)) < 1e-9 * max(1, u.length * v.length), u.dot(v) > 0 { return false }
                    continue
                }
                if segmentsCross(a, b, c, d) { return false }
                if distance(c, toSegment: a, b) < 1e-6 || distance(d, toSegment: a, b) < 1e-6
                    || distance(a, toSegment: c, d) < 1e-6 || distance(b, toSegment: c, d) < 1e-6 { return false }
            }
        }
        return true
    }
}
