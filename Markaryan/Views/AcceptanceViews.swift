import SwiftUI
import ARKit
import RealityKit
import PhotosUI
import simd

// MARK: - «Приёмка без приёмщика»: ровность лидаром, дефекты по фото ИИ, акт осмотра с нормами

/// Что проверяем и какая норма (СП 71.13330.2017 «Изоляционные и отделочные покрытия», ориентиры для приёмки).
enum SurfaceKind: String, CaseIterable, Codable, Identifiable {
    case wallPaint, wallTile, floorLaminate, floorTile, ceiling
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallPaint: "Стена под покраску / обои"
        case .wallTile: "Стена под плитку"
        case .floorLaminate: "Пол под ламинат, паркет"
        case .floorTile: "Пол под плитку"
        case .ceiling: "Потолок"
        }
    }
    var isFloor: Bool { self == .floorLaminate || self == .floorTile }
    var isWall: Bool { self == .wallPaint || self == .wallTile }
    /// Допустимый просвет (неровность) на 2 м, мм.
    var flatnessMM: Double {
        switch self {
        case .wallPaint, .ceiling: 2
        case .wallTile: 3
        case .floorLaminate: 2
        case .floorTile: 4
        }
    }
    /// Отклонение от вертикали (стены) или горизонтали (пол), мм на 1 м.
    var slopeMMPerM: Double { isFloor ? 2 : 1 }
    var norm: String {
        switch self {
        case .wallPaint: "СП 71.13330.2017, табл. 7.5 — высококачественная штукатурка: неровности до 2 мм, вертикаль до 1 мм на 1 м"
        case .wallTile: "СП 71.13330.2017, табл. 7.4/7.5 — основание под плитку: неровности до 3 мм на 2 м"
        case .floorLaminate: "СП 71.13330.2017, табл. 8.5 — просвет под 2‑метровой рейкой до 2 мм (ламинат, паркет, линолеум)"
        case .floorTile: "СП 71.13330.2017, табл. 8.5 — просвет под 2‑метровой рейкой до 4 мм (плитка)"
        case .ceiling: "СП 71.13330.2017, табл. 7.5 — неровности до 2 мм, горизонталь до 1 мм на 1 м"
        }
    }
}

struct AcceptanceCheck: Codable, Identifiable {
    enum Kind: String, Codable { case flatness, defect }
    var id = UUID()
    var kind: Kind
    var room: String
    var title: String
    var detail: String
    var norm: String
    var ok: Bool
    var imageFile: String?
    var date = Date()
    var fixed = false
}

/// Проверки по объекту: в телефоне (JSON + картинки).
@MainActor final class AcceptanceStore: ObservableObject {
    static let shared = AcceptanceStore()
    @Published private(set) var checks: [AcceptanceCheck] = []
    private var objectKey = ""

