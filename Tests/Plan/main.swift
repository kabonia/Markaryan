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

// MARK: Scanned window sills and saved presentations

check(legacyPlan.segments.allSatisfy { $0.elevation == nil }, "Old segments load without a sill height")
var frenchWindow = segment(.window, 1.5, 0, 2.7, 0, height: 2.2)
frenchWindow.elevation = 0.1
let sunroom = rectangle("Гостиная", 4, 3, doors: [segment(.door, 1, 3, 1.8, 3, height: 2.05)], windows: [frenchWindow])
let reloadedSunroom = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(sunroom))
check(reloadedSunroom.windows.first?.elevation == 0.1, "Scanned sill height survives saving")
func aiWindows(_ plan: FloorPlan) -> [[String: Any]] {
    guard let json = try? JSONSerialization.jsonObject(with: Data(PlanWalls.aiDescription(plan).utf8)) as? [String: Any],
          let walls = json["walls"] as? [[String: Any]] else { return [] }
    return walls.flatMap { ($0["windows"] as? [[String: Any]]) ?? [] }
}
let sunroomWindows = aiWindows(sunroom), bedroomWindows = aiWindows(bedroom)
check(sunroomWindows.count == 1 && sunroomWindows[0]["sill"] as? Double == 0.1 && sunroomWindows[0]["height"] as? Double == 2.2, "AI description: scanned sill and window height")
check(bedroomWindows.count == 1 && bedroomWindows[0]["sill"] == nil, "AI description: no sill when the scan did not measure it")

check(migrated.presentation == nil, "Old concepts have no saved presentation")
var presented = migrated
presented.presentation = SavedPresentation(createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), folder: presented.id.uuidString, pdf: "presentation.pdf",
                                           pictures: [.init(title: "Вид 1", file: "picture-1.jpg")], engine: "openrouter:google/gemini-3-pro-image")
