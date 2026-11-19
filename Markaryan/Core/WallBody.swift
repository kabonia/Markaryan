import Foundation

/// The walls as they are drawn and built: the scanned line is the inner face of the wall (where the finish is), the
/// wall goes outward by `thickness`, corners are mitred into one closed contour, doors and windows are gaps with
/// jambs, and sides of the room without a scanned wall (an open kitchen, a passage) stay open. The drawings, the DXF,
/// the plan on screen and the 3D model all use it, so they agree with each other and with the room's real size.
struct WallBody {
    /// Drawn thickness of a wall when the real one is unknown (the scan sees only the inner face).
    static let standardThickness = 0.15

    struct Piece {
        /// Inner start, inner end, outer end, outer start.
        let polygon: [PlanPoint]
        /// Jamb lines at the ends: at an opening or a free end; none where the piece turns the corner into the next wall.
        let capStart: Bool
        let capEnd: Bool
        /// Unit vector out of the room.
        let outward: PlanPoint
        /// A partition with the next room: this room draws its half, the outer face is the middle of the partition
        /// and is not drawn as a line.
        var shared = false

        var innerStart: PlanPoint { polygon[0] }
        var innerEnd: PlanPoint { polygon[1] }
        var outerEnd: PlanPoint { polygon[2] }
        var outerStart: PlanPoint { polygon[3] }
    }

    /// A door, an opening or a window in the wall: where it is on the inner face and on the outer face.
    struct Gap {
        let opening: PlanSegment
        let innerStart: PlanPoint
        let innerEnd: PlanPoint
        let outward: PlanPoint
        let thickness: Double
        var outerStart: PlanPoint { innerStart + outward * thickness }
        var outerEnd: PlanPoint { innerEnd + outward * thickness }
        var polygon: [PlanPoint] { [innerStart, innerEnd, outerEnd, outerStart] }
    }

    let thickness: Double
    let pieces: [Piece]
    let gaps: [Gap]
    /// The room outline the walls follow, clockwise on screen.
    let outline: [PlanPoint]

