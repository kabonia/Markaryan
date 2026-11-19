import Foundation

/// An electrical point of the room: a socket, a switch or a light.
struct ElectricPoint: Hashable {
    enum Kind: String, CaseIterable {
        /// Socket with an earth contact.
        case socket
        case doubleSocket
        /// IP44 socket for a bathroom.
        case wetSocket
        /// 32 A power socket for a hob.
        case powerSocket
        /// TV block: two sockets, aerial and internet.
        case tvBlock
        case switchOne
        case switchTwo
        /// Ceiling light (recessed spot or surface light).
        case ceilingLight
        case pendant
        /// Wall light: a sconce or the light above a mirror.
        case wallLight

        var title: String {
            switch self {
            case .socket: return "Розетка с заземлением"
            case .doubleSocket: return "Розетка двойная с заземлением"
            case .wetSocket: return "Розетка с заземлением IP44, с крышкой"
            case .powerSocket: return "Силовая розетка 32 А"
            case .tvBlock: return "ТВ‑блок: 2 розетки, ТВ, интернет"
            case .switchOne: return "Выключатель одноклавишный"
            case .switchTwo: return "Выключатель двухклавишный"
            case .ceilingLight: return "Светильник потолочный"
            case .pendant: return "Светильник подвесной"
            case .wallLight: return "Светильник настенный"
            }
        }
        var isSocket: Bool { [.socket, .doubleSocket, .wetSocket, .powerSocket, .tvBlock].contains(self) }
        var isSwitch: Bool { self == .switchOne || self == .switchTwo }
        var isLight: Bool { self == .ceilingLight || self == .pendant || self == .wallLight }
    }

    let kind: Kind
    /// On the inner face of the wall (wall devices; on the outer face for a switch outside the room) or on the ceiling.
    let position: PlanPoint
    /// Unit vector the device faces: into the room it serves.
    let facing: PlanPoint
    /// Metres from the finished floor to the centre of the device.
    let height: Double
    let purpose: String
    /// Number of the circuit (group) on the switchboard.
    let circuit: Int
    /// The `PlanWalls` number of the wall it is on; nil for lights on the ceiling.
    let wall: Int?
}

/// A group on the switchboard: what it feeds, the breaker and the cable.
struct ElectricCircuit: Hashable {
    let number: Int
    let title: String
    let breaker: String
    let cable: String
}

struct ElectricPlan {
    let points: [ElectricPoint]
    let circuits: [ElectricCircuit]
    let notes: [String]

    func count(_ kind: ElectricPoint.Kind) -> Int { points.filter { $0.kind == kind }.count }
    var sockets: [ElectricPoint] { points.filter { $0.kind.isSocket } }
    var switches: [ElectricPoint] { points.filter { $0.kind.isSwitch } }
    var lights: [ElectricPoint] { points.filter { $0.kind.isLight } }
}

/// Electrical points of a room by the usual rules (СП 256.1325800, ПУЭ‑7, ГОСТ Р 50571.7.701 for bathrooms):
/// sockets where the furniture needs them and at least one per 4 m of the perimeter of a living room, a switch at
/// the latch side of every door (outside for a bathroom), lights from the concept or an even grid. A starting point
/// for the electrician, checked against the furniture: no socket behind a wardrobe, in a door or near the shower.
enum ElectricPlanner {
    static let socketHeight = 0.3
    static let switchHeight = 0.9

    static func plan(for plan: FloorPlan, proposal: DesignProposal?, room: RoomKind) -> ElectricPlan {
        var builder = Builder(plan: plan, furniture: proposal?.furniture ?? [], room: room)
        builder.lights()
        builder.switches()
        builder.equipment()
        builder.generalSockets()
        return ElectricPlan(points: builder.points, circuits: builder.circuits, notes: notes(room, hasKitchen: builder.hasKitchen))
    }

    /// An even grid of ceiling lights about 1.2 m apart, kept off the walls.
    static func spotLights(_ plan: FloorPlan) -> [PlanPoint] {
        let polygon = plan.outline
        let b = plan.bounds
        let step = 1.2
        var points: [PlanPoint] = []
        var y = b.minY + 0.6
        while y < b.maxY - 0.3 {
            var x = b.minX + 0.6
            while x < b.maxX - 0.3 {
                let p = PlanPoint(x: x, y: y)
                let around = [p, PlanPoint(x: x + 0.4, y: y), PlanPoint(x: x - 0.4, y: y), PlanPoint(x: x, y: y + 0.4), PlanPoint(x: x, y: y - 0.4)]
                if around.allSatisfy({ PlanMath.contains(polygon, $0) }) { points.append(p) }
                x += step
            }
            y += step
        }
        if points.isEmpty, polygon.count >= 3 {
            // A small room: one light in the middle.
            let middle = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
            if PlanMath.contains(polygon, middle) { points.append(middle) }
        }
        return points
    }

