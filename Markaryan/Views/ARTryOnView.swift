import SwiftUI
import ARKit
import RealityKit
import PhotosUI
import Metal

// MARK: - «Примерка ремонта в AR»: новая отделка вживую на ваших стенах и полу

/// Материал для примерки: картинка‑текстура и размер одного элемента (плитка, доска) в метрах.
struct TryOnMaterial: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var image: UIImage?
    var color: UIColor?
    var tileMeters: Double
    var kind: Kind
    enum Kind: String { case tile, wood, paint }

    static func == (a: TryOnMaterial, b: TryOnMaterial) -> Bool { a.id == b.id }

    /// Плитка: цвет, шов, лёгкий разброс тона — нарисовано в телефоне.
    static func tile(_ title: String, base: UIColor, grout: UIColor, sizeMM: Double, vein: Bool = false) -> TryOnMaterial {
        let px: CGFloat = 512
        let image = UIGraphicsImageRenderer(size: CGSize(width: px, height: px)).image { ctx in
            grout.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
            base.setFill(); ctx.fill(CGRect(x: 4, y: 4, width: px - 8, height: px - 8))
            if vein {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 30, y: px * 0.2))
                path.addCurve(to: CGPoint(x: px - 30, y: px * 0.75), controlPoint1: CGPoint(x: px * 0.4, y: px * 0.1), controlPoint2: CGPoint(x: px * 0.55, y: px * 0.9))
                grout.withAlphaComponent(0.35).setStroke(); path.lineWidth = 3; path.stroke()
            }
        }
        return TryOnMaterial(title: title, image: image, tileMeters: sizeMM / 1000, kind: .tile)
    }

    /// Ламинат: доски с разным тоном и стыками.
    static func wood(_ title: String, base: UIColor) -> TryOnMaterial {
        let w: CGFloat = 512, h: CGFloat = 512, plank = h / 4
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
            for row in 0..<4 {
                let shift = CGFloat([0, 0.5, 0.25, 0.75][row]) * w
                for k in -1..<2 {
                    let tone = UIColor(hue: hue, saturation: sat, brightness: max(0, min(1, bri + CGFloat((row * 3 + k + 7) % 5 - 2) * 0.035)), alpha: 1)
                    tone.setFill()
                    let r = CGRect(x: shift + CGFloat(k) * w, y: CGFloat(row) * plank, width: w - 3, height: plank - 3)
                    ctx.fill(r)
                }
                UIColor.black.withAlphaComponent(0.25).setFill()
                ctx.fill(CGRect(x: 0, y: CGFloat(row + 1) * plank - 3, width: w, height: 3))
            }
        }
        return TryOnMaterial(title: title, image: image, tileMeters: 1.2, kind: .wood)
    }

    static func paint(_ title: String, _ color: UIColor) -> TryOnMaterial { TryOnMaterial(title: title, color: color, tileMeters: 1, kind: .paint) }

    static let presets: [TryOnMaterial] = [
        .tile("Светлый мрамор 60×60", base: UIColor(white: 0.93, alpha: 1), grout: UIColor(white: 0.78, alpha: 1), sizeMM: 600, vein: true),
        .tile("Бетон 60×120", base: UIColor(white: 0.62, alpha: 1), grout: UIColor(white: 0.5, alpha: 1), sizeMM: 600),
        .tile("Графит 60×60", base: UIColor(white: 0.25, alpha: 1), grout: UIColor(white: 0.18, alpha: 1), sizeMM: 600),
        .tile("Белая 30×30", base: .white, grout: UIColor(white: 0.85, alpha: 1), sizeMM: 300),
        .wood("Дуб светлый", base: UIColor(red: 0.80, green: 0.68, blue: 0.52, alpha: 1)),
        .wood("Орех", base: UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)),
        .paint("Тёплый белый", UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)),
        .paint("Шалфей", UIColor(red: 0.64, green: 0.70, blue: 0.62, alpha: 1)),
        .paint("Терракота", UIColor(red: 0.76, green: 0.47, blue: 0.36, alpha: 1)),
        .paint("Графит", UIColor(red: 0.27, green: 0.29, blue: 0.30, alpha: 1)),
    ]
}

