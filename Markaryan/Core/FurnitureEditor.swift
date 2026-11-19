import Foundation

/// Moving furniture by hand: a finger drags an item, the editor keeps it square and flush to the walls it comes
/// close to, and the layout check says what is wrong. Pure logic, so it is tested on Linux.
enum FurnitureEditor {
    /// How close (metres) an item has to come to a wall to stand flush with it.
    static let snapDistance = 0.2

    /// Models that normally stand against a wall: a new one is put against a free wall.
    static let wallModels: Set<String> = ["sofa", "bed", "storage", "kitchen", "appliance", "toilet", "sink", "washer", "bathtub", "shower",
                                          "desk", "tv", "mirror", "towel", "boiler", "sconce", "accessory"]

    /// Degrees in 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        let positive = value < 0 ? value + 360 : value
        return positive >= 360 - 1e-9 ? 0 : positive
    }

    /// The item under a finger: solid furniture before things on walls, rugs and ceiling lights; the smallest first
    /// (a chair on a rug, a nightstand next to a bed).
    static func item(at point: PlanPoint, in furniture: [DesignFurniture], margin: Double = 0.08) -> Int? {
        func rank(_ item: DesignFurniture) -> Int { item.blocksFloor ? 0 : (item.isMounted && !item.isCeiling ? 1 : 2) }
        return furniture.indices.filter { furniture[$0].footprint.contains(point, margin: margin) }.min { a, b in
            let ra = rank(furniture[a]), rb = rank(furniture[b])
            if ra != rb { return ra < rb }
            return furniture[a].width * furniture[a].depth < furniture[b].width * furniture[b].depth
        }
    }

    /// Quarter turns (0…3) from "back to the wall" that are closest to the item's rotation.
    static func quarterTurns(_ rotation: Double, to side: WallSide) -> Int {
        Int((normalized(rotation - side.itemRotation) / 90).rounded()) % 4
    }

    /// Moves an item so its centre is at `center`. Close to a wall — and always, for things hung on walls — it turns
    /// square to that wall and stands flush with it; close to the end of that wall it slides into the corner.
    /// Rugs and ceiling lights go exactly where the finger puts them.
    static func move(_ item: DesignFurniture, to center: PlanPoint, walls: [WallSide], snap: Bool = true) -> DesignFurniture {
        var moved = item
        moved.x = center.x; moved.y = center.y
        moved.wall = nil
        guard snap, !item.isCeiling, !item.isFlat else { return moved }
        let gapToWall = LayoutRules.wallGap
        var best: (side: WallSide, turns: Int, gap: Double)?
        for side in walls where side.length >= PlanWalls.minimumLength {
            let projected = side.project(center)
            guard projected.along > -0.1, projected.along < side.length + 0.1 else { continue }
            let turns = item.isMounted ? 0 : quarterTurns(item.rotation, to: side)
            let half = turns % 2 == 0 ? item.depth / 2 : item.width / 2
            let gap = projected.offset - half
            let reach = item.isMounted ? Double.infinity : snapDistance + gapToWall
            guard gap < reach, gap > -half - 0.3 else { continue }
            if best == nil || abs(gap - gapToWall) < abs(best!.gap - gapToWall) { best = (side, turns, gap) }
        }
        guard let best else { return moved }
        let side = best.side
        moved.rotation = normalized(side.itemRotation + Double(best.turns) * 90)
        let halfAcross = best.turns % 2 == 0 ? item.depth / 2 : item.width / 2
        let halfAlong = best.turns % 2 == 0 ? item.width / 2 : item.depth / 2
        var along = side.project(center).along
        if along - halfAlong < snapDistance + gapToWall {
            along = halfAlong + gapToWall
        } else if side.length - (along + halfAlong) < snapDistance + gapToWall {
            along = side.length - halfAlong - gapToWall
        }
        let position = side.point(along, offset: halfAcross + gapToWall)
        moved.x = position.x; moved.y = position.y
        moved.wall = side.number
        return moved
    }

    /// Turns an item about its centre. A quarter turn of an item standing at a wall keeps it flush with the wall.
    static func rotated(_ item: DesignFurniture, by degrees: Double, walls: [WallSide], snap: Bool = true) -> DesignFurniture {
        var turned = item
        turned.rotation = normalized(item.rotation + degrees)
        let quarter = abs(remainder(degrees, 90)) < 0.5
        guard quarter else { turned.wall = nil; return turned }
        guard snap, item.wall != nil else { return turned }
        return move(turned, to: PlanPoint(x: item.x, y: item.y), walls: walls)
    }

    /// A new item at a sensible free place: wall furniture against a free wall, the rest on the free spot closest to
    /// the middle of the room; the middle of the room when nothing fits (the check then says why).
    static func placeNew(_ item: DesignFurniture, plan: FloorPlan, furniture: [DesignFurniture]) -> DesignFurniture {
        let space = LayoutSpace(plan: plan)
        let solid = furniture.filter(\.blocksFloor).map { $0.footprint.grown(by: -0.01) }
        let b = plan.bounds
        let middle = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        func fits(_ candidate: DesignFurniture) -> Bool {
            guard space.isInside(candidate.footprint) else { return false }
            if candidate.isCeiling || candidate.isFlat { return true }
            if space.blocksDoor(candidate) { return false }
            if candidate.isMounted { return true }
            let core = candidate.footprint.grown(by: -0.01)
            return !solid.contains { $0.overlaps(core) }
        }
        func closest(_ candidates: [DesignFurniture]) -> DesignFurniture? {
            candidates.filter(fits).min { PlanPoint(x: $0.x, y: $0.y).distance(to: middle) < PlanPoint(x: $1.x, y: $1.y).distance(to: middle) }
        }
        if wallModels.contains(item.model) {
            var candidates: [DesignFurniture] = []
            for side in space.walls where side.length >= item.width + 2 * LayoutRules.wallGap {
                var along = item.width / 2 + LayoutRules.wallGap
                while along <= side.length - item.width / 2 - LayoutRules.wallGap + 1e-9 {
                    var candidate = item
                    let p = side.point(along, offset: item.depth / 2 + LayoutRules.wallGap)
                    candidate.x = p.x; candidate.y = p.y
                    candidate.rotation = side.itemRotation; candidate.wall = side.number
                    candidates.append(candidate)
                    along += 0.1
                }
            }
            if let found = closest(candidates) { return found }
        }
        var free: [DesignFurniture] = []
        var y = b.minY + 0.075
        while y < b.maxY {
            var x = b.minX + 0.075
            while x < b.maxX {
                var candidate = item
                candidate.x = x; candidate.y = y; candidate.rotation = 0; candidate.wall = nil
                free.append(candidate)
                x += 0.15
            }
            y += 0.15
        }
        if let found = closest(free) { return found }
        var fallback = item
        fallback.x = middle.x; fallback.y = middle.y; fallback.rotation = 0; fallback.wall = nil
        return fallback
    }
}

