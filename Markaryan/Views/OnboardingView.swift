import SwiftUI

/// First‑launch introduction: three short screens that show the value of the app
/// and personalise it with the name and district of the user's object.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    let onFinish: () -> Void
    @State private var page = 0
    @State private var objectName = ""
    @State private var district = ""
    @FocusState private var focused: Bool

    private let slides: [(icon: String, eyebrow: String, title: String, text: String)] = [
        ("function", "Смета за минуту", "Посчитайте стройку\nдо первого рубля.", "14 калькуляторов материалов и полная смета дома, беседки или металлоконструкций — по рыночным ценам вашего города."),
        ("viewfinder", "AR и ИИ", "Измерьте камерой.\nУвидьте результат.", "Замеряйте площадь в AR, размещайте макет плиты или дома на участке и получайте визуализацию будущего объекта.")
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Circle().fill(Theme.orange.opacity(0.13)).frame(width: 380, height: 380).blur(radius: 50).offset(x: 140, y: -300)
            VStack(spacing: 0) {
                HStack {
                    AppMark(size: 34)
                    Text(Brand.name).font(.headline)
                    Spacer()
                    if page < 2 { Button("Пропустить") { finish() }.font(.subheadline).foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 24).padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { index in slide(slides[index]).tag(index) }
                    personalize.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: page)

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(index == page ? Theme.orange : Theme.muted.opacity(0.35)).frame(width: index == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 18)

                PrimaryButton(title: page < 2 ? "Далее" : "Начать работу", icon: page < 2 ? "arrow.right" : "checkmark") {
                    if page < 2 { page += 1 } else { finish() }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
    }

    private func slide(_ item: (icon: String, eyebrow: String, title: String, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: item.icon).font(.system(size: 42, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .frame(width: 92, height: 92)
                .background(Theme.orange, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Theme.orange.opacity(0.35), radius: 24, y: 10)
            Text(item.eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.orange).padding(.top, 10)
            Text(item.title).font(.system(.largeTitle, weight: .bold)).tracking(-1)
            Text(item.text).font(.body).foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var personalize: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ВАШ ОБЪЕКТ").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.orange).padding(.top, 40)
                Text("Что строим?").font(.system(.largeTitle, weight: .bold)).tracking(-1)
                Text("Название и район подставятся в сметы, PDF и чертежи. Данные хранятся на вашем iPhone.").foregroundStyle(Theme.muted)
                VStack(spacing: 12) {
                    TextField("Например, дом в Хосте", text: $objectName).focused($focused).padding(16).fieldSurface(15)
                    TextField("Район: Адлер, Хоста, Дагомыс…", text: $district).focused($focused).padding(16).fieldSurface(15)
                }
                HStack(spacing: 8) {
                    ForEach(["Дом", "Баня", "Беседка", "Ремонт"], id: \.self) { preset in
                        Button(preset) { objectName = preset; Haptics.tap() }
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(objectName == preset ? Theme.orange : Theme.panel, in: Capsule()).overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                            .foregroundStyle(objectName == preset ? Theme.onAccent : Theme.ink)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func finish() {
        focused = false
        let name = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = district.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.passport.name = name }
        if !place.isEmpty { store.passport.address = place }
        store.track("onboarding_done")
        Haptics.success()
        onFinish()
    }
}
