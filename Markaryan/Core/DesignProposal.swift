import Foundation

// MARK: - AI design concept: zones, furniture, finishes

/// Decodes an array element by element, skipping broken items (e.g. the last one of a cut-off AI answer).
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Number that may come as 1.2, "1.2" or "1,2" (AI answers are not always typed strictly).
func flexibleDouble<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
    if let text = try? container.decode(String.self, forKey: key) {
        return Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: CharacterSet(charactersIn: " мm")))
    }
    return nil
}

struct DesignZone: Codable, Hashable {
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var depth: Double
}

extension DesignZone {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let x = flexibleDouble(c, .x), let y = flexibleDouble(c, .y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "zone without position")
        }
        self.init(name: (try? c.decode(String.self, forKey: .name)) ?? "Зона", x: x, y: y,
                  width: max(0.2, flexibleDouble(c, .width) ?? 1), depth: max(0.2, flexibleDouble(c, .depth) ?? 1))
    }
}

struct DesignFurniture: Codable, Hashable {
    var name: String
    var kind: String
    var x: Double
    var y: Double
    var width: Double
    var depth: Double
    /// Degrees, clockwise.
    var rotation: Double
    /// Metres, when known (the layout engine keeps tall items away from windows).
    var height: Double? = nil
    /// Number of the wall the item stands against (`PlanWalls` numbering), when it does.
    var wall: Int? = nil
    /// Zone of the room the item belongs to («Кухня», «Гостиная»…), when the concept has zones.
    var zone: String? = nil
}

extension DesignFurniture {
    /// Lenient: a missing rotation or kind must not drop the item (an empty plan was the result before).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let x = flexibleDouble(c, .x), let y = flexibleDouble(c, .y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "item without position")
        }
        let name = (try? c.decode(String.self, forKey: .name)) ?? "Предмет"
        self.init(name: name, kind: (try? c.decode(String.self, forKey: .kind))?.lowercased() ?? "decor", x: x, y: y,
                  width: max(0.03, flexibleDouble(c, .width) ?? 0.6), depth: max(0.03, flexibleDouble(c, .depth) ?? 0.6),
                  rotation: flexibleDouble(c, .rotation) ?? 0)
        height = flexibleDouble(c, .height).flatMap { $0 > 0 ? $0 : nil }
        wall = try? c.decode(Int.self, forKey: .wall)
        zone = (try? c.decode(String.self, forKey: .zone)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Exact model to draw (toilet, sink, shower…) — the AI often gives a generic kind.
    var model: String { FixtureModel.resolve(kind: kind, name: name) }
    /// Mounted on a wall or the ceiling: does not block the floor.
    var isMounted: Bool { ["mirror", "towel", "boiler", "sconce", "pendant", "hiddenlight", "accessory"].contains(model) }
    /// Hangs from the ceiling or is built into it.
    var isCeiling: Bool { ["pendant", "hiddenlight"].contains(model) }
    /// Lies on the floor (rugs, play mats): furniture may stand on it. The 3D model draws every decor item this way.
    var isFlat: Bool {
        let n = name.lowercased()
        return model == "decor" || n.contains("ковёр") || n.contains("ковер") || n.contains("коврик")
    }
    /// Takes floor space that people and other furniture cannot use.
    var blocksFloor: Bool { !isMounted && !isFlat }
    /// Footprint as a turned rectangle.
    var footprint: PlanRect { PlanRect(center: PlanPoint(x: x, y: y), width: width, depth: depth, rotation: rotation * .pi / 180) }
    /// The side people use (local +y), as a unit vector.
    var front: PlanPoint { footprint.axisY }
    /// Height in metres: given by the AI, or the same typical heights the 3D model uses.
    var estimatedHeight: Double {
        if let height { return height }
        let n = name.lowercased()
        switch model {
        case "storage":
            if n.contains("тумб") || n.contains("комод") || n.contains("обувниц") { return 0.85 }
            if n.contains("полк") { return 0.4 }
            return n.contains("пенал") ? 1.85 : 2.2
        case "kitchen": return 2.2 // wall cabinets above the counter
        case "appliance": return n.contains("холод") || n.contains("колонн") || n.contains("духов") ? 2.0 : 0.85
        case "shower": return 2.0
        case "tv": return 1.1
        case "bed": return 1.0
        case "sofa": return 0.85
        case "table", "desk": return 0.75
        case "chair": return 0.9
        case "toilet": return 0.82
        case "sink": return 0.9
        case "bathtub": return 0.56
        case "washer": return 0.85
        case "plant": return 1.1
        case "floorlamp": return 1.7
        default: return isFlat ? 0.02 : 0.5
        }
    }
    /// Corners of the footprint in plan coordinates.
    var corners: [PlanPoint] {
        let angle = rotation * .pi / 180, c = cos(angle), s = sin(angle)
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
            let lx = sx * width / 2, ly = sy * depth / 2
            return PlanPoint(x: x + lx * c - ly * s, y: y + lx * s + ly * c)
        }
    }
    /// Whether a point is inside the footprint enlarged by `margin`.
    func covers(_ point: PlanPoint, margin: Double) -> Bool {
        let angle = rotation * .pi / 180, c = cos(angle), s = sin(angle)
        let dx = point.x - x, dy = point.y - y
        let lx = dx * c + dy * s, ly = -dx * s + dy * c
        return abs(lx) <= width / 2 + margin && abs(ly) <= depth / 2 + margin
    }
}

