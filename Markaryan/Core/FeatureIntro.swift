import SwiftUI

// MARK: - First-use explanations: what a function does and how to use it, until «Больше не показывать»

enum FeatureIntro: String, CaseIterable, Identifiable {
    case home, estimates, docEstimate, fullEstimate, calculators, calculator, design, photoDesign, facade, ar, photoCount, project, billing, marketEstimate
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .estimates: "doc.text.fill"
        case .docEstimate: "doc.text.magnifyingglass"
        case .fullEstimate: "house"
        case .calculators, .calculator: "function"
        case .design: "cube.transparent"
        case .photoDesign: "camera.aperture"
        case .facade: "building.2"
        case .ar: "ruler"
        case .photoCount: "square.stack.3d.up"
        case .project: "folder.fill"
        case .billing: "creditcard.fill"
        case .marketEstimate: "chart.bar.doc.horizontal"
        }
    }

    var title: String {
        switch self {
        case .home: "Добро пожаловать в СметаПро"
        case .estimates: "Сметы"
        case .docEstimate: "Смета по документам"
        case .fullEstimate: "Типовая смета объекта"
        case .calculators: "Калькуляторы материалов"
        case .calculator: "Как считать калькулятором"
        case .design: "Дизайн помещения"
        case .photoDesign: "Дизайн по фото"
        case .facade: "Фасад и участок"
        case .ar: "AR‑рулетка"
        case .photoCount: "Счёт по фото"
        case .project: "Мой объект"
        case .billing: "Тарифы и баланс"
        case .marketEstimate: "Смета по рыночным ценам"
        }
    }

    var summary: String {
        switch self {
        case .home: "Приложение для тех, кто строит и ремонтирует: сметы по проекту, дизайн интерьера, расчёт материалов и замеры камерой."
        case .estimates: "Все способы узнать стоимость работ и материалов: по документам, по площади или по сохранённым расчётам."
        case .docEstimate: "Профессиональная смета по вашим документам: объёмы работ, материалы с нормами расхода и цены вашего города со ссылками на источники."
        case .fullEstimate: "Быстрая смета дома, беседки или металлоконструкции по площади — когда документов ещё нет."
        case .calculators: "Сколько материала нужно и сколько он стоит: бетон, плитка, кладка, кровля, штукатурка и другое."
        case .calculator: "Введите размеры — калькулятор посчитает количество с запасом, упаковки и стоимость."
        case .design: "Отсканируйте помещение лидаром или сфотографируйте — получите план, стиль, фотореалистичные визуализации, чертежи и смету дизайн‑проекта."
        case .photoDesign: "Сфотографируйте комнату, кухню или санузел — ИИ покажет её в новом стиле или изменит только то, что вы напишете."
        case .facade: "Визуализация дома снаружи: фасад, крыша, забор, ландшафт — по фото участка или по описанию."
        case .ar: "Измерение длин, площадей и периметра камерой iPhone — без рулетки."
        case .photoCount: "Сфотографируйте торцы арматуры, труб, досок или бруса — ИИ посчитает штуки в пачке."
        case .project: "Всё о вашем объекте: этапы, бюджет план/факт, задачи, фото скрытых работ и журнал решений."
        case .billing: "Баланс кредитов, подписка и цены платных функций. Калькуляторы, замеры и типовые сметы — бесплатно."
        case .marketEstimate: "Стоимость дизайн‑проекта по реальным ценам магазинов и мастеров вашего города: материалы и работы с вилкой цен."
        }
    }

    var steps: [String] {
        switch self {
        case .home: ["Большая карточка — дизайн по фото: снимите комнату и увидите её в новом стиле.", "«Инструменты»: смета по документам, дизайн комнаты, AR‑рулетка, счёт по фото, помощник, смета дома.", "«Калькуляторы» — быстрый расчёт материалов.", "Внизу — вкладки: Смета, Дизайн, Проект, Профиль.", "Баланс кредитов и пополнение — справа вверху."]
        case .estimates: ["Есть документы (АР, КР, ТЗ, Excel) — «Смета по документам».", "Документов нет — «Типовая смета объекта» по площади.", "Всё сохранённое — в «Мои расчёты»."]
        case .docEstimate: ["Нажмите «Новая смета» и загрузите PDF, Excel, фото листов или напишите список работ.", "Для каждого файла выберите тип: АР, КР, ТЗ, смета или другое.", "Проверьте город и начисления (НДС, доставка, непредвиденные) и нажмите «Рассчитать».", "Расчёт идёт 5–15 минут — можно свернуть приложение, придёт уведомление.", "Готовую смету откройте в «Мои сметы»: разделы, закупка материалов, основания, PDF и Excel."]
        case .fullEstimate: ["Выберите тип объекта.", "Укажите площадь, этажность и запас.", "Отключите ненужные разделы — итог пересчитается.", "Сохраните или отправьте PDF."]
        case .calculators: ["Найдите калькулятор поиском или в разделах.", "Введите размеры — можно взять их из AR‑рулетки.", "Нажмите «Рассчитать» и сохраните результат."]
        case .calculator: ["Заполните поля — единицы указаны справа.", "Запас на подрезку уже предложен, его можно изменить.", "Цена необязательна: без неё посчитается только количество.", "После расчёта — PDF, сохранение и отправка."]
        case .design: ["Нажмите «Сканировать помещение» (iPhone с лидаром) или выберите «Фото / Live».", "Проверьте план: стены, окна, двери — их можно поправить.", "На шаге «Дизайн» выберите стиль и назначение помещения.", "На шаге «Результат» — визуализации, PDF‑презентация, чертежи и смета по рынку.", "Можно добавить свои материалы и товары — плитку, сантехнику, фасад — ИИ поставит именно их."]
        case .photoDesign: ["Снимите помещение или выберите фото из галереи.", "Укажите, что на фото, и режим: новый дизайн или только правки.", "Выберите стиль, напишите пожелания, при желании добавьте свои материалы.", "Нажмите «Сгенерировать» — через минуту будет вариант; можно уточнять словами."]
        case .facade: ["Загрузите фото дома или участка или опишите идею.", "Выберите стиль и что изменить.", "Получите визуализацию и уточняйте словами."]
        case .ar: ["Медленно поведите телефоном по полу, пока не появится сетка.", "Наведите центр экрана на начало и нажмите «+».", "Поставьте следующую точку — появится длина; замкните контур для площади.", "Размер можно сразу передать в калькулятор. Перепроверяйте рулеткой перед закупкой."]
        case .photoCount: ["Снимите пачку строго с торца, при хорошем свете.", "Выберите, что считать, — ИИ отметит каждую штуку.", "Касанием добавьте или уберите метку, если ИИ ошибся."]
        case .project: ["Заполните паспорт объекта: адрес, площадь, этап.", "Ведите бюджет план/факт и задачи.", "Фотографируйте скрытые работы — фото‑дневник пригодится при приёмке."]
        case .billing: ["Кредиты списываются только за функции ИИ — цена указана в списке ниже.", "Если ИИ не справился, кредиты возвращаются автоматически.", "Пополнить баланс или оформить подписку можно на этом экране."]
        case .marketEstimate: ["Смета считается по материалам и площадям вашей концепции.", "У каждой цены — пример товара и ссылки на источники.", "«Обычно» — типичная цена; вилка — от недорогих до дорогих предложений.", "Отправьте смету или запросите цену у партнёров."]
        }
    }

    var tip: String? {
        switch self {
        case .docEstimate: "Чем полнее документы — планы с размерами, разрезы, спецификации, ведомости проёмов и отделки, — тем точнее смета."
        case .design: "Помощник — кнопка со звёздочкой — подскажет на любом шаге."
        case .ar: "AR‑замер приблизительный: для закупки и разметки перепроверяйте рулеткой."
        default: nil
        }
    }

    private var key: String { "intro.hidden.\(rawValue)" }
    var hidden: Bool { UserDefaults.standard.bool(forKey: key) }
    func hideForever() { UserDefaults.standard.set(true, forKey: key) }
    /// «Понятно» hides it until the next launch.
    static var seenThisLaunch: Set<String> = []
}

