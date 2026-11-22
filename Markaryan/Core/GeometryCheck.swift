import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Guards the AI visualisation against invented geometry.
/// The exact 3D render of the scanned room and the AI image are reduced to edge maps
/// (walls, corners, openings, furniture outlines) and compared. If the AI moved walls,
/// added windows or changed the layout, the score drops and the image is rejected.
enum GeometryCheck {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static let width = 128
    private static let height = 96
    /// Minimum agreement (F2: keeping the scan's walls and openings counts twice as much as extra decor). At or above — the photo is used.
    static let threshold = 0.45
    /// Below the threshold but still close: used only when no frame passed, with a note to check the proportions.
    static let softThreshold = 0.33
    /// The AI may reframe the shot slightly: shifts up to ±4 px of 128 (about 3 %) are searched.
    private static let maxShift = 4

    /// Edge map with a fixed density: the strongest 8 % of edges of a slightly blurred picture,
    /// so style, textures, patterns and lighting do not matter — only the big structure (walls, corners, openings, furniture outlines).
    private static func edgeMap(_ image: UIImage) -> [Bool]? {
        guard let input = CIImage(image: image), input.extent.width > 0, input.extent.height > 0 else { return nil }
        let scaled = input.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / input.extent.width, y: CGFloat(height) / input.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = scaled.clampedToExtent()
        blur.radius = 1.1
        let gray = CIFilter.colorControls()
        gray.inputImage = blur.outputImage
        gray.saturation = 0
        gray.contrast = 1.1
        let edges = CIFilter.edges()
        edges.inputImage = gray.outputImage
        edges.intensity = 5
        guard let output = edges.outputImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(output, toBitmap: &pixels, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
        var magnitude = [Int](repeating: 0, count: width * height)
        for index in 0..<(width * height) { magnitude[index] = Int(pixels[index * 4]) + Int(pixels[index * 4 + 1]) + Int(pixels[index * 4 + 2]) }
        let sorted = magnitude.sorted(by: >)
        let cut = max(1, sorted[min(sorted.count - 1, sorted.count * 8 / 100)])
        // Ignore a 3-pixel border (frame artefacts and the blur edge).
        return magnitude.enumerated().map { index, value in
            let x = index % width, y = index / width
            return value >= cut && x > 2 && y > 2 && x < width - 3 && y < height - 3
        }
    }

    private static func dilate(_ map: [Bool], radius: Int) -> [Bool] {
        var result = map
        for y in 0..<height { for x in 0..<width where map[y * width + x] {
            for dy in -radius...radius { for dx in -radius...radius {
                let nx = x + dx, ny = y + dy
                if nx >= 0, ny >= 0, nx < width, ny < height { result[ny * width + nx] = true }
            } }
        } }
        return result
    }

    private static func shifted(_ map: [Bool], dx: Int, dy: Int) -> [Bool] {
        guard dx != 0 || dy != 0 else { return map }
        var result = [Bool](repeating: false, count: map.count)
        for y in 0..<height { for x in 0..<width where map[y * width + x] {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < width, ny < height { result[ny * width + nx] = true }
        } }
        return result
    }

    /// 0…1: how well the candidate keeps the structure of the reference (the best over small reframings).
    static func score(reference: UIImage, candidate: UIImage) -> Double {
        guard let ref = edgeMap(reference), let cand = edgeMap(candidate) else { return 0 }
        let refCount = ref.filter { $0 }.count, candCount = cand.filter { $0 }.count
        guard refCount > 0, candCount > 0 else { return 0 }
        let refWide = dilate(ref, radius: 2)
        let candWide = dilate(cand, radius: 2)
        var best = 0.0
        for dy in stride(from: -maxShift, through: maxShift, by: 2) {
            for dx in stride(from: -maxShift, through: maxShift, by: 2) {
                let moved = shifted(cand, dx: dx, dy: dy)
                let movedWide = shifted(candWide, dx: dx, dy: dy)
                let movedCount = moved.filter { $0 }.count
                guard movedCount > 0 else { continue }
                let recall = Double(zip(ref, movedWide).filter { $0 && $1 }.count) / Double(refCount)
                let precision = Double(zip(moved, refWide).filter { $0 && $1 }.count) / Double(movedCount)
                guard recall + precision > 0 else { continue }
                // F2: losing a wall or an opening of the scan weighs more than extra decor drawn by the AI.
                best = max(best, 5 * precision * recall / (4 * precision + recall))
            }
        }
        return best
    }
}

/// Exposure check of a render: catches burnt-out white frames and black frames where nothing is visible.
enum RenderQuality {
    struct Stats {
        /// Mean display brightness 0…1.
        let mean: Double
        /// Share of burnt-out pixels.
        let clipped: Double
        /// Share of almost black pixels.
        let dark: Double
        /// Contrast (standard deviation of brightness).
        let contrast: Double
    }

    /// `central` measures only the middle of the frame (top/iso views have a plain background around the model).
    static func stats(_ image: UIImage, central: Bool = false) -> Stats? {
        guard let cg = image.cgImage else { return nil }
        let width = 96, height = 72
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                if central && (x < width / 5 || x > width * 4 / 5 || y < height / 5 || y > height * 4 / 5) { continue }
                let i = (y * width + x) * 4
                values.append((0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255)
            }
        }
        guard !values.isEmpty else { return nil }
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        return Stats(mean: mean, clipped: Double(values.filter { $0 > 0.96 }.count) / count,
                     dark: Double(values.filter { $0 < 0.04 }.count) / count, contrast: sqrt(variance))
    }

    /// A frame a client can look at: not burnt out, not black, with visible structure.
    static func isUsable(_ image: UIImage) -> Bool {
        guard let s = stats(image) else { return false }
        return s.mean > 0.12 && s.mean < 0.82 && s.clipped < 0.15 && s.dark < 0.35 && s.contrast > 0.05
    }
}
