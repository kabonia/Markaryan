import SwiftUI

// Перевод строк, которые компоненты получают как String (кнопки, карточки, подсказки): ищем в каталоге
// Localizable.xcstrings; нет перевода — показываем как есть. Язык — по настройке iPhone.
extension String {
    var tr: String { Bundle.main.localizedString(forKey: self, value: self, table: nil) }
}

extension Substring {
    var tr: String { String(self).tr }
}

extension LocalizedStringKey {
    var tr: LocalizedStringKey { self }
}

extension AttributedString {
    var tr: AttributedString { self }
}

enum AppLanguage {
    /// Язык интерфейса, который выбрала система для приложения (ru, en, es, zh-Hans…).
    static var code: String { Bundle.main.preferredLocalizations.first ?? "ru" }
    static var isRussian: Bool { code.hasPrefix("ru") }
}

/// Единицы измерения: метрические или американские (футы, дюймы, кв. футы). По умолчанию — как в стране iPhone,
/// человек может переключить («м / ft»); выбор хранится в UserDefaults.
enum Units {
    static let key = "units.imperial"
    static var imperial: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
            return Locale.current.measurementSystem == .us
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private static func number(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.isRussian ? Locale(identifier: "ru_RU") : .current
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Длина: «8,00 м» или «26′ 3″» (до дюйма; меньше фута — «5 ½″»).
    static func length(_ meters: Double, digits: Int = 2) -> String {
        guard imperial else { return "\(number(meters, digits: digits)) " + "м".tr }
        let totalInches = (meters / 0.0254 * 2).rounded() / 2   // до ½ дюйма
        let feet = Int(totalInches / 12)
        let inches = totalInches - Double(feet) * 12
        let inchText = inches.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(inches))" : "\(Int(inches)) ½"
        return feet > 0 ? "\(feet)′ \(inchText)″" : "\(inchText)″"
    }

    /// Погрешность: «±2 см» или «±¾″».
    static func tolerance(_ meters: Double) -> String {
        guard imperial else { return "±\(number(meters * 100, digits: 0)) " + "см".tr }
        return "±\(number(meters / 0.0254, digits: 1))″"
    }

    /// Площадь: «64,0 м²» или «689 sq ft».
    static func area(_ squareMeters: Double, digits: Int = 1) -> String {
        guard imperial else { return "\(number(squareMeters, digits: digits)) м²" }
        return "\(number(squareMeters * 10.7639, digits: 0)) sq ft"
    }

    /// Разница с рулеткой: «+0,4 см» или «+0.2″».
    static func delta(cm: Double) -> String {
        let sign = cm >= 0 ? "+" : "−"
        guard imperial else { return "\(sign)\(number(abs(cm), digits: 1)) " + "см".tr }
        return "\(sign)\(number(abs(cm) / 2.54, digits: 2))″"
    }

    /// Длина погонная для сметы: «36,0 м» или «118 ft».
    static func run(_ meters: Double) -> String {
        guard imperial else { return "\(number(meters, digits: 1)) " + "м".tr }
        return "\(number(meters / 0.3048, digits: 0)) ft"
    }
}
