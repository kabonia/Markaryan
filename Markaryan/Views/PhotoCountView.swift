import SwiftUI
import PhotosUI
import AVFoundation

/// Counting materials by a photo of their ends: rebar, pipes, boards, timber.
/// AI marks every end, the user corrects (tap empty spot = add, tap a mark = remove),
/// the app converts the count into tonnes, metres or cubic metres.
enum CountMaterial: String, CaseIterable, Identifiable {
    case rebar, pipe, board, timber, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rebar: return "Арматура"
        case .pipe: return "Трубы"
        case .board: return "Доски"
        case .timber: return "Брус"
        case .other: return "Любое"
        }
    }
    var icon: String {
        switch self {
        case .rebar: return "circle.grid.3x3.fill"
        case .pipe: return "circle.circle"
        case .board: return "rectangle.split.3x1"
        case .timber: return "square.grid.3x3.square"
        case .other: return "number.circle"
        }
    }
    var aiObject: String {
        switch self {
        case .rebar: return "пачка арматуры, торцы круглых стержней"
        case .pipe: return "пачка труб, круглые торцы труб"
        case .board: return "штабель досок, прямоугольные торцы досок"
        case .timber: return "штабель бруса, квадратные или прямоугольные торцы бруса"
        case .other: return "предметы"
        }
    }
    var usesSection: Bool { self == .board || self == .timber }
}

// MARK: - Counting session (several parts: live camera shots and/or gallery photos)

struct CountPart: Identifiable {
    enum Status: Equatable { case counting, done, failed(String) }
    let id = UUID()
    let image: UIImage
    var points: [CGPoint] = []
    var history: [[CGPoint]] = []
    var status: Status = .counting
    var note = ""
}

/// Keeps every part of a big pile: each photo is counted by the AI in the background
/// while the user keeps shooting the next part; the total is the sum of all parts.
@MainActor final class CountSession: ObservableObject {
    @Published var parts: [CountPart] = []
    @Published var selectedID: UUID?
    @Published var autoDetect = true
    @Published var material: CountMaterial = .rebar
    @Published var customObject = ""
    @Published var detectedName = ""

    var total: Int { parts.reduce(0) { $0 + $1.points.count } }
    var countingCount: Int { parts.filter { $0.status == .counting }.count }
    var selectedIndex: Int? { parts.firstIndex { $0.id == selectedID } ?? (parts.isEmpty ? nil : parts.count - 1) }

    /// What the AI should look for. After the first part is recognised, the next parts count the same thing.
    private var aiObject: String? {
        if autoDetect { return detectedName.isEmpty ? nil : detectedName }
        guard material == .other else { return material.aiObject }
        let clean = customObject.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "все одинаковые предметы на фото (гайки, болты, кирпичи, мешки и т.п.); каждый предмет — одна точка" : "\(clean); каждый отдельный предмет — одна точка"
    }

    func add(_ image: UIImage, store: AppStore) {
        let part = CountPart(image: image)
        parts.append(part)
        selectedID = part.id
        count(part.id, store: store)
    }

