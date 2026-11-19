import SwiftUI
import StoreKit

struct AICenterTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "ИИ‑студия", title: "Увидьте объект\nдо начала работ.")
                Text("Создавайте визуальные идеи по фото или описанию, а затем уточняйте смету и этапы со СтройПомощником.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                NavigationLink { AIVisionStudioView(initialStyle: .object) } label: {
                    ObjectVisualizerHero()
                }
                .buttonStyle(PremiumCardPressStyle())

                NavigationLink { FloorPlansView() } label: {
                    ToolFeatureCard(
                        icon: "cube.transparent",
                        eyebrow: "СКАН КОМНАТЫ · ИИ‑ДИЗАЙН",
                        title: "Планировка и дизайн по скану",
                        subtitle: "Отсканируйте комнату — получите план сверху, расстановку мебели, материалы и бюджет от ИИ.",
                        accent: Theme.sky
                    )
                }
                .buttonStyle(PremiumCardPressStyle())

                HStack(spacing: 10) {
                    Label("Объект целиком", systemImage: "house.fill")
                    Spacer(minLength: 0)
                    Label("Детали и окружение", systemImage: "square.3.layers.3d")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)

                NavigationLink { AIAssistantView(context: .general) } label: {
                    AICenterAssistCard()
                }
                .buttonStyle(PremiumCardPressStyle())

                NavigationLink { PhotoCountView() } label: {
                    ToolFeatureCard(
                        icon: "camera.viewfinder",
                        eyebrow: "СЧЁТ ПО ФОТО",
                        title: "Сколько штук в пачке?",
                        subtitle: "Сфотографируйте торцы арматуры, труб, досок или бруса — ИИ посчитает и переведёт в тонны и кубы.",
                        accent: Theme.sky
                    )
                }
                .buttonStyle(PremiumCardPressStyle())

                Button { store.showAR = true } label: {
                    ToolFeatureCard(
                        icon: "viewfinder",
                        eyebrow: "КАМЕРА И AR",
                        title: "AR‑студия",
                        subtitle: "Измеряйте расстояния и размещайте макеты: плиту, стены, крышу, окна, двери и септик.",
                        accent: Theme.orange
                    )
                }
                .buttonStyle(PremiumCardPressStyle())

                InfoNote(text: "Визуализация показывает направление дизайна. Реальные размеры, материалы, стоимость и рабочие решения уточняются по проекту и смете.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("ИИ‑студия")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProjectsTabView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewProject = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Рабочее пространство", title: "Мои объекты")
                Text("Добавляйте объекты и переключайтесь между ними. Этапы, бюджет, фотографии и журнал ведутся отдельно для каждого.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                VStack(spacing: 12) {
                    ForEach(store.projectWorkspaces) { workspace in
                        Button {
                            store.selectProject(workspace.id)
                            Haptics.tap()
                        } label: {
                            ProjectWorkspaceSelectionCard(workspace: workspace, isActive: workspace.id == store.activeProjectID)
                        }
                        .buttonStyle(PremiumCardPressStyle())
                    }
                }

                Button { showNewProject = true } label: {
                    Label("Добавить объект", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .foregroundStyle(.black)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PremiumPressStyle())

                NavigationLink { ProjectHubView() } label: {
                    HomeProjectCard(name: store.projectDisplayName, stage: store.passport.stage, progress: store.projectProgress, next: store.nextMilestone?.title, planned: store.budgetPlanned, actual: store.budgetActual)
                }
                .buttonStyle(PremiumCardPressStyle())

                NavigationLink { FloorPlansView() } label: {
                    AppTabRow(icon: "square.split.bottomrightquarter.fill", title: "Планировки и дизайн", subtitle: store.floorPlans.isEmpty ? "Скан комнаты, план сверху и ИИ‑дизайн" : "Планов: \(store.floorPlans.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ObjectPassportView() } label: {
                    AppTabRow(icon: "house.and.flag.fill", title: "Паспорт объекта", subtitle: "Адрес, площадь, этап и заметки")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ProjectTasksView() } label: {
                    AppTabRow(icon: "checklist", title: "Задачи команды", subtitle: store.projectTasks.isEmpty ? "Поставить задачу, выбрать ответственного и срок" : "Открыто: \(store.projectTasks.filter { $0.status != .done }.count) · готово: \(store.projectTasks.filter { $0.status == .done }.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ProjectBudgetTrackerView() } label: {
                    AppTabRow(icon: "rublesign.circle.fill", title: "Бюджет по этапам", subtitle: store.budgetPlanned > 0 ? "План \(CalculationEngine.money(store.budgetPlanned)) · потрачено \(CalculationEngine.money(store.budgetActual))" : "План, факт и остаток по работам")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ProjectPhotoDiaryView() } label: {
                    AppTabRow(icon: "photo.stack.fill", title: "Фото‑дневник", subtitle: store.projectPhotos.isEmpty ? "Скрытые работы и этапы на фото" : "Фото: \(store.projectPhotos.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ConstructionDiaryView() } label: {
                    AppTabRow(icon: "text.book.closed.fill", title: "Журнал решений", subtitle: store.diary.isEmpty ? "Фиксируйте решения и договорённости" : "Записей: \(store.diary.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ChecklistView() } label: {
                    AppTabRow(icon: "checklist.checked", title: "Чек‑листы", subtitle: "\(store.checklistDone.count) отмечено · контроль от старта до приёмки")
                }
                .buttonStyle(PremiumCardPressStyle())

                SectionTitle(eyebrow: "АртСтрой", title: "Реализованные объекты")
                NavigationLink { PortfolioView() } label: {
                    AppTabRow(icon: "building.2.fill", title: "Портфолио АртСтроя", subtitle: "\(Brand.completedObjects)+ объектов: гостиницы, жильё, рестораны")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { PerformersHubView() } label: {
                    AppTabRow(icon: "bubble.left.and.bubble.right.fill", title: "Мои заявки и чаты", subtitle: store.workOrders.isEmpty ? "Согласование работ с АртСтроем" : "Заявок: \(store.workOrders.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Проекты")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $store.planToOpen) { id in FloorPlanDetailView(planID: id) }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, address in
                store.createProject(name: name, address: address)
            }
        }
    }
}

private struct ProjectWorkspaceSelectionCard: View {
    let workspace: ProjectWorkspace
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isActive ? "АКТИВНЫЙ ОБЪЕКТ" : "ОБЪЕКТ")
                        .font(.caption2.weight(.bold)).tracking(1.1)
                        .foregroundStyle(isActive ? Theme.orange : Theme.muted)
                    Text(workspace.displayName).font(.headline).foregroundStyle(.white)
                    Text(workspace.passport.address.isEmpty ? "Адрес не указан" : workspace.passport.address)
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isActive ? Theme.orange : Theme.muted)
            }
            ProgressView(value: workspace.progress).tint(Theme.orange)
            HStack {
                Text("\(Int(workspace.progress * 100))% · \(workspace.passport.stage)")
                Spacer()
                if workspace.budgetPlanned > 0 {
                    Text("План \(CalculationEngine.money(workspace.budgetPlanned))")
                } else if !isActive {
                    Text("Нажмите, чтобы выбрать")
                }
            }
            .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isActive ? Theme.orange.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    let onCreate: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Новый объект") {
                    TextField("Название, например: Дом в Хосте", text: $name)
                    TextField("Адрес или район", text: $address)
                }
                Section {
                    Text("Для объекта автоматически создадутся отдельные этапы, бюджет, фото-дневник и журнал решений.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Добавить объект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        onCreate(name, address)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ProjectTasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewTask = false

    private var openCount: Int { store.projectTasks.filter { $0.status != .done }.count }
    private var doneCount: Int { store.projectTasks.filter { $0.status == .done }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.projectDisplayName).font(.headline)
                    Text("Задачи сохраняются отдельно для этого объекта.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Text("Пока список доступен на этом iPhone; синхронизация с участниками ещё не подключена.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }

            if store.projectTasks.isEmpty {
                ContentUnavailableView {
                    Label("Задач пока нет", systemImage: "checklist")
                } description: {
                    Text("Добавьте работу, укажите ответственного и срок.")
                } actions: {
                    Button("Добавить задачу") { showNewTask = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.orange)
                }
            } else {
                Section("План · \(openCount) открыто · \(doneCount) готово") {
                    ForEach($store.projectTasks) { $task in
                        ProjectTaskRow(task: $task)
                    }
                    .onDelete { store.projectTasks.remove(atOffsets: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Задачи команды")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewTask = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить задачу")
            }
        }
        .sheet(isPresented: $showNewTask) {
            NewProjectTaskSheet { title, assignee, dueDate, notes in
                store.addProjectTask(title: title, assignee: assignee, dueDate: dueDate, notes: notes)
            }
        }
    }
}

private struct ProjectTaskRow: View {
    @Binding var task: ProjectTask

    private var statusColor: Color {
        switch task.status {
        case .planned: return Theme.muted
        case .inProgress: return Theme.orange
        case .done: return Theme.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy) { task.status = task.status.next }
                    Haptics.tap()
                } label: {
                    Label(task.status.title, systemImage: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(statusColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Изменить статус: \(task.status.title)")
            }

            HStack(spacing: 12) {
                Label(task.assignee.isEmpty ? "Не назначен" : task.assignee, systemImage: "person")
                    .lineLimit(1)
                if let dueDate = task.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .foregroundStyle(dueDate < .now && task.status != .done ? Theme.danger : Theme.muted)
                }
            }
            .font(.caption).foregroundStyle(Theme.muted)

            if !task.notes.isEmpty {
                Text(task.notes).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct NewProjectTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var assignee = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var notes = ""
    let onCreate: (String, String, Date?, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Задача") {
                    TextField("Что нужно сделать", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Ответственный: имя или бригада", text: $assignee)
                    Toggle("Указать срок", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Срок", selection: $dueDate, in: Date.now..., displayedComponents: .date)
                    }
                }
                Section("Детали") {
                    TextField("Материалы, условия или комментарий", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Новая задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        onCreate(title, assignee, hasDueDate ? dueDate : nil, notes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ProfileTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.requestReview) private var requestReview
    private var syncNote: String {
        var note = "Цены синхронизируются с сервером"
        if let sync = store.lastPriceSync { note += " (последний раз \(sync.formatted(date: .abbreviated, time: .shortened)))" }
        return note + ". Паспорт объекта, бюджет и дневник хранятся только на этом iPhone."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .padding(11)
                        .panelCard(19)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("АРТСТРОЙ").font(.title3.bold()).tracking(1.3)
                        Text("ИП МАРКАРЯН А.В.").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                        Text("Строительство и ремонт в Сочи").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                SectionTitle(eyebrow: "Связь с нами", title: "Обсудим ваш объект")
                HStack(spacing: 12) {
                    Link(destination: Brand.phoneURL) { ProfileQuickAction(icon: "phone.fill", title: "Позвонить") }
                    Link(destination: Brand.whatsAppURL(text: "Здравствуйте! Пишу из приложения АртСтрой.")) { ProfileQuickAction(icon: "message.fill", title: "WhatsApp") }
                    Link(destination: Brand.emailURL) { ProfileQuickAction(icon: "envelope.fill", title: "Почта") }
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { ContactView() } label: {
                    AppTabRow(icon: "message.fill", title: "Контакты и услуги", subtitle: "Телефон, почта, адрес и направления работ")
                }
                .buttonStyle(PremiumCardPressStyle())
                Button { store.showRequest = true } label: {
                    AppTabRow(icon: "square.and.pencil", title: "Оставить заявку", subtitle: "Ответим по телефону или в чате приложения")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { PerformersHubView() } label: {
                    AppTabRow(icon: "bubble.left.and.bubble.right.fill", title: "Мои заявки и чаты", subtitle: "Статусы и переписка по заявкам")
                }
                .buttonStyle(PremiumCardPressStyle())

                SectionTitle(eyebrow: "Расскажите друзьям", title: "Строите не один?")
                ShareLink(item: Brand.inviteText) {
                    AppTabRow(icon: "gift.fill", title: "Поделиться приложением", subtitle: "Отправьте калькуляторы и смету тем, кто строится")
                }
                .buttonStyle(PremiumCardPressStyle())
                Button { requestReview() } label: {
                    AppTabRow(icon: "star.fill", title: "Оценить приложение", subtitle: "Отзыв помогает нам становиться лучше")
                }
                .buttonStyle(PremiumCardPressStyle())

                SectionTitle(eyebrow: "Приложение", title: "Настройки")
                NavigationLink { CalculationHistoryView() } label: {
                    AppTabRow(icon: "clock.arrow.circlepath", title: "Мои расчёты", subtitle: store.calculations.isEmpty ? "Сохранённых расчётов пока нет" : "Сохранено: \(store.calculations.count)")
                }
                .buttonStyle(PremiumCardPressStyle())
                NavigationLink { PriceServerSettingsView() } label: {
                    AppTabRow(icon: "arrow.triangle.2.circlepath", title: "Цены и синхронизация", subtitle: "Прайс, сервер и статистика")
                }
                .buttonStyle(PremiumCardPressStyle())

                InfoNote(text: syncNote)
                Text("Версия \(Brand.appVersion)").font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct ObjectVisualizerHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.31, green: 0.23, blue: 0.17), Color(red: 0.09, green: 0.16, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(red: 0.87, green: 0.75, blue: 0.60).opacity(0.9), Color(red: 0.23, green: 0.31, blue: 0.26).opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 250, height: 155)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 0.19, green: 0.24, blue: 0.20))
                        .frame(height: 42)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.72)).frame(width: 33, height: 48).padding(.leading, 26)
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.72)).frame(width: 47, height: 48)
                    }
                    .padding(.top, 42)
                }
                .rotationEffect(.degrees(-6))
                .offset(x: 156, y: -67)
                .opacity(0.96)
            Circle().fill(Theme.orange.opacity(0.24)).frame(width: 190, height: 190).blur(radius: 9).offset(x: 142, y: -112)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "wand.and.stars").font(.caption.weight(.bold)).foregroundStyle(.black).padding(8).background(Theme.orange, in: Circle())
                    Text("ВИЗУАЛИЗАТОР ОБЪЕКТА").font(.caption2.weight(.bold)).tracking(1.15).foregroundStyle(.white.opacity(0.78))
                }
                Text("Покажем будущее\nдо начала работ.")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Дом · фасад · интерьер · мебель · участок")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 7) {
                    Text("Создать по фото или идее").font(.caption.weight(.semibold)).foregroundStyle(.black)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.black)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(red: 0.97, green: 0.71, blue: 0.45), in: Capsule())
                .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 268, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 25))
    }
}

