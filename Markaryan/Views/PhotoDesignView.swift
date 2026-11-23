import SwiftUI
import PhotosUI
import Photos

/// «Дизайн по фото»: a photo of any part of the house — the AI makes a new design,
/// or changes only what the user wrote. Nothing starts until the user has chosen and pressed «Сгенерировать».
/// Every result is saved on the iPhone and can be corrected again in plain words.
struct PhotoDesignView: View {
    @EnvironmentObject private var store: AppStore
    @State private var source: UIImage?
    @State private var results: [UIImage] = []
    /// Which model drew each variant (the picked one, or the next one when it failed).
    @State private var resultModels: [String] = []
    @State private var showModels = false
    @State private var shown = 0
    @State private var room: PhotoDesignRoom?
    @State private var mode: PhotoDesignMode = .redesign
    @State private var style: DesignStyle?
    @State private var wishes = ""
    @State private var correction = ""
    @State private var record: PhotoDesignRecord?
    @State private var library: [PhotoDesignRecord] = []
    @State private var confirmDelete: PhotoDesignRecord?
    @State private var isLoading = false
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var shareFile: SharedFile?
    @State private var saved = false
    @State private var addedToProject = false
    @State private var opened: FloorPlanDetailView.PhotoSheetItem?
    /// The client's own tile, facade, sanitary ware… for the render.
    @State private var materials: [MaterialReference] = []