    func retry(_ id: UUID, store: AppStore) {
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return }
        parts[index].status = .counting
        parts[index].points = []
        parts[index].history = []
        count(id, store: store)
    }

    func remove(_ id: UUID) {
        parts.removeAll { $0.id == id }
        if selectedID == id { selectedID = parts.last?.id }
        if parts.isEmpty { detectedName = "" }
    }

    func reset() { parts = []; selectedID = nil; detectedName = "" }

    private func count(_ id: UUID, store: AppStore) {
        guard let image = parts.first(where: { $0.id == id })?.image else { return }
        let object = aiObject
        Task {
            do {
                let result = try await store.countObjectsOnPhoto(image, object: object)
                guard let index = parts.firstIndex(where: { $0.id == id }) else { return }
                withAnimation(.snappy) {
                    parts[index].points = result.points
                    parts[index].note = result.note
                    parts[index].status = .done
                    if autoDetect && detectedName.isEmpty {
                        material = CountMaterial(rawValue: result.kind) ?? .other
                        detectedName = result.name
                        if material == .other { customObject = result.name }
                    }
                }
                Haptics.success()
            } catch {
                if let index = parts.firstIndex(where: { $0.id == id }) { parts[index].status = .failed(error.localizedDescription) }
                Haptics.warning()
            }
        }
    }

    func tap(at location: CGPoint) {
        guard let index = selectedIndex, parts[index].status == .done else { return }
        parts[index].history.append(parts[index].points)
        if parts[index].history.count > 50 { parts[index].history.removeFirst() }
        let radius: CGFloat = 0.025
        let points = parts[index].points
        if let nearest = points.indices.min(by: { hypot(points[$0].x - location.x, points[$0].y - location.y) < hypot(points[$1].x - location.x, points[$1].y - location.y) }),
           hypot(points[nearest].x - location.x, points[nearest].y - location.y) < radius {
            parts[index].points.remove(at: nearest)
        } else {
            parts[index].points.append(location)
        }
        Haptics.tap()
    }

    func undo() {
        guard let index = selectedIndex, let last = parts[index].history.popLast() else { return }
        parts[index].points = last
    }
}

// MARK: - Main screen

