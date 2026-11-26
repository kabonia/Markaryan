import SwiftUI
import UIKit

/// Поддержка: обращения к менеджеру. Человек пишет здесь → менеджер получает в Telegram с номером аккаунта, балансом
/// и последними списаниями → его ответ приходит сюда. Сервер: /v1/support/tickets.
struct SupportTicket: Decodable, Identifiable, Equatable {
    struct Message: Decodable, Equatable, Identifiable {
        var from: String
        var text: String
        var at: String
        var photo: Bool?
        var credits: Int?
        var id: String { at + from + String(text.prefix(12)) }
        var isManager: Bool { from == "manager" }
        var date: Date? { SupportTicket.parse(at) }
    }
    var id: String
    var number: Int
    var topic: String
    var topicTitle: String
    var feature: String?
    var status: String
    var createdAt: String
    var updatedAt: String
    var messages: [Message]

    var statusTitle: String {
        switch status {
        case "answered": "Есть ответ"
        case "closed": "Закрыто"
        default: "Ждёт ответа"
        }
    }
    var statusColor: Color { status == "answered" ? Theme.success : status == "closed" ? Theme.muted : Theme.gold }
    var lastManagerAt: String? { messages.last(where: \.isManager)?.at }

    static func parse(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

@MainActor final class SupportCenter: ObservableObject {
    static let shared = SupportCenter()

    /// Темы — те же ключи, что на сервере.
    static let topics: [(key: String, title: String, icon: String)] = [
        ("broken", "Не работает функция", "exclamationmark.triangle.fill"),
        ("paid", "Оплатил, но не получил результат", "creditcard.trianglebadge.exclamationmark"),
        ("howto", "Не разобрался, как пользоваться", "questionmark.circle.fill"),
        ("payment", "Оплата и возврат", "rublesign.circle.fill"),
        ("idea", "Предложение", "lightbulb.fill"),
        ("other", "Другое", "ellipsis.bubble.fill"),
    ]
    static let features = ["3D‑обмер дома", "Дизайн‑проект комнаты", "Визуализация", "Счёт по фото", "Смета по документам",
                           "Цены по рынку", "Вопрос ИИ", "Помощник", "Скан комнаты", "Калькуляторы и сметы", "Оплата и баланс", "Другое"]

    @Published private(set) var tickets: [SupportTicket] = []
    @Published private(set) var loading = false
    @Published var error: String?
    /// Когда человек последний раз открывал каждое обращение — чтобы показать «новый ответ».
    private var seenRaw: String {
        get { UserDefaults.standard.string(forKey: "supportSeen") ?? "{}" }
        set { UserDefaults.standard.set(newValue, forKey: "supportSeen") }
    }

    var unread: Int { tickets.filter(isUnread).count }
    func isUnread(_ t: SupportTicket) -> Bool {
        guard let at = t.lastManagerAt else { return false }
        return (seen[t.id] ?? "") < at
    }
    func markSeen(_ t: SupportTicket) {
        var map = seen; map[t.id] = t.messages.last?.at ?? t.updatedAt
        seenRaw = (try? String(data: JSONEncoder().encode(map), encoding: .utf8)) ?? "{}"
        objectWillChange.send()
    }
    private var seen: [String: String] { (try? JSONDecoder().decode([String: String].self, from: Data(seenRaw.utf8))) ?? [:] }

    func refresh() async {
        guard let base = AIServerConfig.marketURL else { return }
        loading = true; defer { loading = false }
        guard let (data, response) = try? await URLSession.shared.data(for: request(base, "v1/support/tickets")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        struct List: Decodable { var tickets: [SupportTicket] }
        if let list = try? JSONDecoder().decode(List.self, from: data) { tickets = list.tickets }
    }

    /// Новое обращение. Возвращает созданное или nil (текст ошибки — в `error`).
    func create(topic: String, feature: String?, text: String, contact: String, photo: UIImage?) async -> SupportTicket? {
        var body: [String: Any] = ["topic": topic, "text": text, "contact": contact, "screen": HelperCenter.shared.screen,
                                   "appVersion": Brand.appVersion, "device": UIDevice.current.model, "language": AppLanguage.code]
        if let feature { body["feature"] = feature }
        if let jpeg = photo.flatMap(Self.jpeg) { body["photo"] = jpeg.base64EncodedString() }
        let ticket = await post("v1/support/tickets", body)
        if let ticket { upsert(ticket); markSeen(ticket) }
        return ticket
    }

    func reply(_ ticket: SupportTicket, text: String, photo: UIImage?) async -> Bool {
        var body: [String: Any] = ["text": text]
        if let jpeg = photo.flatMap(Self.jpeg) { body["photo"] = jpeg.base64EncodedString() }
        guard let updated = await post("v1/support/tickets/\(ticket.id)/messages", body) else { return false }
        upsert(updated); markSeen(updated)
        return true
    }

    private func upsert(_ t: SupportTicket) {
        if let i = tickets.firstIndex(where: { $0.id == t.id }) { tickets[i] = t } else { tickets.insert(t, at: 0) }
    }

    private func post(_ path: String, _ body: [String: Any]) async -> SupportTicket? {
        guard let base = AIServerConfig.marketURL else { error = "Нет связи с сервером.".tr; return nil }
        var req = request(base, path)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200, let t = try? JSONDecoder().decode(SupportTicket.self, from: data) { error = nil; return t }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            error = message ?? "Не получилось отправить. Попробуйте ещё раз.".tr
        } catch {
            self.error = "Нет интернета — сообщение не отправлено.".tr
        }
        return nil
    }

    private func request(_ base: URL, _ path: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        request.setValue(AppLanguage.code, forHTTPHeaderField: "X-App-Language")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Снимок экрана для менеджера: до 1600 px по длинной стороне, JPEG до ~1,4 МБ.
    static func jpeg(_ image: UIImage) -> Data? {
        let side = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(side, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [0.75, 0.6, 0.45, 0.3] {
            if let data = resized.jpegData(compressionQuality: quality), data.count < 1_400_000 { return data }
        }
        return nil
    }
}
