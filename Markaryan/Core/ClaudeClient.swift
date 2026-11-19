import Foundation
import Security
import UIKit

// MARK: - Secure key storage

/// Stores the Claude API key in the iOS Keychain (encrypted, never in UserDefaults, never in backups of other devices).
enum KeychainStore {
    private static let service = "com.sochiart.markaryan.claude"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account)
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(clean.utf8)
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Models available to the app

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case opus = "claude-opus-5-5"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sonnet: return "Claude Sonnet 5.5 — баланс"
        case .haiku: return "Claude Haiku 5.5 — быстрее и дешевле"
        case .opus: return "Claude Opus 5.5 — максимум качества"
        }
    }
}

enum AIPreference: String, CaseIterable, Identifiable {
    case auto, server
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Claude (если добавлен ключ)"
        case .server: return "Только сервер АртСтроя"
        }
    }
}

enum ClaudeError: LocalizedError {
    case noKey, badResponse, api(String), emptyAnswer
    var errorDescription: String? {
        switch self {
        case .noKey: return "ИИ не подключён: укажите адрес сервера ИИ в AIServer.plist."
        case .badResponse: return "ИИ вернул неожиданный ответ. Попробуйте ещё раз."
        case .api(let message): return message
        case .emptyAnswer: return "ИИ не прислал ответ. Попробуйте переформулировать вопрос."
        }
    }
}

/// One message of a Claude conversation. Images are sent as JPEG (vision).
struct ClaudeTurn {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
    var image: UIImage? = nil
}

// MARK: - Messages API client

/// Minimal client for the Anthropic Messages API: streaming text, vision and forced tool use (structured JSON).
struct ClaudeClient {
    static let keyAccount = "claude-api-key"