/// Recognises the real object behind an AI item by its name.
enum FixtureModel {
    static func resolve(kind: String, name: String) -> String {
        let n = name.lowercased()
        let words = Set(n.split { !$0.isLetter }.map(String.init))
        func has(_ parts: String...) -> Bool { parts.contains { n.contains($0) } }
        let direct = ["toilet", "sink", "shower", "bathtub", "washer", "mirror", "towel"]
        if direct.contains(kind) { return kind }
        if kind == "kitchen" { return "kitchen" } // «Кухня с мойкой и раковиной» is still a kitchen unit
        if has("зеркал", "mirror") { return "mirror" }
        if has("полотенцесуш", "towel") { return "towel" }
        if has("бойлер", "водонагрев", "boiler") { return "boiler" }
        if has("стиральн", "сушильн", "washing", "washer") { return "washer" }
        if has("унитаз", "инсталляц", "биде", "toilet") || words.contains("wc") { return "toilet" }
        if has("раковин", "умывальн", "washbasin", "vanity") { return "sink" }
        if has("гигиенич") { return "accessory" }
        if has("душ", "shower", "трап") && !has("подушк") { return "shower" }
        if has("ванна", "bathtub") && !has("шкаф", "пенал", "полк", "тумб", "ванной") { return "bathtub" }
        if kind == "light" || has("светильн", "люстр", "торшер", "лампа", "подсветк") || words.contains("бра") {
            if has("лента", "led", "подсветк", "трек", "спот", "точечн", "встраив", "профил", "настольн") { return "hiddenlight" }
            if has("подвес", "люстр", "pendant") { return "pendant" }
            if has("торшер", "напольн") { return "floorlamp" }
            return words.contains("бра") || has("настен", "над зеркал") ? "sconce" : "pendant"
        }
        if kind == "bath" { return "bathtub" }
        return kind
    }
}

/// A finished client presentation: the PDF and its pictures in Application Support/MarkaryanPresentations/<folder>.
struct SavedPresentation: Codable, Hashable {
    struct Picture: Codable, Hashable {
        var title: String
        var file: String
    }
    var createdAt = Date()
    var folder: String
    var pdf: String
    var pictures: [Picture]
    /// Picture engine that made the photoreal views (nil — only the exact 3D model).
    var engine: String?
}

struct DesignMaterial: Codable, Hashable {
    var name: String
    var `where`: String
    var amount: String
}

/// Finish of one surface (floor, walls or ceiling).
struct DesignFinish: Codable, Hashable {
    var material: String = ""
    var color: String = ""
    var details: String = ""
    var english: String = ""
    var isEmpty: Bool { material.isEmpty && details.isEmpty }
    private enum CodingKeys: String, CodingKey { case material, color, details, english }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        material = (try? c.decode(String.self, forKey: .material)) ?? ""
        color = (try? c.decode(String.self, forKey: .color)) ?? ""
        details = (try? c.decode(String.self, forKey: .details)) ?? ""
        english = (try? c.decode(String.self, forKey: .english)) ?? ""
    }
}

