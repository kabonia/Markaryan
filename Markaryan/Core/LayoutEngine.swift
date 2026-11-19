import Foundation

/// Places furniture by the rules: against walls, into corners, next to / in front of / around other items,
/// keeping door swings, passages of 0.7 m and the space in front of fixtures free.
/// The AI (or the built-in designer) only says what to place and roughly where (`DesignBrief`).
enum LayoutEngine {
    struct Result {
        var furniture: [DesignFurniture] = []
        var zones: [DesignZone] = []
        /// What could not be done as asked, in words for the client.
        var notes: [String] = []
    }

    static func arrange(_ brief: DesignBrief, in plan: FloorPlan, room: RoomKind) -> Result {
        var arranger = Arranger(plan: plan, room: room, items: brief.items)
        return arranger.run()
    }
}

private struct Arranger {
    struct Piece {
        var item: DesignBrief.Item
        /// Index of the item in the brief.
        let source: Int
        /// Index of the piece this one relates to.
        var target: Int?
        var placed: DesignFurniture?
        var model: String { FixtureModel.resolve(kind: item.kind, name: item.name) }
    }
    struct Candidate {
        var furniture: DesignFurniture
        var score: Double
    }

    let plan: FloorPlan
    let room: RoomKind
    let space: LayoutSpace
    let span: Double
    var pieces: [Piece] = []
    var notes: [String] = []
    /// Placed pieces in placement order.
    var order: [Int] = []

    // What the rules need about the placed items, kept up to date on every placement.
    var placed: [DesignFurniture] = []
    /// Floor items, shrunk by 5 mm (they may touch, not overlap).
    var solidCores: [PlanRect] = []
    /// Floor items people cannot move by hand.
    var fixed: [PlanRect] = []
    /// Free space those items need in front of them, shrunk by 1 cm.
    var frontZones: [PlanRect] = []
    /// Floor items 1 m high or more: nothing hangs on the wall behind them.
    var tall: [PlanRect] = []
    /// Mirrors, towel warmers and other things on the walls.
    var wallItems: [PlanRect] = []
    var lights: [PlanPoint] = []
    var zoneCentres: [String: PlanPoint] = [:]
    var wet: PlanPoint?
    /// Cells where a 0.7 m wide person fits with the items placed so far.
    var walkable: [Bool]
    var baseline: LayoutSpace.Reach
    let windowPoints: [PlanPoint]

    init(plan: FloorPlan, room: RoomKind, items: [DesignBrief.Item]) {
        self.plan = plan
        self.room = room
        let space = LayoutSpace(plan: plan)
        self.space = space
        walkable = space.emptyRoomMap
        baseline = space.reach([], walkable: space.emptyRoomMap)
        windowPoints = space.walls.flatMap { wall in wall.windows.map { wall.point($0.middle) } }
        let scanned = plan.objects.filter { ["Унитаз", "Раковина", "Ванна", "Стиральная машина"].contains($0.name) }.map(\.center)
        if !scanned.isEmpty { wet = PlanPoint(x: scanned.map(\.x).reduce(0, +) / Double(scanned.count), y: scanned.map(\.y).reduce(0, +) / Double(scanned.count)) }
        let b = plan.bounds
        span = max(1, hypot(b.maxX - b.minX, b.maxY - b.minY))
        let longestWall = max(1, space.walls.map(\.length).max() ?? max(b.maxX - b.minX, b.maxY - b.minY))

        var firstPiece: [Int: Int] = [:]
        for (index, raw) in items.enumerated() {
            var item = raw
            // Centimetres or millimetres instead of metres; sizes no room can hold.
            for path in [\DesignBrief.Item.width, \DesignBrief.Item.depth] {
                var value = item[keyPath: path]
                if !value.isFinite || value <= 0 { value = 0.6 }
                if value > 300 { value /= 1000 } else if value > 12 { value /= 100 }
                item[keyPath: path] = min(max(0.03, value), longestWall)
            }
            if let height = item.height, height > 12 { item.height = height > 300 ? height / 1000 : height / 100 }
            if FixtureModel.resolve(kind: item.kind, name: item.name) == "sink" && (room == .kitchen || room == .living) { item.kind = "kitchen" }
            guard room.allows(FixtureModel.resolve(kind: item.kind, name: item.name)) else {
                notes.append("Убрано: «\(item.name)» — не для помещения «\(room.purposeTitle.lowercased())»")
                continue
            }
            firstPiece[index] = pieces.count
            for _ in 0..<max(1, item.count) {
                var one = item
                one.count = 1
                pieces.append(Piece(item: one, source: index))
            }
        }
        for i in pieces.indices {
            let wanted = pieces[i].item.target
            guard pieces[i].item.relation != .none, wanted >= 1, let target = firstPiece[wanted - 1], pieces[target].source != pieces[i].source else {
                pieces[i].item.relation = .none
                continue
            }
            pieces[i].target = target
        }
        // A chain that comes back to itself has no start: cut it.
        for i in pieces.indices {
            var seen: Set<Int> = [i]
            var next = pieces[i].target
            while let n = next {
                if seen.contains(n) { pieces[i].target = nil; pieces[i].item.relation = .none; break }
                seen.insert(n)
                next = pieces[n].target
            }
        }
    }

