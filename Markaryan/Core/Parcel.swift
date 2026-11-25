import Foundation
#if canImport(Security)
import Security
#endif

// «Дом снаружи»: участок по кадастру (НСПД — Национальная система пространственных данных Росреестра).
// НСПД отвечает только российским адресам, поэтому запрос идёт прямо с iPhone, а не через наш сервер (он в NL).
// Сертификат nspd.gov.ru выдан российским УЦ Минцифры, которому iOS не доверяет «из коробки»: доверяем
// встроенному корневому сертификату Russian Trusted Root CA — ТОЛЬКО для nspd.gov.ru, остальные соединения как были.
// Геометрия и проверки (отступы, процент застройки, ВРИ) — чистый Foundation, без сети: их проверяют тесты.

// MARK: - Данные участка

struct CadastralParcel: Codable, Equatable {
    var cadNumber: String
    var address: String?
    /// Площадь по ЕГРН, м² (юридическая).
    var areaDocument: Double?
    var category: String?
    var permittedUse: String?
    var cadastralValue: Double?
    /// Внешний контур, [широта, долгота] (WGS‑84).
    var outline: [[Double]]
    var source = "НСПД (Росреестр)"
    var fetchedAt = Date()

    /// Площадь по контуру, м² (проверка: должна сходиться с ЕГРН в пределах 1–2 %).
    var areaOutline: Double { GeoMath.area(GeoMath.local(outline, origin: centroid)) }
    var centroid: GeoPoint {
        let n = Double(max(outline.count, 1))
        return GeoPoint(lat: outline.reduce(0) { $0 + $1[0] } / n, lon: outline.reduce(0) { $0 + $1[1] } / n)
    }
    var isEmpty: Bool { outline.count < 3 }
}

struct GeoPoint: Codable, Equatable {
    var lat: Double
    var lon: Double
}

// MARK: - Геометрия

enum GeoMath {
    static let earthRadius = 6_378_137.0

    /// Web Mercator (EPSG:3857), метры → широта/долгота.
    static func fromMercator(x: Double, y: Double) -> GeoPoint {
        let lon = x / earthRadius * 180 / .pi
        let lat = (2 * atan(exp(y / earthRadius)) - .pi / 2) * 180 / .pi
        return GeoPoint(lat: lat, lon: lon)
    }

    /// Местная плоская система вокруг `origin`: x — на восток, y — на север, метры.
    /// Для участка (до 1–2 км) ошибка проекции — миллиметры.
    static func local(_ points: [[Double]], origin: GeoPoint) -> [SIMD2<Double>] {
        let mLat = 111_132.954 - 559.822 * cos(2 * origin.lat * .pi / 180) + 1.175 * cos(4 * origin.lat * .pi / 180)
        let mLon = 111_412.84 * cos(origin.lat * .pi / 180) - 93.5 * cos(3 * origin.lat * .pi / 180)
        return points.map { SIMD2(($0[1] - origin.lon) * mLon, ($0[0] - origin.lat) * mLat) }
    }

