import SwiftUI
import Combine
import UIKit

struct ObjectPassport: Codable {
    var name = "Мой объект"
    var address = ""
    var stage = "Планирование"
    var area = ""
    var notes = ""
}

enum ProjectTaskStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case inProgress
    case done

    var id: String { rawValue }
    var title: String {
        switch self {
        case .planned: "К выполнению"
        case .inProgress: "В работе"
        case .done: "Готово"
        }
    }
    var next: ProjectTaskStatus {
        switch self {
        case .planned: .inProgress
        case .inProgress: .done
        case .done: .planned
        }
    }
}

struct ProjectTask: Codable, Identifiable {
    let id: UUID
    var title: String
    var assignee: String
    var dueDate: Date?
    var status: ProjectTaskStatus
    var notes: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, assignee: String = "", dueDate: Date? = nil, status: ProjectTaskStatus = .planned, notes: String = "", createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.dueDate = dueDate
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// A locally stored project workspace. Each workspace owns the data that describes and tracks one construction site.
struct ProjectWorkspace: Codable, Identifiable {
    let id: UUID
    var passport: ObjectPassport
    var checklistDone: Set<String>
    var diary: [DiaryEntry]
    var milestones: [ProjectMilestone]
    var budgetItems: [ProjectBudgetItem]
    var projectPhotos: [ProjectPhoto]
    var floorPlans: [FloorPlan]
    var tasks: [ProjectTask]

