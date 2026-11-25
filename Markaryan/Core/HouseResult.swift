import Foundation

// «Дом снаружи»: макет дома, который вернул обработчик скана (house.json). Все поля необязательные —
// обработчик развивается, а старое приложение должно открывать новые макеты.

struct HouseMeasure: Codable, Equatable {
    var value: Double?
    /// measured (LiDAR) · extrapolated (LiDAR + продолжение кромки) · photo (по фото) · assumption (предположение)
    var source: String
    var sigma: Double?
    var note: String?

    var sourceTitle: String {
        switch source {
        case "measured": return "измерено"
        case "extrapolated": return "измерено, продолжено"
        case "photo": return "по фото"
        default: return "предположение"
        }
    }
    /// 0 — измерено, 1 — по фото, 2 — предположение (для цвета метки).
    var trust: Int {
        switch source {
        case "measured": return 0
        case "extrapolated", "photo": return 1
        default: return 2
        }
    }
}

struct HouseResult: Codable, Equatable {
    struct Footprint: Codable, Equatable {
        var gableWidth: HouseMeasure?
        var length: HouseMeasure?
        /// Углы в мире ARKit [x, z], метры.
        var corners: [[Double]]?
    }
    struct Detail: Codable, Equatable {
        var kind: String?
        var ru: String?
        var count: Double?
        var seen: Bool?
    }
    struct Opening: Codable, Equatable, Identifiable {
        var kind: String?
        var width: Double?
        var height: Double?
        var sill: Double?
        var area: Double?
        var frames: Int?
        var source: String?
        var center: [Double]?
        var id: String { "\(kind ?? "")-\(center?.map { String(format: "%.2f", $0) }.joined(separator: ",") ?? UUID().uuidString)" }
        var title: String {
            switch kind {
            case "door": return "Дверь"
            case "garage_door": return "Гаражные ворота"
            case "balcony_door": return "Балконная дверь"
            default: return "Окно"
            }
        }
    }
    struct OpeningsSummary: Codable, Equatable {
        var windows: Int?
        var doors: Int?
        var area: Double?
    }
    struct ByPhoto: Codable, Equatable {
        var facade: String?
        var roofTypeRu: String?
        var covering: String?
        var color: String?
        var details: [Detail]?
        var hidden: [String]?
    }
    struct Roof: Codable, Equatable {
        var type: String?
        var ridgeHeight: HouseMeasure?
        var pitchDeg: HouseMeasure?
        var pitchLeftDeg: Double?
        var pitchRightDeg: Double?
        var symmetric: Bool?
        var typeByPhoto: String?
        var byPhoto: ByPhoto?
        var overhangEave: HouseMeasure?
        var overhangGable: HouseMeasure?
    }
    struct Control: Codable, Equatable {
        var tape: Double?
        var model: Double?
        var deltaCm: Double?
    }
    struct Quality: Codable, Equatable {
        var framesWithDepth: Int?
        var frames: Int?
        var rejectedBlurry: Int?
        var seconds: Double?
    }
    struct Geo: Codable, Equatable {
        /// Углы дома [широта, долгота] — предварительно (GPS ±5–15 м, компас ±5–10°).
        var footprintLatLon: [[Double]]?
    }

    var footprint: Footprint?
    var eaveHeight: HouseMeasure?
    var roof: Roof?
    var control: Control?
    var openings: [Opening]?
    var openingsSummary: OpeningsSummary?
    /// Недоступная сторона: введённая длина (техпаспорт, замер изнутри) против достроенной.
    var blockedSide: Control?
    var quality: Quality?
    var geo: Geo?

    var roofTitle: String {
        if let ru = roof?.byPhoto?.roofTypeRu, !ru.isEmpty { return ru.prefix(1).uppercased() + String(ru.dropFirst()) }
        switch roof?.type {
        case "gable": return "Двускатная"
        case "hip": return "Вальмовая"
        case "flat_or_unknown": return "Плоская или не определена"
        default: return "Не определена"
        }
    }

    /// Площадь застройки по футпринту, м².
    var footprintArea: Double? {
        guard let w = footprint?.gableWidth?.value, let l = footprint?.length?.value else { return nil }
        return w * l
    }

    private var eaveOverhang: Double { roof?.overhangEave?.value ?? 0 }
    private var gableOverhang: Double { roof?.overhangGable?.value ?? 0 }
    var hasOverhangs: Bool { roof?.overhangEave?.value != nil || roof?.overhangGable?.value != nil }

    /// Площадь кровли со свесами (двускатная: 2 ската × длина ската × длина с фронтонными свесами), м².
    var roofArea: Double? {
        guard let w = footprint?.gableWidth?.value, let l = footprint?.length?.value else { return nil }
        let length = l + 2 * gableOverhang
        guard let pitch = roof?.pitchDeg?.value, pitch > 1, pitch < 80 else { return (w + 2 * eaveOverhang) * length }
        return 2 * (w / 2 + eaveOverhang) / cos(pitch * .pi / 180) * length
    }

    /// Водосточный жёлоб: два карниза с фронтонными свесами, м.
    var gutterLength: Double? {
        guard let l = footprint?.length?.value else { return nil }
        return 2 * (l + 2 * gableOverhang)
    }

    /// Площадь фасадов за вычетом окон и дверей, м².
    var facadeNetArea: Double? {
        guard let gross = facadeArea else { return nil }
        let openingsArea = openingsSummary?.area ?? (openings ?? []).reduce(0) { $0 + ($1.area ?? 0) }
        return max(0, gross - openingsArea)
    }

    /// Площадь фасадов без проёмов: стены до карниза по периметру + два фронтона, м².
    var facadeArea: Double? {
        guard let w = footprint?.gableWidth?.value, let l = footprint?.length?.value, let eave = eaveHeight?.value else { return nil }
        let gables: Double
        if let ridge = roof?.ridgeHeight?.value, ridge > eave { gables = w * (ridge - eave) } else { gables = 0 } // 2 треугольника = w·h
        return 2 * (w + l) * eave + gables
    }

    /// Дом как постройка на участке (местная система участка) — для проверки отступов.
    func siteBuilding(parcel: CadastralParcel) -> SiteBuilding? {
        guard let corners = geo?.footprintLatLon, corners.count >= 3, !parcel.isEmpty else { return nil }
        return SiteBuilding(name: "Дом", kind: .house, footprint: GeoMath.local(corners, origin: parcel.centroid))
    }
}
