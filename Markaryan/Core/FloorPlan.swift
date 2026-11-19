import Foundation
#if canImport(RoomPlan)
import RoomPlan
import simd
#endif

// MARK: - 2D floor plan (metres, x → right, y → down, origin at the top-left of the plan)

struct FloorPlan: Codable, Identifiable {
    enum Source: String, Codable { case lidar, contour }
    var id = UUID()
    var name: String
    var createdAt = Date()
    var source: Source
    var segments: [PlanSegment]
    var objects: [PlanObject]
    var floorPolygon: [PlanPoint]
    var ceilingHeight: Double
    var modelFilename: String?
    var proposals: [DesignProposal] = []
    /// Apartment this room belongs to (several rooms scanned in one session). Nil for a separate room.
    var apartmentID: UUID? = nil
    /// Where the room sits in the scan (and apartment) coordinates; set when the plan is normalised.
    var placement: PlanPlacement? = nil

    var walls: [PlanSegment] { segments.filter { $0.kind == .wall } }
    var doors: [PlanSegment] { segments.filter { $0.kind == .door || $0.kind == .opening } }
    var windows: [PlanSegment] { segments.filter { $0.kind == .window } }

    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let points = segments.flatMap { [$0.start, $0.end] } + floorPolygon
        guard let first = points.first else { return (0, 0, 1, 1) }
        return points.reduce((first.x, first.y, first.x, first.y)) { (min($0.0, $1.x), min($0.1, $1.y), max($0.2, $1.x), max($0.3, $1.y)) }
    }
    var width: Double { bounds.maxX - bounds.minX }

    /// Floor outline (scanned polygon or the bounding rectangle).
    var outline: [PlanPoint] {
        if floorPolygon.count >= 3 { return floorPolygon }
        let b = bounds
        return [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
    }
    func contains(_ point: PlanPoint) -> Bool {
        let polygon = outline
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
    /// Door leaf opened 90° INTO the room (hinge at the start of the opening) — the same on the plan, the drawings and in 3D.
    func doorSwing(_ door: PlanSegment) -> (hinge: PlanPoint, leaf: PlanPoint) {
        let dx = door.end.x - door.start.x, dy = door.end.y - door.start.y
        let length = max(0.001, hypot(dx, dy))
        var nx = -dy / length, ny = dx / length
        let mid = PlanPoint(x: (door.start.x + door.end.x) / 2, y: (door.start.y + door.end.y) / 2)
        if !contains(PlanPoint(x: mid.x + nx * 0.3, y: mid.y + ny * 0.3)) { nx = -nx; ny = -ny }
        return (door.start, PlanPoint(x: door.start.x + nx * length, y: door.start.y + ny * length))
    }
    var depth: Double { bounds.maxY - bounds.minY }

    /// Floor area: from the floor polygon if available, otherwise the bounding rectangle.
    var area: Double {
        if floorPolygon.count >= 3 {
            var total = 0.0
            for index in floorPolygon.indices {
                let a = floorPolygon[index], b = floorPolygon[(index + 1) % floorPolygon.count]
                total += a.x * b.y - b.x * a.y
            }
            return abs(total) / 2
        }
        return width * depth
    }
    var perimeter: Double { walls.reduce(0) { $0 + $1.length } }
    var openingsArea: Double { (doors + windows).reduce(0) { $0 + $1.length * $1.height } }
    /// Net wall area for paint/plaster: perimeter × height minus doors and windows.
    var netWallArea: Double { max(0, perimeter * ceilingHeight - openingsArea) }
    var volume: Double { area * ceilingHeight }
}

extension FloorPlan {
    /// Lenient reading of saved plans. Concepts saved before 1.3 (raw AI coordinates) are fitted into the room
    /// once here and keep their room type, so the plan, the 3D model and the drawings no longer redo it on every render.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        source = try c.decode(Source.self, forKey: .source)
        segments = try c.decode([PlanSegment].self, forKey: .segments)
        objects = try c.decodeIfPresent([PlanObject].self, forKey: .objects) ?? []
        floorPolygon = try c.decodeIfPresent([PlanPoint].self, forKey: .floorPolygon) ?? []
        ceilingHeight = try c.decode(Double.self, forKey: .ceilingHeight)
        modelFilename = try c.decodeIfPresent(String.self, forKey: .modelFilename)
        apartmentID = try c.decodeIfPresent(UUID.self, forKey: .apartmentID)
        placement = try c.decodeIfPresent(PlanPlacement.self, forKey: .placement)
        let saved = try c.decodeIfPresent([DesignProposal].self, forKey: .proposals) ?? []
        proposals = []
        proposals = saved.map { $0.placed(in: self) }
    }
}

// MARK: - Building plans

