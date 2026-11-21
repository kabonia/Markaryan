import Foundation

/// Interior styles of the design step: what the card shows (palette, materials, mood)
/// and what the picture AI is told, so the render follows the style down to the details.
struct DesignStyle: Identifiable, Hashable {
    let id: String
    /// Russian name — also what the concept stores in `style`.
    let title: String
    let tagline: String
    let summary: String
    /// Wall, floor, accent, textile — #RRGGBB.
    let palette: [String]
    let materials: [String]
    let english: String

    static let all: [DesignStyle] = [
        DesignStyle(id: "modern", title: "Современный", tagline: "Чистые линии, тёплый свет",
                    summary: "Спокойные нейтральные тона, матовые фасады, скрытое хранение и мягкая подсветка.",
                    palette: ["#E9E4DC", "#B89C7D", "#3D3F42", "#8A9A8C"],
                    materials: ["Матовая краска", "Дуб", "Керамогранит", "Латунь"],
                    english: "contemporary modern interior: clean lines, warm neutral palette, matte handleless fronts, light oak, large-format porcelain, brass accents, layered warm lighting with hidden LED strips"),
        DesignStyle(id: "scandi", title: "Скандинавский", tagline: "Светло, уютно, натурально",
                    summary: "Белые стены, светлое дерево, текстиль из льна и шерсти, много дневного света.",
                    palette: ["#F4F2EE", "#D8C3A5", "#7B8C83", "#2F3437"],
                    materials: ["Белая краска", "Светлый ясень", "Лён", "Шерсть"],
                    english: "Scandinavian interior: white walls, light ash wood floor and furniture, linen and wool textiles, simple functional forms, soft daylight, a few green plants, cosy hygge mood"),
        DesignStyle(id: "minimal", title: "Минимализм", tagline: "Только главное",
                    summary: "Минимум предметов, монохромная гамма, идеальные плоскости и скрытые системы.",
                    palette: ["#F2F2F0", "#CFCFCB", "#8E8E8A", "#1E1E1E"],
                    materials: ["Микроцемент", "Белый лак", "Стекло", "Чёрный металл"],
                    english: "minimalist interior: very few objects, monochrome palette, flawless flat surfaces, microcement, white lacquer, black metal details, completely hidden storage, calm diffused light"),
        DesignStyle(id: "japandi", title: "Японди", tagline: "Япония + Скандинавия",
                    summary: "Низкая мебель, натуральное дерево, глина и бумага, приглушённые землистые тона.",
                    palette: ["#ECE6DA", "#A68A64", "#5B5145", "#93A38A"],
                    materials: ["Орех", "Рисовая бумага", "Глина", "Бамбук"],
                    english: "Japandi interior: low natural wood furniture, walnut and oak, paper lanterns, clay and ceramics, linen, muted earthy palette, wabi-sabi simplicity, soft warm light"),
        DesignStyle(id: "loft", title: "Лофт", tagline: "Кирпич, металл, простор",
                    summary: "Кирпичная кладка, бетон, чёрный металл, кожа и промышленные светильники.",
                    palette: ["#9C5B43", "#6E6A66", "#2A2A2A", "#C49A6C"],
                    materials: ["Кирпич", "Бетон", "Чёрная сталь", "Кожа"],
                    english: "industrial loft interior: exposed red brick wall, concrete surfaces, black steel frames, cognac leather, reclaimed wood, industrial pendant lamps, Edison bulbs"),
        DesignStyle(id: "neoclassic", title: "Неоклассика", tagline: "Классика без тяжести",
                    summary: "Молдинги, симметрия, мрамор, светлые тона и элегантная мебель на тонких ножках.",
                    palette: ["#F1ECE4", "#D6C7B2", "#9A8468", "#3E4A5A"],
                    materials: ["Молдинги", "Мрамор", "Ёлочка", "Бархат"],
                    english: "neoclassical interior: wall mouldings and panels, symmetry, marble, herringbone parquet, light cream walls, velvet upholstery, elegant furniture on slim legs, crystal or brass chandelier"),
        DesignStyle(id: "mediterranean", title: "Средиземноморский", tagline: "Море, солнце, известь",
                    summary: "Известковая штукатурка, терракота, синие акценты, плетёная мебель и арки.",
                    palette: ["#F5EFE3", "#C9714A", "#2F6690", "#D9C9A3"],
                    materials: ["Известковая штукатурка", "Терракота", "Ротанг", "Лён"],
                    english: "Mediterranean interior: textured lime plaster walls, terracotta tiles, blue accents, rattan and wicker furniture, linen curtains, arches, bright sunny light"),
        DesignStyle(id: "eco", title: "Эко", tagline: "Природа в доме",
                    summary: "Дерево, камень, живые растения, натуральные ткани и зелёные оттенки.",
                    palette: ["#EEE9DF", "#8C6E4F", "#5E7D5B", "#C9B79C"],
                    materials: ["Массив дерева", "Натуральный камень", "Растения", "Джут"],
                    english: "eco biophilic interior: solid wood, natural stone, many living plants, jute and cotton textiles, green and earthy tones, natural textures, soft daylight"),
        DesignStyle(id: "artdeco", title: "Ар‑деко", tagline: "Роскошь и геометрия",
                    summary: "Глубокие цвета, латунь, геометрические узоры, мрамор и бархат.",
                    palette: ["#1F3B3A", "#C8A15A", "#EDE3D1", "#6B2D3A"],
                    materials: ["Латунь", "Мрамор", "Бархат", "Лакированное дерево"],
                    english: "Art Deco interior: deep emerald and burgundy, polished brass, geometric patterns, marble, velvet, lacquered wood, fluted details, statement lighting"),
        DesignStyle(id: "contemporary", title: "Тёплый минимализм", tagline: "Мягко и дорого",
                    summary: "Плавные формы, бежевые и песочные оттенки, букле, травертин и рассеянный свет.",
                    palette: ["#EFE7DC", "#D2BFA6", "#A58F78", "#5A4E44"],
                    materials: ["Травертин", "Букле", "Декоративная штукатурка", "Дуб"],
                    english: "warm minimalism interior: soft rounded shapes, beige and sand tones, boucle upholstery, travertine, Venetian plaster, oak, diffused indirect lighting, quiet luxury"),
    ]