let reloadedPresented = try JSONDecoder().decode(DesignProposal.self, from: JSONEncoder().encode(presented))
check(reloadedPresented.presentation == presented.presentation, "Saved presentation survives saving")
let forged = try aiDesign(#"{"title":"x","presentation":{"createdAt":0,"folder":"../../Documents","pdf":"a.pdf","pictures":[]},"items":[]}"#, bedroom, "Спальня")
check(forged.presentation == nil, "An AI answer cannot point at files on the iPhone")

// MARK: Plan screen in three steps

let fresh = PlanFlow(plan: bedroom, proposal: nil, hasPresentation: false, canRender: true)
check(fresh.initialStep == .measure && fresh.done == [.measure], "A new scan opens on the measurements")
check(PlanStep.allCases.allSatisfy { fresh.main(on: $0).action == .createDesign }, "Without a concept every step offers to create one")
check(fresh.main(on: .measure).title == "Создать дизайн по плану", "First design button")
var designed = bedroom
designed.proposals = [pair]
let ready = PlanFlow(plan: designed, proposal: pair, hasPresentation: false, canRender: true)
check(ready.initialStep == .design && ready.done == [.measure, .design], "A plan with a concept opens on the design")
check(ready.main(on: .measure).action == .goTo(.design), "Measurements lead on to the design")
check(ready.main(on: .design).action == .buildPresentation && ready.main(on: .result).action == .buildPresentation, "A concept leads to its presentation")
let finished = PlanFlow(plan: designed, proposal: pair, hasPresentation: true, canRender: true)
check(finished.initialStep == .result && finished.done == Set(PlanStep.allCases), "A finished presentation opens on the result")
check(finished.main(on: .design).action == .goTo(.result) && finished.main(on: .result).action == .orderRenovation, "After the presentation comes the renovation request")
let offline = PlanFlow(plan: designed, proposal: pair, hasPresentation: false, canRender: false)
check(offline.main(on: .design).action == .goTo(.result) && offline.main(on: .result).action == .orderRenovation, "Without picture engines the result offers the renovation")
var emptyConcept = pair
emptyConcept.furniture = []
let emptyFlow = PlanFlow(plan: designed, proposal: emptyConcept, hasPresentation: false, canRender: true)
check(emptyFlow.main(on: .design) == PlanMainButton(action: .createDesign, title: "Ещё вариант дизайна", icon: "wand.and.stars"), "A concept without a layout asks for another variant")
check(PlanFlow(plan: designed, proposal: nil, hasPresentation: true, canRender: true).done == [.measure, .design], "No finished result without a selected concept")
check(PlanStep.allCases.map(\.title) == ["Обмер", "Дизайн", "Результат"] && PlanStep.result.number == 3, "Step titles and numbers")

let calculations = PlanMaterials.calculations(bedroom)
check(calculations.count == 6 && Set(calculations.map(\.id)).count == 6, "Six calculators with distinct titles")
check(calculations[0].kind == .tiles && calculations[0].values["area"] == "12.00", "Floor area goes to the floor calculator")
check(calculations[2].kind == .paint && calculations[2].values["area"] == "37.80" && calculations[2].values["openings"] == "3.44", "Walls: perimeter × height, openings apart")
check(calculations[5].values["openings"] == "0" && calculations[5].values["area"] == "12.00", "Ceiling has no openings")

// MARK: Editing the plan by hand

func wallNumber(_ plan: FloorPlan, containing id: UUID) -> Int? {
    PlanWalls.numbered(plan).first { ($0.doors + $0.windows).contains { $0.segment.id == id } }?.number
}
let bedroomWindow = bedroom.windows[0], bedroomDoor = bedroom.doors[0]
check(PlanWalls.numbered(bedroom).first { $0.number == 3 }.map { $0.start == PlanPoint(x: 0, y: 0) && $0.end == PlanPoint(x: 4, y: 0) } == true, "Wall 3 of the bedroom is the top wall")
var withChest = designed
withChest.proposals[0].furniture.append(DesignFurniture(name: "Комод", kind: "storage", x: 3.4, y: 2.0, width: 1.0, depth: 0.45, rotation: 90, height: 0.85))
withChest.proposals[0].furniture.append(DesignFurniture(name: "Пуф", kind: "chair", x: 1.0, y: 2.0, width: 0.4, depth: 0.4, rotation: 0))
let longer = try PlanEditor.setWallLength(withChest, wall: 3, to: 4.5)
near(longer.area, 13.5, "Longer wall: the room grows")
near(longer.width, 4.5, "Longer wall: the far side moved")
check(longer.editedAt != nil, "An edited plan remembers when")
check(PlanWalls.numbered(longer).allSatisfy { abs($0.direction.x * $0.direction.y) < 1e-9 }, "Longer wall: corners stay square")
let movedWindow = longer.windows[0]
near(min(movedWindow.start.x, movedWindow.end.x), 2.0, "The window keeps its distance to the nearer corner")
near(max(movedWindow.start.x, movedWindow.end.x), 3.2, "The window keeps its width")
check(longer.doors[0].start.distance(to: bedroomDoor.start) < 1e-9 && longer.doors[0].end.distance(to: bedroomDoor.end) < 1e-9, "The door near the corner that stays does not move")
let chest = longer.proposals[0].furniture.first { $0.name == "Комод" }!, pouf = longer.proposals[0].furniture.first { $0.name == "Пуф" }!
near(chest.x, 3.9, "Furniture in the far half moves with the wall")
near(pouf.x, 1.0, "Furniture in the near half stays")
let shorter = try PlanEditor.setWallLength(bedroom, wall: 3, to: 3.0)
near(shorter.area, 9, "Shorter wall: the room shrinks")
near(min(shorter.windows[0].start.x, shorter.windows[0].end.x), 0.5, "The window slides with the corner it is near")
check(LayoutSpace(plan: shorter).walls.count == 4, "The shortened room still has four walls")
do { _ = try PlanEditor.setWallLength(bedroom, wall: 3, to: 0.2); check(false, "A 20 cm wall is refused") } catch { check(error as? PlanEditor.EditError != nil, "A 20 cm wall is refused") }
do { _ = try PlanEditor.setWallLength(bedroom, wall: 3, to: 0.6); check(false, "A wall too short for its door is refused") } catch { check((error as? PlanEditor.EditError).map { if case .opening = $0 { return true } else { return false } } == true, "A wall too short for its door is refused: \(error)") }
do { _ = try PlanEditor.setWallLength(bedroom, wall: 9, to: 3); check(false, "Unknown wall") } catch { check(error as? PlanEditor.EditError == .noWall, "Unknown wall is refused") }
let wider = try PlanEditor.setWallLength(lShaped, wall: 1, to: 6)
near(wider.area, 18, "L-shaped room: the top wall grows the right wing")
let narrower = try PlanEditor.setWallLength(lShaped, wall: 1, to: 3.5)
near(narrower.area, 13, "L-shaped room: the right wing can shrink")
do { _ = try PlanEditor.setWallLength(lShaped, wall: 1, to: 2.5); check(false, "A wall turned inside out is refused") } catch { check(error as? PlanEditor.EditError == .outline, "A wall turned inside out is refused") }
let sameLength = try PlanEditor.setWallLength(bedroom, wall: 3, to: 4.0)
check(sameLength.editedAt == nil, "The same length changes nothing")

let lower = try PlanEditor.setCeilingHeight(bedroom, to: 2.2)
check(lower.ceilingHeight == 2.2 && lower.walls.allSatisfy { $0.height == 2.2 }, "Ceiling height goes to the walls")
near(lower.windows[0].height, 1.3, "A window that would reach the ceiling gets lower")
near(lower.doors[0].height, 2.05, "A door that fits keeps its height")
do { _ = try PlanEditor.setCeilingHeight(bedroom, to: 1.5); check(false, "Too low ceiling") } catch { check(true, "A 1.5 m ceiling is refused") }

let windowSpec = PlanEditor.spec(of: bedroomWindow.id, in: bedroom)
check(windowSpec == PlanEditor.OpeningSpec(kind: .window, wall: 3, from: 1.5, width: 1.2, height: 1.5, sill: 0.85), "Window as the editor shows it: \(String(describing: windowSpec))")
let doorSpec = PlanEditor.spec(of: bedroomDoor.id, in: bedroom)!
check(doorSpec.wall == 1 && doorSpec.hingeAtEnd, "Door on wall 1, hinged at the far end of the opening")
near(doorSpec.from, 2.2, "Door position from the start of wall 1")
near(doorSpec.width, 0.8, "Door width")
let added = try PlanEditor.addOpening(bedroom, .window(wall: 2, from: 0.9))
check(added.plan.windows.count == 2 && wallNumber(added.plan, containing: added.id) == 2, "A window is added to wall 2")
check(PlanEditor.spec(of: added.id, in: added.plan) == .window(wall: 2, from: 0.9), "The added window reads back as it was asked")
func refused(_ spec: PlanEditor.OpeningSpec, _ name: String) {
    do { _ = try PlanEditor.addOpening(bedroom, spec); check(false, name) } catch { check(error is PlanEditor.EditError, name) }
}
refused(.window(wall: 3, from: 2.0), "A window over another window is refused")
refused(PlanEditor.OpeningSpec(kind: .window, wall: 2, from: 0.5, width: 1.0, height: 2.0, sill: 0.85), "A window above the ceiling is refused")
refused(.window(wall: 3, from: 3.5), "A window past the end of the wall is refused")
refused(PlanEditor.OpeningSpec(kind: .door, wall: 2, from: 0.5, width: 0.2, height: 2.0, sill: 0), "A 20 cm door is refused")
var flipped = doorSpec
flipped.from = 0.5; flipped.hingeAtEnd = false
let movedDoor = try PlanEditor.updateOpening(bedroom, id: bedroomDoor.id, to: flipped)
check(movedDoor.doors.count == 1 && movedDoor.doors[0].id == bedroomDoor.id, "Updating keeps the same door")
check(movedDoor.doorSwing(movedDoor.doors[0]).hinge == PlanPoint(x: 3.5, y: 3), "The door moved and hangs on the other side")
check(PlanEditor.removeOpening(bedroom, id: bedroomWindow.id).windows.isEmpty, "A window is removed")
if let contourRoom = FloorPlanBuilder.fromContour([turned(0, 0), turned(5, 0), turned(5, 3), turned(0, 3)], name: "Контур") {
    let withDoor = try PlanEditor.addOpening(contourRoom, .door(wall: 1, from: 1))
    check(withDoor.plan.doors.count == 1 && !LayoutSpace(plan: withDoor.plan).entrances.isEmpty, "An AR contour plan gets a door")
} else { check(false, "Contour plan for doors") }

let skewed = room("Кривая", [(0, 0), (4, 0.15), (4.1, 3), (0, 3)])
var skewedDesign = skewed
skewedDesign.proposals = [pair]
skewedDesign.proposals[0].furniture = [DesignFurniture(name: "Комод", kind: "storage", x: 2, y: 0.33, width: 1, depth: 0.45, rotation: atan2(0.15, 4) * 180 / .pi, height: 0.85)]
let straight = try PlanEditor.straightened(skewedDesign)
check(straight.corners == 3, "Three corners of the skewed room moved, got \(straight.corners)")
check(straight.plan.walls.allSatisfy { abs($0.start.x - $0.end.x) < 1e-9 || abs($0.start.y - $0.end.y) < 1e-9 }, "Straightened walls run along the axes")
check(PlanMath.isSimple(straight.plan.floorPolygon) && straight.plan.floorPolygon.count == 4, "Straightened outline is a simple quadrangle")
let squaredChest = straight.plan.proposals[0].furniture[0]
check(abs(squaredChest.rotation) < 0.01 || abs(squaredChest.rotation - 360) < 0.01, "Furniture turns with its wall: \(squaredChest.rotation)")
near(squaredChest.y - straight.plan.floorPolygon.map(\.y).min()!, 0.33 - 0.075, "Furniture keeps its distance from the wall", 0.03)
let alreadySquare = try PlanEditor.straightened(bedroom)
check(alreadySquare.corners == 0, "A square room has nothing to straighten")
let notched = room("Почти прямая", [(0, 0), (2, 0.01), (4, 0), (4, 3), (0, 3)])
let merged = try PlanEditor.straightened(notched)
check(merged.plan.floorPolygon.count == 4 && merged.corners >= 1, "A corner that is almost straight disappears")
let triangle = try PlanEditor.straightened(room("Треугольник", [(0, 0), (4, 0), (4, 3)]))
check(triangle.corners == 0, "A slanted wall far from the axes stays")
do { _ = try PlanEditor.straightened(noPolygon); check(false, "No outline") } catch { check(true, "A plan without a floor outline is not straightened") }
check(PlanMath.isSimple([PlanPoint(x: 0, y: 0), PlanPoint(x: 2, y: 0), PlanPoint(x: 2, y: 2), PlanPoint(x: 0, y: 2)]), "A square is simple")
check(!PlanMath.isSimple([PlanPoint(x: 0, y: 0), PlanPoint(x: 2, y: 2), PlanPoint(x: 2, y: 0), PlanPoint(x: 0, y: 2)]), "A bow tie is not")

check(PlanEditor.parseMeters("3,42") == 3.42 && PlanEditor.parseMeters("3.42 м") == 3.42, "Metres with a comma or a point")
check(PlanEditor.parseMeters("342") == 3.42 && PlanEditor.parseMeters("80 см") == 0.8 && PlanEditor.parseMeters("3420") == 3.42, "Centimetres and millimetres")
check(PlanEditor.parseMeters("") == nil && PlanEditor.parseMeters("абв") == nil, "Not a number")

let savedEdit = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(longer))
check(savedEdit.editedAt != nil, "The edit time survives saving")

