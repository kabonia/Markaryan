import Foundation

/// A problem in a furniture layout, in words the client understands.
struct LayoutIssue: Hashable {
    enum Kind: String { case outside, overlap, door, front, passage, window }
    let kind: Kind
    let message: String
    /// Indices of the items it is about (in the list that was checked), so an editor can mark them.
    var items: [Int] = []
}

/// Free space a piece of equipment needs in front of it to be used (metres).
enum LayoutRules {
    /// Narrowest passage people can walk through.
    static let passage = 0.7
    /// Gap between the back of an item and the wall line: the scanned line is the inner face of the wall
    /// (`WallBody` draws the wall outward), so only the skirting and a little air.
    static let wallGap = 0.03

    static func frontClearance(_ item: DesignFurniture) -> Double {
        switch item.model {
        case "kitchen": return 0.9
        case "appliance": return 0.7
        case "storage": return item.estimatedHeight >= 1.5 && item.depth >= 0.45 ? 0.7 : 0
        case "desk": return 0.6
        case "sink", "toilet", "shower", "washer": return 0.6
        case "bathtub": return 0.5
        default: return 0
        }
    }

    /// Chairs, plants and similar small things are moved by hand: they do not close a passage.
    static func isMovable(_ item: DesignFurniture) -> Bool { ["chair", "plant", "floorlamp"].contains(item.model) }

    /// Sides people must be able to reach (local directions of the item); empty — no access needed.
    static func accessSides(_ item: DesignFurniture) -> [PlanPoint] {
        let front = PlanPoint(x: 0, y: 1), back = PlanPoint(x: 0, y: -1), left = PlanPoint(x: -1, y: 0), right = PlanPoint(x: 1, y: 0)
        let n = item.name.lowercased()
        switch item.model {
        case "chair", "plant", "decor", "tv", "floorlamp": return []
        case "bed", "sofa": return [left, right, front]
        case "table": return [front, back, left, right]
        case "storage" where item.estimatedHeight < 1.2 && (n.contains("тумб") || n.contains("комод") || n.contains("полк")) && item.width <= 0.7: return []
        default: return item.blocksFloor ? [front] : []
        }
    }
}

/// Everything about the room that layout checks need, computed once per plan.
struct LayoutSpace {
    let plan: FloorPlan
    let outline: [PlanPoint]
    let walls: [WallSide]
    /// Every wall line (including short fragments) as segments.
    let wallLines: [(PlanPoint, PlanPoint)]
    /// Where a door leaf swings (a quarter circle) or people walk through an opening (a rectangle); convex polygons.
    let doorZones: [[PlanPoint]]
    /// Points just inside every door; the first is the entrance.
    let entrances: [PlanPoint]

    private let step: Double
    private let originX: Double, originY: Double
    private let columns: Int, rows: Int
    /// Cell centres inside the room with their distance to the nearest wall (nil — outside the room).
    private let wallClearance: [Double?]