enum TryOnTarget: String, CaseIterable, Identifiable {
    case floor, walls
    var id: String { rawValue }
    var title: String { self == .floor ? "Пол" : "Стены" }
}

/// Плоскости ARKit → «наклейки» с материалом; площадь пола и стен — для подсчёта, сколько купить.
final class TryOnCoordinator: NSObject, ARSessionDelegate, ObservableObject {
    weak var view: ARView?
    @Published var floorArea: Double = 0
    @Published var wallArea: Double = 0
    @Published var surfaces = 0
    private var entities: [UUID: (anchor: AnchorEntity, model: ModelEntity, target: TryOnTarget)] = [:]
    var materials: [TryOnTarget: TryOnMaterial] = [:]

    private func target(_ plane: ARPlaneAnchor, cameraY: Float) -> TryOnTarget? {
        if plane.alignment == .vertical { return .walls }
        switch plane.classification {
        case .floor: return .floor
        case .ceiling, .table, .seat: return nil
        default: return plane.transform.columns.3.y < cameraY - 0.4 ? .floor : nil
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { update(anchors, session) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { update(anchors, session) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for a in anchors { if let e = entities.removeValue(forKey: a.identifier) { e.anchor.removeFromParent() } }
        recount()
    }

    private func update(_ anchors: [ARAnchor], _ session: ARSession) {
        guard let view else { return }
        let cameraY = session.currentFrame?.camera.transform.columns.3.y ?? 1.4
        for case let plane as ARPlaneAnchor in anchors {
            guard let target = target(plane, cameraY: cameraY) else { continue }
            let w = plane.planeExtent.width, d = plane.planeExtent.height
            guard w > 0.2, d > 0.2 else { continue }
            if entities[plane.identifier] == nil {
                let anchor = AnchorEntity(anchor: plane)
                let model = ModelEntity(mesh: .generatePlane(width: w, depth: d))
                anchor.addChild(model)
                view.scene.addAnchor(anchor)
                entities[plane.identifier] = (anchor, model, target)
            }
            guard let entry = entities[plane.identifier] else { continue }
            entry.model.model?.mesh = .generatePlane(width: w, depth: d)
            entry.model.position = plane.center
            entry.model.orientation = simd_quatf(angle: plane.planeExtent.rotationOnYAxis, axis: [0, 1, 0])
            apply(to: entry.model, target: target, width: w, depth: d)
        }
        recount()
    }

    func refreshMaterials() {
        for (_, e) in entities {
            let bounds = e.model.model?.mesh.bounds.extents ?? [1, 0, 1]
            apply(to: e.model, target: e.target, width: bounds.x, depth: bounds.z)
        }
    }

    private func apply(to model: ModelEntity, target: TryOnTarget, width: Float, depth: Float) {
        guard let m = materials[target] else { model.isEnabled = false; return }
        model.isEnabled = true
        var pbr = PhysicallyBasedMaterial()
        pbr.roughness = .init(floatLiteral: m.kind == .paint ? 0.92 : 0.45)
        if let image = m.image?.cgImage, let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = .repeat; sampler.tAddressMode = .repeat
            sampler.minFilter = .linear; sampler.magFilter = .linear; sampler.mipFilter = .linear
            pbr.baseColor = .init(texture: .init(texture, sampler: .init(sampler)))
            let tile = Float(max(0.05, m.tileMeters))
            pbr.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2(width / tile, depth / tile), rotation: 0)
        } else if let color = m.color {
            pbr.baseColor = .init(tint: color)
        }
        model.model?.materials = [pbr]
    }

    private func recount() {
        var floor = 0.0, walls = 0.0
        for (_, e) in entities {
            let ext = e.model.model?.mesh.bounds.extents ?? .zero
            let area = Double(ext.x * ext.z)
            if e.target == .floor { floor += area } else { walls += area }
        }
        DispatchQueue.main.async { self.floorArea = floor; self.wallArea = walls; self.surfaces = self.entities.count }
    }
}

struct TryOnARView: UIViewRepresentable {
    let coordinator: TryOnCoordinator
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            view.environment.sceneUnderstanding.options.insert(.occlusion)   // мебель закрывает отделку, как в жизни
        }
        coordinator.view = view
        view.session.delegate = coordinator
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {}
    static func dismantleUIView(_ view: ARView, coordinator: ()) { view.session.pause() }
}