struct PhotoCountView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var session = CountSession()
    @State private var items: [PhotosPickerItem] = []
    @State private var showLiveCamera = false
    @State private var diameter = "12"
    @State private var thickness = "50"
    @State private var width = "150"
    @State private var length = "6"
    @State private var price = ""
    @State private var shareBundle: ShareBundle?
    @State private var error: String?

    private var material: CountMaterial { session.material }
    private var count: Int { session.total }
    private var lengthM: Double { CalculationEngine.parse(length) ?? 0 }
    private var totalLength: Double { Double(count) * lengthM }
    private var massKg: Double {
        let d = (CalculationEngine.parse(diameter) ?? 0) / 1000
        return Double.pi * d * d / 4 * 7850 * totalLength
    }
    private var volumeM3: Double {
        let t = (CalculationEngine.parse(thickness) ?? 0) / 1000, w = (CalculationEngine.parse(width) ?? 0) / 1000
        return t * w * totalLength
    }
    private var cost: Double? {
        guard let value = CalculationEngine.parse(price), value > 0 else { return nil }
        switch material {
        case .rebar: return massKg / 1000 * value
        case .pipe: return totalLength * value
        case .board, .timber: return volumeM3 * value
        case .other: return Double(count) * value
        }
    }
    private var priceUnit: String {
        switch material { case .rebar: return "₽/т"; case .pipe: return "₽/м"; case .board, .timber: return "₽/м³"; case .other: return "₽/шт." }
    }
    private var countTitle: String {
        if !session.detectedName.isEmpty { return session.detectedName }
        let custom = session.customObject.trimmingCharacters(in: .whitespaces)
        return material == .other ? (custom.isEmpty ? "Предметы" : custom) : material.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Счёт по камере", title: "Наведите камеру —\nИИ посчитает")
                Text("Снимайте прямо с камеры или загружайте фото. Большую пачку снимайте по частям — итог сложится сам.").font(.subheadline).foregroundStyle(Theme.muted)

                Button { showLiveCamera = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder").font(.title2.weight(.semibold)).foregroundStyle(.black)
                            .frame(width: 52, height: 52).background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Считать камерой").font(.headline).foregroundStyle(.white)
                            Text("Снимайте часть за частью — счёт идёт сразу").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .padding(16).panelCard(20)
                }
                .buttonStyle(PremiumCardPressStyle())
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                PhotosPicker(selection: $items, maxSelectionCount: 12, matching: .images) {
                    SecondaryActionLabel(title: "Загрузить фото (можно несколько частей)", icon: "photo.on.rectangle.angled")
                }
                .buttonStyle(PremiumPressStyle())

                Toggle(isOn: $session.autoDetect.animation(.snappy)) { Label("ИИ сам определит, что на фото", systemImage: "sparkles") }
                    .tint(Theme.orange).padding(14).panelCard(14)
                if !session.autoDetect {
                    Picker("Материал", selection: $session.material) { ForEach(CountMaterial.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    if session.material == .other {
                        TextField("Что считать: гайки М12, кирпич, мешки цемента…", text: $session.customObject).padding(14).panelCard(14)
                    }
                }

                if session.parts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Снимайте прямо, перпендикулярно пачке или сверху на кучу", systemImage: "camera.metering.center.weighted")
                        Label("Части не должны перекрываться — каждый предмет только в одном кадре", systemImage: "square.split.2x2")
                        Label("Мелочь (гайки, болты) рассыпьте в один слой на контрастном фоне", systemImage: "circle.grid.3x3")
                    }
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
                } else {
                    totalCard
                    if let index = session.selectedIndex { partCard(session.parts[index]) }
                    parameters
                    summary
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                InfoNote(text: "Счёт по фото — быстрая проверка поставки, а не замена приёмки. При плотной укладке ИИ может пропустить или задвоить предметы: проверьте метки и поправьте касанием.")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Счёт по фото")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !session.parts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Сбросить") { session.reset() } }
            }
        }
        .fullScreenCover(isPresented: $showLiveCamera) { LiveCountCameraView(session: session) }
        .sheet(item: $shareBundle) { bundle in ActivityShareSheet(items: bundle.urls) }
        .onChange(of: items) { _, selected in
            guard !selected.isEmpty else { return }
            Task {
                for item in selected {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { session.add(image, store: store) }
                }
                items = []
            }
        }
    }

    // MARK: Total and parts

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    if !session.detectedName.isEmpty { Text(session.detectedName.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.sky) }
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(count)").font(.system(size: 44, weight: .bold)).monospacedDigit().contentTransition(.numericText()).foregroundStyle(Theme.orange)
                        Text("шт.").font(.title3.weight(.semibold))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("частей: \(session.parts.count)").font(.caption.weight(.semibold))
                    if session.countingCount > 0 { HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("считаем \(session.countingCount)").font(.caption) }.foregroundStyle(Theme.muted) }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.parts.enumerated()), id: \.element.id) { index, part in
                        PartThumbnail(part: part, number: index + 1, selected: session.selectedIndex == index)
                            .onTapGesture { Haptics.tap(); session.selectedID = part.id }
                    }
                }
            }
        }
        .padding(14).panelCard(20)
    }

    private func partCard(_ part: CountPart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Часть \((session.parts.firstIndex(where: { $0.id == part.id }) ?? 0) + 1) · \(part.points.count) шт.").font(.headline)
                Spacer()
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward").padding(9).background(Theme.panelRaised, in: Circle()) }
                    .disabled(part.history.isEmpty).accessibilityLabel("Отменить правку")
                Button { session.retry(part.id, store: store) } label: { Image(systemName: "arrow.clockwise").padding(9).background(Theme.panelRaised, in: Circle()) }
                    .disabled(part.status == .counting).accessibilityLabel("Посчитать заново")
                Button(role: .destructive) { withAnimation(.snappy) { session.remove(part.id) } } label: { Image(systemName: "trash").padding(9).background(Theme.panelRaised, in: Circle()) }
                    .accessibilityLabel("Удалить часть")
            }
            MarkedPhoto(image: part.image, points: part.points) { location in session.tap(at: location) }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if part.status == .counting {
                        VStack(spacing: 8) { ProgressView().tint(.white); Text("ИИ считает…").font(.caption.weight(.semibold)) }
                            .padding(14).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            switch part.status {
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.danger)
            case .done: Text("Касание пустого места — добавить метку, касание метки — убрать.").font(.caption).foregroundStyle(Theme.muted)
            case .counting: EmptyView()
            }
            if !part.note.isEmpty { Label(part.note, systemImage: "sparkles").font(.caption).foregroundStyle(.white.opacity(0.8)) }
        }
        .padding(14).panelCard(20)
    }

    // MARK: Parameters and result

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            if material != .other {
                HStack(spacing: 10) {
                    if material.usesSection {
                        field("Толщина, мм", $thickness)
                        field("Ширина, мм", $width)
                    } else {
                        field("Диаметр, мм", $diameter)
                    }
                    field("Длина, м", $length)
                }
            }
            field("Цена, \(priceUnit) (необязательно)", $price)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ИТОГО · \(countTitle.uppercased())").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Theme.orange)
            row("Количество", "\(count) шт.")
            if material != .other { row("Общая длина", "\(CalculationEngine.format((totalLength * 10).rounded() / 10)) м") }
            switch material {
            case .rebar: row("Масса (теоретическая)", "\(CalculationEngine.format(massKg.rounded())) кг · \(CalculationEngine.format(massKg.rounded() / 1000)) т")
            case .pipe, .other: EmptyView()
            case .board, .timber: row("Объём", "\(CalculationEngine.format((volumeM3 * 1000).rounded() / 1000)) м³")
            }
            if let cost { Divider(); row("Стоимость по вашей цене", CalculationEngine.money(cost)) }
            HStack(spacing: 10) {
                Button { share() } label: { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
                Button { store.appendToRequest(reportText) } label: { SecondaryActionLabel(title: "В заявку", icon: "square.and.pencil") }.buttonStyle(PremiumPressStyle())
            }
            .padding(.top, 4)
        }
        .padding(18).panelCard(20)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline).foregroundStyle(Theme.muted); Spacer(); Text(value).font(.subheadline.bold()).monospacedDigit() }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            TextField("0", text: text).keyboardType(.decimalPad).font(.headline.monospacedDigit()).padding(12).panelCard(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reportText: String {
        var lines = ["СЧЁТ ПО ФОТО · \(countTitle.uppercased())", "Количество: \(count) шт. (частей: \(session.parts.count))"]
        if material != .other { lines.append("Длина: \(length) м, общая длина \(CalculationEngine.format((totalLength * 10).rounded() / 10)) м") }
        switch material {
        case .rebar: lines.append("Диаметр \(diameter) мм, масса ≈ \(CalculationEngine.format(massKg.rounded())) кг")
        case .pipe, .other: break
        case .board, .timber: lines.append("Сечение \(thickness)×\(width) мм, объём ≈ \(CalculationEngine.format((volumeM3 * 1000).rounded() / 1000)) м³")
        }
        if let cost { lines.append("Стоимость: \(CalculationEngine.money(cost))") }
        lines += ["Подсчёт по фото с проверкой вручную, ориентировочно.", "", Brand.shareFooter]
        return lines.joined(separator: "\n")
    }

    @MainActor private func share() {
        var urls: [URL] = []
        for (index, part) in session.parts.enumerated() {
            let renderer = ImageRenderer(content: MarkedPhoto(image: part.image, points: part.points, onTap: nil).frame(width: 1200, height: 1200 * part.image.size.height / max(1, part.image.size.width)))
            renderer.scale = 1
            guard let image = renderer.uiImage, let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.85) else { continue }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Счёт-часть\(index + 1)-\(part.points.count)шт-\(Int(Date().timeIntervalSince1970)).jpg")
            if (try? data.write(to: url, options: .atomic)) != nil { urls.append(url) }
        }
        let textURL = FileManager.default.temporaryDirectory.appendingPathComponent("Счёт-итог-\(count)шт.txt")
        if (try? reportText.write(to: textURL, atomically: true, encoding: .utf8)) != nil { urls.insert(textURL, at: 0) }
        guard !urls.isEmpty else { error = "Не удалось подготовить файлы."; return }
        shareBundle = ShareBundle(urls: urls)
    }
}