// MARK: Moving furniture by hand

check(FurnitureEditor.normalized(-90) == 270 && FurnitureEditor.normalized(450) == 90 && FurnitureEditor.normalized(360) == 0, "Angles in 0..<360")
let dresser = DesignFurniture(name: "Комод", kind: "storage", x: 2, y: 1.5, width: 1.0, depth: 0.45, rotation: 0, height: 0.85)
let atTop = FurnitureEditor.move(dresser, to: PlanPoint(x: 2, y: 0.35), walls: bedroomWalls)
near(atTop.y, 0.225 + LayoutRules.wallGap, "Near a wall the item stands flush with it")
check(atTop.rotation == 0 && atTop.wall == 3, "Back to the top wall")
let inCorner = FurnitureEditor.move(dresser, to: PlanPoint(x: 0.6, y: 0.35), walls: bedroomWalls)
near(inCorner.x, 0.5 + LayoutRules.wallGap, "Near the end of the wall it slides into the corner")
near(inCorner.y, 0.225 + LayoutRules.wallGap, "…and stays flush with the wall")
let inMiddle = FurnitureEditor.move(dresser, to: PlanPoint(x: 2, y: 1.6), walls: bedroomWalls)
check(inMiddle.x == 2 && inMiddle.y == 1.6 && inMiddle.wall == nil, "In the middle of the room the item goes where the finger is")
let free = FurnitureEditor.move(dresser, to: PlanPoint(x: 2, y: 0.35), walls: bedroomWalls, snap: false)
check(free.y == 0.35 && free.wall == nil, "Without snapping nothing is adjusted")
let mirror = FurnitureEditor.move(DesignFurniture(name: "Зеркало", kind: "mirror", x: 0, y: 0, width: 0.6, depth: 0.03, rotation: 45), to: PlanPoint(x: 2, y: 1.2), walls: bedroomWalls)
near(mirror.y, 0.015 + LayoutRules.wallGap, "A mirror always hangs on the nearest wall")
check(mirror.rotation == 0, "A mirror faces the room")
let movedRug = FurnitureEditor.move(DesignFurniture(name: "Ковёр", kind: "decor", x: 0, y: 0, width: 2, depth: 1.4, rotation: 10), to: PlanPoint(x: 1.1, y: 0.8), walls: bedroomWalls)
check(movedRug.x == 1.1 && movedRug.y == 0.8 && movedRug.rotation == 10, "A rug goes exactly where it is put")
let quarter = FurnitureEditor.rotated(atTop, by: 90, walls: bedroomWalls)
check(quarter.rotation == 90 && quarter.wall == 3, "A quarter turn at a wall keeps the item at the wall")
near(quarter.y, 0.5 + LayoutRules.wallGap, "…flush with its other side")
let slanted = FurnitureEditor.rotated(atTop, by: 15, walls: bedroomWalls)
check(slanted.rotation == 15 && slanted.wall == nil && slanted.y == atTop.y, "A small turn is free")

