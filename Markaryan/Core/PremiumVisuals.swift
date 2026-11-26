import SwiftUI

// MARK: - Metal palette shared by the credit coin and the illustrations

enum Lux {
    static let goldBright = Color(red: 0.984, green: 0.906, blue: 0.690)   // #FBE7B0
    static let goldMid = Color(red: 0.851, green: 0.682, blue: 0.361)      // #D9AE5C
    static let goldDeep = Color(red: 0.557, green: 0.392, blue: 0.125)     // #8E6420
    static let goldShadow = Color(red: 0.369, green: 0.247, blue: 0.063)   // #5E3F10
    static let emeraldBright = Color(red: 0.180, green: 0.612, blue: 0.486)
    static let emeraldDeep = Color(red: 0.027, green: 0.200, blue: 0.161)
    static let night = Color(red: 0.039, green: 0.090, blue: 0.075)        // almost black green

    static let goldGradient = LinearGradient(colors: [goldBright, goldMid, goldDeep, goldMid, goldBright], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Dark premium backdrop of the illustrations (same mood as the app icon).
    static let backdrop = RadialGradient(colors: [Color(red: 0.106, green: 0.227, blue: 0.192), Color(red: 0.055, green: 0.129, blue: 0.110), night], center: UnitPoint(x: 0.4, y: 0.25), startRadius: 10, endRadius: 520)
}

/// Soft light spot drawn as a gradient — looks like a blur but costs nothing to animate.
struct Glow: View {
    let color: Color
    var size: CGFloat = 240
    var body: some View {
        Circle().fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size).allowsHitTesting(false)
    }
}

// MARK: - Credit coin: a gold coin with an emerald gem and a light sweep

struct GemShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.75, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.34))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.34))
        p.closeSubpath()
        return p
    }
}

struct GemFacets: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0, 0.34)); p.addLine(to: pt(1, 0.34))
        p.move(to: pt(0.25, 0)); p.addLine(to: pt(0.37, 0.34)); p.addLine(to: pt(0.5, 1))
        p.move(to: pt(0.75, 0)); p.addLine(to: pt(0.63, 0.34)); p.addLine(to: pt(0.5, 1))
        p.move(to: pt(0.37, 0.34)); p.addLine(to: pt(0.5, 0)); p.addLine(to: pt(0.63, 0.34))
        return p
    }
}

/// Four-point star used as the «ИИ» sparkle.
struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, h = r.height / 2, k: CGFloat = 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - h))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        p.closeSubpath()
        return p
    }
}

struct CreditCoin: View {
    var size: CGFloat = 24
    var shine = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Lux.goldBright, Lux.goldMid, Lux.goldDeep, Lux.goldMid, Lux.goldBright, Lux.goldDeep, Lux.goldBright], center: .center, angle: .degrees(-40)))
            Circle().fill(LinearGradient(colors: [Lux.goldBright, Lux.goldMid, Lux.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.10)
            Circle().strokeBorder(Lux.goldShadow.opacity(0.55), lineWidth: max(0.5, size * 0.025)).padding(size * 0.10)
            ZStack {
                GemShape().fill(LinearGradient(colors: [Lux.emeraldBright, Theme.orange, Lux.emeraldDeep], startPoint: .topLeading, endPoint: .bottom))
                GemFacets().stroke(Color.white.opacity(0.45), lineWidth: max(0.4, size * 0.018))
                GemShape().stroke(Lux.goldShadow.opacity(0.6), lineWidth: max(0.4, size * 0.02))
            }
            .frame(width: size * 0.48, height: size * 0.40)
            .offset(y: size * 0.02)
            if shine && size >= 18 && !reduceMotion {
                LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: size * 0.32, height: size * 1.6)
                    .rotationEffect(.degrees(25))
                    .offset(x: sweep ? size * 1.2 : -size * 1.2)
                    .mask(Circle())
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).delay(0.6).repeatForever(autoreverses: false)) { sweep = true }
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Lux.goldShadow.opacity(0.35), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

// MARK: - Animated illustrations of every function (used by the explanations and onboarding)

enum FeatureSceneKind {
    case home, documents, calculator, design, ar, count, project, billing, house
}

extension FeatureIntro {
    var scene: FeatureSceneKind {
        switch self {
        case .home: .home
        case .estimates, .docEstimate, .fullEstimate, .marketEstimate: .documents
        case .calculators, .calculator: .calculator
        case .design, .photoDesign, .facade: .design
        case .ar: .ar
        case .photoCount: .count
        case .project: .project
        case .billing: .billing
        case .houseScan, .acceptance: .house
        case .tryOn, .photoRoom: .design
        case .quoteCheck, .receipt: .documents
        case .roomScan, .roomMaterials, .apartment: .design
        case .purchase: .project
        case .houseEstimate, .metalEstimate: .documents
        case .houseResult, .parcel: .house
        case .support: .billing
        }
    }
}