    private var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("Acceptance", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load(object: UUID?) {
        objectKey = object?.uuidString ?? "loose"
        if let data = UserDefaults.standard.data(forKey: "acceptance.\(objectKey)"), let list = try? JSONDecoder().decode([AcceptanceCheck].self, from: data) { checks = list } else { checks = [] }
    }
    private func save() { if let data = try? JSONEncoder().encode(checks) { UserDefaults.standard.set(data, forKey: "acceptance.\(objectKey)") } }

    func add(_ check: AcceptanceCheck, image: UIImage?) {
        var c = check
        if let image, let folder, let data = image.jpegData(compressionQuality: 0.82) {
            let name = "\(c.id.uuidString).jpg"
            try? data.write(to: folder.appendingPathComponent(name))
            c.imageFile = name
        }
        checks.insert(c, at: 0)
        save()
    }
    func toggleFixed(_ id: UUID) { if let i = checks.firstIndex(where: { $0.id == id }) { checks[i].fixed.toggle(); save() } }
    func remove(_ id: UUID) {
        if let file = checks.first(where: { $0.id == id })?.imageFile, let folder { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
        checks.removeAll { $0.id == id }
        save()
    }
    func image(_ check: AcceptanceCheck) -> UIImage? {
        guard let file = check.imageFile, let folder else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(file).path)
    }
}

// MARK: Измерение ровности по глубине лидара

struct FlatnessResult {
    var spanMM: Double          // просвет: от впадины до горба (95-й − 5-й перцентиль), мм
    var bumpMM: Double          // самый большой горб над плоскостью
    var dipMM: Double           // самая глубокая впадина
    var slopeMMPerM: Double     // отклонение от вертикали/горизонтали
    var areaM2: Double          // какую площадь измерили
    var distance: Double        // до поверхности, м
    var image: UIImage          // кадр с цветной картой
    var okFlat: Bool
    var okSlope: Bool
}

enum FlatnessMeter {
    /// Несколько кадров глубины подряд (телефон неподвижен) → средняя глубина → плоскость → отклонения и карта.
    static func measure(frames: [ARFrame], surface: SurfaceKind) -> FlatnessResult? {
        guard let last = frames.last, let depth0 = last.sceneDepth?.depthMap ?? last.smoothedSceneDepth?.depthMap else { return nil }
        let w = CVPixelBufferGetWidth(depth0), h = CVPixelBufferGetHeight(depth0)
        var sum = [Float](repeating: 0, count: w * h), count = [Float](repeating: 0, count: w * h)
        let start = last.camera.transform.columns.3
        for frame in frames {
            // Кадры, где телефон сдвинули больше чем на 1 см, не усредняем.
            let p = frame.camera.transform.columns.3
            if simd_distance(SIMD3(p.x, p.y, p.z), SIMD3(start.x, start.y, start.z)) > 0.01 { continue }
            guard let data = frame.sceneDepth ?? frame.smoothedSceneDepth else { continue }
            let map = data.depthMap, conf = data.confidenceMap
            CVPixelBufferLockBaseAddress(map, .readOnly); defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
            if let conf { CVPixelBufferLockBaseAddress(conf, .readOnly) }
            defer { if let conf { CVPixelBufferUnlockBaseAddress(conf, .readOnly) } }
            guard let base = CVPixelBufferGetBaseAddress(map) else { continue }
            let row = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.size
            let d = base.assumingMemoryBound(to: Float32.self)
            let c = conf.flatMap { CVPixelBufferGetBaseAddress($0)?.assumingMemoryBound(to: UInt8.self) }
            let crow = conf.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
            for y in 0..<h { for x in 0..<w {
                if let c, c[y * crow + x] < 2 { continue }   // только высокая уверенность
                let v = d[y * row + x]
                if v > 0.2 && v < 3.5 { sum[y * w + x] += v; count[y * w + x] += 1 }
            } }
        }
        // Камера: внутренние параметры для кадра камеры → масштаб к карте глубины.
        let K = last.camera.intrinsics
        let imageW = Float(CVPixelBufferGetWidth(last.capturedImage))
        let s = Float(w) / imageW
        let fx = K[0][0] * s, fy = K[1][1] * s, cx = K[2][0] * s, cy = K[2][1] * s
        // Центральные 70 % кадра.
        let x0 = Int(Float(w) * 0.15), x1 = Int(Float(w) * 0.85), y0 = Int(Float(h) * 0.15), y1 = Int(Float(h) * 0.85)
        var pts: [SIMD3<Float>] = [], idx: [Int] = []
        for y in y0..<y1 { for x in x0..<x1 {
            let i = y * w + x
            guard count[i] > 0 else { continue }
            let z = sum[i] / count[i]
            pts.append(SIMD3((Float(x) - cx) * z / fx, -(Float(y) - cy) * z / fy, -z)); idx.append(i)
        } }
        guard pts.count > 800 else { return nil }
        // Плоскость Z = aX + bY + c (МНК).
        var sxx: Float = 0, sxy: Float = 0, syy: Float = 0, sx: Float = 0, sy: Float = 0, sxz: Float = 0, syz: Float = 0, sz: Float = 0
        for p in pts { sxx += p.x*p.x; sxy += p.x*p.y; syy += p.y*p.y; sx += p.x; sy += p.y; sxz += p.x*p.z; syz += p.y*p.z; sz += p.z }
        let n = Float(pts.count)
        let A = simd_float3x3(SIMD3(sxx, sxy, sx), SIMD3(sxy, syy, sy), SIMD3(sx, sy, n))
        guard abs(A.determinant) > 1e-9 else { return nil }
        let coef = A.inverse * SIMD3(sxz, syz, sz)
        let norm = sqrt(1 + coef.x * coef.x + coef.y * coef.y)
        var residual = [Float](repeating: .nan, count: w * h)
        var values: [Float] = []
        values.reserveCapacity(pts.count)
        for (k, p) in pts.enumerated() {
            let r = (p.z - (coef.x * p.x + coef.y * p.y + coef.z)) / norm * 1000   // мм; + — к камере (горб)
            residual[idx[k]] = r; values.append(r)
        }
        let sorted = values.sorted()
        let p5 = Double(sorted[Int(Double(sorted.count) * 0.05)]), p95 = Double(sorted[Int(Double(sorted.count) * 0.95)])
        let span = p95 - p5
        // Нормаль плоскости в мире: стены — от вертикали, пол и потолок — от горизонтали.
        let nCam = simd_normalize(SIMD3(coef.x, coef.y, -1))
        let R = simd_float3x3(SIMD3(last.camera.transform.columns.0.x, last.camera.transform.columns.0.y, last.camera.transform.columns.0.z),
                              SIMD3(last.camera.transform.columns.1.x, last.camera.transform.columns.1.y, last.camera.transform.columns.1.z),
                              SIMD3(last.camera.transform.columns.2.x, last.camera.transform.columns.2.y, last.camera.transform.columns.2.z))
        let nWorld = simd_normalize(R * nCam)
        let slopeAngle = surface.isWall ? asin(min(1, abs(Double(nWorld.y)))) : acos(min(1, abs(Double(nWorld.y))))
        let slope = tan(slopeAngle) * 1000
        let meanZ = Double(-sz / n)
        let widthM = Double(x1 - x0) * meanZ / Double(fx), heightM = Double(y1 - y0) * meanZ / Double(fy)
        let tol = Float(surface.flatnessMM / 2)
        let image = heatmap(frame: last, residual: residual, w: w, h: h, tolerance: tol)
        return FlatnessResult(spanMM: span, bumpMM: p95, dipMM: -p5, slopeMMPerM: slope, areaM2: widthM * heightM, distance: meanZ,
                              image: image, okFlat: span <= surface.flatnessMM + 1, okSlope: slope <= surface.slopeMMPerM * 1.5)
    }