    /// Площадь многоугольника (формула Гаусса), м².
    static func area(_ polygon: [SIMD2<Double>]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    static func distance(_ p: SIMD2<Double>, segment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let length = (ab * ab).sum()
        let t = length > 0 ? max(0, min(1, ((p - a) * ab).sum() / length)) : 0
        let d = p - (a + ab * t)
        return (d * d).sum().squareRoot()
    }

    /// Расстояние от точки до границы многоугольника.
    static func distanceToBoundary(_ p: SIMD2<Double>, _ polygon: [SIMD2<Double>]) -> Double {
        guard polygon.count >= 2 else { return .infinity }
        return polygon.indices.map { distance(p, segment: polygon[$0], polygon[($0 + 1) % polygon.count]) }.min() ?? .infinity
    }

    static func contains(_ p: SIMD2<Double>, _ polygon: [SIMD2<Double>]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Наименьшее расстояние от контура постройки до границы участка (по вершинам и рёбрам обоих контуров).
    static func setback(of building: [SIMD2<Double>], in parcel: [SIMD2<Double>]) -> Double {
        let fromBuilding = building.map { distanceToBoundary($0, parcel) }.min() ?? .infinity
        let fromParcel = parcel.map { distanceToBoundary($0, building) }.min() ?? .infinity
        return min(fromBuilding, fromParcel)
    }
}

// MARK: - Проверки по нормам

struct ParcelFinding: Identifiable, Equatable {
    enum Level: String { case ok, warning, problem, info }
    let id = UUID()
    var level: Level
    var title: String
    var detail: String
    /// Ссылка на норму — чтобы прораб или заказчик мог проверить.
    var norm: String?

    static func == (a: ParcelFinding, b: ParcelFinding) -> Bool { a.level == b.level && a.title == b.title && a.detail == b.detail }
}

/// Постройка на участке в местной системе участка (метры, x — восток, y — север).
struct SiteBuilding {
    enum Kind { case house, outbuilding, garage, bathhouse }
    var name: String
    var kind: Kind
    var footprint: [SIMD2<Double>]
}

enum ParcelRules {
    /// Минимальные отступы до границы соседнего участка (СП 30‑102‑99 п. 5.3.4; СП 53.13330.2019 п. 6.7).
    static func minimumSetback(_ kind: SiteBuilding.Kind) -> Double {
        switch kind {
        case .house: return 3
        case .garage, .outbuilding: return 1
        case .bathhouse: return 1
        }
    }

    /// Проверки участка и построек. `maxCoverage` — допустимый процент застройки из ПЗЗ (если неизвестен — 0,3 как частый).
    static func check(parcel: CadastralParcel, buildings: [SiteBuilding], maxCoverage: Double? = nil) -> [ParcelFinding] {
        var findings: [ParcelFinding] = []
        let local = GeoMath.local(parcel.outline, origin: parcel.centroid)
        let outlineArea = GeoMath.area(local)

        if let document = parcel.areaDocument, document > 0, outlineArea > 0 {
            let delta = abs(outlineArea - document) / document
            findings.append(delta <= 0.02
                ? ParcelFinding(level: .ok, title: "Площадь сходится с ЕГРН", detail: "По контуру \(format(outlineArea)) м², по документам \(format(document)) м².")
                : ParcelFinding(level: .warning, title: "Площадь по контуру отличается от ЕГРН на \(Int((delta * 100).rounded())) %",
                                detail: "По контуру \(format(outlineArea)) м², по документам \(format(document)) м². Возможна неточная граница — проверьте межевание.", norm: "218‑ФЗ"))
        }

        let use = (parcel.permittedUse ?? "").lowercased()
        let category = (parcel.category ?? "").lowercased()
        if category.contains("сельскохозяйственного") && !(use.contains("садовод") || use.contains("крестьян") || use.contains("лпх") || use.contains("личного подсобного")) {
            findings.append(ParcelFinding(level: .problem, title: "Земли сельхозназначения",
                                          detail: "На таком участке жилой дом строить нельзя без смены ВРИ (кроме садоводства и ЛПХ с правом застройки).", norm: "ЗК РФ ст. 77–78"))
        }
        if !use.isEmpty {
            let residential = ["индивидуальн", "ижс", "личного подсобного", "лпх", "садовод", "блокированн"].contains { use.contains($0) }
            findings.append(residential
                ? ParcelFinding(level: .ok, title: "ВРИ допускает жилой дом", detail: parcel.permittedUse ?? "")
                : ParcelFinding(level: .warning, title: "Проверьте вид разрешённого использования", detail: "«\(parcel.permittedUse ?? "")» — жилой дом может быть не разрешён.", norm: "ЗК РФ ст. 7, ПЗЗ"))
        }

        var built = 0.0
        for building in buildings where building.footprint.count >= 3 {
            built += GeoMath.area(building.footprint)
            let inside = building.footprint.allSatisfy { GeoMath.contains($0, local) }
            if !inside {
                findings.append(ParcelFinding(level: .problem, title: "\(building.name) выходит за границу участка",
                                              detail: "Часть контура за кадастровой границей. Проверьте привязку макета к участку (две точки на углах участка).", norm: "ГрК РФ ст. 51.1"))
                continue
            }
            let setback = GeoMath.setback(of: building.footprint, in: local)
            let need = minimumSetback(building.kind)
            findings.append(setback + 0.05 >= need
                ? ParcelFinding(level: .ok, title: "\(building.name): отступ \(format(setback, digits: 1)) м", detail: "Норма — не меньше \(format(need, digits: 0)) м от границы соседнего участка.", norm: "СП 30‑102‑99 п. 5.3.4; СП 53.13330.2019 п. 6.7")
                : ParcelFinding(level: .problem, title: "\(building.name): отступ \(format(setback, digits: 1)) м — меньше нормы \(format(need, digits: 0)) м",
                                detail: "Нужно согласие соседа (письменное) или перенос. От красной линии улицы — 5 м, проезда — 3 м.", norm: "СП 30‑102‑99 п. 5.3.4; СП 42.13330.2016 п. 7.1"))
        }
        if outlineArea > 0 && built > 0 {
            let share = built / outlineArea
            let limit = maxCoverage ?? 0.3
            let known = maxCoverage != nil
            findings.append(share <= limit
                ? ParcelFinding(level: known ? .ok : .info, title: "Застроено \(Int((share * 100).rounded())) % участка",
                                detail: known ? "Допустимо по ПЗЗ — до \(Int(limit * 100)) %." : "Частый предел по ПЗЗ — 30–40 %. Уточните в ПЗЗ вашего поселения.", norm: "ПЗЗ")
                : ParcelFinding(level: known ? .problem : .warning, title: "Застроено \(Int((share * 100).rounded())) % участка",
                                detail: "Больше \(Int(limit * 100)) % — \(known ? "превышает ПЗЗ" : "может превышать ПЗЗ, уточните").", norm: "ПЗЗ"))
        }
        if buildings.filter({ $0.kind == .house }).count > 0 {
            findings.append(ParcelFinding(level: .info, title: "Пожарные разрывы до домов соседей",
                                          detail: "6–15 м в зависимости от материала стен (кирпич/бетон — 6 м, дерево — до 15 м). Соседние дома в макете — этап «Участок».", norm: "СП 4.13130.2013 табл. 1"))
        }
        return findings
    }

    /// Формат чисел: по умолчанию русский («1,5»); приложение при запуске ставит язык пользователя.
    static var locale = Locale(identifier: "ru_RU")

    static func format(_ value: Double, digits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Разбор ответа НСПД

enum NSPDParser {
    /// Ответ НСПД: GeoJSON‑объекты (поиск — `data.features`, карта — `features`). Координаты — EPSG:3857 или WGS‑84.
    static func parcels(from data: Data) -> [CadastralParcel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return features(in: json).compactMap(parcel(from:))
    }

    private static func features(in json: Any) -> [[String: Any]] {
        if let dict = json as? [String: Any] {
            if let list = dict["features"] as? [[String: Any]] { return list }
            if let inner = dict["data"] { return features(in: inner) }
            if dict["geometry"] != nil { return [dict] }
        }
        if let list = json as? [[String: Any]] { return list.filter { $0["geometry"] != nil } }
        return []
    }

    static func parcel(from feature: [String: Any]) -> CadastralParcel? {
        guard let geometry = feature["geometry"] as? [String: Any], let ring = outerRing(geometry) else { return nil }
        let properties = feature["properties"] as? [String: Any] ?? [:]
        let options = properties["options"] as? [String: Any] ?? properties
        func text(_ keys: [String]) -> String? {
            for key in keys { if let v = options[key] as? String, !v.isEmpty { return v }; if let v = properties[key] as? String, !v.isEmpty { return v } }
            return nil
        }
        func number(_ keys: [String]) -> Double? {
            for key in keys {
                if let v = options[key] as? Double { return v }
                if let v = options[key] as? Int { return Double(v) }
                if let v = options[key] as? String, let d = Double(v.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }) { return d }
            }
            return nil
        }
        let mercator = ring.contains { abs($0[0]) > 180 || abs($0[1]) > 90 }
        let outline = ring.map { point -> [Double] in
            if mercator { let p = GeoMath.fromMercator(x: point[0], y: point[1]); return [p.lat, p.lon] }
            return [point[1], point[0]] // GeoJSON: [долгота, широта]
        }
        guard outline.count >= 3 else { return nil }
        let cad = text(["cad_num", "cad_number", "cn", "label"]) ?? (properties["label"] as? String) ?? "—"
        return CadastralParcel(
            cadNumber: cad,
            address: text(["readable_address", "address"]),
            areaDocument: number(["land_record_area", "specified_area", "declared_area", "area"]),
            category: text(["land_record_category_type", "category_type", "category"]),
            permittedUse: text(["permitted_use_established_by_document", "permitted_use_name", "util_by_doc", "permitted_use"]),
            cadastralValue: number(["cost_value", "cad_cost"]),
            outline: outline)
    }

    /// Внешнее кольцо Polygon / самого большого MultiPolygon: [[x, y]].
    private static func outerRing(_ geometry: [String: Any]) -> [[Double]]? {
        let type = geometry["type"] as? String
        let coordinates = geometry["coordinates"]
        func ring(_ any: Any?) -> [[Double]]? {
            (any as? [[Any]])?.compactMap { pair in
                let values = pair.compactMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) }
                return values.count >= 2 ? Array(values.prefix(2)) : nil
            }
        }
        if type == "Polygon", let rings = coordinates as? [Any], let outer = ring(rings.first) { return outer.count > 3 && outer.first == outer.last ? Array(outer.dropLast()) : outer }
        if type == "MultiPolygon", let polygons = coordinates as? [[Any]] {
            let outers = polygons.compactMap { ring($0.first) }
            guard let largest = outers.max(by: { $0.count < $1.count }) else { return nil }
            return largest.count > 3 && largest.first == largest.last ? Array(largest.dropLast()) : largest
        }
        return nil
    }
}

// MARK: - Клиент НСПД

#if canImport(Security)

final class NSPDClient: NSObject, URLSessionDelegate {
    static let shared = NSPDClient()
    private static let host = "nspd.gov.ru"
    /// Сертификаты Минцифры (DER, base64): корневой и промежуточные. Промежуточные нужны, если сервер НСПД
    /// не присылает их сам — без них iPhone не может достроить цепочку и пишет ошибку TLS. SHA‑256:
    /// Root CA D2:6D:2D:…:CF:31 (до 2032), Sub CA BB:BD:E2:…:FD:9B (до 2027), Sub CA 2024 21:55:78:…:A3:F2 (до 2029).
    private static let trustedDER: [String] = [
        """
        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
        """,
        """
        MIIHQjCCBSqgAwIBAgICEAIwDQYJKoZIhvcNAQELBQAwcDELMAkGA1UEBhMCUlUxPzA9BgNVBAoMNlRoZSBNaW5pc3RyeSBvZiBEaWdpdGFsIERldmVsb3Bt
        ZW50IGFuZCBDb21tdW5pY2F0aW9uczEgMB4GA1UEAwwXUnVzc2lhbiBUcnVzdGVkIFJvb3QgQ0EwHhcNMjIwMzAyMTEyNTE5WhcNMjcwMzA2MTEyNTE5WjBv
        MQswCQYDVQQGEwJSVTE/MD0GA1UECgw2VGhlIE1pbmlzdHJ5IG9mIERpZ2l0YWwgRGV2ZWxvcG1lbnQgYW5kIENvbW11bmljYXRpb25zMR8wHQYDVQQDDBZS
        dXNzaWFuIFRydXN0ZWQgU3ViIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA9YPqBKOk19NFymrEwehzrhBEgT2atLezpduB24mQ7CiOa/HV
        pFCDRZzdxqlh8drku408/tTmWzlNH/brHuQhZ/miWKOf35lpKzjyBd6TPM23uAfJvEOQ2/dnKGGJbsUo1/udKSvxQwVHpVv3S80OlluKfhWPDEXQpgyFqIzP
        oxIQTLZ0deirZwMVHarZ5u8HqHetRuAtmO2ZDGQnvVOJYAjls+Hiueq7Lj7Oce7CQsTwVZeP+XQx28PAaEZ3y6sQEt6rL06ddpSdoTMpBnCqTbxW+eWMyjkI
        n6t9GBtUV45yB1EkHNnj2Ex4GwCiN9T84QQjKSr+8f0psGrZvPbCbQAwNFJjisLixnjlGPLKa5vOmNwIh/LAyUW5DjpkCx004LPDuqPpFsKXNKpaL2Dm6uc0
        x4Jo5m+gUTVORB6hOSzWnWDj2GWfomLzzyjG81DRGFBpco/O93zecsIN3SL2Ysjpq1zdoS01CMYxie//9zWvYwzI25/OZigtnpCIrcd2j1Y6dMUFQAzAtHE+
        qsXflSL8HIS+IJEFIQobLlYhHkoE3avgNx5jlu+OLYe0dF0Ykx1PGNjbwqvTX37RCn32NMjlotW2QcGEZhDKj+3urZizp5xdTPZitA+aEjZM/Ni71VOdiOP0
        igbw6asZ2fxdozZ1TnSSYNYvNATwthNmZysCAwEAAaOCAeUwggHhMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTR4XEN
        Cy2BTm6KSo9MI7NMXqtpCzAfBgNVHSMEGDAWgBTh0YHlzlpfBKrS6badZrHF+qwshzCBxwYIKwYBBQUHAQEEgbowgbcwOwYIKwYBBQUHMAKGL2h0dHA6Ly9y
        b3N0ZWxlY29tLnJ1L2NkcC9yb290Y2Ffc3NsX3JzYTIwMjIuY3J0MDsGCCsGAQUFBzAChi9odHRwOi8vY29tcGFueS5ydC5ydS9jZHAvcm9vdGNhX3NzbF9y
        c2EyMDIyLmNydDA7BggrBgEFBQcwAoYvaHR0cDovL3JlZXN0ci1wa2kucnUvY2RwL3Jvb3RjYV9zc2xfcnNhMjAyMi5jcnQwgbAGA1UdHwSBqDCBpTA1oDOg
        MYYvaHR0cDovL3Jvc3RlbGVjb20ucnUvY2RwL3Jvb3RjYV9zc2xfcnNhMjAyMi5jcmwwNaAzoDGGL2h0dHA6Ly9jb21wYW55LnJ0LnJ1L2NkcC9yb290Y2Ff
        c3NsX3JzYTIwMjIuY3JsMDWgM6Axhi9odHRwOi8vcmVlc3RyLXBraS5ydS9jZHAvcm9vdGNhX3NzbF9yc2EyMDIyLmNybDANBgkqhkiG9w0BAQsFAAOCAgEA
        RBVzZls79AdiSCpar15dA5Hr/rrT4WbrOfzlpI+xrLeRPrUG6eUWIW4vSui1yx3iqGLCjPcKb+HOTwoRMbI6ytP/ndp3TlYua2advYBEhSvjs+4vDZNwXr/D
        anbwIWdurZmViQRBDFebpkvnIvru/RpWud/5r624Wp8voZMRtj/cm6aI9LtvBfT9cfzhOaexI/99c14dyiuk1+6QhdwKaCRTc1mdfNQmnfWNRbfWhWBlK3h4
        GGE9JK33Gk8ZS8DMrkdAh0xby4xAQ/mSWAfWrBmfzlOqGyoB1U47WTOeqNbWkkoAP2ys94+sJg4NTkiDVtXRF6nr6fYi0bSOvOFg0IQrMXO2Y8gyg9ARdPJw
        KtvWX8VPADCYMiWHh4n8bZokIrImVKLDQKHY4jCsND2HHdJfnrdL2YJw1qFskNO4cSNmZydw0Wkgjv9kF+KxqrDKlB8MZu2Hclph6v/CZ0fQ9YuE8/lsHZ0Q
        c2HyiSMnvjgK5fDc3TD4fa8FE8gMNurM+kV8PT8LNIM+4Zs+LKEV8nqRWBaxkIVJGekkVKO8xDBOG/aN62AZKHOeGcyIdu7yNMMRihGVZCYr8rYiJoKiOzDq
        OkPkLOPdhtVlgnhowzHDxMHND/E2WA5pZHuNM/m0TXt2wTTPL7JH2YC0gPz/BvvSzjksgzU5rLbRyUKQkgU=
        """,
        """
        MIIG6DCCBNCgAwIBAgICEAUwDQYJKoZIhvcNAQELBQAwcDELMAkGA1UEBhMCUlUxPzA9BgNVBAoMNlRoZSBNaW5pc3RyeSBvZiBEaWdpdGFsIERldmVsb3Bt
        ZW50IGFuZCBDb21tdW5pY2F0aW9uczEgMB4GA1UEAwwXUnVzc2lhbiBUcnVzdGVkIFJvb3QgQ0EwHhcNMjQwNzE1MTI1MDQxWhcNMjkwNzE5MTI1MDQxWjBv
        MQswCQYDVQQGEwJSVTE/MD0GA1UECgw2VGhlIE1pbmlzdHJ5IG9mIERpZ2l0YWwgRGV2ZWxvcG1lbnQgYW5kIENvbW11bmljYXRpb25zMR8wHQYDVQQDDBZS
        dXNzaWFuIFRydXN0ZWQgU3ViIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1j0rkZECOt1S8o7IJY+4YKAxuEa5xaHKHXT2EpkuC/0krqMO
        jUy2oPIRNgR5g8X0Jl6jamxeGLc4Q1tfju6or9oSRYThIUhRsFDQNBiBBEXoBgWxTfiKB2eyT97+pz5TBtBiRCPaLGRHYLRb9Jz2HkJlxbtNPjtDrF5DPHym
        +mZ1M1z3hIQYAqJwLpsEBnsw/VxWMlxqHoeewd0huJMd71KQ5vOKlz7KrIZ6EobNNa6wItuvsfj3kYCK7O78uLHGXXFxdr8Hae9lMUmC8F7AFwa+bO1LRlTl
        qW7rE3rLf+jj70N01N8T3o22v14YBaFBWQWncAVYD2JuL3tH252+kdNOERf1fLbLRigJAbd+hOhWYlNf963TFDgnNPliHNIW72SygVBnI2V3JwO1dp1hVKpK
        /zt8ziGdHW4gmOLTsH50YKdR4jNqUgQv4wASlKn9OpN6zHYc5G8h86fYBM+zxE5ikGI+I/vIqBuI0eaDU92AWN/YjFLpu8tMu9kLRSCf1vug6FIfDPWVo7iP
        ac/SI2v8jnnpaW7ph/Pz3WkzaG7ZZJsfFs+8dploWc6LOoDtbFBhMdGMxu024msC0PSjZb5ODXPIaO2NsA7fMiAtZcoK6anTUJh4zOP/stA9qsJGNxdrEmiP
        XSmBZY/NY0wkZgZ6JTDhw7038bPvctkblJkCAwEAAaOCAYswggGHMB0GA1UdDgQWBBR3Pdk5r0K93FvKduru/c4+YSkwXzAfBgNVHSMEGDAWgBTh0YHlzlpf
        BKrS6badZrHF+qwshzAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADCBmAYIKwYBBQUHAQEEgYswgYgwQAYIKwYBBQUHMAKGNGh0dHA6Ly9u
        dWMtY2RwLnZvc2tob2QucnUvY2RwL3Jvb3RjYV9zc2xfcnNhMjAyMi5jcnQwRAYIKwYBBQUHMAKGOGh0dHA6Ly9udWMtY2RwLmRpZ2l0YWwuZ292LnJ1L2Nk
        cC9yb290Y2Ffc3NsX3JzYTIwMjIuY3J0MIGFBgNVHR8EfjB8MDqgOKA2hjRodHRwOi8vbnVjLWNkcC52b3NraG9kLnJ1L2NkcC9yb290Y2Ffc3NsX3JzYTIw
        MjIuY3JsMD6gPKA6hjhodHRwOi8vbnVjLWNkcC5kaWdpdGFsLmdvdi5ydS9jZHAvcm9vdGNhX3NzbF9yc2EyMDIyLmNybDANBgkqhkiG9w0BAQsFAAOCAgEA
        msINXtQ7wwUWvIeOr80MdJS/5G4xhyZOVEmeUorThquT672ycCg3XCxc4fwbiZqSSbBqntQ7RtiTAKMYMvBageKoVHbzz+R4jX01tKcTx8cDePrzdJ73bLNU
        orE7RU9QsW4KyiUeRmjMDV23AUlEvuQFTwgkHXvbac1BBdPn9CrssQuF5EGohZKcQPFiAAc4SHbRNhlr7uAwgpc/erzI9EAcvA6BVAXcVKoeGpV01uexUgZ6
        St5RP9UmDWNA7T4yVXWJ233N0Q8bl+6AswINQ3PosPu6yQQHQjr65YS06epK+AeI6j+oGR4xI7EhTQhQvaobnGmX/8QQ7XDRYCP2HXYxiffnn/CfZ/BVyKLY
        eY1ZipjEnzqdQIC2+Q3WtY8jsVRQMP38WFRmtsIt5snehnPTs5bKGVIcYzj3o3Ex/K7agEz0zAJ0JR5ivXZOvNkT0g9x1v+S1IkU3e/nX1a+tpRquMtnHX0L
        2lXArNHUbaOO9EJtd57WaIpofV5cVhhwShOgAuBc9UMJF3/n4t4RKiPxtsK8P67gcmphMhslj7AMYrYMej2NvQZY4m3ub3CPC/PrTjDONvb+8g5xrKtxBjYq
        C74HSB4dg9G3WimSDUuP2Su6G2y2TUeyJuCvCLz289VoO0vg7cNdMobE3KCqAiiNhN2VBFxHAUKmUoRcRdw=
        """,
    ]
    /// Причина последней ошибки проверки сертификата — показываем человеку, чтобы понять, что не так.
    private var lastTrustError: String?

