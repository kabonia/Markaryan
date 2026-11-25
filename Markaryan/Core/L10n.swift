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
