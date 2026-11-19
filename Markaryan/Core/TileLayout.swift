import Foundation

/// Tile size in metres: `width` along x (along the wall on an elevation), `length` along y (up the wall).
struct TileSize: Equatable {
    let width: Double
    let length: Double

    static let floor = TileSize(width: 0.6, length: 0.6)
    static let wall = TileSize(width: 0.6, length: 0.3)

    var title: String { "\(Int((width * 1000).rounded()))×\(Int((length * 1000).rounded())) мм" }

    /// A size written in a finish: «керамогранит 600×1200», «плитка 30x60 см», «20×20».
    static func parse(_ text: String) -> TileSize? {
        let pattern = #"(\d{2,4})\s*[×xхXХ*]\s*(\d{2,4})\s*(мм|см|mm|cm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(match.range(at: 1), in: text).flatMap({ Double(text[$0]) }),
              let b = Range(match.range(at: 2), in: text).flatMap({ Double(text[$0]) }) else { return nil }
        let unit = Range(match.range(at: 3), in: text).map { text[$0].lowercased() }
        // Without a unit: three or four digits are millimetres (600×600), two are centimetres (30×60).
        let divisor = unit == "мм" || unit == "mm" ? 1000.0 : (unit == "см" || unit == "cm" ? 100.0 : (max(a, b) >= 100 ? 1000.0 : 100.0))
        let size = TileSize(width: a / divisor, length: b / divisor)
        return size.width >= 0.05 && size.length >= 0.05 && size.width <= 3.2 && size.length <= 3.2 ? size : nil
    }
}

/// Tiles laid in a straight grid over a surface: where the grid starts so that no cut is a sliver, which tiles stay
/// whole and which are cut, and how many to buy with the reserve.
struct TileLayout {
    struct Piece {
        /// The part of the tile that is laid (plan or elevation coordinates).
        let polygon: [PlanPoint]
        let whole: Bool
        /// The narrowest side of a cut piece, metres.
        let narrowest: Double
    }

    let tile: TileSize
    let joint: Double
    /// A tile corner every `tile + joint` from here.
    let origin: PlanPoint
    let pieces: [Piece]
    /// Area the tiles cover, m².
    let area: Double
    /// 10 % for a straight layout: cuts and breakage.
    let reserve = 0.1

    var whole: Int { pieces.filter(\.whole).count }
    var cut: Int { pieces.count - whole }
    var narrowestCut: Double? { pieces.filter { !$0.whole }.map(\.narrowest).min() }
    var toBuy: Int { Int((Double(pieces.count) * (1 + reserve)).rounded(.up)) }
    var buyArea: Double { Double(toBuy) * tile.width * tile.length }

    /// Is this floor tiled: tile, porcelain, stone or concrete in the finish, a bathroom without a finish.
    static func isTiled(_ room: RoomKind, _ finish: DesignFinish?) -> Bool {
        let text = ((finish?.material ?? "") + " " + (finish?.details ?? "")).lowercased()
        if ["плитк", "керамогранит", "керамич", "кафел", "камень", "мрамор", "микроцемент", "бетон"].contains(where: { text.contains($0) }) { return true }
        if ["доск", "паркет", "ламинат", "винил", "spc", "краск", "штукатур", "обои"].contains(where: { text.contains($0) }) { return false }
        return room == .bathroom
    }

    // MARK: Floor