    /// Key built into the app from ClaudeKey.plist (owner's own builds only — never publish such a build).
    static var bundledKey: String? {
        #if !DEBUG
        return nil // published builds never read keys from files: AI works through the server
        #endif
        guard let url = Bundle.main.url(forResource: "ClaudeKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = (plist["CLAUDE_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.hasPrefix("sk-ant-api") else { return nil }
        return key
    }
    static let workspaceAccount = "claude-workspace-id"
    static var bundledWorkspaceID: String? {
        guard let url = Bundle.main.url(forResource: "ClaudeKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = (plist["CLAUDE_WORKSPACE_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.hasPrefix("wrkspc_") else { return nil }
        return id
    }
    static var currentWorkspaceID: String? { KeychainStore.read(workspaceAccount) ?? bundledWorkspaceID }
    /// Key entered on this iPhone wins over the built-in one.
    static var currentKey: String? { KeychainStore.read(keyAccount) ?? bundledKey }
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String
    let model: String
    /// Needed when the key is not bound to a workspace (error «must include the anthropic-workspace-id header»).
    var workspaceID: String? = nil

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    private func request(body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty { request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id") }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func content(_ turn: ClaudeTurn) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if let image = turn.image, let data = jpeg(image) {
            blocks.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]])
        }
        blocks.append(["type": "text", "text": turn.text.isEmpty ? "(без текста)" : turn.text])
        return blocks
    }

    /// Claude works best with images up to ~1568 px on the long side.
    static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1568
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private static func messages(_ turns: [ClaudeTurn]) -> [[String: Any]] {
        turns.map { ["role": $0.role.rawValue, "content": content($0)] }
    }

    private static func apiError(_ data: Data, status: Int) -> ClaudeError {
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = raw["error"] as? [String: Any], let message = error["message"] as? String {
            switch status {
            case 401: return .api("Ключ Claude API не подошёл. Проверьте его в настройках ИИ.")
            case 429: return .api("Слишком много запросов к Claude. Подождите минуту.")
            case 529: return .api("Claude сейчас перегружен. Попробуйте чуть позже.")
            default: return .api("Claude: \(message)")
            }
        }
        return .api("Claude ответил с кодом \(status).")
    }

    /// Streams the answer text piece by piece (the reply appears while Claude is still writing).
    func stream(system: String, turns: [ClaudeTurn], maxTokens: Int = 2000) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system, "messages": Self.messages(turns), "stream": true]
                    let (bytes, response) = try await Self.session.bytes(for: try request(body: body))
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte); if data.count > 20_000 { break } }
                        throw Self.apiError(data, status: status)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        if type == "content_block_delta", let delta = event["delta"] as? [String: Any], let text = delta["text"] as? String {
                            continuation.yield(text)
                        } else if type == "error" {
                            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "ошибка потока"
                            throw ClaudeError.api("Claude: \(message)")
                        } else if type == "message_stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Plain (non-streaming) answer.
    func complete(system: String, turns: [ClaudeTurn], maxTokens: Int = 1500) async throws -> String {
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system, "messages": Self.messages(turns)]
        let (data, response) = try await Self.session.data(for: try request(body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Self.apiError(data, status: status) }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any], let content = raw["content"] as? [[String: Any]] else { throw ClaudeError.badResponse }
        let text = content.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.emptyAnswer }
        return text
    }

    /// Forces Claude to answer through one tool, which guarantees JSON that matches `schema`.
    /// Returns the tool input re-encoded as JSON data, ready for `JSONDecoder`.
    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int = 4000) async throws -> Data {
        // Long answers (design, counting) are streamed: a silent connection that waits a minute
        // for a big JSON is often dropped by mobile networks («сетевое соединение потеряно»).
        // One automatic retry covers short drops.
        do {
            return try await structuredStream(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: maxTokens)
        } catch let error as URLError where [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost].contains(error.code) {
            try await Task.sleep(for: .seconds(2))
            return try await structuredStream(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: maxTokens)
        }
    }

    private func structuredStream(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> Data {
        // Some models do not accept a forced tool_choice, so the tool is offered with "auto"
        // and the prompt insists on calling it. A plain JSON text answer is accepted too.
        let strictSystem = system + "\n\nОтвечай ТОЛЬКО вызовом инструмента \(toolName), без текста до или после."
        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "system": strictSystem, "messages": Self.messages(turns),
            "tools": [["name": toolName, "description": toolDescription, "input_schema": schema] as [String: Any]],
            "tool_choice": ["type": "auto"],
            "stream": true
        ]
        let (bytes, response) = try await Self.session.bytes(for: try request(body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 20_000 { break } }
            throw Self.apiError(data, status: status)
        }
        var toolJSON = ""
        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            if type == "content_block_delta", let delta = event["delta"] as? [String: Any] {
                if let partial = delta["partial_json"] as? String { toolJSON += partial }
                if let piece = delta["text"] as? String { text += piece }
            } else if type == "error" {
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? "ошибка потока"
                throw ClaudeError.api("Claude: \(message)")
            } else if type == "message_stop" {
                break
            }
        }
        if !toolJSON.isEmpty, let data = Self.validJSON(toolJSON) { return data }
        if let start = text.firstIndex(of: "{") {
            if let end = text.lastIndex(of: "}"), start < end, let data = Self.validJSON(String(text[start...end])) { return data }
            if let data = Self.validJSON(String(text[start...])) { return data }
        }
        throw ClaudeError.api("ИИ ответил не полностью. Попробуйте ещё раз.")
    }

    /// Parses JSON; if the answer was cut off (token limit), closes the open strings, arrays and objects
    /// after the last complete value so that everything received so far is still usable.
    static func validJSON(_ raw: String) -> Data? {
        if let data = raw.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil { return data }
        var stack: [Character] = []
        var inString = false, escaped = false
        var lastSafe: (index: String.Index, stack: [Character])?
        for index in raw.indices {
            let char = raw[index]
            if inString {
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
                continue
            }
            switch char {
            case "\"": inString = true
            case "{", "[": stack.append(char)
            case "}", "]":
                _ = stack.popLast()
                lastSafe = (raw.index(after: index), stack)
            case ",": lastSafe = (index, stack)
            default: break
            }
        }
        guard let safe = lastSafe else { return nil }
        var repaired = String(raw[..<safe.index])
        while repaired.last == "," || repaired.last == " " || repaired.last == "\n" { repaired.removeLast() }
        for open in safe.stack.reversed() { repaired.append(open == "{" ? "}" : "]") }
        guard let data = repaired.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return data
    }
}

// MARK: - Prompts

