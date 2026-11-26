import Foundation
import UIKit

/// Common interface of the AI the app talks to: the app's AI server (release) or Claude directly (owner's debug builds).
protocol AIEngine {
    func stream(system: String, turns: [ClaudeTurn], maxTokens: Int) -> AsyncThrowingStream<String, Error>
    func complete(system: String, turns: [ClaudeTurn], maxTokens: Int) async throws -> String
    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> Data
    /// The same as `structured`, plus the model that really answered when the engine knows it (it may be a fallback).
    func structuredAnswer(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> (data: Data, model: String?)
}

extension AIEngine {
    func structuredAnswer(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> (data: Data, model: String?) {
        (try await structured(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: maxTokens), nil)
    }
    func stream(system: String, turns: [ClaudeTurn]) -> AsyncThrowingStream<String, Error> { stream(system: system, turns: turns, maxTokens: 2000) }
    func complete(system: String, turns: [ClaudeTurn]) async throws -> String { try await complete(system: system, turns: turns, maxTokens: 1500) }
    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any]) async throws -> Data {
        try await structured(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: 4000)
    }
}

extension ClaudeClient: AIEngine {}

/// Address of the AI server and the optional app token — from AIServer.plist. No AI keys in the app.
enum AIServerConfig {
    private static var plist: [String: Any] {
        guard let url = Bundle.main.url(forResource: "AIServer", withExtension: "plist"), let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return value
    }
    static var baseURL: URL? {
        guard let raw = (plist["AI_SERVER_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.lowercased().hasPrefix("https://"), !raw.contains("example") else { return nil }
        return URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    /// Server of market prices and partner contractors (may differ from the AI server). Falls back to the AI server.
    static var marketURL: URL? {
        guard let raw = (plist["MARKET_SERVER_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.lowercased().hasPrefix("https://"), !raw.contains("example") else { return baseURL }
        return URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    static var appToken: String { (plist["APP_TOKEN"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    /// The OpenRouter key built into the app (OPENROUTER_API_KEY in AIServer.plist, which is not in git):
    /// chat, design and pictures work without a server and without asking the user for a key.
    static var openRouterKey: String? {
        // В релизной сборке ключа ИИ в приложении быть не может: его достанут из файла приложения (аудит 2.8).
        #if !DEBUG
        return nil
        #endif
        guard let raw = (plist["OPENROUTER_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("sk-or-"), raw.count > 20 else { return nil }
        return raw
    }

    /// Random id of this installation (kept in the Keychain): the server counts daily limits by it.
    static var installID: String {
        if let saved = KeychainStore.read("ai-install-id"), saved.count >= 16 { return saved }
        let id = UUID().uuidString
        KeychainStore.save(id, account: "ai-install-id")
        return id
    }
}

/// A picture engine on the server (Nano Banana Pro, GPT Image, FLUX…).
struct ImageEngine: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
}

/// A text model the server offers for the design (Claude Opus 5.5…).
struct AIModelInfo: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
}

/// A photoreal picture and the engine that made it.
struct RenderedImage {
    let image: UIImage
    let engine: String
    let title: String
}

/// What the server can do right now (and how much of today's limit is left).
struct AICapabilities: Decodable {
    var chat = false
    var vision = false
    var imageGenerate = false
    /// Old engine names ("flux", "gpt") that app versions up to 1.2 understand.
    var imageEdit: [String] = []
    /// Picture engines in the server's order: the first answers when no engine is chosen.
    var imageEngines: [ImageEngine] = []
    var providers: [String] = []
    /// Models the user may pick on the «Дизайн» step (empty — an older server or no OpenRouter: it chooses itself).
    var designModels: [AIModelInfo] = []
    var renderModels: [ImageEngine] = []

    init() {}
    private enum CodingKeys: String, CodingKey { case chat, vision, imageGenerate, imageEdit, imageEngines, providers, designModels, renderModels }
    /// Lenient: an older server without some fields still works.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chat = (try? c.decode(Bool.self, forKey: .chat)) ?? false
        vision = (try? c.decode(Bool.self, forKey: .vision)) ?? false
        imageGenerate = (try? c.decode(Bool.self, forKey: .imageGenerate)) ?? false
        imageEdit = (try? c.decode([String].self, forKey: .imageEdit)) ?? []
        imageEngines = (try? c.decode([ImageEngine].self, forKey: .imageEngines)) ?? []
        providers = (try? c.decode([String].self, forKey: .providers)) ?? []
        designModels = (try? c.decode([AIModelInfo].self, forKey: .designModels)) ?? []
        renderModels = (try? c.decode([ImageEngine].self, forKey: .renderModels)) ?? []
    }
}

/// Client of the app's AI server (GigaChat / YandexGPT behind it, keys only on the server).
struct ServerAIClient: AIEngine {
    let base: URL
    /// The model the user picked for the design (OpenRouter id): the server tries it first. Nil — the server's order.
    var designModel: String? = nil
    /// "helper": the server answers with its cheap, fast model (the in-app helper).
    var tier: String? = nil

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300 // each request sets its own wait; renders may need up to 5 minutes
        configuration.timeoutIntervalForResource = 330
        return URLSession(configuration: configuration)
    }()

    private func request(_ path: String, body: [String: Any]?, accept: String = "application/json", timeout: TimeInterval = 200) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = timeout
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        request.setValue(AppLanguage.code, forHTTPHeaderField: "X-App-Language")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func messages(_ turns: [ClaudeTurn]) -> [[String: Any]] {
        turns.map { turn in
            var item: [String: Any] = ["role": turn.role.rawValue, "text": turn.text]
            if let image = turn.image, let jpeg = ClaudeClient.jpeg(image) { item["image"] = jpeg.base64EncodedString() }
            return item
        }
    }

    /// Market prices with sources for every material and work of a design project (the server searches the web).
    func priceEstimate(city: String, items: [MarketEstimateRequestItem]) async throws -> MarketEstimate {
        let json = try await post("v1/ai/price-estimate", ["city": city, "items": items.map(\.dictionary)], timeout: 280)
        return try JSONDecoder().decode(MarketEstimate.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Name of a long job for the «готово» notification; nil — a quick request that does not need the background session.
    private static func backgroundTitle(_ path: String) -> String? {
        switch path {
        case "v1/ai/image-edit", "v1/ai/image": return "Визуализация"
        case "v1/ai/json": return "Дизайн‑проект"
        case "v1/ai/price-estimate": return "Смета по рынку"
        default: return nil
        }
    }

    private static func failure(_ data: Data, status: Int) -> Error {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch status {
        case 429: return ClaudeError.api(message ?? "Дневной лимит ИИ исчерпан. Попробуйте завтра.")
        case 503: return ClaudeError.api(message ?? "ИИ временно недоступен. Попробуйте позже.")
        default: return ClaudeError.api(message ?? "Сервер ИИ ответил с кодом \(status).")
        }
    }

    private func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 200) async throws -> [String: Any] {
        let data: Data
        let status: Int
        if let title = Self.backgroundTitle(path) {
            // Long jobs survive minimising the app; a notification tells when they are done.
            let (received, response) = try await BackgroundAI.shared.send(try request(path, body: body, timeout: timeout), title: title)
            data = received; status = response.statusCode
        } else {
            let (received, response) = try await Self.session.data(for: try request(path, body: body, timeout: timeout))
            data = received; status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard (200...299).contains(status) else { throw Self.failure(data, status: status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        return json
    }

    func stream(system: String, turns: [ClaudeTurn], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = ["system": system, "messages": Self.messages(turns), "maxTokens": maxTokens, "stream": true]
                    if let tier { body["tier"] = tier }
                    let (bytes, response) = try await Self.session.bytes(for: try request("v1/ai/chat", body: body, accept: "text/event-stream"))
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(data, status: status)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                        if let delta = event["delta"] as? String { continuation.yield(delta) }
                        if let error = event["error"] as? String { throw ClaudeError.api(error) }
                        if event["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(system: String, turns: [ClaudeTurn], maxTokens: Int) async throws -> String {
        var body: [String: Any] = ["system": system, "messages": Self.messages(turns), "maxTokens": maxTokens]
        if let tier { body["tier"] = tier }
        let json = try await post("v1/ai/chat", body)
        guard let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.emptyAnswer }
        return text
    }

    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> Data {
        try await structuredAnswer(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: maxTokens).data
    }

    /// The server says which model answered (the picked one or its fallback); an older server says nothing.
    func structuredAnswer(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> (data: Data, model: String?) {
        var body: [String: Any] = ["system": system, "messages": Self.messages(turns), "name": toolName, "description": toolDescription, "schema": schema, "maxTokens": maxTokens]
        if let designModel { body["model"] = designModel }
        func answer(_ json: [String: Any]) throws -> (data: Data, model: String?) {
            guard let result = json["json"] else { throw ClaudeError.badResponse }
            return (try JSONSerialization.data(withJSONObject: result), json["model"] as? String)
        }
        do {
            return try answer(try await post("v1/ai/json", body))
        } catch let error as URLError where [.networkConnectionLost, .timedOut].contains(error.code) {
            return try answer(try await post("v1/ai/json", body)) // one retry on a dropped mobile connection
        }
    }

    // MARK: Images

    func capabilities() async throws -> AICapabilities {
        let (data, response) = try await Self.session.data(for: try request("v1/ai/capabilities", body: nil))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Self.failure(data, status: status) }
        return try JSONDecoder().decode(AICapabilities.self, from: data)
    }

    /// Photoreal edit of an image (the exact 3D render or a photo) on the server.
    /// `engine`: "auto" — the server's engines in order, the next one when one fails; an engine id — only that engine.
    /// `prefer`: with "auto", the engine the user picked goes first (an older server ignores it).
    func editImage(_ image: UIImage, prompt: String, engine: String = "auto", prefer: String? = nil, references: [MaterialReference] = []) async throws -> RenderedImage {
        let maxSide: CGFloat = 1536
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.88) else { throw ClaudeError.api("Не удалось подготовить изображение.") }
        let shape = Self.shape(of: image)
        var body: [String: Any] = ["image": jpeg.base64EncodedString(), "prompt": prompt + MaterialReference.prompt(references), "engine": engine, "size": shape.size, "aspectRatio": shape.ratio]
        // The client's own materials and products go as extra reference pictures after the scene.
        let samples = references.filter(\.ready).compactMap { $0.jpeg?.base64EncodedString() }
        if !samples.isEmpty { body["references"] = samples }
        if let prefer { body["prefer"] = prefer }
        // Seedream takes about two minutes for a frame, a fallback after it a bit more.
        let json = try await post("v1/ai/image-edit", body, timeout: 300)
        guard let base64 = json["image"] as? String, let data = Data(base64Encoded: base64), let result = UIImage(data: data) else { throw ClaudeError.badResponse }
        let id = json["engine"] as? String ?? engine
        return RenderedImage(image: result, engine: id, title: json["title"] as? String ?? id)
    }

    /// Nearest standard aspect ratio of the picture and the matching output size (multiples of 16).
    static func shape(of image: UIImage) -> (ratio: String, size: String) {
        let ratio = Double(image.size.width / max(1, image.size.height))
        let options: [(Double, String, String)] = [(1, "1:1", "1024x1024"), (4.0 / 3, "4:3", "1536x1152"), (3.0 / 4, "3:4", "1152x1536"),
                                                   (3.0 / 2, "3:2", "1536x1024"), (2.0 / 3, "2:3", "1024x1536"), (16.0 / 9, "16:9", "1536x864"), (9.0 / 16, "9:16", "864x1536")]
        let best = options.min { abs(log($0.0 / ratio)) < abs(log($1.0 / ratio)) }!
        return (best.1, best.2)
    }

    /// Picture by description (the server's picture engines, or Kandinsky / Alice AI ART).
    /// A picture by description; `prefer` — the engine the user picked goes first (an older server ignores it).
    func generateImage(prompt: String, prefer: String? = nil) async throws -> UIImage {
        var body: [String: Any] = ["prompt": prompt]
        if let prefer { body["prefer"] = prefer }
        let json = try await post("v1/ai/image", body, timeout: 300)
        guard let base64 = json["image"] as? String, let data = Data(base64Encoded: base64), let result = UIImage(data: data) else { throw ClaudeError.badResponse }
        return result
    }
}
