import Foundation

// Участок по кадастру: геометрия, разбор ответа НСПД, проверки по нормам. Запуск: sh Tests/run.sh.

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) { if !condition() { fatalError("FAIL: \(name)") }; passed += 1 }
func near(_ a: Double, _ b: Double, _ name: String, _ tolerance: Double) { check(abs(a - b) <= tolerance, "\(name): \(a) ≠ \(b) ± \(tolerance)") }

let origin = GeoPoint(lat: 55.7558, lon: 37.6173)
// Обратная проекция: местные метры → широта/долгота (те же коэффициенты, что в GeoMath.local).
func geo(_ x: Double, _ y: Double) -> [Double] {
    let mLat = 111_132.954 - 559.822 * cos(2 * origin.lat * .pi / 180) + 1.175 * cos(4 * origin.lat * .pi / 180)
    let mLon = 111_412.84 * cos(origin.lat * .pi / 180) - 93.5 * cos(3 * origin.lat * .pi / 180)
    return [origin.lat + y / mLat, origin.lon + x / mLon]
}

// 1. Меркатор ↔ широта/долгота.
let mx = origin.lon * .pi / 180 * GeoMath.earthRadius
let my = log(tan(.pi / 4 + origin.lat * .pi / 360)) * GeoMath.earthRadius
let back = GeoMath.fromMercator(x: mx, y: my)
near(back.lat, origin.lat, "широта из Меркатора", 1e-9)
near(back.lon, origin.lon, "долгота из Меркатора", 1e-9)

// 2. Участок 30 × 40 м: площадь и расстояния.
let parcelOutline = [geo(-15, -20), geo(15, -20), geo(15, 20), geo(-15, 20)]
var parcel = CadastralParcel(cadNumber: "77:01:0001001:1", areaDocument: 1200, category: "Земли населённых пунктов",
                             permittedUse: "Для индивидуального жилищного строительства", outline: parcelOutline)
near(parcel.areaOutline, 1200, "площадь по контуру", 0.5)
let local = GeoMath.local(parcel.outline, origin: parcel.centroid)
near(GeoMath.distanceToBoundary(SIMD2(0, 0), local), 15, "до границы из центра", 0.01)
check(GeoMath.contains(SIMD2(0, 0), local), "центр внутри")
check(!GeoMath.contains(SIMD2(20, 0), local), "снаружи")

// 3. Разбор ответа НСПД (EPSG:3857, как отдаёт поиск).
func merc(_ p: [Double]) -> [Double] { [p[1] * .pi / 180 * GeoMath.earthRadius, log(tan(.pi / 4 + p[0] * .pi / 360)) * GeoMath.earthRadius] }
let ring = (parcelOutline + [parcelOutline[0]]).map(merc)
let response: [String: Any] = ["data": ["type": "FeatureCollection", "features": [[
    "type": "Feature",
    "geometry": ["type": "Polygon", "coordinates": [ring], "crs": ["type": "name", "properties": ["name": "EPSG:3857"]]],
    "properties": ["label": "77:01:0001001:1", "options": [
        "cad_num": "77:01:0001001:1", "land_record_area": 1200, "readable_address": "г. Москва, ул. Тестовая, 1",
        "land_record_category_type": "Земли населённых пунктов", "permitted_use_established_by_document": "Для ИЖС", "cost_value": 5_400_000.5,
    ]],
]]]]
let parsed = NSPDParser.parcels(from: try! JSONSerialization.data(withJSONObject: response))
check(parsed.count == 1, "один участок из ответа")
check(parsed.first?.cadNumber == "77:01:0001001:1", "кадастровый номер")
check(parsed.first?.outline.count == 4, "замыкающая точка снята")
near(parsed.first?.areaOutline ?? 0, 1200, "площадь из ответа НСПД", 0.5)
near(parsed.first?.cadastralValue ?? 0, 5_400_000.5, "кадастровая стоимость", 0.01)

// 4. Нормы: дом 10 × 8 м в 2 м от границы — нарушение; баня в 1,5 м — норма.
let houseNear = SiteBuilding(name: "Дом", kind: .house, footprint: [SIMD2(-13, -5), SIMD2(-3, -5), SIMD2(-3, 3), SIMD2(-13, 3)])
let bath = SiteBuilding(name: "Баня", kind: .bathhouse, footprint: [SIMD2(10, 14), SIMD2(13.5, 14), SIMD2(13.5, 18.5), SIMD2(10, 18.5)])
let findings = ParcelRules.check(parcel: parcel, buildings: [houseNear, bath])
check(findings.contains { $0.level == .problem && $0.title.hasPrefix("Дом: отступ 2") }, "дом ближе 3 м — нарушение")
check(findings.contains { $0.level == .ok && $0.title.hasPrefix("Баня: отступ 1,5") }, "баня 1,5 м — норма")
check(findings.contains { $0.level == .ok && $0.title == "Площадь сходится с ЕГРН" }, "площадь сходится")
check(findings.contains { $0.title.hasPrefix("ВРИ допускает") }, "ВРИ ИЖС")
let houseOk = SiteBuilding(name: "Дом", kind: .house, footprint: [SIMD2(-11, -5), SIMD2(-1, -5), SIMD2(-1, 3), SIMD2(-11, 3)])
check(ParcelRules.check(parcel: parcel, buildings: [houseOk]).contains { $0.level == .ok && $0.title.hasPrefix("Дом: отступ 4") }, "дом в 4 м — норма")
let outside = SiteBuilding(name: "Гараж", kind: .garage, footprint: [SIMD2(14, 0), SIMD2(18, 0), SIMD2(18, 6), SIMD2(14, 6)])
check(ParcelRules.check(parcel: parcel, buildings: [outside]).contains { $0.level == .problem && $0.title.contains("за границу") }, "за границей")
parcel.category = "Земли сельскохозяйственного назначения"
parcel.permittedUse = "Для сельскохозяйственного производства"
check(ParcelRules.check(parcel: parcel, buildings: []).contains { $0.level == .problem && $0.title == "Земли сельхозназначения" }, "сельхозземли")

print("Parcel tests passed: \(passed)")