enum ClaudePrompts {
    static func assistantSystem(context: AIAssistantContext) -> String {
        var text = """
        Ты — СтройПомощник, ИИ‑инженер компании АртСтрой (ИП Маркарян А.В.), которая строит в Сочи с 2012 года: фундаменты, монолит, коробки, кровли, фасады, инженерные сети, отделку и благоустройство.
        Отвечай по‑русски, коротко и по делу: сначала главный вывод, затем шаги или список. Без воды и канцелярита.
        Учитывай условия Сочи: влажный субтропический климат, сейсмичность 8–9 баллов, склоны и оползни, глинистые грунты, ливни, морской воздух и коррозию.
        Не выдумывай точные цены и сроки, если их нет в данных; давай диапазоны и честно помечай их как ориентир.
        Для несущих конструкций, фундаментов на склоне и усилений всегда напоминай, что решения принимает проектировщик по расчёту.
        Если вопрос требует выезда, точной сметы или договора — предложи связаться с АртСтроем: \(Brand.phoneDisplay), WhatsApp wa.me/\(Brand.phoneDigits).
        Город клиента: \(context.city).
        """
        if !context.lines.isEmpty || context.total != nil {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(context), let json = String(data: data, encoding: .utf8) {
                text += "\n\nДанные текущего расчёта клиента (JSON, суммы в рублях): \(json.prefix(12_000))\nОпирайся на эти цифры, объясняй их и предлагай, где можно сэкономить без потери качества."
            }
        }
        return text
    }

    static let designSystem = """
    Ты — ведущий дизайнер интерьеров и инженер АртСтроя (Сочи). По плану помещения из LiDAR‑скана или замера ты решаешь, что поставить в комнату, и предлагаешь дизайн: отделку, палитру, свет, материалы и бюджет.
    Координаты ты НЕ задаёшь: точную расстановку по правилам делает приложение (проходы не уже 0,7 м, зона открывания двери свободна, перед сантехникой и кухней есть место, высокая мебель не закрывает окна). Ты выбираешь состав, реальные размеры и привязки:
    • items — предметы. width — размер вдоль стены, к которой предмет стоит спиной (у кровати — ширина, у дивана — длина), depth — глубина от стены, height — высота; всё в метрах, не в сантиметрах. Размеры реальные: диван 2,2×0,95; кровать 1,6×2,05; обеденный стол 1,2×0,8; шкаф 1,2–2,0×0,6; унитаз подвесной 0,4×0,55; тумба с раковиной 0,6×0,47; душ 0,9×0,9.
    • placement: wall — спиной к стене; corner — в угол; free — отдельно стоящий (обеденный стол, остров, кресло, ковёр); mounted — на стене выше пола (зеркало, полотенцесушитель, ТВ на стене, бра, бойлер); ceiling — подвесной светильник.
    • wall — номер стены: стены пронумерованы по часовой стрелке, стена 1 — с входной дверью (номера есть на картинке и в JSON). 0 — любая подходящая.
    • relation и target — привязка к другому предмету по его номеру в списке items, начиная с 1: nextTo — рядом (тумбы у кровати, стиральная машина у раковины, холодильник у гарнитура); front — перед ним (журнальный столик перед диваном, кресло у письменного стола); around — вокруг (стулья вокруг стола); opposite — на стене напротив (ТВ напротив дивана); above — над ним (зеркало над раковиной, светильник над столом); under — под ним (ковёр под столиком). Без привязки — none и 0.
    • count — сколько одинаковых предметов (например, 4 стула вокруг стола).
    • prefer: window — ближе к окну, door — ближе ко входу, farFromDoor — подальше от входа, water — ближе к стояку и другой сантехнике, none — без предпочтений.
    • optional: true — можно не ставить, если не поместится.
    • zone — зона комнаты (Кухня, Столовая, Гостиная, Рабочее место); в однозонной комнате оставь пустым.
    Сначала перечисли главное (кровать, диван, гарнитур, сантехника), потом второстепенное. Не больше 25 строк в items. Учитывай двери и окна: высокие шкафы и кухню с верхними шкафами не ставь к стене с окном, если есть другое место.
    Обязательно продумай отделку поверхностей: пол (материал, цвет, укладка, плинтус, переход в мокрых зонах), стены (покраска, штукатурка, панели, молдинги, фартук), потолок (тип, уровни, карнизы, теневой профиль, освещение). Это попадёт в визуализацию и смету.
    Тип помещения строго по назначению:
    • санузел / ванная / туалет — только сантехника и оборудование санузла: toilet (унитаз/инсталляция), sink (раковина с тумбой), shower (душевая), bathtub (ванна), washer (стиральная машина), mirror (зеркало), towel (полотенцесушитель), storage (шкаф, пенал), light (бра, подсветка). Никакой кухни, плиты, холодильника, дивана, кровати, стола, ТВ, ковров;
    • кухня — kitchen, appliance, table, chair; без кровати и сантехники санузла;
    • жилые комнаты — без сантехники санузла.
    Светильники — kind light с понятным названием: «подвесной светильник», «бра», «светодиодная подсветка». Ковёр — kind decor.
    Будь лаконичен: материалов не больше 10, советов не больше 5; описания короткие.
    Пиши по‑русски. Бюджет — реалистичный ориентир для Сочи в рублях (отделка + мебель), без выдуманной точности.
    """

