import SwiftUI
import AVFoundation
import simd

/// Голосовые подсказки при обходе: человек смотрит на дом, а не в экран. Язык — как у приложения.
@MainActor final class HouseScanVoice: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "houseScan.voice") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "houseScan.voice"); if !enabled { synth.stopSpeaking(at: .immediate) } }
    }
    private let synth = AVSpeechSynthesizer()
    private var lastText = ""
    private var lastTime = Date.distantPast

    private var voiceLanguage: String {
        let code = AppLanguage.code
        if code.hasPrefix("ru") { return "ru-RU" }
        if code.hasPrefix("es") { return "es-ES" }
        if code.hasPrefix("zh") { return "zh-CN" }
        return "en-US"
    }

    func prepare() {
        // Подсказки слышно и при беззвучном режиме; музыку приглушаем, а не останавливаем.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func say(_ hint: HouseScanHint) {
        guard enabled else { return }
        let text = hint.text.tr
        let now = Date()
        // Новая подсказка — сразу (если прошлая договорена или прошло 3 с); «Идите дальше» — не чаще раза в 20 с.
        if text == lastText { return }
        if hint == .keepGoing && now.timeIntervalSince(lastTime) < 20 { return }
        if synth.isSpeaking && now.timeIntervalSince(lastTime) < 3 { return }
        lastText = text
        lastTime = now
        synth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(utterance)
    }

    /// Любая фраза (подсказки скана комнаты RoomPlan): не повторяем ту же чаще раза в 6 с.
    func speak(_ phrase: String) {
        guard enabled else { return }
        let text = phrase.tr
        let now = Date()
        if text == lastText && now.timeIntervalSince(lastTime) < 6 { return }
        if synth.isSpeaking && now.timeIntervalSince(lastTime) < 2.5 { return }
        lastText = text
        lastTime = now
        synth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Мини‑карта сверху: точки стен, куда смотрела камера (контур дома проявляется по ходу), путь и где вы сейчас.
struct HouseScanMiniMap: View {
    let wallPoints: [SIMD2<Float>]
    let track: [SIMD2<Float>]
    let here: (position: SIMD2<Float>, heading: Float)?

    var body: some View {
        Canvas { context, size in
            let all = wallPoints + track + (here.map { [$0.position] } ?? [])
            guard let first = all.first else { return }
            var minP = first, maxP = first
            for p in all { minP = simd_min(minP, p); maxP = simd_max(maxP, p) }
            let span = max(maxP.x - minP.x, maxP.y - minP.y, 4)
            let scale = Float(min(size.width, size.height) - 16) / span
            let mid = (minP + maxP) / 2
            func point(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: size.width / 2 + CGFloat((p.x - mid.x) * scale), y: size.height / 2 + CGFloat((p.y - mid.y) * scale))
            }
            for p in wallPoints {
                let c = point(p)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 1.3, y: c.y - 1.3, width: 2.6, height: 2.6)), with: .color(Lux.goldBright.opacity(0.85)))
            }
            if track.count > 1 {
                var path = Path()
                path.move(to: point(track[0]))
                for p in track.dropFirst() { path.addLine(to: point(p)) }
                context.stroke(path, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let here {
                let c = point(here.position)
                let a = CGFloat(here.heading)
                var arrow = Path()
                arrow.move(to: CGPoint(x: c.x + 9 * sin(a), y: c.y - 9 * cos(a)))
                arrow.addLine(to: CGPoint(x: c.x + 5 * sin(a + 2.5), y: c.y - 5 * cos(a + 2.5)))
                arrow.addLine(to: CGPoint(x: c.x + 5 * sin(a - 2.5), y: c.y - 5 * cos(a - 2.5)))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(Theme.orangeSoft))
                context.stroke(arrow, with: .color(.white), lineWidth: 1)
            }
        }
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .accessibilityLabel("Карта обхода")
    }
}

/// Расстояние до стены: зелёный — 3–6 м (лидар точнее всего), жёлтый — ближе или дальше.
struct HouseScanDistanceChip: View {
    let meters: Float?

    var body: some View {
        if let meters {
            let good = meters >= 3 && meters <= 6
            HStack(spacing: 5) {
                Image(systemName: "arrow.left.and.right").font(.caption2.weight(.bold))
                Text(Units.length(Double(meters), digits: 1)).font(.caption.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(good ? Theme.ink : .white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(good ? Theme.orangeSoft : Theme.gold.opacity(0.85), in: Capsule())
            .accessibilityLabel("До стены")
        }
    }
}
