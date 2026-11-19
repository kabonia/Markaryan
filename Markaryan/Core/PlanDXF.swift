import Foundation

/// A plain ASCII DXF R12 (AC1009): the most widely read version — AutoCAD, nanoCAD, ArchiCAD, КОМПАС, LibreCAD.
/// Millimetres, y up (the plan's y is flipped), text in Windows‑1251 as the header says ($DWGCODEPAGE ANSI_1251).
struct DXFWriter {
    struct Layer {
        let name: String
        /// AutoCAD colour index.
        let color: Int
        var lineType = "CONTINUOUS"
    }

    let layers: [Layer]
    private var body: [String] = []
    private var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity

    init(layers: [Layer]) { self.layers = layers }

    /// Plan metres (y down) to DXF millimetres (y up).
    static func mm(_ p: PlanPoint) -> (x: Double, y: Double) { (p.x * 1000, -p.y * 1000) }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let clean = abs(rounded) < 0.05 ? 0 : rounded
        return clean == clean.rounded() ? String(Int(clean)) : String(format: "%.1f", clean)
    }

    /// Characters Windows‑1251 has no place for, written the way CAD shows them.
    static func clean(_ text: String) -> String {
        var result = text
        for (from, to) in [("×", "x"), ("\u{2011}", "-"), ("\u{2010}", "-"), ("²", "2"), ("³", "3"), ("…", "..."), ("\u{202F}", " "), ("\n", " ")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    private mutating func extend(_ x: Double, _ y: Double) {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    }

    private mutating func entity(_ type: String, layer: String, _ codes: [(Int, String)]) {
        body += ["0", type, "8", layer]
        for (code, value) in codes { body += [String(code), value] }
    }

    private mutating func point(_ p: PlanPoint, _ base: Int) -> [(Int, String)] {
        let q = DXFWriter.mm(p)
        extend(q.x, q.y)
        return [(base, DXFWriter.number(q.x)), (base + 10, DXFWriter.number(q.y)), (base + 20, "0")]
    }

    mutating func line(_ a: PlanPoint, _ b: PlanPoint, layer: String) {
        entity("LINE", layer: layer, point(a, 10) + point(b, 11))
    }

    mutating func polyline(_ points: [PlanPoint], closed: Bool, layer: String) {
        guard points.count >= 2 else { return }
        entity("POLYLINE", layer: layer, [(66, "1"), (10, "0"), (20, "0"), (30, "0"), (70, closed ? "1" : "0")])
        for p in points { entity("VERTEX", layer: layer, point(p, 10)) }
        entity("SEQEND", layer: layer, [])
    }

    /// A filled triangle or quadrangle (corners in order around it).
    mutating func solid(_ points: [PlanPoint], layer: String) {
        guard points.count == 3 || points.count == 4 else { return }
        // SOLID takes the third and fourth corners crosswise.
        let order = points.count == 4 ? [points[0], points[1], points[3], points[2]] : [points[0], points[1], points[2], points[2]]
        entity("SOLID", layer: layer, point(order[0], 10) + point(order[1], 11) + point(order[2], 12) + point(order[3], 13))
    }

    mutating func circle(_ center: PlanPoint, radius: Double, layer: String) {
        entity("CIRCLE", layer: layer, point(center, 10) + [(40, DXFWriter.number(radius * 1000))])
    }

    /// Arc counter-clockwise (in the DXF, y up) from `startDegrees` to `endDegrees`.
    mutating func arc(_ center: PlanPoint, radius: Double, startDegrees: Double, endDegrees: Double, layer: String) {
        entity("ARC", layer: layer, point(center, 10) + [(40, DXFWriter.number(radius * 1000)), (50, DXFWriter.number(startDegrees)), (51, DXFWriter.number(endDegrees))])
    }

    /// Text `height` metres tall; `centered` puts its middle at `at`.
    mutating func text(_ value: String, at: PlanPoint, height: Double, layer: String, rotationDegrees: Double = 0, centered: Bool = false) {
        let string = DXFWriter.clean(value)
        guard !string.isEmpty else { return }
        var codes = point(at, 10) + [(40, DXFWriter.number(height * 1000)), (1, string), (50, DXFWriter.number(rotationDegrees))]
        if centered { codes += [(72, "1"), (73, "2")] + point(at, 11) }
        entity("TEXT", layer: layer, codes)
    }

    var document: String {
        let hasExtents = minX <= maxX
        var lines: [String] = ["0", "SECTION", "2", "HEADER",
                               "9", "$ACADVER", "1", "AC1009",
                               "9", "$DWGCODEPAGE", "3", "ANSI_1251",
                               "9", "$INSBASE", "10", "0", "20", "0", "30", "0",
                               "9", "$EXTMIN", "10", DXFWriter.number(hasExtents ? minX : 0), "20", DXFWriter.number(hasExtents ? minY : 0), "30", "0",
                               "9", "$EXTMAX", "10", DXFWriter.number(hasExtents ? maxX : 1000), "20", DXFWriter.number(hasExtents ? maxY : 1000), "30", "0",
                               "9", "$LTSCALE", "40", "1",
                               "0", "ENDSEC",
                               "0", "SECTION", "2", "TABLES",
                               "0", "TABLE", "2", "LTYPE", "70", "2",
                               "0", "LTYPE", "2", "CONTINUOUS", "70", "0", "3", "Solid line", "72", "65", "73", "0", "40", "0",
                               "0", "LTYPE", "2", "DASHED", "70", "0", "3", "__ __ __", "72", "65", "73", "2", "40", "600", "49", "400", "49", "-200",
                               "0", "ENDTAB",
                               "0", "TABLE", "2", "LAYER", "70", String(layers.count)]
        for layer in layers {
            lines += ["0", "LAYER", "2", layer.name, "70", "0", "62", String(layer.color), "6", layer.lineType]
        }
        lines += ["0", "ENDTAB",
                  "0", "TABLE", "2", "STYLE", "70", "1",
                  "0", "STYLE", "2", "STANDARD", "70", "0", "40", "0", "41", "1", "50", "0", "71", "0", "42", "250", "3", "arial.ttf", "4", "",
                  "0", "ENDTAB",
                  "0", "ENDSEC",
                  "0", "SECTION", "2", "ENTITIES"]
        lines += body
        lines += ["0", "ENDSEC", "0", "EOF"]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The file: Windows‑1251, as declared in the header.
    var data: Data { document.data(using: .windowsCP1251, allowLossyConversion: true) ?? Data(document.utf8) }
}

/// The room for CAD: walls (outward, as on the drawings), doors, windows, the furniture of the concept, dimensions,
/// electrics and floor tiles — each on its own layer, 1:1 in millimetres.
enum PlanDXF {
    enum Layer {
        static let walls = "A-WALL", wallFill = "A-WALL-FILL", doors = "A-DOOR", windows = "A-GLAZ", furniture = "A-FURN"
        static let dimensions = "A-ANNO-DIMS", text = "A-ANNO-TEXT", sockets = "E-POWR", switches = "E-SWCH", lights = "E-LITE", tiles = "A-FLOR-TILE"
    }

    static let layers: [DXFWriter.Layer] = [
        DXFWriter.Layer(name: Layer.walls, color: 7), DXFWriter.Layer(name: Layer.wallFill, color: 8),
        DXFWriter.Layer(name: Layer.doors, color: 3), DXFWriter.Layer(name: Layer.windows, color: 4),
        DXFWriter.Layer(name: Layer.furniture, color: 6), DXFWriter.Layer(name: Layer.dimensions, color: 1),
        DXFWriter.Layer(name: Layer.text, color: 7), DXFWriter.Layer(name: Layer.sockets, color: 1),
        DXFWriter.Layer(name: Layer.switches, color: 5), DXFWriter.Layer(name: Layer.lights, color: 2, lineType: "DASHED"),
        DXFWriter.Layer(name: Layer.tiles, color: 8)
    ]

    static func writer(plan: FloorPlan, proposal original: DesignProposal?, room: RoomKind) -> DXFWriter {
        let proposal = original?.placed(in: plan)
        var dxf = DXFWriter(layers: layers)
        let body = WallBody(plan: plan)

        // Floor tiles under everything else.
        if TileLayout.isTiled(room, proposal?.floor) {
            let tiles = TileLayout.floor(plan, tile: TileSize.parse((proposal?.floor.material ?? "") + " " + (proposal?.floor.details ?? "")) ?? .floor)
            for piece in tiles.pieces { dxf.polyline(piece.polygon, closed: true, layer: Layer.tiles) }
        }

        addWalls(&dxf, [body])

        // Wall lengths inside the room, and the room label.
        for side in PlanWalls.numbered(plan) where side.length >= 0.4 {
            let a = side.point(0, offset: 0.35), b = side.point(side.length, offset: 0.35)
            dxf.line(a, b, layer: Layer.dimensions)
            for end in [a, b] { dxf.line(end + (side.direction + side.normal) * 0.05, end - (side.direction + side.normal) * 0.05, layer: Layer.dimensions) }
            let angle = atan2(-side.direction.y, side.direction.x) * 180 / .pi
            let upright = angle > 90.5 || angle < -89.5 ? angle + 180 : angle
            dxf.text("\(Int((side.length * 1000).rounded()))", at: side.point(side.length / 2, offset: 0.25), height: 0.1, layer: Layer.dimensions, rotationDegrees: upright, centered: true)
        }
        let b = plan.bounds
        let middle = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        dxf.text(plan.name, at: middle, height: 0.2, layer: Layer.text, centered: true)
        dxf.text(String(format: "%.2f м2", plan.area).replacingOccurrences(of: ".", with: ","), at: middle + PlanPoint(x: 0, y: 0.3), height: 0.15, layer: Layer.text, centered: true)

        // Furniture of the concept with names.
        for item in proposal?.furniture ?? [] where item.model != "hiddenlight" {
            dxf.polyline(item.footprint.corners, closed: true, layer: Layer.furniture)
            if item.width >= 0.4 && item.depth >= 0.3 {
                dxf.text(item.name, at: PlanPoint(x: item.x, y: item.y), height: 0.07, layer: Layer.furniture, centered: true)
            }
        }

        // Electrics: simple symbols with heights.
        let power = ElectricPlanner.plan(for: plan, proposal: proposal, room: room)
        for device in power.points {
            let p = device.position, f = device.facing, across = PlanPoint(x: -f.y, y: f.x)
            let r = 0.08
            switch device.kind {
            case .ceilingLight, .pendant:
                dxf.circle(p, radius: r, layer: Layer.lights)
                dxf.line(p + PlanPoint(x: -r, y: -r) * 0.7, p + PlanPoint(x: r, y: r) * 0.7, layer: Layer.lights)
                dxf.line(p + PlanPoint(x: -r, y: r) * 0.7, p + PlanPoint(x: r, y: -r) * 0.7, layer: Layer.lights)
            case .switchOne, .switchTwo:
                let center = p + f * (r * 0.9)
                dxf.circle(center, radius: r * 0.5, layer: Layer.switches)
                dxf.line(center + (f + across) * (r * 0.35), center + (f + across) * (r * 1.6), layer: Layer.switches)
            case .wallLight:
                dxf.circle(p + f * (r * 0.5), radius: r * 0.5, layer: Layer.lights)
            default:
                // Semicircle on the wall bulging into the room (DXF angles: y up), with the contact line.
                let facing = atan2(-f.y, f.x) * 180 / .pi
                dxf.arc(p, radius: r, startDegrees: facing - 90, endDegrees: facing + 90, layer: Layer.sockets)
                dxf.line(p - across * r, p + across * r, layer: Layer.sockets)
                dxf.line(p + f * r, p + f * (r * 1.9), layer: Layer.sockets)
            }
            if device.wall != nil {
                dxf.text("h=\(Int((device.height * 1000).rounded()))", at: p + f * 0.28, height: 0.06, layer: device.kind.isSwitch ? Layer.switches : (device.kind.isLight ? Layer.lights : Layer.sockets), centered: true)
            }
        }
        return dxf
    }

    /// Walls (faces, jambs, fill), windows and door swings of one room or of all rooms of an apartment: the middle of
    /// a partition is not drawn, and only the doors in `doors` get a swing (nil — every door).
    static func addWalls(_ dxf: inout DXFWriter, _ bodies: [WallBody], doors: Set<UUID>? = nil) {
        for piece in bodies.flatMap(\.pieces) {
            dxf.solid(piece.polygon, layer: Layer.wallFill)
            dxf.line(piece.innerStart, piece.innerEnd, layer: Layer.walls)
            if !piece.shared { dxf.line(piece.outerStart, piece.outerEnd, layer: Layer.walls) }
            if piece.capStart { dxf.line(piece.innerStart, piece.outerStart, layer: Layer.walls) }
            if piece.capEnd { dxf.line(piece.innerEnd, piece.outerEnd, layer: Layer.walls) }
        }
        for gap in bodies.flatMap(\.gaps) {
            let opening = gap.opening
            if opening.kind == .window {
                for k in [0.0, 0.4, 0.6, 1.0] {
                    let shift = gap.outward * (gap.thickness * k)
                    dxf.line(gap.innerStart + shift, gap.innerEnd + shift, layer: Layer.windows)
                }
            } else if opening.kind == .door, doors.map({ $0.contains(opening.id) }) ?? true {
                let hinge = gap.innerStart.distance(to: opening.start) <= gap.innerEnd.distance(to: opening.start) ? gap.innerStart : gap.innerEnd
                let latch = hinge == gap.innerStart ? gap.innerEnd : gap.innerStart
                let width = hinge.distance(to: latch)
                let leaf = hinge + gap.outward * -width
                dxf.line(hinge, leaf, layer: Layer.doors)
                // The swing in DXF space (y up): from the latch to the open leaf, counter-clockwise.
                let h = DXFWriter.mm(hinge), l = DXFWriter.mm(latch), e = DXFWriter.mm(leaf)
                let toLatch = atan2(l.y - h.y, l.x - h.x) * 180 / .pi, toLeaf = atan2(e.y - h.y, e.x - h.x) * 180 / .pi
                let counterClockwise = (l.x - h.x) * (e.y - h.y) - (l.y - h.y) * (e.x - h.x) > 0
                dxf.arc(hinge, radius: width, startDegrees: counterClockwise ? toLatch : toLeaf, endDegrees: counterClockwise ? toLeaf : toLatch, layer: Layer.doors)
            }
        }
    }

    /// The whole apartment: every room where the scan saw it, partitions once, doors once, the furniture of each
    /// room's latest concept, room numbers, names and areas, the overall size.
    static func writer(apartment: ApartmentLayout, name: String) -> DXFWriter {
        var dxf = DXFWriter(layers: layers)
        addWalls(&dxf, apartment.wallBodies(), doors: Set(apartment.doors.map(\.door.id)))
        for room in apartment.rooms {
            let label = room.labelPoint
            dxf.text("\(room.number). \(room.name)", at: label, height: 0.2, layer: Layer.text, centered: true)
            dxf.text(String(format: "%.2f м2", room.area).replacingOccurrences(of: ".", with: ","), at: label + PlanPoint(x: 0, y: 0.3), height: 0.15, layer: Layer.text, centered: true)
            for item in room.plan.proposals.last?.furniture ?? [] where item.model != "hiddenlight" {
                dxf.polyline(item.footprint.corners, closed: true, layer: Layer.furniture)
            }
        }
        // Overall size below and to the left of the plan.
        let w = apartment.width, d = apartment.depth
        dxf.line(PlanPoint(x: 0, y: d + 0.8), PlanPoint(x: w, y: d + 0.8), layer: Layer.dimensions)
        dxf.line(PlanPoint(x: -0.8, y: 0), PlanPoint(x: -0.8, y: d), layer: Layer.dimensions)
        dxf.text("\(Int((w * 1000).rounded()))", at: PlanPoint(x: w / 2, y: d + 0.65), height: 0.15, layer: Layer.dimensions, centered: true)
        dxf.text("\(Int((d * 1000).rounded()))", at: PlanPoint(x: -0.95, y: d / 2), height: 0.15, layer: Layer.dimensions, rotationDegrees: 90, centered: true)
        dxf.text("\(name): \(String(format: "%.2f", apartment.area).replacingOccurrences(of: ".", with: ",")) м2", at: PlanPoint(x: w / 2, y: d + 1.3), height: 0.2, layer: Layer.text, centered: true)
        return dxf
    }

    static func file(apartment: ApartmentLayout, name: String) throws -> URL {
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("АР-\(safe.isEmpty ? "квартира" : safe).dxf")
        try writer(apartment: apartment, name: name).data.write(to: url, options: .atomic)
        return url
    }

    /// The DXF file for the room, in the temporary folder, named like the drawings.
    static func file(plan: FloorPlan, proposal: DesignProposal?, room: RoomKind) throws -> URL {
        let safe = plan.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("АР-\(safe.isEmpty ? "помещение" : safe).dxf")
        try writer(plan: plan, proposal: proposal, room: room).data.write(to: url, options: .atomic)
        return url
    }
}