struct ARTryOnView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ar = TryOnCoordinator()
    @State private var target: TryOnTarget = .floor
    @State private var chosen: [TryOnTarget: TryOnMaterial] = [:]
    @State private var custom: [TryOnMaterial] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var shot: UIImage?
    @State private var describing = false
    @State private var prompt = ""
    @State private var generating = false
    @State private var snap: Snap?
    @State private var error: String?

    private var all: [TryOnMaterial] { custom + TryOnMaterial.presets.filter { target == .floor ? $0.kind != .paint : true } }
    private var area: Double { target == .floor ? ar.floorArea : ar.wallArea }

    var body: some View {
        ZStack(alignment: .bottom) {
            TryOnARView(coordinator: ar).ignoresSafeArea()
            VStack {
                topBar
                Spacer()
                panel
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { addPhoto(image) } } }
        .onChange(of: shot) { _, image in if let image { addPhoto(image); shot = nil } }
        .fullScreenCover(isPresented: $showCamera) { CameraCaptureView(image: $shot).ignoresSafeArea() }
        .sheet(item: $snap) { snap in
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(uiImage: snap.image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                        ShareLink(item: Image(uiImage: snap.image), preview: SharePreview("Примерка ремонта", image: Image(uiImage: snap.image))) { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }
                        SavePictureToObjectButton(image: snap.image, title: "Примерка: \(chosen.values.map(\.title).joined(separator: ", "))")
                    }
                    .padding(20)
                }
                .buttonStyle(PremiumPressStyle())
                .navigationTitle("Снимок").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { self.snap = nil } } }
            }
        }
        .alert("Опишите материал", isPresented: $describing) {
            TextField("Например: светлый мрамор с золотыми прожилками", text: $prompt)
            Button("Нарисовать") { Task { await generate() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("ИИ нарисует бесшовную текстуру, и она ляжет на \(target == .floor ? "пол" : "стены").") }
    }

    private struct Snap: Identifiable { let id = UUID(); let image: UIImage }

    private var topBar: some View {
        HStack {
            Text("ПРИМЕРКА РЕМОНТА").font(.headline).tracking(2).foregroundStyle(.white)
            Spacer()
            Button { ar.view?.snapshot(saveToHDR: false) { image in if let image { snap = Snap(image: image); Haptics.success() } } } label: { Image(systemName: "camera.shutter.button").padding(12).background(.ultraThinMaterial, in: Circle()) }
                .accessibilityLabel("Снимок")
            Button { dismiss() } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }
                .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ar.surfaces == 0 {
                Label("Медленно поводите телефоном по полу и стенам — найдём поверхности", systemImage: "move.3d").font(.footnote.weight(.semibold))
            }
            Picker("", selection: $target) { ForEach(TryOnTarget.allCases) { Text($0.title.tr).tag($0) } }.pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) { swatchButton(icon: "photo", title: "Своё фото") }
                    Button { showCamera = true } label: { swatchButton(icon: "camera.fill", title: "Плитка в магазине") }
                    Button { prompt = ""; describing = true } label: { swatchButton(icon: "sparkles", title: generating ? "Рисуем…" : "Описать ИИ") }.disabled(generating)
                    ForEach(all) { m in
                        Button { choose(m) } label: { swatch(m) }
                    }
                }
            }
            if let m = chosen[target] {
                if m.kind == .tile {
                    Picker("Размер плитки", selection: Binding(get: { Int((m.tileMeters * 1000).rounded()) }, set: { resize(m, mm: $0) })) {
                        ForEach([200, 300, 450, 600, 800, 1200], id: \.self) { Text("\($0) мм").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                quantity(m)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(10)
    }

    private func swatchButton(icon: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).frame(width: 58, height: 58).background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
            Text(title.tr).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 70)
        }
    }

    private func swatch(_ m: TryOnMaterial) -> some View {
        let on = chosen[target] == m
        return VStack(spacing: 4) {
            Group {
                if let image = m.image { Image(uiImage: image).resizable().scaledToFill() } else { Color(m.color ?? .gray) }
            }
            .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Theme.goldLight : .white.opacity(0.3), lineWidth: on ? 3 : 1))
            Text(m.title.tr).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 70)
        }
    }

    /// Сколько купить: площадь найденных поверхностей + 10 % запаса.
    private func quantity(_ m: TryOnMaterial) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(m.title.tr) · \(target.title.tr): ≈ \(ParcelRules.format(area, digits: 1)) м²").font(.footnote.weight(.semibold))
            switch m.kind {
            case .tile:
                let one = m.tileMeters * m.tileMeters
                Text("Купить ≈ \(ParcelRules.format(area * 1.1, digits: 1)) м² — около \(Int((area * 1.1 / max(0.01, one)).rounded(.up))) плиток (запас 10 %)").font(.caption)
            case .wood:
                Text("Купить ≈ \(ParcelRules.format(area * 1.07, digits: 1)) м² ламината (запас 7 %)").font(.caption)
            case .paint:
                Text("Краски ≈ \(ParcelRules.format(area * 2 / 9, digits: 1)) л на 2 слоя (≈ 9 м² с литра)").font(.caption)
            }
            Text("Площадь — по найденным поверхностям; обойдите всю комнату, чтобы посчитать точнее. Точный расчёт — в «Скан комнаты».").font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Другой размер плитки: тот же материал, рисунок пересчитывается на поверхности.
    private func resize(_ m: TryOnMaterial, mm: Int) {
        var copy = m
        copy.tileMeters = Double(mm) / 1000
        if let i = custom.firstIndex(of: m) { custom[i] = copy }
        for key in chosen.keys where chosen[key] == m { chosen[key] = copy }
        ar.materials = chosen
        ar.refreshMaterials()
    }

    private func choose(_ m: TryOnMaterial) {
        chosen[target] = m
        ar.materials = chosen
        ar.refreshMaterials()
        Haptics.tap()
    }

    /// Фото плитки → квадрат из центра → бесшовная текстура с тонким швом.
    private func addPhoto(_ image: UIImage) {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let px: CGFloat = 512
        let texture = UIGraphicsImageRenderer(size: CGSize(width: px, height: px)).image { ctx in
            UIColor(white: 0.8, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
            let scale = px / side
            image.draw(in: CGRect(x: -crop.minX * scale + 3, y: -crop.minY * scale + 3, width: image.size.width * scale - 6, height: image.size.height * scale - 6))
        }
        let m = TryOnMaterial(title: "Моя плитка", image: texture, tileMeters: 0.6, kind: .tile)
        custom.insert(m, at: 0)
        choose(m)
    }

    private func generate() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generating = true; error = nil
        defer { generating = false }
        do {
            let english = await store.englishPrompt(text)
            let image = try await store.pictureByDescription("Seamless tileable square texture, flat top-down orthographic view, even lighting, no perspective, no objects: \(english). High detail, realistic material.")
            let m = TryOnMaterial(title: String(text.prefix(22)), image: image, tileMeters: target == .floor ? 0.6 : 0.6, kind: .tile)
            custom.insert(m, at: 0)
            choose(m)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