    // MARK: Order

    private func group(_ piece: Piece) -> Int {
        switch piece.item.placement {
        case .wall, .corner: return isFlat(piece) ? 2 : 0
        case .free: return isFlat(piece) ? 2 : 1
        case .mounted: return 3
        case .ceiling: return 4
        }
    }

    private func priority(_ piece: Piece) -> Int {
        switch piece.model {
        case "kitchen": return 10
        case "bed", "bathtub", "shower": return 9
        case "sofa", "toilet": return 8
        case "sink": return 7
        case "appliance", "washer": return 6
        case "storage": return piece.item.width * piece.item.depth > 0.4 ? 6 : 3
        case "desk", "table": return 5
        case "tv": return 4
        case "chair": return 2
        case "plant": return 1
        default: return 0
        }
    }

    private func isFlat(_ piece: Piece) -> Bool { probe(piece.item).isFlat }

    mutating func run() -> LayoutEngine.Result {
        let roots = pieces.indices.filter { pieces[$0].target == nil }.sorted { a, b in
            let pa = pieces[a], pb = pieces[b]
            let ka = (group(pa) >= 3 ? 1 : 0, pa.item.optional ? 1 : 0, group(pa), -priority(pa), -pa.item.width * pa.item.depth, a)
            let kb = (group(pb) >= 3 ? 1 : 0, pb.item.optional ? 1 : 0, group(pb), -priority(pb), -pb.item.width * pb.item.depth, b)
            return ka < kb
        }
        var children: [Int: [Int]] = [:]
        for i in pieces.indices { if let t = pieces[i].target { children[t, default: []].append(i) } }
        for root in roots { placeTree(root, children: children) }

        var result = LayoutEngine.Result()
        result.furniture = pieces.compactMap(\.placed)
        result.zones = zones()
        result.notes = notes
        // Anything the rules still did not catch is shown, never hidden.
        for issue in LayoutCheck.issues(space: space, furniture: result.furniture) where issue.kind != .window {
            if !result.notes.contains(issue.message) { result.notes.append(issue.message) }
        }
        return result
    }

    private mutating func placeTree(_ index: Int, children: [Int: [Int]]) {
        place(index)
        for child in children[index] ?? [] {
            if pieces[index].placed == nil {
                // Without its anchor a companion (chair, nightstand, mirror above a sink) has no meaning.
                if pieces[child].item.optional || ["chair"].contains(pieces[child].model) || [.around, .front, .under].contains(pieces[child].item.relation) {
                    notes.append("Не поставлено: «\(pieces[child].item.name)» — нет места для «\(pieces[index].item.name)»")
                    continue
                }
                pieces[child].target = nil
                pieces[child].item.relation = .none
            }
            placeTree(child, children: children)
        }
    }

