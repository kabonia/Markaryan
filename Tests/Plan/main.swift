import Foundation

// Plan, design and layout checks. Run: sh Tests/run.sh (works on macOS and Linux).

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) { if !condition() { fatalError("FAIL: \(name)") }; passed += 1 }
func near(_ a: Double, _ b: Double, _ name: String, _ tolerance: Double = 0.0001) { check(abs(a - b) < tolerance, "\(name): \(a) ≠ \(b)") }

// MARK: Test rooms

func segment(_ kind: PlanSegment.Kind, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, height: Double = 2.7) -> PlanSegment {
    PlanSegment(kind: kind, start: PlanPoint(x: x1, y: y1), end: PlanPoint(x: x2, y: y2), height: height)
}

/// Polygon room (walls follow the outline) with optional doors and windows.
func room(_ name: String, _ outline: [(Double, Double)], doors: [PlanSegment] = [], windows: [PlanSegment] = [], objects: [PlanObject] = [], height: Double = 2.7) -> FloorPlan {
    let points = outline.map { PlanPoint(x: $0.0, y: $0.1) }
    var segments = points.indices.map { PlanSegment(kind: .wall, start: points[$0], end: points[($0 + 1) % points.count], height: height) }
    segments += doors + windows
    return FloorPlan(name: name, source: .lidar, segments: segments, objects: objects, floorPolygon: points, ceilingHeight: height, modelFilename: nil)
}

func rectangle(_ name: String, _ width: Double, _ depth: Double, doors: [PlanSegment] = [], windows: [PlanSegment] = [], objects: [PlanObject] = []) -> FloorPlan {
    room(name, [(0, 0), (width, 0), (width, depth), (0, depth)], doors: doors, windows: windows, objects: objects)
}

func decodeProposal(_ json: String) throws -> DesignProposal { try JSONDecoder().decode(DesignProposal.self, from: Data(json.utf8)) }

// MARK: Geometry of a plan

let bedroom = rectangle("Спальня", 4, 3, doors: [segment(.door, 1, 3, 1.8, 3, height: 2.05)], windows: [segment(.window, 1.5, 0, 2.7, 0, height: 1.5)])
near(bedroom.area, 12, "Rectangle area")
near(bedroom.perimeter, 14, "Perimeter counts walls only")
near(bedroom.openingsArea, 0.8 * 2.05 + 1.2 * 1.5, "Openings area")
near(bedroom.netWallArea, 14 * 2.7 - (0.8 * 2.05 + 1.2 * 1.5), "Net wall area")
near(bedroom.width, 4, "Width from bounds")
near(bedroom.depth, 3, "Depth from bounds")
check(bedroom.walls.count == 4 && bedroom.doors.count == 1 && bedroom.windows.count == 1, "Segments by kind")
check(bedroom.contains(PlanPoint(x: 2, y: 1.5)) && !bedroom.contains(PlanPoint(x: 4.5, y: 1)), "Point in polygon")
let swing = bedroom.doorSwing(bedroom.doors[0])
check(swing.hinge == PlanPoint(x: 1, y: 3), "Door hinge at the start of the opening")
near(swing.leaf.x, 1, "Door leaf x")
near(swing.leaf.y, 2.2, "Door leaf opens into the room")

let lShaped = room("Гостиная", [(0, 0), (5, 0), (5, 2), (3, 2), (3, 4), (0, 4)])
near(lShaped.area, 16, "L-shaped area from the floor polygon")
check(lShaped.contains(PlanPoint(x: 1, y: 3)), "Inside the L")
check(!lShaped.contains(PlanPoint(x: 4, y: 3)), "Notch of the L is outside")

let noPolygon = FloorPlan(name: "Без контура", source: .lidar, segments: bedroom.segments, objects: [], floorPolygon: [], ceilingHeight: 2.7, modelFilename: nil)
near(noPolygon.area, 12, "Area falls back to the bounding rectangle")
check(noPolygon.outline.count == 4, "Outline falls back to the bounding rectangle")

