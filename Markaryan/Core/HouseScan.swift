import Foundation
import ARKit
import Accelerate
import CoreImage
import ImageIO
import UIKit
import CoreLocation
import CryptoKit
import simd

// «Дом снаружи», этап 1: обход дома с iPhone. Записываем ключевые кадры (JPEG), глубину LiDAR (Float16),
// уверенность глубины, позы камеры ARKit и внутренние параметры камеры; в конце — живой меш ARKit (OBJ).
// Всё пишется сразу на диск и пакуется в scan.zip (формат — docs/house-exterior/SPEC-0-1.md, §1.3).
// Обработка (сетка с размерами, сегментация, крыша, splatting) — на GPU; сервер только принимает пакет.

/// Кольцо покрытия: 36 секторов по 10° вокруг дома, у каждого ярус «стены» и ярус «крыша».
struct HouseCoverage: Equatable {
    static let sectors = 36
    var walls = [Int](repeating: 0, count: sectors)
    var roof = [Int](repeating: 0, count: sectors)
    /// Сектор, в котором сейчас стоит человек (nil — центр дома ещё не найден).
    var current: Int?
    /// Секторы, куда не пройти (дом впритык к соседу, забору): считаются закрытыми, сторону достроит обработчик.
    var blocked = Set<Int>()

    private func done(_ list: [Int], _ i: Int) -> Bool { list[i] > 0 || blocked.contains(i) }
    var wallShare: Double { Double((0..<Self.sectors).filter { done(walls, $0) }.count) / Double(Self.sectors) }
    var roofShare: Double { Double((0..<Self.sectors).filter { done(roof, $0) }.count) / Double(Self.sectors) }
    /// Общий процент: стены важнее (60 %), крыша — 40 %.
    var total: Double { wallShare * 0.6 + roofShare * 0.4 }

    /// Самая длинная незакрытая дуга (по стенам): начало и длина в секторах.
    var largestGap: (start: Int, length: Int)? {
        guard walls.contains(where: { $0 > 0 }) else { return nil }
        var best: (Int, Int)? = nil
        var i = 0
        while i < Self.sectors {
            if !done(walls, i) {
                var length = 0
                while length < Self.sectors && !done(walls, (i + length) % Self.sectors) { length += 1 }
                if best == nil || length > best!.1 { best = (i, length) }
                i += max(length, 1)
            } else { i += 1 }
        }
        return best.map { (start: $0.0, length: $0.1) }
    }
}

/// Одна подсказка за раз — самая важная (спецификация §1.1 B).
enum HouseScanHint: Equatable {
    case findHouse, lowLight, slower, stepBack, closer, raiseCamera, keepGoing, gap(String), done, hot

    var text: String {
        switch self {
        case .findHouse: return "Наведите камеру на дом"
        case .lowLight: return "Мало света или деталей — наведите на стену с фактурой"
        case .slower: return "Медленнее — кадры смазываются"
        case .stepBack: return "Отойдите — дом не помещается в кадр"
        case .closer: return "Подойдите ближе — до стены больше 20 м"
        case .raiseCamera: return "Поднимите камеру — снимите крышу и фронтон"
        case .keepGoing: return "Хорошо! Идите дальше по кругу"
        case .gap(let side): return "Осталось снять:".tr + " " + side.tr
        case .done: return "Дом снят со всех сторон — можно нажимать «Готово»"
        case .hot: return "Телефон перегрелся — сделайте паузу на минуту в тени"
        }
    }
    var icon: String {
        switch self {
        case .findHouse: return "house"
        case .lowLight: return "sun.max"
        case .slower: return "tortoise"
        case .stepBack: return "arrow.down.backward"
        case .closer: return "arrow.up.forward"
        case .raiseCamera: return "arrow.up.circle"
        case .keepGoing: return "figure.walk"
        case .gap: return "arrow.triangle.turn.up.right.circle"
        case .done: return "checkmark.seal"
        case .hot: return "thermometer.sun"
        }
    }
}

/// Запись одного кадра в manifest.json.
struct HouseScanFrame: Codable {
    var i: Int
    var t: Double
    var image: String
    var depth: String?
    var conf: String?
    /// 4×4 камера→мир, по столбцам (как simd_float4x4 в ARKit).
    var pose: [Float]
    /// fx, fy, cx, cy — для размера JPEG.
    var K: [Float]
    var tracking: String
    var exposure: Double
    /// "wall" или "roof".
    var tier: String
    /// Резкость (дисперсия лапласиана по яркости) — GPU берёт резкие кадры первыми.
    var sharpness: Float = 0
    /// Опорные точки ARKit этого кадра (points/NNNNNN.bin: float32 x,y,z + uint64 id) — для уточнения поз на GPU.
    var points: String?
}