    static func notes(_ room: RoomKind, hasKitchen: Bool) -> [String] {
        var notes = [
            "1. Высоты — от уровня чистого пола до центра изделия.",
            "2. Кабель ВВГнг(А)‑LS: освещение 3×1,5 мм², розетки 3×2,5 мм²\(hasKitchen ? ", варочная панель 3×6 мм²" : "").",
            "3. Розеточные группы — через УЗО или дифавтомат с током утечки 30 мА.",
            "4. Трассы скрытые, только по вертикали и горизонтали, не ближе 150 мм от потолка и углов."
        ]
        if room == .bathroom {
            notes.append("5. Санузел: розетки IP44 не ближе 0,6 м от ванны и душа, выключатель снаружи у двери, металлические части — в систему уравнивания потенциалов (ГОСТ Р 50571.7.701).")
        }
        if hasKitchen {
            notes.append("\(notes.count + 1). Кухня: точки за гарнитуром уточнить по проекту кухни и паспортам техники.")
        }
        notes.append("\(notes.count + 1). Положение точек уточнить на месте по мебели и технике.")
        return notes
    }

    private struct Builder {
        let plan: FloorPlan
        let walls: [WallSide]
        let furniture: [DesignFurniture]
        let room: RoomKind
        /// Bathroom zone 2: 0.6 m around the shower and the bath — no sockets there.
        let wetZones: [PlanRect]
        var points: [ElectricPoint] = []
        var circuits: [ElectricCircuit] = []
        var hasKitchen = false

        init(plan: FloorPlan, furniture: [DesignFurniture], room: RoomKind) {
            self.plan = plan
            walls = PlanWalls.numbered(plan)
            self.furniture = furniture
            self.room = room
            wetZones = furniture.filter { ["shower", "bathtub"].contains($0.model) }.map { $0.footprint.grown(by: 0.6) }
        }

        mutating func circuit(_ title: String, breaker: String, cable: String) -> Int {
            if let existing = circuits.first(where: { $0.title == title }) { return existing.number }
            let circuit = ElectricCircuit(number: circuits.count + 1, title: title, breaker: breaker, cable: cable)
            circuits.append(circuit)
            return circuit.number
        }

