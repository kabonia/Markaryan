import SwiftUI
import AVFoundation

// MARK: - First-use explanations: what a function does and how to use it, until «Больше не показывать»

enum FeatureIntro: String, CaseIterable, Identifiable {
    case home, estimates, docEstimate, fullEstimate, calculators, calculator, design, photoDesign, facade, ar, photoCount, project, billing, marketEstimate, houseScan
    case acceptance, quoteCheck, receipt, photoRoom
    case roomScan, roomMaterials, purchase, houseEstimate, metalEstimate, houseResult, parcel, apartment, support
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
        case .houseScan: "house.lodge"
        case .acceptance: "checkmark.seal.fill"
        case .quoteCheck: "checkmark.shield.fill"
        case .receipt: "receipt.fill"
        case .photoRoom: "camera.aperture"
        case .roomScan: "camera.metering.matrix"
        case .roomMaterials: "shippingbox.fill"
        case .purchase: "cart.fill"
        case .houseEstimate: "house.fill"
        case .metalEstimate: "square.3.layers.3d"
        case .houseResult: "house.lodge.fill"
        case .parcel: "map.fill"
        case .apartment: "building.fill"
        case .support: "bubble.left.and.bubble.right.fill"
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
        case .houseScan: "3D‑обмер дома"
        case .acceptance: "Приёмка без приёмщика"
        case .quoteCheck: "Проверка сметы подрядчика"
        case .receipt: "Чек → в бюджет"
        case .photoRoom: "Размеры и материалы по фото"
        case .roomScan: "Скан комнаты"
        case .roomMaterials: "Материалы, цены и визуализация"
        case .purchase: "Закупка объекта"
        case .houseEstimate: "Смета дома"
        case .metalEstimate: "Металлоконструкции"
        case .houseResult: "Макет дома"
        case .parcel: "Участок по кадастру"
        case .apartment: "Квартира целиком"
        case .support: "Поддержка"
        }
    }

    var summary: String {
        switch self {
        case .home: "Приложение для тех, кто строит и ремонтирует: сметы по проекту, дизайн интерьера, расчёт материалов и замеры камерой."
        case .estimates: "Все способы узнать стоимость работ и материалов: по документам, по площади или по сохранённым расчётам."
        case .docEstimate: "Профессиональная смета по вашим документам: объёмы работ, материалы с нормами расхода и цены вашего города со ссылками на источники."
        case .fullEstimate: "Смета дома или металлоконструкций по параметрам: размеры, материалы и реальные цены вашего города — когда документов ещё нет."
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
        case .houseScan: "Обойдите дом с iPhone — получите 3D‑модель с точными размерами стен и крыши, площади кровли и фасадов для сметы и проверку дома по границам участка из Росреестра."
        case .acceptance: "Проверьте ремонт или новостройку сами: лидар меряет ровность по нормам СП, ИИ находит дефекты на фото, в конце — акт осмотра."
        case .quoteCheck: "Сфотографируйте смету подрядчика — сверим каждую строку с ценами города и покажем переплату и забытое."
        case .receipt: "Сфотографируйте чек — сумма сама попадёт в траты объекта, перерасход виден сразу."
        case .photoRoom: "Нет лидара — размеры комнаты по фото, дальше материалы, цены и визуализация."
        case .roomScan: "Обойдите комнату с iPhone — получите точный план со стенами, окнами и дверями за минуту."
        case .roomMaterials: "Сколько купить плитки, клея, штукатурки и краски для этой комнаты — с ценами и картинкой с этой отделкой."
        case .purchase: "Все материалы объекта одним списком: одинаковое сложено, цены со ссылками, отметки «куплено»."
        case .houseEstimate: "Полная смета частного дома по размерам и материалам — по реальным ценам вашего города."
        case .metalEstimate: "Смета навеса, ангара или каркаса из металла по размерам — металл, работа и монтаж."
        case .houseResult: "Готовый 3D‑обмер: размеры, крыша, окна, площади — и сразу смета, визуализация и отправка."
        case .parcel: "Граница, площадь, вид разрешённого использования из Росреестра и проверка отступов дома."
        case .apartment: "Все комнаты квартиры вместе: общий план, площади и чертежи на всю квартиру."
        case .support: "Что‑то не работает или оплатили и не получили — напишите менеджеру, ответ придёт сюда."
        }
    }

    var steps: [String] {
        switch self {
        case .home: ["Большая карточка — дизайн по фото: снимите комнату и увидите её в новом стиле.", "«Инструменты»: 3D‑обмер дома, смета по документам, дизайн комнаты, AR‑рулетка, счёт по фото, помощник, смета дома.", "«Калькуляторы» — быстрый расчёт материалов.", "Внизу — вкладки: Смета, Дизайн, Проект, Профиль.", "Баланс кредитов и пополнение — справа вверху."]
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
        case .project: ["Выберите объект вверху или создайте новый — всё дальше сохранится в нём.", "«Деньги»: впишите свой бюджет — увидите, укладывается ли смета и где перерасход.", "«Этапы» показывают, что сделано: обмер, материалы, смета, дизайн, закупка, приёмка, работы.", "Скажите голосом: «Потратил 20 тысяч на плитку» или «Задача купить клей».", "Пригласите супруга или прораба по коду — правки видят все."]
        case .billing: ["Кредиты списываются только за функции ИИ — цена указана в списке ниже.", "Если ИИ не справился, кредиты возвращаются автоматически.", "Пополнить баланс или оформить подписку можно на этом экране."]
        case .houseScan: [
            "По желанию сначала «Участок по кадастру» → «Я на участке»: граница, площадь и ВРИ из Росреестра.",
            "«Начать обход»: идите вокруг дома в 4–8 м от стен, камера — на стены. Кольцо вверху показывает, что уже снято.",
            "Второй круг — дальше от дома, камеру поднимите на крышу и фронтоны. Подсказка скажет, если что‑то пропущено.",
            "«Готово» — введите длину одной стены, измеренную рулеткой: так проверим точность.",
            "Через 1–3 минуты макет в «Мои обмеры»: размеры с метками «измерено / по фото», крыша, площади, отступы от границ.",
        ]
        case .marketEstimate: ["Смета считается по материалам и площадям вашей концепции.", "У каждой цены — пример товара и ссылки на источники.", "«Обычно» — типичная цена; вилка — от недорогих до дорогих предложений.", "Отправьте смету или запросите цену у партнёров."]
        case .acceptance: ["Впишите комнату и выберите, что проверяете: стену, пол или потолок.", "Встаньте в метре, держите телефон неподвижно и нажмите «Измерить» — появится цветная карта.", "Зелёное — в норме, красное — горб, синее — яма. Цифры в мм рядом с нормой.", "Снимите подозрительные места — ИИ отметит дефекты на фото.", "«Акт осмотра» — PDF для застройщика или бригады; замечания станут задачами."]
        case .quoteCheck: ["Сфотографируйте смету подрядчика или загрузите PDF — до 4 страниц.", "Нажмите «Проверить смету» — ИИ перепишет строки и найдёт цены города.", "Красное — завышено, зелёное — в рынке; сверху — сумма переплаты.", "«Возможно, забыли» — что спросить у подрядчика. «Отправить разбор» — для торга."]
        case .receipt: ["Нажмите «Снять чек» и сфотографируйте его целиком.", "«Прочитать чек» — ИИ найдёт магазин, сумму и статью бюджета.", "Проверьте статью и нажмите «Добавить в „Потрачено“» — бюджет объекта обновится."]
        case .photoRoom: ["Снимите комнату из угла, чтобы были видны пол, потолок и дверь.", "«Оценить размеры» — ИИ посчитает длину, ширину и высоту.", "Поправьте цифры, если мерили рулеткой, и нажмите «Создать комнату».", "Откроется комната с материалами, ценами и визуализацией."]
        case .roomScan: ["Встаньте в центре, нажмите «Начать» и медленно поверните телефон по кругу.", "Наведите камеру на все стены, окна и двери — они появятся на плане.", "Пропущенное место подсветится — подойдите и доснимите.", "«Готово» — откроется комната: размеры, материалы, цены и дизайн на одной странице."]
        case .roomMaterials: ["Выберите тип помещения — работы подставятся сами.", "Включите нужные работы и формат плитки — материалы посчитаются сразу.", "«Цены в вашем городе» — у каждой позиции ссылка на магазин.", "«Показать комнату с этой отделкой» — картинка и шторка «до / после».", "«Отправить» — список с ценами; «В бюджет объекта» — сумма в план."]
        case .purchase: ["Материалы приходят из комнат с открытым расчётом и из расчётов, добавленных в объект.", "Коснитесь строки, когда купили, — она зачеркнётся.", "«Цены в вашем городе» — эконом, средний и премиум, ссылки на магазины.", "«Отправить список» — в мессенджер себе или прорабу."]
        case .houseEstimate: ["Укажите длину, ширину и этажность.", "Выберите фундамент, стены, кровлю, фасад и отделку кнопками.", "«Рассчитать смету» — разделы, материалы, работы и диапазон рынка.", "Ниже — «Дом с этой отделкой»: картинка с выбранными фасадом и кровлей."]
        case .metalEstimate: ["Выберите тип конструкции и укажите размеры.", "Отметьте покрытие и окраску.", "«Рассчитать» — тонны металла, работа, монтаж и цены города."]
        case .houseResult: ["Крутите 3D‑модель пальцем — выберите ракурс для картинки.", "«Смета по этим размерам»: выберите стены, фасад и кровлю — и «Посчитать смету».", "«Показать дом с этой отделкой» — картинка по вашей модели, шторка «до / после».", "Ниже — размеры с метками «измерено / по фото», крыша, окна и площади для сметы.", "«Сохранить в объект» и «Отправить размеры и смету»."]
        case .parcel: ["Нажмите «Я на участке» или введите кадастровый номер.", "Проверьте границу на карте и площадь.", "После 3D‑обмера дом встанет на участок — проверим отступы от границ."]
        case .apartment: ["Отсканируйте комнаты по очереди — они соберутся в квартиру.", "Поправьте расположение комнат, если нужно.", "Откройте общий план и чертежи на всю квартиру."]
        case .support: ["Нажмите «Новое обращение» и выберите тему и функцию.", "Опишите, что случилось, при желании приложите снимок экрана.", "Ответ менеджера появится здесь — на вкладке «Профиль» загорится значок.", "Если функция сломалась по нашей вине — вернём кредиты."]
        }
    }

    var tip: String? {
        switch self {
        case .docEstimate: "Чем полнее документы — планы с размерами, разрезы, спецификации, ведомости проёмов и отделки, — тем точнее смета."
        case .design: "Помощник — кнопка со звёздочкой — подскажет на любом шаге."
        case .ar: "AR‑замер приблизительный: для закупки и разметки перепроверяйте рулеткой."
        case .houseScan: "Снимайте днём, лучше в пасмурную погоду. На iPhone Pro (с лидаром) точность — сантиметры; на обычном — ±2–5 %, и тогда рулетка обязательна."
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("introVoice") private var voiceOn = true
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var playing = true
    @State private var finished = false
    @State private var showText = false
    @StateObject private var voice = IntroVoice()

    /// Слайды ролика: шаги + совет в конце.
    private var slides: [String] { intro.steps + (intro.tip.map { [$0] } ?? []) }
    private func duration(_ i: Int) -> Double { min(7, 2.6 + Double(slides[i].tr.count) * 0.045) }

    var body: some View {
        VStack(spacing: 0) {
            video
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(intro.title.tr).font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(Theme.ink)
                    Text(intro.summary.tr).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(isExpanded: $showText) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(intro.steps.enumerated()), id: \.offset) { i, step in
                                Button { jump(i) } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.goldLight)
                                            .frame(width: 22, height: 22).background(Theme.heroGradient, in: Circle())
                                        Text(step.tr).font(.footnote).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    } label: { Text("Все шаги текстом").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
                    .tint(Theme.orange)
                }
                .padding(.horizontal, 22).padding(.top, 16)
            }
            actions
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .task(id: index) { await play() }
        .onDisappear { voice.stop() }
    }

    // MARK: Ролик

    private var video: some View {
        ZStack {
            FeatureScene(kind: intro.scene, paused: !playing).scaleEffect(reduceMotion ? 1 : 1 + progress * 0.06)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                // Полоски, как в «историях».
                HStack(spacing: 4) {
                    ForEach(slides.indices, id: \.self) { i in
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.3))
                                Capsule().fill(.white).frame(width: g.size.width * (i < index ? 1 : i == index ? progress : 0))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.top, 16)
                HStack {
                    Label(intro.title.tr, systemImage: intro.icon).font(.caption.weight(.bold)).foregroundStyle(Theme.goldLight).lineLimit(1)
                    Spacer()
                    Button { voiceOn.toggle(); if !voiceOn { voice.stop() } else { voice.say(slides[index].tr) } } label: {
                        Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.subheadline).foregroundStyle(.white)
                            .padding(8).background(.black.opacity(0.3), in: Circle())
                    }
                    .accessibilityLabel(voiceOn ? "Выключить голос" : "Включить голос")
                }
                .padding(.top, 10)
                Spacer()
                // Значок шага — живой.
                Image(systemName: IntroVoice.icon(for: slides[index], fallback: intro.icon))
                    .font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.goldLight)
                    .symbolEffect(.bounce, value: index)
                    .frame(width: 74, height: 74).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldLight.opacity(0.4), lineWidth: 1))
                    .padding(.bottom, 14)
                Text(index < intro.steps.count ? "ШАГ \(index + 1) ИЗ \(intro.steps.count)" : "СОВЕТ")
                    .font(.caption2.weight(.heavy)).tracking(1.6).foregroundStyle(Theme.goldLight)
                Text(slides[index].tr).font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    .id(index).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                if finished {
                    Button { jump(0) } label: {
                        Label("Повторить", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8).background(.white.opacity(0.2), in: Capsule()).foregroundStyle(.white)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 22)
            // Касание справа — дальше, слева — назад; удержание — пауза.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { jump(max(0, index - 1)) }
                Color.clear.contentShape(Rectangle()).onTapGesture { jump(min(slides.count - 1, index + 1)) }
            }
            .padding(.top, 70)
            .onLongPressGesture(minimumDuration: 0.25, pressing: { down in playing = !down; if down { voice.pause() } else { voice.resume() } }, perform: {})
        }
        .frame(height: 440)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
        .accessibilityElement(children: .contain)
    }

    private func jump(_ i: Int) {
        finished = false
        if i == index { progress = 0; Task { await play() } } else { index = i }
        Haptics.tap()
    }

    /// Шаг ролика: голос и полоска; дальше — следующий шаг.
    private func play() async {
        progress = 0
        guard slides.indices.contains(index) else { return }
        if voiceOn { voice.say(slides[index].tr) }
        let total = duration(index)
        let tick = 0.05
        var elapsed = 0.0
        while elapsed < total {
            try? await Task.sleep(for: .seconds(tick))
            if Task.isCancelled { return }
            if playing { elapsed += tick; progress = min(1, elapsed / total) }
        }
        // Голос дочитывает фразу, прежде чем перейти дальше.
        while voiceOn && voice.speaking && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(120)) }
        if index < slides.count - 1 { index += 1 } else { finished = true }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            PrimaryButton(title: "Понятно, начнём", icon: "arrow.right") { voice.stop(); dismiss() }
            Button { intro.hideForever(); voice.stop(); dismiss() } label: {
                Text("Больше не показывать").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 24).padding(.top, 10)
    }
}

