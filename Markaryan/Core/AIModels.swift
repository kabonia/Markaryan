import Foundation

/// The AI that designs the room on the «Дизайн» step: picks the furniture with real sizes and their places
/// (wall, corner, next to what), the finishes, the light and the data for the drawings.
/// The chosen model answers first; the others stay behind it as fallbacks (OpenRouter switches on a failure).
/// Ids are OpenRouter's; all four work with the same key.
enum DesignModel: String, CaseIterable, Identifiable, Hashable {
    case opus = "anthropic/claude-opus-5.5"
    case sonnet = "anthropic/claude-sonnet-5.5"
    case gpt = "openai/gpt-6.2-astra"
    case gemini = "google/gemini-4-carbon"

    static let standard: DesignModel = .opus
    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: return "Claude Opus 5.5"
        case .sonnet: return "Claude Sonnet 5.5"
        case .gpt: return "GPT‑6.2 Astra"
        case .gemini: return "Gemini 4 Carbon"
        }
    }

    /// Why one would pick it (prices of OpenRouter, November 2026).
    var note: String {
        switch self {
        case .opus: return "Рекомендую: точнее держит правила расстановки · ≈ $0,10–0,15 за концепцию"
        case .sonnet: return "Вдвое дешевле Opus"
        case .gpt: return "Модель OpenAI · вдвое дороже Opus"
        case .gemini: return "Модель Google · вдвое дешевле Opus"
        }
    }

    /// The same model by its Anthropic API name, for a key of Anthropic itself (sk-ant-…); nil — not a Claude model.
    var anthropicID: String? {
        switch self {
        case .opus: return "claude-opus-5-5"
        case .sonnet: return "claude-sonnet-5-5"
        case .gpt, .gemini: return nil
        }
    }

    /// The other models in order, at most three: OpenRouter tries them when the chosen one fails.
    var fallbacks: [String] { Array(Self.allCases.filter { $0 != self }.map(\.rawValue).prefix(3)) }

    /// A model id the server or OpenRouter reports (it may be a fallback, with or without the vendor):
    /// its title, the bare name for an unknown model, nil for nothing.
    static func title(of id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        // OpenRouter may add a variant (":batch"), Anthropic a date ("claude-opus-5-5-20261015").
        if let model = Self.allCases.first(where: { id == $0.rawValue || id.hasPrefix($0.rawValue + ":") || $0.anthropicID.map { id == $0 || id.hasPrefix($0 + "-") } == true }) {
            return model.title
        }
        switch id.lowercased() {
        case "gigachat": return "GigaChat"
        case "yandex": return "YandexGPT"
        default: return id.split(separator: "/").last.map(String.init) ?? id
        }
    }
}

/// The image model that turns the exact 3D render of the scan into a photo without moving the walls or the furniture.
/// The chosen model draws first; the others (and FLUX 3 at the end) step in when it fails.
enum RenderModel: String, CaseIterable, Identifiable, Hashable {
    case nanoBananaPro = "google/gemini-3-pro-image"
    case gptImage = "openai/gpt-image-2.6-sunburst"
    case seedream = "bytedance-seed/seedream-5-0-pro"

    static let standard: RenderModel = .nanoBananaPro
    /// The last resort when none of the three answers.
    static let lastResort = "black-forest-labs/flux-3-image"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nanoBananaPro: return "Nano Banana Pro"
        case .gptImage: return "GPT Image 2.6 Sunburst"
        case .seedream: return "Seedream 5.0 Pro"
        }
    }

    var note: String {
        switch self {
        case .nanoBananaPro: return "Рекомендую: держит ракурс · ≈ 20 с · ≈ $0,13 за кадр"
        case .gptImage: return "Лучшее качество картинки · медленнее и дороже"
        case .seedream: return "Точнее всех совпадает с 3D‑моделью · ≈ $0,045 за кадр · ≈ 2 мин"
        }
    }

    /// The engine id of the app's AI server.
    var engineID: String { "openrouter:" + rawValue }

    /// Models to try with the app's own OpenRouter key: the chosen one, the other two, FLUX 3 last.
    var order: [String] { [rawValue] + Self.allCases.filter { $0 != self }.map(\.rawValue) + [Self.lastResort] }

    /// The chosen model by an engine id of the server ("openrouter:…") or a bare OpenRouter id.
    init?(engine: String) {
        let id = engine.hasPrefix("openrouter:") ? String(engine.dropFirst("openrouter:".count)) : engine
        self.init(rawValue: id)
    }
}

/// Where the choice is kept between launches, and how a saved value is read back safely
/// (a model removed in a later version falls back to the recommended one).
enum AIModelChoice {
    static let designKey = "designModel"
    static let renderKey = "renderModel"

    static func design(_ saved: String?) -> DesignModel { saved.flatMap(DesignModel.init(rawValue:)) ?? .standard }
    static func render(_ saved: String?) -> RenderModel { saved.flatMap(RenderModel.init(rawValue:)) ?? .standard }
}