enum FloorPlanBuilder {
    /// Normalises raw points: rotates so the longest wall is horizontal, then moves the plan to the origin with a small margin.
    /// The transform back to the scan coordinates is kept in `placement` (rooms of one apartment share those coordinates).
    static func normalize(_ plan: FloorPlan) -> FloorPlan {
        var plan = plan
        var angle = 0.0
        if let longest = plan.walls.max(by: { $0.length < $1.length }) {
            angle = -atan2(longest.end.y - longest.start.y, longest.end.x - longest.start.x)
            let cosA = cos(angle), sinA = sin(angle)
            func rotate(_ p: PlanPoint) -> PlanPoint { PlanPoint(x: p.x * cosA - p.y * sinA, y: p.x * sinA + p.y * cosA) }
            plan.segments = plan.segments.map { var s = $0; s.start = rotate(s.start); s.end = rotate(s.end); return s }
            plan.floorPolygon = plan.floorPolygon.map(rotate)
            plan.objects = plan.objects.map { var o = $0; o.center = rotate(o.center); o.rotation += angle; return o }
        }
        let b = plan.bounds
        let shift = PlanPoint(x: -b.minX, y: -b.minY)
        plan.segments = plan.segments.map { var s = $0; s.start = s.start + shift; s.end = s.end + shift; return s }
        plan.floorPolygon = plan.floorPolygon.map { $0 + shift }
        plan.objects = plan.objects.map { var o = $0; o.center = o.center + shift; return o }
        plan.placement = (plan.placement ?? .identity).undoing(rotation: angle, thenShift: shift)
        return plan
    }

    /// Plan from an AR floor contour (works on any iPhone with ARKit).
    static func fromContour(_ points: [SIMD3<Float>], name: String, ceilingHeight: Double = 2.7) -> FloorPlan? {
        guard points.count >= 3 else { return nil }
        let polygon = points.map { PlanPoint(x: Double($0.x), y: Double($0.z)) }
        var segments: [PlanSegment] = []
        for index in polygon.indices {
            segments.append(PlanSegment(kind: .wall, start: polygon[index], end: polygon[(index + 1) % polygon.count], height: ceilingHeight))
        }
        return normalize(FloorPlan(name: name, source: .contour, segments: segments, objects: [], floorPolygon: polygon, ceilingHeight: ceilingHeight, modelFilename: nil))
    }

    #if canImport(RoomPlan)
    /// Plan from an Apple RoomPlan LiDAR scan: walls, doors, windows, openings, floor outline and furniture.
    @available(iOS 17.0, *)
    static func fromRoom(_ room: CapturedRoom, name: String, modelFilename: String?) -> FloorPlan {
        func flat(_ v: simd_float4) -> PlanPoint { PlanPoint(x: Double(v.x), y: Double(v.z)) }
        func segment(_ surface: CapturedRoom.Surface, kind: PlanSegment.Kind) -> PlanSegment {
            let center = surface.transform.columns.3
            let axis = simd_normalize(simd_float3(surface.transform.columns.0.x, 0, surface.transform.columns.0.z))
            let half = surface.dimensions.x / 2
            let start = simd_float4(center.x - axis.x * half, 0, center.z - axis.z * half, 1)
            let end = simd_float4(center.x + axis.x * half, 0, center.z + axis.z * half, 1)
            return PlanSegment(kind: kind, start: flat(start), end: flat(end), height: Double(surface.dimensions.y))
        }
        var segments: [PlanSegment] = room.walls.map { segment($0, kind: .wall) }
        segments += room.doors.map { segment($0, kind: .door) }
        segments += room.windows.map { segment($0, kind: .window) }
        segments += room.openings.map { segment($0, kind: .opening) }

        var polygon: [PlanPoint] = []
        if let floor = room.floors.first, floor.polygonCorners.count >= 3 {
            polygon = floor.polygonCorners.map { corner in flat(floor.transform * simd_float4(corner.x, corner.y, corner.z, 1)) }
        }
        let objects = room.objects.map { object -> PlanObject in
            let c = object.transform.columns.3
            let axis = object.transform.columns.0
            return PlanObject(name: objectName(object.category), center: flat(c), width: Double(object.dimensions.x), depth: Double(object.dimensions.z), rotation: atan2(Double(axis.z), Double(axis.x)))
        }
        let heights = room.walls.map { Double($0.dimensions.y) }
        let height = heights.isEmpty ? 2.7 : heights.reduce(0, +) / Double(heights.count)
        return normalize(FloorPlan(name: name, source: .lidar, segments: segments, objects: objects, floorPolygon: polygon, ceilingHeight: height, modelFilename: modelFilename))
    }

    @available(iOS 17.0, *)
    private static func objectName(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .bed: return "Кровать"
        case .sofa: return "Диван"
        case .table: return "Стол"
        case .chair: return "Стул"
        case .storage: return "Шкаф"
        case .refrigerator: return "Холодильник"
        case .stove: return "Плита"
        case .oven: return "Духовка"
        case .dishwasher: return "Посудомойка"
        case .washerDryer: return "Стиральная машина"
        case .sink: return "Раковина"
        case .bathtub: return "Ванна"
        case .toilet: return "Унитаз"
        case .fireplace: return "Камин"
        case .television: return "Телевизор"
        case .stairs: return "Лестница"
        @unknown default: return "Предмет"
        }
    }
    #endif
}