    init(plan: FloorPlan) {
        self.plan = plan
        var outline = plan.outline
        if PlanMath.signedArea2(outline) < 0 { outline.reverse() }
        self.outline = outline
        walls = PlanWalls.numbered(plan)
        var lines = plan.walls.map { ($0.start, $0.end) }
        for i in outline.indices { lines.append((outline[i], outline[(i + 1) % outline.count])) }
        wallLines = lines

        var zones: [[PlanPoint]] = []
        var inside: [PlanPoint] = []
        for door in plan.doors {
            let width = max(0.4, door.length)
            let along = (door.end - door.start) * (1 / max(1e-9, door.length))
            let swing = plan.doorSwing(door)
            let normal = (swing.leaf - swing.hinge) * (1 / max(1e-9, swing.leaf.distance(to: swing.hinge)))
            let middle = (door.start + door.end) * 0.5
            if door.kind == .door {
                // The leaf sweeps a quarter circle from the closed position to the open one.
                let start = atan2(door.end.y - swing.hinge.y, door.end.x - swing.hinge.x)
                var sweep = atan2(swing.leaf.y - swing.hinge.y, swing.leaf.x - swing.hinge.x) - start
                if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
                zones.append([swing.hinge] + (0...8).map { step in
                    let angle = start + sweep * Double(step) / 8
                    return swing.hinge + PlanPoint(x: cos(angle), y: sin(angle)) * width
                })
            } else {
                zones.append(PlanRect(center: middle + normal * 0.3, width: width, depth: 0.6, rotation: atan2(along.y, along.x)).corners)
            }
            inside.append(middle + normal * 0.45)
        }
        doorZones = zones
        entrances = inside

        let b = plan.bounds
        let area = max(1, plan.area)
        step = max(0.05, (area / 20_000).squareRoot())
        originX = b.minX; originY = b.minY
        columns = max(1, Int(((b.maxX - b.minX) / step).rounded(.up)))
        rows = max(1, Int(((b.maxY - b.minY) / step).rounded(.up)))
        var clearance: [Double?] = Array(repeating: nil, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let p = PlanPoint(x: b.minX + (Double(column) + 0.5) * step, y: b.minY + (Double(row) + 0.5) * step)
                guard PlanMath.contains(outline, p) else { continue }
                clearance[row * columns + column] = lines.map { PlanMath.distance(p, toSegment: $0.0, $0.1) }.min() ?? .infinity
            }
        }
        wallClearance = clearance
    }

    // MARK: Single item

    /// The footprint stays inside the room and no wall line crosses it.
    func isInside(_ rect: PlanRect) -> Bool {
        let core = rect.grown(by: -0.005)
        guard PlanMath.polygon(outline, contains: core) else { return false }
        return !plan.walls.contains { core.crosses($0.start, $0.end) }
    }

    /// The item stands where a door leaf swings or where people walk in.
    func blocksDoor(_ item: DesignFurniture) -> Bool {
        guard !item.isCeiling, !item.isFlat else { return false }
        let core = item.footprint.grown(by: -0.01).corners
        return doorZones.contains { PlanMath.convexOverlap($0, core) }
    }

    /// Tall item with its back to a window.
    func blocksWindow(_ item: DesignFurniture) -> Bool {
        guard item.blocksFloor, item.estimatedHeight >= 1.2 else { return false }
        let corners = item.footprint.corners
        for wall in walls where !wall.windows.isEmpty {
            let projected = corners.map { wall.project($0) }
            guard projected.map(\.offset).min()! < 0.35 else { continue }
            let from = projected.map(\.along).min()!, to = projected.map(\.along).max()!
            if wall.windows.contains(where: { min(to, $0.to) - max(from, $0.from) > 0.1 }) { return true }
        }
        return false
    }

    /// Free area the item needs in front of it (nil when it needs none).
    func frontZone(of item: DesignFurniture) -> PlanRect? {
        let depth = LayoutRules.frontClearance(item)
        guard depth > 0 else { return nil }
        let rect = item.footprint
        return PlanRect(center: rect.center + rect.axisY * (item.depth / 2 + depth / 2), width: max(0.5, item.width * 0.9), depth: depth, rotation: rect.rotation)
    }

    // MARK: Passages

    struct Reach {
        /// Nobody can walk in from the entrance.
        var entranceBlocked = false
        /// Indices of items people cannot reach through passages of `LayoutRules.passage`.
        var unreachable: [Int] = []
    }

    /// Half of the narrowest passage (a little less, for the 5 cm grid).
    static let walkRadius = LayoutRules.passage / 2 - 0.025

    /// Cells where a 0.7 m wide person fits, given only the walls.
    var emptyRoomMap: [Bool] { wallClearance.map { ($0 ?? 0) >= LayoutSpace.walkRadius } }

    /// Marks the cells a solid item takes from the passages (closer than half a passage to its footprint).
    func block(_ map: inout [Bool], with rect: PlanRect) {
        let radius = LayoutSpace.walkRadius
        let corners = rect.grown(by: radius).corners
        let c0 = max(0, Int(((corners.map(\.x).min()! - originX) / step).rounded(.down))), c1 = min(columns - 1, Int(((corners.map(\.x).max()! - originX) / step).rounded(.down)))
        let r0 = max(0, Int(((corners.map(\.y).min()! - originY) / step).rounded(.down))), r1 = min(rows - 1, Int(((corners.map(\.y).max()! - originY) / step).rounded(.down)))
        guard c0 <= c1, r0 <= r1 else { return }
        for row in r0...r1 {
            for column in c0...c1 {
                let index = row * columns + column
                if map[index] && rect.distance(to: cellCenter(index)) < radius { map[index] = false }
            }
        }
    }

    /// Passage map for these items (only solid ones block: chairs and plants are moved by hand).
    func walkableMap(_ furniture: [DesignFurniture]) -> [Bool] {
        var map = emptyRoomMap
        for item in furniture where item.blocksFloor && !LayoutRules.isMovable(item) { block(&map, with: item.footprint) }
        return map
    }

    /// Flood fill from the entrance through every place where a 0.7 m wide person fits.
    func reach(_ furniture: [DesignFurniture]) -> Reach { reach(furniture, walkable: walkableMap(furniture)) }

    /// Same, on a passage map that already has the items blocked (the layout engine keeps one up to date).
    func reach(_ furniture: [DesignFurniture], walkable: [Bool]) -> Reach {
        let radius = LayoutSpace.walkRadius
        func cells(near point: PlanPoint, within distance: Double) -> [Int] {
            let reachCells = Int((distance / step).rounded(.up))
            let column = Int(((point.x - originX) / step).rounded(.down)), row = Int(((point.y - originY) / step).rounded(.down))
            let rowRange = (max(0, row - reachCells), min(rows - 1, row + reachCells))
            let columnRange = (max(0, column - reachCells), min(columns - 1, column + reachCells))
            guard rowRange.0 <= rowRange.1, columnRange.0 <= columnRange.1 else { return [] }
            var found: [Int] = []
            for r in rowRange.0...rowRange.1 {
                for c in columnRange.0...columnRange.1 {
                    let index = r * columns + c
                    if walkable[index] && cellCenter(index).distance(to: point) <= distance { found.append(index) }
                }
            }
            return found
        }

        var result = Reach()
        var start = entrances.flatMap { cells(near: $0, within: 0.3) }
        if entrances.isEmpty {
            // AR contours have no doors: start from the most open place of the room.
            if let best = walkable.indices.filter({ walkable[$0] }).max(by: { (wallClearance[$0] ?? 0) < (wallClearance[$1] ?? 0) }) { start = [best] }
        }
        guard !start.isEmpty else {
            result.entranceBlocked = true
            result.unreachable = furniture.indices.filter { !LayoutRules.accessSides(furniture[$0]).isEmpty }
            return result
        }
        var reached = [Bool](repeating: false, count: columns * rows)
        var queue = start
        for index in start { reached[index] = true }
        var head = 0
        while head < queue.count {
            let index = queue[head]; head += 1
            let row = index / columns, column = index % columns
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let r = row + dr, c = column + dc
                    guard r >= 0, r < rows, c >= 0, c < columns else { continue }
                    let next = r * columns + c
                    if walkable[next] && !reached[next] { reached[next] = true; queue.append(next) }
                }
            }
        }
        for (index, item) in furniture.enumerated() {
            let sides = LayoutRules.accessSides(item)
            guard !sides.isEmpty else { continue }
            let rect = item.footprint
            let ok = sides.contains { side in
                let extent = side.x != 0 ? item.width / 2 : item.depth / 2
                let direction = rect.axisX * side.x + rect.axisY * side.y
                let point = rect.center + direction * (extent + radius)
                return cells(near: point, within: step * 2.5).contains { reached[$0] }
            }
            if !ok { result.unreachable.append(index) }
        }
        return result
    }

    private func cellCenter(_ index: Int) -> PlanPoint {
        PlanPoint(x: originX + (Double(index % columns) + 0.5) * step, y: originY + (Double(index / columns) + 0.5) * step)
    }
}

