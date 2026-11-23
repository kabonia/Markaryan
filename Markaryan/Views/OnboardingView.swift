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

    private let slides: [(scene: FeatureSceneKind, eyebrow: String, title: String, text: String)] = [
        (.documents, "Сметы", "Смета по проекту —\nкак у сметчика.", "Загрузите АР, КР, ТЗ или Excel: объёмы, материалы с нормами расхода и цены вашего города со ссылками на источники."),
        (.design, "Дизайн и ИИ", "Увидьте ремонт\nдо его начала.", "Сфотографируйте комнату или фасад — ИИ покажет их в новом стиле, с вашими материалами и сметой."),
        (.ar, "Замеры и расчёты", "Измерьте камерой.\nПосчитайте за минуту.", "AR‑рулетка, калькуляторы материалов и счёт арматуры по фото — без рулетки и таблиц.")
    ]
    private var last: Int { slides.count }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    AppMark(size: 34)
                    Text(Brand.name).font(.system(.headline, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    if page < last { Button("Пропустить") { finish() }.font(.subheadline).foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 24).padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { index in slide(slides[index], active: page == index).tag(index) }
                    personalize.tag(last)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: page)

                HStack(spacing: 7) {
                    ForEach(0...last, id: \.self) { index in
                        Capsule().fill(index == page ? AnyShapeStyle(Lux.goldGradient) : AnyShapeStyle(Theme.muted.opacity(0.3))).frame(width: index == page ? 26 : 7, height: 7)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 18)

                PrimaryButton(title: page < last ? "Далее" : "Начать работу", icon: page < last ? "arrow.right" : "checkmark") {
                    if page < last { page += 1 } else { finish() }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
    }

    private func slide(_ item: (scene: FeatureSceneKind, eyebrow: String, title: String, text: String), active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureScene(kind: item.scene)
                .frame(maxWidth: .infinity).frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 1))
                .shadow(color: Theme.ink.opacity(0.22), radius: 24, y: 14)
                .scaleEffect(active ? 1 : 0.94)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: active)
                .padding(.top, 14)
            HStack(spacing: 8) {
                Rectangle().fill(Theme.goldHairline).frame(width: 18, height: 1)
                Text(item.eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.gold)
            }
            .padding(.top, 8)
            Text(item.title).font(.system(size: 32, weight: .bold, design: .serif)).tracking(-0.6).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.text).font(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var personalize: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ВАШ ОБЪЕКТ").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.orange).padding(.top, 40)
                Text("Что строим?").font(.system(size: 32, weight: .bold, design: .serif)).tracking(-0.6).foregroundStyle(Theme.ink)
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
