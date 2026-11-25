import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - «Свой материал»: a photo or a file of the exact tile, facade, toilet, sink… the client wants to see in the render

struct MaterialChoice: Codable, Hashable { var ru: String; var en: String }

struct MaterialReference: Identifiable {
    let id = UUID()
    var image: UIImage
    var fileName: String = ""
    var fileText: String = ""
    var recognizing = true
    var failure: String? = nil
    var title = ""
    var english = ""
    var question = ""
    var placements: [MaterialChoice] = []
    var methods: [MaterialChoice] = []
    var placement: MaterialChoice? = nil
    var method: MaterialChoice? = nil
    var note = ""
    /// The note translated for the image model (filled right before the render).
    var noteEnglish = ""

    var ready: Bool { !recognizing && failure == nil && placement != nil }

    /// JPEG for the server: long side 1024 px is enough to keep pattern and colour.
    var jpeg: Data? {
        let scale = min(1, 1024 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.85)
    }

    /// The part of the render prompt about the client's materials; reference images go after the main picture (image 1).
    static func prompt(_ list: [MaterialReference]) -> String {
        let ready = list.filter(\.ready)
        guard !ready.isEmpty else { return "" }
        let lines = ready.enumerated().map { index, item in
            var line = "Reference image \(index + 2) shows a real product/material chosen by the client: \(item.english.isEmpty ? item.title : item.english). Use exactly this item for: \(item.placement?.en ?? "the most suitable place")."
            if let method = item.method { line += " Installation / layout: \(method.en)." }
            if !item.noteEnglish.isEmpty { line += " Client's note: \(item.noteEnglish)." }
            return line
        }
        return "\n\nCLIENT'S OWN MATERIALS — mandatory. The first image is the scene to edit; the next images are only samples of materials and products, never copy their background or framing. "
            + lines.joined(separator: " ")
            + " Reproduce each sample's exact colour, pattern, texture, finish, format and design at a realistic scale for the room; keep the room geometry, walls, windows and camera exactly as in the first image."
    }
}

@MainActor
enum MaterialRecognizer {
    static func identify(_ item: MaterialReference, screen: String, room: String) async throws -> MaterialReference {
        guard let base = AIServerConfig.baseURL else { throw ClaudeError.api("Распознавание материалов работает через сервер приложения.") }
        guard let jpeg = item.jpeg else { throw ClaudeError.api("Не удалось подготовить изображение.") }
        var request = URLRequest(url: base.appendingPathComponent("v1/ai/material-identify"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        request.setValue(AppLanguage.code, forHTTPHeaderField: "X-App-Language")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["image": jpeg.base64EncodedString(), "screen": screen, "room": room, "fileName": item.fileName, "text": item.fileText])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ClaudeError.api(json["error"] as? String ?? "Не удалось распознать материал.")
        }
        func choices(_ key: String) -> [MaterialChoice] {
            (json[key] as? [[String: Any]] ?? []).compactMap { o in
                guard let ru = o["ru"] as? String, let en = o["en"] as? String else { return nil }
                return MaterialChoice(ru: ru, en: en)
            }
        }
        var result = item
        result.recognizing = false
        result.failure = nil
        result.title = json["title"] as? String ?? "Материал"
        result.english = json["english"] as? String ?? ""
        result.question = json["question"] as? String ?? "Куда это поставить и как?"
        result.placements = choices("placements")
        result.methods = choices("methods")
        result.placement = result.placements.first
        result.method = result.methods.first
        return result
    }
}

/// «Свои материалы и товары»: add a photo or a file, the AI recognises it and asks where and how.
struct MaterialReferencesSection: View {
    @EnvironmentObject private var store: AppStore
    @Binding var items: [MaterialReference]
    /// For the AI: which screen and which room (bathroom, facade…).
    var screen: String
    var room: String
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var showCamera = false
    @State private var captured: UIImage?