    init(
        id: UUID = UUID(),
        passport: ObjectPassport = ObjectPassport(),
        checklistDone: Set<String> = [],
        diary: [DiaryEntry] = [],
        milestones: [ProjectMilestone] = ProjectMilestone.defaults,
        budgetItems: [ProjectBudgetItem] = ProjectBudgetItem.defaults,
        projectPhotos: [ProjectPhoto] = [],
        floorPlans: [FloorPlan] = [],
        tasks: [ProjectTask] = []
    ) {
        self.id = id
        self.passport = passport
        self.checklistDone = checklistDone
        self.diary = diary
        self.milestones = milestones
        self.budgetItems = budgetItems
        self.projectPhotos = projectPhotos
        self.floorPlans = floorPlans
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey {
        case id, passport, checklistDone, diary, milestones, budgetItems, projectPhotos, floorPlans, tasks
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        passport = try values.decodeIfPresent(ObjectPassport.self, forKey: .passport) ?? ObjectPassport()
        checklistDone = try values.decodeIfPresent(Set<String>.self, forKey: .checklistDone) ?? []
        diary = try values.decodeIfPresent([DiaryEntry].self, forKey: .diary) ?? []
        milestones = try values.decodeIfPresent([ProjectMilestone].self, forKey: .milestones) ?? ProjectMilestone.defaults
        budgetItems = try values.decodeIfPresent([ProjectBudgetItem].self, forKey: .budgetItems) ?? ProjectBudgetItem.defaults
        projectPhotos = try values.decodeIfPresent([ProjectPhoto].self, forKey: .projectPhotos) ?? []
        floorPlans = try values.decodeIfPresent([FloorPlan].self, forKey: .floorPlans) ?? []
        tasks = try values.decodeIfPresent([ProjectTask].self, forKey: .tasks) ?? []
    }

    var displayName: String {
        let name = passport.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Мой объект" : name
    }
    var progress: Double {
        milestones.isEmpty ? 0 : Double(milestones.filter(\.completed).count) / Double(milestones.count)
    }
    var nextMilestone: ProjectMilestone? { milestones.first { !$0.completed } }
    var budgetPlanned: Double { budgetItems.filter(\.included).reduce(0) { $0 + $1.planned } }
    var budgetActual: Double { budgetItems.filter(\.included).reduce(0) { $0 + $1.actual } }
}

struct DiaryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    var text: String
    init(id: UUID = UUID(), date: Date = .now, text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}
struct ProjectMilestone: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var completed: Bool = false
    static let defaults = [
        ProjectMilestone(id: "brief", title: "Задача и бюджет", subtitle: "Зафиксировать цель и ориентир цены"),
        ProjectMilestone(id: "estimate", title: "Смета", subtitle: "Проверить объёмы, материалы и работы"),
        ProjectMilestone(id: "site", title: "Выезд на объект", subtitle: "Уточнить участок и состав работ"),
        ProjectMilestone(id: "contract", title: "Договор и график", subtitle: "Согласовать этапы и оплату"),
        ProjectMilestone(id: "work", title: "Работы и фотоотчёты", subtitle: "Контролировать ход работ"),
        ProjectMilestone(id: "acceptance", title: "Приёмка", subtitle: "Проверить результат и документы")
    ]
}
struct ProjectBudgetItem: Codable, Identifiable {
    let id: String
    let title: String
    var planned: Double = 0
    var actual: Double = 0
    var included: Bool = true
    static let defaults = ["Подготовка", "Фундамент", "Коробка", "Кровля", "Инженерия", "Фасад", "Отделка", "Доставка и техника"].enumerated().map { ProjectBudgetItem(id: "budget-\($0.offset)", title: $0.element) }
}
struct ProjectPhoto: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var caption: String
    let filename: String
}
struct PriceLine: Codable, Identifiable {
    let code: String
    var section: String
    var title: String
    var unit: String
    var materialRate: Double
    var laborRate: Double
    var quantityPerSquareMeter: Double
    var basis: String
    /// Nil keeps compatibility with the first price files and means that the line belongs to a house estimate.
    var appliesTo: [String]? = nil
    // Market range from the price collection (P25 / P75 of real offers) and how many offers it rests on.
    var materialLow: Double? = nil
    var materialHigh: Double? = nil
    var laborLow: Double? = nil
    var laborHigh: Double? = nil
    var materialSources: Int? = nil
    var laborSources: Int? = nil
    /// "material" / "labor": which side of the line has market data for the chosen city. Empty: base guide price.
    var marketData: [String]? = nil
    var lowData: Bool? = nil
    var id: String { code }
    var scopes: [String] { appliesTo ?? ["house"] }
    var hasMarketData: Bool { !(marketData ?? []).isEmpty }
}
struct PriceBook: Codable {
    var updatedAt: Date
    var lines: [PriceLine]
    /// City the market prices were collected for; nil — built-in base guide prices.
    var city: String? = nil
    /// city / region / nearby / national / import
    var coverage: String? = nil
    var distanceKm: Double? = nil
    var method: String? = nil
    var marketLineCount: Int { lines.filter(\.hasMarketData).count }
    static let `default` = PriceBook(updatedAt: .now, lines: [
        PriceLine(code: "survey", section: "Подготовка", title: "Выезд, геодезия и разметка", unit: "компл.", materialRate: 0, laborRate: 35_000, quantityPerSquareMeter: 0, basis: "fixed"),
        PriceLine(code: "temporary", section: "Подготовка", title: "Временное электроснабжение и бытовка", unit: "компл.", materialRate: 70_000, laborRate: 20_000, quantityPerSquareMeter: 0, basis: "fixed"),
        PriceLine(code: "excavation", section: "Фундамент", title: "Разработка грунта", unit: "м³", materialRate: 0, laborRate: 1_100, quantityPerSquareMeter: 0.45, basis: "area"),
        PriceLine(code: "sand", section: "Фундамент", title: "Песчано-щебёночное основание", unit: "м³", materialRate: 3_200, laborRate: 900, quantityPerSquareMeter: 0.25, basis: "area"),
        PriceLine(code: "concrete", section: "Фундамент", title: "Бетон для фундаментной плиты", unit: "м³", materialRate: 7_800, laborRate: 1_400, quantityPerSquareMeter: 0.30, basis: "area"),
        PriceLine(code: "rebar", section: "Фундамент", title: "Арматура и вязальная проволока", unit: "кг", materialRate: 82, laborRate: 28, quantityPerSquareMeter: 18, basis: "area"),
        PriceLine(code: "formwork", section: "Фундамент", title: "Опалубка и крепёж", unit: "м²", materialRate: 1_250, laborRate: 1_050, quantityPerSquareMeter: 0.55, basis: "area"),
        PriceLine(code: "waterproofing", section: "Фундамент", title: "Гидроизоляция фундамента", unit: "м²", materialRate: 520, laborRate: 360, quantityPerSquareMeter: 1.1, basis: "area"),
        PriceLine(code: "pump", section: "Фундамент", title: "Бетононасос и техника", unit: "смена", materialRate: 0, laborRate: 28_000, quantityPerSquareMeter: 0, basis: "fixed"),
        PriceLine(code: "block", section: "Коробка", title: "Кладка наружных стен", unit: "м² стен", materialRate: 2_500, laborRate: 1_350, quantityPerSquareMeter: 2.8, basis: "area"),
        PriceLine(code: "floor", section: "Коробка", title: "Перекрытия и армопояса", unit: "м² дома", materialRate: 4_800, laborRate: 2_000, quantityPerSquareMeter: 1, basis: "area"),
        PriceLine(code: "roof", section: "Кровля", title: "Стропильная система", unit: "м² кровли", materialRate: 3_500, laborRate: 1_700, quantityPerSquareMeter: 1.25, basis: "area"),
        PriceLine(code: "covering", section: "Кровля", title: "Кровельное покрытие и водосток", unit: "м² кровли", materialRate: 3_900, laborRate: 1_150, quantityPerSquareMeter: 1.25, basis: "area"),
        PriceLine(code: "windows", section: "Проёмы", title: "Окна и входные двери", unit: "м² проёмов", materialRate: 17_000, laborRate: 2_200, quantityPerSquareMeter: 0.20, basis: "area"),
        PriceLine(code: "facade", section: "Фасад", title: "Утепление и фасад", unit: "м² фасада", materialRate: 3_600, laborRate: 2_100, quantityPerSquareMeter: 2.8, basis: "area"),
        PriceLine(code: "electric", section: "Инженерия", title: "Электрика", unit: "м² дома", materialRate: 3_500, laborRate: 2_300, quantityPerSquareMeter: 1, basis: "area"),
        PriceLine(code: "water", section: "Инженерия", title: "Водоснабжение и канализация", unit: "м² дома", materialRate: 2_900, laborRate: 1_900, quantityPerSquareMeter: 1, basis: "area"),
        PriceLine(code: "septic", section: "Инженерия", title: "Септик и подключение", unit: "компл.", materialRate: 145_000, laborRate: 45_000, quantityPerSquareMeter: 0, basis: "fixed"),
        PriceLine(code: "roughFinish", section: "Отделка", title: "Черновая отделка", unit: "м² дома", materialRate: 5_800, laborRate: 3_800, quantityPerSquareMeter: 1, basis: "area"),
        PriceLine(code: "finish", section: "Отделка", title: "Чистовая отделка", unit: "м² дома", materialRate: 8_500, laborRate: 5_500, quantityPerSquareMeter: 1, basis: "area"),
        PriceLine(code: "delivery", section: "Логистика", title: "Доставка материалов", unit: "компл.", materialRate: 85_000, laborRate: 0, quantityPerSquareMeter: 0, basis: "fixed"),
        PriceLine(code: "waste", section: "Логистика", title: "Вывоз мусора", unit: "компл.", materialRate: 30_000, laborRate: 10_000, quantityPerSquareMeter: 0, basis: "fixed")
        ,PriceLine(code: "gazeboLayout", section: "Подготовка", title: "Разметка площадки", unit: "компл.", materialRate: 0, laborRate: 8_000, quantityPerSquareMeter: 0, basis: "fixed", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboBase", section: "Основание", title: "Щебёночное основание", unit: "м³", materialRate: 3_300, laborRate: 800, quantityPerSquareMeter: 0.18, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboConcrete", section: "Основание", title: "Бетонные опоры", unit: "м³", materialRate: 8_100, laborRate: 2_000, quantityPerSquareMeter: 0.12, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboFrame", section: "Каркас", title: "Деревянный или металлический каркас", unit: "м²", materialRate: 4_700, laborRate: 2_500, quantityPerSquareMeter: 1, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboRoof", section: "Кровля", title: "Стропила, покрытие и водосток", unit: "м²", materialRate: 5_200, laborRate: 1_900, quantityPerSquareMeter: 1.25, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboFloor", section: "Отделка", title: "Настил пола", unit: "м²", materialRate: 2_900, laborRate: 1_300, quantityPerSquareMeter: 1, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboRail", section: "Отделка", title: "Ограждения и декоративные элементы", unit: "м²", materialRate: 1_600, laborRate: 1_200, quantityPerSquareMeter: 1, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboPaint", section: "Отделка", title: "Защита и покраска", unit: "м²", materialRate: 700, laborRate: 650, quantityPerSquareMeter: 1.6, basis: "area", appliesTo: ["gazebo"])
        ,PriceLine(code: "gazeboDelivery", section: "Логистика", title: "Доставка и монтаж", unit: "компл.", materialRate: 18_000, laborRate: 12_000, quantityPerSquareMeter: 0, basis: "fixed", appliesTo: ["gazebo"])
        ,PriceLine(code: "metalMeasure", section: "Подготовка", title: "Замер и рабочая схема", unit: "компл.", materialRate: 0, laborRate: 12_000, quantityPerSquareMeter: 0, basis: "fixed", appliesTo: ["metal"])
        ,PriceLine(code: "metalProfile", section: "Материал", title: "Профильная труба и прокат", unit: "кг", materialRate: 150, laborRate: 0, quantityPerSquareMeter: 22, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalSheet", section: "Материал", title: "Листовой металл и крепёж", unit: "м²", materialRate: 1_900, laborRate: 0, quantityPerSquareMeter: 1.1, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalWeld", section: "Изготовление", title: "Резка, сварка и сборка", unit: "кг", materialRate: 0, laborRate: 110, quantityPerSquareMeter: 22, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalPrimer", section: "Защита", title: "Антикоррозионный грунт и окраска", unit: "м²", materialRate: 950, laborRate: 700, quantityPerSquareMeter: 1.5, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalAnchors", section: "Монтаж", title: "Анкеры, крепёж и расходники", unit: "м²", materialRate: 650, laborRate: 500, quantityPerSquareMeter: 1, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalInstall", section: "Монтаж", title: "Доставка и монтаж конструкции", unit: "м²", materialRate: 0, laborRate: 2_200, quantityPerSquareMeter: 1, basis: "area", appliesTo: ["metal"])
        ,PriceLine(code: "metalLift", section: "Логистика", title: "Подъёмная техника", unit: "смена", materialRate: 0, laborRate: 18_000, quantityPerSquareMeter: 0, basis: "fixed", appliesTo: ["metal"])
    ])
}

struct AIAssistantLine: Codable, Identifiable {
    let id: String
    let section: String
    let title: String
    let quantity: Double
    let unit: String
    let material: Double
    let labor: Double
    let total: Double
}

struct AIAssistantContext: Codable {
    let estimateType: String
    let objectName: String
    let area: Double?
    let floors: Int?
    let reservePercent: Double?
    let materialTotal: Double?
    let laborTotal: Double?
    let total: Double?
    let lines: [AIAssistantLine]
    var city: String = "Сочи"

    func withCity(_ value: String) -> AIAssistantContext {
        AIAssistantContext(
            estimateType: estimateType,
            objectName: objectName,
            area: area,
            floors: floors,
            reservePercent: reservePercent,
            materialTotal: materialTotal,
            laborTotal: laborTotal,
            total: total,
            lines: lines,
            city: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? city : value
        )
    }

    static let general = AIAssistantContext(estimateType: "Общий строительный вопрос", objectName: "", area: nil, floors: nil, reservePercent: nil, materialTotal: nil, laborTotal: nil, total: nil, lines: [])
}

struct AIAssistantLocalLink: Decodable, Identifiable {
    let title: String
    let url: String
    var id: String { url }
    var destination: URL? { URL(string: url) }
}

struct AIAssistantReply: Decodable {
    let answer: String
    let links: [AIAssistantLocalLink]?
    var localLinks: [AIAssistantLocalLink] { links ?? [] }
}
private struct VisualizationResponse: Decodable {
    let imageBase64: String
}

enum AIAssistantError: LocalizedError {
    case serverAddress
    case server
    case message(String)
    var errorDescription: String? {
        switch self {
        case .serverAddress: return "Сначала укажите адрес сервера в настройках прайса."
        case .server: return "Сервер ИИ не ответил. Попробуйте позже."
        case .message(let text): return text
        }
    }
}
enum VisualizationError: LocalizedError {
    case serverAddress, server, imagePreparation, imageDecoding, message(String)
    var errorDescription: String? { switch self {
    case .serverAddress: return "Сначала укажите адрес сервера в настройках прайса."
    case .server: return "Сервер визуализации не ответил. Попробуйте позже."
    case .imagePreparation: return "Не удалось подготовить исходное фото."
    case .imageDecoding: return "Сервер вернул повреждённое изображение."
    case .message(let text): return text
    } }
}

@MainActor final class AppStore: ObservableObject {
    static let productionServerURL = "https://pastura.2-26-100-30.sslip.io"
    @Published var tab = 0
    @Published var favorites: Set<String> = [] { didSet { scheduleSave(favorites, key: "favorites") } }
    @Published var calculations: [SavedCalculation] = [] { didSet { scheduleSave(calculations, key: "calculations") } }
    @Published private(set) var projectWorkspaces: [ProjectWorkspace] = []
    @Published private(set) var activeProjectID: UUID?
    @Published var passport = ObjectPassport() { didSet { scheduleSave(passport, key: "passport"); persistActiveWorkspace() } }
    @Published var checklistDone: Set<String> = [] { didSet { scheduleSave(checklistDone, key: "checklistDone"); persistActiveWorkspace() } }
    @Published var diary: [DiaryEntry] = [] { didSet { scheduleSave(diary, key: "diary"); persistActiveWorkspace() } }
    @Published var milestones: [ProjectMilestone] = ProjectMilestone.defaults { didSet { scheduleSave(milestones, key: "milestones"); persistActiveWorkspace() } }
    @Published var budgetItems: [ProjectBudgetItem] = ProjectBudgetItem.defaults { didSet { scheduleSave(budgetItems, key: "budgetItems"); persistActiveWorkspace() } }
    @Published var projectPhotos: [ProjectPhoto] = [] { didSet { scheduleSave(projectPhotos, key: "projectPhotos"); persistActiveWorkspace() } }
    @Published var projectTasks: [ProjectTask] = [] { didSet { scheduleSave(projectTasks, key: "projectTasks"); persistActiveWorkspace() } }
    @Published var lastInputs: [String: [String: String]] = [:] { didSet { scheduleSave(lastInputs, key: "lastInputs") } }
    @Published var floorPlans: [FloorPlan] = [] { didSet { scheduleSave(floorPlans, key: "floorPlans"); persistActiveWorkspace() } }
    /// Plan to open right after a scan or AR contour is saved.
    @Published var planToOpen: FloorPlan.ID?
    /// An apartment to show after a multi-room scan.
    @Published var apartmentToOpen: UUID?
    @Published var showRoomScan = false
    /// «Дом снаружи» → «Скан дома».
    @Published var showHouseScan = false
    // AI engine: Claude directly (key in Keychain) or the app's server.
    @Published var aiPreference: AIPreference = .auto { didSet { UserDefaults.standard.set(aiPreference.rawValue, forKey: "aiPreference") } }
    @Published var claudeModel: ClaudeModel = .sonnet { didSet { UserDefaults.standard.set(claudeModel.rawValue, forKey: "claudeModel") } }
    /// Picked on the «Дизайн» step: the AI that designs and lays out the room, and the one that draws the 3D render.
    @Published var designModel: DesignModel = .standard { didSet { UserDefaults.standard.set(designModel.rawValue, forKey: AIModelChoice.designKey) } }
    @Published var renderModel: RenderModel = .standard { didSet { UserDefaults.standard.set(renderModel.rawValue, forKey: AIModelChoice.renderKey) } }
    @Published private(set) var hasClaudeKey = false
    @Published var priceBook = PriceBook.default { didSet { scheduleSave(priceBook, key: "priceBook") } }
    @Published var priceServerURL = AppStore.productionServerURL { didSet { UserDefaults.standard.set(priceServerURL, forKey: "priceServerURL") } }
    @Published var priceSyncMessage: String?
    @Published var priceAlert: String? { didSet { UserDefaults.standard.set(priceAlert, forKey: "priceAlert") } }
    @Published var storageError: String?
    @Published var arTransfer: ARTransfer?
    @Published var showAR = false
    @Published var lastPriceSync: Date? { didSet { UserDefaults.standard.set(lastPriceSync, forKey: "lastPriceSync") } }
    /// City for market prices and partner contractors.
    @Published var userRegion: UserRegion? { didSet { scheduleSave(userRegion, key: "userRegion") } }
    @Published var showRegionPicker = false
    @Published private(set) var regionDetecting = false
    @Published private(set) var locationDenied = false
    private let locationService = LocationService()
    /// Number of meaningful results (saved calculation, PDF, sent request). Used to ask for an App Store rating at a good moment.
    @Published private(set) var meaningfulActions = UserDefaults.standard.integer(forKey: "meaningfulActions")
    private var pendingSaves: [String: () -> Void] = [:]
    private var saveTask: Task<Void, Never>?
    private var isRestoringWorkspace = false

    /// Short timeouts: the app must never hang on a slow mobile network.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 130
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init() {
        favorites = Self.read("favorites") ?? []
        calculations = Self.read("calculations") ?? []
        passport = Self.read("passport") ?? ObjectPassport()
        checklistDone = Self.read("checklistDone") ?? []
        diary = Self.read("diary") ?? []
        milestones = Self.read("milestones") ?? ProjectMilestone.defaults
        budgetItems = Self.read("budgetItems") ?? ProjectBudgetItem.defaults
        projectPhotos = Self.read("projectPhotos") ?? []
        projectTasks = Self.read("projectTasks") ?? []
        lastInputs = Self.read("lastInputs") ?? [:]
        floorPlans = Self.read("floorPlans") ?? []
        aiPreference = AIPreference(rawValue: UserDefaults.standard.string(forKey: "aiPreference") ?? "") ?? .auto
        claudeModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .sonnet
        designModel = AIModelChoice.design(UserDefaults.standard.string(forKey: AIModelChoice.designKey))
        renderModel = AIModelChoice.render(UserDefaults.standard.string(forKey: AIModelChoice.renderKey))
        hasClaudeKey = ClaudeClient.currentKey != nil
        userRegion = Self.read("userRegion")
        priceBook = Self.read("priceBook") ?? .default
        // Prices saved by older versions came from the company price list: start from the base guide instead.
        if priceBook.coverage == nil { priceBook = .default }
        let savedServerURL = UserDefaults.standard.string(forKey: "priceServerURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        priceServerURL = savedServerURL.isEmpty ? Self.productionServerURL : savedServerURL
        priceAlert = UserDefaults.standard.string(forKey: "priceAlert")
        lastPriceSync = UserDefaults.standard.object(forKey: "lastPriceSync") as? Date
        HelperCenter.shared.store = self

        if let savedWorkspaces: [ProjectWorkspace] = Self.read("projectWorkspaces"), !savedWorkspaces.isEmpty {
            projectWorkspaces = savedWorkspaces
            let savedID = UserDefaults.standard.string(forKey: "activeProjectID").flatMap(UUID.init(uuidString:))
            let selected = savedWorkspaces.first(where: { $0.id == savedID }) ?? savedWorkspaces[0]
            activeProjectID = selected.id
            restoreWorkspace(selected)
            UserDefaults.standard.set(selected.id.uuidString, forKey: "activeProjectID")
        } else {
            // One-time migration: keep the user's existing single-object data as their first workspace.
            let first = ProjectWorkspace(
                passport: passport,
                checklistDone: checklistDone,
                diary: diary,
                milestones: milestones,
                budgetItems: budgetItems,
                projectPhotos: projectPhotos,
                floorPlans: floorPlans,
                tasks: projectTasks
            )
            projectWorkspaces = [first]
            activeProjectID = first.id
            UserDefaults.standard.set(first.id.uuidString, forKey: "activeProjectID")
            if let data = try? JSONEncoder().encode(projectWorkspaces) {
                UserDefaults.standard.set(data, forKey: "projectWorkspaces")
            }
        }
        Task { [weak self] in await self?.refreshAICapabilities() }
    }

    // MARK: Persistence (debounced: typing in a text field no longer re-encodes data on every keystroke)

    static func bundle<T: Decodable>(_ name: String) -> T where T: RangeReplaceableCollection {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { return T() }
        return value
    }
    private static func read<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            // Не прочиталось (например, после обновления формата) — сохраняем копию, чтобы следующая запись
            // не стёрла данные пользователя насовсем; их можно восстановить.
            backup(data, key: key, reason: error)
            return nil
        }
    }

    /// Списки (комнаты, расчёты, фото…) читаются поштучно: одна испорченная запись не обнуляет весь список.
    private static func read<E: Decodable>(_ key: String) -> [E]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let all = try? JSONDecoder().decode([E].self, from: data) { return all }
        guard let items = try? JSONDecoder().decode([LossyItem<E>].self, from: data) else {
            backup(data, key: key, reason: nil)
            return nil
        }
        backup(data, key: key, reason: nil)
        return items.compactMap(\.value)
    }