    static func named(_ title: String) -> DesignStyle? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.title.lowercased() == clean || $0.id == clean }
    }

    /// Prompt for a quick preview of THIS room in the style (the reference is the exact 3D render of the scan).
    func previewPrompt(room: String) -> String {
        "Photorealistic interior render of THIS exact \(room) in \(english). Keep the camera, every wall, corner, door and window exactly as in the reference; only finishes, furniture style, colours and light change. Professional interior photography, no text, no people."
    }
}

/// «Дизайн по фото»: what is photographed and what to do with it.
enum PhotoDesignRoom: String, CaseIterable, Identifiable {
    case kitchen, bathroom, living, bedroom, kids, hall, balcony, facade, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kitchen: return "Кухня"
        case .bathroom: return "Санузел"
        case .living: return "Гостиная"
        case .bedroom: return "Спальня"
        case .kids: return "Детская"
        case .hall: return "Прихожая"
        case .balcony: return "Балкон"
        case .facade: return "Фасад"
        case .other: return "Другое"
        }
    }
    var icon: String {
        switch self {
        case .kitchen: return "fork.knife"
        case .bathroom: return "shower.fill"
        case .living: return "sofa.fill"
        case .bedroom: return "bed.double.fill"
        case .kids: return "teddybear.fill"
        case .hall: return "door.left.hand.open"
        case .balcony: return "sun.max.fill"
        case .facade: return "house.fill"
        case .other: return "square.dashed"
        }
    }
    var english: String {
        switch self {
        case .kitchen: return "kitchen"
        case .bathroom: return "bathroom"
        case .living: return "living room"
        case .bedroom: return "bedroom"
        case .kids: return "children's room"
        case .hall: return "entrance hall"
        case .balcony: return "balcony"
        case .facade: return "house facade"
        case .other: return "space"
        }
    }
}

enum PhotoDesignMode: String, CaseIterable, Identifiable {
    /// A new interior in the same room: walls, windows and the camera stay.
    case redesign
    /// The existing interior stays; only what the user asked changes.
    case refine
    var id: String { rawValue }
    var title: String { self == .redesign ? "Новый дизайн" : "Доработать текущий" }
    var subtitle: String { self == .redesign ? "Новая отделка и мебель, стены и окна на месте" : "Меняем только то, что вы напишете" }

    func prompt(room: PhotoDesignRoom, style: DesignStyle?, wishesEnglish: String) -> String {
        var parts: [String] = []
        switch self {
        case .redesign:
            parts.append("Redesign THIS \(room.english) from the photo as a finished, professionally designed interior\(style.map { " in \($0.english)" } ?? "").")
            parts.append("Keep exactly: the camera position and lens, the room's geometry, every wall, corner, ceiling height, window and door in the same place and size. Replace finishes, furniture, lighting and decor so the whole room is complete and consistent.")
        case .refine:
            parts.append("Edit THIS photo of a \(room.english). Keep everything as it is — camera, geometry, furniture, finishes and light — and change ONLY what is requested below\(style.map { ", in the spirit of \($0.english)" } ?? "").")
        }
        if !wishesEnglish.isEmpty { parts.append("Requested: \(wishesEnglish).") }
        parts.append("Photorealistic, magazine-quality interior photography, real materials and textures, correct perspective, natural light, sharp details, no text, no people, no watermark.")
        return parts.joined(separator: " ")
    }
}
