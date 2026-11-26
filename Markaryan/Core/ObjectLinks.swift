import SwiftUI

/// Что из сделанного вне плана комнаты принадлежит какому объекту: обмеры дома, сметы, расчёты, картинки.
/// Привязка по желанию: результат живёт и без объекта, «В объект» добавляет его туда одним нажатием.
@MainActor final class ObjectLinks: ObservableObject {
    static let shared = ObjectLinks()

    enum Kind: String, CaseIterable {
        case houseScan, docEstimate, calculation, picture
        var title: String {
            switch self {
            case .houseScan: "3D‑обмеры дома"
            case .docEstimate: "Сметы"
            case .calculation: "Расчёты"
            case .picture: "Визуализации"
            }
        }
        var icon: String {
            switch self {
            case .houseScan: "house.lodge.fill"
            case .docEstimate: "doc.text.fill"
            case .calculation: "function"
            case .picture: "photo.fill"
            }
        }
    }

    struct Link: Codable, Equatable, Identifiable {
        var kind: String
        var itemID: String
        var object: UUID
        var title: String
        var subtitle: String?
        var addedAt = Date()
        var id: String { kind + ":" + itemID }
    }

    @Published private(set) var links: [Link] = []
    private let key = "objectLinks.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Link].self, from: data) { links = saved }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(links) { UserDefaults.standard.set(data, forKey: key) }
    }

    func object(of kind: Kind, id: String) -> UUID? { links.first { $0.kind == kind.rawValue && $0.itemID == id }?.object }

    func link(_ kind: Kind, id: String, to object: UUID, title: String, subtitle: String? = nil) {
        links.removeAll { $0.kind == kind.rawValue && $0.itemID == id }
        if object != AppStore.looseWorkID {
            links.insert(Link(kind: kind.rawValue, itemID: id, object: object, title: title, subtitle: subtitle), at: 0)
        }
        save()
    }

    func unlink(_ kind: Kind, id: String) {
        links.removeAll { $0.kind == kind.rawValue && $0.itemID == id }
        save()
    }

    func items(in object: UUID, kind: Kind) -> [Link] { links.filter { $0.object == object && $0.kind == kind.rawValue } }
    func count(in object: UUID) -> Int { links.filter { $0.object == object }.count }

    func removeAll(object: UUID) {
        links.removeAll { $0.object == object }
        save()
    }

    /// Новый результат: если человек сейчас работает в объекте — сразу туда.
    func autoLink(_ kind: Kind, id: String, title: String, subtitle: String? = nil, store: AppStore) {
        guard store.inObject, let active = store.activeProjectID, object(of: kind, id: id) == nil else { return }
        link(kind, id: id, to: active, title: title, subtitle: subtitle)
    }
}
