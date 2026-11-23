import SwiftUI
import UIKit
import ImageIO
import CoreImage.CIFilterBuiltins

// MARK: - Brand constants

enum Brand {
    static let name = "СметаПро"
    static let tagline = "Сметы, замеры и дизайн для стройки и ремонта"
    /// City used until the user picks one (prices and partners need some city).
    static let city = "Сочи"

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Short signature for shared texts: only the app, no company contacts.
    static var shareFooter: String { "—\nПосчитано в приложении «\(name)»" }

    static var inviteText: String {
        "Считаю стройку и ремонт в приложении «\(name)»: калькуляторы, сметы по рыночным ценам, AR‑замеры, дизайн и ИИ‑помощник."
    }
}

// MARK: - Theme

enum Theme {
    // «Премиум‑изумруд»: warm ivory page, milky cards, deep emerald‑graphite text, emerald accent, gold details.
    static let background = Color(red: 0.953, green: 0.941, blue: 0.910)     // #F3F0E8 warm ivory
    static let panel = Color(red: 0.992, green: 0.988, blue: 0.973)          // #FDFCF8 milky card
    static let panelRaised = Color(red: 0.918, green: 0.898, blue: 0.851)    // #EAE5D9 sand
    static let stroke = Color(red: 0.24, green: 0.20, blue: 0.12).opacity(0.10)
    static let ink = Color(red: 0.086, green: 0.141, blue: 0.122)            // #16241F — main text
    static let onAccent = Color.white                                         // text on accent fills
    /// Main accent (historic name kept so every screen picks it up).
    static let orange = Color(red: 0.059, green: 0.420, blue: 0.333)         // #0F6B55 deep emerald
    static let orangeSoft = Color(red: 0.180, green: 0.612, blue: 0.486)     // #2E9C7C
    static let accentTint = Color(red: 0.867, green: 0.929, blue: 0.898)     // #DDEDE5
    static let muted = Color(red: 0.400, green: 0.392, blue: 0.361)          // #66645C warm grey
    /// Gold details: eyebrows, badges, hairlines on hero cards.
    static let gold = Color(red: 0.580, green: 0.435, blue: 0.157)           // #946F28 (readable on ivory)
    static let goldLight = Color(red: 0.902, green: 0.784, blue: 0.533)      // #E6C888 (on emerald)
    static let goldTint = Color(red: 0.965, green: 0.925, blue: 0.835)       // #F6ECD5
    static let success = Color(red: 0.118, green: 0.560, blue: 0.330)
    static let danger = Color(red: 0.780, green: 0.239, blue: 0.220)
    static let sky = Color(red: 0.204, green: 0.420, blue: 0.788)
    static let sage = Color(red: 0.494, green: 0.639, blue: 0.353)

    /// Hero cards: deep emerald gradient with white text.
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.067, green: 0.400, blue: 0.318), Color(red: 0.039, green: 0.259, blue: 0.212), Color(red: 0.027, green: 0.192, blue: 0.161)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Primary buttons: a lighter emerald on top.
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.094, green: 0.486, blue: 0.388), Color(red: 0.051, green: 0.369, blue: 0.294)],
        startPoint: .top, endPoint: .bottom
    )
    /// Hairline of gold on hero cards.
    static let goldHairline = LinearGradient(colors: [goldLight.opacity(0.75), goldLight.opacity(0.10), goldLight.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct PanelCardModifier: ViewModifier {
    let radius: CGFloat
    var fill: Color = Theme.panel
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.6))
            .shadow(color: Color(red: 0.25, green: 0.20, blue: 0.10).opacity(fill == Theme.panel ? 0.07 : 0), radius: 18, y: 7)
            .shadow(color: Color(red: 0.25, green: 0.20, blue: 0.10).opacity(fill == Theme.panel ? 0.04 : 0), radius: 2, y: 1)
    }
}

/// Input surface: a quiet field with a hairline, emerald when focused (no card shadow on inputs).
struct FieldSurfaceModifier: ViewModifier {
    let radius: CGFloat
    var focused = false
    func body(content: Content) -> some View { content.tint(Theme.orange).panelCard(radius) }
}

extension View {
    func fieldSurface(_ radius: CGFloat = 14, focused: Bool = false) -> some View { modifier(FieldSurfaceModifier(radius: radius, focused: focused)) }

    /// Standard card surface: white, soft corners, hairline and a gentle shadow.
    func panelCard(_ radius: CGFloat = 20, fill: Color = Theme.panel) -> some View {
        modifier(PanelCardModifier(radius: radius, fill: fill))
    }
}

/// App logo drawn in code: an emerald tile with a tape measure.
struct AppMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image("BrandMark").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Theme.goldLight.opacity(0.35), lineWidth: 0.6))
            .accessibilityHidden(true)
    }
}

// MARK: - Haptics

@MainActor enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Promotion helpers: QR code and watermark

enum BrandGraphics {
    private static let context = CIContext()

    /// Crisp QR code image for the given text (used in PDF documents).
    static func qrCode(_ text: String, size: CGFloat = 220) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Adds a discreet branded caption to the bottom of an image before it is shared.
    static func watermarked(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 10, size.height > 10 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = max(12, size.width * 0.026)
            let text = "\(Brand.name)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let padding = fontSize * 0.7
            let badge = CGRect(x: size.width - textSize.width - padding * 3, y: size.height - textSize.height - padding * 3, width: textSize.width + padding * 2, height: textSize.height + padding)
            UIColor.black.withAlphaComponent(0.45).setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: badge.height / 2).fill()
            text.draw(at: CGPoint(x: badge.minX + padding, y: badge.minY + padding / 2), withAttributes: attributes)
        }
    }
}

// MARK: - Fast thumbnails (ImageIO downsampling + memory cache)

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 120 }

    func image(for url: URL, maxPixel: CGFloat) -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Loads a downsampled photo off the main thread so long photo lists scroll smoothly.
struct LocalThumbnail: View {
    let url: URL?
    var maxPixel: CGFloat = 900
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.panelRaised
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                ProgressView().tint(Theme.orange)
            }
        }
        .task(id: url) {
            guard let url else { return }
            let pixel = maxPixel
            let loaded = await Task.detached(priority: .userInitiated) { ThumbnailCache.shared.image(for: url, maxPixel: pixel) }.value
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