/// AI design concept for one plan (returned by Claude as strict JSON).
struct DesignProposal: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title: String
    var style: String
    var summary: String
    var roomPurpose: String
    var zones: [DesignZone]
    var furniture: [DesignFurniture]
    var palette: [String]
    var materials: [DesignMaterial]
    var lighting: String
    var tips: [String]
    var budgetMin: Double
    var budgetMax: Double
    var renderPrompt: String
    var renderPromptEnglish: String
    var floor: DesignFinish
    var walls: DesignFinish
    var ceiling: DesignFinish
    /// Room type fixed once when the concept is placed (`RoomKind` raw value). Nil in concepts saved before 1.3.
    var roomKind: String? = nil
    /// How the furniture got its coordinates: nil — raw AI answer, not checked yet;
    /// 1 — AI coordinates fitted into the room (`fitted(to:)`); 2 — placed by the layout engine.
    var layoutVersion: Int? = nil
    /// What the layout engine could not do as asked (item made smaller, did not fit…), for the client.
    var layoutNotes: [String] = []
    /// The client presentation made for this concept (files on the iPhone), so it opens again without new renders.
    var presentation: SavedPresentation? = nil

    /// One English sentence about all surfaces — added to every image prompt so they come out precise.
    var finishesEnglish: String {
        var parts: [String] = []
        if !floor.english.isEmpty { parts.append("Floor: \(floor.english)") }
        if !walls.english.isEmpty { parts.append("Walls: \(walls.english)") }
        if !ceiling.english.isEmpty { parts.append("Ceiling: \(ceiling.english)") }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: ". ") + ". Floor, walls and ceiling finishes clearly visible and precisely executed: straight even lines, clean corners and junctions, neat skirting boards and ceiling cornices, flush built-in lighting."
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, title, style, summary, roomPurpose, zones, furniture, palette, materials, lighting, tips, budgetMin, budgetMax, renderPrompt, renderPromptEnglish, floor, walls, ceiling, roomKind, layoutVersion, layoutNotes, presentation
    }

    init(from decoder: Decoder) throws {
        // Lenient decoding: the AI may omit optional parts; the plan still renders.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        title = (try? c.decode(String.self, forKey: .title)) ?? "Концепция"
        style = (try? c.decode(String.self, forKey: .style)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        roomPurpose = (try? c.decode(String.self, forKey: .roomPurpose)) ?? ""
        zones = (try? c.decode([Lossy<DesignZone>].self, forKey: .zones))?.compactMap(\.value) ?? []
        furniture = (try? c.decode([Lossy<DesignFurniture>].self, forKey: .furniture))?.compactMap(\.value) ?? []
        palette = (try? c.decode([String].self, forKey: .palette)) ?? []
        materials = (try? c.decode([Lossy<DesignMaterial>].self, forKey: .materials))?.compactMap(\.value) ?? []
        lighting = (try? c.decode(String.self, forKey: .lighting)) ?? ""
        tips = (try? c.decode([String].self, forKey: .tips)) ?? []
        budgetMin = (try? c.decode(Double.self, forKey: .budgetMin)) ?? 0
        budgetMax = (try? c.decode(Double.self, forKey: .budgetMax)) ?? 0
        renderPrompt = (try? c.decode(String.self, forKey: .renderPrompt)) ?? ""
        renderPromptEnglish = (try? c.decode(String.self, forKey: .renderPromptEnglish)) ?? ""
        floor = (try? c.decode(DesignFinish.self, forKey: .floor)) ?? DesignFinish()
        walls = (try? c.decode(DesignFinish.self, forKey: .walls)) ?? DesignFinish()
        ceiling = (try? c.decode(DesignFinish.self, forKey: .ceiling)) ?? DesignFinish()
        roomKind = (try? c.decode(String.self, forKey: .roomKind)).flatMap { RoomKind(rawValue: $0)?.rawValue }
        layoutVersion = try? c.decode(Int.self, forKey: .layoutVersion)
        layoutNotes = (try? c.decode([String].self, forKey: .layoutNotes)) ?? []
        presentation = try? c.decode(SavedPresentation.self, forKey: .presentation)
    }
}

// MARK: - Fitting the AI layout into the scanned room