/// Items the furniture editor can add, with typical sizes; the room's own items first, nothing the room forbids.
enum FurnitureCatalog {
    struct Entry: Identifiable, Hashable {
        let name: String
        let kind: String
        /// Metres along the wall the item stands against.
        let width: Double
        let depth: Double
        var height: Double? = nil
        var id: String { name }
        var item: DesignFurniture { DesignFurniture(name: name, kind: kind, x: 0, y: 0, width: width, depth: depth, rotation: 0, height: height) }
    }

    static let all: [Entry] = [
        Entry(name: "Диван", kind: "sofa", width: 2.2, depth: 0.95, height: 0.85),
        Entry(name: "Кресло", kind: "chair", width: 0.85, depth: 0.85, height: 0.9),
        Entry(name: "Журнальный столик", kind: "table", width: 1.0, depth: 0.55, height: 0.45),
        Entry(name: "ТВ‑тумба с телевизором", kind: "tv", width: 1.6, depth: 0.45),
        Entry(name: "Стеллаж", kind: "storage", width: 0.8, depth: 0.35, height: 2.0),
        Entry(name: "Комод", kind: "storage", width: 1.0, depth: 0.45, height: 0.85),
        Entry(name: "Шкаф", kind: "storage", width: 1.8, depth: 0.6, height: 2.2),
        Entry(name: "Шкаф‑купе", kind: "storage", width: 2.0, depth: 0.6, height: 2.4),
        Entry(name: "Обувница", kind: "storage", width: 0.8, depth: 0.35, height: 0.9),
        Entry(name: "Кровать 160×200", kind: "bed", width: 1.6, depth: 2.05, height: 0.9),
        Entry(name: "Кровать 90×200", kind: "bed", width: 0.9, depth: 2.05, height: 0.9),
        Entry(name: "Прикроватная тумба", kind: "storage", width: 0.45, depth: 0.4, height: 0.55),
        Entry(name: "Рабочий стол", kind: "desk", width: 1.2, depth: 0.6, height: 0.75),
        Entry(name: "Стул", kind: "chair", width: 0.45, depth: 0.5),
        Entry(name: "Обеденный стол", kind: "table", width: 1.2, depth: 0.8, height: 0.75),
        Entry(name: "Кухонный гарнитур", kind: "kitchen", width: 2.4, depth: 0.6),
        Entry(name: "Холодильник", kind: "appliance", width: 0.6, depth: 0.65, height: 2.0),
        Entry(name: "Посудомоечная машина", kind: "appliance", width: 0.6, depth: 0.6, height: 0.85),
        Entry(name: "Унитаз", kind: "toilet", width: 0.4, depth: 0.6),
        Entry(name: "Раковина с тумбой", kind: "sink", width: 0.6, depth: 0.47),
        Entry(name: "Душевая", kind: "shower", width: 0.9, depth: 0.9),
        Entry(name: "Ванна", kind: "bathtub", width: 1.7, depth: 0.75),
        Entry(name: "Стиральная машина", kind: "washer", width: 0.6, depth: 0.6, height: 0.85),
        Entry(name: "Зеркало", kind: "mirror", width: 0.6, depth: 0.03),
        Entry(name: "Полотенцесушитель", kind: "towel", width: 0.5, depth: 0.1),
        Entry(name: "Водонагреватель", kind: "boiler", width: 0.45, depth: 0.45),
        Entry(name: "Растение", kind: "plant", width: 0.4, depth: 0.4),
        Entry(name: "Торшер", kind: "light", width: 0.35, depth: 0.35),
        Entry(name: "Подвесной светильник", kind: "light", width: 0.5, depth: 0.5),
        Entry(name: "Ковёр", kind: "decor", width: 2.0, depth: 1.4)
    ]