struct ShareBundle: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct PartThumbnail: View {
    let part: CountPart
    let number: Int
    let selected: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: part.image).resizable().scaledToFill().frame(width: 78, height: 78).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            Group {
                switch part.status {
                case .counting: ProgressView().tint(.white).controlSize(.small)
                case .done: Text("\(part.points.count)").font(.subheadline.bold()).monospacedDigit()
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                }
            }
            .padding(6)
            Text("\(number)").font(.caption2.bold()).padding(4).background(.black.opacity(0.6), in: Circle()).padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 78, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.orange : .clear, lineWidth: 2))
        .accessibilityLabel("Часть \(number): \(part.points.count) штук")
    }
}

// MARK: - Live camera: shoot part after part, counting runs in the background

struct LiveCountCameraView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CountSession
    @StateObject private var camera = CountCameraController()
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.authorized {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else if camera.denied {
                VStack(spacing: 14) {
                    Text("Нет доступа к камере").font(.title3.bold())
                    Link("Открыть настройки", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
            Color.white.opacity(flash ? 0.6 : 0).ignoresSafeArea().allowsHitTesting(false)
            // Framing guide
            RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .padding(.horizontal, 24).padding(.vertical, 170).allowsHitTesting(false)

            VStack(spacing: 12) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }
                        .accessibilityLabel("Закрыть камеру")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.detectedName.isEmpty ? "ИТОГО" : session.detectedName.uppercased()).font(.caption2.weight(.bold)).tracking(1)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(session.total)").font(.system(size: 34, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                            Text("шт.").font(.subheadline.weight(.semibold))
                        }
                        if session.countingCount > 0 { HStack(spacing: 5) { ProgressView().controlSize(.mini).tint(.white); Text("считаем \(session.countingCount)").font(.caption2) } }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                Text(session.parts.isEmpty ? "Наведите на пачку или кучу и сделайте снимок" : "Сдвиньтесь к следующей части без перекрытия и снимите ещё").font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                Spacer()
                if !session.parts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(session.parts.enumerated()), id: \.element.id) { index, part in
                                PartThumbnail(part: part, number: index + 1, selected: false)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                HStack {
                    Spacer().frame(width: 70)
                    Spacer()
                    Button { shoot() } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 70, height: 70)
                            Circle().stroke(.white.opacity(0.6), lineWidth: 4).frame(width: 84, height: 84)
                        }
                    }
                    .disabled(!camera.authorized)
                    .accessibilityLabel("Снять часть")
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Готово").font(.subheadline.weight(.bold)).foregroundStyle(.black).frame(width: 70, height: 44).background(Theme.orange, in: Capsule())
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            camera.onPhoto = { image in session.add(image, store: store) }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private func shoot() {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task { try? await Task.sleep(for: .milliseconds(140)); withAnimation(.easeIn(duration: 0.2)) { flash = false } }
        camera.capture()
    }
}