/// Dark premium stage with drifting light and gold dust; `kind` decides what lives on it.
struct FeatureScene: View {
    let kind: FeatureSceneKind
    var paused = false
    /// Кадров в секунду: подсказки — 30, карточки на главной — 15 (рядом крутятся и другие анимации).
    var fps: Double = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps, paused: reduceMotion || paused)) { context in
            let t = reduceMotion ? 2.6 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                SceneBackdrop(t: t)
                Group {
                    switch kind {
                    case .home: HomeScene(t: t)
                    case .documents: DocumentsScene(t: t)
                    case .calculator: CalculatorScene(t: t)
                    case .design: DesignScene(t: t)
                    case .ar: ARScene(t: t)
                    case .count: CountScene(t: t)
                    case .project: ProjectScene(t: t)
                    case .billing: BillingScene(t: t)
                    case .house: HouseScanScene(t: t)
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct SceneBackdrop: View {
    let t: Double
    var body: some View {
        ZStack {
            Lux.backdrop
            // blueprint grid, fading out to the edges
            Canvas { ctx, size in
                var grid = Path()
                stride(from: 0, through: size.width, by: 28).forEach { x in grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: 28).forEach { y in grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(grid, with: .color(Theme.goldLight.opacity(0.06)), lineWidth: 0.6)
            }
            .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 20, endRadius: 260))
            Glow(color: Lux.goldMid.opacity(0.30), size: 380)
                .offset(x: -110 + 40 * sin(t * 0.35), y: -70 + 20 * cos(t * 0.3))
            Glow(color: Lux.emeraldBright.opacity(0.32), size: 360)
                .offset(x: 130 + 30 * cos(t * 0.3), y: 80 + 20 * sin(t * 0.4))
            // gold dust
            Canvas { ctx, size in
                for i in 0..<18 {
                    let seed = Double(i) * 12.9898
                    let x = (sin(seed) * 0.5 + 0.5) * size.width
                    let speed = 10 + (cos(seed * 1.7) * 0.5 + 0.5) * 16
                    let y = size.height - ((t * speed + Double(i) * 47).truncatingRemainder(dividingBy: size.height + 20))
                    let r = 0.8 + (sin(seed * 3.1) * 0.5 + 0.5) * 1.6
                    let alpha = 0.25 + 0.35 * (sin(t * 1.3 + seed) * 0.5 + 0.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: x + 6 * sin(t * 0.6 + seed), y: y, width: r * 2, height: r * 2)), with: .color(Lux.goldBright.opacity(alpha)))
                }
            }
        }
    }
}

private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
private func ease(_ v: Double) -> Double { let x = clamp01(v); return x * x * (3 - 2 * x) }

private struct GlassCard<Content: View>: View {
    var corner: CGFloat = 16
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(LinearGradient(colors: [Theme.goldLight.opacity(0.55), Theme.goldLight.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
    }
}

// Home: the brand mark with the tools orbiting around it.
private struct HomeScene: View {
    let t: Double
    private let icons = ["doc.text.magnifyingglass", "camera.aperture", "ruler", "function", "square.stack.3d.up", "building.2"]
    var body: some View {
        ZStack {
            ForEach(icons.indices, id: \.self) { i in
                let a = t * 0.35 + Double(i) / Double(icons.count) * 2 * .pi
                let depth = (sin(a) + 1) / 2
                Image(systemName: icons[i]).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.goldLight)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.goldLight.opacity(0.35), lineWidth: 0.7))
                    .scaleEffect(0.75 + 0.35 * depth)
                    .opacity(0.45 + 0.55 * depth)
                    .offset(x: 130 * cos(a), y: 46 * sin(a))
                    .zIndex(depth)
            }
            Image("BrandMark").resizable().scaledToFill().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Lux.goldGradient, lineWidth: 1))
                .shadow(color: Lux.goldMid.opacity(0.45), radius: 24)
                .offset(y: -4 + 4 * sin(t * 1.2))
                .zIndex(0.5)
        }
    }
}

