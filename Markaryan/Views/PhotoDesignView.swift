import SwiftUI
import PhotosUI
import Photos

/// «Дизайн по фото / Live»: a photo of any part of the house — the AI makes a new design,
/// or changes only what the user wrote. Every result can be corrected again in plain words.
struct PhotoDesignView: View {
    @EnvironmentObject private var store: AppStore
    @State private var source: UIImage?
    @State private var results: [UIImage] = []
    /// Which model drew each variant (the picked one, or the next one when it failed).
    @State private var resultModels: [String] = []
    @State private var showModels = false
    @State private var shown = 0
    @State private var room: PhotoDesignRoom = .kitchen
    @State private var mode: PhotoDesignMode = .redesign
    @State private var style: DesignStyle? = DesignStyle.all[0]
    @State private var wishes = ""
    @State private var correction = ""
    @State private var live = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var shareFile: SharedFile?
    @State private var saved = false
    @State private var addedToProject = false
    @State private var opened: FloorPlanDetailView.PhotoSheetItem?

    private var current: UIImage? { results.indices.contains(shown) ? results[shown] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sourceCard
                if source != nil {
                    settings
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
        .navigationTitle("Дизайн по фото")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in Task { await load(item) } }
        .sheet(isPresented: $showCamera) { CameraCaptureView(image: $captured).ignoresSafeArea() }
        .onChange(of: captured) { _, image in
            guard let image else { return }
            captured = nil
            start(with: image)
            if live { generate() }
        }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .sheet(item: $opened) { item in NavigationStack { RenderResultView(image: item.image, title: "Дизайн · \(room.title)") } }
        .sheet(isPresented: $showModels) { NavigationStack { AIModelsView(showsDesign: false) }.presentationDetents([.medium, .large]) }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ФОТО → НОВЫЙ ДИЗАЙН").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Theme.sky)
            Text("Снимите помещение —\nувидьте его обновлённым").font(.title2.bold())
            Text("Кухня, санузел, комната, балкон или фасад. ИИ сохранит стены, окна и ракурс, а отделку, мебель и свет сделает в выбранном стиле. Потом можно дописывать правки сколько угодно раз.")
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
                        .frame(maxWidth: .infinity).padding(15).foregroundStyle(.black)
                        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(PremiumPressStyle())
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Из галереи", systemImage: "photo.on.rectangle").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(15).foregroundStyle(.white)
                        .panelCard(15, fill: Theme.panelRaised)
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: $live) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live‑режим").font(.subheadline.weight(.semibold))
                    Text("Сделали снимок — дизайн начинается сразу, без лишних нажатий").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.sky)
        }
        .padding(16)
        .panelCard(22)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Что на фото").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoDesignRoom.allCases) { item in
                            Button { Haptics.tap(); room = item } label: {
                                Label(item.title, systemImage: item.icon).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(room == item ? Theme.sky : Theme.panel, in: Capsule())
                                    .foregroundStyle(room == item ? .black : .white)
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
                            .foregroundStyle(mode == item ? .black : .white)
                            .background(mode == item ? Theme.sky : Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(mode == .redesign ? "Стиль" : "Стиль (необязательно)").font(.headline)
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

    private var generateButton: some View {
        PrimaryButton(title: isLoading ? "ИИ работает…" : (results.isEmpty ? "Сделать дизайн" : "Сделать ещё вариант"), icon: "wand.and.stars") { generate() }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1)
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
                    Text("\(room.title)\(style.map { " · \($0.title)" } ?? "")").font(.headline)
                }
                Spacer()
                if results.count > 1 { Text("Вариант \(shown + 1) из \(results.count)").font(.caption).foregroundStyle(Theme.muted) }
            }
            BeforeAfterSlider(before: before, after: after)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture(count: 2) { opened = FloorPlanDetailView.PhotoSheetItem(image: after) }
            Text("Двигайте ползунок: слева — было, справа — стало. Двойное касание — на весь экран.").font(.caption2).foregroundStyle(Theme.muted)
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
                        .frame(maxWidth: .infinity).padding(13).foregroundStyle(.black)
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
        error = nil
        saved = false
        addedToProject = false
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
            if live { generate() }
        } catch { self.error = error.localizedDescription }
    }

    /// A new variant from the source photo.
    private func generate() {
        guard let source else { return }
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
            let prompt = mode.prompt(room: room, style: style, wishesEnglish: english)
            do {
                let result = try await store.photorealRender(base, prompt: prompt)
                withAnimation(.snappy) {
                    results.append(result.image)
                    resultModels.append(result.title)
                    shown = results.count - 1
                }
                store.track("photo_design")
                store.registerMeaningfulAction()
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
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
            try store.addProjectPhoto(image, caption: "Дизайн по фото: \(room.title.lowercased())\(style.map { ", \($0.title.lowercased())" } ?? "")")
            addedToProject = true
            Haptics.success()
        } catch { self.error = error.localizedDescription }
    }

    private func share(_ image: UIImage) {
        guard let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.92) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Дизайн-АртСтрой-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            shareFile = SharedFile(url: url)
            store.track("photo_design_shared")
        } catch { self.error = error.localizedDescription }
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
                Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(.white, in: Circle()).shadow(radius: 4)
                    .offset(x: width * split - 17)
                Text("БЫЛО").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top).padding(10)
                Text("СТАЛО").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Theme.sky, in: Capsule()).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / max(1, width)))
            })
        }
    }
}