let bedIndex = pair.furniture.firstIndex { $0.model == "bed" }!
check(FurnitureEditor.item(at: PlanPoint(x: bed.x, y: bed.y), in: pair.furniture) == bedIndex, "A finger on the bed picks the bed")
let stand = pair.furniture.firstIndex { $0.name == "Тумба" }!
check(FurnitureEditor.item(at: PlanPoint(x: pair.furniture[stand].x, y: pair.furniture[stand].y), in: pair.furniture) == stand, "A finger on a nightstand picks it")
let withRug = [DesignFurniture(name: "Ковёр", kind: "decor", x: 2, y: 1.5, width: 2, depth: 1.4, rotation: 0), DesignFurniture(name: "Стул", kind: "chair", x: 2, y: 1.5, width: 0.45, depth: 0.5, rotation: 0)]
check(FurnitureEditor.item(at: PlanPoint(x: 2, y: 1.5), in: withRug) == 1, "A chair on a rug is picked before the rug")
check(FurnitureEditor.item(at: PlanPoint(x: 3.9, y: 2.9), in: withRug) == nil, "An empty spot picks nothing")

let wardrobe = FurnitureEditor.placeNew(FurnitureCatalog.all.first { $0.name == "Шкаф" }!.item, plan: bedroom, furniture: pair.furniture)
let wardrobeSpace = LayoutSpace(plan: bedroom)
check(wardrobe.wall != nil && wardrobeSpace.isInside(wardrobe.footprint) && !wardrobeSpace.blocksDoor(wardrobe), "A new wardrobe stands at a free wall")
check(!pair.furniture.filter(\.blocksFloor).contains { $0.footprint.grown(by: -0.01).overlaps(wardrobe.footprint.grown(by: -0.01)) }, "…without standing on other furniture")
let newRug = FurnitureEditor.placeNew(FurnitureCatalog.all.first { $0.name == "Ковёр" }!.item, plan: bedroom, furniture: [])
check(abs(newRug.x - 2) < 0.1 && abs(newRug.y - 1.5) < 0.1, "A rug goes to the middle of the room: \(newRug.x), \(newRug.y)")
let huge = FurnitureEditor.placeNew(DesignFurniture(name: "Диван 5 м", kind: "sofa", x: 0, y: 0, width: 5, depth: 1, rotation: 0), plan: bedroom, furniture: [])
check(huge.x == 2 && huge.y == 1.5, "An item that fits nowhere waits in the middle")

let bathroomCatalog = FurnitureCatalog.entries(for: .bathroom)
check(bathroomCatalog.first?.name == "Унитаз" && !bathroomCatalog.contains { $0.kind == "sofa" }, "Bathroom catalogue: its own items first, no sofa")
check(!FurnitureCatalog.entries(for: .kitchen).contains { $0.kind == "sink" }, "Kitchen catalogue follows the room rules")
check(FurnitureCatalog.all.first { $0.name == "Торшер" }!.item.model == "floorlamp" && FurnitureCatalog.all.first { $0.name == "Подвесной светильник" }!.item.model == "pendant"
      && FurnitureCatalog.all.first { $0.name == "Водонагреватель" }!.item.model == "boiler", "Catalogue items are drawn as what they are")
check(Set(FurnitureCatalog.all.map(\.id)).count == FurnitureCatalog.all.count, "Catalogue names are unique")

let overlapping = [DesignFurniture(name: "Шкаф", kind: "storage", x: 2, y: 0.4, width: 1.8, depth: 0.6, rotation: 0), DesignFurniture(name: "Комод", kind: "storage", x: 2.3, y: 0.5, width: 1, depth: 0.45, rotation: 0)]
check(LayoutCheck.issues(plan: bedroom, furniture: overlapping).contains { $0.kind == .overlap && $0.items == [0, 1] }, "A problem names the items it is about")

let viewport = PlanViewport(plan: bedroom, width: 400, height: 300, margin: 0)
let corner = viewport.screen(PlanPoint(x: 4, y: 3))
check(corner.x == 400 && corner.y == 300 && viewport.plan(x: 200, y: 150) == PlanPoint(x: 2, y: 1.5), "Plan and screen map onto each other")
let framed = PlanViewport(plan: lShaped, width: 600, height: 380, margin: 34)
let there = framed.screen(PlanPoint(x: 1.3, y: 2.7)), back = framed.plan(x: there.x, y: there.y)
near(back.x, 1.3, "Screen to plan and back: x", 1e-9)
near(back.y, 2.7, "Screen to plan and back: y", 1e-9)

var stale = designed
stale.proposals[0].presentation = SavedPresentation(createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), folder: "x", pdf: "a.pdf", pictures: [], engine: nil)
stale.proposals[0].editedAt = Date(timeIntervalSinceReferenceDate: 800_000_100)
let staleFlow = PlanFlow(plan: stale, proposal: stale.proposals[0], hasPresentation: true, canRender: true)
check(staleFlow.presentationOutdated && !staleFlow.done.contains(.result), "A presentation made before an edit is out of date")
check(staleFlow.main(on: .result) == PlanMainButton(action: .buildPresentation, title: "Обновить презентацию", icon: "arrow.triangle.2.circlepath"), "…and the result offers to update it")
stale.proposals[0].editedAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
check(!PlanFlow(plan: stale, proposal: stale.proposals[0], hasPresentation: true, canRender: true).presentationOutdated, "An older edit does not matter")