// Documents: a fan of drawings, a scan line reading them, the total appearing.
private struct DocumentsScene: View {
    let t: Double
    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: 5.0) / 5.0
        ZStack {
            sheet(lines: 4).rotationEffect(.degrees(-12)).offset(x: -70, y: 10).opacity(0.75)
            sheet(lines: 4).rotationEffect(.degrees(9)).offset(x: 72, y: 6).opacity(0.8)
            ZStack(alignment: .top) {
                sheet(lines: 0)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<6, id: \.self) { i in
                        let p = ease(phase * 8 - Double(i) * 0.9)
                        HStack(spacing: 6) {
                            Capsule().fill(Theme.ink.opacity(0.55)).frame(width: CGFloat(54 + (i * 17) % 36) * p, height: 5)
                            Spacer(minLength: 0)
                            Capsule().fill(Lux.goldMid).frame(width: 24 * p, height: 5)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 34)
                Capsule().fill(Theme.orange).frame(width: 70, height: 6).padding(.top, 16).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                // scan line
                LinearGradient(colors: [Lux.goldBright.opacity(0), Lux.goldBright.opacity(0.9), Lux.goldBright.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 2).shadow(color: Lux.goldBright, radius: 6)
                    .offset(y: 10 + 170 * ease(phase * 1.6))
                    .opacity(phase < 0.62 ? 1 : 0)
            }
            .frame(width: 150, height: 196)
            .offset(y: -6 + 3 * sin(t))
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Lux.goldBright)
                Text("Итого 1 248 300 ₽").font(.system(.footnote, design: .rounded, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.orange, in: Capsule())
            .overlay(Capsule().strokeBorder(Lux.goldGradient, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .scaleEffect(0.6 + 0.4 * ease((phase - 0.62) * 8))
            .opacity(ease((phase - 0.62) * 8))
            .offset(x: 62, y: 92)
        }
    }

    private func sheet(lines: Int) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color.white, Color(red: 0.95, green: 0.94, blue: 0.91)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<lines, id: \.self) { i in Capsule().fill(Theme.ink.opacity(0.18)).frame(width: CGFloat(60 + i * 12), height: 5) }
                }
                .padding(16)
            }
            .frame(width: 150, height: 196)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }
}

// Calculator: fields filled in and the result counting up.
private struct CalculatorScene: View {
    let t: Double
    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: 4.5) / 4.5
        let value = 6.38 * ease(phase * 2.2 - 0.5)
        GlassCard(corner: 22) {
            VStack(alignment: .leading, spacing: 10) {
                row("Площадь", "42,5 м²", visible: ease(phase * 6))
                row("Толщина", "0,15 м", visible: ease(phase * 6 - 1))
                Rectangle().fill(Theme.goldLight.opacity(0.25)).frame(height: 0.6)
                HStack(alignment: .firstTextBaseline) {
                    Text("БЕТОН").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(Theme.goldLight)
                    Spacer()
                    Text(String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")).font(.system(size: 40, weight: .bold, design: .serif)).monospacedDigit().foregroundStyle(.white)
                    Text("м³").font(.headline).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(Lux.goldMid.opacity(0.85)).frame(height: 12)
                            .opacity(ease(phase * 10 - 4 - Double(i) * 0.4))
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 260)
        .offset(y: 3 * sin(t))
    }

    private func row(_ title: String, _ value: String, visible: Double) -> some View {
        HStack {
            Text(title.tr).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .opacity(visible)
        }
    }
}

// Design: the same room before and after, with a sliding divider.
private struct DesignScene: View {
    let t: Double
    var body: some View {
        let split = 0.5 + 0.36 * sin(t * 0.8)
        let w: CGFloat = 280, h: CGFloat = 186
        ZStack(alignment: .leading) {
            StyleRoomIllustration(palette: ["#D8D5CF", "#A8A39B", "#6E6A65", "#8C8780"]).saturation(0)
            StyleRoomIllustration(palette: ["#EFE7DA", "#B8875A", "#1F3B3A", "#C8A15A"])
                .mask(alignment: .leading) { Rectangle().frame(width: w * split) }
            Rectangle().fill(.white).frame(width: 2).shadow(color: .black.opacity(0.4), radius: 4).offset(x: w * split - 1)
            Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                .frame(width: 32, height: 32).background(.white, in: Circle()).shadow(color: .black.opacity(0.3), radius: 6)
                .offset(x: w * split - 16)
            VStack {
                HStack {
                    tag("Стало", gold: true)
                    Spacer()
                    tag("Было", gold: false)
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Lux.goldGradient, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
        .overlay(alignment: .topTrailing) {
            SparkleShape().fill(Lux.goldGradient).frame(width: 30, height: 30)
                .scaleEffect(0.85 + 0.2 * sin(t * 2)).offset(x: 14, y: -16)
        }
    }

    private func tag(_ text: String, gold: Bool) -> some View {
        Text(text.tr.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(gold ? Theme.orange : Color.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white)
    }
}

// AR: points placed on a grid, the contour closing, the area appearing.
private struct ARScene: View {
    let t: Double
    private let points: [CGPoint] = [CGPoint(x: 0.12, y: 0.30), CGPoint(x: 0.78, y: 0.18), CGPoint(x: 0.90, y: 0.78), CGPoint(x: 0.20, y: 0.86)]
    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: 5.5) / 5.5
        let draw = ease(phase * 1.6)
        GeometryReader { geo in
            let size = geo.size
            let pts = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            ZStack {
                Path { p in p.addLines(pts); p.closeSubpath() }
                    .fill(Theme.orange.opacity(0.28 * ease((phase - 0.6) * 6)))
                Path { p in p.addLines(pts); p.closeSubpath() }
                    .trim(from: 0, to: draw)
                    .stroke(Lux.goldBright, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6]))
                    .shadow(color: Lux.goldBright.opacity(0.7), radius: 4)
                ForEach(pts.indices, id: \.self) { i in
                    let shown = draw * 4 >= Double(i)
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.orange, lineWidth: 3))
                        .scaleEffect(shown ? 1 : 0.2).opacity(shown ? 1 : 0)
                        .position(pts[i])
                }
                Text("4,20 м").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Lux.goldBright, in: Capsule())
                    .position(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 - 16)
                    .opacity(ease(draw * 4 - 1))
                VStack(spacing: 0) {
                    Text("18,6").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(.white)
                    Text("м² · площадь").font(.caption.weight(.semibold)).foregroundStyle(Theme.goldLight)
                }
                .position(x: size.width * 0.5, y: size.height * 0.54)
                .opacity(ease((phase - 0.62) * 6))
                // reticle
                Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5).frame(width: 34, height: 34)
                    .overlay(Circle().fill(.white).frame(width: 4, height: 4))
                    .scaleEffect(1 + 0.12 * sin(t * 4))
                    .position(x: size.width * 0.5, y: size.height * 0.5)
                    .opacity(1 - ease((phase - 0.55) * 6))
            }
        }
        .frame(width: 290, height: 200)
    }
}