    // MARK: Placing one piece

    private mutating func commit(_ f: DesignFurniture, _ index: Int) {
        pieces[index].placed = f
        order.append(index)
        placed.append(f)
        if f.isCeiling {
            lights.append(PlanPoint(x: f.x, y: f.y))
        } else if f.isMounted {
            wallItems.append(f.footprint.grown(by: -0.005))
        } else if f.blocksFloor {
            solidCores.append(f.footprint.grown(by: -0.005))
            if !LayoutRules.isMovable(f) {
                fixed.append(f.footprint)
                space.block(&walkable, with: f.footprint)
            }
            if let zone = space.frontZone(of: f) { frontZones.append(zone.grown(by: -0.01)) }
            if f.estimatedHeight >= 1.0 { tall.append(f.footprint) }
            if wet == nil && ["toilet", "sink", "shower", "bathtub", "washer", "kitchen"].contains(f.model) { wet = PlanPoint(x: f.x, y: f.y) }
        }
        var groups: [String: [PlanPoint]] = [:]
        for item in placed where item.blocksFloor { if let zone = item.zone { groups[zone, default: []].append(PlanPoint(x: item.x, y: item.y)) } }
        zoneCentres = groups.mapValues { points in PlanPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count)) }
        baseline = space.reach(placed, walkable: walkable)
    }

    private mutating func place(_ index: Int) {
        let original = pieces[index].item
        for width in widths(for: pieces[index]) {
            for relaxed in [false, true] {
                var item = original
                item.width = width
                if let found = search(index, item: item, relaxed: relaxed) {
                    commit(found, index)
                    if width < original.width - 0.005 {
                        notes.append("«\(original.name)» уменьшен до \(metres(width)) м по ширине, чтобы поместиться")
                    }
                    if space.blocksWindow(found) { notes.append("«\(original.name)» частично закрывает окно — другого места нет") }
                    return
                }
            }
        }
        // A related item that does not fit by its anchor may still stand somewhere else.
        if pieces[index].target != nil && !["chair"].contains(pieces[index].model) {
            var item = original
            item.relation = .none
            if item.placement == .free && !probe(item).isFlat { item.placement = .wall }
            for relaxed in [false, true] {
                if let found = search(index, item: item, relaxed: relaxed, ignoringTarget: true) {
                    commit(found, index)
                    return
                }
            }
        }
        notes.append(original.optional ? "Не поместилось (необязательно): «\(original.name)»" : "Не поместилось: «\(original.name)» — уменьшите размер или уберите другой предмет")
    }

    /// The asked width first, then narrower versions down to a sensible minimum.
    private func widths(for piece: Piece) -> [Double] {
        let w = piece.item.width
        let minimum: Double
        switch piece.model {
        case "bed": minimum = 0.9
        case "sofa": minimum = 1.4
        case "kitchen": minimum = 1.2
        case "storage": minimum = w >= 1 ? 0.8 : w
        case "table", "desk": minimum = 0.7
        case "sink": minimum = 0.4
        case "bathtub": minimum = 1.5
        case "tv": minimum = 1.0
        default: minimum = w
        }
        var result = [w]
        for factor in [0.85, 0.72, 0.6] where w * factor >= minimum - 0.001 { result.append((w * factor * 100).rounded() / 100) }
        return result
    }

    /// Best candidate that keeps every rule; solid items must also keep everything reachable through 0.7 m passages.
    private func search(_ index: Int, item: DesignBrief.Item, relaxed: Bool, ignoringTarget: Bool = false) -> DesignFurniture? {
        let target = ignoringTarget ? nil : pieces[index].target.flatMap { pieces[$0].placed }
        let ring = item.relation == .none && item.placement == .free
        let candidates = generate(item, target: target, relaxed: relaxed).sorted { $0.score > $1.score }
        let known = Set(baseline.unreachable)
        var rejected: [PlanPoint] = []
        var tries = 0
        for candidate in candidates {
            let f = candidate.furniture
            guard isValid(f, relaxed: relaxed, ring: ring) else { continue }
            guard f.blocksFloor, !LayoutRules.isMovable(f), !baseline.entranceBlocked else { return f }
            let center = PlanPoint(x: f.x, y: f.y)
            if rejected.contains(where: { $0.distance(to: center) < 0.12 }) { continue }
            tries += 1
            if tries > 40 { return nil }
            var map = walkable
            space.block(&map, with: f.footprint)
            let reach = space.reach(placed + [f], walkable: map)
            if !reach.entranceBlocked && Set(reach.unreachable).isSubset(of: known) { return f }
            rejected.append(center)
        }
        return nil
    }

    // MARK: Rules

    /// `ring`: a free-standing table also keeps room for chairs and people around it.
    private func isValid(_ f: DesignFurniture, relaxed: Bool, ring: Bool) -> Bool {
        if f.isCeiling { return PlanMath.contains(space.outline, PlanPoint(x: f.x, y: f.y)) }
        guard space.isInside(f.footprint) else { return false }
        if f.isFlat { return true }
        let core = f.footprint.grown(by: -0.005)
        guard !space.blocksDoor(f) else { return false }
        if f.isMounted {
            // Nothing tall in front of it, and not on top of another wall item.
            return !tall.contains { $0.overlaps(core) } && !wallItems.contains { $0.overlaps(core) }
        }
        if solidCores.contains(where: { $0.overlaps(core) }) { return false }
        if !LayoutRules.isMovable(f) && frontZones.contains(where: { $0.overlaps(core) }) { return false }
        if let zone = space.frontZone(of: f) {
            guard space.isInside(zone) else { return false }
            let zoneCore = zone.grown(by: -0.01)
            if fixed.contains(where: { $0.overlaps(zoneCore) }) { return false }
        }
        if f.estimatedHeight >= 1.0 && wallItems.contains(where: { $0.overlaps(core) }) { return false }
        if ring && f.model == "table" && !relaxed {
            let around = f.footprint.grown(by: 0.45)
            guard space.isInside(around) else { return false }
            let aroundCore = around.grown(by: -0.01)
            if fixed.contains(where: { $0.overlaps(aroundCore) }) { return false }
        }
        if !relaxed && space.blocksWindow(f) { return false }
        return true
    }

    // MARK: Candidates

    private func probe(_ item: DesignBrief.Item) -> DesignFurniture {
        DesignFurniture(name: item.name, kind: item.kind, x: 0, y: 0, width: item.width, depth: item.depth, rotation: 0, height: item.height)
    }

    private func make(_ item: DesignBrief.Item, _ center: PlanPoint, _ rotation: Double, wall: Int? = nil) -> DesignFurniture {
        var degrees = rotation.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 } else if degrees <= -180 { degrees += 360 }
        if abs(degrees) < 1e-9 { degrees = 0 }
        return DesignFurniture(name: item.name, kind: item.kind, x: center.x, y: center.y, width: item.width, depth: item.depth, rotation: degrees,
                               height: item.height, wall: wall, zone: item.zone.isEmpty ? nil : item.zone)
    }

    private func generate(_ item: DesignBrief.Item, target: DesignFurniture?, relaxed: Bool) -> [Candidate] {
        guard let target, item.relation != .none else { return standalone(item, relaxed: relaxed) }
        switch item.relation {
        case .nextTo: return nextTo(item, target)
        case .front: return front(item, target)
        case .around: return around(item, target)
        case .opposite: return opposite(item, target)
        case .above: return above(item, target)
        case .under: return under(item, target)
        case .none: return standalone(item, relaxed: relaxed)
        }
    }

    private func standalone(_ item: DesignBrief.Item, relaxed: Bool) -> [Candidate] {
        switch item.placement {
        case .wall, .mounted: return alongWalls(item, cornersOnly: false)
        case .corner: return alongWalls(item, cornersOnly: !relaxed)
        case .free: return probe(item).isFlat || !relaxed ? freeStanding(item) : freeStanding(item) + alongWalls(item, cornersOnly: false).map { Candidate(furniture: $0.furniture, score: $0.score - 3) }
        case .ceiling: return ceiling(item)
        }
    }

    private func alongWalls(_ item: DesignBrief.Item, cornersOnly: Bool) -> [Candidate] {
        var result: [Candidate] = []
        let w = item.width, d = item.depth
        for wall in space.walls where wall.length >= w + 0.04 {
            var positions = Array(stride(from: w / 2 + 0.02, through: wall.length - w / 2 - 0.02, by: 0.05))
            positions.append(wall.length - w / 2 - 0.02)
            for t in positions {
                let endGap = min(t - w / 2, wall.length - t - w / 2)
                if cornersOnly && endGap > 0.35 { continue }
                let f = make(item, wall.point(t, offset: LayoutRules.wallGap + d / 2), wall.itemRotation, wall: wall.number)
                var score = preference(item, f)
                if item.wall > 0 && wall.number == item.wall { score += 8 }
                if item.placement == .corner { score -= endGap * 4 } else if endGap > 0.03 && endGap < 0.3 { score -= 1.5 }
                score += wall.length * 0.05
                if space.blocksWindow(f) { score -= 6 }
                if f.model == "tv" && !wall.windows.isEmpty { score -= 2 } // glare on the screen
                result.append(Candidate(furniture: f, score: score))
            }
        }
        return result
    }

    private func freeStanding(_ item: DesignBrief.Item) -> [Candidate] {
        let b = plan.bounds
        let step = span > 9 ? 0.2 : 0.15
        // Directions of the walls (a turned room keeps its furniture parallel to its walls).
        var angles: [Double] = []
        for wall in space.walls {
            for turn in [0.0, 90, 180, 270] {
                let a = ((wall.itemRotation + turn).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                if !angles.contains(where: { abs($0 - a) < 2 || abs(abs($0 - a) - 360) < 2 }) { angles.append(a) }
            }
            if angles.count >= 8 { break }
        }
        if angles.isEmpty { angles = [0, 90, 180, 270] }
        let entrance = space.entrances.first
        var result: [Candidate] = []
        var x = b.minX + 0.2
        while x <= b.maxX - 0.2 {
            var y = b.minY + 0.2
            while y <= b.maxY - 0.2 {
                for angle in angles {
                    let f = make(item, PlanPoint(x: x, y: y), angle)
                    var score = preference(item, f)
                    // Keep the way in free.
                    if let entrance, entrance.distance(to: PlanPoint(x: x, y: y)) < 1.3 { score -= 2 }
                    result.append(Candidate(furniture: f, score: score))
                }
                y += step
            }
            x += step
        }
        return result
    }

    private func ceiling(_ item: DesignBrief.Item) -> [Candidate] {
        let b = plan.bounds
        let anchor = zoneCentre(item.zone) ?? PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        var result: [Candidate] = []
        for dx in stride(from: -1.5, through: 1.5, by: 0.25) {
            for dy in stride(from: -1.5, through: 1.5, by: 0.25) {
                let p = anchor + PlanPoint(x: dx, y: dy)
                var score = -p.distance(to: anchor) * 2
                if let nearest = lights.map({ $0.distance(to: p) }).min() { score += min(nearest, 1.5) * 3 }
                result.append(Candidate(furniture: make(item, p, 0), score: score))
            }
        }
        return result
    }

    private func nextTo(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        var result: [Candidate] = []
        if target.wall != nil {
            for candidate in alongWalls(item, cornersOnly: false) {
                let gap = distance(candidate.furniture.footprint, target.footprint)
                guard gap <= 0.6 else { continue }
                var score = candidate.score - gap * 6
                if candidate.furniture.wall == target.wall { score += 1 }
                result.append(Candidate(furniture: candidate.furniture, score: score))
            }
        }
        // Beside the target in its own frame, backs in line (also for free-standing targets).
        let rect = target.footprint
        for side in [-1.0, 1.0] {
            for extra in [0.02, 0.1, 0.2] {
                let center = rect.center + rect.axisX * (side * (target.width / 2 + item.width / 2 + extra)) + rect.axisY * ((item.depth - target.depth) / 2)
                let f = make(item, center, target.rotation, wall: target.wall)
                result.append(Candidate(furniture: f, score: preference(item, f) - extra * 6))
            }
        }
        return result
    }

    private func front(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        let model = FixtureModel.resolve(kind: item.kind, name: item.name)
        let gap = model == "table" ? 0.4 : 0.05 // coffee table before a sofa; chair, bench or rug right in front
        let rotation = model == "chair" ? target.rotation + 180 : target.rotation
        let rect = target.footprint
        var result: [Candidate] = []
        for lateral in [0, -0.1, 0.1, -0.2, 0.2, -0.35, 0.35, -0.5, 0.5] {
            for extra in [0, 0.1, 0.2, 0.35] {
                let center = rect.center + rect.axisY * (target.depth / 2 + gap + extra + item.depth / 2) + rect.axisX * lateral
                result.append(Candidate(furniture: make(item, center, rotation), score: -abs(lateral) * 2 - extra * 3))
            }
        }
        return result
    }

    private func around(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        let rect = target.footprint
        let offset = item.depth / 2 + 0.02
        var slots: [(PlanPoint, Double)] = []
        let perSide = max(1, Int((target.width / 0.6).rounded(.down)))
        for k in 0..<perSide {
            let x = (Double(k) - Double(perSide - 1) / 2) * (target.width / Double(perSide))
            slots.append((rect.center + rect.axisY * (target.depth / 2 + offset) + rect.axisX * x, target.rotation + 180))
            slots.append((rect.center - rect.axisY * (target.depth / 2 + offset) + rect.axisX * x, target.rotation))
        }
        if target.depth >= 0.55 {
            slots.append((rect.center + rect.axisX * (target.width / 2 + offset), target.rotation + 90))
            slots.append((rect.center - rect.axisX * (target.width / 2 + offset), target.rotation - 90))
        }
        return slots.enumerated().map { index, slot in Candidate(furniture: make(item, slot.0, slot.1), score: -Double(index)) }
    }

    private func opposite(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        let origin = PlanPoint(x: target.x, y: target.y), direction = target.front
        var hit: (wall: WallSide, along: Double, distance: Double)?
        for wall in space.walls where wall.normal.dot(direction) < -0.5 {
            let denominator = direction.cross(wall.direction)
            guard abs(denominator) > 1e-9 else { continue }
            let s = (wall.start - origin).cross(wall.direction) / denominator
            let u = (wall.start - origin).cross(direction) / denominator
            guard s > 0.5, u >= -0.2, u <= wall.length + 0.2 else { continue }
            if hit == nil || s < hit!.distance { hit = (wall, u, s) }
        }
        var result: [Candidate] = []
        let w = item.width, d = item.depth
        if let hit, hit.wall.length >= w + 0.04 {
            for t in stride(from: max(w / 2 + 0.02, hit.along - 1.2), through: min(hit.wall.length - w / 2 - 0.02, hit.along + 1.2), by: 0.05) {
                let f = make(item, hit.wall.point(t, offset: LayoutRules.wallGap + d / 2), hit.wall.itemRotation, wall: hit.wall.number)
                result.append(Candidate(furniture: f, score: -abs(t - hit.along) * 3 - (hit.wall.windows.isEmpty ? 0 : 2)))
            }
        }
        // The opposite wall is taken (a kitchen in a studio): stand free, facing the target, like a partition.
        let edge = origin + direction * (target.depth / 2)
        for distance in stride(from: 1.8, through: 3.4, by: 0.2) {
            for lateral in [0, -0.3, 0.3] {
                let center = edge + direction * (distance + d / 2) + target.footprint.axisX * lateral
                result.append(Candidate(furniture: make(item, center, target.rotation + 180), score: -4 - abs(distance - 2.4) - abs(lateral) * 2))
            }
        }
        return result
    }

    private func above(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        let rect = target.footprint
        if item.placement == .ceiling || probe(item).isCeiling {
            return [0, -0.2, 0.2].map { Candidate(furniture: make(item, rect.center + rect.axisX * $0, target.rotation), score: -abs($0)) }
        }
        // On the wall behind the target, flush with its back.
        return [0, -0.1, 0.1, -0.2, 0.2, -0.35, 0.35].map { lateral in
            let center = rect.center - rect.axisY * (target.depth / 2 - item.depth / 2) + rect.axisX * lateral
            return Candidate(furniture: make(item, center, target.rotation, wall: target.wall), score: -abs(lateral) * 2)
        }
    }

    private func under(_ item: DesignBrief.Item, _ target: DesignFurniture) -> [Candidate] {
        let rect = target.footprint
        return [0, 0.2, 0.4].map { shift in
            Candidate(furniture: make(item, rect.center + rect.axisY * shift, target.rotation), score: -shift)
        }
    }

    // MARK: Preferences

    /// What the brief prefers (window, door, far from the door, near water) plus keeping zones together.
    private func preference(_ item: DesignBrief.Item, _ f: DesignFurniture) -> Double {
        let center = PlanPoint(x: f.x, y: f.y)
        var preference = item.prefer
        var weight = 6.0
        if preference == .none {
            weight = 3
            switch f.model {
            case "bed", "shower", "bathtub": preference = .farFromDoor
            case "toilet", "sink", "washer": preference = .water
            case "desk": preference = .window
            default: break
            }
        }
        var score = 0.0
        switch preference {
        case .window:
            if let nearest = windowPoints.map({ $0.distance(to: center) }).min() { score -= nearest / span * weight }
        case .door:
            if let entrance = space.entrances.first { score -= entrance.distance(to: center) / span * weight }
        case .farFromDoor:
            if let entrance = space.entrances.first { score += entrance.distance(to: center) / span * weight }
        case .water:
            if let wet { score -= wet.distance(to: center) / span * weight }
        case .none:
            break
        }
        if !item.zone.isEmpty {
            if let own = zoneCentre(item.zone) { score -= own.distance(to: center) / span * 4 }
            for (name, centre) in zoneCentres where name != item.zone { score += min(centre.distance(to: center), 3) / span }
        }
        return score
    }

    private func zoneCentre(_ zone: String) -> PlanPoint? { zone.isEmpty ? nil : zoneCentres[zone] }

    /// Zones drawn on the plan: the area around the items of each zone (only when the room has two or more).
    private func zones() -> [DesignZone] {
        let names = Array(Set(pieces.compactMap { $0.placed?.zone })).sorted()
        guard names.count >= 2 else { return [] }
        let b = plan.bounds
        return names.compactMap { name in
            let corners = pieces.compactMap(\.placed).filter { $0.zone == name && $0.blocksFloor }.flatMap { $0.footprint.corners }
            guard let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(), let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max() else { return nil }
            let x0 = max(b.minX, minX - 0.15), x1 = min(b.maxX, maxX + 0.15), y0 = max(b.minY, minY - 0.15), y1 = min(b.maxY, maxY + 0.15)
            return DesignZone(name: name, x: (x0 + x1) / 2, y: (y0 + y1) / 2, width: x1 - x0, depth: y1 - y0)
        }
    }

    private func distance(_ a: PlanRect, _ b: PlanRect) -> Double {
        if a.overlaps(b) { return 0 }
        return min(a.corners.map { b.distance(to: $0) }.min()!, b.corners.map { a.distance(to: $0) }.min()!)
    }

    private func metres(_ value: Double) -> String { String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") }
}