// Contour from AR points (x, z): rotated so the longest wall is horizontal, moved to the origin.
let angle = 0.5
func turned(_ x: Double, _ z: Double) -> SIMD3<Float> { SIMD3<Float>(Float(x * cos(angle) - z * sin(angle) + 3), 0, Float(x * sin(angle) + z * cos(angle) - 2)) }
if let contour = FloorPlanBuilder.fromContour([turned(0, 0), turned(5, 0), turned(5, 3), turned(0, 3)], name: "Контур") {
    near(contour.area, 15, "Contour area survives rotation", 0.001)
    near(contour.width, 5, "Longest wall becomes horizontal", 0.001)
    near(contour.depth, 3, "Depth after normalising", 0.001)
    near(contour.bounds.minX, 0, "Plan starts at x = 0", 0.0001)
    near(contour.bounds.minY, 0, "Plan starts at y = 0", 0.0001)
    check(contour.source == .contour && contour.walls.count == 4 && contour.doors.isEmpty, "Contour plan has walls only")
} else { check(false, "Contour plan is built") }
check(FloorPlanBuilder.fromContour([SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0)], name: "x") == nil, "Two points are not a room")

if let json = try? JSONSerialization.jsonObject(with: Data(bedroom.aiDescription.utf8)) as? [String: Any] {
    near(json["floorArea"] as? Double ?? 0, 12, "AI description: area")
    check((json["walls"] as? [Any])?.count == 4 && (json["doors"] as? [Any])?.count == 1, "AI description: walls and doors")
} else { check(false, "AI description is JSON") }

// MARK: Room type

check(RoomKind.keyword("Санузел") == .bathroom && RoomKind.keyword("с/у совмещённый") == .bathroom, "Bathroom keywords")
check(RoomKind.keyword("Кухня") == .kitchen, "Kitchen keyword")
check(RoomKind.keyword("Кухня‑гостиная") == .living && RoomKind.keyword("Студия") == .living, "Kitchen-living room is a living room")
check(RoomKind.keyword("Детская спальня") == .kids && RoomKind.keyword("Спальня") == .bedroom, "Kids before bedroom")
check(RoomKind.keyword("Прихожая") == .hall && RoomKind.keyword("Кабинет") == .office, "Hall and office keywords")
check(RoomKind.keyword("  ") == nil && RoomKind.keyword("Комната 3") == nil, "No type from neutral names")
let scannedBath = rectangle("Комната 1", 2, 1.7, objects: [PlanObject(name: "Унитаз", center: PlanPoint(x: 0.3, y: 0.4), width: 0.4, depth: 0.6, rotation: 0)])
check(RoomKind.fromScan(scannedBath) == .bathroom, "Room type from scanned fixtures")
check(RoomKind.scanReason(scannedBath)?.contains("унитаз") == true, "Reason names the fixture")
check(RoomKind.bathroom.allows("toilet") && !RoomKind.bathroom.allows("sofa"), "Bathroom rules")
check(!RoomKind.bedroom.allows("toilet") && RoomKind.bedroom.allows("bed"), "Bedroom rules")

// MARK: Fixture models from names

check(FixtureModel.resolve(kind: "decor", name: "Унитаз подвесной на инсталляции") == "toilet", "Toilet by name")
check(FixtureModel.resolve(kind: "storage", name: "Зеркало с подсветкой") == "mirror", "Mirror by name")
check(FixtureModel.resolve(kind: "light", name: "Подвесной светильник над столом") == "pendant", "Pendant light")
check(FixtureModel.resolve(kind: "light", name: "Бра у кровати") == "sconce", "Sconce")
check(FixtureModel.resolve(kind: "light", name: "Светодиодная подсветка ниши") == "hiddenlight", "Hidden light")
check(FixtureModel.resolve(kind: "decor", name: "Декоративная подушка") != "shower", "A cushion is not a shower")
check(FixtureModel.resolve(kind: "kitchen", name: "Кухня с мойкой и раковиной") == "kitchen", "Kitchen unit keeps its kind")

// MARK: Lenient decoding of AI answers

