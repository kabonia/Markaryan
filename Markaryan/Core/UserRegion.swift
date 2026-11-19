import Foundation
import CoreLocation

/// The user's city: prices in estimates and partner contractors are picked for it.
/// Comes from the device location (city only, coordinates rounded to ~1 km) or is chosen by hand.
struct UserRegion: Codable, Hashable, Identifiable {
    enum Source: String, Codable { case location, manual }
    var city: String
    var region: String
    var latitude: Double?
    var longitude: Double?
    var source: Source
    var id: String { city + "|" + region }
    var title: String { region.isEmpty || region == city ? city : "\(city), \(region)" }

    private static func city(_ city: String, _ region: String, _ lat: Double, _ lon: Double) -> UserRegion {
        UserRegion(city: city, region: region, latitude: lat, longitude: lon, source: .manual)
    }

    /// Cities for manual choice when location is unavailable. Any other city can be typed in.
    static let cities: [UserRegion] = [
        city("Сочи", "Краснодарский край", 43.585, 39.723),
        city("Краснодар", "Краснодарский край", 45.035, 38.975),
        city("Новороссийск", "Краснодарский край", 44.723, 37.769),
        city("Анапа", "Краснодарский край", 44.894, 37.316),
        city("Геленджик", "Краснодарский край", 44.561, 38.077),
        city("Туапсе", "Краснодарский край", 44.098, 39.074),
        city("Армавир", "Краснодарский край", 44.999, 41.129),
        city("Майкоп", "Республика Адыгея", 44.609, 40.106),
        city("Ростов-на-Дону", "Ростовская область", 47.222, 39.718),
        city("Ставрополь", "Ставропольский край", 45.044, 41.969),
        city("Пятигорск", "Ставропольский край", 44.049, 43.060),
        city("Махачкала", "Республика Дагестан", 42.983, 47.504),
        city("Владикавказ", "Республика Северная Осетия — Алания", 43.020, 44.680),
        city("Нальчик", "Кабардино-Балкарская Республика", 43.485, 43.607),
        city("Грозный", "Чеченская Республика", 43.318, 45.698),
        city("Волгоград", "Волгоградская область", 48.708, 44.513),
        city("Астрахань", "Астраханская область", 46.348, 48.033),
        city("Симферополь", "Республика Крым", 44.952, 34.102),
        city("Севастополь", "Севастополь", 44.616, 33.525),
        city("Ялта", "Республика Крым", 44.495, 34.166),
        city("Москва", "Москва", 55.756, 37.617),
        city("Санкт-Петербург", "Санкт-Петербург", 59.939, 30.316),
        city("Воронеж", "Воронежская область", 51.672, 39.184),
        city("Белгород", "Белгородская область", 50.595, 36.587),
        city("Курск", "Курская область", 51.730, 36.193),
        city("Липецк", "Липецкая область", 52.608, 39.599),
        city("Тула", "Тульская область", 54.193, 37.617),
        city("Рязань", "Рязанская область", 54.629, 39.736),
        city("Калуга", "Калужская область", 54.513, 36.261),
        city("Брянск", "Брянская область", 53.243, 34.364),
        city("Смоленск", "Смоленская область", 54.782, 32.045),
        city("Тверь", "Тверская область", 56.859, 35.911),
        city("Ярославль", "Ярославская область", 57.626, 39.894),
        city("Иваново", "Ивановская область", 57.000, 40.974),
        city("Нижний Новгород", "Нижегородская область", 56.327, 44.006),
        city("Казань", "Республика Татарстан", 55.796, 49.106),
        city("Чебоксары", "Чувашская Республика", 56.146, 47.251),
        city("Ульяновск", "Ульяновская область", 54.314, 48.403),
        city("Самара", "Самарская область", 53.195, 50.101),
        city("Саратов", "Саратовская область", 51.533, 46.034),
        city("Пенза", "Пензенская область", 53.195, 45.018),
        city("Оренбург", "Оренбургская область", 51.768, 55.097),
        city("Уфа", "Республика Башкортостан", 54.735, 55.958),
        city("Ижевск", "Удмуртская Республика", 56.852, 53.206),
        city("Киров", "Кировская область", 58.603, 49.668),
        city("Пермь", "Пермский край", 58.010, 56.229),
        city("Екатеринбург", "Свердловская область", 56.838, 60.597),
        city("Челябинск", "Челябинская область", 55.160, 61.402),
        city("Тюмень", "Тюменская область", 57.153, 65.534),
        city("Омск", "Омская область", 54.989, 73.368),
        city("Новосибирск", "Новосибирская область", 55.030, 82.920),
        city("Томск", "Томская область", 56.484, 84.948),
        city("Барнаул", "Алтайский край", 53.348, 83.780),
        city("Кемерово", "Кемеровская область", 55.355, 86.087),
        city("Красноярск", "Красноярский край", 56.010, 92.852),
        city("Иркутск", "Иркутская область", 52.287, 104.305),
        city("Хабаровск", "Хабаровский край", 48.480, 135.072),
        city("Владивосток", "Приморский край", 43.115, 131.885),
        city("Калининград", "Калининградская область", 54.710, 20.510),
        city("Архангельск", "Архангельская область", 64.539, 40.516),
        city("Мурманск", "Мурманская область", 68.970, 33.075),
    ]
}

/// One-shot location request for the city. Never asks again after the user said no.
@MainActor final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var requestNumber = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }

    func currentLocation() async -> CLLocation? {
        guard !isDenied, continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestNumber += 1
            let number = requestNumber
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                // Time out only this request, never a newer one.
                guard let self, self.requestNumber == number else { return }
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    /// City and region of a point, in Russian.
    static func region(for location: CLLocation) async -> UserRegion? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ru_RU")).first else { return nil }
        guard let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea, !city.isEmpty else { return nil }
        let round = { (value: Double) in (value * 100).rounded() / 100 }
        return UserRegion(city: city, region: placemark.administrativeArea ?? "", latitude: round(location.coordinate.latitude), longitude: round(location.coordinate.longitude), source: .location)
    }
}

/// A contractor connected to the platform.
struct Partner: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    var description: String?
    var categories: [String]?
    var phone: String?
    var whatsapp: String?
    var site: String?
    var rating: Double?
    /// Ad marking data (advertiser, erid), kept on the server; not shown in the app for now.
    var advertiser: String?
    var erid: String?

    var phoneURL: URL? { phone.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) } }
    func whatsAppURL(text: String) -> URL? {
        guard let digits = whatsapp?.filter(\.isNumber), !digits.isEmpty else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }
    var siteURL: URL? {
        guard let site, !site.isEmpty else { return nil }
        return URL(string: site.lowercased().hasPrefix("http") ? site : "https://" + site)
    }
}
struct PartnersResponse: Decodable { let partners: [Partner] }