extension DesignProposal {
    /// The concept ready to show: an old or fresh AI layout is fitted into the room once and gets its room type;
    /// a concept that is already placed comes back unchanged (cheap enough to call on every render).
    func placed(in plan: FloorPlan) -> DesignProposal {
        guard layoutVersion == nil else { return self }
        var copy = fitted(to: plan)
        copy.layoutVersion = 1
        if copy.roomKind == nil { copy.roomKind = RoomKind.detect(plan: plan, proposal: copy).rawValue }
        return copy
    }

    /// Guarantees that every item is inside the real room: fixes centimetre/millimetre answers,
    /// limits sizes and moves items that cross a wall back inside the floor outline.
    func fitted(to plan: FloorPlan) -> DesignProposal {
        var copy = self
        let b = plan.bounds
        let roomW = max(0.5, b.maxX - b.minX), roomD = max(0.5, b.maxY - b.minY)
        let maxSide = max(roomW, roomD)
        let biggest = (furniture.flatMap { [$0.x, $0.y] } + zones.flatMap { [$0.x, $0.y] }).map(abs).max() ?? 0
        let factor: Double = biggest > maxSide * 200 ? 1000 : (biggest > maxSide * 8 ? 100 : 1)
        let center = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        // Half of the drawn wall thickness: items stand against the inner face of the wall, not inside it.
        let inset = 0.075

        /// Which axes the item still has to move along to get off the walls.
        func needs(_ item: DesignFurniture) -> (x: Bool, y: Bool) {
            var needX = false, needY = false
            for corner in item.corners {
                let inside = plan.contains(corner)
                let outX = PlanPoint(x: corner.x + (corner.x >= item.x ? inset : -inset), y: corner.y)
                let outY = PlanPoint(x: corner.x, y: corner.y + (corner.y >= item.y ? inset : -inset))
                if !inside || !plan.contains(outX) { needX = true }
                if !inside || !plan.contains(outY) { needY = true }
            }
            return (needX, needY)
        }
        func fits(_ item: DesignFurniture) -> Bool { let n = needs(item); return !n.x && !n.y }

        // What does not belong in this type of room is removed (no sofa in a bathroom, no toilet in a bedroom).
        let room = RoomKind.detect(plan: plan, proposal: self)
        copy.furniture = furniture.compactMap { (original: DesignFurniture) -> DesignFurniture? in
            var item = original
            // A «раковина» in a kitchen or a kitchen‑living room is the kitchen sink unit.
            if item.model == "sink" && (room == .kitchen || room == .living) { item.kind = "kitchen" }
            guard room.allows(item.model) else { return nil }
            if factor > 1 { item.x /= factor; item.y /= factor; item.width /= factor; item.depth /= factor }
            guard item.x.isFinite, item.y.isFinite else { return nil }
            item.width = min(max(0.03, item.width), maxSide - 0.1)
            item.depth = min(max(0.03, item.depth), maxSide - 0.1)
            if item.model == "hiddenlight" { return item }
            // Far outside: jump towards the centre first, then push off the walls centimetre by centimetre, axis by axis.
            var jumps = 0
            while !plan.contains(PlanPoint(x: item.x, y: item.y)) && jumps < 60 {
                item.x += (center.x - item.x) * 0.12
                item.y += (center.y - item.y) * 0.12
                jumps += 1
            }
            var step = 0
            while step < 300 {
                let need = needs(item)
                if !need.x && !need.y { break }
                if need.x { item.x += center.x > item.x ? 0.01 : -0.01 }
                if need.y { item.y += center.y > item.y ? 0.01 : -0.01 }
                step += 1
            }
            if !fits(item) { item.x = center.x; item.y = center.y }
            return item
        }
        copy.zones = zones.map { (original: DesignZone) -> DesignZone in
            var zone = original
            if factor > 1 { zone.x /= factor; zone.y /= factor; zone.width /= factor; zone.depth /= factor }
            zone.width = min(zone.width, roomW); zone.depth = min(zone.depth, roomD)
            zone.x = min(max(zone.x, b.minX + zone.width / 2), b.maxX - zone.width / 2)
            zone.y = min(max(zone.y, b.minY + zone.depth / 2), b.maxY - zone.depth / 2)
            return zone
        }
        return copy
    }
}