    /// Кадр камеры + полупрозрачная карта: зелёный — в норме, жёлтый — на грани, красный — горб, синий — яма.
    private static func heatmap(frame: ARFrame, residual: [Float], w: Int, h: Int, tolerance: Float) -> UIImage {
        let ci = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()
        let size = CGSize(width: 1280, height: 960)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: size.width / ci.extent.width, y: size.height / ci.extent.height))
        let camera = context.createCGImage(scaled, from: CGRect(origin: .zero, size: size))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let r = residual[i]
            guard !r.isNaN else { continue }
            let a = abs(r)
            let color: (UInt8, UInt8, UInt8) = a <= tolerance ? (40, 190, 90) : a <= tolerance * 2 ? (240, 200, 40) : (r > 0 ? (230, 60, 50) : (60, 110, 230))
            pixels[i * 4] = color.0; pixels[i * 4 + 1] = color.1; pixels[i * 4 + 2] = color.2; pixels[i * 4 + 3] = 120
        }
        let overlay: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        let landscape = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
            if let camera { cg.draw(camera, in: CGRect(origin: .zero, size: size)) }
            if let overlay { cg.interpolationQuality = .none; cg.draw(overlay, in: CGRect(origin: .zero, size: size)) }
        }
        guard let cg = landscape.cgImage else { return landscape }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }
}

/// Камера с лидаром: хранит последние кадры для усреднения.
final class FlatnessCamera: NSObject, ARSessionDelegate, ObservableObject {
    private var buffer: [ARFrame] = []
    private var collecting = false
    private var done: (([ARFrame]) -> Void)?
    weak var session: ARSession?

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard collecting else { return }
        buffer.append(frame)
        if buffer.count >= 15 {
            collecting = false
            let frames = buffer; buffer = []
            let callback = done
            DispatchQueue.main.async { callback?(frames) }
        }
    }

    func capture(_ completion: @escaping ([ARFrame]) -> Void) { buffer = []; done = completion; collecting = true }

    static func configuration() -> ARWorldTrackingConfiguration {
        let c = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { c.frameSemantics.insert(.sceneDepth) }
        return c
    }
}