    static let limit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("СВОИ МАТЕРИАЛЫ И ТОВАРЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Spacer()
                if !items.isEmpty { Text("\(items.count) из \(Self.limit)").font(.caption).foregroundStyle(Theme.muted) }
            }
            Text("Плитка, фасад, унитаз, раковина, обои, ламинат, светильник — пришлите фото или файл, ИИ узнает, что это, спросит, куда и как, и поставит именно это.")
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach($items) { $item in MaterialReferenceCard(item: $item, retry: { recognize(item.id) }, remove: { items.removeAll { $0.id == item.id } }) }
            if items.count < Self.limit {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $picked, maxSelectionCount: Self.limit - items.count, matching: .images) { chip("Фото", "photo") }
                    Button { showCamera = true } label: { chip("Камера", "camera") }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Button { importing = true } label: { chip("Файл", "doc") }
                }
                .buttonStyle(PremiumPressStyle())
            }
        }
        .padding(16).panelCard(20)
        .onChange(of: picked) { _, list in Task { await addPhotos(list) } }
        .onChange(of: captured) { _, image in if let image { add(image, name: "Фото с камеры") }; captured = nil }
        .sheet(isPresented: $showCamera) { CameraCaptureView(image: $captured).ignoresSafeArea() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { for url in urls { addFile(url) } }
        }
    }

    private func chip(_ title: String, _ icon: String) -> some View {
        Label(title.tr, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addPhotos(_ list: [PhotosPickerItem]) async {
        guard !list.isEmpty else { return }
        for item in list {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { add(image, name: "") }
        }
        picked = []
    }

    private func addFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url), let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1400 / max(bounds.width, bounds.height, 1)
            add(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox), name: name, text: String((document.string ?? "").prefix(4000)))
        } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            add(image, name: name)
        }
    }

    private func add(_ image: UIImage, name: String, text: String = "") {
        guard items.count < Self.limit else { return }
        let item = MaterialReference(image: image, fileName: name, fileText: text)
        items.append(item)
        recognize(item.id)
    }

    private func recognize(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recognizing = true
        items[index].failure = nil
        let item = items[index]
        Task {
            do {
                let result = try await MaterialRecognizer.identify(item, screen: screen, room: room)
                if let i = items.firstIndex(where: { $0.id == id }) { withAnimation(.snappy) { items[i] = result } }
                Haptics.success()
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].recognizing = false; items[i].failure = error.localizedDescription }
                HelperCenter.shared.failed(error, action: "Распознать свой материал")
            }
        }
    }
}

struct MaterialReferenceCard: View {
    @Binding var item: MaterialReference
    var retry: () -> Void
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(uiImage: item.image).resizable().scaledToFill().frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if item.recognizing {
                        HStack(spacing: 8) { ProgressView(); Text("ИИ распознаёт…").font(.subheadline).foregroundStyle(Theme.muted) }
                    } else if let failure = item.failure {
                        Text(failure).font(.caption).foregroundStyle(Theme.danger)
                        Button("Повторить", action: retry).font(.caption.weight(.semibold))
                    } else {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Text(item.question).font(.caption).foregroundStyle(Theme.orange)
                    }
                }
                Spacer(minLength: 4)
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.accessibilityLabel("Убрать")
            }
            if !item.recognizing && item.failure == nil {
                if !item.placements.isEmpty {
                    Text("Куда").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    choices(item.placements, selected: item.placement) { item.placement = $0 }
                }
                if item.methods.count > 1 {
                    Text("Как").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    choices(item.methods, selected: item.method) { item.method = $0 }
                }
                TextField("Уточнение: например, шов 2 мм графит, только нижняя половина стены", text: $item.note, axis: .vertical)
                    .font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1...3)
                    .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .background(Theme.panelRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func choices(_ list: [MaterialChoice], selected: MaterialChoice?, pick: @escaping (MaterialChoice) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(list, id: \.self) { option in
                    let on = option == selected
                    Button { Haptics.tap(); pick(option) } label: {
                        Text(option.ru).font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                            .background(on ? Theme.orange : Theme.panel, in: Capsule()).overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .overlay(Capsule().strokeBorder(Theme.stroke))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension Array where Element == MaterialReference {
    /// Translates the clients' notes before the render (the image models work best in English).
    @MainActor
    func preparedForRender(_ store: AppStore) async -> [MaterialReference] {
        var result: [MaterialReference] = []
        for var item in self where item.ready {
            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            item.noteEnglish = note.isEmpty ? "" : await store.englishPrompt(note)
            result.append(item)
        }
        return result
    }
}