// MARK: Walls drawn outward from the scanned line

let thick = WallBody.standardThickness
func samePoint(_ a: PlanPoint, _ b: PlanPoint) -> Bool { a.distance(to: b) < 1e-9 }
let bedroomBody = WallBody(plan: bedroom)
check(bedroomBody.pieces.count == 6, "Bedroom walls: four walls, the door and the window split two of them, got \(bedroomBody.pieces.count)")
check(bedroomBody.pieces.filter(\.capStart).count + bedroomBody.pieces.filter(\.capEnd).count == 4, "Jambs only at the door and the window")
check(bedroomBody.pieces.allSatisfy { piece in
    let inner = piece.innerEnd - piece.innerStart, outer = piece.outerEnd - piece.outerStart
    return abs(inner.cross(outer)) < 1e-9 && abs((piece.outerStart - piece.innerStart).dot(piece.outward) - thick) < 1e-9 || !piece.capStart
}, "The outer face is parallel to the inner one, a wall thickness out")
let outerCorners = bedroomBody.pieces.flatMap { [$0.outerStart, $0.outerEnd] }
for corner in [PlanPoint(x: -thick, y: -thick), PlanPoint(x: 4 + thick, y: -thick), PlanPoint(x: 4 + thick, y: 3 + thick), PlanPoint(x: -thick, y: 3 + thick)] {
    check(outerCorners.contains { samePoint($0, corner) }, "Mitred outer corner at \(corner)")
}
check(bedroomBody.pieces.allSatisfy { piece in [piece.innerStart, piece.innerEnd].allSatisfy { p in PlanMath.distance(p, toSegment: PlanPoint(x: 0, y: 0), PlanPoint(x: 4, y: 0)) < 1e-9 || PlanMath.distance(p, toSegment: PlanPoint(x: 4, y: 0), PlanPoint(x: 4, y: 3)) < 1e-9 || PlanMath.distance(p, toSegment: PlanPoint(x: 4, y: 3), PlanPoint(x: 0, y: 3)) < 1e-9 || PlanMath.distance(p, toSegment: PlanPoint(x: 0, y: 3), PlanPoint(x: 0, y: 0)) < 1e-9 } }, "The inner face is the scanned line: the room keeps its size")
let windowGap = bedroomBody.gaps.first { $0.opening.kind == .window }!
check(samePoint(windowGap.innerStart, PlanPoint(x: 1.5, y: 0)) && samePoint(windowGap.innerEnd, PlanPoint(x: 2.7, y: 0)) && samePoint(windowGap.outward, PlanPoint(x: 0, y: -1)), "The window gap and the outward side")
check(bedroomBody.gaps.count == 2, "Door and window are gaps")
let solidBody = WallBody(plan: bedroom, cut: [])
check(solidBody.pieces.count == 4 && solidBody.gaps.count == 2 && solidBody.pieces.allSatisfy { !$0.capStart && !$0.capEnd }, "Without cuts: four closed walls, openings still known")
let lBody = WallBody(plan: lShaped)
check(lBody.pieces.count == 6, "L-shaped room: six walls")
check(lBody.pieces.contains { samePoint($0.outerEnd, PlanPoint(x: 3 + thick, y: 2 + thick)) } && lBody.pieces.contains { samePoint($0.outerStart, PlanPoint(x: 3 + thick, y: 2 + thick)) }, "The inner corner of the L is mitred too")
var openSide = bedroom
openSide.segments.removeAll { $0.kind == .wall && $0.start == PlanPoint(x: 4, y: 0) }
let openBody = WallBody(plan: openSide)
check(!openBody.pieces.contains { abs($0.innerStart.x - 4) < 1e-9 && abs($0.innerEnd.x - 4) < 1e-9 }, "A side without a scanned wall stays open")
check(openBody.pieces.filter { $0.capEnd && samePoint($0.innerEnd, PlanPoint(x: 4, y: 0)) }.count == 1, "The wall next to the open side ends with a jamb")
let loopBody = WallBody(plan: noPolygon)
check(loopBody.outline.count == 4 && loopBody.pieces.count == 6, "Without a floor outline the walls themselves make the loop")
check(LayoutRules.wallGap < 0.05, "Furniture stands just off the inner face of the wall")

// MARK: Electrics

let bedroomPower = ElectricPlanner.plan(for: designed, proposal: pair, room: .bedroom)
check(bedroomPower.switches.count == 1 && bedroomPower.switches[0].height == ElectricPlanner.switchHeight, "One switch by the bedroom door at 0.9 m")
near(bedroomPower.switches[0].position.x, 1.95, "The switch is at the latch side, 15 cm from the door")
near(bedroomPower.switches[0].position.y, 3, "…on the door's wall")
check(bedroomPower.points.contains { $0.purpose == "у кровати" && $0.kind == .doubleSocket && $0.height == 0.7 }, "A double socket by the bed, even with the bed in a corner")
let bedRoom = rectangle("Спальня", 4, 3.5, doors: [segment(.door, 3.0, 3.5, 3.8, 3.5, height: 2.05)], windows: [segment(.window, 1.0, 0, 2.2, 0, height: 1.5)])
var bedLayout = pair
bedLayout.furniture = [DesignFurniture(name: "Кровать", kind: "bed", x: 1.055, y: 1.75, width: 1.6, depth: 2.05, rotation: 270),
                       DesignFurniture(name: "Прикроватная тумба", kind: "storage", x: 0.23, y: 0.705, width: 0.45, depth: 0.4, rotation: 270, height: 0.55),
                       DesignFurniture(name: "Прикроватная тумба", kind: "storage", x: 0.23, y: 2.795, width: 0.45, depth: 0.4, rotation: 270, height: 0.55)]