struct FeatureIntroSheet: View {
    let intro: FeatureIntro
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(intro.title).font(.system(size: 30, weight: .bold, design: .serif)).tracking(-0.5).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(intro.summary).font(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Rectangle().fill(Theme.goldHairline).frame(width: 18, height: 1)
                            Text("КАК ПОЛЬЗОВАТЬСЯ").font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(Theme.gold)
                        }
                        .padding(.bottom, 14)
                        ForEach(Array(intro.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(index: index, text: step, last: index == intro.steps.count - 1)
                                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                                .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.15 + Double(index) * 0.07), value: appeared)
                        }
                    }

                    if let tip = intro.tip {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.max.fill").font(.headline).foregroundStyle(Theme.gold)
                            Text(tip).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.goldTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.gold.opacity(0.25), lineWidth: 0.8))
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: appeared)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { actions }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.08)) { appeared = true } }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            FeatureScene(kind: intro.scene).frame(height: 320)
            HStack(spacing: 8) {
                Image(systemName: intro.icon).font(.caption.weight(.bold))
                Text("ПОДСКАЗКА · \(Brand.name.uppercased())").font(.caption2.weight(.heavy)).tracking(1.4)
            }
            .foregroundStyle(Theme.goldLight)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.goldLight.opacity(0.35), lineWidth: 0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 26).padding(.leading, 20)
        }
        .frame(height: 320)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.18), radius: 18, y: 10)
    }

    private func stepRow(index: Int, text: String, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text("\(index + 1)").font(.system(.subheadline, design: .serif, weight: .bold)).foregroundStyle(Theme.goldLight)
                    .frame(width: 32, height: 32)
                    .background(Theme.heroGradient, in: Circle())
                    .overlay(Circle().strokeBorder(Lux.goldGradient, lineWidth: 1))
                    .shadow(color: Theme.orange.opacity(0.25), radius: 6, y: 3)
                if !last {
                    Rectangle().fill(LinearGradient(colors: [Theme.gold.opacity(0.45), Theme.gold.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.2).frame(maxHeight: .infinity)
                }
            }
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6).padding(.bottom, last ? 0 : 18)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            PrimaryButton(title: "Понятно, начнём", icon: "arrow.right") { dismiss() }
            Button { intro.hideForever(); dismiss() } label: {
                Text("Больше не показывать").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 24).padding(.top, 14)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background, Theme.background], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

private struct FeatureIntroModifier: ViewModifier {
    let intro: FeatureIntro
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shown = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Как пользоваться")
                }
            }
            .sheet(isPresented: $shown) { FeatureIntroSheet(intro: intro) }
            .task {
                #if DEBUG
                if ScreenshotRoute.current != nil { return }
                #endif
                guard !intro.hidden, !FeatureIntro.seenThisLaunch.contains(intro.rawValue), UserDefaults.standard.bool(forKey: "onboardingCompleted") else { return }
                FeatureIntro.seenThisLaunch.insert(intro.rawValue)
                try? await Task.sleep(for: .milliseconds(450))
                shown = true
            }
    }
}

extension View {
    /// Shows the explanation of this function on entry until the person taps «Больше не показывать»; «?» opens it again.
    func featureIntro(_ intro: FeatureIntro) -> some View { modifier(FeatureIntroModifier(intro: intro)) }
}
