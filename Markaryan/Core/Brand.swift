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
    static let background = Color(red: 0.055, green: 0.072, blue: 0.064)
    static let panel = Color(red: 0.115, green: 0.142, blue: 0.126)
    static let panelRaised = Color(red: 0.150, green: 0.180, blue: 0.162)
    static let stroke = Color.white.opacity(0.07)
    static let orange = Color(red: 0.98, green: 0.43, blue: 0.22)
    static let orangeSoft = Color(red: 0.97, green: 0.71, blue: 0.45)
    static let muted = Color(red: 0.67, green: 0.72, blue: 0.67)
    static let success = Color(red: 0.45, green: 0.85, blue: 0.60)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let sky = Color(red: 0.56, green: 0.70, blue: 0.98)
    static let sage = Color(red: 0.68, green: 0.81, blue: 0.47)

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.18, green: 0.24, blue: 0.22), Color(red: 0.08, green: 0.11, blue: 0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct PanelCardModifier: ViewModifier {
    let radius: CGFloat
    var fill: Color = Theme.panel
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    /// Standard card surface: panel colour, continuous corners and a hairline border.
    func panelCard(_ radius: CGFloat = 18, fill: Color = Theme.panel) -> some View {
        modifier(PanelCardModifier(radius: radius, fill: fill))
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
