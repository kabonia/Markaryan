import SwiftUI

/// Выбор объекта: «Сохранить в объект» из любого места; можно сразу создать новый.
struct ObjectPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    var current: UUID? = nil
    let onPick: (UUID) -> Void
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Новый объект, например «Дача»", text: $newName)
                    Button("Создать") {
                        let id = store.addObject(name: newName)
                        onPick(id); Haptics.success(); dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !store.objects.isEmpty {
                Section("Мои объекты") {
                    ForEach(store.objects) { object in
                        Button {
                            onPick(object.id); Haptics.success(); dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "building.2.fill").foregroundStyle(Theme.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(object.passport.name.isEmpty ? "Мой объект" : object.passport.name).foregroundStyle(Theme.ink)
                                    if !object.passport.address.isEmpty { Text(object.passport.address).font(.caption).foregroundStyle(Theme.muted) }
                                }
                                Spacer()
                                if object.id == current { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
    }
}

/// Кнопка «В объект» / «В объекте «Дача»» для результата вне плана комнаты.
struct SaveToObjectButton: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var links = ObjectLinks.shared
    let kind: ObjectLinks.Kind
    let id: String
    let title: String
    var subtitle: String? = nil
    @State private var picking = false

    var body: some View {
        let current = links.object(of: kind, id: id)
        Button { picking = true } label: {
            SecondaryActionLabel(title: store.objectName(current).map { "В объекте «\($0)»" } ?? "Сохранить в объект", icon: current == nil ? "folder.badge.plus" : "folder.fill")
        }
        .buttonStyle(PremiumPressStyle())
        .sheet(isPresented: $picking) {
            NavigationStack {
                ObjectPickerSheet(title: "В какой объект", current: current) { object in
                    links.link(kind, id: id, to: object, title: title, subtitle: subtitle)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { links.autoLink(kind, id: id, title: title, subtitle: subtitle, store: store) }
    }
}

/// На главной: где сейчас сохраняется работа — в объекте или «без объекта»; переключение одним нажатием.
struct ObjectContextChip: View {
    @EnvironmentObject private var store: AppStore
    @State private var newObject = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Button { store.workWithoutObject() } label: {
                Label("Без объекта", systemImage: store.inObject ? "tray" : "checkmark")
            }
            ForEach(store.objects) { object in
                Button { store.selectProject(object.id) } label: {
                    Label(object.passport.name.isEmpty ? "Мой объект" : object.passport.name,
                          systemImage: object.id == store.activeProjectID ? "checkmark" : "building.2")
                }
            }
            Divider()
            Button { newObject = true } label: { Label("Новый объект", systemImage: "plus") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.inObject ? "building.2.fill" : "tray.fill").font(.caption)
                Text(store.inObject ? store.projectDisplayName : "Без объекта".tr).font(.caption.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(store.inObject ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(store.inObject ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.panel), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.goldHairline, lineWidth: 0.8))
        }
        .accessibilityLabel(store.inObject ? "Объект: \(store.projectDisplayName)" : "Работа без объекта")
        .alert("Новый объект", isPresented: $newObject) {
            TextField("Например, дача", text: $newName)
            Button("Создать") { store.createProject(name: newName, address: ""); newName = "" }
            Button("Отмена", role: .cancel) { newName = "" }
        } message: { Text("Всё, что вы сделаете дальше, сохранится в этот объект.") }
    }
}

/// В объекте: всё, что к нему добавлено — обмеры дома, сметы, расчёты, картинки. Долгое нажатие — убрать из объекта.
struct ObjectLinkedItems: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var links = ObjectLinks.shared
    @State private var openedScan: HouseScanUploader.Remote?
    @State private var loadingScan = false

    var body: some View {
        if let object = store.activeProjectID, store.inObject, links.count(in: object) > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("ДОБАВЛЕНО В ОБЪЕКТ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(ObjectLinks.Kind.allCases, id: \.self) { kind in
                    let items = links.items(in: object, kind: kind)
                    if !items.isEmpty {
                        Text(kind.title.tr).font(.caption).foregroundStyle(Theme.muted).padding(.top, 2)
                        ForEach(items) { item in row(item, kind: kind) }
                    }
                }
            }
            .sheet(item: $openedScan) { scan in
                NavigationStack {
                    HouseResultView(scan: scan)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { openedScan = nil } } }
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: ObjectLinks.Link, kind: ObjectLinks.Kind) -> some View {
        let label = AppTabRow(icon: kind.icon, title: item.title, subtitle: item.subtitle ?? item.addedAt.formatted(date: .abbreviated, time: .omitted))
        Group {
            switch kind {
            case .calculation:
                if let calc = store.calculations.first(where: { $0.id.uuidString == item.itemID }) {
                    NavigationLink { SavedCalculationView(item: calc) } label: { label }
                } else { label }
            case .houseScan:
                Button { Task { await openScan(item.itemID) } } label: { label }
            case .docEstimate:
                NavigationLink { DocEstimateResultLoader(id: item.itemID) } label: { label }
            case .picture:
                if let image = ObjectPictures.load(item.itemID) {
                    NavigationLink { RenderResultView(image: image, title: item.title) } label: { label }
                } else { label }
            }
        }
        .buttonStyle(PremiumCardPressStyle())
        .contextMenu {
            Button(role: .destructive) { links.unlink(kind, id: item.itemID) } label: { Label("Убрать из объекта", systemImage: "folder.badge.minus") }
        }
    }

    private func openScan(_ id: String) async {
        guard let uploader = HouseScanUploader(), let list = try? await uploader.list() else { return }
        openedScan = list.first { $0.id == id && $0.result != nil }
    }
}

/// Картинки, сохранённые в объект (визуализации комнат и домов).
enum ObjectPictures {
    private static func url(_ id: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("ObjectPictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(id).jpg")
    }
    static func save(_ image: UIImage) -> String {
        let id = UUID().uuidString
        if let url = url(id), let data = image.jpegData(compressionQuality: 0.85) { try? data.write(to: url) }
        return id
    }
    static func load(_ id: String) -> UIImage? { url(id).flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:)) }
}

/// «Сохранить картинку в объект»: копия в телефоне + ссылка в объекте.
struct SavePictureToObjectButton: View {
    @EnvironmentObject private var store: AppStore
    let image: UIImage
    let title: String
    @State private var picking = false
    @State private var savedTo: String?

    var body: some View {
        Button { picking = true } label: {
            SecondaryActionLabel(title: savedTo.map { "Сохранено в «\($0)»" } ?? "Сохранить картинку в объект", icon: savedTo == nil ? "folder.badge.plus" : "checkmark")
        }
        .buttonStyle(PremiumPressStyle())
        .sheet(isPresented: $picking) {
            NavigationStack {
                ObjectPickerSheet(title: "В какой объект") { object in
                    let id = ObjectPictures.save(image)
                    ObjectLinks.shared.link(.picture, id: id, to: object, title: title)
                    savedTo = store.objectName(object)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