    private lazy var session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = ["Accept": "application/json", "Referer": "https://nspd.gov.ru/map"]
        return configuration
    }(), delegate: self, delegateQueue: nil)

    enum Failure: LocalizedError {
        case notFound, unreachable(String)
        var errorDescription: String? {
            switch self {
            case .notFound: return "Участок не найден в НСПД. Проверьте кадастровый номер."
            case .unreachable(let reason): return "Росреестр не отдал данные приложению (\(reason))."
            }
        }
    }

    /// Кадастровый номер вида 50:20:0010101:123.
    static func isCadastralNumber(_ text: String) -> Bool {
        text.range(of: #"^\d{2}:\d{2}:\d{6,7}:\d{1,}$"#, options: .regularExpression) != nil
    }

    func parcel(number: String) async throws -> CadastralParcel {
        var components = URLComponents(string: "https://\(Self.host)/api/geoportal/v2/search/geoportal")!
        components.queryItems = [URLQueryItem(name: "query", value: number), URLQueryItem(name: "thematicSearchId", value: "1")]
        let found = NSPDParser.parcels(from: try await get(components.url!))
        guard let parcel = found.first(where: { $0.cadNumber == number }) ?? found.first else { throw Failure.notFound }
        return parcel
    }

    /// Участок в точке (GPS): слой «Земельные участки ЕГРН» (36048) через WMS GetFeatureInfo.
    func parcel(at point: GeoPoint) async throws -> CadastralParcel {
        let x = point.lon * .pi / 180 * GeoMath.earthRadius
        let y = log(tan(.pi / 4 + point.lat * .pi / 360)) * GeoMath.earthRadius
        let half = 40.0
        var components = URLComponents(string: "https://\(Self.host)/api/aeggis/v3/36048/wms")!
        components.queryItems = [
            "REQUEST": "GetFeatureInfo", "SERVICE": "WMS", "VERSION": "1.3.0", "FORMAT": "image/png", "STYLES": "",
            "TRANSPARENT": "true", "LAYERS": "36048", "QUERY_LAYERS": "36048", "RESOLUTION": "96", "WIDTH": "512", "HEIGHT": "512",
            "INFO_FORMAT": "application/json", "FEATURE_COUNT": "5", "I": "256", "J": "256", "CRS": "EPSG:3857",
            "BBOX": "\(x - half),\(y - half),\(x + half),\(y + half)",
        ].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let found = NSPDParser.parcels(from: try await get(components.url!))
        // Несколько участков рядом — тот, в который попадает точка.
        let hit = found.first { parcel in GeoMath.contains(.zero, GeoMath.local(parcel.outline, origin: point)) }
        guard let parcel = hit ?? found.first else { throw Failure.notFound }
        // В ответе карты бывает не всё (ВРИ, стоимость) — дочитываем карточку по номеру.
        if parcel.permittedUse == nil, Self.isCadastralNumber(parcel.cadNumber), let full = try? await self.parcel(number: parcel.cadNumber) {
            return full.isEmpty ? parcel : full
        }
        return parcel
    }

    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { throw Failure.unreachable("код \(status)") }
            return data
        } catch let failure as Failure { throw failure } catch {
            // Подробно: код ошибки iOS и причина проверки сертификата — по ним видно, что чинить.
            let code = (error as NSError).code
            let trust = lastTrustError.map { "; сертификат: \($0)" } ?? ""
            throw Failure.unreachable("\(error.localizedDescription) [код \(code)]\(trust)")
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
              Self.isNSPD(space.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let problem = Self.evaluate(trust, host: space.host) {
            lastTrustError = problem
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            lastTrustError = nil
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    static func isNSPD(_ host: String) -> Bool { host == Self.host || host.hasSuffix(".\(Self.host)") }

    /// Проверка сертификата: сначала обычная iOS, затем цепочка до встроенных сертификатов Минцифры (имя хоста проверяется).
    /// nil — доверяем; иначе — причина отказа. Используется и запросами, и встроенной картой.
    static func evaluate(_ trust: SecTrust, host: String) -> String? {
        if SecTrustEvaluateWithError(trust, nil) { return nil }
        let anchors = trustedDER.compactMap { text -> SecCertificate? in
            guard let der = Data(base64Encoded: text.filter { !$0.isWhitespace }) else { return nil }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
        guard !anchors.isEmpty else { return "нет встроенных сертификатов" }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error) ? nil : ((error as Error?)?.localizedDescription ?? "не доверяем")
    }

    /// Публичная кадастровая карта: на точке (если есть) — для просмотра человеком во встроенном окне.
    static func mapURL(at point: GeoPoint?) -> URL {
        var components = URLComponents(string: "https://\(host)/map")!
        var items = [URLQueryItem(name: "thematic", value: "PKK")]
        if let point {
            let x = point.lon * .pi / 180 * GeoMath.earthRadius
            let y = log(tan(.pi / 4 + point.lat * .pi / 360)) * GeoMath.earthRadius
            items += [URLQueryItem(name: "zoom", value: "18"), URLQueryItem(name: "coordinate_x", value: String(format: "%.2f", x)),
                      URLQueryItem(name: "coordinate_y", value: String(format: "%.2f", y)), URLQueryItem(name: "active_layers", value: "36048")]
        }
        components.queryItems = items
        return components.url!
    }
}
#endif