struct FlatnessARView: UIViewRepresentable {
    let camera: FlatnessCamera
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableHDR]
        view.session.delegate = camera
        camera.session = view.session
        view.session.run(FlatnessCamera.configuration(), options: [.resetTracking, .removeExistingAnchors])
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {}
    static func dismantleUIView(_ view: ARView, coordinator: ()) { view.session.pause() }
}

struct FlatnessScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = FlatnessCamera()
    @State private var surface: SurfaceKind = .wallPaint
    @State private var room = "Комната"
    @State private var measuring = false
    @State private var result: FlatnessResult?
    @State private var failed = false
    let onSave: (AcceptanceCheck, UIImage) -> Void

    var body: some View {
        ZStack {
            FlatnessARView(camera: camera).ignoresSafeArea()
            // Прицел: какую часть кадра меряем.
            if result == nil {
                RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(.horizontal, 50).padding(.vertical, 170).allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let result {
                    ScrollView { resultCard(result) }.frame(maxHeight: 560).scrollBounceBehavior(.basedOnSize)
                } else { controls }
            }
        }
        // Крестик всегда на месте — сверху поверх камеры и результата.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("РОВНОСТЬ ЛИДАРОМ").font(.headline).tracking(2).foregroundStyle(.white).shadow(radius: 4)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white).padding(12).background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 20).padding(.top, 6)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Поверхность", selection: $surface) { ForEach(SurfaceKind.allCases) { Text($0.title.tr).tag($0) } }.pickerStyle(.menu)
            TextField("Комната, например «Кухня»", text: $room).padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            Text("Встаньте в 1–1,5 м, направьте телефон прямо на \(surface.isFloor ? "пол" : surface == .ceiling ? "потолок" : "стену"), держите неподвижно 1 секунду.")
                .font(.caption).foregroundStyle(Theme.muted)
            if failed { Text("Не хватило точек глубины: подойдите ближе, включите свет, не двигайте телефон.").font(.caption).foregroundStyle(Theme.danger) }
            PrimaryButton(title: measuring ? "Меряем… не двигайте" : "Измерить", icon: "ruler") {
                measuring = true; failed = false
                camera.capture { frames in
                    let r = FlatnessMeter.measure(frames: frames, surface: surface)
                    measuring = false
                    if let r { result = r; Haptics.success() } else { failed = true; Haptics.warning() }
                }
            }
            .disabled(measuring)
        }
        .padding(18).background(Theme.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(12)
    }

    private func resultCard(_ r: FlatnessResult) -> some View {
        let ok = r.okFlat && r.okSlope
        return VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: r.image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 14))
            Label(ok ? "В норме" : "Есть отклонения от нормы", systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(ok ? Theme.success : Theme.danger)
            Text("Неровность (просвет): \(fmt(r.spanMM)) мм при норме до \(fmt(surface.flatnessMM)) мм · горб \(fmt(r.bumpMM)) мм, яма \(fmt(r.dipMM)) мм")
                .font(.footnote)
            Text("\(surface.isWall ? "От вертикали" : "Уклон"): \(fmt(r.slopeMMPerM)) мм на 1 м при норме до \(fmt(surface.slopeMMPerM)) мм · площадь ≈ \(fmt(r.areaM2)) м²")
                .font(.footnote)
            Text("Зелёный — в норме, жёлтый — на грани, красный — горб, синий — яма. Точность лидара ±2 мм: спорные места проверьте 2‑метровым правилом.")
                .font(.caption2).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Button { result = nil } label: { SecondaryActionLabel(title: "Ещё раз", icon: "arrow.counterclockwise") }
                Button {
                    let check = AcceptanceCheck(kind: .flatness, room: room, title: "\(surface.title): \(ok ? "в норме" : "отклонения")",
                                                detail: "Просвет \(fmt(r.spanMM)) мм (норма \(fmt(surface.flatnessMM))); \(surface.isWall ? "вертикаль" : "уклон") \(fmt(r.slopeMMPerM)) мм/м (норма \(fmt(surface.slopeMMPerM))); площадь \(fmt(r.areaM2)) м²",
                                                norm: surface.norm, ok: ok)
                    onSave(check, r.image); dismiss()
                } label: { SecondaryActionLabel(title: "В акт", icon: "doc.badge.plus") }
            }
            .buttonStyle(PremiumPressStyle())
        }
        .padding(16).background(Theme.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(12)
    }

    private func fmt(_ v: Double) -> String { ParcelRules.format(v, digits: 1) }
}