// Count: rebar / pipe ends being ticked one by one.
private struct CountScene: View {
    let t: Double
    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: 6.0)
        let total = 22
        let done = min(total, Int(phase / 0.17))
        ZStack(alignment: .topTrailing) {
            VStack(spacing: -4) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<(r % 2 == 0 ? 6 : 5), id: \.self) { c in
                            let index = [0, 6, 11, 17][r] + c
                            end(checked: index < done)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("\(done)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                Text("шт").font(.caption.weight(.semibold)).opacity(0.75)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Lux.goldGradient, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .offset(x: 18, y: -28)
        }
    }

    private func end(checked: Bool) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.62, green: 0.64, blue: 0.66), Color(red: 0.30, green: 0.32, blue: 0.34)], center: .center, startRadius: 2, endRadius: 22))
            Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1).padding(6)
            if checked {
                Circle().fill(Theme.orange.opacity(0.85)).padding(5)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        .scaleEffect(checked ? 1 : 0.96)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: checked)
    }
}

// Project: progress ring and the stages of the object.
private struct ProjectScene: View {
    let t: Double
    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: 6.0) / 6.0
        let progress = 0.68 * ease(phase * 2.5)
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 12)
                Circle().trim(from: 0, to: progress).stroke(Lux.goldGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%").font(.system(size: 30, weight: .bold, design: .serif)).monospacedDigit().foregroundStyle(.white)
                    Text("готово").font(.caption2.weight(.semibold)).foregroundStyle(Theme.goldLight)
                }
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 10) {
                stage("Фундамент", done: progress > 0.2)
                stage("Стены", done: progress > 0.45)
                stage("Кровля", done: progress > 0.66)
                stage("Отделка", done: false)
            }
        }
        .offset(y: 3 * sin(t))
    }

    private func stage(_ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Lux.goldBright : .white.opacity(0.4))
            Text(title.tr).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(done ? 1 : 0.55))
        }
    }
}

// Billing: the coin turning in the light with smaller coins around.
private struct BillingScene: View {
    let t: Double
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let a = t * 0.5 + Double(i) * 2.1
                CreditCoin(size: 34, shine: false)
                    .offset(x: 120 * cos(a), y: 40 * sin(a))
                    .scaleEffect(0.8 + 0.25 * (sin(a) + 1) / 2)
                    .opacity(0.55 + 0.45 * (sin(a) + 1) / 2)
                    .zIndex((sin(a) + 1) / 2)
            }
            CreditCoin(size: 120)
                .rotation3DEffect(.degrees(22 * sin(t * 0.9)), axis: (x: 0, y: 1, z: 0))
                .offset(y: -4 + 5 * sin(t * 1.1))
                .shadow(color: Lux.goldMid.opacity(0.5), radius: 30)
                .zIndex(0.5)
            ForEach(0..<3, id: \.self) { i in
                SparkleShape().fill(Lux.goldBright)
                    .frame(width: CGFloat(10 + i * 5), height: CGFloat(10 + i * 5))
                    .opacity(0.4 + 0.6 * (sin(t * 2 + Double(i) * 2) * 0.5 + 0.5))
                    .offset(x: [-80, 86, 60][i], y: [-62, -48, 70][i])
            }
        }
    }
}