let bedSockets = ElectricPlanner.plan(for: bedRoom, proposal: bedLayout, room: .bedroom).points.filter { $0.purpose == "у кровати" }
check(bedSockets.count == 2 && bedSockets.allSatisfy { abs($0.position.x) < 1e-6 && $0.kind == .doubleSocket && $0.height == 0.7 }, "Double sockets above both nightstands, on the head wall")
check(bedSockets.map(\.position.y).sorted().enumerated().allSatisfy { index, y in abs(y - [0.75, 2.75][index]) < 0.06 }, "…at the sides of the bed head: \(bedSockets.map(\.position.y))")
check(bedroomPower.sockets.filter { $0.height < 1.5 }.count >= 4, "At least one socket per 4 m of the perimeter: \(bedroomPower.sockets.count)")
check(bedroomPower.sockets.allSatisfy { s in !(abs(s.position.y - 3) < 1e-6 && s.position.x > 0.9 && s.position.x < 1.9) && !(abs(s.position.y) < 1e-6 && s.position.x > 1.4 && s.position.x < 2.8) }, "No socket in the door or under the window")
check(bedroomPower.lights.count == 6 && bedroomPower.lights.allSatisfy { bedroom.contains($0.position) }, "Six ceiling lights inside the room")
check(bedroomPower.circuits.map(\.title) == ["Освещение", "Розетки"] && bedroomPower.circuits[1].breaker.contains("УЗО"), "Lighting and socket circuits, sockets through an RCD")
check(bedroomPower.sockets.allSatisfy { s in bedroomWalls.contains { PlanMath.distance(s.position, toSegment: $0.start, $0.end) < 1e-6 } }, "Sockets sit on the walls")

let bathDesign = OfflineDesigner.propose(plan: bigBathroom, style: "Современный", purpose: "Ванная", wishes: "ванна, стиральная машина")!
let bathPower = ElectricPlanner.plan(for: bigBathroom, proposal: bathDesign, room: .bathroom)
check(bathPower.switches.count == 1 && !bigBathroom.contains(bathPower.switches[0].position), "The bathroom switch is outside, by the door")
check(!bathPower.sockets.isEmpty && bathPower.sockets.allSatisfy { $0.kind == .wetSocket }, "Bathroom sockets are IP44")
let bath = bathDesign.furniture.first { $0.model == "bathtub" }!
check(bathPower.sockets.allSatisfy { bath.footprint.distance(to: $0.position) >= 0.55 }, "No socket within 0.6 m of the bath")
check(bathPower.circuits.contains { $0.title == "Стиральная машина" && $0.breaker.contains("УЗО") }, "The washer has its own RCD circuit")
check(bathPower.notes.contains { $0.contains("IP44") }, "Bathroom notes mention IP44")

let kitchenDesign = OfflineDesigner.propose(plan: kitchen, style: "Современный", purpose: "Кухня", wishes: "")!
let kitchenPower = ElectricPlanner.plan(for: kitchen, proposal: kitchenDesign, room: .kitchen)
check(kitchenPower.count(.powerSocket) == 1 && kitchenPower.circuits.contains { $0.title == "Варочная панель" && $0.breaker == "C32" }, "A 32 A socket and circuit for the hob")
check(kitchenPower.points.filter { $0.purpose == "над столешницей" && $0.height == 1.1 }.count >= 2, "Work sockets above the worktop")
check(kitchenPower.points.contains { $0.purpose == "холодильник" }, "A socket for the fridge")
check(kitchenPower.notes.contains { $0.contains("3×6") }, "The hob cable is in the notes")

let livingDesign = OfflineDesigner.propose(plan: lLiving, style: "Современный", purpose: "Гостиная", wishes: "")!
let livingPower = ElectricPlanner.plan(for: lLiving, proposal: livingDesign, room: .living)
check(livingPower.sockets.filter { $0.height < 1.5 }.count >= Int((lLiving.perimeter / 4).rounded(.up)), "Living room: the perimeter rule")
check(livingPower.count(.tvBlock) == 1, "A TV block behind the TV")
let hallDesign = OfflineDesigner.propose(plan: hall, style: "Современный", purpose: "Прихожая", wishes: "")!
check(ElectricPlanner.plan(for: hall, proposal: hallDesign, room: .hall).points.contains { $0.purpose == "у входа" && $0.kind == .socket }, "A socket by the entrance of the hall")
check(ElectricPlanner.spotLights(room("Кладовка", [(0, 0), (1.2, 0), (1.2, 1.0), (0, 1.0)])).count == 1, "A small room gets one light in the middle")
check(ElectricPlanner.plan(for: bedroom, proposal: nil, room: .bedroom).sockets.count >= 4, "Without a concept the room still gets its sockets")

// MARK: Tiles