/// Голос роликов: язык телефона; значок шага — по словам в тексте.
@MainActor final class IntroVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    @Published private(set) var speaking = false
    override init() { super.init(); synth.delegate = self }

    func say(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let u = AVSpeechUtterance(string: text)
        let code = AppLanguage.isRussian ? "ru-RU" : (Locale.current.language.languageCode?.identifier ?? "en")
        u.voice = AVSpeechSynthesisVoice(language: code)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        speaking = true
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    func pause() { synth.pauseSpeaking(at: .word) }
    func resume() { synth.continueSpeaking() }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }

    static func icon(for text: String, fallback: String) -> String {
        let t = text.lowercased()
        let map: [(String, [String])] = [
            ("camera.fill", ["сним", "фото", "сфотограф"]), ("ruler", ["измер", "рулетк", "размер", "длин"]),
            ("doc.fill", ["pdf", "документ", "акт", "смет"]), ("sparkles", ["ии ", "ии.", "ии,", "сгенер", "нарису"]),
            ("hand.tap.fill", ["нажмите", "коснитесь", "выберите", "касанием"]), ("square.and.arrow.up", ["отправ", "поделит"]),
            ("checkmark.seal.fill", ["норм", "провер"]), ("cart.fill", ["купить", "закупк"]), ("lightbulb.fill", ["лучше", "совет", "днём", "точн"]),
            ("figure.walk", ["обойдите", "идите", "круг"]), ("iphone.gen3.radiowaves.left.and.right", ["поводите", "наведите", "телефон"]),
        ]
        return map.first { _, words in words.contains { t.contains($0) } }?.0 ?? fallback
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
