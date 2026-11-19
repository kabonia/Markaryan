import Foundation
import UIKit

/// OpenAI GPT Image: photorealistic edit of the exact 3D render (POST /v1/images/edits, multipart, base64 answer).
/// Only for the owner's debug builds with a key in the app; release builds go through the AI server.
struct OpenAIImageClient {
    let apiKey: String
    var model = "gpt-image-2.6-sunburst"

    /// Key from the Keychain or OpenAIKey.plist (owner's own builds). Never in the code.
    static var configuredKey: String? {
        if let saved = KeychainStore.read("openai-api-key") { return saved }
        #if !DEBUG
        return nil // in the App Store build GPT Image works only through the AI server
        #endif
        guard let url = Bundle.main.url(forResource: "OpenAIKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist["OPENAI_API_KEY"] as? String, !raw.contains("ВСТАВЬТЕ") else { return nil }
        var key = raw
        for prefix in ["Bearer ", "OPENAI_API_KEY="] where key.hasPrefix(prefix) { key = String(key.dropFirst(prefix.count)) }
        key = String(key.unicodeScalars.filter { $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\"" && $0 != "'" }.map(Character.init))
        return key.hasPrefix("sk-") && key.count >= 20 ? key : nil
    }
    static var isConfigured: Bool { configuredKey != nil }

    enum OpenAIImageError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    /// Size divisible by 16 with the aspect of the source (4:3 renders → 1536×1152).
    private static func size(for image: UIImage) -> String {
        let ratio = image.size.width / max(1, image.size.height)
        if abs(ratio - 4.0 / 3.0) < 0.05 { return "1536x1152" }
        if ratio > 1.2 { return "1536x1024" }
        if ratio < 0.83 { return "1024x1536" }
        return "1024x1024"
    }

    func edit(_ image: UIImage, prompt: String) async throws -> UIImage {
        let maxSide: CGFloat = 1536
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let png = resized.pngData() else { throw OpenAIImageError.message("Не удалось подготовить изображение для GPT.") }

        let boundary = "ArtStroy-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("prompt", String(prompt.prefix(30000)))
        field("size", Self.size(for: image))
        field("quality", "high")
        field("output_format", "jpeg")
        field("n", "1")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"render.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(png)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...299).contains(status) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "код \(status)"
            switch status {
            case 401: throw OpenAIImageError.message("Ключ OpenAI не подошёл. Проверьте его в OpenAIKey.plist.")
            case 429: throw OpenAIImageError.message("OpenAI: закончился баланс или лимит запросов. Пополните счёт на platform.openai.com.")
            case 403: throw OpenAIImageError.message("OpenAI: для GPT Image нужна верификация организации на platform.openai.com. \(message)")
            default: throw OpenAIImageError.message("OpenAI: \(message)")
            }
        }
        guard let first = (json?["data"] as? [[String: Any]])?.first, let base64 = first["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64), let result = UIImage(data: imageData) else {
            throw OpenAIImageError.message("GPT не вернул изображение. Попробуйте ещё раз.")
        }
        return result
    }
}