    static func entries(for room: RoomKind) -> [Entry] {
        let own: [String]
        switch room {
        case .bathroom: own = ["Унитаз", "Раковина с тумбой", "Душевая", "Ванна", "Стиральная машина", "Зеркало", "Полотенцесушитель", "Водонагреватель"]
        case .kitchen: own = ["Кухонный гарнитур", "Холодильник", "Посудомоечная машина", "Обеденный стол", "Стул"]
        case .hall: own = ["Шкаф‑купе", "Обувница", "Зеркало", "Комод"]
        case .bedroom: own = ["Кровать 160×200", "Прикроватная тумба", "Шкаф", "Комод", "Рабочий стол", "Стул", "Ковёр"]
        case .kids: own = ["Кровать 90×200", "Рабочий стол", "Стул", "Шкаф", "Стеллаж", "Ковёр"]
        case .office: own = ["Рабочий стол", "Кресло", "Стеллаж", "Шкаф"]
        case .living: own = ["Диван", "Кресло", "Журнальный столик", "ТВ‑тумба с телевизором", "Стеллаж", "Обеденный стол", "Стул", "Ковёр", "Торшер"]
        }
        let first = own.compactMap { name in all.first { $0.name == name } }
        return first + all.filter { entry in !own.contains(entry.name) && room.allows(entry.item.model) }
    }
}

/// Plan ↔ screen: the same fit and centring as `FloorPlanCanvas`, so a finger lands where the item is drawn.
struct PlanViewport {
    let originX: Double, originY: Double
    let scale: Double
    let offsetX: Double, offsetY: Double

    init(plan: FloorPlan, width: Double, height: Double, margin: Double) {
        self.init(bounds: plan.bounds, width: width, height: height, margin: margin)
    }

    init(bounds b: (minX: Double, minY: Double, maxX: Double, maxY: Double), width: Double, height: Double, margin: Double) {
        originX = b.minX; originY = b.minY
        let spanX = max(0.5, b.maxX - b.minX), spanY = max(0.5, b.maxY - b.minY)
        scale = max(1e-6, min((width - margin * 2) / spanX, (height - margin * 2) / spanY))
        offsetX = (width - (b.maxX - b.minX) * scale) / 2
        offsetY = (height - (b.maxY - b.minY) * scale) / 2
    }

    func screen(_ point: PlanPoint) -> (x: Double, y: Double) {
        (offsetX + (point.x - originX) * scale, offsetY + (point.y - originY) * scale)
    }

    func plan(x: Double, y: Double) -> PlanPoint {
        PlanPoint(x: (x - offsetX) / scale + originX, y: (y - offsetY) / scale + originY)
    }
}
