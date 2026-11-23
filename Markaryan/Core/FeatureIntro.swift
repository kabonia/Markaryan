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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: intro.icon).font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.goldLight)
                    .frame(width: 60, height: 60).background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(intro.title).font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
                Text(intro.summary).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text("КАК ПОЛЬЗОВАТЬСЯ").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold)
                    ForEach(Array(intro.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.system(.subheadline, design: .serif, weight: .bold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 26, height: 26).background(Theme.orange, in: Circle())
                            Text(step).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
                if let tip = intro.tip {
                    Label(tip, systemImage: "lightbulb").font(.footnote).foregroundStyle(Theme.muted)
                }
                PrimaryButton(title: "Понятно", icon: "checkmark") { dismiss() }
                Button { intro.hideForever(); dismiss() } label: {
                    Text("Больше не показывать").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(24)
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