check(TileSize.parse("Керамогранит 600×1200, матовый") == TileSize(width: 0.6, length: 1.2), "Tile size in millimetres from a finish")
check(TileSize.parse("плитка 30x60 см") == TileSize(width: 0.3, length: 0.6) && TileSize.parse("кафель 20х20") == TileSize(width: 0.2, length: 0.2), "Tile size in centimetres")
check(TileSize.parse("мрамор") == nil, "No size in the finish")
func finish(_ material: String) -> DesignFinish { var value = DesignFinish(); value.material = material; return value }
check(TileLayout.isTiled(.bathroom, nil) && !TileLayout.isTiled(.living, finish("Ламинат")) && TileLayout.isTiled(.kitchen, finish("Керамогранит")), "Which floors are tiled")
let floorTiles = TileLayout.floor(bedroom)
let laidArea = floorTiles.pieces.reduce(0) { $0 + abs(PlanMath.signedArea2($1.polygon)) / 2 }
check(laidArea > 11.85 && laidArea <= 12 + 1e-9, "The tiles cover the floor less the joints: \(laidArea)")
check(floorTiles.whole + floorTiles.cut == floorTiles.pieces.count && floorTiles.whole >= 20, "Whole and cut tiles: \(floorTiles.whole) + \(floorTiles.cut)")
check((floorTiles.narrowestCut ?? 1) >= 0.2, "No sliver cuts: the narrowest is \(floorTiles.narrowestCut ?? 0) m")
check(floorTiles.toBuy == Int((Double(floorTiles.pieces.count) * 1.1).rounded(.up)) && abs(floorTiles.buyArea - Double(floorTiles.toBuy) * 0.36) < 1e-9, "Tiles to buy with a 10 % reserve")
check(floorTiles.pieces.allSatisfy { $0.polygon.allSatisfy { p in p.x >= -1e-9 && p.x <= 4 + 1e-9 && p.y >= -1e-9 && p.y <= 3 + 1e-9 } }, "Tiles stay inside the room")
let lTiles = TileLayout.floor(lShaped)
let lArea = lTiles.pieces.reduce(0) { $0 + abs(PlanMath.signedArea2($1.polygon)) / 2 }
check(lArea > 15.8 && lArea <= 16 + 1e-9 && (lTiles.narrowestCut ?? 1) >= 0.1, "L-shaped floor is tiled without slivers: \(lArea), \(lTiles.narrowestCut ?? 0)")
check(lTiles.pieces.allSatisfy { piece in lShaped.contains(piece.polygon.reduce(PlanPoint(x: 0, y: 0)) { $0 + $1 } * (1 / Double(piece.polygon.count))) }, "Every L-floor tile lies in the room")
let wallTiles = TileLayout.wall(length: 2.6, height: 2.7, holes: [(0.4, 0, 1.2, 2.0)])
let wallArea = wallTiles.pieces.reduce(0) { total, piece in
    let p = piece.polygon
    return total + (p[1].x - p[0].x) * (p[2].y - p[1].y)
}
near(wallTiles.area, 2.6 * 2.7 - 0.8 * 2.0, "Wall area without the door")
check(wallTiles.pieces.allSatisfy { $0.polygon[0].y >= 0 && $0.polygon[2].y <= 2.7 + 1e-9 } && wallTiles.pieces.contains { abs($0.polygon[0].y) < 1e-9 && $0.whole }, "Wall rows start from the floor with whole tiles")
check(wallArea > wallTiles.area, "Cut pieces around the door are counted")
check(!wallTiles.pieces.contains { p in p.polygon[0].x >= 0.4 && p.polygon[1].x <= 1.2 && p.polygon[2].y <= 2.0 }, "No tile inside the door opening")
check(TileLayout.positiveRemainder(-0.1, 0.602) > 0.5, "Remainder is positive")

// MARK: DXF for CAD

struct DXFEntity { let type: String; let layer: String; let values: [(Int, String)]
    func value(_ code: Int) -> String? { values.first { $0.0 == code }?.1 }
}
func dxfPairs(_ text: String) -> [(Int, String)] {
    let lines = text.components(separatedBy: "\r\n")
    var pairs: [(Int, String)] = []
    var index = 0
    while index + 1 < lines.count {
        if let code = Int(lines[index].trimmingCharacters(in: .whitespaces)) { pairs.append((code, lines[index + 1])) }
        index += 2
    }
    return pairs
}
func dxfEntities(_ pairs: [(Int, String)]) -> [DXFEntity] {
    guard let start = pairs.firstIndex(where: { $0.0 == 2 && $0.1 == "ENTITIES" }) else { return [] }
    var result: [DXFEntity] = []
    var current: (String, [(Int, String)])?
    for pair in pairs[(start + 1)...] {
        if pair.0 == 0 {
            if let current { result.append(DXFEntity(type: current.0, layer: current.1.first { $0.0 == 8 }?.1 ?? "", values: current.1)) }
            if pair.1 == "ENDSEC" { break }
            current = (pair.1, [])
        } else { current?.1.append(pair) }
    }
    return result
}
check(DXFWriter.number(1500) == "1500" && DXFWriter.number(12.34) == "12.3" && DXFWriter.number(-0.0001) == "0", "DXF numbers in millimetres")
check(DXFWriter.clean("1600×2000 \u{2011} м²") == "1600x2000 - м2", "Characters CP1251 lacks are replaced")
let bedroomDXF = PlanDXF.writer(plan: designed, proposal: pair, room: .bedroom)
let dxfText = bedroomDXF.document
let pairs = dxfPairs(dxfText)
check(pairs.contains { $0.0 == 1 && $0.1 == "AC1009" } && pairs.contains { $0.0 == 3 && $0.1 == "ANSI_1251" }, "DXF R12 in Windows-1251")
check(dxfText.hasSuffix("0\r\nEOF\r\n"), "DXF ends with EOF")
let layerNames = Set(pairs.indices.compactMap { i in i > 0 && pairs[i - 1] == (0, "LAYER") && pairs[i].0 == 2 ? pairs[i].1 : nil })
check(layerNames == Set(PlanDXF.layers.map(\.name)) && layerNames.count == 11, "Every layer is declared: \(layerNames.sorted())")
let entities = dxfEntities(pairs)
check(entities.filter { $0.type == "LINE" && $0.layer == PlanDXF.Layer.walls }.count == 16, "Wall faces and jambs: \(entities.filter { $0.type == "LINE" && $0.layer == PlanDXF.Layer.walls }.count)")
check(entities.filter { $0.type == "SOLID" && $0.layer == PlanDXF.Layer.wallFill }.count == 6, "Wall fill")
check(entities.contains { $0.type == "LINE" && $0.layer == PlanDXF.Layer.walls && $0.value(10) == "0" && $0.value(20) == "0" && $0.value(11) == "1500" && $0.value(21) == "0" }, "The inner face of the top wall up to the window, in millimetres")
check(entities.contains { $0.type == "LINE" && $0.value(20) == "-3000" }, "y is flipped: the bottom wall is at -3000")
check(entities.contains { $0.type == "ARC" && $0.layer == PlanDXF.Layer.doors && $0.value(40) == "800" }, "The door swing is an arc of the door width")
check(entities.filter { $0.type == "POLYLINE" && $0.layer == PlanDXF.Layer.furniture }.count == pair.furniture.count, "Every item of the concept is a polyline")
check([PlanDXF.Layer.sockets, PlanDXF.Layer.switches, PlanDXF.Layer.lights].allSatisfy { layer in entities.contains { $0.layer == layer } }, "Electrics are on their layers")
check(!entities.contains { $0.layer == PlanDXF.Layer.tiles }, "No tiles on a bedroom floor")
check(entities.contains { $0.type == "TEXT" && $0.value(1) == "Спальня" }, "The room name is on the plan")
check(dxfEntities(dxfPairs(PlanDXF.writer(plan: bigBathroom, proposal: bathDesign, room: .bathroom).document)).contains { $0.layer == PlanDXF.Layer.tiles }, "Bathroom floor tiles are on their layer")
let dxfData = bedroomDXF.data
check(String(data: dxfData, encoding: .windowsCP1251) == dxfText && dxfData.count == dxfText.unicodeScalars.count, "The file is Windows-1251, one byte a character")
let socketArcs = entities.filter { $0.type == "ARC" && $0.layer == PlanDXF.Layer.sockets }
check(!socketArcs.isEmpty && socketArcs.allSatisfy { arc in
    guard let start = Double(arc.value(50) ?? ""), let end = Double(arc.value(51) ?? "") else { return false }
    return abs((end - start) - 180) < 0.5
}, "Socket symbols are half circles")