        var lighting: Int { mutating get { circuit("Освещение", breaker: "C10", cable: "ВВГнг(А)‑LS 3×1,5") } }
        var roomSockets: Int {
            mutating get {
                room == .bathroom
                    ? circuit("Розетки санузла IP44", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5")
                    : circuit("Розетки", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5")
            }
        }

        mutating func add(_ kind: ElectricPoint.Kind, wall: WallSide, along: Double, height: Double, purpose: String, circuit: Int, outside: Bool = false) {
            let position = outside ? wall.point(along, offset: -WallBody.standardThickness) : wall.point(along)
            points.append(ElectricPoint(kind: kind, position: position, facing: outside ? wall.normal * -1 : wall.normal, height: height,
                                        purpose: purpose, circuit: circuit, wall: wall.number))
        }

        /// A wall spot where a device at `height` stays usable: not in a door or window opening, not hidden behind
        /// furniture taller than it, not in the wet zone of a bathroom, not on top of another device.
        func isFree(_ wall: WallSide, at along: Double, height: Double, ignoring: Set<Int> = []) -> Bool {
            guard along >= 0.15, along <= wall.length - 0.15 else { return false }
            if (wall.doors + wall.windows).contains(where: { along > $0.from - 0.1 && along < $0.to + 0.1 }) { return false }
            let point = wall.point(along, offset: 0.05)
            for (index, item) in furniture.enumerated() where item.blocksFloor && !ignoring.contains(index) && item.footprint.distance(to: point) < 0.06 {
                if item.estimatedHeight > height - 0.05 { return false }
            }
            if wetZones.contains(where: { $0.contains(point) }) { return false }
            return !points.contains { $0.kind.isSocket && $0.wall == wall.number && $0.position.distance(to: wall.point(along)) < 0.25 && abs($0.height - height) < 0.3 }
        }

        /// The free wall spot closest to `target` (a few centimetres off the target are fine, a metre is the limit).
        func spot(near target: PlanPoint, height: Double, reach: Double = 1.2, ignoring: Set<Int> = []) -> (WallSide, Double)? {
            var best: (wall: WallSide, along: Double, distance: Double)?
            for wall in walls {
                let projected = wall.project(target)
                guard projected.offset > -0.3, projected.offset < reach + 0.3 else { continue }
                var step = 0.0
                while step <= reach {
                    if let along = [projected.along + step, projected.along - step].first(where: { isFree(wall, at: $0, height: height, ignoring: ignoring) }) {
                        let distance = wall.point(along).distance(to: target)
                        if distance <= reach + 0.4, best == nil || distance < best!.distance { best = (wall, along, distance) }
                        break
                    }
                    step += 0.05
                }
            }
            return best.map { ($0.wall, $0.along) }
        }

        @discardableResult
        mutating func socket(_ kind: ElectricPoint.Kind, near target: PlanPoint, height: Double, purpose: String, circuit: Int, ignoring: Set<Int> = []) -> Bool {
            guard let (wall, along) = spot(near: target, height: height, ignoring: ignoring) else { return false }
            add(kind, wall: wall, along: along, height: height, purpose: purpose, circuit: circuit)
            return true
        }

        // MARK: Lights and switches

        mutating func lights() {
            let ceiling = plan.ceilingHeight
            let group = lighting
            for p in ElectricPlanner.spotLights(plan) {
                points.append(ElectricPoint(kind: .ceilingLight, position: p, facing: PlanPoint(x: 0, y: 1), height: ceiling, purpose: "общий свет", circuit: group, wall: nil))
            }
            for item in furniture where item.model == "pendant" {
                points.append(ElectricPoint(kind: .pendant, position: PlanPoint(x: item.x, y: item.y), facing: PlanPoint(x: 0, y: 1), height: ceiling, purpose: item.name.lowercased(), circuit: group, wall: nil))
            }
            for item in furniture where item.model == "sconce" || (item.model == "mirror" && [.bathroom, .hall].contains(room)) {
                guard let wall = nearestWall(to: PlanPoint(x: item.x, y: item.y)) else { continue }
                let along = min(max(wall.project(PlanPoint(x: item.x, y: item.y)).along, 0.15), wall.length - 0.15)
                add(.wallLight, wall: wall, along: along, height: item.model == "mirror" ? 1.9 : 1.6, purpose: item.model == "mirror" ? "подсветка зеркала" : item.name.lowercased(), circuit: group)
            }
        }

        mutating func switches() {
            let group = lighting
            let lightKinds = Set(points.filter(\.kind.isLight).map(\.kind))
            let kind: ElectricPoint.Kind = lightKinds.count > 1 ? .switchTwo : .switchOne
            for wall in walls {
                for door in wall.doors {
                    // Latch side: away from the hinge at the start of the door, so the open leaf does not hide the switch.
                    let hingeAtFrom = wall.project(door.segment.start).along <= wall.project(door.segment.end).along
                    let sides = hingeAtFrom ? [door.to + 0.15, door.from - 0.15] : [door.from - 0.15, door.to + 0.15]
                    guard let along = sides.first(where: { $0 >= 0.1 && $0 <= wall.length - 0.1 }) else { continue }
                    // A bathroom switch is outside, next to the door.
                    add(kind, wall: wall, along: along, height: ElectricPlanner.switchHeight, purpose: room == .bathroom ? "снаружи у двери" : "у входа",
                        circuit: group, outside: room == .bathroom)
                }
            }
        }

        // MARK: Sockets by the furniture

        mutating func equipment() {
            for item in furniture {
                let rect = item.footprint
                let back = rect.center - rect.axisY * (item.depth / 2)
                let side = rect.axisX * (item.width / 2 + 0.2)
                switch item.model {
                case "bed":
                    // Above the nightstands, which are lower than the sockets.
                    let group = roomSockets
                    let nightstands = Set(furniture.indices.filter { index in
                        let other = furniture[index]
                        return other.model == "storage" && other.width <= 0.65 && other.depth <= 0.55 && other.footprint.distance(to: rect.center) < item.width / 2 + item.depth / 2 + 0.6
                    })
                    for target in [back + side, back - side] { socket(.doubleSocket, near: target, height: 0.7, purpose: "у кровати", circuit: group, ignoring: nightstands) }
                case "desk":
                    socket(.doubleSocket, near: back + rect.axisX * max(0, item.width / 2 - 0.25), height: 0.9, purpose: "над рабочим столом", circuit: roomSockets)
                case "tv":
                    socket(.tvBlock, near: back, height: 1.1, purpose: "за телевизором", circuit: roomSockets)
                case "sofa":
                    let group = roomSockets
                    for target in [back + side, back - side] { socket(.socket, near: target, height: ElectricPlanner.socketHeight, purpose: "у дивана", circuit: group) }
                case "floorlamp":
                    socket(.socket, near: rect.center, height: ElectricPlanner.socketHeight, purpose: "торшер", circuit: roomSockets)
                case "washer":
                    let group = circuit("Стиральная машина", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5")
                    socket(room == .bathroom ? .wetSocket : .socket, near: back + side, height: 1.0, purpose: "стиральная машина", circuit: group)
                case "boiler":
                    let group = circuit("Водонагреватель", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5")
                    socket(room == .bathroom ? .wetSocket : .socket, near: back + side, height: 1.6, purpose: "водонагреватель", circuit: group)
                case "sink" where room == .bathroom:
                    socket(.wetSocket, near: back + side, height: 1.0, purpose: "у зеркала: фен, бритва", circuit: roomSockets)
                case "appliance" where item.name.lowercased().contains("холод"):
                    let group = hasKitchenUnit ? kitchenWork : roomSockets
                    socket(.socket, near: back + side, height: ElectricPlanner.socketHeight, purpose: "холодильник", circuit: group)
                case "kitchen":
                    kitchen(item)
                default:
                    break
                }
            }
        }

        var hasKitchenUnit: Bool { furniture.contains { $0.model == "kitchen" } }
        var kitchenWork: Int { mutating get { circuit("Кухня: рабочая зона", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5") } }

        /// Above the worktop, behind the cabinets: hob, oven, dishwasher, hood.
        mutating func kitchen(_ item: DesignFurniture) {
            hasKitchen = true
            let rect = item.footprint
            guard let wall = walls.first(where: { $0.number == item.wall }) ?? nearestWall(to: rect.center - rect.axisY * (item.depth / 2)) else { return }
            let alongs = rect.corners.map { wall.project($0).along }
            let low = max(0.1, alongs.min()!), high = min(wall.length - 0.1, alongs.max()!)
            guard high - low > 0.3 else { return }
            let work = kitchenWork
            let count = max(2, min(4, Int((high - low) / 0.9)))
            for index in 0..<count {
                add(.doubleSocket, wall: wall, along: low + (high - low) * (Double(index) + 0.5) / Double(count), height: 1.1, purpose: "над столешницей", circuit: work)
            }
            let middle = (low + high) / 2
            add(.powerSocket, wall: wall, along: middle, height: 0.15, purpose: "варочная панель",
                circuit: circuit("Варочная панель", breaker: "C32", cable: "ВВГнг(А)‑LS 3×6"))
            add(.socket, wall: wall, along: min(high - 0.1, middle + 0.6), height: 0.15, purpose: "духовой шкаф",
                circuit: circuit("Духовой шкаф", breaker: "C16", cable: "ВВГнг(А)‑LS 3×2,5"))
            add(.socket, wall: wall, along: max(low + 0.1, low + 0.45), height: ElectricPlanner.socketHeight, purpose: "посудомоечная машина",
                circuit: circuit("Посудомоечная машина", breaker: "C16 + УЗО 30 мА", cable: "ВВГнг(А)‑LS 3×2,5"))
            add(.socket, wall: wall, along: middle, height: 2.2, purpose: "вытяжка", circuit: work)
        }

        // MARK: Sockets for the room

        /// At least one socket per 4 m of the perimeter of a living room (one per 10 m² in a hall), spread along the
        /// free walls as far from the others as possible.
        mutating func generalSockets() {
            let required: Int
            switch room {
            case .living, .bedroom, .kids, .office: required = Int((plan.perimeter / 4).rounded(.up))
            case .hall: required = max(1, Int((plan.area / 10).rounded(.up)))
            case .kitchen: required = hasKitchen ? 0 : 4
            case .bathroom: required = 0
            }
            let group = roomSockets
            if room == .hall, let entrance = plan.doors.first {
                socket(.socket, near: entrance.end, height: ElectricPlanner.socketHeight, purpose: "у входа", circuit: group)
            }
            var have = points.filter { [.socket, .doubleSocket, .tvBlock].contains($0.kind) && $0.height < 1.5 }.count
            while have < required {
                var best: (wall: WallSide, along: Double, distance: Double)?
                for wall in walls {
                    var along = 0.3
                    while along <= wall.length - 0.3 {
                        if isFree(wall, at: along, height: ElectricPlanner.socketHeight) {
                            let p = wall.point(along)
                            let distance = points.filter(\.kind.isSocket).map { $0.position.distance(to: p) }.min() ?? 100
                            if best == nil || distance > best!.distance + 1e-9 { best = (wall, along, distance) }
                        }
                        along += 0.25
                    }
                }
                guard let best, best.distance >= 0.6 else { break }
                add(.socket, wall: best.wall, along: best.along, height: ElectricPlanner.socketHeight, purpose: "общая", circuit: group)
                have += 1
            }
        }

        func nearestWall(to point: PlanPoint) -> WallSide? {
            walls.min { PlanMath.distance(point, toSegment: $0.start, $0.end) < PlanMath.distance(point, toSegment: $1.start, $1.end) }
        }
    }
}