/// Checks a finished layout: inside the walls, no overlaps, doors open, room to use every item, passages ≥ 0.7 m.
enum LayoutCheck {
    static func issues(plan: FloorPlan, furniture: [DesignFurniture]) -> [LayoutIssue] {
        let space = LayoutSpace(plan: plan)
        return issues(space: space, furniture: furniture)
    }

    static func issues(space: LayoutSpace, furniture: [DesignFurniture]) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        let floor = furniture.indices.filter { furniture[$0].blocksFloor }
        for i in floor where !space.isInside(furniture[i].footprint) {
            issues.append(LayoutIssue(kind: .outside, message: "«\(furniture[i].name)» выходит за стену", items: [i]))
        }
        for (n, i) in floor.enumerated() {
            for j in floor[(n + 1)...] where furniture[i].footprint.grown(by: -0.01).overlaps(furniture[j].footprint.grown(by: -0.01)) {
                issues.append(LayoutIssue(kind: .overlap, message: "«\(furniture[i].name)» и «\(furniture[j].name)» стоят друг на друге", items: [i, j]))
            }
        }
        for i in furniture.indices where space.blocksDoor(furniture[i]) {
            issues.append(LayoutIssue(kind: .door, message: "«\(furniture[i].name)» мешает открыть дверь", items: [i]))
        }
        for i in floor {
            let item = furniture[i]
            guard let zone = space.frontZone(of: item) else { continue }
            let core = zone.grown(by: -0.01)
            let blockers = floor.filter { j in j != i && furniture[j] != item && !LayoutRules.isMovable(furniture[j]) && furniture[j].footprint.overlaps(core) }
            if !space.isInside(zone) || !blockers.isEmpty {
                issues.append(LayoutIssue(kind: .front, message: "Перед «\(item.name)» меньше \(format(LayoutRules.frontClearance(item))) м свободного места", items: [i] + blockers))
            }
        }
        let reach = space.reach(furniture)
        if reach.entranceBlocked {
            issues.append(LayoutIssue(kind: .passage, message: "От входа нет прохода шириной \(format(LayoutRules.passage)) м"))
        } else {
            for index in reach.unreachable {
                issues.append(LayoutIssue(kind: .passage, message: "К «\(furniture[index].name)» нет прохода шириной \(format(LayoutRules.passage)) м", items: [index]))
            }
        }
        for i in floor where space.blocksWindow(furniture[i]) {
            issues.append(LayoutIssue(kind: .window, message: "«\(furniture[i].name)» закрывает окно", items: [i]))
        }
        return issues
    }

    private static func format(_ value: Double) -> String { String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") }
}