// MARK: Apartment from one scan

let apartmentID = UUID()
/// A room as a multi-room scan gives it: corners in the scan's frame (turned as the iPhone stood), normalised on its own.
func scanned(_ name: String, _ outline: [(Double, Double)], doors: [PlanSegment] = [], order: Double) -> FloorPlan {
    let turn = 0.4, c = cos(turn), s = sin(turn)
    func scan(_ p: PlanPoint) -> PlanPoint { PlanPoint(x: p.x * c - p.y * s + 10, y: p.x * s + p.y * c - 4) }
    var plan = room(name, outline, doors: doors)
    plan.segments = plan.segments.map { var segment = $0; segment.start = scan(segment.start); segment.end = scan(segment.end); return segment }
    plan.floorPolygon = plan.floorPolygon.map(scan)
    var normalized = FloorPlanBuilder.normalize(plan)
    normalized.apartmentID = apartmentID
    normalized.apartmentName = "Квартира 1"
    normalized.createdAt = Date(timeIntervalSinceReferenceDate: order)
    return normalized
}
let roomA = scanned("Гостиная", [(0, 0), (4, 0), (4, 3), (0, 3)], doors: [segment(.door, 4, 1.0, 4, 1.9)], order: 1)
let roomB = scanned("Спальня", [(4.12, 0), (7.12, 0), (7.12, 3), (4.12, 3)], doors: [segment(.door, 4.12, 1.0, 4.12, 1.9)], order: 2)
let apartments = Apartment.group([roomB, bedroom, roomA])
check(apartments.count == 1 && apartments[0].rooms.map(\.name) == ["Гостиная", "Спальня"] && apartments[0].name == "Квартира 1", "Rooms of one scan make one apartment, in scan order")
near(apartments[0].area, 21, "Apartment area is the sum of its rooms", 1e-6)
let flat = apartments[0].layout
near(flat.width, 7.12, "The apartment is put back together along its longest wall: width", 1e-6)
near(flat.depth, 3, "…and depth", 1e-6)
near(flat.rooms[0].area, 12, "Room areas survive", 1e-6)
func gap(_ a: [PlanPoint], _ b: [PlanPoint]) -> Double {
    func edges(_ p: [PlanPoint]) -> [(PlanPoint, PlanPoint)] { p.indices.map { (p[$0], p[($0 + 1) % p.count]) } }
    let one = a.flatMap { point in edges(b).map { PlanMath.distance(point, toSegment: $0.0, $0.1) } }
    let two = b.flatMap { point in edges(a).map { PlanMath.distance(point, toSegment: $0.0, $0.1) } }
    return (one + two).min() ?? 0
}
near(gap(flat.rooms[0].plan.floorPolygon, flat.rooms[1].plan.floorPolygon), 0.12, "The partition between the rooms is as scanned", 1e-6)
let bodies = flat.wallBodies()
let partition = bodies[0].pieces.filter(\.shared)
check(!partition.isEmpty && partition.allSatisfy { abs(($0.outerStart - $0.innerStart).dot($0.outward) - 0.06) < 1e-6 }, "Each room fills half of the partition")
check(bodies[0].pieces.filter { !$0.shared }.allSatisfy { abs(($0.outerEnd - $0.innerEnd).dot($0.outward) - WallBody.standardThickness) < 1e-6 || $0.capEnd }, "Outside walls keep the standard thickness")
check(bodies[1].pieces.contains(where: \.shared), "The partition is shared from the other side too")
check(flat.doors.count == 1, "The door between the rooms is drawn once")
let bedroomMiddle = flat.rooms[1].labelPoint
check(flat.room(at: bedroomMiddle)?.name == "Спальня" && flat.room(at: PlanPoint(x: -1, y: -1)) == nil, "A finger finds the room it is on")
check(flat.rooms.allSatisfy { $0.plan.contains($0.labelPoint) }, "Room labels are inside the rooms")
let movedA = roomA.moved(turn: 0.3, shift: PlanPoint(x: 1, y: 2))
let scanBefore = roomA.placement!.apply(roomA.floorPolygon[0]), scanAfter = movedA.placement!.apply(movedA.floorPolygon[0])
check(scanBefore.distance(to: scanAfter) < 1e-9 && abs(movedA.area - roomA.area) < 1e-9, "A moved room still knows where it is in the scan")
let lShapedFlat = Apartment(id: UUID(), name: "Г", rooms: [lShaped]).layout
check(lShapedFlat.rooms[0].plan.contains(lShapedFlat.rooms[0].labelPoint), "The label of an L-shaped room is inside it")
let savedApartmentRoom = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(roomA))
check(savedApartmentRoom.apartmentName == "Квартира 1" && savedApartmentRoom.apartmentID == apartmentID, "The apartment survives saving")

print("PASS: \(passed) plan and design checks")