    /// The floor of the room; the grid starts where the cuts at the walls come out widest.
    static func floor(_ plan: FloorPlan, tile: TileSize = .floor, joint: Double = 0.002) -> TileLayout {
        var outline = plan.outline
        if PlanMath.signedArea2(outline) < 0 { outline.reverse() }
        let count = outline.count
        var xs: [(position: Double, roomAfter: Bool)] = [], ys: [(position: Double, roomAfter: Bool)] = []
        for i in 0..<count {
            let a = outline[i], b = outline[(i + 1) % count]
            let length = a.distance(to: b)
            guard length > 0.05 else { continue }
            let inward = PlanPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
            if abs(b.x - a.x) < 0.01 * length { xs.append(((a.x + b.x) / 2, inward.x > 0)) }
            if abs(b.y - a.y) < 0.01 * length { ys.append(((a.y + b.y) / 2, inward.y > 0)) }
        }
        let b = plan.bounds
        let ox = bestOffset(xs, size: tile.width, joint: joint, center: (b.minX + b.maxX) / 2)
        let oy = bestOffset(ys, size: tile.length, joint: joint, center: (b.minY + b.maxY) / 2)
        let mx = tile.width + joint, my = tile.length + joint
        var pieces: [Piece] = []
        var column = Int(((b.minX - ox) / mx).rounded(.down))
        while ox + Double(column) * mx < b.maxX {
            var row = Int(((b.minY - oy) / my).rounded(.down))
            while oy + Double(row) * my < b.maxY {
                let x0 = ox + Double(column) * mx, y0 = oy + Double(row) * my
                let cell = [PlanPoint(x: x0, y: y0), PlanPoint(x: x0 + tile.width, y: y0), PlanPoint(x: x0 + tile.width, y: y0 + tile.length), PlanPoint(x: x0, y: y0 + tile.length)]
                let laid = clip(outline, to: (x0, y0, x0 + tile.width, y0 + tile.length))
                let area = abs(PlanMath.signedArea2(laid)) / 2
                if area > 1e-6 {
                    let whole = area >= tile.width * tile.length - 1e-6
                    pieces.append(Piece(polygon: whole ? cell : laid, whole: whole, narrowest: whole ? min(tile.width, tile.length) : narrowestSide(laid)))
                }
                row += 1
            }
            column += 1
        }
        return TileLayout(tile: tile, joint: joint, origin: PlanPoint(x: ox, y: oy), pieces: pieces, area: plan.area)
    }

    // MARK: A wall

    /// One wall from the floor up to `height`: rows start from the floor with whole tiles (the cut row is under the
    /// ceiling), columns where the cuts at the corners and the openings come out widest. `holes` — doors and windows
    /// as (from, bottom, to, top) in metres along the wall and up from the floor.
    static func wall(length: Double, height: Double, holes: [(Double, Double, Double, Double)], tile: TileSize = .wall, joint: Double = 0.002) -> TileLayout {
        var xs: [(position: Double, roomAfter: Bool)] = [(0, true), (length, false)]
        for hole in holes { xs.append((hole.0, false)); xs.append((hole.2, true)) }
        let ox = bestOffset(xs, size: tile.width, joint: joint, center: length / 2)
        let mx = tile.width + joint, my = tile.length + joint
        var pieces: [Piece] = []
        var area = length * height
        for hole in holes { area -= max(0, min(hole.2, length) - max(hole.0, 0)) * max(0, min(hole.3, height) - max(hole.1, 0)) }
        var column = Int(((0 - ox) / mx).rounded(.down))
        while ox + Double(column) * mx < length {
            var row = 0
            while Double(row) * my < height {
                let x0 = ox + Double(column) * mx, y0 = Double(row) * my
                let x1 = x0 + tile.width, y1 = y0 + tile.length
                let cx0 = max(0, x0), cx1 = min(length, x1), cy0 = y0, cy1 = min(height, y1)
                var laid = max(0, cx1 - cx0) * max(0, cy1 - cy0)
                var narrowest = min(cx1 - cx0, cy1 - cy0)
                for hole in holes {
                    let hx0 = max(cx0, hole.0), hx1 = min(cx1, hole.2), hy0 = max(cy0, hole.1), hy1 = min(cy1, hole.3)
                    guard hx1 > hx0, hy1 > hy0 else { continue }
                    laid -= (hx1 - hx0) * (hy1 - hy0)
                    for strip in [hx0 - cx0, cx1 - hx1, hy0 - cy0, cy1 - hy1] where strip > 1e-6 { narrowest = min(narrowest, strip) }
                }
                if laid > 1e-6 {
                    let whole = laid >= tile.width * tile.length - 1e-6
                    let polygon = [PlanPoint(x: cx0, y: cy0), PlanPoint(x: cx1, y: cy0), PlanPoint(x: cx1, y: cy1), PlanPoint(x: cx0, y: cy1)]
                    pieces.append(Piece(polygon: polygon, whole: whole, narrowest: whole ? min(tile.width, tile.length) : narrowest))
                }
                row += 1
            }
            column += 1
        }
        return TileLayout(tile: tile, joint: joint, origin: PlanPoint(x: ox, y: 0), pieces: pieces, area: max(0, area))
    }