// MARK: Дефекты по фото

struct DefectReading: Codable {
    struct Defect: Codable, Hashable { var title: String; var severity: String; var norm: String?; var fix: String?; var x: Double?; var y: Double? }
    var defects: [Defect]
    var summary: String?
}

enum DefectFinder {
    static func find(_ image: UIImage, room: String) async throws -> DefectReading {
        guard let base = AIServerConfig.baseURL else { throw ClaudeError.api("Поиск дефектов работает через сервер приложения.") }
        let schema: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(#"""
        {"type":"object","properties":{"summary":{"type":"string"},
          "defects":{"type":"array","items":{"type":"object","properties":{
            "title":{"type":"string"},"severity":{"type":"string","enum":["критично","существенно","косметика"]},
            "norm":{"type":"string"},"fix":{"type":"string"},"x":{"type":"number"},"y":{"type":"number"}},"required":["title","severity"]}}},
          "required":["defects"]}
        """#.utf8))) as? [String: Any] ?? [:]
        let system = """
        Ты — инженер технадзора на приёмке ремонта или квартиры в новостройке. Найди на фото видимые дефекты:
        неровные и разной ширины швы плитки, перепад между плитками, сколы, трещины, отслоения, пузыри, пятна, подтёки краски,
        щели у плинтуса и наличников, царапины и сколы на окнах и дверях, перекос дверей, следы протечек, плесень.
        Для каждого: короткое название, серьёзность, норма (СП 71.13330.2017, ГОСТ 30674 окна, ГОСТ 475 двери — пункт, если уверен),
        как исправить, и точка на фото x,y от 0 до 1000. Не выдумывай: нет дефектов — пустой список. summary — одним предложением.
        """
        let data = try await ServerAIClient(base: base).structured(system: system, turns: [ClaudeTurn(role: .user, text: "Помещение: \(room). Найди дефекты.", image: image)],
                                                                   toolName: "defects", toolDescription: "Дефекты на фото", schema: schema, maxTokens: 4000)
        return try JSONDecoder().decode(DefectReading.self, from: data)
    }

    /// Фото с номерами дефектов.
    static func marked(_ image: UIImage, _ defects: [DefectReading.Defect]) -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
            let r = max(18, image.size.width / 40)
            for (i, d) in defects.enumerated() {
                guard let x = d.x, let y = d.y else { continue }
                let p = CGPoint(x: x / 1000 * image.size.width, y: y / 1000 * image.size.height)
                let color: UIColor = d.severity == "критично" ? .systemRed : d.severity == "существенно" ? .systemOrange : .systemYellow
                color.setStroke(); color.withAlphaComponent(0.85).setFill()
                let circle = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                circle.lineWidth = r / 5; circle.fill()
                let text = "\(i + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: r), .foregroundColor: UIColor.white]
                let s = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: attrs)
            }
        }
    }
}

// MARK: Экран приёмки

struct AcceptanceView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var acceptance = AcceptanceStore.shared
    @State private var scanning = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var photo: UIImage?
    @State private var room = "Комната"
    @State private var finding = false
    @State private var error: String?
    @State private var act: SharedFile?
    @State private var tasksAdded = false

    private var problems: [AcceptanceCheck] { acceptance.checks.filter { !$0.ok && !$0.fixed } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                tools
                if finding { HStack(spacing: 10) { ProgressView(); Text("Ищем дефекты…").foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity) }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                if acceptance.checks.isEmpty { howTo } else { summary; checksList; actions }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Приёмка").navigationBarTitleDisplayMode(.inline).featureIntro(.acceptance)
        .onAppear { acceptance.load(object: store.inObject ? store.activeProjectID : nil) }
        .fullScreenCover(isPresented: $scanning) {
            FlatnessScanView { check, image in acceptance.add(check, image: image) }
        }
        .fullScreenCover(isPresented: $showCamera) { CameraCaptureView(image: $photo).ignoresSafeArea() }
        .onChange(of: pickerItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) } } }
        .onChange(of: photo) { _, image in if let image { Task { await findDefects(image) } } }
        .sheet(item: $act) { file in ActivityShareSheet(items: [file.url]) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПРИЁМКА БЕЗ ПРИЁМЩИКА").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.goldLight)
            Text("Проверьте ремонт или новостройку сами").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.white)
            Text("Лидар меряет ровность стен и пола по нормам СП и рисует карту отклонений. ИИ находит дефекты на фото. В конце — акт осмотра с фото и нормами для застройщика или бригады.")
                .font(.footnote).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Комната, например «Ванная»", text: $room).padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            if HouseScanRecorder.hasLiDAR {
                Button { scanning = true } label: {
                    AppTabRow(icon: "ruler.fill", title: "Ровность стен и пола — лидаром", subtitle: "Цветная карта горбов и ям, просвет и вертикаль в мм против нормы")
                }
                .buttonStyle(PremiumCardPressStyle())
            } else {
                InfoNote(text: "Ровность лидаром — на iPhone Pro. На этом iPhone доступен поиск дефектов по фото.")
            }
            HStack(spacing: 10) {
                Button { showCamera = true } label: { SecondaryActionLabel(title: "Снять дефект", icon: "camera.fill") }
                PhotosPicker(selection: $pickerItem, matching: .images) { SecondaryActionLabel(title: "Из фото", icon: "photo") }
            }
            .buttonStyle(PremiumPressStyle())
            PaidNote(kind: "vision")
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("КАК ПРОВЕРИТЬ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            Label("Впишите комнату и измерьте лидаром каждую стену, пол и потолок — по одному замеру на участок 1–1,5 м", systemImage: "1.circle.fill")
            Label("Снимите вблизи всё подозрительное: швы плитки, углы, окна, двери, стыки — ИИ отметит дефекты на фото", systemImage: "2.circle.fill")
            Label("Нажмите «Акт осмотра» — PDF с фото, мм и пунктами норм. Замечания одной кнопкой станут задачами бригаде", systemImage: "3.circle.fill")
        }
        .font(.footnote).foregroundStyle(Theme.ink)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    private var summary: some View {
        let ok = acceptance.checks.filter(\.ok).count
        return HStack {
            PlanStat(value: "\(acceptance.checks.count)", title: "Проверок")
            PlanStat(value: "\(problems.count)", title: "Замечаний")
            PlanStat(value: "\(ok)", title: "В норме")
        }
    }

    private var checksList: some View {
        ForEach(acceptance.checks) { check in
            HStack(alignment: .top, spacing: 12) {
                if let image = acceptance.image(check) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : check.fixed ? "checkmark.circle" : "exclamationmark.circle.fill")
                            .foregroundStyle(check.ok ? Theme.success : check.fixed ? Theme.muted : Theme.danger)
                        Text(check.title).font(.subheadline.weight(.semibold)).strikethrough(check.fixed)
                    }
                    Text("\(check.room) · \(check.detail)").font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Text(check.norm).font(.caption2).foregroundStyle(Theme.gold).lineLimit(2)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
            .contextMenu {
                if !check.ok { Button { acceptance.toggleFixed(check.id) } label: { Label(check.fixed ? "Не исправлено" : "Исправлено", systemImage: "checkmark") } }
                Button(role: .destructive) { acceptance.remove(check.id) } label: { Label("Удалить", systemImage: "trash") }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Акт осмотра (PDF)", icon: "doc.richtext") { if let url = AcceptanceAct.pdf(checks: acceptance.checks, store: store, images: acceptance.image) { act = SharedFile(url: url); Haptics.success() } }
            if !problems.isEmpty {
                Button {
                    for c in problems { store.projectTasks.insert(ProjectTask(title: "Устранить: \(c.title) (\(c.room))", notes: c.detail + "\n" + c.norm), at: 0) }
                    tasksAdded = true; Haptics.success()
                } label: { SecondaryActionLabel(title: tasksAdded ? "Замечания в задачах объекта" : "Замечания → задачи бригаде", icon: tasksAdded ? "checkmark" : "checklist") }
                .buttonStyle(PremiumPressStyle()).disabled(tasksAdded)
            }
            Text("Долгое нажатие на пункт — «Исправлено» или удалить. Акт — техническое заключение собственника, не замена экспертизы.").font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    private func findDefects(_ image: UIImage) async {
        finding = true; error = nil
        defer { finding = false; photo = nil }
        do {
            let reading = try await DefectFinder.find(image, room: room)
            if reading.defects.isEmpty {
                acceptance.add(AcceptanceCheck(kind: .defect, room: room, title: "Дефектов не видно", detail: reading.summary ?? "По фото замечаний нет", norm: "Визуальный осмотр", ok: true), image: image)
            } else {
                let marked = DefectFinder.marked(image, reading.defects)
                for (i, d) in reading.defects.enumerated() {
                    acceptance.add(AcceptanceCheck(kind: .defect, room: room, title: "\(i + 1). \(d.title)", detail: "\(d.severity)" + (d.fix.map { " · исправить: \($0)" } ?? ""), norm: d.norm ?? "Визуальный осмотр", ok: false), image: i == 0 ? marked : nil)
                }
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Акт осмотра

@MainActor enum AcceptanceAct {
    static func pdf(checks: [AcceptanceCheck], store: AppStore, images: (AcceptanceCheck) -> UIImage?) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842), m: CGFloat = 40
        let ink = UIColor(red: 0.09, green: 0.14, blue: 0.12, alpha: 1), gold = UIColor(red: 0.58, green: 0.44, blue: 0.16, alpha: 1)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y: CGFloat = 0
            func newPage() { ctx.beginPage(); y = m }
            func text(_ s: String, _ font: UIFont, _ color: UIColor = ink, gap: CGFloat = 4) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let rect = (s as NSString).boundingRect(with: CGSize(width: page.width - 2 * m, height: 2000), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                if y + rect.height > page.height - m { newPage() }
                (s as NSString).draw(in: CGRect(x: m, y: y, width: page.width - 2 * m, height: rect.height + 2), withAttributes: attrs)
                y += rect.height + gap
            }
            newPage()
            text("АКТ ОСМОТРА", .boldSystemFont(ofSize: 20))
            text([store.inObject ? store.projectDisplayName : "", store.passport.address, Date().formatted(date: .long, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · "), .systemFont(ofSize: 11), gold, gap: 12)
            let problems = checks.filter { !$0.ok && !$0.fixed }
            text("Проверок: \(checks.count). Замечаний: \(problems.count). В норме: \(checks.filter(\.ok).count).", .systemFont(ofSize: 11), gap: 14)
            for (i, c) in checks.enumerated() {
                text("\(i + 1). \(c.room): \(c.title)\(c.ok ? " — в норме" : c.fixed ? " — исправлено" : " — ЗАМЕЧАНИЕ")", .boldSystemFont(ofSize: 11.5), c.ok ? ink : UIColor.systemRed)
                text(c.detail, .systemFont(ofSize: 10.5))
                text("Норма: \(c.norm)", .italicSystemFont(ofSize: 9.5), gold)
                if let image = images(c) {
                    let w = min(300, page.width - 2 * m), h = w * image.size.height / max(1, image.size.width)
                    if y + h > page.height - m { newPage() }
                    image.draw(in: CGRect(x: m, y: y, width: w, height: h)); y += h + 10
                }
                y += 6
            }
            y += 10
            if !problems.isEmpty { text("Требуется устранить замечания №\(checks.enumerated().filter { !$0.element.ok && !$0.element.fixed }.map { "\($0.offset + 1)" }.joined(separator: ", ")) до подписания акта приёма‑передачи / оплаты этапа.", .boldSystemFont(ofSize: 11)) }
            text("Измерения ровности выполнены лидаром iPhone (точность ±2 мм) с усреднением; спорные места рекомендуется подтвердить 2‑метровым правилом. Документ — техническое заключение собственника для предъявления замечаний.", .systemFont(ofSize: 9), gold, gap: 20)
            text("Собственник: ____________________        Представитель подрядчика / застройщика: ____________________", .systemFont(ofSize: 10.5))
            text("Подготовлено в приложении «\(Brand.name)»", .systemFont(ofSize: 9), gold)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Акт осмотра — \(store.projectDisplayName).pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
