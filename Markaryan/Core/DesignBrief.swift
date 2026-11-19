import Foundation

/// What the AI (or the built-in designer) decides about a room: which items, of what real size, against which wall,
/// in a corner or next to what — never coordinates. `LayoutEngine` turns it into exact positions by the rules.
struct DesignBrief {
    enum Placement: String, CaseIterable {
        /// Back against a wall.
        case wall
        /// Into a corner (shower, wardrobe, corner kitchen).
        case corner
        /// Free-standing (dining table, island, armchair, rug).
        case free
        /// Hung on a wall above the floor (mirror, towel warmer, wall TV, sconce, boiler).
        case mounted
        /// Hangs from the ceiling (pendant, chandelier).
        case ceiling
    }
    enum Relation: String, CaseIterable {
        case none
        /// Beside the target, on the same wall or round the corner (nightstand, washer, fridge).
        case nextTo
        /// In front of the target (coffee table before a sofa, chair at a desk).
        case front
        /// Around the target (chairs around a table).
        case around
        /// On the opposite wall, facing the target (TV opposite a sofa).
        case opposite
        /// Above the target (mirror above a sink, pendant above a table).
        case above
        /// Under the target (rug under a table or a bed).
        case under
    }
    enum Preference: String, CaseIterable {
        case none, window, door, farFromDoor, water
    }

    struct Item {
        var name: String
        var kind: String
        /// Metres along the wall it stands against (or the long side).
        var width: Double
        var depth: Double
        var height: Double? = nil
        var count = 1
        var placement: Placement = .wall
        /// Preferred wall number (`PlanWalls`), 0 — any.
        var wall = 0
        var relation: Relation = .none
        /// Number of the related item in the list, from 1; 0 — none.
        var target = 0
        var prefer: Preference = .none
        var optional = false
        var zone = ""
    }

    var items: [Item]
}

extension DesignBrief: Decodable {
    private enum CodingKeys: String, CodingKey { case items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([Lossy<Item>].self, forKey: .items))?.compactMap(\.value) ?? []
    }
}

extension DesignBrief.Item: Decodable {
    private enum CodingKeys: String, CodingKey { case name, kind, width, depth, height, count, placement, wall, relation, target, prefer, optional, zone }

    /// Lenient like the rest of the AI answers: unknown words fall back to defaults, numbers may come as text.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = try? c.decode(String.self, forKey: .name), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "item without a name")
        }
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        kind = ((try? c.decode(String.self, forKey: .kind)) ?? "decor").lowercased()
        let typical = DesignBrief.typicalSize(kind: kind, name: self.name)
        func positive(_ key: CodingKeys) -> Double? { flexibleDouble(c, key).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        func whole(_ key: CodingKeys) -> Int? { positive(key).map { Int(min($0, 1000).rounded()) } }
        width = positive(.width) ?? typical.width
        depth = positive(.depth) ?? typical.depth
        height = positive(.height)
        count = min(12, max(1, whole(.count) ?? 1))
        placement = (try? c.decode(String.self, forKey: .placement)).flatMap { DesignBrief.Placement(rawValue: $0) } ?? .wall
        wall = whole(.wall) ?? 0
        relation = (try? c.decode(String.self, forKey: .relation)).flatMap { DesignBrief.Relation(rawValue: $0) } ?? .none
        target = whole(.target) ?? 0
        prefer = (try? c.decode(String.self, forKey: .prefer)).flatMap { DesignBrief.Preference(rawValue: $0) } ?? .none
        optional = (try? c.decode(Bool.self, forKey: .optional)) ?? false
        zone = ((try? c.decode(String.self, forKey: .zone)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension DesignBrief {
    /// Size used when the AI forgot one (metres, width × depth).
    static func typicalSize(kind: String, name: String) -> (width: Double, depth: Double) {
        switch FixtureModel.resolve(kind: kind, name: name) {
        case "sofa": return (2.2, 0.95)
        case "bed": return (1.6, 2.05)
        case "table": return (1.2, 0.8)
        case "desk": return (1.2, 0.6)
        case "chair": return (0.45, 0.5)
        case "storage": return (1.2, 0.6)
        case "kitchen": return (2.4, 0.6)
        case "appliance": return (0.6, 0.65)
        case "toilet": return (0.4, 0.55)
        case "sink": return (0.6, 0.47)
        case "shower": return (0.9, 0.9)
        case "bathtub": return (1.7, 0.75)
        case "washer": return (0.6, 0.6)
        case "mirror": return (0.6, 0.03)
        case "towel": return (0.5, 0.1)
        case "tv": return (1.6, 0.45)
        case "plant": return (0.4, 0.4)
        default: return (0.6, 0.6)
        }
    }
}

/// Builds the finished concept from an AI answer: texts and finishes as the AI wrote them, layout by `LayoutEngine`.
enum DesignComposer {
    static func room(plan: FloorPlan, purpose: String) -> RoomKind {
        RoomKind.keyword(purpose) ?? RoomKind.fromScan(plan) ?? .living
    }

    /// `data` is the JSON answer. A new-style answer has `items` (no coordinates) and is laid out by the engine;
    /// an old-style answer with `furniture` coordinates is fitted into the room as before.
    static func proposal(from data: Data, plan: FloorPlan, purpose: String) throws -> DesignProposal {
        let decoder = JSONDecoder()
        var base = try decoder.decode(DesignProposal.self, from: data)
        let brief = (try? decoder.decode(DesignBrief.self, from: data)) ?? DesignBrief(items: [])
        base.layoutVersion = nil
        base.roomKind = nil
        base.layoutNotes = []
        if let chosen = RoomKind.keyword(purpose), RoomKind.keyword(base.roomPurpose) != chosen { base.roomPurpose = purpose }
        if base.roomPurpose.isEmpty { base.roomPurpose = purpose }
        guard !brief.items.isEmpty else { return base.placed(in: plan) }
        return compose(base, brief: brief, plan: plan, room: room(plan: plan, purpose: purpose))
    }

    /// Lays out the brief and puts the result into `base`.
    static func compose(_ base: DesignProposal, brief: DesignBrief, plan: FloorPlan, room: RoomKind) -> DesignProposal {
        let layout = LayoutEngine.arrange(brief, in: plan, room: room)
        var proposal = base
        proposal.furniture = layout.furniture
        proposal.zones = layout.zones
        proposal.layoutNotes = layout.notes
        proposal.layoutVersion = 2
        proposal.roomKind = room.rawValue
        return proposal
    }
}