/// Minimal AVFoundation camera: live preview + still photos.
final class CountCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var authorized = false
    @Published var denied = false
    var onPhoto: ((UIImage) -> Void)?
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "artstroy.count.camera")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.run() } else { self.denied = true } }
            }
        default: denied = true
        }
    }

    private func run() {
        authorized = true
        queue.async {
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func capture() {
        queue.async {
            guard self.session.isRunning else { return }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onPhoto?(image) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Photo with numbered marks; reports taps in 0…1 image coordinates.
struct MarkedPhoto: View {
    let image: UIImage
    let points: [CGPoint]
    var onTap: ((CGPoint) -> Void)?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    let size = proxy.size
                    let dot = max(10, min(26, size.width / 34))
                    ZStack {
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            ZStack {
                                Circle().fill(Theme.orange.opacity(0.85))
                                Circle().stroke(.white, lineWidth: 1.5)
                                if points.count <= 200 { Text("\(index + 1)").font(.system(size: dot * 0.42, weight: .bold)).foregroundStyle(.black).minimumScaleFactor(0.5) }
                            }
                            .frame(width: dot, height: dot)
                            .position(x: point.x * size.width, y: point.y * size.height)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let onTap, size.width > 0, size.height > 0 else { return }
                        onTap(CGPoint(x: location.x / size.width, y: location.y / size.height))
                    }
                }
            }
            .accessibilityLabel("Фото с отметками: \(points.count)")
    }
}