    private var current: UIImage? { results.indices.contains(shown) ? results[shown] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sourceCard
                if source != nil {
                    settings
                    MaterialReferencesSection(items: $materials, screen: "Дизайн по фото / Live", room: room?.title ?? "не выбрано")
                    if store.photorealAvailable {
                        AIModelsRow(value: store.renderModel.title, title: "Модель ИИ") { showModels = true }
                    }
                    generateButton
                }
                if isLoading { loadingCard }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
                }
                if let source, let current { resultCard(before: source, after: current) }
                savedDesigns
                if !store.photorealAvailable {
                    InfoNote(text: "Дизайн по фото сейчас недоступен: картинки ИИ не подключены.")
                }
            }
            .padding(20)
            .animation(.snappy(duration: 0.3), value: results.count)
            .animation(.snappy(duration: 0.3), value: source != nil)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Дизайн по фото").helperScreen("Дизайн по фото")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in Task { await load(item) } }
        .sheet(isPresented: $showCamera) { CameraCaptureView(image: $captured).ignoresSafeArea() }
        .onChange(of: captured) { _, image in
            guard let image else { return }
            captured = nil
            start(with: image)
        }
        .onAppear { library = PhotoDesignLibrary.all() }
        .confirmationDialog("Удалить этот дизайн с iPhone?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let item = confirmDelete {
                    PhotoDesignLibrary.delete(item.id)
                    if record?.id == item.id { record = nil }
                    withAnimation(.snappy) { library = PhotoDesignLibrary.all() }
                }
                confirmDelete = nil
            }
        }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .sheet(item: $opened) { item in NavigationStack { RenderResultView(image: item.image, title: "Дизайн · \((room ?? .other).title)") } }
        .sheet(isPresented: $showModels) { NavigationStack { AIModelsView(showsDesign: false) }.presentationDetents([.medium, .large]) }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ФОТО → НОВЫЙ ДИЗАЙН").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Theme.sky)
            Text("Снимите помещение —\nувидьте его обновлённым").font(.title2.bold())
            Text("1. Снимите или выберите фото. 2. Укажите, что на нём, и выберите стиль. 3. Нажмите «Сгенерировать». ИИ сохранит стены, окна и ракурс, а отделку, мебель и свет сделает в выбранном стиле. Все результаты сохраняются на iPhone.")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let source {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: source).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 200).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("ИСХОДНОЕ ФОТО").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white).padding(10)
                }
            }
            HStack(spacing: 10) {
                Button { showCamera = true } label: {
                    Label(source == nil ? "Снять сейчас" : "Новое фото", systemImage: "camera.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(15).foregroundStyle(Theme.onAccent)
                        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(PremiumPressStyle())
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Из галереи", systemImage: "photo.on.rectangle").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(15).foregroundStyle(Theme.ink)
                        .panelCard(15, fill: Theme.panelRaised)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .panelCard(22)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Что на фото").font(.headline)
                    .foregroundStyle(room == nil ? Theme.sky : Theme.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoDesignRoom.allCases) { item in
                            Button { Haptics.tap(); withAnimation(.snappy) { room = item } } label: {
                                Label(item.title, systemImage: item.icon).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(room == item ? Theme.sky : Theme.panel, in: Capsule())
                                    .foregroundStyle(room == item ? Theme.onAccent : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Что сделать").font(.headline)
                HStack(spacing: 10) {
                    ForEach(PhotoDesignMode.allCases) { item in
                        Button { Haptics.tap(); withAnimation(.snappy) { mode = item } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.subtitle).font(.caption2).foregroundStyle(mode == item ? .black.opacity(0.7) : Theme.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading).padding(12)
                            .foregroundStyle(mode == item ? Theme.onAccent : Theme.ink)
                            .background(mode == item ? Theme.sky : Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(mode == .redesign ? "Стиль" : "Стиль (необязательно)").font(.headline)
                    .foregroundStyle(mode == .redesign && style == nil ? Theme.sky : Theme.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if mode == .refine {
                            Button { style = nil } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "circle.slash").font(.title2).frame(width: 128, height: 92)
                                        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Text("Как есть").font(.caption.weight(.semibold))
                                }
                                .padding(8)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style == nil ? Theme.sky : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(DesignStyle.all) { item in
                            Button { Haptics.tap(); withAnimation(.snappy) { style = item } } label: {
                                StyleCard(style: item, selected: style?.id == item.id).frame(width: 144)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let style { Text(style.summary).font(.caption).foregroundStyle(Theme.muted) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Примечание").font(.headline)
                TextField(room == .bathroom ? "Например: душ вместо ванны, крупная светлая плитка, тёплый свет" : room == .kitchen ? "Например: фасады цвета шалфея, столешница под камень, открытые полки" : "Например: светлый пол, больше хранения, рабочее место у окна", text: $wishes, axis: .vertical)
                    .lineLimit(2...5).padding(14).panelCard(14)
            }
        }
    }

    /// What is still to choose before the AI may start; nil — everything is chosen.
    private var missingChoice: String? {
        if room == nil { return "Выберите, что на фото" }
        if mode == .redesign && style == nil { return "Выберите стиль" }
        if mode == .refine && style == nil && wishes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Напишите, что изменить, или выберите стиль" }
        return nil
    }

    private var generateButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrimaryButton(title: isLoading ? "ИИ работает…" : (results.isEmpty ? "Сгенерировать" : "Сгенерировать ещё вариант"), icon: "wand.and.stars") { generate() }
                .disabled(isLoading || missingChoice != nil)
                .opacity(isLoading || missingChoice != nil ? 0.5 : 1)
            if let missingChoice, !isLoading {
                Label(missingChoice, systemImage: "hand.point.up.left.fill").font(.caption).foregroundStyle(Theme.sky)
            }
        }
    }

    /// Designs made earlier: stored on the iPhone with the source photo and every variant.
    @ViewBuilder private var savedDesigns: some View {
        if !library.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("МОИ ДИЗАЙНЫ ПО ФОТО").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(Theme.sky)
                ForEach(library) { item in
                    Button { open(item) } label: { PhotoDesignRow(record: item) }
                        .buttonStyle(PremiumCardPressStyle())
                        .contextMenu {
                            Button(role: .destructive) { confirmDelete = item } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
                Text("Удерживайте карточку, чтобы удалить.").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.sky)
            VStack(alignment: .leading, spacing: 3) {
                Text("ИИ создаёт дизайн").font(.subheadline.weight(.semibold))
                Text(store.modelChoiceWorks.render && store.renderModel == .seedream ? "Seedream рисует 1–3 минуты. Не сворачивайте приложение." : "Обычно 20–60 секунд. Не сворачивайте приложение.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    private func resultCard(before: UIImage, after: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("РЕЗУЛЬТАТ").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(Theme.sky)
                    Text("\(room?.title ?? "Дизайн")\(style.map { " · \($0.title)" } ?? "")").font(.headline)
                }
                Spacer()
                if results.count > 1 { Text("Вариант \(shown + 1) из \(results.count)").font(.caption).foregroundStyle(Theme.muted) }
            }
            BeforeAfterSlider(before: before, after: after)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture(count: 2) { opened = FloorPlanDetailView.PhotoSheetItem(image: after) }
            Text("Двигайте ползунок: слева — было, справа — стало. Двойное касание — на весь экран. Все варианты сохранены в «Моих дизайнах».").font(.caption2).foregroundStyle(Theme.muted)
            if resultModels.indices.contains(shown) {
                Label("Сделано: \(resultModels[shown])", systemImage: "cpu").font(.caption).foregroundStyle(Theme.muted)
            }
            if results.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 74, height: 56).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(index == shown ? Theme.sky : .clear, lineWidth: 2))
                                .onTapGesture { withAnimation(.snappy) { shown = index } }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("ВНЕСТИ ПРАВКУ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.sky)
                TextField("Например: сделай стены темнее, убери люстру, добавь растения", text: $correction, axis: .vertical)
                    .lineLimit(1...4).padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button { correct(after) } label: {
                    Label("Применить к этому варианту", systemImage: "wand.and.rays").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(13).foregroundStyle(Theme.onAccent)
                        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PremiumPressStyle())
                .disabled(isLoading || correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 10) {
                Button { saveToPhotos(after) } label: { SecondaryActionLabel(title: saved ? "В Фото ✓" : "В Фото", icon: "square.and.arrow.down") }
                    .buttonStyle(PremiumPressStyle())
                Button { addToProject(after) } label: { SecondaryActionLabel(title: addedToProject ? "В проекте" : "В проект", icon: addedToProject ? "checkmark" : "folder.badge.plus") }
                    .buttonStyle(PremiumPressStyle())
                Button { share(after) } label: { SecondaryActionLabel(title: "", icon: "square.and.arrow.up") }
                    .buttonStyle(PremiumPressStyle())
                    .frame(width: 64)
                    .accessibilityLabel("Поделиться")
            }
        }
        .padding(16)
        .panelCard(22)
    }

    // MARK: Actions

    private func start(with image: UIImage) {
        source = image
        results = []
        resultModels = []
        shown = 0
        record = nil
        error = nil
        saved = false
        addedToProject = false
    }

    /// Opens a saved design: the photo, every variant and the choices it was made with.
    private func open(_ item: PhotoDesignRecord) {
        guard let photo = PhotoDesignLibrary.image("source.jpg", in: item.id) else {
            error = "Файлы этого дизайна не найдены на iPhone."
            return
        }
        Haptics.tap()
        withAnimation(.snappy) {
            source = photo
            results = item.versions.compactMap { PhotoDesignLibrary.image($0, in: item.id) }
            resultModels = (item.models ?? []).count == results.count ? (item.models ?? []) : []
            shown = max(0, results.count - 1)
            record = item
            room = PhotoDesignRoom(rawValue: item.room)
            mode = PhotoDesignMode(rawValue: item.mode) ?? .redesign
            style = item.style.flatMap { id in DesignStyle.all.first { $0.id == id } }
            wishes = item.wishes
            error = nil
            saved = false
            addedToProject = false
        }
    }

    /// Every new variant goes to the iPhone at once, so nothing is lost when the screen is closed.
    private func persist(_ image: UIImage, model: String) {
        guard let source else { return }
        var item = record ?? PhotoDesignRecord(id: UUID(), date: .now, room: room?.rawValue ?? PhotoDesignRoom.other.rawValue, mode: mode.rawValue, style: style?.id, wishes: wishes, versions: [])
        do {
            if record == nil { try PhotoDesignLibrary.write(source, name: "source.jpg", in: item.id) }
            let name = "v\(item.versions.count + 1).jpg"
            try PhotoDesignLibrary.write(image, name: name, in: item.id)
            try PhotoDesignLibrary.writeThumbnail(image, in: item.id)
            item.versions.append(name)
            item.models = (item.models ?? []) + [model]
            item.date = .now
            item.style = style?.id ?? item.style
            try PhotoDesignLibrary.save(item)
            record = item
            library = PhotoDesignLibrary.all()
        } catch {
            self.error = "Результат не сохранился на iPhone: \(error.localizedDescription)"
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = "Не удалось открыть фото."
                return
            }
            pickerItem = nil
            start(with: image)
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }

    /// A new variant from the source photo.
    private func generate() {
        guard let source, missingChoice == nil else { return }
        run(base: source, mode: mode, style: style, wishes: wishes.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The shown variant changed only as written.
    private func correct(_ image: UIImage) {
        let text = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        correction = ""
        run(base: image, mode: .refine, style: nil, wishes: text)
    }

    private func run(base: UIImage, mode: PhotoDesignMode, style: DesignStyle?, wishes: String) {
        guard !isLoading else { return }
        error = nil
        saved = false
        addedToProject = false
        isLoading = true
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            let english = wishes.isEmpty ? "" : await store.englishPrompt(wishes)
            let prompt = mode.prompt(room: room ?? .other, style: style, wishesEnglish: english)
            let samples = await materials.preparedForRender(store)
            do {
                let result = try await store.photorealRender(base, prompt: prompt, references: samples)
                withAnimation(.snappy) {
                    results.append(result.image)
                    resultModels.append(result.title)
                    shown = results.count - 1
                }
                persist(result.image, model: result.title)
                store.track("photo_design")
                store.registerMeaningfulAction()
                Haptics.success()
            } catch {
                self.error = error.localizedDescription; HelperCenter.shared.failed(error)
                Haptics.warning()
            }
            isLoading = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { error = "Разрешите приложению сохранять изображения в Фото." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, saveError in
                DispatchQueue.main.async {
                    if success { saved = true } else { error = saveError?.localizedDescription ?? "Не удалось сохранить изображение." }
                }
            }
        }
    }

    private func addToProject(_ image: UIImage) {
        do {
            try store.addProjectPhoto(image, caption: "Дизайн по фото: \((room ?? .other).title.lowercased())\(style.map { ", \($0.title.lowercased())" } ?? "")")
            addedToProject = true
            Haptics.success()
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }

    private func share(_ image: UIImage) {
        guard let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.92) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Дизайн-\(Brand.name)-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            shareFile = SharedFile(url: url)
            store.track("photo_design_shared")
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }
}

/// A design by photo kept on the iPhone: Application Support/PhotoDesigns/<id>/ — source.jpg, v1.jpg…, thumb.jpg, meta.json.
struct PhotoDesignRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var room: String
    var mode: String
    var style: String?
    var wishes: String
    var versions: [String]
    /// Which model drew each variant (older records have none).
    var models: [String]? = nil
}

enum PhotoDesignLibrary {
    static var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("PhotoDesigns", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directory(_ id: UUID) -> URL {
        let url = folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func all() -> [PhotoDesignRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url -> PhotoDesignRecord? in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("meta.json")) else { return nil }
            return try? decoder.decode(PhotoDesignRecord.self, from: data)
        }
        .filter { !$0.versions.isEmpty }
        .sorted { $0.date > $1.date }
    }

    static func save(_ record: PhotoDesignRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: directory(record.id).appendingPathComponent("meta.json"), options: .atomic)
    }

    static func write(_ image: UIImage, name: String, in id: UUID) throws {
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory(id).appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }

    static func writeThumbnail(_ image: UIImage, in id: UUID) throws {
        let side: CGFloat = 360
        let scale = min(1, side / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try write(small, name: "thumb.jpg", in: id)
    }

    static func image(_ name: String, in id: UUID) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(name).path)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}

struct PhotoDesignRow: View {
    let record: PhotoDesignRecord

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumb = PhotoDesignLibrary.image("thumb.jpg", in: record.id) {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Theme.panelRaised
                }
            }
            .frame(width: 76, height: 58).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                let room = PhotoDesignRoom(rawValue: record.room) ?? .other
                let style = record.style.flatMap { id in DesignStyle.all.first { $0.id == id } }
                Text("\(room.title)\(style.map { " · \($0.title)" } ?? "")").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · вариантов: \(record.versions.count)")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .panelCard(16)
    }
}

/// Before / after with a draggable divider.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            ZStack(alignment: .leading) {
                Image(uiImage: after).resizable().scaledToFill().frame(width: width, height: height).clipped()
                Image(uiImage: before).resizable().scaledToFill().frame(width: width, height: height).clipped()
                    .mask(alignment: .leading) { Rectangle().frame(width: max(0, width * split)) }
                Rectangle().fill(.white).frame(width: 2, height: height).offset(x: width * split - 1)
                Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34).background(.white, in: Circle()).shadow(radius: 4)
                    .offset(x: width * split - 17)
                Text("БЫЛО").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top).padding(10)
                Text("СТАЛО").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Theme.sky, in: Capsule()).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / max(1, width)))
            })
        }
    }
}