    private struct LossyItem<E: Decodable>: Decodable {
        let value: E?
        init(from decoder: Decoder) throws { value = try? E(from: decoder) }
    }

    /// Копия сохранённых данных, которые не удалось прочитать: Application Support/Backups/<ключ>-<время>.json.
    private static func backup(_ data: Data, key: String, reason: Error?) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: folder.appendingPathComponent("\(key)-\(stamp).json"), options: [.atomic, .completeFileProtection])
        if let reason { print("[storage] \(key): не прочиталось (\(reason)); копия сохранена") }
    }
    private func scheduleSave<T: Encodable>(_ value: T, key: String) {
        pendingSaves[key] = { [weak self] in
            do { UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: key) }
            catch { self?.storageError = "Не удалось сохранить изменения на устройстве." }
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
    /// Writes all pending changes immediately (called when the app goes to background).
    func flush() {
        let saves = pendingSaves
        pendingSaves.removeAll()
        saves.values.forEach { $0() }
    }

    // MARK: Multiple project workspaces

    var activeWorkspace: ProjectWorkspace? {
        guard let activeProjectID else { return nil }
        return projectWorkspaces.first { $0.id == activeProjectID }
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectID, let workspace = projectWorkspaces.first(where: { $0.id == id }) else { return }
        persistActiveWorkspace()
        activeProjectID = id
        UserDefaults.standard.set(id.uuidString, forKey: "activeProjectID")
        restoreWorkspace(workspace)
    }

    @discardableResult
    func createProject(name: String, address: String) -> UUID {
        persistActiveWorkspace()
        var passport = ObjectPassport()
        passport.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Новый объект" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        passport.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = ProjectWorkspace(passport: passport)
        projectWorkspaces.append(workspace)
        activeProjectID = workspace.id
        UserDefaults.standard.set(workspace.id.uuidString, forKey: "activeProjectID")
        restoreWorkspace(workspace)
        scheduleSave(projectWorkspaces, key: "projectWorkspaces")
        return workspace.id
    }

    private func restoreWorkspace(_ workspace: ProjectWorkspace) {
        isRestoringWorkspace = true
        passport = workspace.passport
        checklistDone = workspace.checklistDone
        diary = workspace.diary
        milestones = workspace.milestones
        budgetItems = workspace.budgetItems
        projectPhotos = workspace.projectPhotos
        floorPlans = workspace.floorPlans
        projectTasks = workspace.tasks
        isRestoringWorkspace = false
    }

    private func persistActiveWorkspace() {
        guard !isRestoringWorkspace, let activeProjectID,
              let index = projectWorkspaces.firstIndex(where: { $0.id == activeProjectID }) else { return }
        projectWorkspaces[index] = ProjectWorkspace(
            id: activeProjectID,
            passport: passport,
            checklistDone: checklistDone,
            diary: diary,
            milestones: milestones,
            budgetItems: budgetItems,
            projectPhotos: projectPhotos,
            floorPlans: floorPlans,
            tasks: projectTasks
        )
        scheduleSave(projectWorkspaces, key: "projectWorkspaces")
    }

    func addProjectTask(title: String, assignee: String, dueDate: Date?, notes: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        projectTasks.insert(ProjectTask(
            title: cleanTitle,
            assignee: assignee.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ), at: 0)
    }

    // MARK: Local data

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }
    func addCalculation(_ result: SavedCalculation) {
        calculations.insert(result, at: 0)
        registerMeaningfulAction()
    }
    func toggleChecklist(_ id: String) {
        if checklistDone.contains(id) { checklistDone.remove(id) } else { checklistDone.insert(id) }
    }
    func addDiary(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        diary.insert(DiaryEntry(text: clean), at: 0)
    }
    func rememberInputs(_ values: [String: String], for kind: CalculationKind) {
        var copy = values
        copy["price"] = values["price"] ?? ""
        lastInputs[kind.rawValue] = copy
    }
    func registerMeaningfulAction() {
        meaningfulActions += 1
        UserDefaults.standard.set(meaningfulActions, forKey: "meaningfulActions")
    }
    /// Ask for a rating after the 3rd and 12th useful result, never more often.
    var shouldAskForReview: Bool { [3, 12].contains(meaningfulActions) }

    var projectDisplayName: String {
        let name = passport.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Мой объект" : name
    }
    var projectCity: String {
        let city = passport.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? (userRegion?.city ?? Brand.city) : city
    }
    var projectProgress: Double {
        milestones.isEmpty ? 0 : Double(milestones.filter(\.completed).count) / Double(milestones.count)
    }
    var nextMilestone: ProjectMilestone? { milestones.first { !$0.completed } }
    var budgetPlanned: Double { budgetItems.filter(\.included).reduce(0) { $0 + $1.planned } }
    var budgetActual: Double { budgetItems.filter(\.included).reduce(0) { $0 + $1.actual } }

    /// Moves the sections of a full estimate into the project budget as planned amounts.
    @discardableResult
    func applyEstimateToBudget(_ sections: [(title: String, amount: Double)]) -> Int {
        let aliases = ["Проёмы": "Коробка", "Логистика": "Доставка и техника", "Основание": "Фундамент", "Каркас": "Коробка", "Материал": "Коробка", "Изготовление": "Коробка", "Защита": "Фасад", "Монтаж": "Доставка и техника"]
        var grouped: [String: Double] = [:]
        var order: [String] = []
        for section in sections where section.amount > 0 {
            let title = aliases[section.title] ?? section.title
            if grouped[title] == nil { order.append(title) }
            grouped[title, default: 0] += section.amount
        }
        var items = budgetItems
        for title in order {
            let amount = (grouped[title] ?? 0).rounded()
            if let index = items.firstIndex(where: { $0.title == title }) {
                items[index].planned = amount
                items[index].included = true
            } else {
                items.append(ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: title, planned: amount, actual: 0, included: true))
            }
        }
        budgetItems = items
        return order.count
    }

    // MARK: Project photos

    func addProjectPhoto(_ image: UIImage, caption: String) throws {
        guard let data = image.jpegData(compressionQuality: 0.82) else { throw ProjectPhotoError.encoding }
        guard data.count <= 8_000_000 else { throw ProjectPhotoError.tooLarge }
        let id = UUID(), filename = "project-\(id.uuidString).jpg"
        let folder = try Self.projectImageFolder()
        try data.write(to: folder.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        projectPhotos.insert(ProjectPhoto(id: id, createdAt: .now, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), filename: filename), at: 0)
    }
    func projectPhotoURL(_ photo: ProjectPhoto) -> URL? {
        guard let folder = try? Self.projectImageFolder() else { return nil }
        let url = folder.appendingPathComponent(photo.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func deleteProjectPhotos(at offsets: IndexSet) {
        for index in offsets { if let url = projectPhotoURL(projectPhotos[index]) { try? FileManager.default.removeItem(at: url) } }
        projectPhotos.remove(atOffsets: offsets)
    }
    private static func projectImageFolder() throws -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MarkaryanProjectPhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Server

    private var serverBase: String {
        priceServerURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private func serverURL(_ path: String) -> URL? {
        let base = serverBase
        guard !base.isEmpty, base.lowercased().hasPrefix("http"), let url = URL(string: base + path) else { return nil }
        return url
    }

    func importPriceBook(from url: URL) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var book = try decoder.decode(PriceBook.self, from: Data(contentsOf: url))
        guard !book.lines.isEmpty else { throw PriceBookError.empty }
        book.coverage = "import"
        applyPriceBook(book)
        priceSyncMessage = "Прайс обновлён: \(book.lines.count) позиций."
    }

    // MARK: Region and market prices

    /// Server with market prices and partners: the platform AI server, else the configured server.
    private func marketURL(_ path: String, query: [URLQueryItem] = []) -> URL? {
        let base = AIServerConfig.marketURL?.absoluteString ?? serverBase
        guard base.lowercased().hasPrefix("http"), var components = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }
    private var regionQuery: [URLQueryItem] {
        guard let region = userRegion else { return [] }
        var items = [URLQueryItem(name: "city", value: region.city), URLQueryItem(name: "region", value: region.region)]
        if let lat = region.latitude, let lon = region.longitude {
            items += [URLQueryItem(name: "lat", value: String(format: "%.2f", lat)), URLQueryItem(name: "lon", value: String(format: "%.2f", lon))]
        }
        return items
    }

    /// Asks for the city once: from location if allowed, otherwise opens the manual city choice.
    func ensureRegion() async {
        guard userRegion == nil, !regionDetecting else { return }
        if !(await detectRegion()) { showRegionPicker = true }
    }

    @discardableResult
    func detectRegion() async -> Bool {
        regionDetecting = true
        defer { regionDetecting = false; locationDenied = locationService.isDenied }
        guard let location = await locationService.currentLocation(), let region = await LocationService.region(for: location) else { return false }
        setRegion(region)
        return true
    }

    func setRegion(_ region: UserRegion) {
        guard region != userRegion else { return }
        userRegion = region
        track("region_\(region.source.rawValue)")
        Task { await refreshPriceBook(silent: true) }
    }

    /// - Parameter silent: background refresh (launch) never shows alerts; only a manual refresh reports the result.
    func refreshPriceBook(silent: Bool = false) async {
        guard let region = userRegion else {
            if !silent { showRegionPicker = true }
            return
        }
        guard let url = marketURL("/v1/market/price-book", query: regionQuery) else {
            if !silent { priceSyncMessage = "Сервер рыночных цен не настроен." }
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = silent ? 8 : 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PriceBookError.server }
            if http.statusCode == 404 {
                useBasePrices(for: region)
                if !silent { priceSyncMessage = "Для города \(region.city) рыночные цены пока не собраны. Смета посчитана по базовым ориентирам." }
                return
            }
            guard (200...299).contains(http.statusCode) else { throw PriceBookError.server }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let market = try decoder.decode(PriceBook.self, from: data)
            guard !market.lines.isEmpty else { throw PriceBookError.empty }
            // Market lines replace the base guide line by line; lines without market data stay as a marked guide.
            let byCode = Dictionary(market.lines.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
            let baseCodes = Set(PriceBook.default.lines.map(\.code))
            var book = market
            book.lines = PriceBook.default.lines.map { base in
                guard var line = byCode[base.code] else { return base }
                // A side without market data (e.g. only material offers were found) keeps the base guide rate.
                let sides = line.marketData ?? []
                if !sides.contains("material") { line.materialRate = base.materialRate; line.materialLow = nil; line.materialHigh = nil }
                if !sides.contains("labor") { line.laborRate = base.laborRate; line.laborLow = nil; line.laborHigh = nil }
                return line
            } + market.lines.filter { !baseCodes.contains($0.code) }
            applyPriceBook(book)
            if !silent { priceSyncMessage = "Рыночные цены: \(book.city ?? region.city), \(book.marketLineCount) из \(book.lines.count) позиций, от \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))." }
        } catch {
            // Never keep prices of another city after the city was changed.
            if priceBook.city != nil, priceBook.city != region.city, priceBook.coverage != "nearby" { useBasePrices(for: region) }
            if !silent { priceSyncMessage = "Не удалось обновить цены: \(error.localizedDescription)" }
        }
    }

    private func useBasePrices(for _: UserRegion) {
        var book = PriceBook.default
        book.coverage = "base"
        priceBook = book
        lastPriceSync = .now
    }

    // MARK: Partner contractors (advertising)

    func partners(category: String) async -> [Partner] {
        guard userRegion != nil, let url = marketURL("/v1/partners", query: regionQuery + [URLQueryItem(name: "category", value: category)]) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let result = try? await session.data(for: request), (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode(PartnersResponse.self, from: result.0).partners) ?? []
    }

    /// Views and clicks are counted per partner for advertising reports.
    func partnerEvent(_ partnerID: String, _ type: String) {
        guard let url = marketURL("/v1/partners/\(partnerID)/events"), let body = try? JSONSerialization.data(withJSONObject: ["type": type]) else { return }
        Task { _ = try? await postJSON(url, body: body, timeout: 10) }
    }

    private func applyPriceBook(_ book: PriceBook) {
        // Compare by code, not by position: the owner can reorder lines in the price file.
        let previous = Dictionary(priceBook.lines.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = book.lines.filter { line in
            guard let old = previous[line.code] else { return false }
            return old.materialRate != line.materialRate || old.laborRate != line.laborRate
        }.count
        priceBook = book
        lastPriceSync = .now
        if changed > 0 { priceAlert = "Обновлён прайс: изменено позиций — \(changed). Пересчитайте смету." }
    }

    /// Lightweight connectivity check for the settings screen.
    func checkServer(_ base: String? = nil) async -> String {
        let root = (base ?? serverBase).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard root.lowercased().hasPrefix("http"), let url = URL(string: root + "/v1/public/price-book") else { return "Адрес должен начинаться с https://" }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 10
            let started = Date()
            let (_, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else { return "Сервер не ответил." }
            return (200...299).contains(http.statusCode) ? "Сервер доступен · \(ms) мс" : "Сервер ответил с кодом \(http.statusCode)"
        } catch { return String(localized: "Нет связи: \(error.localizedDescription)") }
    }

    private func postJSON(_ url: URL, body: Data, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        return (data, response as? HTTPURLResponse)
    }

    private static func serverMessage(_ data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = raw["message"] as? String, !message.isEmpty else { return nil }
        return message
    }

    /// - Parameter history: previous turns. They are added to the question so the assistant keeps the thread;
    ///   if the server rejects the longer prompt, the question is retried on its own.
    func askAssistant(question: String, context: AIAssistantContext, history: [(question: String, answer: String)] = []) async throws -> AIAssistantReply {
        if let claude = usesAIServer ? helperEngine : claudeClient {
            let answer = try await claude.complete(system: ClaudePrompts.assistantSystem(context: context), turns: Self.turns(history: history, question: question, image: nil))
            track("assistant_answer_claude")
            return AIAssistantReply(answer: answer, links: nil)
        }
        guard let url = serverURL("/v1/public/assistant") else { throw AIAssistantError.serverAddress }
        func encode(_ text: String) throws -> Data {
            try JSONEncoder().encode(["question": AnyEncodable(text), "context": AnyEncodable(context)])
        }
        var prompts = [question]
        if let last = history.last {
            let threaded = "Предыдущий вопрос: \(last.question.prefix(300))\nКраткий ответ: \(last.answer.prefix(500))\n\nНовый вопрос: \(question)"
            prompts.insert(threaded, at: 0)
        }
        var lastError: Error = AIAssistantError.server
        for prompt in prompts {
            do {
                let (data, http) = try await postJSON(url, body: try encode(prompt), timeout: 55)
                guard let http else { throw AIAssistantError.server }
                guard (200...299).contains(http.statusCode) else {
                    throw Self.serverMessage(data).map { AIAssistantError.message($0) } ?? AIAssistantError.server
                }
                let reply = try JSONDecoder().decode(AIAssistantReply.self, from: data)
                guard !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIAssistantError.server }
                track("assistant_answer")
                return reply
            } catch let networkError as URLError {
                throw networkError // a network failure will not be fixed by a shorter prompt
            } catch { lastError = error }
        }
        throw lastError
    }

    // MARK: Claude

    var usesClaude: Bool { aiPreference != .server && hasClaudeKey }
    var aiEngineTitle: String {
        guard usesClaude && AIServerConfig.baseURL == nil else { return "Сервер приложения" }
        let model = claudeModel.title.components(separatedBy: " — ").first ?? "Claude"
        return OpenRouterImageClient.isConfigured ? "\(model) через OpenRouter" : model
    }
    /// The AI the app talks to: the app's AI server when its address is set; otherwise the user's own key
    /// (Anthropic or OpenRouter) from the Keychain of this iPhone. Keys from files in the app — only in debug builds.
    private var claudeClient: (any AIEngine)? {
        if let base = AIServerConfig.baseURL { return ServerAIClient(base: base) }
        guard usesClaude, let key = ClaudeClient.currentKey else { return nil }
        return ClaudeClient(apiKey: key, model: claudeModel.rawValue, workspaceID: ClaudeClient.isOpenRouterKey(key) ? nil : ClaudeClient.currentWorkspaceID)
    }
    /// The helper's AI: the server's cheap fast model; with the owner's own key — Claude Haiku.
    var helperEngine: (any AIEngine)? {
        if let base = AIServerConfig.baseURL { return ServerAIClient(base: base, tier: "helper") }
        guard usesClaude, let key = ClaudeClient.currentKey else { return nil }
        return ClaudeClient(apiKey: key, model: ClaudeModel.haiku.rawValue, workspaceID: ClaudeClient.isOpenRouterKey(key) ? nil : ClaudeClient.currentWorkspaceID)
    }
    /// The AI for the concept and the layout: the same engine as `claudeClient`, with the model picked on the
    /// «Дизайн» step first and the other models behind it. A key of Anthropic itself runs Claude models only.
    private var designEngine: (any AIEngine)? {
        if let base = AIServerConfig.baseURL { return ServerAIClient(base: base, designModel: designModel.rawValue) }
        guard usesClaude, let key = ClaudeClient.currentKey else { return nil }
        if ClaudeClient.isOpenRouterKey(key) {
            return ClaudeClient(apiKey: key, model: designModel.rawValue, workspaceID: nil, fallbacks: designModel.fallbacks)
        }
        return ClaudeClient(apiKey: key, model: designModel.anthropicID ?? claudeModel.rawValue, workspaceID: ClaudeClient.currentWorkspaceID)
    }

    /// Whether the picks on the «Дизайн» step reach the AI: (design, render). An older server or another gateway
    /// chooses by itself; a key of Anthropic runs only the Claude models.
    var modelChoiceWorks: (design: Bool, render: Bool) {
        if AIServerConfig.baseURL != nil { return (!aiCapabilities.designModels.isEmpty, !aiCapabilities.renderModels.isEmpty) }
        guard usesClaude, let key = ClaudeClient.currentKey else { return (false, false) }
        if ClaudeClient.isOpenRouterKey(key) { return (true, true) }
        return (designModel.anthropicID != nil, false)
    }

    /// Some AI answers now: the server or a key on this iPhone.
    var aiAvailable: Bool { claudeClient != nil }
    var usesAIServer: Bool { AIServerConfig.baseURL != nil }

    /// What the AI server can do now (photoreal engines etc.). Refreshed at launch and before a presentation.
    @Published var aiCapabilities = AICapabilities()
    func refreshAICapabilities() async {
        guard let base = AIServerConfig.baseURL, let caps = try? await ServerAIClient(base: base).capabilities() else { return }
        aiCapabilities = caps
    }
    func setClaudeKey(_ key: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { KeychainStore.delete(ClaudeClient.keyAccount) } else { KeychainStore.save(clean, account: ClaudeClient.keyAccount) }
        hasClaudeKey = ClaudeClient.currentKey != nil
    }
    func testClaude() async -> String {
        guard let claude = claudeClient else { return "ИИ не подключён: впишите OPENROUTER_API_KEY в AIServer.plist и пересоберите приложение." }
        do {
            let answer = try await claude.complete(system: "Отвечай одним коротким предложением по-русски.", turns: [ClaudeTurn(role: .user, text: "Скажи, что ты готов помогать.")], maxTokens: 60)
            return String(localized: "Работает: \(answer)")
        } catch { return error.localizedDescription }
    }
    private static func turns(history: [(question: String, answer: String)], question: String, image: UIImage?) -> [ClaudeTurn] {
        var turns: [ClaudeTurn] = []
        for pair in history.suffix(8) {
            turns.append(ClaudeTurn(role: .user, text: pair.question))
            turns.append(ClaudeTurn(role: .assistant, text: pair.answer))
        }
        turns.append(ClaudeTurn(role: .user, text: question, image: image))
        return turns
    }
    /// Streaming answer from Claude, or nil when the server engine is used.
    func streamAssistant(question: String, context: AIAssistantContext, history: [(question: String, answer: String)], image: UIImage?) -> AsyncThrowingStream<String, Error>? {
        guard let claude = usesAIServer ? helperEngine : claudeClient else { return nil }
        track("assistant_stream")
        return claude.stream(system: ClaudePrompts.assistantSystem(context: context), turns: Self.turns(history: history, question: question, image: image), maxTokens: 2500)
    }

    // MARK: Floor plans

    func savePlan(_ plan: FloorPlan) {
        if let index = floorPlans.firstIndex(where: { $0.id == plan.id }) { floorPlans[index] = plan } else { floorPlans.insert(plan, at: 0) }
    }
    // MARK: Apartments (rooms of one scan)

    var apartments: [Apartment] { Apartment.group(floorPlans) }

    func renameApartment(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        floorPlans = floorPlans.map { plan in
            var renamed = plan
            if plan.apartmentID == id { renamed.apartmentName = clean }
            return renamed
        }
    }

    /// The rooms stay, each on its own.
    func ungroupApartment(_ id: UUID) {
        floorPlans = floorPlans.map { plan in
            var single = plan
            if plan.apartmentID == id { single.apartmentID = nil; single.apartmentName = nil }
            return single
        }
    }

    func deleteApartment(_ id: UUID) {
        for plan in floorPlans.filter({ $0.apartmentID == id }) { deletePlan(plan) }
    }

    func deletePlan(_ plan: FloorPlan) {
        if let url = planModelURL(plan) { try? FileManager.default.removeItem(at: url) }
        if let folder = try? Self.presentationsFolder() {
            for proposal in plan.proposals { try? FileManager.default.removeItem(at: folder.appendingPathComponent(proposal.id.uuidString, isDirectory: true)) }
        }
        floorPlans.removeAll { $0.id == plan.id }
    }
    static func planModelFolder() throws -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MarkaryanRoomScans", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    func planModelURL(_ plan: FloorPlan) -> URL? {
        guard let name = plan.modelFilename, let folder = try? Self.planModelFolder() else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Saved presentations (the PDF and pictures of a concept, kept on the iPhone)

    static func presentationsFolder() throws -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MarkaryanPresentations", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Keeps a finished presentation with its concept: opening the plan again shows it without paying for new renders.
    @discardableResult
    func savePresentation(pdf: URL, pictures: [(title: String, image: UIImage)], engine: String?, proposalID: UUID, planID: UUID) throws -> SavedPresentation {
        let folderName = proposalID.uuidString
        let folder = try Self.presentationsFolder().appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: pdf, to: folder.appendingPathComponent(pdf.lastPathComponent))
        var saved: [SavedPresentation.Picture] = []
        for (index, picture) in pictures.enumerated() {
            guard let data = picture.image.jpegData(compressionQuality: 0.93) else { continue }
            let name = "picture-\(index + 1).jpg"
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            saved.append(SavedPresentation.Picture(title: picture.title, file: name))
        }
        let record = SavedPresentation(folder: folderName, pdf: pdf.lastPathComponent, pictures: saved, engine: engine)
        if var plan = floorPlans.first(where: { $0.id == planID }), let index = plan.proposals.firstIndex(where: { $0.id == proposalID }) {
            plan.proposals[index].presentation = record
            savePlan(plan)
        }
        return record
    }

    /// A file of a saved presentation, if it is still on the iPhone.
    func presentationFile(_ record: SavedPresentation, _ name: String) -> URL? {
        guard let folder = try? Self.presentationsFolder() else { return nil }
        let url = folder.appendingPathComponent(record.folder, isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Counts bar/board/pipe ends on a photo with Claude vision.
    /// Returns centres in 0…1 image coordinates; the user then corrects them by tapping.
    /// - Parameter object: what to count, or nil to let the AI recognise the material itself.
    func countObjectsOnPhoto(_ image: UIImage, object: String?) async throws -> (points: [CGPoint], note: String, kind: String, name: String) {
        guard let claude = claudeClient else { throw ClaudeError.api("ИИ не подключён: впишите OPENROUTER_API_KEY в AIServer.plist.") }
        struct Result: Decodable {
            struct Point: Decodable { let x: Double; let y: Double }
            let points: [Lossy<Point>]
            let note: String?
            let kind: String?
            let objectName: String?
        }
        let target = object ?? "сначала сам определи, что изображено (арматура, трубы, доски, брус или другие предметы — гайки, болты, кирпичи, мешки и т.п.), и считай именно эти предметы"
        let system = """
        Ты точно считаешь предметы на фото. Что считать: \(target).
        В kind укажи тип: rebar (арматура), pipe (трубы), board (доски), timber (брус) или other (всё остальное). В objectName — короткое название по‑русски, например «Гайки М12» или «Арматура».
        Найди КАЖДЫЙ отдельный экземпляр (для пачек — каждый торец: круг арматуры или трубы, прямоугольник доски или бруса) и верни координаты его центра.
        Координаты: x и y от 0 до 1000, (0,0) — левый верхний угол изображения, (1000,1000) — правый нижний.
        Считай только нужные предметы, не считай фон, тени, отражения и посторонние вещи. Не пропускай частично закрытые предметы по краям и в кучах.
        Если торцов очень много, будь особенно внимателен к плотным рядам. В note коротко напиши, насколько уверен и что мешало.
        """
        let schema: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(#"""
        {"type":"object","properties":{
          "points":{"type":"array","items":{"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}},
          "kind":{"type":"string","enum":["rebar","pipe","board","timber","other"]},
          "objectName":{"type":"string"},
          "note":{"type":"string"}},"required":["kind","objectName","points","note"]}
        """#.utf8))) as? [String: Any] ?? [:]
        let data = try await claude.structured(system: system, turns: [ClaudeTurn(role: .user, text: "Посчитай торцы на фото и верни центр каждого.", image: image)], toolName: "count_result", toolDescription: "Центры всех найденных торцов", schema: schema, maxTokens: 16000)
        let result = try JSONDecoder().decode(Result.self, from: data)
        track("photo_count")
        registerMeaningfulAction()
        let points = result.points.compactMap(\.value)
            .filter { (0...1000).contains($0.x) && (0...1000).contains($0.y) }
            .map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }
        return (points, result.note ?? "", result.kind ?? "other", result.objectName ?? "")
    }

    // MARK: Pictures: photoreal render of the exact 3D model, pictures by description

    /// Picture engines on the server, in its order (the first answers when no engine is chosen),
    /// and the render models it offers — so the owner's comparison covers the three choices too.
    var imageEngines: [ImageEngine] {
        let engines = aiCapabilities.imageEngines
        return engines + aiCapabilities.renderModels.filter { choice in !engines.contains { $0.id == choice.id } }
    }

    /// Something can turn the exact 3D render into a photo: the server, or a key in the owner's debug build.
    var photorealAvailable: Bool {
        !aiCapabilities.imageEngines.isEmpty || !aiCapabilities.imageEdit.isEmpty || OpenRouterImageClient.isConfigured || FluxClient.isConfigured || OpenAIImageClient.isConfigured
    }

    /// Image models understand English best: the AI translates the brief when it is available.
    func englishPrompt(_ text: String) async -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil, let claude = helperEngine else { return clean }
        let translated = try? await claude.complete(system: "Translate the user's text into a concise English prompt for a photorealistic image model. Output only the prompt, no quotes.", turns: [ClaudeTurn(role: .user, text: clean)], maxTokens: 300)
        return translated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? clean
    }

    /// Photoreal version of an image (the exact 3D render or a photo of the site).
    /// `engine`: nil — the render model picked on the «Дизайн» step first, the next engine when it fails;
    /// an engine id — only that engine (owner comparison).
    func photorealRender(_ image: UIImage, prompt: String, engine: String? = nil, references: [MaterialReference] = []) async throws -> RenderedImage {
        if let base = AIServerConfig.baseURL, !aiCapabilities.imageEngines.isEmpty || !aiCapabilities.imageEdit.isEmpty || !aiCapabilities.renderModels.isEmpty {
            // A server before 1.3 knows only "flux" and "gpt".
            let chosen = engine ?? (aiCapabilities.imageEngines.isEmpty && aiCapabilities.renderModels.isEmpty ? aiCapabilities.imageEdit.first ?? "auto" : "auto")
            let result = try await ServerAIClient(base: base).editImage(image, prompt: prompt, engine: chosen, prefer: engine == nil ? renderModel.engineID : nil, references: references)
            track("photoreal_server")
            registerMeaningfulAction()
            return result
        }
        // The user's own OpenRouter key on this iPhone: the picked model first.
        if let key = OpenRouterImageClient.configuredKey {
            // A given engine (owner comparison) runs alone; otherwise the picked model, then the others.
            let order = engine.map { [$0.hasPrefix("openrouter:") ? String($0.dropFirst("openrouter:".count)) : $0] } ?? renderModel.order
            let result = try await OpenRouterImageClient(apiKey: key).render(prompt: prompt, reference: image, models: order)
            track("photoreal_openrouter")
            registerMeaningfulAction()
            return result
        }
        // Owner's debug builds with keys in the app.
        if let key = FluxClient.configuredKey {
            let picture = try await FluxClient(apiKey: key, model: .max).edit(image, prompt: prompt)
            track("flux_render")
            registerMeaningfulAction()
            return RenderedImage(image: picture, engine: "local:flux-kontext-max", title: "FLUX Kontext Max")
        }
        if let key = OpenAIImageClient.configuredKey {
            let picture = try await OpenAIImageClient(apiKey: key).edit(image, prompt: prompt)
            track("gpt_render")
            registerMeaningfulAction()
            return RenderedImage(image: picture, engine: "local:gpt-image", title: "GPT Image")
        }
        throw ClaudeError.api("Картинки ИИ не подключены: впишите OPENROUTER_API_KEY в AIServer.plist.")
    }

    /// Photoreal pictures by description: the server's picture engines, or a FLUX key in the owner's debug build.
    var picturesByDescriptionAvailable: Bool { !aiCapabilities.imageEngines.isEmpty || OpenRouterImageClient.isConfigured || FluxClient.isConfigured }

    /// Picture by description, without a source photo: the server's picture engines (or Kandinsky / Alice AI ART);
    /// FLUX.2 with a key in the owner's debug build.
    func pictureByDescription(_ prompt: String) async throws -> UIImage {
        if let base = AIServerConfig.baseURL, aiCapabilities.imageGenerate || !aiCapabilities.imageEngines.isEmpty {
            let picture = try await ServerAIClient(base: base).generateImage(prompt: prompt, prefer: renderModel.engineID)
            track("picture_server")
            registerMeaningfulAction()
            return picture
        }
        if let key = OpenRouterImageClient.configuredKey {
            let result = try await OpenRouterImageClient(apiKey: key).render(prompt: prompt, reference: nil, models: renderModel.order)
            track("picture_openrouter")
            registerMeaningfulAction()
            return result.image
        }
        guard let key = FluxClient.configuredKey else { throw ClaudeError.api("Картинки ИИ не подключены: впишите OPENROUTER_API_KEY в AIServer.plist.") }
        let picture = try await FluxClient(apiKey: key).generate(prompt: prompt)
        track("flux_generate")
        registerMeaningfulAction()
        return picture
    }

    /// AI interior concept for a plan: the AI (app server, or Claude directly in the owner's debug builds) chooses
    /// the items, their real sizes and where they belong (wall, corner, next to what) and writes the finishes;
    /// `LayoutEngine` places everything by the rules. Without a working AI the built‑in designer does the same on the iPhone.
    func generateDesign(for plan: FloorPlan, planImage: UIImage?, style: String, purpose: String, wishes: String) async throws -> DesignProposal {
        let room = DesignComposer.room(plan: plan, purpose: purpose)
        let request = """
        Помещение: \(purpose). Стиль: \(style).
        \(room.rulesRussian)
        Пожелания клиента: \(wishes.isEmpty ? "нет, предложи лучший вариант" : wishes)
        План помещения (JSON): \(PlanWalls.aiDescription(plan))
        На картинке — тот же план сверху, номера стен в кружках. Выбери состав мебели и оборудования с реальными размерами и привязками к стенам и друг к другу — координаты не нужны, расстановку по правилам сделает приложение.
        """
        // Without a working AI (no key, disabled account, no internet) the built‑in designer makes the project on the iPhone.
        func offline() throws -> DesignProposal {
            guard let proposal = OfflineDesigner.propose(plan: plan, style: style, purpose: purpose, wishes: wishes) else {
                throw ClaudeError.api("Не удалось расставить предметы в этом помещении. Проверьте скан.")
            }
            track("design_offline")
            registerMeaningfulAction()
            return proposal
        }
        guard claudeClient != nil else { return try offline() }
        do { return try await aiDesign(for: plan, planImage: planImage, purpose: purpose, request: request) }
        catch { return try offline() }
    }

    private func aiDesign(for plan: FloorPlan, planImage: UIImage?, purpose: String, request: String) async throws -> DesignProposal {
        guard let claude = designEngine else { throw ClaudeError.noKey }
        let picked = designModel
        func ask(_ text: String) async throws -> DesignProposal {
            let answer = try await claude.structuredAnswer(system: ClaudePrompts.designSystem, turns: [ClaudeTurn(role: .user, text: text, image: planImage)], toolName: "design_proposal", toolDescription: "Концепция дизайна: мебель и оборудование с привязками к стенам, отделка, свет и бюджет", schema: ClaudePrompts.designSchema, maxTokens: 16000)
            var proposal = try DesignComposer.proposal(from: answer.data, plan: plan, purpose: purpose)
            // Which model made it: the one that answered, or the picked one when the engine does not say.
            proposal.designModel = answer.model ?? (modelChoiceWorks.design ? picked.rawValue : nil)
            return proposal
        }
        var proposal = try await ask(request)
        if proposal.furniture.isEmpty {
            // An empty layout gives an empty plan and an empty 3D model: ask once more, explicitly.
            let retry = request + "\n\nВАЖНО: в прошлом ответе не было предметов или ни один не поместился. Обязательно заполни items реальными предметами с размерами в метрах, которые помещаются в эту комнату."
            if let second = try? await ask(retry), !second.furniture.isEmpty { proposal = second }
        }
        guard !proposal.furniture.isEmpty else { throw ClaudeError.api("ИИ не прислал расстановку. Нажмите «Создать» ещё раз.") }
        track("design_ai")
        registerMeaningfulAction()
        return proposal
    }

    func createVisualization(style: String, brief: String, source: UIImage?) async throws -> UIImage {
        guard let url = serverURL("/v1/public/visualization") else { throw VisualizationError.serverAddress }
        var values: [String: AnyEncodable] = ["style": AnyEncodable(style), "brief": AnyEncodable(brief)]
        if let source { values["imageBase64"] = AnyEncodable(try Self.compactJPEG(source, maxDimension: 1600, quality: 0.78, limit: 5_000_000, failure: VisualizationError.imagePreparation).base64EncodedString()) }
        let (data, http) = try await postJSON(url, body: try JSONEncoder().encode(values), timeout: 120)
        guard let http else { throw VisualizationError.server }
        guard (200...299).contains(http.statusCode) else {
            throw Self.serverMessage(data).map { VisualizationError.message($0) } ?? VisualizationError.server
        }
        let result = try JSONDecoder().decode(VisualizationResponse.self, from: data)
        guard let generated = Data(base64Encoded: result.imageBase64), let image = UIImage(data: generated) else { throw VisualizationError.imageDecoding }
        return image
    }

    private static func compactJPEG(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat, limit: Int, failure: Error) throws -> Data {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.jpegData(compressionQuality: quality), data.count <= limit else { throw failure }
        return data
    }

    // MARK: Analytics (anonymous)

    func track(_ name: String) {
        guard let url = serverURL("/v1/public/events") else { return }
        let payload: [String: Any] = ["name": name, "createdAt": ISO8601DateFormatter().string(from: .now), "appVersion": Brand.appVersion]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task { _ = try? await postJSON(url, body: body, timeout: 10) }
    }
}

enum ProjectPhotoError: LocalizedError {
    case encoding, tooLarge
    var errorDescription: String? { switch self { case .encoding: return "Не удалось подготовить фото."; case .tooLarge: return "Выберите фото меньшего размера." } }
}

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
enum PriceBookError: LocalizedError { case empty, server; var errorDescription: String? { switch self { case .empty: return "В прайсе нет позиций."; case .server: return "Сервер не принял запрос." } } }
struct ARTransfer: Identifiable {
    let id = UUID()
    let kind: CalculationKind
    let key: String
    let value: Double
}