// 3D‑обмер дома: телефон обходит дом, кольцо покрытия заполняется, затем — размеры, крыша и «Макет готов».
struct HouseScanScene: View {
    let t: Double

    var body: some View {
        let cycle = 9.0
        let phase = t.truncatingRemainder(dividingBy: cycle) / cycle      // 0…1
        let walk = clamp01(phase / 0.55)                                    // обход — первые 55 %
        let angle = -Double.pi / 2 + walk * 2 * .pi
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
            let ring = min(size.width, size.height) * 0.43
            // Кольцо покрытия: 36 секторов, загораются по ходу обхода.
            let lit = Int(walk * 36)
            for i in 0..<36 {
                let a0 = -Double.pi / 2 + Double(i) / 36 * 2 * .pi + 0.03
                let a1 = a0 + 2 * .pi / 36 - 0.06
                var arc = Path()
                arc.addArc(center: c, radius: ring, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                ctx.stroke(arc, with: .color(i < lit ? Lux.emeraldBright : .white.opacity(0.12)), lineWidth: 7)
                var inner = Path()
                inner.addArc(center: c, radius: ring - 10, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                ctx.stroke(inner, with: .color(i < lit - 4 ? Lux.goldBright : .white.opacity(0.08)), lineWidth: 4)
            }
            // Дом сверху: контур и конёк; заливка проявляется к концу обхода.
            let w = size.width * 0.34, h = size.width * 0.24
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.orange.opacity(0.18 + 0.4 * ease((phase - 0.45) * 5))))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white.opacity(0.85)), lineWidth: 2)
            var ridge = Path()
            ridge.move(to: CGPoint(x: rect.minX + 6, y: c.y)); ridge.addLine(to: CGPoint(x: rect.maxX - 6, y: c.y))
            ctx.stroke(ridge, with: .color(Lux.goldBright.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            // Телефон на круге и луч «камеры» на дом.
            if phase < 0.6 {
                let r = ring * 0.78
                let p = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
                var beam = Path()
                beam.move(to: p)
                beam.addLine(to: CGPoint(x: c.x + (p.x - c.x) * 0.25 - (p.y - c.y) * 0.18, y: c.y + (p.y - c.y) * 0.25 + (p.x - c.x) * 0.18))
                beam.addLine(to: CGPoint(x: c.x + (p.x - c.x) * 0.25 + (p.y - c.y) * 0.18, y: c.y + (p.y - c.y) * 0.25 - (p.x - c.x) * 0.18))
                beam.closeSubpath()
                ctx.fill(beam, with: .color(Lux.goldBright.opacity(0.22)))
                ctx.fill(Path(roundedRect: CGRect(x: p.x - 6, y: p.y - 10, width: 12, height: 20), cornerRadius: 3), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 7, width: 4, height: 4)), with: .color(Theme.ink))
            }
        }
        .overlay {
            GeometryReader { geo in
                let size = geo.size
                let c = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
                let w = size.width * 0.34, h = size.width * 0.24
                ZStack {
                    label("10,00 м").position(x: c.x, y: c.y - h / 2 - 14).opacity(ease((phase - 0.58) * 8))
                    label("8,00 м").rotationEffect(.degrees(-90)).position(x: c.x + w / 2 + 16, y: c.y).opacity(ease((phase - 0.63) * 8))
                    HStack(spacing: 6) {
                        Image(systemName: "triangle").font(.caption2.weight(.bold))
                        Text("конёк 6,00 м · 36,9°").font(.system(.caption2, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Lux.goldGradient, in: Capsule())
                    .position(x: c.x, y: c.y + h / 2 + 18).opacity(ease((phase - 0.7) * 8))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Макет готов").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.orange, in: Capsule())
                    .position(x: c.x, y: 22).opacity(ease((phase - 0.8) * 8))
                }
            }
        }
        .frame(width: 300, height: 240)
    }

    private func label(_ text: String) -> some View {
        Text(text.tr).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Lux.goldBright, in: Capsule())
    }
}