struct HouseScanManifest: Codable {
    struct Size: Codable { var width: Int; var height: Int }
    struct Depth: Codable { var width: Int; var height: Int; var format = "f16"; var units = "m" }
    /// gravityAndHeading: y — вверх, x — на восток, −z — на север (компас, ±5–10°; точно — по углам участка).
    struct World: Codable {
        var alignment = "gravityAndHeading"; var up: [Float] = [0, 1, 0]; var units = "m"
        var location: Location?
    }
    struct Location: Codable { var lat: Double; var lon: Double; var accuracy: Double; var altitude: Double? }
    /// Кадр высокого разрешения (крыша и детали): своя поза и параметры камеры.
    struct Still: Codable { var i: Int; var image: String; var pose: [Float]; var K: [Float]; var width: Int; var height: Int }
    struct Coverage: Codable { var sectors: Int; var walls: Double; var roof: Double; var blocked: [Int] = [] }
    struct Control: Codable { var kind: String; var meters: Double; var note: String? }

    var format = "smetapro-house-scan"
    var version = 1
    var kind = "house"
    var createdAt: String
    var device: String
    var lidar: Bool
    var ios: String
    /// Кадры — как с сенсора (альбомная ориентация, «домой» справа), без поворота.
    var imageOrientation = "sensor-landscape-right"
    var image: Size
    var depth: Depth?
    var world = World()
    var center: [Float]?
    var coverage: Coverage
    var control: [Control] = []
    var frames: [HouseScanFrame]
    var stills: [Still] = []
    /// Участок из НСПД, если найден до скана.
    var parcel: CadastralParcel?
    /// Сколько кадров отброшено как смазанные (для отчёта о качестве).
    var rejectedBlurry = 0
    /// Язык приложения — на нём ИИ описывает крышу и детали в макете.
    var language: String?
}