let partial = try decodeProposal(#"{"title":"Т","furniture":[{"name":"Унитаз","kind":"toilet","x":"1,2","y":1,"width":0.4,"depth":"0.6"},{"name":"Без координат"}],"zones":[{"name":"Мокрая зона","x":1,"y":1}]}"#)
check(partial.furniture.count == 1, "Broken item is skipped, the rest is kept")
near(partial.furniture[0].x, 1.2, "Number with a comma")
near(partial.furniture[0].depth, 0.6, "Number as a string")
near(partial.furniture[0].rotation, 0, "Missing rotation becomes 0")
check(partial.zones.count == 1 && partial.zones[0].width == 1, "Zone with default size")
check(partial.palette.isEmpty && partial.floor.isEmpty && partial.budgetMax == 0, "Missing parts get defaults")
let empty = try decodeProposal("{}")
check(empty.title == "Концепция" && empty.furniture.isEmpty, "Empty answer still decodes")
let roundTrip = try JSONDecoder().decode(DesignProposal.self, from: JSONEncoder().encode(partial))
check(roundTrip.id == partial.id && roundTrip.furniture == partial.furniture, "Proposal survives saving")

// MARK: Fitting an AI layout into the room

let bathroom = rectangle("Санузел", 2.0, 1.7, doors: [segment(.door, 0.1, 1.7, 0.8, 1.7, height: 2.0)])
let centimetres = try decodeProposal(#"{"roomPurpose":"Санузел","furniture":[{"name":"Унитаз","kind":"toilet","x":150,"y":40,"width":40,"depth":55,"rotation":0},{"name":"Диван","kind":"sofa","x":100,"y":100,"width":200,"depth":90,"rotation":0}]}"#)
let fittedCentimetres = centimetres.fitted(to: bathroom)
check(fittedCentimetres.furniture.count == 1 && fittedCentimetres.furniture[0].model == "toilet", "A sofa is removed from a bathroom")
near(fittedCentimetres.furniture[0].width, 0.4, "Centimetres are converted to metres")
let outside = try decodeProposal(#"{"roomPurpose":"Спальня","furniture":[{"name":"Шкаф","kind":"storage","x":5.5,"y":1.5,"width":1.2,"depth":0.6,"rotation":0}]}"#)
let pulledIn = outside.fitted(to: bedroom).furniture[0]
check(pulledIn.corners.allSatisfy { bedroom.contains($0) }, "An item outside is moved inside the walls")
let kitchenSink = try decodeProposal(#"{"roomPurpose":"Кухня","furniture":[{"name":"Раковина","kind":"sink","x":1,"y":0.5,"width":0.6,"depth":0.5,"rotation":0}]}"#)
check(kitchenSink.fitted(to: bedroom).furniture[0].kind == "kitchen", "A sink in a kitchen is the kitchen sink unit")

// MARK: Built-in designer (characterisation of the current behaviour)

func overlaps(_ a: DesignFurniture, _ b: DesignFurniture) -> Bool {
    func probes(_ item: DesignFurniture) -> [PlanPoint] {
        let c = item.corners
        var points = c + [PlanPoint(x: item.x, y: item.y)]
        for i in 0..<4 { points.append(PlanPoint(x: (c[i].x + c[(i + 1) % 4].x) / 2, y: (c[i].y + c[(i + 1) % 4].y) / 2)) }
        // Points slightly inside the footprint: touching edges is not an overlap.
        return points.map { PlanPoint(x: $0.x + (item.x - $0.x) * 0.05, y: $0.y + (item.y - $0.y) * 0.05) }
    }
    return probes(a).contains { b.covers($0, margin: 0) } || probes(b).contains { a.covers($0, margin: 0) }
}

for (purpose, plan) in [("Спальня", bedroom), ("Санузел", bathroom), ("Гостиная", lShaped)] {
    guard let proposal = OfflineDesigner.propose(plan: plan, style: "Скандинавский", purpose: purpose, wishes: "") else { check(false, "Offline design for \(purpose)"); continue }
    check(!proposal.furniture.isEmpty, "Offline design places items: \(purpose)")
    check(RoomKind.keyword(proposal.roomPurpose) == RoomKind.keyword(purpose), "Offline design keeps the purpose: \(purpose)")
    let floorItems = proposal.furniture.filter { !$0.isMounted && $0.kind != "decor" }
    for item in floorItems { check(item.corners.allSatisfy { plan.contains($0) }, "\(purpose): \(item.name) is inside") }
    for (i, a) in floorItems.enumerated() { for b in floorItems[(i + 1)...] { check(!overlaps(a, b), "\(purpose): \(a.name) does not overlap \(b.name)") } }
    check(proposal.budgetMax > proposal.budgetMin && proposal.budgetMin > 0, "Offline budget: \(purpose)")
}

print("PASS: \(passed) plan and design checks")
