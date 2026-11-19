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

if let json = try? JSONSerialization.jsonObject(with: Data(PlanWalls.aiDescription(bedroom).utf8)) as? [String: Any], let walls = json["walls"] as? [[String: Any]] {
    near(json["floorArea"] as? Double ?? 0, 12, "AI description: area")
    check(walls.count == 4 && walls[0]["number"] as? Int == 1 && (walls[0]["doors"] as? [Any])?.count == 1, "AI description: wall 1 has the door")
    check((walls[2]["windows"] as? [Any])?.count == 1, "AI description: window on wall 3")
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

// MARK: Concepts are placed once and keep their room type

let legacyPlanJSON = #"""
{"id":"7A4F0B6E-1111-4C3B-9C49-3D2E1F0A5B6C","name":"Санузел","createdAt":700000000,"source":"lidar","ceilingHeight":2.6,
 "segments":[{"id":"7A4F0B6E-2222-4C3B-9C49-3D2E1F0A5B6C","kind":"wall","start":{"x":0,"y":0},"end":{"x":2,"y":0},"height":2.6},
             {"id":"7A4F0B6E-3333-4C3B-9C49-3D2E1F0A5B6C","kind":"wall","start":{"x":2,"y":0},"end":{"x":2,"y":1.7},"height":2.6},
             {"id":"7A4F0B6E-4444-4C3B-9C49-3D2E1F0A5B6C","kind":"wall","start":{"x":2,"y":1.7},"end":{"x":0,"y":1.7},"height":2.6},
             {"id":"7A4F0B6E-5555-4C3B-9C49-3D2E1F0A5B6C","kind":"wall","start":{"x":0,"y":1.7},"end":{"x":0,"y":0},"height":2.6}],
 "proposals":[{"title":"Старая концепция","roomPurpose":"Санузел",
   "furniture":[{"name":"Унитаз","kind":"toilet","x":150,"y":40,"width":40,"depth":55,"rotation":0},{"name":"Диван","kind":"sofa","x":100,"y":100,"width":200,"depth":90,"rotation":0}]}]}
"""#
let legacyPlan = try JSONDecoder().decode(FloorPlan.self, from: Data(legacyPlanJSON.utf8))
check(legacyPlan.objects.isEmpty && legacyPlan.floorPolygon.isEmpty && legacyPlan.apartmentID == nil, "Old plan without optional keys still loads")
let migrated = legacyPlan.proposals[0]
check(migrated.layoutVersion == 1 && migrated.roomKind == "bathroom", "Old concept is placed once while loading")
check(migrated.furniture.count == 1, "Old concept loses items that do not belong in the room")
near(migrated.furniture[0].width, 0.4, "Old concept is converted to metres while loading")
let placedTwice = migrated.placed(in: legacyPlan)
check(placedTwice.furniture == migrated.furniture && placedTwice.layoutVersion == 1, "Placing again changes nothing")
let saved = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(legacyPlan))
check(saved.proposals[0].furniture == migrated.furniture && saved.proposals[0].roomKind == "bathroom", "Placed concept survives saving")
var relabelled = migrated
relabelled.roomPurpose = "Гостиная"
check(RoomKind.detect(plan: legacyPlan, proposal: relabelled) == .bathroom, "Stored room type wins over later guesses")

// MARK: Apartment foundation: every normalised room knows where it sits in the scan

let rawPoints = [turned(0, 0), turned(5, 0), turned(5, 3), turned(0, 3)]
if let local = FloorPlanBuilder.fromContour(rawPoints, name: "Комната"), let placement = local.placement {
    for (point, raw) in zip(local.floorPolygon, rawPoints) {
        let back = placement.apply(point)
        near(back.x, Double(raw.x), "Placement maps back to scan x", 0.0005)
        near(back.y, Double(raw.z), "Placement maps back to scan y", 0.0005)
    }
    let restored = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(local))
    check(restored.placement == placement, "Placement survives saving")
} else { check(false, "Contour plan has a placement") }
var withApartment = bedroom
withApartment.apartmentID = UUID()
let reloadedApartment = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(withApartment))
check(reloadedApartment.apartmentID == withApartment.apartmentID, "Apartment link survives saving")

// MARK: Turned rectangles and polygons

let square = PlanRect(center: PlanPoint(x: 0, y: 0), width: 1, depth: 1, rotation: 0)
check(!square.overlaps(PlanRect(center: PlanPoint(x: 1, y: 0), width: 1, depth: 1, rotation: 0)), "Touching rectangles do not overlap")
check(square.overlaps(PlanRect(center: PlanPoint(x: 0.9, y: 0.3), width: 1, depth: 1, rotation: 0)), "Overlapping rectangles")
check(square.overlaps(PlanRect(center: PlanPoint(x: 1.2, y: 0), width: 1, depth: 1, rotation: .pi / 4)), "A turned corner pokes in")
check(!square.overlaps(PlanRect(center: PlanPoint(x: 1.25, y: 0), width: 1, depth: 1, rotation: .pi / 4)), "A turned rectangle just clear")
near(square.distance(to: PlanPoint(x: 1.5, y: 0)), 1, "Distance to a rectangle side")
near(square.distance(to: PlanPoint(x: 1.5, y: 1.5)), 2.squareRoot(), "Distance to a rectangle corner")
check(square.crosses(PlanPoint(x: -2, y: 0), PlanPoint(x: 2, y: 0)), "A line through the rectangle")
let uShape = [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0), (3.0, 3.0), (3.0, 1.0), (1.0, 1.0), (1.0, 3.0), (0.0, 3.0)].map { PlanPoint(x: $0.0, y: $0.1) }
check(PlanMath.polygon(uShape, contains: PlanRect(center: PlanPoint(x: 2, y: 0.5), width: 3, depth: 0.6, rotation: 0)), "Rectangle inside the U")
check(!PlanMath.polygon(uShape, contains: PlanRect(center: PlanPoint(x: 2, y: 2.25), width: 3, depth: 0.5, rotation: 0)), "Corners inside the U but the middle crosses the gap")
check(PlanMath.signedArea2(uShape) > 0, "Clockwise on screen has a positive area")

// MARK: Walls numbered clockwise from the entrance

let bedroomWalls = PlanWalls.numbered(bedroom)
check(bedroomWalls.map(\.number) == [1, 2, 3, 4], "Four numbered walls")
check(bedroomWalls[0].doors.count == 1 && bedroomWalls[0].start == PlanPoint(x: 4, y: 3) && bedroomWalls[0].end == PlanPoint(x: 0, y: 3), "Wall 1 has the entrance, walked right to left")
near(bedroomWalls[0].doors[0].from, 2.2, "Door position along wall 1")
near(bedroomWalls[0].doors[0].to, 3.0, "Door end along wall 1")
check(bedroomWalls[1].start == PlanPoint(x: 0, y: 3) && bedroomWalls[2].start == PlanPoint(x: 0, y: 0) && bedroomWalls[3].start == PlanPoint(x: 4, y: 0), "Then left, top and right walls")
check(bedroomWalls[2].windows.count == 1 && bedroomWalls[2].normal == PlanPoint(x: 0, y: 1), "Window on the top wall, normal into the room")
near(bedroomWalls[2].itemRotation, 0, "Item against the top wall faces down")
near(abs(bedroomWalls[0].itemRotation), 180, "Item against the entrance wall faces up")
check(bedroomWalls.allSatisfy { bedroom.contains($0.point($0.length / 2, offset: 0.2)) }, "Every normal points into the room")
let lWalls = PlanWalls.numbered(lShaped)
check(lWalls.map { Int(($0.length * 10).rounded()) } == [50, 20, 20, 20, 30, 40], "L-shaped room: top wall first, then clockwise")
check(lWalls.allSatisfy { lShaped.contains($0.point($0.length / 2, offset: 0.2)) }, "L-shaped room: normals into the room")

// MARK: Layout check

func item(_ name: String, _ kind: String, _ x: Double, _ y: Double, _ width: Double, _ depth: Double, _ rotation: Double = 0) -> DesignFurniture {
    DesignFurniture(name: name, kind: kind, x: x, y: y, width: width, depth: depth, rotation: rotation)
}
let goodBedroom = [
    item("Кровать 1600×2000", "bed", 1.6, 1.08, 1.6, 2.0),
    item("Шкаф 1200", "storage", 3.62, 2.35, 1.2, 0.6, 90)
]
check(LayoutCheck.issues(plan: bedroom, furniture: goodBedroom).isEmpty, "A good bedroom has no issues: \(LayoutCheck.issues(plan: bedroom, furniture: goodBedroom).map(\.message))")
func kinds(_ furniture: [DesignFurniture], in plan: FloorPlan = bedroom) -> Set<LayoutIssue.Kind> { Set(LayoutCheck.issues(plan: plan, furniture: furniture).map(\.kind)) }
check(kinds(goodBedroom + [item("Стол", "desk", 2.0, 1.0, 1.2, 0.6)]).contains(.overlap), "Overlap is found")
check(kinds(goodBedroom + [item("Комод", "storage", 1.4, 2.65, 0.8, 0.45, 180)]).contains(.door), "Item in the door swing is found")
check(kinds([item("Шкаф", "storage", 4.2, 1.5, 1.2, 0.6, 90)]).contains(.outside), "Item behind a wall is found")
check(kinds([item("Шкаф под окном", "storage", 2.1, 0.38, 1.2, 0.6)]).contains(.window), "Tall item in front of a window is found")
check(!kinds([item("Комод под окном", "storage", 2.1, 0.305, 1.0, 0.45)]).contains(.window), "Low chest under a window is fine")
let wall = [item("Стеллаж через всю комнату", "storage", 2.0, 1.8, 3.84, 0.4), item("Кровать", "bed", 2.0, 0.6, 1.4, 1.0, 90)]
check(LayoutCheck.issues(plan: bedroom, furniture: wall).contains { $0.kind == .passage && $0.message.contains("Кровать") }, "Item cut off from the entrance is found")
check(kinds([item("Шкаф у двери", "storage", 1.4, 2.6, 1.6, 0.6, 180)]).contains(.passage), "Blocked entrance is found")
check(kinds([item("Кухня", "kitchen", 2.0, 0.38, 2.4, 0.6), item("Остров", "table", 2.0, 1.2, 1.6, 0.6)]).contains(.front), "Too little room in front of a kitchen is found")

// MARK: Layout engine: built-in designer in typical rooms

let narrowBathroom = room("Санузел", [(0, 0), (1.5, 0), (1.5, 2.6), (0, 2.6)], doors: [segment(.door, 0.4, 2.6, 1.1, 2.6, height: 2.0)])
let smallBathroom = room("Санузел", [(0, 0), (2, 0), (2, 1.7), (0, 1.7)], doors: [segment(.door, 0.1, 1.7, 0.8, 1.7, height: 2.0)])
let bigBathroom = room("Ванная", [(0, 0), (2.6, 0), (2.6, 2.4), (0, 2.4)], doors: [segment(.door, 1.7, 2.4, 2.45, 2.4, height: 2.0)])
let lLiving = room("Гостиная", [(0, 0), (5, 0), (5, 2.4), (3, 2.4), (3, 4.5), (0, 4.5)], doors: [segment(.door, 3.0, 3.2, 3.0, 4.1, height: 2.05)], windows: [segment(.window, 1.0, 0, 3.0, 0, height: 1.5)])
let studio = room("Студия", [(0, 0), (6, 0), (6, 5), (0, 5)], doors: [segment(.door, 0.3, 5, 1.2, 5, height: 2.05)], windows: [segment(.window, 1.5, 0, 4.5, 0, height: 1.6)])
let hall = room("Прихожая", [(0, 0), (1.6, 0), (1.6, 3.2), (0, 3.2)], doors: [segment(.door, 0.4, 3.2, 1.3, 3.2, height: 2.05), segment(.opening, 0.3, 0, 1.2, 0, height: 2.1)])
let kids = room("Детская", [(0, 0), (3, 0), (3, 3.3), (0, 3.3)], doors: [segment(.door, 2.0, 3.3, 2.8, 3.3, height: 2.05)], windows: [segment(.window, 0.8, 0, 2.2, 0, height: 1.5)])
let office = room("Кабинет", [(0, 0), (2.6, 0), (2.6, 3), (0, 3)], doors: [segment(.door, 0.2, 3, 1.0, 3, height: 2.05)], windows: [segment(.window, 0.7, 0, 1.9, 0, height: 1.5)])
let kitchen = room("Кухня", [(0, 0), (3, 0), (3, 3.5), (0, 3.5)], doors: [segment(.door, 2.0, 3.5, 2.8, 3.5, height: 2.05)], windows: [segment(.window, 0.9, 0, 2.1, 0, height: 1.5)])
let chamfered = room("Спальня", [(0, 0), (4, 0), (4, 2.2), (3.2, 3.4), (0, 3.4)], doors: [segment(.door, 0.3, 3.4, 1.1, 3.4, height: 2.05)], windows: [segment(.window, 1.2, 0, 2.6, 0, height: 1.5)])
let doorless = FloorPlanBuilder.fromContour([SIMD3<Float>(0, 0, 0), SIMD3<Float>(4, 0, 0), SIMD3<Float>(4, 0, 3.5), SIMD3<Float>(0, 0, 3.5)], name: "Контур")!

func models(_ proposal: DesignProposal) -> [String] { proposal.furniture.map(\.model) }
let cases: [(String, FloorPlan, String, [String])] = [
    ("Санузел", narrowBathroom, "", ["shower", "toilet", "sink"]),
    ("Санузел", smallBathroom, "", ["shower", "toilet", "sink"]),
    ("Ванная", bigBathroom, "ванна, стиральная машина", ["bathtub", "toilet", "sink", "washer"]),
    ("Спальня", bedroom, "", ["bed"]),
    ("Спальня", chamfered, "", ["bed", "storage"]),
    ("Гостиная", lLiving, "", ["sofa", "tv"]),
    ("Кухня‑гостиная", studio, "", ["kitchen", "table", "chair", "sofa", "tv"]),
    ("Прихожая", hall, "", ["storage"]),
    ("Детская", kids, "", ["bed", "desk"]),
    ("Кабинет", office, "", ["desk", "chair"]),
    ("Кухня", kitchen, "", ["kitchen", "appliance"]),
    ("Спальня", doorless, "", ["bed"])
]
for (purpose, plan, wishes, required) in cases {
    guard let proposal = OfflineDesigner.propose(plan: plan, style: "Современный", purpose: purpose, wishes: wishes) else { check(false, "Design for \(plan.name)"); continue }
    let issues = LayoutCheck.issues(plan: plan, furniture: proposal.furniture)
    check(issues.isEmpty, "\(purpose) «\(plan.name)»: no layout issues, got \(issues.map(\.message))")
    for model in required { check(models(proposal).contains(model), "\(purpose) «\(plan.name)»: has \(model), got \(models(proposal))") }
    check(proposal.layoutVersion == 2 && proposal.roomKind == DesignComposer.room(plan: plan, purpose: purpose).rawValue, "\(purpose): placed by the engine")
    check(proposal.placed(in: plan).furniture == proposal.furniture, "\(purpose): engine layout is not fitted again")
}
let studioDesign = OfflineDesigner.propose(plan: studio, style: "Лофт", purpose: "Кухня‑гостиная", wishes: "")!
check(Set(studioDesign.zones.map(\.name)) == ["Кухня", "Гостиная"], "Studio has kitchen and living zones")
check(!LayoutCheck.issues(plan: studio, furniture: studioDesign.furniture).contains { $0.kind == .window }, "Kitchen is not put under the window")
let again = OfflineDesigner.propose(plan: studio, style: "Лофт", purpose: "Кухня‑гостиная", wishes: "")!
check(again.furniture == studioDesign.furniture, "Same room, same layout")

// MARK: Layout engine: AI brief

func aiDesign(_ json: String, _ plan: FloorPlan, _ purpose: String) throws -> DesignProposal {
    try DesignComposer.proposal(from: Data(json.utf8), plan: plan, purpose: purpose)
}
let studioBrief = #"""
{"title":"Светлая студия","style":"Скандинавский","summary":"Кухня у глухой стены, диван спиной к кухне.","roomPurpose":"кухня-гостиная",
 "items":[
  {"name":"Кухонный гарнитур 2700","kind":"kitchen","width":2.7,"depth":0.6,"count":1,"placement":"corner","wall":2,"relation":"none","target":0,"prefer":"none","optional":false,"zone":"Кухня"},
  {"name":"Холодильник","kind":"appliance","width":0.6,"depth":0.65,"count":1,"placement":"wall","wall":0,"relation":"nextTo","target":1,"prefer":"none","optional":false,"zone":"Кухня"},
  {"name":"Обеденный стол","kind":"table","width":1.4,"depth":0.8,"count":1,"placement":"free","wall":0,"relation":"none","target":0,"prefer":"window","optional":false,"zone":"Кухня"},
  {"name":"Стул","kind":"chair","width":0.45,"depth":0.5,"count":"4","placement":"free","wall":0,"relation":"around","target":3,"prefer":"none","optional":false,"zone":"Кухня"},
  {"name":"Диван","kind":"sofa","width":220,"depth":95,"count":1,"placement":"wall","wall":4,"relation":"none","target":0,"prefer":"none","optional":false,"zone":"Гостиная"},
  {"name":"Журнальный столик","kind":"table","width":1.0,"depth":0.55,"count":1,"placement":"free","wall":0,"relation":"front","target":5,"prefer":"none","optional":true,"zone":"Гостиная"},
  {"name":"ТВ на тумбе","kind":"tv","width":1.8,"depth":0.45,"count":1,"placement":"wall","wall":0,"relation":"opposite","target":5,"prefer":"none","optional":false,"zone":"Гостиная"},
  {"name":"Ковёр","kind":"decor","width":2.0,"depth":1.4,"count":1,"placement":"free","wall":0,"relation":"under","target":6,"prefer":"none","optional":true,"zone":"Гостиная"},
  {"name":"Подвесной светильник","kind":"light","width":0.5,"depth":0.5,"count":1,"placement":"ceiling","wall":0,"relation":"above","target":3,"prefer":"none","optional":true,"zone":"Кухня"},
  {"name":"Унитаз","kind":"toilet","width":0.4,"depth":0.6,"count":1,"placement":"wall","wall":0,"relation":"none","target":0,"prefer":"none","optional":false,"zone":""}
 ],
 "palette":["#F2EFEA","#D9C7A7"],"materials":[],"lighting":"","tips":[],"budgetMin":900000,"budgetMax":1500000,
 "floor":{"material":"Кварцвинил","color":"#D9C7A7","details":"","english":"oak vinyl"},"walls":{"material":"Краска","color":"#F2EFEA","details":"","english":"white paint"},"ceiling":{"material":"Натяжной","color":"#FFFFFF","details":"","english":"white ceiling"}}
"""#
let ai = try aiDesign(studioBrief, studio, "Кухня‑гостиная")
let aiIssues = LayoutCheck.issues(plan: studio, furniture: ai.furniture)
check(aiIssues.isEmpty, "AI studio: no layout issues, got \(aiIssues.map(\.message)) notes \(ai.layoutNotes)")
check(ai.layoutVersion == 2 && ai.title == "Светлая студия" && ai.floor.material == "Кварцвинил", "AI texts and finishes are kept")
check(!models(ai).contains("toilet") && ai.layoutNotes.contains { $0.contains("Унитаз") }, "Toilet is removed from a studio with a note")
let aiSofa = ai.furniture.first { $0.model == "sofa" }!
near(aiSofa.width, 2.2, "Centimetres in the brief become metres")
check(aiSofa.wall == 4, "Sofa stands against the wall the AI asked for")
check(ai.furniture.first { $0.model == "kitchen" }?.wall == 2, "Kitchen on the wall the AI asked for")
let aiTable = ai.furniture.first { $0.name == "Обеденный стол" }!
let chairs = ai.furniture.filter { $0.model == "chair" }
check(chairs.count == 4, "Four chairs from one item with count 4, got \(chairs.count)")
check(chairs.allSatisfy { aiTable.footprint.distance(to: PlanPoint(x: $0.x, y: $0.y)) < 0.4 }, "Chairs stand around the table")
check(chairs.allSatisfy { $0.front.dot(PlanPoint(x: aiTable.x - $0.x, y: aiTable.y - $0.y)) > 0 }, "Chairs face the table")
let coffee = ai.furniture.first { $0.name == "Журнальный столик" }!
let toCoffee = PlanPoint(x: coffee.x - aiSofa.x, y: coffee.y - aiSofa.y)
check(toCoffee.dot(aiSofa.front) > 0.5 && toCoffee.dot(aiSofa.front) < 1.4, "Coffee table in front of the sofa")
let tv = ai.furniture.first { $0.model == "tv" }!
check(tv.front.dot(PlanPoint(x: aiSofa.x - tv.x, y: aiSofa.y - tv.y)) > 1.5 && aiSofa.front.dot(PlanPoint(x: tv.x - aiSofa.x, y: tv.y - aiSofa.y)) > 1.5, "TV faces the sofa from the opposite wall")
let rug = ai.furniture.first { $0.name == "Ковёр" }!
check(rug.isFlat && rug.footprint.contains(PlanPoint(x: coffee.x, y: coffee.y)), "Rug lies under the coffee table")
let lamp = ai.furniture.first { $0.name == "Подвесной светильник" }!
check(lamp.isCeiling && aiTable.footprint.contains(PlanPoint(x: lamp.x, y: lamp.y)), "Pendant hangs above the table")
check(ai.zones.count == 2, "Zones come from the items")

let tooBig = try aiDesign(#"{"items":[{"name":"Кровать 1600","kind":"bed","width":1.6,"depth":2.05,"placement":"wall"}]}"#, room("Кладовая", [(0, 0), (1.5, 0), (1.5, 1.5), (0, 1.5)], doors: [segment(.door, 0.4, 1.5, 1.1, 1.5)]), "Спальня")
check(tooBig.furniture.isEmpty && tooBig.layoutNotes.contains { $0.contains("Не поместилось") }, "An item that cannot fit is reported, not forced in")
let closet = room("Гардеробная", [(0, 0), (2.4, 0), (2.4, 2.4), (0, 2.4)], doors: [segment(.door, 0.2, 2.4, 0.9, 2.4)])
let shrunk = try aiDesign(#"{"items":[{"name":"Шкаф","kind":"storage","width":2.6,"depth":0.6,"placement":"wall"}]}"#, closet, "Прихожая")
check(shrunk.furniture.count == 1 && shrunk.furniture[0].width < 2.3 && shrunk.layoutNotes.contains { $0.contains("уменьшен") }, "A too wide item is made narrower with a note: \(shrunk.furniture.map(\.width)) \(shrunk.layoutNotes)")
check(LayoutCheck.issues(plan: closet, furniture: shrunk.furniture).isEmpty, "The narrower item keeps the rules")
let legacy = try aiDesign(#"{"furniture":[{"name":"Кровать","kind":"bed","x":2,"y":1.2,"width":1.6,"depth":2.0,"rotation":0}]}"#, bedroom, "Спальня")
check(legacy.layoutVersion == 1 && legacy.furniture.count == 1, "An old-style answer with coordinates is still fitted")
let pair = try aiDesign(#"{"items":[{"name":"Кровать","kind":"bed","width":1.6,"depth":2.05,"placement":"wall","prefer":"farFromDoor"},{"name":"Тумба","kind":"storage","width":0.45,"depth":0.4,"count":2,"relation":"nextTo","target":1}]}"#, bedroom, "Спальня")
let bed = pair.furniture.first { $0.model == "bed" }!
let stands = pair.furniture.filter { $0.name == "Тумба" }
check(stands.count == 2, "Two nightstands placed")
let sides = stands.map { PlanPoint(x: $0.x - bed.x, y: $0.y - bed.y).dot(bed.footprint.axisX) }
check(sides.count == 2 && sides[0] * sides[1] < 0, "Nightstands on both sides of the bed")
check(stands.allSatisfy { bed.footprint.distance(to: PlanPoint(x: $0.x, y: $0.y)) < 0.35 }, "Nightstands right next to the bed")
let lenient = try JSONDecoder().decode(DesignBrief.self, from: Data(#"{"items":[{"name":"Стол","kind":"table","placement":"у стены","count":"2","target":"1","relation":"рядом"},{"kind":"chair"}]}"#.utf8))
check(lenient.items.count == 1 && lenient.items[0].placement == .wall && lenient.items[0].count == 2 && lenient.items[0].relation == .none, "Brief decoding is lenient")
near(lenient.items[0].width, 1.2, "Missing size becomes a typical size")

print("PASS: \(passed) plan and design checks")