@MainActor final class HouseScanRecorder: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var coverage = HouseCoverage()
    @Published private(set) var hint: HouseScanHint = .findHouse
    @Published private(set) var frameCount = 0
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var recording = false
    @Published private(set) var trackingOK = false
    /// Расстояние до того, что в центре кадра, м (округлено до 0,1).
    @Published private(set) var distance: Float?
    /// Мини‑карта: путь человека и точки стен, куда смотрела камера (вид сверху, x/z).
    @Published private(set) var track: [SIMD2<Float>] = []
    @Published private(set) var wallPoints: [SIMD2<Float>] = []
    /// Где человек сейчас и куда смотрит (для мини‑карты; обновляется ~5 раз в секунду).
    @Published private(set) var here: (position: SIMD2<Float>, heading: Float)?
    @Published private(set) var stillCount = 0
    private var lastHereUpdate: TimeInterval = 0
    private var darkSince: TimeInterval?

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    let id = UUID()
    let folder: URL
    private(set) var frames: [HouseScanFrame] = []
    weak var session: ARSession?

    // Отбор ключевых кадров (спецификация §1.2).
    private let minMove: Float = 0.35
    private let minTurn: Float = 8 * .pi / 180
    private let maxAngularSpeed: Float = 60 * .pi / 180
    private let minInterval: TimeInterval = 1.0 / 3
    private var lastKey: (pose: simd_float4x4, time: TimeInterval)?
    private var lastFrame: (pose: simd_float4x4, time: TimeInterval)?
    private var angularSpeed: Float = 0
    private var groundY: Float?
    private var centerSum = SIMD3<Float>(repeating: 0)
    private var centerCount: Float = 0
    private var lastDepthMedian: Float?
    private var limitedReason: ARCamera.TrackingState.Reason?
    private var startTime: TimeInterval?
    private var imageSize = (width: 1920, height: 1440)
    private var depthSize: (width: Int, height: Int)?
    /// Кадров в записи на диск: не больше двух, иначе пропускаем (ARKit не любит, когда держат его кадры).
    private var inFlight = 0
    private let writer = DispatchQueue(label: "house-scan-writer", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Резкость последних ключевых кадров: смазанный (< 45 % от медианы) отбрасывается.
    private var recentSharpness: [Float] = []
    private(set) var rejectedBlurry = 0
    private var stills: [HouseScanManifest.Still] = []
    private var lastStillTime: TimeInterval = 0
    private var stillInFlight = false
    private let maxStills = 36
    private var location: CLLocation?
    var parcel: CadastralParcel?

    override init() {
        folder = HouseScanStore.root.appendingPathComponent(id.uuidString, isDirectory: true)
        super.init()
    }

    // MARK: Сессия

    static func configuration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        // Север из компаса: макет сразу ложится на карту и кадастровый участок (солнце и тени — тоже).
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal, .vertical]
        if hasLiDAR {
            config.frameSemantics.insert(.sceneDepth)
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { config.sceneReconstruction = .mesh }
        }
        // Формат, в котором можно брать снимки высокого разрешения (12 Мп) — для крыши и деталей.
        if let hires = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing,
           hires.imageResolution.width <= 1920 {
            config.videoFormat = hires
            return config
        }
        // Иначе 4:3, наибольшее разрешение до 1920 по ширине — больше не нужно, а файлы растут.
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        if let best = formats.filter({ abs($0.imageResolution.width / $0.imageResolution.height - 4.0 / 3.0) < 0.01 && $0.imageResolution.width <= 1920 })
            .max(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = best
        }
        return config
    }

    func start() {
        if location == nil {
            Task { [weak self] in
                let found = await PreciseLocation.current()
                self?.location = found
            }
        }
        // Папки — только когда обход начался: открыть экран и закрыть его ничего не оставляет на диске.
        for sub in ["frames", "depth", "conf", "mesh", "points", "hires"] {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        recording = true
    }
    func pause() { recording = false }

    /// «Сторона недоступна»: закрывает самую большую неснятую дугу (или ±40° вокруг человека) — её достроит обработчик.
    func markBlocked() {
        var sectors: [Int] = []
        if let gap = coverage.largestGap, gap.length < HouseCoverage.sectors {
            sectors = (0..<gap.length).map { (gap.start + $0) % HouseCoverage.sectors }
        } else if let current = coverage.current {
            sectors = (-4...4).map { (current + $0 + HouseCoverage.sectors) % HouseCoverage.sectors }
        }
        guard !sectors.isEmpty else { return }
        // Недоступной может быть одна‑две стороны, не весь дом: за раз — не больше 9 секторов (90°) у человека,
        // всего — не больше трети кольца, иначе макет «достраивается» из ничего.
        if sectors.count > 9, let current = coverage.current {
            sectors = (-4...4).map { (current + $0 + HouseCoverage.sectors) % HouseCoverage.sectors }
        }
        let room = max(0, HouseCoverage.sectors / 3 - coverage.blocked.count)
        guard room > 0 else { blockedLimitReached = true; return }
        sectors = Array(sectors.filter { !coverage.blocked.contains($0) }.prefix(room))
        coverage.blocked.formUnion(sectors)
        hasBlocked = true
        Haptics.success()
    }
    @Published private(set) var hasBlocked = false
    /// Закрыто уже треть кольца — больше нельзя (подсказка на экране).
    @Published private(set) var blockedLimitReached = false

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        Task { @MainActor in
            switch state {
            case .normal: self.trackingOK = true; self.limitedReason = nil
            case .limited(let reason): self.trackingOK = false; self.limitedReason = reason
            case .notAvailable: self.trackingOK = false; self.limitedReason = nil
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Всё лёгкое — прямо здесь: позы и решение «ключевой ли кадр». Тяжёлое (JPEG) — в очереди записи.
        let pose = frame.camera.transform
        let time = frame.timestamp
        let tracking = frame.camera.trackingState
        let intrinsics = frame.camera.intrinsics
        let exposure = frame.camera.exposureDuration
        let resolution = frame.camera.imageResolution
        let depthMedian = Self.centerDepth(frame.sceneDepth?.depthMap)
        let light = frame.lightEstimate.map { Float($0.ambientIntensity) }
        // Без LiDAR — расстояние до стены по лучу из центра кадра (оценочная плоскость ARKit).
        var hitDistance: Float? = depthMedian
        if hitDistance == nil {
            let query = frame.raycastQuery(from: CGPoint(x: 0.5, y: 0.5), allowing: .estimatedPlane, alignment: .any)
            if let hit = session.raycast(query).first {
                hitDistance = simd_distance(hit.worldTransform.columns.3.xyz, pose.columns.3.xyz)
            }
        }
        Task { @MainActor in
            self.process(frame: frame, pose: pose, time: time, tracking: tracking, intrinsics: intrinsics,
                         exposure: exposure, resolution: resolution, distance: hitDistance, lidarDepth: depthMedian, light: light)
        }
    }

    private func process(frame: ARFrame, pose: simd_float4x4, time: TimeInterval, tracking: ARCamera.TrackingState,
                         intrinsics: simd_float3x3, exposure: TimeInterval, resolution: CGSize, distance: Float?, lidarDepth: Float?,
                         light: Float? = nil) {
        if let last = lastFrame, time > last.time {
            let turn = Self.angle(between: last.pose, and: pose)
            angularSpeed = angularSpeed * 0.7 + Float(turn / Float(time - last.time)) * 0.3
        }
        lastFrame = (pose, time)
        lastDepthMedian = distance
        let rounded = distance.map { ($0 * 10).rounded() / 10 }
        if rounded != self.distance { self.distance = rounded }
        // Темно дольше секунды (меньше ~250 лм) — подсказка про свет.
        if let light, light < 250 { if darkSince == nil { darkSince = time } } else { darkSince = nil }
        let position = pose.columns.3.xyz
        if groundY == nil, case .normal = tracking { groundY = position.y - 1.4 } // телефон на уровне груди
        let forward = -pose.columns.2.xyz

        // Центр дома — среднее точек, куда смотрит центр кадра (по горизонтали).
        if let distance, distance > 1.5, distance < 25, case .normal = tracking {
            let target = position + forward * distance
            centerSum += target; centerCount += 1
        }
        let center: SIMD3<Float>? = centerCount >= 5 ? centerSum / centerCount : nil
        let sector = center.map { Self.sector(of: position, around: $0) }
        let lookingUp = forward.y > sin(18 * Float.pi / 180)
        var hitHigh = false
        if let distance, let ground = groundY { hitHigh = (position + forward * distance).y - ground > 3.0 }
        let tier = (lookingUp || hitHigh) ? "roof" : "wall"

        if coverage.current != sector { coverage.current = sector }
        var next = nextHint(tracking: tracking, distance: distance, center: center, sector: sector)
        if let darkSince, time - darkSince > 1 { next = .lowLight }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical { next = .hot }
        if hint != next { hint = next }
        if time - lastHereUpdate > 0.2 {
            lastHereUpdate = time
            here = (SIMD2(position.x, position.z), atan2(forward.x, -forward.z))
        }

        guard recording, case .normal = tracking, angularSpeed < maxAngularSpeed, inFlight < 2 else { return }
        if let key = lastKey {
            let interval = ProcessInfo.processInfo.thermalState == .serious ? minInterval * 2 : minInterval
            guard time - key.time >= interval else { return }
            let moved = simd_distance(key.pose.columns.3.xyz, position)
            let turned = Self.angle(between: key.pose, and: pose)
            guard moved >= minMove || turned >= minTurn else { return }
        }
        // Смазанный кадр не берём (резкость считается по яркости с шагом 4 px — доли миллисекунды).
        let sharpness = Self.sharpness(frame.capturedImage)
        if recentSharpness.count >= 8 {
            let median = recentSharpness.sorted()[recentSharpness.count / 2]
            if sharpness < median * 0.45 { rejectedBlurry += 1; return }
        }
        recentSharpness.append(sharpness)
        if recentSharpness.count > 30 { recentSharpness.removeFirst() }
        lastKey = (pose, time)
        track.append(SIMD2(position.x, position.z))
        if let distance, distance < 25 {
            let p = position + forward * distance
            if wallPoints.count < 3000 { wallPoints.append(SIMD2(p.x, p.z)) }
        }
        if let sector {
            if tier == "roof" { coverage.roof[sector] += 1 } else { coverage.walls[sector] += 1 }
            if (tier == "roof" ? coverage.roof[sector] : coverage.walls[sector]) == 1 { Haptics.tap() }
        }
        if startTime == nil { startTime = time }
        imageSize = (Int(resolution.width), Int(resolution.height))
        let index = frames.count + 1
        let name = String(format: "%06d", index)
        let hasDepth = frame.sceneDepth != nil
        let item = HouseScanFrame(
            i: index, t: time - (startTime ?? time), image: "frames/\(name).jpg",
            depth: hasDepth ? "depth/\(name).f16" : nil, conf: hasDepth ? "conf/\(name).u8" : nil,
            pose: Self.flatten(pose), K: [intrinsics[0][0], intrinsics[1][1], intrinsics[2][0], intrinsics[2][1]],
            tracking: "normal", exposure: exposure, tier: tier, sharpness: sharpness,
            points: frame.rawFeaturePoints == nil ? nil : "points/\(name).bin")
        frames.append(item)
        frameCount = frames.count
        write(frame: frame, name: name)
        if tier == "roof" { captureStill(index: index) }
    }

    private func nextHint(tracking: ARCamera.TrackingState, distance: Float?, center: SIMD3<Float>?, sector: Int?) -> HouseScanHint {
        if case .limited(let reason) = tracking {
            return reason == .excessiveMotion ? .slower : .lowLight
        }
        if angularSpeed > maxAngularSpeed { return .slower }
        if let distance, distance < 3 { return .stepBack }
        if let distance, distance > 20 { return .closer }
        guard center != nil, let sector else { return .findHouse }
        if coverage.blocked.contains(sector) { return .keepGoing }
        if coverage.walls[sector] > 0 && coverage.roof[sector] == 0 { return .raiseCamera }
        if coverage.wallShare >= 0.9 && coverage.roofShare >= 0.6 { return .done }
        if coverage.walls[sector] > 0, let gap = coverage.largestGap, gap.length >= 4 {
            // Дуга «впереди» по ходу — значит направление очевидно; иначе подскажем, где она.
            let middle = (gap.start + gap.length / 2) % HouseCoverage.sectors
            let delta = (middle - sector + HouseCoverage.sectors) % HouseCoverage.sectors
            if delta > 6 && delta < 30 { return .gap(delta <= 18 ? "сторона справа по ходу" : "сторона слева, вернитесь назад") }
        }
        return .keepGoing
    }

    // MARK: Запись на диск

    private func write(frame: ARFrame, name: String) {
        inFlight += 1
        // Глубину копируем сразу (маленькая), кадр камеры — в CIImage, JPEG — в фоне.
        let depth = frame.sceneDepth.flatMap { Self.float16(from: $0.depthMap) }
        let conf = frame.sceneDepth?.confidenceMap.flatMap { Self.bytes(of: $0) }
        if depthSize == nil, let map = frame.sceneDepth?.depthMap {
            depthSize = (CVPixelBufferGetWidth(map), CVPixelBufferGetHeight(map))
        }
        var points: Data?
        if let cloud = frame.rawFeaturePoints, !cloud.points.isEmpty {
            var data = Data(capacity: cloud.points.count * 20)
            for (point, id) in zip(cloud.points, cloud.identifiers) {
                withUnsafeBytes(of: point.x) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: point.y) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: point.z) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: id) { data.append(contentsOf: $0) }
            }
            points = data
        }
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let folder = folder
        let context = ciContext
        writer.async { [weak self] in
            var written: Int64 = 0
            if let points { try? points.write(to: folder.appendingPathComponent("points/\(name).bin")); written += Int64(points.count) }
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
            if let jpeg = context.jpegRepresentation(of: image, colorSpace: space, options: [quality: 0.8]) {
                try? jpeg.write(to: folder.appendingPathComponent("frames/\(name).jpg"))
                written += Int64(jpeg.count)
            }
            if let depth { try? depth.write(to: folder.appendingPathComponent("depth/\(name).f16")); written += Int64(depth.count) }
            if let conf { try? conf.write(to: folder.appendingPathComponent("conf/\(name).u8")); written += Int64(conf.count) }
            Task { @MainActor in
                guard let self else { return }
                self.inFlight -= 1
                self.bytesWritten += written
            }
        }
    }

    /// Снимок 12 Мп раз в 2 с на ярусе «крыша» (до 36 штук): по ним ИИ видит кровлю, трубы, водостоки.
    private func captureStill(index: Int) {
        guard let session, !stillInFlight, stills.count < maxStills,
              ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing != nil,
              Date().timeIntervalSinceReferenceDate - lastStillTime > 2 else { return }
        stillInFlight = true
        lastStillTime = Date().timeIntervalSinceReferenceDate
        session.captureHighResolutionFrame { [weak self] frame, _ in
            Task { @MainActor in
                guard let self else { return }
                defer { self.stillInFlight = false }
                guard let frame else { return }
                let name = String(format: "%06d", index)
                let width = CVPixelBufferGetWidth(frame.capturedImage), height = CVPixelBufferGetHeight(frame.capturedImage)
                let k = frame.camera.intrinsics
                self.stillCount += 1
                self.stills.append(.init(i: index, image: "hires/\(name).jpg", pose: Self.flatten(frame.camera.transform),
                                         K: [k[0][0], k[1][1], k[2][0], k[2][1]], width: width, height: height))
                let image = CIImage(cvPixelBuffer: frame.capturedImage)
                let folder = self.folder
                let context = self.ciContext
                self.writer.async {
                    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                    let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
                    if let jpeg = context.jpegRepresentation(of: image, colorSpace: space, options: [quality: 0.85]) {
                        try? jpeg.write(to: folder.appendingPathComponent("hires/\(name).jpg"))
                        Task { @MainActor [weak self] in self?.bytesWritten += Int64(jpeg.count) }
                    }
                }
            }
        }
    }

    /// Резкость: дисперсия лапласиана по яркости (плоскость Y), с шагом 4 пикселя.
    static func sharpness(_ buffer: CVPixelBuffer) -> Float {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return 0 }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let step = 4
        var sum: Float = 0, sumSq: Float = 0, count: Float = 0
        var y = step
        while y < height - step {
            var x = step
            while x < width - step {
                let c = Float(pixels[y * row + x]) * 4
                let l = c - Float(pixels[y * row + x - step]) - Float(pixels[y * row + x + step])
                    - Float(pixels[(y - step) * row + x]) - Float(pixels[(y + step) * row + x])
                sum += l; sumSq += l * l; count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return sumSq / count - mean * mean
    }

    /// Ждёт, пока все кадры лягут на диск, сохраняет меш ARKit и manifest.json.
    func finish(control: [HouseScanManifest.Control]) async throws -> URL {
        recording = false
        let meshes = session?.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        let obj = Self.obj(from: meshes)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in writer.async { done.resume() } }
        if let obj { try obj.write(to: folder.appendingPathComponent("mesh/arkit.obj")) }
        let center = centerCount >= 5 ? centerSum / centerCount : nil
        let manifest = HouseScanManifest(
            createdAt: ISO8601DateFormatter().string(from: Date()), device: Self.deviceModel, lidar: Self.hasLiDAR,
            ios: UIDevice.current.systemVersion, image: .init(width: imageSize.width, height: imageSize.height),
            depth: depthSize.map { .init(width: $0.width, height: $0.height) },
            center: center.map { [$0.x, $0.y, $0.z] },
            coverage: .init(sectors: HouseCoverage.sectors, walls: coverage.wallShare, roof: coverage.roofShare, blocked: coverage.blocked.sorted()),
            control: control, frames: frames, stills: stills, parcel: parcel, rejectedBlurry: rejectedBlurry)
        var located = manifest
        located.language = AppLanguage.code
        if let location {
            located.world.location = .init(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                                           accuracy: location.horizontalAccuracy, altitude: location.verticalAccuracy >= 0 ? location.altitude : nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(located).write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }

    func discard() { try? FileManager.default.removeItem(at: folder) }

    // MARK: Помощники

    nonisolated static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static func flatten(_ m: simd_float4x4) -> [Float] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    static func angle(between a: simd_float4x4, and b: simd_float4x4) -> Float {
        let qa = simd_quatf(a), qb = simd_quatf(b)
        let dot = min(1, abs(simd_dot(qa.vector, qb.vector)))
        return 2 * acos(dot)
    }

    static func sector(of position: SIMD3<Float>, around center: SIMD3<Float>) -> Int {
        let angle = atan2(position.z - center.z, position.x - center.x) // −π…π
        let unit = (angle + .pi) / (2 * .pi)
        return min(HouseCoverage.sectors - 1, Int(unit * Float(HouseCoverage.sectors)))
    }

    /// Медиана глубины в центральном квадрате кадра (LiDAR), метры.
    nonisolated static func centerDepth(_ map: CVPixelBuffer?) -> Float? {
        guard let map, CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let row = CVPixelBufferGetBytesPerRow(map)
        var values: [Float] = []
        for y in stride(from: height * 2 / 5, to: height * 3 / 5, by: 4) {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
            for x in stride(from: width * 2 / 5, to: width * 3 / 5, by: 4) where line[x].isFinite && line[x] > 0 { values.append(line[x]) }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        return values[values.count / 2]
    }

    /// Глубина Float32 → Float16 (vImage; тип Float16 в Swift есть не на всех архитектурах симулятора).
    nonisolated static func float16(from map: CVPixelBuffer) -> Data? {
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        var out = Data(count: width * height * 2)
        let ok = out.withUnsafeMutableBytes { raw -> Bool in
            var src = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(map))
            var dst = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 2)
            return vImageConvert_PlanarFtoPlanar16F(&src, &dst, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        return ok ? out : nil
    }

    /// Карта уверенности (UInt8) построчно без отступов.
    nonisolated static func bytes(of map: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map), row = CVPixelBufferGetBytesPerRow(map)
        var out = Data(capacity: width * height)
        for y in 0..<height { out.append(base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self), count: width) }
        return out
    }

    /// Живой меш ARKit (LiDAR) одним OBJ в мировых координатах.
    static func obj(from anchors: [ARMeshAnchor]) -> Data? {
        guard !anchors.isEmpty else { return nil }
        var text = "# SmetaPro house scan: ARKit scene mesh, world coordinates, metres\n"
        var offset = 0
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let transform = anchor.transform
            for v in 0..<vertices.count {
                let pointer = vertices.buffer.contents().advanced(by: vertices.offset + vertices.stride * v)
                let local = pointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let world = transform * SIMD4<Float>(local.0, local.1, local.2, 1)
                text += String(format: "v %.4f %.4f %.4f\n", world.x, world.y, world.z)
            }
            let faces = geometry.faces
            guard faces.bytesPerIndex == 4, faces.indexCountPerPrimitive == 3 else { offset += vertices.count; continue }
            let indices = faces.buffer.contents().assumingMemoryBound(to: UInt32.self)
            for f in 0..<faces.count {
                let a = Int(indices[f * 3]) + offset + 1, b = Int(indices[f * 3 + 1]) + offset + 1, c = Int(indices[f * 3 + 2]) + offset + 1
                text += "f \(a) \(b) \(c)\n"
            }
            offset += vertices.count
        }
        return text.data(using: .utf8)
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

// MARK: - Упаковка и загрузка

/// Сканы на диске: папка на скан, внутри state.json (отправлен ли, id на сервере).
enum HouseScanStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HouseScans", isDirectory: true)
    }

    struct State: Codable {
        var serverID: String?
        var status: String = "local"
        var message: String?
        var frames: Int = 0
        var bytes: Int64 = 0
        var createdAt = Date()
    }

    static func state(of folder: URL) -> State? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
    static func save(_ state: State, in folder: URL) {
        try? JSONEncoder().encode(state).write(to: folder.appendingPathComponent("state.json"))
    }
    struct Pending: Identifiable {
        let folder: URL
        let state: State
        var id: URL { folder }
    }

    /// Удаляет кадры, глубину и архив отправленного скана, оставляя запись о нём.
    static func removeData(in folder: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent != "state.json" { try? FileManager.default.removeItem(at: item) }
    }

    /// При запуске: у уже отправленных сканов удаляем кадры и архив (освобождаем память iPhone).
    static func cleanupUploaded() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let state = state(of: folder), state.status != "local", state.status != "uploading" else { continue }
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if items.contains(where: { $0 != "state.json" }) { removeData(in: folder) }
        }
    }

    /// Сканы, которые ещё не дошли до сервера (новые сверху); отправленные смотрим в «Мои обмеры».
    static func pending() -> [Pending] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in state(of: folder).map { Pending(folder: folder, state: $0) } }
            .filter { $0.state.status == "local" || $0.state.status == "uploading" }
            .sorted { $0.state.createdAt > $1.state.createdAt }
    }
}