    /// `cut`: kinds of openings that leave a gap in the wall (the 3D model keeps the wall over a door, for example).
    /// `neighbours`: outlines of the other rooms of the apartment in the same coordinates; a wall facing one of them
    /// closer than 45 cm is a partition: each room fills half of the real gap instead of a wall of standard thickness.
    init(plan: FloorPlan, thickness: Double = WallBody.standardThickness, cut: Set<PlanSegment.Kind> = [.door, .opening, .window], neighbours: [[PlanPoint]] = []) {
        self.thickness = thickness
        var outline = WallBody.outline(of: plan)
        if PlanMath.signedArea2(outline) < 0 { outline.reverse() }
        self.outline = outline
        let count = outline.count
        guard count >= 3 else { pieces = []; gaps = []; return }

        struct Edge { let a: PlanPoint; let d: PlanPoint; let length: Double; let out: PlanPoint }
        let edges: [Edge] = (0..<count).map { i in
            let a = outline[i], b = outline[(i + 1) % count]
            let length = max(1e-9, a.distance(to: b))
            let d = (b - a) * (1 / length)
            return Edge(a: a, d: d, length: length, out: PlanPoint(x: d.y, y: -d.x))
        }
        // Partitions: the gap to a neighbouring room's wall along the outward side, sampled along the edge.
        let partitions: [Double?] = edges.map { edge in
            guard !neighbours.isEmpty else { return nil }
            var found: [Double] = []
            for fraction in [0.2, 0.5, 0.8] {
                let p = edge.a + edge.d * (edge.length * fraction)
                var nearest: Double?
                for other in neighbours where other.count >= 3 {
                    for j in other.indices {
                        let c = other[j], e = other[(j + 1) % other.count]
                        let side = e - c
                        guard side.length > 0.05, abs(edge.d.cross(side * (1 / side.length))) < 0.1 else { continue }
                        let denominator = edge.out.cross(side)
                        guard abs(denominator) > 1e-9 else { continue }
                        let distance = (c - p).cross(side) / denominator, along = (c - p).cross(edge.out) / denominator
                        if along >= -0.01, along <= 1.01, distance > -0.1, distance < 0.45, nearest.map({ distance < $0 }) ?? true { nearest = distance }
                    }
                }
                if let nearest { found.append(nearest) }
            }
            guard found.count >= 2 else { return nil }
            return found.sorted()[found.count / 2]
        }
        let thicknesses: [Double] = partitions.map { gap in gap.map { max(0.01, $0 / 2) } ?? thickness }
        /// Part of the edge a segment lies on (both ends close to the edge line and parallel to it), in metres along it.
        func span(_ segment: PlanSegment, on edge: Edge, tolerance: Double = 0.25) -> (Double, Double)? {
            guard segment.length > 0.02 else { return nil }
            let direction = (segment.end - segment.start) * (1 / segment.length)
            guard abs(direction.cross(edge.d)) < 0.1 else { return nil }
            let s = segment.start - edge.a, f = segment.end - edge.a
            guard abs(s.dot(edge.out)) < tolerance, abs(f.dot(edge.out)) < tolerance else { return nil }
            let low = max(0, min(s.dot(edge.d), f.dot(edge.d))), high = min(edge.length, max(s.dot(edge.d), f.dot(edge.d)))
            return high - low > 0.02 ? (low, high) : nil
        }

        // Where the edges have walls: a scanned wall along the edge; small gaps and short ends are closed.
        let walls = plan.walls
        var covered: [[(Double, Double)]] = edges.map { edge in
            guard !walls.isEmpty else { return [(0, edge.length)] }
            let parts = walls.compactMap { span($0, on: edge) }.sorted { $0.0 < $1.0 }
            var merged: [(Double, Double)] = []
            for part in parts {
                if let last = merged.last, part.0 <= last.1 + 0.1 { merged[merged.count - 1].1 = max(last.1, part.1) } else { merged.append(part) }
            }
            return merged.map { (low, high) in (low < 0.1 ? 0 : low, edge.length - high < 0.1 ? edge.length : high) }
        }

        // Openings: each on the edge it lies on.
        var gaps: [Gap] = []
        var holes: [[(Double, Double)]] = Array(repeating: [], count: count)
        for opening in plan.segments where opening.kind != .wall {
            let candidates = edges.indices.compactMap { index in span(opening, on: edges[index]).map { (index, $0) } }
            let mid = (opening.start + opening.end) * 0.5
            guard let (index, part) = candidates.min(by: { abs((mid - edges[$0.0].a).dot(edges[$0.0].out)) < abs((mid - edges[$1.0].a).dot(edges[$1.0].out)) }) else { continue }
            let edge = edges[index]
            gaps.append(Gap(opening: opening, innerStart: edge.a + edge.d * part.0, innerEnd: edge.a + edge.d * part.1, outward: edge.out, thickness: thicknesses[index]))
            if cut.contains(opening.kind) { holes[index].append(part) }
        }
        self.gaps = gaps
        for index in covered.indices {
            for hole in holes[index] {
                covered[index] = covered[index].flatMap { part -> [(Double, Double)] in
                    guard hole.1 > part.0, hole.0 < part.1 else { return [part] }
                    return [(part.0, hole.0), (hole.1, part.1)].filter { $0.1 - $0.0 > 0.01 }
                }
            }
        }

        /// Outer corner where two neighbouring walls meet; nil for a straight joint or a corner so sharp the mitre runs away.
        func mitre(_ firstIndex: Int, _ secondIndex: Int) -> PlanPoint? {
            let first = edges[firstIndex], second = edges[secondIndex]
            let denominator = first.d.cross(second.d)
            guard abs(denominator) > 1e-6 else { return nil }
            let p = first.a + first.out * thicknesses[firstIndex], q = second.a + second.out * thicknesses[secondIndex]
            let point = p + first.d * ((q - p).cross(second.d) / denominator)
            let corner = second.a
            return point.distance(to: corner) <= max(thicknesses[firstIndex], thicknesses[secondIndex]) * 4 ? point : nil
        }

        var pieces: [Piece] = []
        for (index, edge) in edges.enumerated() {
            let previous = (index + count - 1) % count, next = (index + 1) % count
            let own = thicknesses[index]
            for part in covered[index] {
                let inner0 = edge.a + edge.d * part.0, inner1 = edge.a + edge.d * part.1
                var outer0 = inner0 + edge.out * own, outer1 = inner1 + edge.out * own
                var capStart = true, capEnd = true
                if part.0 <= 1e-9, let last = covered[previous].last, last.1 >= edges[previous].length - 1e-9 {
                    capStart = false
                    if let point = mitre(previous, index) { outer0 = point }
                }
                if part.1 >= edge.length - 1e-9, let first = covered[next].first, first.0 <= 1e-9 {
                    capEnd = false
                    if let point = mitre(index, next) { outer1 = point }
                }
                // A wall shorter than the mitres turns inside out: square ends instead.
                if (outer1 - outer0).dot(inner1 - inner0) <= 0 {
                    outer0 = inner0 + edge.out * own; outer1 = inner1 + edge.out * own
                    capStart = true; capEnd = true
                }
                pieces.append(Piece(polygon: [inner0, inner1, outer1, outer0], capStart: capStart, capEnd: capEnd, outward: edge.out, shared: partitions[index] != nil))
            }
        }
        self.pieces = pieces
    }

    /// The outline the walls follow: the scanned floor, or — without one — the loop of the numbered walls.
    static func outline(of plan: FloorPlan) -> [PlanPoint] {
        if plan.floorPolygon.count >= 3 { return plan.floorPolygon }
        let sides = PlanWalls.numbered(plan)
        guard sides.count >= 3 else { return plan.outline }
        var loop: [PlanPoint] = []
        for (index, side) in sides.enumerated() {
            let previous = sides[(index + sides.count - 1) % sides.count]
            let denominator = previous.direction.cross(side.direction)
            if abs(denominator) < 1e-6 {
                loop.append((previous.end + side.start) * 0.5)
            } else {
                loop.append(previous.start + previous.direction * ((side.start - previous.start).cross(side.direction) / denominator))
            }
        }
        return PlanMath.isSimple(loop) ? loop : plan.outline
    }
}
