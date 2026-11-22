import SwiftUI
import ARKit
import RealityKit
import AVFoundation
import Combine
import simd

enum ARMode: String, CaseIterable, Identifiable {
    case distance = "Длина", area = "Площадь", preview = "Макет"
    var id: String { rawValue }
}
enum ARPreviewKind: String, CaseIterable, Identifiable {
    case slab = "Плита", walls = "Стены", roof = "Крыша", window = "Окно", door = "Дверь", septic = "Септик"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .slab: return "square.3.layers.3d"
        case .walls: return "square.split.2x2"
        case .roof: return "house"
        case .window: return "macwindow"
        case .door: return "door.left.hand.open"
        case .septic: return "cylinder"
        }
    }
}
enum ARBlueprintPreset: CaseIterable, Identifiable {
    case slab, walls, roof, window, door, septic
    var id: String { title }
    var title: String { switch self { case .slab: return "Плита 8 × 10 м"; case .walls: return "Коробка 8 × 10 м"; case .roof: return "Кровля 8 × 10 м"; case .window: return "Окно 1,5 × 1,4 м"; case .door: return "Дверь 0,9 × 2,1 м"; case .septic: return "Септик 2 × 2 м" } }
    var kind: ARPreviewKind { switch self { case .slab: return .slab; case .walls: return .walls; case .roof: return .roof; case .window: return .window; case .door: return .door; case .septic: return .septic } }
    var dimensions: (String, String, String) { switch self { case .slab: return ("10", "8", "0,25"); case .walls: return ("10", "8", "3"); case .roof: return ("10", "8", "2,4"); case .window: return ("1,5", "0,18", "1,4"); case .door: return ("0,9", "0,08", "2,1"); case .septic: return ("2", "2", "2") } }
}
@MainActor final class ARMeasureModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var mode: ARMode = .distance
    @Published var previewKind: ARPreviewKind = .slab
    @Published var status = "Медленно наведите камеру на освещённую поверхность"
    @Published var points: [SIMD3<Float>] = []
    @Published var ready = false
    @Published var permission = false
    @Published var denied = false
    @Published var lengthText = "3"
    @Published var widthText = "2"
    @Published var heightText = "0,2"
    var arView: ARView?
    private var readinessTimer: AnyCancellable?
    private var anchors: [AnchorEntity] = []
    private var previewAnchor: AnchorEntity?
    private var trackingNormal = false
    private var floorY: Float?
    var supported: Bool { ARWorldTrackingConfiguration.isSupported }
    var distance: Double {
        guard points.count == 2 else { return 0 }
        return MeasurementGeometry.distance(points[0], points[1])
    }
    var area: Double { MeasurementGeometry.floorArea(points) }
    /// Opens the camera immediately if access was granted earlier (no extra tap on every launch).
    func checkExistingAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = true
        case .denied, .restricted: denied = true
        default: break
        }
    }
    func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = true
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { granted in Task { @MainActor in self.permission = granted; self.denied = !granted } }
        default: denied = true
        }
    }
    func start(_ view: ARView) {
        arView = view
        view.session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        // Check the centre point ~8 times per second instead of on every camera frame (60 fps):
        // less CPU and heat, the reticle still feels instant.
        readinessTimer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let hit = self.centerHit() != nil
                if self.ready != hit { self.ready = hit }
            }
        }
    }
    func stop() { readinessTimer?.cancel(); readinessTimer = nil; arView?.session.pause() }
    func restart() { reset(); if let arView { start(arView) } }
    func apply(_ preset: ARBlueprintPreset) { previewKind = preset.kind; let values = preset.dimensions; lengthText = values.0; widthText = values.1; heightText = values.2; status = "Выбран макет: \(preset.title). Наведите центр на поверхность и разместите его." }
    func snapshot(_ completion: @escaping (UIImage?) -> Void) { arView?.snapshot(saveToHDR: false) { image in Task { @MainActor in completion(image) } } }
    func centerHit() -> SIMD3<Float>? {
        guard trackingNormal, let view = arView else { return nil }
        let alignment: ARRaycastQuery.TargetAlignment = mode == .distance ? .any : .horizontal
        let results = view.raycast(from: CGPoint(x: view.bounds.midX, y: view.bounds.midY), allowing: .existingPlaneGeometry, alignment: alignment)
        guard let result = results.first else { return nil }
        let position = result.worldTransform.columns.3
        let hit = SIMD3(position.x, position.y, position.z)
        if mode == .area, let y = floorY, abs(hit.y - y) > 0.04 { return nil }
        return hit
    }
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let normal: Bool
        let message: String
        switch camera.trackingState {
        case .normal: normal = true; message = "Найдите поверхность и наведите центр на точку"
        case .limited(.excessiveMotion): normal = false; message = "Двигайте iPhone медленнее"
        case .limited(.insufficientFeatures): normal = false; message = "Мало ориентиров. Выберите освещённую фактурную поверхность"
        default: normal = false; message = "Осматривайте поверхность: AR уточняет положение"
        }
        Task { @MainActor in self.trackingNormal = normal; self.status = message; if !normal { self.ready = false } }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.ready = false; self.trackingNormal = false; self.status = "AR приостановлен. После возврата начните новый замер." }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) { Task { @MainActor in self.restart() } }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = "Камера недоступна: \(message). Нажмите «Сбросить»."; self.ready = false; self.trackingNormal = false }
    }
    func reset() {
        anchors.forEach { $0.removeFromParent() }; anchors.removeAll(); previewAnchor?.removeFromParent(); previewAnchor = nil; points.removeAll(); floorY = nil
    }
    func undo() {
        guard !points.isEmpty else { return }
        let retained = Array(points.dropLast()); reset(); points = retained; floorY = points.first?.y; redraw()
    }
    func addPoint() {
        guard var hit = centerHit() else { status = "Сначала найдите поверхность. Центр должен стать оранжевым."; return }
        if mode == .preview { placePreview(at: hit); return }
        if mode == .distance && points.count == 2 { reset() }
        guard points.count < 12 else { status = "До 12 точек в одном контуре."; return }
        if mode == .area {
            if floorY == nil { floorY = hit.y }
            hit.y = floorY ?? hit.y
        }
        if points.contains(where: { simd_distance($0, hit) < 0.02 }) { status = "Точки слишком близко: выберите другую точку."; return }
        if mode == .area && wouldIntersect(hit) { status = "Контур пересекается. Добавляйте углы последовательно по периметру."; return }
        points.append(hit); redraw()
        Haptics.tap()
        status = mode == .distance ? (points.count == 1 ? "Отметьте вторую точку" : "Расстояние измерено. Новый замер начнётся с первой точки") : "Точек: \(points.count). Обходите углы пола по порядку"
    }
    func wouldIntersect(_ point: SIMD3<Float>) -> Bool { MeasurementGeometry.selfIntersects(points + [point]) }
    func redraw() {
        anchors.forEach { $0.removeFromParent() }; anchors.removeAll()
        guard let view = arView else { return }
        let material = SimpleMaterial(color: .systemOrange, isMetallic: false)
        for (index, point) in points.enumerated() {
            let anchor = AnchorEntity(world: point)
            anchor.addChild(ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [material]))
            view.scene.addAnchor(anchor); anchors.append(anchor)
            if index > 0 { line(points[index-1], point) }
        }
        if mode == .area && points.count > 2 { line(points.last!, points[0]) }
    }
    func line(_ start: SIMD3<Float>, _ end: SIMD3<Float>) {
        guard let view = arView else { return }
        let delta = end - start, length = simd_length(delta)
        guard length > 0 else { return }
        let anchor = AnchorEntity(world: (start + end) / 2)
        let line = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.007, length, 0.007)), materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
        line.orientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(delta))
        anchor.addChild(line); view.scene.addAnchor(anchor); anchors.append(anchor)
    }
    func placePreview(at hit: SIMD3<Float>) {
        guard let length = CalculationEngine.parse(lengthText), let width = CalculationEngine.parse(widthText), let height = CalculationEngine.parse(heightText), (0.05...30).contains(length), (0.05...30).contains(width), (0.02...10).contains(height), let view = arView else {
            status = "Размеры: длина и ширина 0,05–30 м, высота 0,02–10 м."; return
        }
        previewAnchor?.removeFromParent()
        let previewLength = Float(length), previewWidth = Float(width), previewHeight = Float(height)
        let anchor = AnchorEntity(world: hit)

        switch previewKind {
        case .slab:
            break
        case .walls:
            addWalls(to: anchor, width: previewWidth, length: previewLength, height: previewHeight)
        case .roof:
            addRoof(to: anchor, width: previewWidth, length: previewLength, height: previewHeight)
        case .window:
            addWindow(to: anchor, width: previewWidth, height: previewHeight)
        case .door:
            addDoor(to: anchor, width: previewWidth, height: previewHeight)
        case .septic:
            addSeptic(to: anchor, diameter: previewWidth, height: previewHeight)
        }
        if previewKind != .slab {
            finishPreview(anchor, description: "\(previewKind.rawValue): \(widthText) × \(lengthText) × \(heightText) м. Это визуальный макет, размеры перепроверьте на объекте.")
            return
        }

        // Construction preview: a gravel base, concrete slab, rebar grid and a high-contrast perimeter.
        // The materials are deliberately matte so the object stays legible under changing outdoor light.
        let base = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(previewWidth + 0.12, 0.025, previewLength + 0.12)),
            materials: [material(color: UIColor(red: 0.26, green: 0.28, blue: 0.26, alpha: 1), roughness: 1)]
        )
        base.position.y = 0.0125
        anchor.addChild(base)

        let slab = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(previewWidth, previewHeight, previewLength)),
            materials: [material(color: UIColor(red: 0.52, green: 0.54, blue: 0.52, alpha: 1), roughness: 0.92)]
        )
        slab.position.y = previewHeight / 2 + 0.025
        anchor.addChild(slab)

        let edgeMaterial = material(color: .systemOrange, roughness: 0.58)
        let topY = previewHeight + 0.04
        let edgeThickness: Float = 0.018
        for (position, size) in [
            (SIMD3<Float>(0, topY, -previewLength / 2), SIMD3<Float>(previewWidth, edgeThickness, edgeThickness)),
            (SIMD3<Float>(0, topY, previewLength / 2), SIMD3<Float>(previewWidth, edgeThickness, edgeThickness)),
            (SIMD3<Float>(-previewWidth / 2, topY, 0), SIMD3<Float>(edgeThickness, edgeThickness, previewLength)),
            (SIMD3<Float>(previewWidth / 2, topY, 0), SIMD3<Float>(edgeThickness, edgeThickness, previewLength))
        ] {
            let edge = ModelEntity(mesh: .generateBox(size: size), materials: [edgeMaterial])
            edge.position = position
            anchor.addChild(edge)
        }

        let rebarMaterial = material(color: UIColor(red: 0.16, green: 0.2, blue: 0.19, alpha: 0.88), roughness: 0.52)
        let spacing: Float = max(0.18, min(0.35, max(previewWidth, previewLength) / 12))
        let barLength = max(Float(0), previewLength - 0.08)
        let barWidth = max(Float(0), previewWidth - 0.08)
        stride(from: -previewWidth / 2 + spacing, through: previewWidth / 2 - spacing, by: spacing).forEach { x in
            let bar = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.009, 0.009, barLength)), materials: [rebarMaterial])
            bar.position = [x, topY + 0.025, 0]
            anchor.addChild(bar)
        }
        stride(from: -previewLength / 2 + spacing, through: previewLength / 2 - spacing, by: spacing).forEach { z in
            let bar = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(barWidth, 0.009, 0.009)), materials: [rebarMaterial])
            bar.position = [0, topY + 0.04, z]
            anchor.addChild(bar)
        }

        view.scene.addAnchor(anchor)
        previewAnchor = anchor
        Haptics.success()
        status = "Плита \(widthText) × \(lengthText) × \(heightText) м. Оранжевая кромка и сетка — визуальный макет, не схема армирования."
    }

    private func finishPreview(_ anchor: AnchorEntity, description: String) {
        arView?.scene.addAnchor(anchor)
        previewAnchor = anchor
        status = description
    }

    private func addWalls(to anchor: AnchorEntity, width: Float, length: Float, height: Float) {
        let wall: Float = min(0.25, max(0.08, min(width, length) / 20))
        let concrete = material(color: UIColor(red: 0.62, green: 0.61, blue: 0.57, alpha: 0.82), roughness: 0.9)
        for (position, size) in [
            (SIMD3<Float>(0, height / 2, -length / 2 + wall / 2), SIMD3<Float>(width, height, wall)),
            (SIMD3<Float>(0, height / 2, length / 2 - wall / 2), SIMD3<Float>(width, height, wall)),
            (SIMD3<Float>(-width / 2 + wall / 2, height / 2, 0), SIMD3<Float>(wall, height, length)),
            (SIMD3<Float>(width / 2 - wall / 2, height / 2, 0), SIMD3<Float>(wall, height, length))
        ] {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [concrete])
            entity.position = position
            anchor.addChild(entity)
        }
        // Shallow block joints sit clearly in front of the wall plane, avoiding coplanar flicker.
        let joint = material(color: UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1), roughness: 1)
        let frontZ = -length / 2 - 0.012
        let row: Float = 0.22
        stride(from: row, through: height - row / 2, by: row).forEach { y in
            let seam = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(max(0.08, width - 0.08), 0.012, 0.016)), materials: [joint])
            seam.position = [0, y, frontZ]
            anchor.addChild(seam)
        }
        stride(from: -width / 2 + 0.3, through: width / 2 - 0.15, by: 0.6).forEach { x in
            let seam = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.012, height - 0.08, 0.016)), materials: [joint])
            seam.position = [x, height / 2, frontZ]
            anchor.addChild(seam)
        }
    }

    private func addRoof(to anchor: AnchorEntity, width: Float, length: Float, height: Float) {
        let rise = max(0.25, height)
        let halfRun = width / 2
        let slopeLength = sqrt(halfRun * halfRun + rise * rise)
        let roof = material(color: UIColor(red: 0.18, green: 0.22, blue: 0.24, alpha: 0.9), roughness: 0.72)
        let angle = atan2(rise, halfRun)
        for side: Float in [-1, 1] {
            let panel = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(slopeLength, 0.07, length)), materials: [roof])
            panel.position = SIMD3<Float>(side * halfRun / 2, rise / 2, 0)
            panel.orientation = simd_quatf(angle: -side * angle, axis: SIMD3<Float>(0, 0, 1))
            let seamMaterial = material(color: UIColor(red: 0.09, green: 0.12, blue: 0.14, alpha: 1), roughness: 0.62)
            stride(from: -slopeLength / 2 + 0.22, through: slopeLength / 2 - 0.15, by: 0.32).forEach { x in
                let seam = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.024, 0.024, max(0.1, length - 0.05))), materials: [seamMaterial])
                seam.position = [x, 0.05, 0]
                panel.addChild(seam)
            }
            anchor.addChild(panel)
        }
    }

    private func addWindow(to anchor: AnchorEntity, width: Float, height: Float) {
        let frame = material(color: UIColor(red: 0.1, green: 0.12, blue: 0.13, alpha: 0.95), roughness: 0.45)
        let glass = material(color: UIColor(red: 0.22, green: 0.53, blue: 0.65, alpha: 1), roughness: 0.16, metallic: 0.12)
        let depth: Float = 0.06, edge: Float = min(0.1, max(0.035, min(width, height) / 12))
        let pane = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(width, height, depth / 2)), materials: [glass])
        pane.position.y = height / 2
        anchor.addChild(pane)
        for (position, size) in [
            (SIMD3<Float>(0, height, 0), SIMD3<Float>(width + edge, edge, depth)),
            (SIMD3<Float>(0, 0, 0), SIMD3<Float>(width + edge, edge, depth)),
            (SIMD3<Float>(-width / 2, height / 2, 0), SIMD3<Float>(edge, height, depth)),
            (SIMD3<Float>(width / 2, height / 2, 0), SIMD3<Float>(edge, height, depth))
        ] {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [frame]); entity.position = position; anchor.addChild(entity)
        }
    }

    private func addDoor(to anchor: AnchorEntity, width: Float, height: Float) {
        let frame = material(color: UIColor(red: 0.11, green: 0.09, blue: 0.07, alpha: 0.95), roughness: 0.68)
        let wood = material(color: UIColor(red: 0.49, green: 0.27, blue: 0.13, alpha: 0.92), roughness: 0.78)
        let depth: Float = 0.08, edge: Float = min(0.1, max(0.04, min(width, height) / 14))
        let panel = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(width, height, depth)), materials: [wood]); panel.position.y = height / 2; anchor.addChild(panel)
        let panelDetail = material(color: UIColor(red: 0.29, green: 0.15, blue: 0.07, alpha: 1), roughness: 0.84)
        for y in [height * 0.26, height * 0.5, height * 0.74] {
            let rail = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(max(0.08, width - 0.15), 0.025, 0.02)), materials: [panelDetail])
            rail.position = [0, y, depth / 2 + 0.014]
            anchor.addChild(rail)
        }
        for (position, size) in [
            (SIMD3<Float>(-width / 2, height / 2, 0), SIMD3<Float>(edge, height + edge, depth * 1.3)),
            (SIMD3<Float>(width / 2, height / 2, 0), SIMD3<Float>(edge, height + edge, depth * 1.3)),
            (SIMD3<Float>(0, height, 0), SIMD3<Float>(width + edge, edge, depth * 1.3))
        ] {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [frame]); entity.position = position; anchor.addChild(entity)
        }
    }

    private func addSeptic(to anchor: AnchorEntity, diameter: Float, height: Float) {
        let side = max(0.16, diameter)
        let body = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(side, height, side)), materials: [material(color: UIColor(red: 0.28, green: 0.5, blue: 0.42, alpha: 0.9), roughness: 0.76)])
        body.position.y = height / 2
        anchor.addChild(body)
        let bandMaterial = material(color: UIColor(red: 0.16, green: 0.31, blue: 0.25, alpha: 1), roughness: 0.86)
        for y in [height * 0.22, height * 0.5, height * 0.78] {
            let band = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(side + 0.012, 0.035, side + 0.012)), materials: [bandMaterial])
            band.position = [0, y, 0]
            anchor.addChild(band)
        }
        let hatch = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(side * 0.45, 0.04, side * 0.45)), materials: [material(color: .systemOrange, roughness: 0.55)])
        hatch.position.y = height + 0.02
        anchor.addChild(hatch)
    }

    private func material(color: UIColor, roughness: Float, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = color
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
        return material
    }
}
struct ARCameraView: UIViewRepresentable {
    let model: ARMeasureModel
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        model.start(view); return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) { uiView.session.pause() }
}
struct ARMeasureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ARMeasureModel()
    @State private var showTransfer = false
    @State private var snapshot: UIImage?
    @State private var showShare = false
    @State private var showLengthTransfer = false
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.supported && model.permission {
                ARCameraView(model: model).ignoresSafeArea()
                Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(model.ready ? Theme.orange : .white).shadow(radius: 3).accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                HStack(spacing: 10) { Text("AR-СТУДИЯ").font(.headline).tracking(2); Spacer(); if model.supported && model.permission { TorchButton() }; Button { dismiss() } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Закрыть AR") }.padding(.horizontal, 20)
                if model.permission && model.supported {
                    Picker("Режим AR", selection: $model.mode) { ForEach(ARMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20).onChange(of: model.mode) { _, _ in model.reset() }
                    Text(model.status).font(.footnote).multilineTextAlignment(.center).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
                    Spacer()
                    controls
                } else {
                    Spacer()
                    VStack(spacing: 22) {
                        Image(systemName: "viewfinder").font(.system(size: 56)).foregroundStyle(Theme.orange)
                        Text(model.supported ? "Пространство\nв цифрах." : "AR недоступен на этом устройстве").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(model.supported ? "Измеряйте расстояния и площадь пола. Размещайте на площадке плиту, стены, крышу, окна, двери и септик с заданными размерами." : "Для замеров нужен совместимый iPhone с камерой. Обычные калькуляторы работают без AR.").foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        if model.denied { Text("Разрешите камеру в настройках iPhone, затем откройте AR снова.").font(.footnote); Link("Открыть настройки", destination: URL(string: UIApplication.openSettingsURLString)!) }
                        else if model.supported { PrimaryButton(title: "Включить камеру", icon: "camera") { model.requestAccess() } }
                        Text("Камера не записывается. AR-замеры приблизительны; перед закупкой перепроверьте размеры рулеткой.").font(.footnote).foregroundStyle(Theme.muted)
                    }.padding(28)
                    Spacer()
                }
            }.padding(.top, 12)
        }.onDisappear { model.stop() }
            .onAppear { model.checkExistingAccess() }
            .helperScreen("AR‑замер")
            .confirmationDialog("Использовать площадь в расчёте", isPresented: $showTransfer, titleVisibility: .visible) {
                ForEach([CalculationKind.tiles, .screed, .paint, .plaster, .drywall, .insulation]) { kind in Button(kind.title) { transfer(kind, key: "area", value: model.area) } }
            }
            .confirmationDialog("Использовать длину в расчёте", isPresented: $showLengthTransfer, titleVisibility: .visible) {
                Button("Плита — длина") { transfer(.slab, key: "length", value: model.distance) }
                Button("Плита — ширина") { transfer(.slab, key: "width", value: model.distance) }
                Button("Ленточный фундамент — длина лент") { transfer(.strip, key: "length", value: model.distance) }
                Button("Кладка — длина стен") { transfer(.masonry, key: "length", value: model.distance) }
                Button("Забор — длина") { transfer(.fence, key: "length", value: model.distance) }
            }
            .sheet(isPresented: $showShare) { if let snapshot { ActivityShareSheet(items: [BrandGraphics.watermarked(snapshot)]) } }
    }
    var controls: some View {
        VStack(spacing: 14) {
            if model.mode == .preview {
                Picker("Элемент", selection: $model.previewKind) {
                    ForEach(ARPreviewKind.allCases) { kind in Label(kind.rawValue, systemImage: kind.icon).tag(kind) }
                }.pickerStyle(.menu).tint(Theme.orange).frame(maxWidth: .infinity, alignment: .leading)
                Menu { ForEach(ARBlueprintPreset.allCases) { preset in Button(preset.title) { model.apply(preset) } } } label: { Label("Готовый макет", systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }
                HStack { dimension("Длина, м", $model.lengthText); dimension("Ширина, м", $model.widthText); dimension("Высота, м", $model.heightText) }
            } else {
                Text(model.mode == .distance ? (model.points.count == 2 ? "≈ \(CalculationEngine.format(model.distance)) м" : "Отметьте две точки") : (model.points.count >= 3 ? "≈ \(CalculationEngine.format(model.area)) м²" : "Отметьте углы пола"))
                    .font(.title.bold()).monospacedDigit().contentTransition(.numericText())
                Text(model.mode == .area ? "Одна горизонтальная поверхность. Углы по периметру." : "Наведите центр на поверхность и добавьте точку.").font(.caption).multilineTextAlignment(.center)
            }
            PrimaryButton(title: model.mode == .preview ? "Разместить: \(model.previewKind.rawValue)" : "Добавить точку", icon: model.mode == .preview ? model.previewKind.icon : "plus") { model.addPoint() }.disabled(!model.ready).opacity(model.ready ? 1 : 0.5)
            if model.mode == .preview { Button { model.snapshot { image in snapshot = image; showShare = image != nil } } label: { Label("Сохранить снимок AR", systemImage: "camera.viewfinder").frame(maxWidth: .infinity).padding(13).background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain).disabled(model.arView == nil) }
            HStack {
                Button("Отменить точку") { model.undo() }.disabled(model.points.isEmpty)
                Spacer(); Button("Сбросить") { model.restart() }
            }.font(.footnote)
            if model.mode == .area && model.points.count >= 3 && model.area > 0 {
                HStack {
                    Button("В калькулятор") { showTransfer = true }
                    Spacer()
                    Button { savePlan() } label: { Label("Сохранить как план", systemImage: "square.split.bottomrightquarter") }
                }
                .font(.subheadline.weight(.semibold))
            }
            if model.mode == .distance && model.points.count == 2 {
                Button("Использовать длину в калькуляторе") { showLengthTransfer = true }.font(.subheadline.weight(.semibold))
            }
            Text("Приблизительный замер. Не используйте для разбивки осей и контроля несущих конструкций.").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26)).padding(12)
    }
    func dimension(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption); TextField("м", text: binding).keyboardType(.decimalPad).padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10)) }
    }
    func savePlan() {
        guard let plan = FloorPlanBuilder.fromContour(model.points, name: "Помещение \(store.floorPlans.count + 1)") else { return }
        store.savePlan(plan)
        store.track("contour_plan_saved")
        Haptics.success()
        dismiss()
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(500)); store.planToOpen = plan.id }
    }
    func transfer(_ kind: CalculationKind, key: String, value: Double) {
        let transfer = ARTransfer(kind: kind, key: key, value: value)
        store.track("ar_transfer_\(kind.rawValue)")
        dismiss()
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(500)); store.arTransfer = transfer }
    }
}