/// ZIP без сжатия (JPEG и так сжат): пишется потоком, файл за файлом.
enum StoredZip {
    static func make(from folder: URL, to zipURL: URL, skip: Set<String> = ["state.json", "scan.zip"]) throws {
        FileManager.default.createFile(atPath: zipURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: zipURL)
        defer { try? out.close() }
        var central = Data()
        var offset: UInt32 = 0
        var count: UInt16 = 0
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, !skip.contains(url.lastPathComponent) { files.append(url) }
        }
        files.sort { $0.path < $1.path }
        let prefix = folder.standardizedFileURL.path + "/"
        for file in files {
            let name = Data(file.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "").utf8)
            let data = try Data(contentsOf: file)
            let crc = CRC32.checksum(data)
            var local = Data()
            local.append(le32: 0x04034b50); local.append(le16: 20); local.append(le16: 0x0800); local.append(le16: 0)
            local.append(le16: 0); local.append(le16: 0x21)
            local.append(le32: crc); local.append(le32: UInt32(data.count)); local.append(le32: UInt32(data.count))
            local.append(le16: UInt16(name.count)); local.append(le16: 0); local.append(name)
            try out.write(contentsOf: local)
            try out.write(contentsOf: data)
            var entry = Data()
            entry.append(le32: 0x02014b50); entry.append(le16: 20); entry.append(le16: 20); entry.append(le16: 0x0800); entry.append(le16: 0)
            entry.append(le16: 0); entry.append(le16: 0x21)
            entry.append(le32: crc); entry.append(le32: UInt32(data.count)); entry.append(le32: UInt32(data.count))
            entry.append(le16: UInt16(name.count)); entry.append(le16: 0); entry.append(le16: 0); entry.append(le16: 0); entry.append(le16: 0)
            entry.append(le32: 0); entry.append(le32: offset); entry.append(name)
            central.append(entry)
            offset += UInt32(local.count + data.count)
            count += 1
        }
        var end = Data()
        end.append(le32: 0x06054b50); end.append(le16: 0); end.append(le16: 0); end.append(le16: count); end.append(le16: count)
        end.append(le32: UInt32(central.count)); end.append(le32: offset); end.append(le16: 0)
        try out.write(contentsOf: central)
        try out.write(contentsOf: end)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}