    /// JSON schema of the design proposal (kept as JSON text: easier to read and edit than nested Swift literals).
    static let designSchema: [String: Any] = {
        let json = #"""
        {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "Короткое название концепции"},
            "style": {"type": "string"},
            "summary": {"type": "string", "description": "2–4 предложения: идея и почему она подходит этой планировке"},
            "roomPurpose": {"type": "string", "description": "Назначение помещения, например: гостиная-кухня"},
            "items": {"type": "array", "description": "Мебель и оборудование: что, какого размера и к чему привязано (без координат)", "items": {"type": "object", "properties": {
              "name": {"type": "string", "description": "Название по‑русски, например «Диван 2200» или «Тумба с раковиной 600»"},
              "kind": {"type": "string", "enum": ["sofa", "bed", "table", "chair", "storage", "kitchen", "appliance", "toilet", "sink", "shower", "bathtub", "washer", "mirror", "towel", "bath", "decor", "plant", "light", "desk", "tv"]},
              "width": {"type": "number", "description": "Метры вдоль стены, к которой предмет стоит спиной (длинная сторона)"},
              "depth": {"type": "number", "description": "Метры от стены"},
              "height": {"type": "number", "description": "Высота, метры"},
              "count": {"type": "integer", "description": "Сколько одинаковых, обычно 1"},
              "placement": {"type": "string", "enum": ["wall", "corner", "free", "mounted", "ceiling"]},
              "wall": {"type": "integer", "description": "Номер стены, 0 — любая"},
              "relation": {"type": "string", "enum": ["none", "nextTo", "front", "around", "opposite", "above", "under"]},
              "target": {"type": "integer", "description": "Номер предмета в items (с 1), к которому привязка; 0 — нет"},
              "prefer": {"type": "string", "enum": ["none", "window", "door", "farFromDoor", "water"]},
              "optional": {"type": "boolean"},
              "zone": {"type": "string", "description": "Зона комнаты или пустая строка"}},
              "required": ["name", "kind", "width", "depth", "height", "count", "placement", "wall", "relation", "target", "prefer", "optional", "zone"]}},
            "palette": {"type": "array", "items": {"type": "string", "description": "Цвет в HEX, например #E8DFD3"}},
            "materials": {"type": "array", "items": {"type": "object", "properties": {
              "name": {"type": "string"}, "where": {"type": "string"}, "amount": {"type": "string"}},
              "required": ["name", "where", "amount"]}},
            "lighting": {"type": "string"},
            "tips": {"type": "array", "items": {"type": "string"}},
            "budgetMin": {"type": "number", "description": "Нижняя граница бюджета, руб."},
            "budgetMax": {"type": "number", "description": "Верхняя граница бюджета, руб."},
            "renderPrompt": {"type": "string", "description": "Описание интерьера для фотореалистичной визуализации, 1–3 предложения"},
            "renderPromptEnglish": {"type": "string", "description": "The same interior description in English, max 200 characters"},
            "floor": {"type": "object", "description": "Отделка пола", "properties": {
              "material": {"type": "string", "description": "Например: инженерная доска дуб, укладка ёлочкой"},
              "color": {"type": "string", "description": "HEX основного цвета"},
              "details": {"type": "string", "description": "Укладка, плинтус, стыки, зоны плитки"},
              "english": {"type": "string", "description": "Precise English description for an image model"}},
              "required": ["material", "color", "details", "english"]},
            "walls": {"type": "object", "description": "Отделка стен", "properties": {
              "material": {"type": "string"}, "color": {"type": "string"}, "details": {"type": "string", "description": "Покраска/штукатурка/панели, молдинги, акцентная стена, фартук кухни"}, "english": {"type": "string"}},
              "required": ["material", "color", "details", "english"]},
            "ceiling": {"type": "object", "description": "Потолок", "properties": {
              "material": {"type": "string"}, "color": {"type": "string"}, "details": {"type": "string", "description": "Гипсокартон/натяжной, уровни, теневой профиль, карниз, споты, треки, подсветка"}, "english": {"type": "string"}},
              "required": ["material", "color", "details", "english"]}
          },
          "required": ["title", "style", "summary", "roomPurpose", "floor", "walls", "ceiling", "items", "palette", "materials", "lighting", "tips", "budgetMin", "budgetMax", "renderPrompt", "renderPromptEnglish"]
        }
        """#
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }()
}