    /// Every numbered wall of the room (`PlanWalls` order) from the floor to the ceiling, doors and windows left out.
    static func walls(_ plan: FloorPlan, tile: TileSize = .wall, joint: Double = 0.002) -> [TileLayout] {
        let height = plan.ceilingHeight
        return PlanWalls.numbered(plan).map { side in
            var holes: [(Double, Double, Double, Double)] = []
            for door in side.doors { holes.append((door.from, 0, door.to, min(height, door.segment.height > 1.5 ? door.segment.height : 2.1))) }
            for window in side.windows {
                let sill = min(max(0, window.segment.elevation ?? 0.85), height - 0.3)
                holes.append((window.from, sill, window.to, min(height, sill + max(0.3, window.segment.height))))
            }
            return wall(length: side.length, height: height, holes: holes, tile: tile, joint: joint)
        }
    }

    // MARK: Geometry

    /// Grid start (a tile corner) for the given walls: no cut narrower than a third of a tile if that can be helped,
    /// then as few cut rows as possible, then the widest narrowest cut; among equal starts, the one closest to a tile
    /// centred in the room.
    static func bestOffset(_ walls: [(position: Double, roomAfter: Bool)], size: Double, joint: Double, center: Double) -> Double {
        let module = size + joint
        let centered = positiveRemainder(center - size / 2, module)
        guard !walls.isEmpty else { return centered }
        func evaluate(_ offset: Double) -> (enough: Double, cuts: Int, smallest: Double) {
            var smallest = size, cuts = 0
            for wall in walls {
                let r = positiveRemainder(wall.position - offset, module)
                // The piece inside the room next to this wall.
                let piece = wall.roomAfter ? positiveRemainder(module - r, module) - joint : r
                if piece <= 0.0005 || piece >= size - 0.0005 { continue }   // the wall falls on a joint: no cut
                cuts += 1
                smallest = min(smallest, piece)
            }
            return (min(smallest, size / 3), cuts, smallest)
        }
        func better(_ a: (enough: Double, cuts: Int, smallest: Double), than b: (enough: Double, cuts: Int, smallest: Double)) -> Bool? {
            if abs(a.enough - b.enough) > 0.005 { return a.enough > b.enough }
            if a.cuts != b.cuts { return a.cuts < b.cuts }
            if abs(a.smallest - b.smallest) > 0.005 { return a.smallest > b.smallest }
            return nil
        }
        func distance(_ offset: Double) -> Double { min(abs(offset - centered), module - abs(offset - centered)) }
        // Every 5 mm, and exactly at each wall (a whole tile starting or ending at it).
        var candidates = stride(from: 0.0, to: module, by: 0.005).map { $0 }
        for wall in walls { candidates.append(positiveRemainder(wall.roomAfter ? wall.position : wall.position - size, module)) }
        var best = (offset: centered, value: evaluate(centered))
        for offset in candidates {
            let value = evaluate(offset)
            if better(value, than: best.value) ?? (distance(offset) < distance(best.offset)) { best = (offset, value) }
        }
        return best.offset
    }

    static func positiveRemainder(_ value: Double, _ module: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: module)
        return r < 0 ? r + module : r
    }

    /// The part of `polygon` inside the box (Sutherland–Hodgman against a convex window: right for any room shape).
    static func clip(_ polygon: [PlanPoint], to box: (Double, Double, Double, Double)) -> [PlanPoint] {
        var result = polygon
        let edges: [(PlanPoint) -> Double] = [{ $0.x - box.0 }, { box.2 - $0.x }, { $0.y - box.1 }, { box.3 - $0.y }]
        for inside in edges {
            guard !result.isEmpty else { break }
            let input = result
            result = []
            for i in input.indices {
                let current = input[i], previous = input[(i + input.count - 1) % input.count]
                let a = inside(previous), c = inside(current)
                if c >= 0 {
                    if a < 0 { result.append(previous + (current - previous) * (a / (a - c))) }
                    result.append(current)
                } else if a >= 0 {
                    result.append(previous + (current - previous) * (a / (a - c)))
                }
            }
        }
        return result
    }

    /// The narrowest extent of a cut piece across its own bounding box.
    static func narrowestSide(_ polygon: [PlanPoint]) -> Double {
        guard let minX = polygon.map(\.x).min(), let maxX = polygon.map(\.x).max(),
              let minY = polygon.map(\.y).min(), let maxY = polygon.map(\.y).max() else { return 0 }
        return min(maxX - minX, maxY - minY)
    }
}