/// Загрузка scan.zip частями по 8 МБ с докачкой (сервер помнит полученные части).
struct HouseScanUploader {
    struct Remote: Decodable, Identifiable {
        let id: String
        let status: String
        let parts: Int
        let partBytes: Int
        let received: [Int]
        let message: String?
        var progress: Double?
        var createdAt: String?
        var queuePosition: Int?
        var hasModel = false
        /// Макет (house.json обработчика); разбирается мягко — новые поля сервера не ломают старое приложение.
        var result: HouseResult?

        private enum CodingKeys: String, CodingKey { case id, status, parts, partBytes, received, message, progress, createdAt, queuePosition, hasModel, result }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            status = try c.decode(String.self, forKey: .status)
            parts = (try? c.decode(Int.self, forKey: .parts)) ?? 0
            partBytes = (try? c.decode(Int.self, forKey: .partBytes)) ?? 8 * 1_048_576
            received = (try? c.decode([Int].self, forKey: .received)) ?? []
            message = try? c.decode(String.self, forKey: .message)
            progress = try? c.decode(Double.self, forKey: .progress)
            createdAt = try? c.decode(String.self, forKey: .createdAt)
            queuePosition = try? c.decode(Int.self, forKey: .queuePosition)
            hasModel = (try? c.decode(Bool.self, forKey: .hasModel)) ?? false
            result = try? c.decode(HouseResult.self, forKey: .result)
        }
    }

    private struct ScanList: Decodable { let scans: [Remote] }

    /// Сканы этого iPhone на сервере (новые сверху).
    func list() async throws -> [Remote] {
        var req = request("v1/ai/house/scans", method: "GET")
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClaudeError.api("Сервер не ответил. Проверьте интернет.") }
        return try JSONDecoder().decode(ScanList.self, from: data).scans
    }

    func status(_ id: String) async throws -> Remote { try await call(request("v1/ai/house/scans/\(id)", method: "GET")) }

    /// Удалить скан на сервере (пакет, макет, модель) и скачанную модель на iPhone.
    func delete(_ id: String) async throws {
        let (data, response) = try await URLSession.shared.data(for: request("v1/ai/house/scans/\(id)", method: "DELETE"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 404 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ClaudeError.api(message ?? "Не удалось удалить скан.")
        }
        try? FileManager.default.removeItem(at: HouseScanStore.root.appendingPathComponent("models/\(id).obj"))
    }

    /// 3D‑модель готового макета (OBJ) — скачивается один раз и хранится в телефоне.
    func model(_ id: String) async throws -> URL {
        let folder = HouseScanStore.root.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(id).obj")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        var req = request("v1/ai/house/scans/\(id)/model.obj", method: "GET")
        req.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 100 else { throw ClaudeError.api("3D‑модель ещё не готова.") }
        try data.write(to: file)
        return file
    }

    let base: URL

    init?() {
        guard let base = AIServerConfig.baseURL else { return nil }
        self.base = base
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        request.setValue(AppLanguage.code, forHTTPHeaderField: "X-App-Language")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        return request
    }

    private func call(_ request: URLRequest, body: Data? = nil) async throws -> Remote {
        let (data, response): (Data, URLResponse)
        if let body { (data, response) = try await URLSession.shared.upload(for: request, from: body) } else { (data, response) = try await URLSession.shared.data(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ClaudeError.api(message ?? "Сервер ответил с кодом \(status).")
        }
        return try JSONDecoder().decode(Remote.self, from: data)
    }

    /// Пакует папку скана (если ещё не упакована) и отправляет; `progress` — доля 0…1.
    func upload(folder: URL, frames: Int, lidar: Bool, progress: @escaping @MainActor (Double, String) -> Void) async throws -> Remote {
        let zip = folder.appendingPathComponent("scan.zip")
        var state = HouseScanStore.state(of: folder) ?? HouseScanStore.State(frames: frames)
        if !FileManager.default.fileExists(atPath: zip.path) {
            await progress(0, "Упаковываем скан…")
            try await Task.detached(priority: .userInitiated) { try StoredZip.make(from: folder, to: zip) }.value
        }
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.int64Value ?? 0
        state.bytes = size
        let sha = try await Task.detached(priority: .userInitiated) { try Self.sha256(of: zip) }.value

        var remote: Remote
        var existing: Remote?
        if let id = state.serverID { existing = try? await call(request("v1/ai/house/scans/\(id)", method: "GET")) }
        if let existing, existing.status == "uploading" {
            remote = existing
        } else if let existing {
            return existing // уже загружен раньше
        } else {
            var create = request("v1/ai/house/scans", method: "POST")
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = try JSONSerialization.data(withJSONObject: ["bytes": size, "sha256": sha, "manifest": ["frames": frames, "lidar": lidar, "device": HouseScanRecorder.deviceModel, "kind": "house"]])
            remote = try await call(create, body: body)
            state.serverID = remote.id
            state.status = "uploading"
            HouseScanStore.save(state, in: folder)
        }

        let handle = try FileHandle(forReadingFrom: zip)
        defer { try? handle.close() }
        var done = Set(remote.received)
        for part in 0..<remote.parts where !done.contains(part) {
            try handle.seek(toOffset: UInt64(part * remote.partBytes))
            let chunk = try handle.read(upToCount: remote.partBytes) ?? Data()
            var put = request("v1/ai/house/scans/\(remote.id)/parts/\(part)", method: "PUT")
            put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            var attempt = 0
            while true {
                do { _ = try await call(put, body: chunk); break } catch {
                    attempt += 1
                    if attempt >= 4 { throw error }
                    try await Task.sleep(for: .seconds(Double(attempt * attempt) * 2))
                }
            }
            done.insert(part)
            let sent = Double(min(Int64(done.count * remote.partBytes), size))
            await progress(sent / Double(max(size, 1)), "Загружаем \(Self.mb(Int64(sent))) из \(Self.mb(size))")
        }
        let final = try await call(request("v1/ai/house/scans/\(remote.id)/complete", method: "POST"), body: Data("{}".utf8))
        state.status = final.status
        state.message = final.message
        HouseScanStore.save(state, in: folder)
        // Пакет целиком на сервере (SHA‑256 сошёлся) — кадры, глубину и архив с iPhone удаляем:
        // это сотни мегабайт на каждый обмер. Остаётся только запись о скане (state.json).
        if final.status != "uploading" { HouseScanStore.removeData(in: folder) }
        return final
    }

    static func mb(_ bytes: Int64) -> String { String(format: "%.0f МБ", Double(bytes) / 1_048_576) }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}


/// Проверки перед обходом: место в памяти, нагрев, лидар.
enum HouseScanPrecheck {
    static func issues() -> [String] {
        var list: [String] = []
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < 1_500_000_000 {
            list.append("Мало места в памяти iPhone (\(free / 1_000_000_000) ГБ) — для обхода нужно около 1,5 ГБ.")
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: list.append("iPhone перегрет — дайте ему остыть несколько минут, иначе кадры будут реже.")
        default: break
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            list.append("Включён режим энергосбережения — камера может работать медленнее. Лучше выключить на время обхода.")
        }
        return list
    }
}
