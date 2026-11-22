import Foundation
import UIKit

/// Pictures through the app's OpenRouter key (sk-or-…, OPENROUTER_API_KEY in AIServer.plist).
/// The same request as the АртСтрой server makes: POST /api/v1/images, the reference picture as `input_references`.
/// Used when there is no AI server: renders of the exact 3D model, design by photo, pictures by description.
struct OpenRouterImageClient {
    let apiKey: String

    /// In order: the first model answers, the next ones step in when it fails (as OPENROUTER_IMAGE_MODELS on the server).
    static let models = ["google/gemini-3-pro-image", "openai/gpt-image-2.6-sunburst", "black-forest-labs/flux-3-image"]
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/images")!

    /// The OpenRouter key of the app: built in (AIServer.plist) or saved in the Keychain.
    static var configuredKey: String? {
        guard let key = ClaudeClient.currentKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              ClaudeClient.isOpenRouterKey(key) else { return nil }
        return key
    }
    static var isConfigured: Bool { configuredKey != nil }

    enum OpenRouterImageError: LocalizedError {
        case message(String)
        /// Busy, overloaded or too slow: worth one more try.
        case transient(String)
        var errorDescription: String? {
            switch self { case .message(let text), .transient(let text): return text }
        }
    }

    static func title(_ model: String) -> String {
        if let known = RenderModel(rawValue: model) { return known.title }
        if model == RenderModel.lastResort { return "FLUX 3" }
        let vendor = model.split(separator: "/").first.map(String.init) ?? ""
        if vendor == "google" { return "Nano Banana Pro" }
        if vendor == "openai" { return "GPT Image" }
        if vendor == "black-forest-labs" { return "FLUX" }
        if vendor == "bytedance-seed" { return "Seedream" }
        return model
    }

    /// Aspect of the picture to make, from the reference (renders are 4:3, phone photos 3:4 or 4:3).
    static func aspectRatio(for image: UIImage?) -> String {
        guard let image, image.size.height > 0 else { return "4:3" }
        let ratio = image.size.width / image.size.height
        if ratio > 1.55 { return "16:9" }
        if ratio > 1.15 { return "4:3" }
        if ratio > 0.87 { return "1:1" }
        if ratio > 0.65 { return "3:4" }
        return "9:16"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // A 2K render waits silently until the picture is ready: Seedream and a busy queue need several minutes.
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    /// JPEG of the reference, the long side at most 2048 px.
    private static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 2048
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let target = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.9)
    }

    /// One picture from one model.
    func image(prompt: String, reference: UIImage?, aspectRatio: String, model: String) async throws -> UIImage {
        var body: [String: Any] = ["model": model, "prompt": String(prompt.prefix(30_000)), "n": 1, "aspect_ratio": aspectRatio]
        let vendor = model.split(separator: "/").first.map(String.init) ?? ""
        if vendor == "openai" { body["quality"] = "high" } else { body["resolution"] = "2K" }
        if let reference, let data = Self.jpeg(reference) {
            body["input_references"] = [["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]]
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ArtStroy", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            if status == 401 { throw OpenRouterImageError.message("OpenRouter не принял ключ. Проверьте OPENROUTER_API_KEY в AIServer.plist.") }
            if status == 402 { throw OpenRouterImageError.message("На балансе OpenRouter закончились деньги — пополните его на openrouter.ai.") }
            if [408, 429, 500, 502, 503, 504, 520, 522, 524, 529].contains(status) {
                throw OpenRouterImageError.transient("\(Self.title(model)) занят или отвечал слишком долго (\(status)).")
            }
            throw OpenRouterImageError.message("\(Self.title(model)): \(detail ?? "ошибка \(status)")")
        }
        let first = (json?["data"] as? [[String: Any]])?.first
        if let base64 = first?["b64_json"] as? String, let decoded = Data(base64Encoded: base64), let picture = UIImage(data: decoded) {
            return picture
        }
        if let link = first?["url"] as? String {
            if link.hasPrefix("data:"), let comma = link.firstIndex(of: ",") {
                let payload = String(link[link.index(after: comma)...])
                if let decoded = Data(base64Encoded: payload), let picture = UIImage(data: decoded) { return picture }
            } else if let url = URL(string: link) {
                let (file, _) = try await Self.session.data(from: url)
                if let picture = UIImage(data: file) { return picture }
            }
        }
        throw OpenRouterImageError.message("\(Self.title(model)) не вернул картинку.")
    }

    /// The first model that answers; the next one when it fails. `models` — the order to try (the user's pick first).
    /// A busy model or a request that timed out is tried once more after a pause before moving on.
    func render(prompt: String, reference: UIImage?, models: [String] = OpenRouterImageClient.models) async throws -> RenderedImage {
        let ratio = Self.aspectRatio(for: reference)
        var lastError: Error = OpenRouterImageError.message("OpenRouter не вернул картинку.")
        for model in models {
            for attempt in 0..<2 {
                do {
                    let picture = try await image(prompt: prompt, reference: reference, aspectRatio: ratio, model: model)
                    return RenderedImage(image: picture, engine: "openrouter:\(model)", title: Self.title(model))
                } catch let error as OpenRouterImageError {
                    lastError = error
                    if case .message(let text) = error {
                        // A rejected key or an empty balance will not be fixed by the next model.
                        if text.hasPrefix("OpenRouter не принял") || text.hasPrefix("На балансе") { throw error }
                        break
                    }
                    if attempt == 0 { try await Task.sleep(for: .seconds(4)) }
                } catch let error as URLError {
                    if error.code == .notConnectedToInternet { throw error }
                    guard [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code) else { throw error }
                    lastError = OpenRouterImageError.transient(error.code == .timedOut
                        ? "\(Self.title(model)) рисовал дольше 10 минут."
                        : "Связь прервалась, пока \(Self.title(model)) рисовал.")
                    if attempt == 0 { try await Task.sleep(for: .seconds(3)) }
                } catch {
                    if error is CancellationError { throw error }
                    lastError = error
                    break
                }
            }
        }
        throw lastError
    }
}