struct AICenterAssistCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hardhat.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.17, blue: 0.11))
                .frame(width: 48, height: 48)
                .background(Color(red: 0.68, green: 0.81, blue: 0.47), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) {
                Text("СТРОЙПОМОЩНИК").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(Color(red: 0.68, green: 0.81, blue: 0.47))
                Text("Смета без непонятных строк").font(.headline).foregroundStyle(.white)
                Text("Материалы, этапы, объёмы и наша цена — простым языком.").font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(17)
        .panelCard(21)
    }
}

struct ToolFeatureCard: View {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 48, height: 48)
                .background(accent, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(accent)
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(.top, 6)
        }
        .padding(17)
        .panelCard(21)
    }
}

struct AppTabRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.orange)
                .frame(width: 42, height: 42)
                .background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .panelCard(18)
    }
}

struct ProjectFocusCard: View {
    let name: String
    let stage: String
    let area: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ТЕКУЩИЙ ОБЪЕКТ").font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(.white.opacity(0.64))
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(Theme.orange)
            }
            Text(name).font(.title3.bold()).foregroundStyle(.white)
            Text(area.isEmpty ? stage : "\(stage) · \(area) м²").font(.subheadline).foregroundStyle(.white.opacity(0.72))
            HStack(spacing: 7) {
                Circle().fill(Color(red: 0.45, green: 0.85, blue: 0.60)).frame(width: 7, height: 7)
                Text("Данные сохранены").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.21), Color(red: 0.09, green: 0.12, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ProfileQuickAction: View {
    let icon: String
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(.black)
                .frame(width: 46, height: 46).background(Theme.orange, in: Circle())
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).panelCard(18)
    }
}
