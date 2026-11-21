import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var favoritesOnly = false
    var filtered: [BuildingProject] { store.projects.filter { !favoritesOnly || store.favorites.contains($0.id) } }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(eyebrow: "Портфолио", title: "Мои работы")
            Text("Компактная подборка объектов. Откройте карточку, чтобы посмотреть фотографии и состав работ.").font(.subheadline).foregroundStyle(Theme.muted)
            Picker("Объекты", selection: $favoritesOnly) { Text("Все объекты").tag(false); Text("Избранное").tag(true) }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(filtered) { project in
                    NavigationLink { ProjectDetail(project: project) } label: { ProjectTile(project: project, favorite: store.favorites.contains(project.id)) }.buttonStyle(.plain)
                }
            }
            if filtered.isEmpty { ContentUnavailableView("Сохраните понравившийся объект", systemImage: "heart", description: Text("Нажмите на сердце в карточке проекта.")) }
        }.padding(20) }.background(Theme.background).navigationTitle("Объекты")
    }
}
struct ProjectTile: View {
    let project: BuildingProject
    let favorite: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(project.photos.first ?? "photo-0").resizable().scaledToFill().frame(height: 126).frame(maxWidth: .infinity).clipped()
                if favorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.orange).padding(8).background(.black.opacity(0.55), in: Circle()).padding(8) }
            }.clipShape(RoundedRectangle(cornerRadius: 16))
            Text(project.location).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            Text(project.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2).frame(minHeight: 36, alignment: .topLeading)
            Text(project.tag).font(.caption2.weight(.medium)).foregroundStyle(Theme.orange).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).panelCard(20)
    }
}
struct ProjectDetail: View {
    @EnvironmentObject private var store: AppStore
    let project: BuildingProject
    @State private var selectedPhoto: PhotoItem?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(eyebrow: project.location, title: project.name)
            ForEach(project.photos, id: \.self) { photo in
                Button { selectedPhoto = PhotoItem(name: photo) } label: { Image(photo).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain).accessibilityLabel("Увеличить фотографию объекта")
            }
            Text("Выполненные работы").font(.title2.bold())
            ForEach(project.works, id: \.self) { Label($0, systemImage: "checkmark").foregroundStyle(Theme.muted) }
            PrimaryButton(title: "Хочу похожий объект", icon: "square.and.pencil") { store.appendToRequest("Интересует объект, похожий на: \(project.name).") }
            Link(destination: Brand.whatsAppURL(text: "Здравствуйте! Увидел в приложении ваш объект «\(project.name)». Хочу обсудить похожий.")) { SecondaryActionLabel(title: "Обсудить в WhatsApp", icon: "message.fill") }.buttonStyle(PremiumPressStyle())
        }.padding(20) }.background(Theme.background).navigationTitle("Проект").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { store.toggleFavorite(project.id) } label: { Image(systemName: store.favorites.contains(project.id) ? "heart.fill" : "heart") }.accessibilityLabel(store.favorites.contains(project.id) ? "Убрать из избранного" : "Добавить в избранное") }
            .sheet(item: $selectedPhoto) { photo in NavigationStack { ZoomPhoto(name: photo.name).toolbar { Button("Закрыть") { selectedPhoto = nil } } } }
    }
}
struct PhotoItem: Identifiable { let name: String; var id: String { name } }
struct ZoomPhoto: View {
    let name: String
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Image(name).resizable().scaledToFit()
                    .frame(width: proxy.size.width * scale)
                    .frame(minHeight: proxy.size.height)
                    .gesture(MagnifyGesture()
                        .onChanged { scale = min(4, max(1, baseScale * $0.magnification)) }
                        .onEnded { _ in baseScale = scale })
                    .onTapGesture(count: 2) { withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5; baseScale = scale } }
                    .accessibilityLabel("Фотография. Разведите пальцы или коснитесь дважды, чтобы увеличить.")
            }
        }
        .background(.black)
        .safeAreaInset(edge: .bottom) { HStack { Button("Уменьшить") { scale = max(1, scale - 0.5); baseScale = scale }; Spacer(); Button("Увеличить") { scale = min(4, scale + 0.5); baseScale = scale } }.padding().background(.ultraThinMaterial) }
    }
}
