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

    static func format(_ value: Double, digits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
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
    /// Russian Trusted Root CA (Минцифры), DER в base64. SHA‑256 отпечаток:
    /// D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31 (действует до 2032 г.).
    private static let russianRootDER = """
    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
    """

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
            case .unreachable(let reason): return "Кадастровая карта не ответила (\(reason)). Она работает только из России; попробуйте позже или введите номер вручную."
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
        } catch let failure as Failure { throw failure } catch { throw Failure.unreachable(error.localizedDescription) }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
              space.host == Self.host || space.host.hasSuffix(".\(Self.host)") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Сначала обычная проверка iOS; не прошла — проверка цепочки до встроенного корня Минцифры (имя хоста проверяется).
        if SecTrustEvaluateWithError(trust, nil) { completionHandler(.useCredential, URLCredential(trust: trust)); return }
        guard let der = Data(base64Encoded: Self.russianRootDER.filter { !$0.isWhitespace }),
              let root = SecCertificateCreateWithData(nil, der as CFData) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, space.host as CFString))
        SecTrustSetAnchorCertificates(trust, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        if SecTrustEvaluateWithError(trust, nil) { completionHandler(.useCredential, URLCredential(trust: trust)) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
#endif
