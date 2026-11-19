import SwiftUI
import QuickLook

// MARK: - Top-down plan drawing

/// Architectural top view: floor, walls, windows, doors with swing arcs, wall lengths,
/// scanned furniture and (optionally) the AI concept with zones and furniture.
struct FloorPlanCanvas: View {
    let plan: FloorPlan
    var proposal: DesignProposal?
    var showDimensions = true
    var compact = false
    /// Wall numbers in circles (the picture sent to the AI: «стена 2» in its answer is the wall marked 2 here).
    var wallNumbers = false

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let ink = Color(red: 0.13, green: 0.15, blue: 0.14)

    /// Space around the plan inside the canvas (the editors use the same to hit what is drawn).
    static func margin(compact: Bool) -> Double { compact ? 10 : 34 }

    var body: some View {
        let proposal = self.proposal?.placed(in: plan)
        return Canvas { context, size in
            let b = plan.bounds
            let viewport = PlanViewport(plan: plan, width: Double(size.width), height: Double(size.height), margin: Self.margin(compact: compact))
            let scale = CGFloat(viewport.scale)
            func p(_ point: PlanPoint) -> CGPoint { let s = viewport.screen(point); return CGPoint(x: s.x, y: s.y) }
            func pt(_ x: Double, _ y: Double) -> CGPoint { p(PlanPoint(x: x, y: y)) }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            // Floor
            let outline = plan.floorPolygon.count >= 3 ? plan.floorPolygon : [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
            var floor = Path(); floor.addLines(outline.map(p)); floor.closeSubpath()
            context.fill(floor, with: .color(Color(red: 0.91, green: 0.88, blue: 0.82)))
            // Grid 1 m
            if !compact {
                var grid = Path()
                var x = (b.minX).rounded(.down)
                while x <= b.maxX { grid.move(to: pt(x, b.minY)); grid.addLine(to: pt(x, b.maxY)); x += 1 }
                var y = (b.minY).rounded(.down)
                while y <= b.maxY { grid.move(to: pt(b.minX, y)); grid.addLine(to: pt(b.maxX, y)); y += 1 }
                context.stroke(grid, with: .color(ink.opacity(0.06)), lineWidth: 0.5)
            }
            // AI zones
            if let proposal {
                let zoneColors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]
                for (index, zone) in proposal.zones.enumerated() {
                    let rect = CGRect(origin: pt(zone.x - zone.width / 2, zone.y - zone.depth / 2), size: CGSize(width: CGFloat(zone.width) * scale, height: CGFloat(zone.depth) * scale))
                    let color = zoneColors[index % zoneColors.count]
                    context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color.opacity(0.10)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    if !compact { context.draw(Text(zone.name.uppercased()).font(.system(size: 8, weight: .bold)).foregroundColor(color.opacity(0.9)), at: CGPoint(x: rect.minX + 4, y: rect.minY + 4), anchor: .topLeading) }
                }
            }
            // Scanned furniture (only when no AI concept is shown)
            if proposal == nil {
                for object in plan.objects {
                    let path = rotatedRect(center: p(object.center), width: CGFloat(object.width) * scale, depth: CGFloat(object.depth) * scale, radians: object.rotation)
                    context.fill(path, with: .color(ink.opacity(0.12)))
                    context.stroke(path, with: .color(ink.opacity(0.45)), lineWidth: 0.8)
                    if !compact { context.draw(Text(object.name).font(.system(size: 7.5)).foregroundColor(ink.opacity(0.7)), at: p(object.center)) }
                }
            }
            // AI furniture
            if let proposal {
                for item in proposal.furniture {
                    let path = rotatedRect(center: pt(item.x, item.y), width: CGFloat(item.width) * scale, depth: CGFloat(item.depth) * scale, radians: item.rotation * .pi / 180)
                    let color = FurnitureStyle.color(item.model)
                    context.fill(path, with: .color(color.opacity(0.85)))
                    context.stroke(path, with: .color(ink.opacity(0.55)), lineWidth: 0.8)
                    if !compact && min(item.width, item.depth) * Double(scale) > 18 {
                        context.draw(Text(item.name).font(.system(size: 7.5, weight: .semibold)).foregroundColor(ink), at: pt(item.x, item.y))
                    }
                }
            }
            // Walls: one closed contour outward from the scanned line, the same as on the drawings and in 3D.
            let body = WallBody(plan: plan, thickness: max(WallBody.standardThickness, Double((compact ? 2.5 : 4) / max(scale, 0.001))))
            let wallPoints = CGFloat(body.thickness) * scale
            var walls = Path()
            for piece in body.pieces { walls.addLines(piece.polygon.map(p)); walls.closeSubpath() }
            context.fill(walls, with: .color(ink))
            for gap in body.gaps {
                if gap.opening.kind == .window {
                    // Window: frame lines on both faces, the glass in the middle of the wall.
                    var frame = Path()
                    for k in [0.0, 1.0] {
                        frame.move(to: p(gap.innerStart + gap.outward * (gap.thickness * k)))
                        frame.addLine(to: p(gap.innerEnd + gap.outward * (gap.thickness * k)))
                    }
                    context.stroke(frame, with: .color(ink), lineWidth: 1)
                    var glass = Path()
                    glass.move(to: p(gap.innerStart + gap.outward * (gap.thickness / 2)))
                    glass.addLine(to: p(gap.innerEnd + gap.outward * (gap.thickness / 2)))
                    context.stroke(glass, with: .color(Color(red: 0.25, green: 0.55, blue: 0.85)), lineWidth: 2)
                } else if gap.opening.kind == .door && !compact {
                    // Leaf opens into the room from the hinge at the start of the door — the same as on the drawings and in 3D.
                    let hinge = gap.innerStart.distance(to: gap.opening.start) <= gap.innerEnd.distance(to: gap.opening.start) ? gap.innerStart : gap.innerEnd
                    let latch = hinge == gap.innerStart ? gap.innerEnd : gap.innerStart
                    let a = p(hinge), c = p(latch)
                    let leafEnd = p(hinge + gap.outward * -hinge.distance(to: latch))
                    let radius = hypot(c.x - a.x, c.y - a.y)
                    let start = atan2(c.y - a.y, c.x - a.x), finish = atan2(leafEnd.y - a.y, leafEnd.x - a.x)
                    var sweep = finish - start
                    if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
                    var leaf = Path(); leaf.move(to: a); leaf.addLine(to: leafEnd)
                    var arc = Path()
                    arc.addLines((0...16).map { step in
                        let angle = start + sweep * CGFloat(step) / 16
                        return CGPoint(x: a.x + cos(angle) * radius, y: a.y + sin(angle) * radius)
                    })
                    context.stroke(leaf, with: .color(Theme.orange), lineWidth: 1.2)
                    context.stroke(arc, with: .color(Theme.orange.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                }
            }
            // Wall lengths
            if showDimensions && !compact {
                let center = pt((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2)
                for wall in plan.walls where wall.length > 0.4 {
                    let a = p(wall.start), c = p(wall.end)
                    let mid = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2)
                    var normal = CGPoint(x: -(c.y - a.y), y: c.x - a.x)
                    let len = max(0.001, hypot(normal.x, normal.y)); normal = CGPoint(x: normal.x / len, y: normal.y / len)
                    // Put the label outside the room.
                    if (mid.x + normal.x - center.x) * normal.x + (mid.y + normal.y - center.y) * normal.y < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
                    let label = CGPoint(x: mid.x + normal.x * (wallPoints + 10), y: mid.y + normal.y * (wallPoints + 10))
                    context.draw(Text(String(format: "%.2f м", wall.length).replacingOccurrences(of: ".", with: ",")).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundColor(ink.opacity(0.8)), at: label)
                }
            }
            if wallNumbers && !compact {
                for wall in PlanWalls.numbered(plan) {
                    let center = p(wall.point(wall.length / 2, offset: 0.32))
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)), with: .color(ink))
                    context.draw(Text("\(wall.number)").font(.system(size: 11, weight: .bold)).foregroundColor(paper), at: center)
                }
            }
        }
        .accessibilityLabel("План помещения: площадь \(CalculationEngine.format((plan.area * 10).rounded() / 10)) квадратных метров")
    }

    private func rotatedRect(center: CGPoint, width: CGFloat, depth: CGFloat, radians: Double) -> Path {
        let rect = CGRect(x: -width / 2, y: -depth / 2, width: width, height: depth)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(radians))
        return Path(roundedRect: rect, cornerRadius: min(4, min(width, depth) / 4)).applying(transform)
    }
}

enum FurnitureStyle {
    static func title(_ kind: String) -> String {
        switch kind {
        case "toilet", "sink", "shower", "bathtub": return "Сантехника"
        case "washer": return "Техника"
        case "mirror", "towel", "accessory": return "Аксессуары"
        case "boiler": return "Инженерное оборудование"
        case "pendant", "sconce", "floorlamp", "hiddenlight": return "Освещение"
        case "sofa": return "Мягкая мебель"
        case "bed": return "Спальное место"
        case "table", "desk": return "Столы"
        case "chair": return "Стулья и кресла"
        case "storage": return "Системы хранения"
        case "kitchen": return "Кухня"
        case "appliance": return "Техника"
        case "bath": return "Сантехника"
        case "plant": return "Озеленение"
        case "light": return "Освещение"
        case "tv": return "ТВ‑зона"
        default: return "Декор"
        }
    }

    static func color(_ kind: String) -> Color {
        switch kind {
        case "toilet", "sink", "shower", "bathtub": return Color(red: 0.62, green: 0.80, blue: 0.84)
        case "washer", "boiler": return Color(red: 0.62, green: 0.70, blue: 0.80)
        case "mirror", "towel", "accessory": return Color(red: 0.78, green: 0.80, blue: 0.82)
        case "pendant", "sconce", "floorlamp", "hiddenlight", "light": return Color(red: 0.95, green: 0.82, blue: 0.45)
        case "sofa": return Color(red: 0.55, green: 0.66, blue: 0.62)
        case "bed": return Color(red: 0.72, green: 0.66, blue: 0.80)
        case "table", "desk": return Color(red: 0.80, green: 0.66, blue: 0.48)
        case "chair": return Color(red: 0.86, green: 0.76, blue: 0.62)
        case "storage": return Color(red: 0.70, green: 0.62, blue: 0.55)
        case "kitchen", "appliance": return Color(red: 0.62, green: 0.70, blue: 0.80)
        case "bath": return Color(red: 0.62, green: 0.80, blue: 0.84)
        case "plant": return Color(red: 0.55, green: 0.76, blue: 0.48)
        case "tv": return Color(red: 0.35, green: 0.37, blue: 0.40)
        default: return Color(red: 0.84, green: 0.80, blue: 0.74)
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color (used for the AI palette).
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Plans list

struct FloorPlansView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Скан → план → дизайн", title: "Планировки\nи дизайн комнат")
                Text("Отсканируйте комнату лидаром или обойдите углы в AR — получите план сверху с размерами, а ИИ предложит зонирование, мебель, материалы и бюджет.").font(.subheadline).foregroundStyle(Theme.muted)
                HStack(spacing: 12) {
                    Button { store.showRoomScan = true } label: { HomeActionCard(icon: "cube.transparent", title: "Скан комнаты", subtitle: "Лидар · 3D", accent: Theme.orange) }
                    Button { store.showAR = true } label: { HomeActionCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Контур в AR", subtitle: "Любой iPhone", accent: Theme.sky) }
                }
                .buttonStyle(PremiumCardPressStyle())
                if store.floorPlans.isEmpty {
                    ContentUnavailableView("Пока нет планировок", systemImage: "square.split.bottomrightquarter", description: Text("Первый скан займёт 1–2 минуты."))
                } else {
                    ForEach(store.floorPlans) { plan in
                        NavigationLink { FloorPlanDetailView(planID: plan.id) } label: { FloorPlanRow(plan: plan) }
                            .buttonStyle(PremiumCardPressStyle())
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Планировки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FloorPlanRow: View {
    let plan: FloorPlan
    var body: some View {
        HStack(spacing: 14) {
            FloorPlanCanvas(plan: plan, proposal: plan.proposals.last, showDimensions: false, compact: true)
                .frame(width: 92, height: 72).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(plan.name).font(.headline).foregroundStyle(.white)
                Text("\(CalculationEngine.format((plan.area * 10).rounded() / 10)) м² · \(plan.source == .lidar ? "лидар" : "контур AR")").font(.caption).foregroundStyle(Theme.muted)
                Text(plan.proposals.isEmpty ? "Дизайн ещё не создан" : "Концепций: \(plan.proposals.count)").font(.caption.weight(.semibold)).foregroundStyle(plan.proposals.isEmpty ? Theme.muted : Theme.orange)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .panelCard(18)
    }
}

// MARK: - Plan detail with AI design

struct FloorPlanDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let planID: FloorPlan.ID
    @State private var selectedProposal: UUID?
    @State private var showDesignSheet = false
    @State private var isGenerating = false
    @State private var error: String?
    @State private var modelURL: URL?
    @State private var shareFile: SharedFile?
    @State private var isRendering = false
    @State private var progressText: String?
    @State private var presentation: PresentationResult?
    @State private var isComparing = false
    @State private var comparison: EngineComparison?

    struct PresentationResult {
        let proposalID: UUID
        let pdf: URL
        let images: [(title: String, image: UIImage)]
    }

    /// Owner only: the same exact render through every picture engine.
    struct EngineComparison: Identifiable {
        struct Result: Identifiable {
            let id: String
            let title: String
            let image: UIImage?
            let score: Double?
            let seconds: Double
            let error: String?
        }
        let id = UUID()
        let reference: UIImage
        let results: [Result]
    }
    @State private var openedPhoto: PhotoSheetItem?

    struct PhotoSheetItem: Identifiable { let id = UUID(); let image: UIImage }
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var step: PlanStep = .measure
    @State private var stepChosen = false
    @State private var show3D = false
    @State private var showOrder = false
    @State private var editPlan = false
    @State private var furnitureTarget: FurnitureTarget?

    /// The concept whose furniture is being moved by hand.
    struct FurnitureTarget: Identifiable { let id: UUID }

    private var plan: FloorPlan? { store.floorPlans.first { $0.id == planID } }
    private var proposal: DesignProposal? {
        guard let plan else { return nil }
        if let selectedProposal { return plan.proposals.first { $0.id == selectedProposal } }
        return nil
    }

    /// A presentation of the selected concept is on the iPhone.
    private var hasPresentation: Bool {
        guard let presentation, let proposal else { return false }
        return presentation.proposalID == proposal.id
    }
    /// A presentation can be built: the AI server or picture keys in the owner's build.
    private var canRender: Bool { store.photorealAvailable || store.usesAIServer }
    private func planFlow(_ plan: FloorPlan) -> PlanFlow {
        PlanFlow(plan: plan, proposal: proposal, hasPresentation: hasPresentation, canRender: canRender)
    }

    var body: some View {
        Group {
            if let plan { content(plan) }
            else { ContentUnavailableView("План удалён", systemImage: "trash") }
        }
        .background(Theme.background)
        .navigationTitle(plan?.name ?? "План")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .sheet(isPresented: $showDesignSheet) {
            NavigationStack {
                DesignRequestSheet(suggested: plan.flatMap { suggestedRoom($0) }, reason: plan.flatMap { RoomKind.scanReason($0) }) { style, purpose, wishes in
                    generate(style: style, purpose: purpose, wishes: wishes)
                }
            }
                .presentationDetents([.large])
        }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .sheet(item: $openedPhoto) { item in NavigationStack { RenderResultView(image: item.image, title: proposal?.title ?? plan?.name ?? "Интерьер") } }
        .sheet(item: $comparison) { item in NavigationStack { EngineComparisonView(comparison: item) } }
        .fullScreenCover(isPresented: $show3D) {
            if let plan {
                NavigationStack {
                    Room3DView(plan: plan, proposal: step == .measure ? nil : proposal)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { show3D = false } } }
                }
            }
        }
        .fullScreenCover(isPresented: $editPlan) { NavigationStack { PlanEditorView(planID: planID) } }
        .fullScreenCover(item: $furnitureTarget) { target in NavigationStack { FurnitureEditorView(planID: planID, proposalID: target.id) } }
        .navigationDestination(isPresented: $showOrder) {
            if let plan { CreateWorkOrderView(prefill: workOrder(plan)) }
        }
        .quickLookPreview($modelURL)
        .alert("Название плана", isPresented: $showRename) {
            TextField("Например, гостиная", text: $newName)
            Button("Сохранить") { rename() }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить план и все концепции?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let plan { store.deletePlan(plan) }; dismiss() }
        }
        .onAppear {
            if selectedProposal == nil { selectedProposal = plan?.proposals.last?.id }
            loadSavedPresentation()
            // Opens where the work stopped: the measurements, the concept or its presentation.
            if !stepChosen, let plan {
                step = planFlow(plan).initialStep
                stepChosen = true
            }
        }
        .onChange(of: selectedProposal) { _, _ in loadSavedPresentation() }
    }

    private func content(_ plan: FloorPlan) -> some View {
        let flow = planFlow(plan)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PlanStepBar(step: $step, done: flow.done)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
                }
                if isComparing {
                    Label("Сравниваем движки рендера… 1–3 мин", systemImage: "hourglass").font(.footnote).foregroundStyle(Theme.muted)
                }
                switch step {
                case .measure: measureStep(plan, flow: flow)
                case .design: designStep(plan, flow: flow)
                case .result: resultStep(plan, flow: flow)
                }
            }
            .padding(20)
        }
    }

    /// Step 1: the room as scanned — the plan with sizes and the numbers; materials are counted from here.
    @ViewBuilder private func measureStep(_ plan: FloorPlan, flow: PlanFlow) -> some View {
        planPicture(plan, proposal: nil)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PlanStat(value: "\(CalculationEngine.format((plan.area * 10).rounded() / 10)) м²", title: "Площадь")
            PlanStat(value: "\(CalculationEngine.format((plan.perimeter * 10).rounded() / 10)) м", title: "Периметр")
            PlanStat(value: "\(CalculationEngine.format((plan.ceilingHeight * 100).rounded() / 100)) м", title: "Потолок")
            PlanStat(value: "\(CalculationEngine.format(plan.netWallArea.rounded())) м²", title: "Стены")
            PlanStat(value: "\(plan.windows.count)", title: "Окна")
            PlanStat(value: "\(plan.doors.count)", title: "Двери")
        }
        mainButton(flow.main(on: .measure), plan: plan)
        Button { editPlan = true } label: { SecondaryActionLabel(title: "Исправить план: стены, двери, окна", icon: "pencil.and.ruler") }
            .buttonStyle(PremiumPressStyle())
        NavigationLink { PlanMaterialsView(plan: plan) } label: {
            HStack(spacing: 12) {
                Image(systemName: "function").font(.title3).foregroundStyle(Theme.orange).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Материалы и смета").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Пол, стяжка, стены и потолок — размеры уже из плана").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard(16)
        }
        .buttonStyle(PremiumCardPressStyle())
        InfoNote(text: plan.source == .lidar ? "Точность лидара — около 1–2 см на метр. Перед закупкой и заказом мебели перепроверьте ключевые размеры рулеткой." : "План построен по углам пола в AR. Окна и двери добавьте в «Исправить план»; для точной планировки нужен iPhone с лидаром.")
    }

    /// Step 2: the concepts — the layout on the plan, finishes and budget; then the presentation.
    @ViewBuilder private func designStep(_ plan: FloorPlan, flow: PlanFlow) -> some View {
        if plan.proposals.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(plan.proposals) { item in chip(item.title, selected: selectedProposal == item.id) { selectedProposal = item.id } }
                }
            }
        }
        if let proposal {
            planPicture(plan, proposal: proposal)
            proposalCard(proposal, plan: plan)
        } else if !isGenerating {
            Text("ИИ предложит зонирование, мебель, отделку, палитру и бюджет. Мебель приложение расставит по правилам: с проходами, свободной дверью и окнами.")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
        if isGenerating {
            generatingCard
        } else {
            mainButton(flow.main(on: .design), plan: plan)
        }
        if let proposal {
            if !proposal.furniture.isEmpty {
                Button { furnitureTarget = FurnitureTarget(id: proposal.id) } label: { SecondaryActionLabel(title: "Передвинуть мебель", icon: "hand.draw") }
                    .buttonStyle(PremiumPressStyle())
            }
            if !isGenerating && flow.main(on: .design).action != .createDesign {
                Button { showDesignSheet = true } label: { SecondaryActionLabel(title: "Ещё вариант дизайна", icon: "wand.and.stars") }
                    .buttonStyle(PremiumPressStyle())
            }
            NavigationLink { AIAssistantView(context: assistantContext(proposal, plan: plan)) } label: {
                SecondaryActionLabel(title: "Обсудить концепцию с ИИ", icon: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(PremiumPressStyle())
        }
    }

    /// Step 3: what goes to the client — the PDF presentation, the working drawings and the renovation request.
    @ViewBuilder private func resultStep(_ plan: FloorPlan, flow: PlanFlow) -> some View {
        if let proposal {
            VStack(alignment: .leading, spacing: 4) {
                Text("КОНЦЕПЦИЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
                Text(proposal.title).font(.title3.bold())
            }
            if flow.presentationOutdated {
                Label("План или мебель изменены после презентации — обновите её.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.footnote).foregroundStyle(Theme.orange)
            }
            if let presentation, presentation.proposalID == proposal.id {
                presentationGallery(presentation)
            } else if flow.conceptReady && flow.canRender && !isRendering {
                Text("Обмерный план, план расстановки, точная 3D‑модель сверху и в объёме, три вида комнаты и фотореализм (только если совпадает с моделью) — в одной PDF‑презентации. Около 1–2 минут, сохраняется на iPhone.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        } else {
            Text("Презентация строится по концепции дизайна. Чертежи и заявку на ремонт можно сделать и по одному обмеру.")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
        mainButton(flow.main(on: .result), plan: plan)
        VStack(alignment: .leading, spacing: 10) {
            Text("РАБОЧИЕ ЧЕРТЕЖИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
            Text("Обмерный план, план расстановки, точки сантехники, полы и раскладка плитки, потолок, электрика, развёртки и ведомость отделки — листы А3 со штампом, в масштабе.")
                .font(.caption).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Button { openDrawings(plan) } label: { SecondaryActionLabel(title: "Открыть", icon: "doc.text.magnifyingglass") }.buttonStyle(PremiumPressStyle())
                Button { shareDrawings(plan) } label: { SecondaryActionLabel(title: "Сохранить PDF", icon: "square.and.arrow.down") }.buttonStyle(PremiumPressStyle())
            }
            Button { shareDXF(plan) } label: { SecondaryActionLabel(title: "DXF для AutoCAD, nanoCAD, ArchiCAD", icon: "square.and.arrow.up") }
                .buttonStyle(PremiumPressStyle())
        }
        if flow.main(on: .result).action != .orderRenovation {
            Button { showOrder = true } label: { SecondaryActionLabel(title: "Ремонт этой комнаты под ключ", icon: "paperplane.fill") }
                .buttonStyle(PremiumPressStyle())
        }
    }

    private func presentationGallery(_ presentation: PresentationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(presentation.images.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 5) {
                            Image(uiImage: item.image).resizable().scaledToFill().frame(width: 250, height: 180).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(item.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(2)
                                .frame(width: 250, alignment: .leading)
                        }
                        .onTapGesture { openedPhoto = PhotoSheetItem(image: item.image) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { modelURL = presentation.pdf } label: { SecondaryActionLabel(title: "Открыть PDF", icon: "doc.richtext") }.buttonStyle(PremiumPressStyle())
                Button { shareFile = SharedFile(url: presentation.pdf) } label: { SecondaryActionLabel(title: "Отправить", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
            }
        }
    }

    private func planPicture(_ plan: FloorPlan, proposal: DesignProposal?) -> some View {
        FloorPlanCanvas(plan: plan, proposal: proposal)
            .aspectRatio(max(0.7, min(1.6, plan.width / max(0.5, plan.depth))), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(plan.source == .lidar ? "ЛИДАР‑СКАН" : "КОНТУР AR").font(.caption2.weight(.bold)).tracking(1).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.65), in: Capsule()).foregroundStyle(.white).padding(10)
            }
    }

    /// The one main button of a step.
    private func mainButton(_ button: PlanMainButton, plan: FloorPlan) -> some View {
        let busy = isRendering && button.action == .buildPresentation
        let blocked = (button.action == .buildPresentation && (isRendering || isComparing)) || (button.action == .createDesign && isGenerating)
        return Button { perform(button.action, plan: plan) } label: {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.black) } else { Image(systemName: button.icon) }
                Text(busy ? (progressText ?? "Готовим презентацию…") : button.title).font(.headline).lineLimit(2)
            }
            .frame(maxWidth: .infinity).padding(16).foregroundStyle(.black)
            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(blocked)
    }

    private func perform(_ action: PlanAction, plan: FloorPlan) {
        Haptics.tap()
        switch action {
        case .createDesign:
            showDesignSheet = true
        case .goTo(let next):
            withAnimation(.snappy) { step = next }
        case .buildPresentation:
            guard let proposal else { return }
            withAnimation(.snappy) { step = .result }
            Task { await buildPresentation(proposal, plan: plan) }
        case .orderRenovation:
            showOrder = true
        }
    }

    private var generatingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("ИИ проектирует интерьер").font(.subheadline.weight(.semibold))
                Text("Обычно 30–90 секунд. Не сворачивайте приложение.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    /// «Ещё»: what is needed now and then.
    private var moreMenu: some View {
        Menu {
            Button { newName = plan?.name ?? ""; showRename = true } label: { Label("Переименовать", systemImage: "pencil") }
            Button { show3D = true } label: { Label("3D‑просмотр комнаты", systemImage: "rotate.3d") }
            if let plan, let url = store.planModelURL(plan) {
                Button { modelURL = url } label: { Label("3D‑модель скана (USDZ)", systemImage: "cube") }
            }
            if let plan {
                Button { sharePlan(plan) } label: { Label("Поделиться планом", systemImage: "square.and.arrow.up") }
            }
            if let plan, let proposal, hasPresentation, canRender {
                Button { step = .result; Task { await buildPresentation(proposal, plan: plan) } } label: {
                    Label("Пересобрать презентацию", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isRendering)
            }
            if let plan, let proposal, store.ownerUnlocked, store.imageEngines.count > 1 {
                Button { Task { await compareEngines(proposal, plan: plan) } } label: {
                    Label("Сравнить движки рендера", systemImage: "square.grid.2x2")
                }
                .disabled(isComparing || isRendering)
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить план", systemImage: "trash") }
        } label: {
            Label("Ещё", systemImage: "ellipsis.circle")
        }
    }

    private func proposalCard(_ proposal: DesignProposal, plan: FloorPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(proposal.roomPurpose.uppercased() + (proposal.style.isEmpty ? "" : " · " + proposal.style.uppercased())).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
            Text(proposal.title).font(.title3.bold())
            Text(proposal.summary).font(.subheadline).foregroundStyle(.white.opacity(0.88))
            if !proposal.layoutNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(proposal.layoutNotes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            if !proposal.palette.isEmpty {
                HStack(spacing: 8) {
                    ForEach(proposal.palette, id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: hex) ?? Theme.panelRaised).frame(height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    }
                }
                .accessibilityLabel("Палитра концепции")
            }
            if !(proposal.floor.isEmpty && proposal.walls.isEmpty && proposal.ceiling.isEmpty) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ОТДЕЛКА").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
                    FinishRow(title: "Пол", icon: "square.grid.3x3.fill", finish: proposal.floor)
                    FinishRow(title: "Стены", icon: "rectangle.portrait.fill", finish: proposal.walls)
                    FinishRow(title: "Потолок", icon: "light.recessed", finish: proposal.ceiling)
                }
            }
            if proposal.budgetMax > 0 {
                HStack {
                    Text("Бюджет").font(.subheadline).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(CalculationEngine.money(proposal.budgetMin)) – \(CalculationEngine.money(proposal.budgetMax))").font(.subheadline.bold()).monospacedDigit()
                }
            }
            if proposal.furniture.isEmpty {
                Label("В этой концепции нет расстановки — создайте ещё вариант дизайна.", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
            } else {
                DisclosureGroup("\(RoomKind.detect(plan: plan, proposal: proposal).specificationTitle) · \(proposal.furniture.count)") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(proposal.furniture, id: \.self) { item in
                            HStack {
                                Circle().fill(FurnitureStyle.color(item.model)).frame(width: 9, height: 9)
                                Text(item.name).font(.footnote)
                                Spacer()
                                Text(String(format: "%.1f × %.1f м", item.width, item.depth).replacingOccurrences(of: ".", with: ",")).font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
                            }
                        }
                    }.padding(.top, 8)
                }.tint(Theme.orange)
            }
            if !proposal.materials.isEmpty {
                DisclosureGroup("Материалы · \(proposal.materials.count)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(proposal.materials, id: \.self) { material in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(material.name).font(.footnote.weight(.semibold))
                                Text("\(material.where) · \(material.amount)").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }.padding(.top, 8)
                }.tint(Theme.orange)
            }
            if !proposal.lighting.isEmpty || !proposal.tips.isEmpty {
                DisclosureGroup("Свет и советы") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !proposal.lighting.isEmpty { Label(proposal.lighting, systemImage: "lightbulb").font(.footnote) }
                        ForEach(proposal.tips, id: \.self) { Label($0, systemImage: "checkmark.circle").font(.footnote) }
                    }.padding(.top, 8)
                }.tint(Theme.orange)
            }
        }
        .padding(18)
        .panelCard(20)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); withAnimation(.snappy) { action() } } label: {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? Theme.orange : Theme.panel, in: Capsule()).foregroundStyle(selected ? .black : .white)
        }
    }

    private func assistantContext(_ proposal: DesignProposal, plan: FloorPlan) -> AIAssistantContext {
        let lines = proposal.materials.enumerated().map { index, material in
            AIAssistantLine(id: "material-\(index)", section: "Материалы концепции", title: "\(material.name) (\(material.where))", quantity: 0, unit: material.amount, material: 0, labor: 0, total: 0)
        }
        return AIAssistantContext(estimateType: "Дизайн: \(proposal.title)", objectName: plan.name, area: plan.area, floors: nil, reservePercent: nil, materialTotal: nil, laborTotal: nil, total: proposal.budgetMax > 0 ? proposal.budgetMax : nil, lines: lines)
    }

    @MainActor private func planImage(_ plan: FloorPlan, proposal: DesignProposal?, wallNumbers: Bool = false) -> UIImage? {
        let ratio = max(0.7, min(1.6, plan.width / max(0.5, plan.depth)))
        let width: CGFloat = 1200
        let renderer = ImageRenderer(content: FloorPlanCanvas(plan: plan, proposal: proposal, wallNumbers: wallNumbers).frame(width: width, height: width / ratio))
        renderer.scale = 1
        return renderer.uiImage
    }

    /// Room type for the design sheet: scan (toilet, bathtub, stove…), plan name or the previous concept.
    private func suggestedRoom(_ plan: FloorPlan) -> RoomKind? {
        RoomKind.fromScan(plan) ?? plan.proposals.last.flatMap { RoomKind.keyword($0.roomPurpose) }
    }

    private func generate(style: String, purpose: String, wishes: String) {
        guard let plan else { return }
        error = nil
        isGenerating = true
        withAnimation(.snappy) { step = .design }
        UIApplication.shared.isIdleTimerDisabled = true // the screen must not lock while the AI is working
        let image = planImage(plan, proposal: nil, wallNumbers: true)
        Task {
            do {
                let result = try await store.generateDesign(for: plan, planImage: image, style: style, purpose: purpose, wishes: wishes)
                if var updated = store.floorPlans.first(where: { $0.id == plan.id }) {
                    updated.proposals.append(result)
                    store.savePlan(updated)
                }
                withAnimation(.snappy) { selectedProposal = result.id }
                Haptics.success()
            } catch { self.error = error.localizedDescription; Haptics.warning() }
            isGenerating = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Full design presentation: measured plan, layout plan, exact 3D model (top + isometric),
    /// exact interior views and photoreal versions that passed the geometry check — assembled into a PDF.
    private func buildPresentation(_ original: DesignProposal, plan: FloorPlan) async {
        isRendering = true
        error = nil
        UIApplication.shared.isIdleTimerDisabled = true
        defer { isRendering = false; progressText = nil; UIApplication.shared.isIdleTimerDisabled = false }

        // Every item inside the scanned outline; the room type decides titles, shots and what the AI may draw.
        let proposal = original.placed(in: plan)
        let room = RoomKind.detect(plan: plan, proposal: proposal)

        progressText = "Строим точную 3D‑модель по скану…"
        await store.refreshAICapabilities()
        // 3D plan and isometry: ONLY the exact model (no AI) — walls, openings and layout 1:1 with the scan.
        let top = Room3DBuilder.snapshot(plan: plan, proposal: proposal, mode: .overhead, size: CGSize(width: 1600, height: 1200))
        let iso = Room3DBuilder.snapshot(plan: plan, proposal: proposal, mode: .top, size: CGSize(width: 1600, height: 1200))
        let shots = Array(Room3DBuilder.interiorShots(plan: plan, proposal: proposal).prefix(3))
        // Exact interior renders with auto-exposure; burnt-out or black frames are thrown away.
        var exact: [(title: String, image: UIImage)] = []
        for shot in shots {
            if let image = Room3DBuilder.snapshot(plan: plan, proposal: proposal, mode: .interior, shot: shot, size: CGSize(width: 2048, height: 1536)), RenderQuality.isUsable(image) {
                exact.append((title: shot.title, image: image))
            }
        }
        let names = proposal.furniture.filter { $0.model != "hiddenlight" }.map(\.name).joined(separator: ", ")
        var items = ""
        if !names.isEmpty { items = await store.englishPrompt(names) }
        if items.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil { items = OfflineDesigner.englishNames(proposal.furniture) }
        let references = exact.map { $0.image }
        let photoPrompt = Room3DBuilder.photoPrompt(proposal: proposal, itemsEnglish: items, plan: plan)

        progressText = exact.isEmpty ? "Собираем PDF‑презентацию…" : "ИИ делает фотореализм по точной модели… 1–2 мин"
        async let first = verifiedPhoto(references.count > 0 ? references[0] : nil, prompt: photoPrompt)
        async let second = verifiedPhoto(references.count > 1 ? references[1] : nil, prompt: photoPrompt)
        async let third = verifiedPhoto(references.count > 2 ? references[2] : nil, prompt: photoPrompt)
        let photos = await [first, second, third]

        var interiors: [(title: String, image: UIImage)] = []
        for (index, item) in exact.enumerated() {
            if let photo = photos[index] { interiors.append((title: "\(item.title) · фотореализм (\(photo.title))", image: photo.image)) }
            interiors.append((title: "\(item.title) · точная 3D‑модель", image: item.image))
        }
        let rejected = exact.indices.filter { photos[$0] == nil }.count

        progressText = "Собираем PDF‑презентацию…"
        let measured = DrawingsPDF.planPicture(plan: plan, proposal: nil, furniture: false)
        let layout = proposal.furniture.isEmpty ? nil : DrawingsPDF.planPicture(plan: plan, proposal: proposal, furniture: true)
        let engineering = DrawingsPDF.engineeringPicture(plan: plan, proposal: proposal)
        let content = DesignPresentationContent(projectName: store.projectDisplayName, plan: plan, proposal: proposal, roomKind: room, measuredPlan: measured, planImage: layout, engineering: engineering, topRender: top, isoRender: iso, interiorPhotos: interiors)
        do {
            let url = try DesignPresentationPDF.render(content)
            var gallery: [(title: String, image: UIImage)] = []
            if let top { gallery.append((title: "3D‑план сверху · точная модель", image: top)) }
            if let iso { gallery.append((title: "Объёмный вид · точная модель", image: iso)) }
            gallery += interiors
            // Kept with the concept: next time the plan opens with this presentation, without new renders.
            var pdf = url
            if let saved = try? store.savePresentation(pdf: url, pictures: gallery, engine: photos.compactMap { $0?.title }.first, proposalID: original.id, planID: plan.id),
               let file = store.presentationFile(saved, saved.pdf) {
                pdf = file
            }
            withAnimation(.snappy) { presentation = PresentationResult(proposalID: original.id, pdf: pdf, images: gallery) }
            store.track("design_presentation")
            if proposal.furniture.isEmpty {
                error = "В этой концепции ИИ не прислал расстановку — в презентации только обмерный план и пустая комната. Нажмите «Ещё вариант дизайна»."
            } else if rejected > 0 && store.photorealAvailable {
                error = "ИИ‑фото не прошли проверку геометрии: \(rejected). В презентации вместо них точная 3D‑модель — стены и расстановка гарантированно как в скане."
            }
            Haptics.success()
            modelURL = pdf
        } catch { self.error = "Не удалось собрать PDF: \(error.localizedDescription)" }
    }

    /// Photoreal version of one exact render: the server's engine (the next one if it fails), checked against the render
    /// (geometry and exposure). One more try if the check fails; nil — the exact 3D model goes into the presentation instead.
    private func verifiedPhoto(_ reference: UIImage?, prompt: String) async -> (image: UIImage, title: String)? {
        guard let reference, store.photorealAvailable else { return nil }
        for _ in 0..<2 {
            guard let rendered = try? await store.photorealRender(reference, prompt: prompt) else { continue }
            let score = GeometryCheck.score(reference: reference, candidate: rendered.image)
            if score >= GeometryCheck.threshold, RenderQuality.isUsable(rendered.image) {
                store.track("photo_accepted")
                return (rendered.image, rendered.title)
            }
            store.track("geometry_rejected")
        }
        return nil
    }

    /// The presentation saved with the selected concept (PDF and pictures on the iPhone).
    private func loadSavedPresentation() {
        guard let proposal else { presentation = nil; return }
        guard presentation?.proposalID != proposal.id else { return }
        guard let saved = proposal.presentation, let pdf = store.presentationFile(saved, saved.pdf) else { presentation = nil; return }
        let images = saved.pictures.compactMap { picture -> (title: String, image: UIImage)? in
            guard let url = store.presentationFile(saved, picture.file), let image = UIImage(contentsOfFile: url.path) else { return nil }
            return (title: picture.title, image: image)
        }
        presentation = PresentationResult(proposalID: proposal.id, pdf: pdf, images: images)
    }

    /// Owner only: the same exact render through every picture engine, with the geometry score and the time —
    /// to choose the engine on real scans.
    private func compareEngines(_ original: DesignProposal, plan: FloorPlan) async {
        isComparing = true
        error = nil
        UIApplication.shared.isIdleTimerDisabled = true
        defer { isComparing = false; UIApplication.shared.isIdleTimerDisabled = false }
        await store.refreshAICapabilities()
        let proposal = original.placed(in: plan)
        guard let shot = Room3DBuilder.interiorShots(plan: plan, proposal: proposal).first,
              let reference = Room3DBuilder.snapshot(plan: plan, proposal: proposal, mode: .interior, shot: shot, size: CGSize(width: 2048, height: 1536)) else {
            error = "Не удалось построить кадр 3D‑модели для сравнения."
            return
        }
        let prompt = Room3DBuilder.photoPrompt(proposal: proposal, itemsEnglish: OfflineDesigner.englishNames(proposal.furniture), plan: plan)
        let engines = store.imageEngines
        let results = await withTaskGroup(of: EngineComparison.Result.self) { group -> [EngineComparison.Result] in
            for engine in engines {
                group.addTask { await renderForComparison(engine, reference: reference, prompt: prompt) }
            }
            var collected: [EngineComparison.Result] = []
            for await result in group { collected.append(result) }
            return collected
        }
        store.track("engine_comparison")
        comparison = EngineComparison(reference: reference, results: engines.compactMap { engine in results.first { $0.id == engine.id } })
    }

    private func renderForComparison(_ engine: ImageEngine, reference: UIImage, prompt: String) async -> EngineComparison.Result {
        let started = Date()
        do {
            let rendered = try await store.photorealRender(reference, prompt: prompt, engine: engine.id)
            let score = GeometryCheck.score(reference: reference, candidate: rendered.image)
            return EngineComparison.Result(id: engine.id, title: engine.title, image: rendered.image, score: score, seconds: Date().timeIntervalSince(started), error: nil)
        } catch {
            return EngineComparison.Result(id: engine.id, title: engine.title, image: nil, score: nil, seconds: Date().timeIntervalSince(started), error: error.localizedDescription)
        }
    }

    private func drawingsURL(_ plan: FloorPlan) -> URL? {
        do { return try DrawingsPDF.render(plan: plan, proposal: proposal, projectName: store.projectDisplayName) }
        catch { self.error = "Не удалось сделать чертежи: \(error.localizedDescription)"; return nil }
    }
    private func openDrawings(_ plan: FloorPlan) {
        guard let url = drawingsURL(plan) else { return }
        store.track("drawings_open")
        modelURL = url
    }
    private func shareDrawings(_ plan: FloorPlan) {
        guard let url = drawingsURL(plan) else { return }
        store.track("drawings_share")
        shareFile = SharedFile(url: url)
    }

    /// The plan for CAD: walls, openings, furniture, electrics and tiles on separate layers, in millimetres.
    private func shareDXF(_ plan: FloorPlan) {
        do {
            let url = try PlanDXF.file(plan: plan, proposal: proposal, room: RoomKind.detect(plan: plan, proposal: proposal))
            store.track("drawings_dxf")
            shareFile = SharedFile(url: url)
        } catch { self.error = "Не удалось сделать DXF: \(error.localizedDescription)" }
    }

    private func sharePlan(_ plan: FloorPlan) {
        guard let image = planImage(plan, proposal: step == .measure ? nil : proposal) else { return }
        shareImage(image, name: "План-\(plan.name)")
    }

    private func shareImage(_ image: UIImage, name: String = "Интерьер-АртСтрой") {
        guard let data = BrandGraphics.watermarked(image).pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).png")
        do { try data.write(to: url, options: .atomic); shareFile = SharedFile(url: url); store.track("plan_shared") }
        catch { self.error = error.localizedDescription }
    }

    private func rename() {
        guard var plan, !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        plan.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.savePlan(plan)
    }

    private func workOrder(_ plan: FloorPlan) -> WorkOrderDraft {
        var details = "Нужен ремонт помещения «\(plan.name)» по скану из приложения.\nПлощадь: \(CalculationEngine.format((plan.area * 10).rounded() / 10)) м², периметр \(CalculationEngine.format((plan.perimeter * 10).rounded() / 10)) м, потолок \(CalculationEngine.format((plan.ceilingHeight * 100).rounded() / 100)) м, окон: \(plan.windows.count), дверей: \(plan.doors.count)."
        if let proposal {
            details += "\n\nВыбранная концепция: \(proposal.title) (\(proposal.style)).\n\(proposal.summary)"
            if proposal.budgetMax > 0 { details += "\nОриентир бюджета: \(CalculationEngine.money(proposal.budgetMin)) – \(CalculationEngine.money(proposal.budgetMax))" }
        }
        return WorkOrderDraft(category: "Ремонт и отделка", city: store.projectCity, details: details, budget: proposal.map { $0.budgetMax > 0 ? CalculationEngine.money($0.budgetMax) : "" } ?? "", attachment: planImage(plan, proposal: proposal))
    }
}

/// The three steps of the plan screen; a finished step shows a check mark.
struct PlanStepBar: View {
    @Binding var step: PlanStep
    let done: Set<PlanStep>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlanStep.allCases) { item in
                let selected = item == step
                Button { Haptics.tap(); withAnimation(.snappy) { step = item } } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(selected ? Color.black.opacity(0.16) : Theme.panelRaised)
                            if done.contains(item) && !selected {
                                Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(Theme.orange)
                            } else {
                                Text("\(item.number)").font(.caption2.weight(.bold))
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected ? Color.black : Color.white)
                    .background(selected ? Theme.orange : Theme.panel, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Шаг \(item.number) из \(PlanStep.allCases.count): \(item.title)" + (done.contains(item) ? ", готово" : ""))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// «Материалы и смета»: the room's finishing calculators with its sizes filled in.
struct PlanMaterialsView: View {
    let plan: FloorPlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Размеры уже подставлены из плана: пол \(format(plan.area)) м², стены \(format(plan.perimeter * plan.ceilingHeight)) м², окна и двери \(format(plan.openingsArea)) м².")
                    .font(.footnote).foregroundStyle(Theme.muted)
                ForEach(PlanMaterials.calculations(plan)) { item in
                    NavigationLink {
                        CalculatorView(kind: item.kind, initialValues: item.values, measurementNote: "Размеры взяты из плана комнаты. Перепроверьте их перед закупкой.")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.kind.icon).foregroundStyle(Theme.orange).frame(width: 26)
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .panelCard(14)
                    }
                    .buttonStyle(PremiumCardPressStyle())
                }
                InfoNote(text: "Перед закупкой перепроверьте ключевые размеры рулеткой.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Материалы и смета")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ value: Double) -> String { CalculationEngine.format((value * 10).rounded() / 10) }
}

/// Owner only: one exact render of the room through every picture engine — to choose the engine on real scans.
struct EngineComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let comparison: FloorPlanDetailView.EngineComparison
    @State private var opened: FloorPlanDetailView.PhotoSheetItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Один и тот же кадр точной 3D‑модели через каждый движок. «Совпадение» — насколько ИИ сохранил стены, проёмы и расстановку; в презентацию идут кадры от \(Int((GeometryCheck.threshold * 100).rounded())) %.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Text("ТОЧНАЯ 3D‑МОДЕЛЬ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
                Image(uiImage: comparison.reference).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                ForEach(comparison.results) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(result.title).font(.headline)
                            Spacer()
                            Text(String(format: "%.0f с", result.seconds)).font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        if let image = result.image {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onTapGesture { opened = FloorPlanDetailView.PhotoSheetItem(image: image) }
                        }
                        if let score = result.score {
                            Label("Совпадение с моделью: \(Int((score * 100).rounded())) %", systemImage: score >= GeometryCheck.threshold ? "checkmark.seal.fill" : "xmark.seal")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(score >= GeometryCheck.threshold ? Theme.success : Theme.danger)
                        }
                        if let error = result.error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                    }
                    .padding(14)
                    .panelCard(16)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Сравнение движков")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        .sheet(item: $opened) { item in NavigationStack { RenderResultView(image: item.image, title: "Сравнение движков") } }
    }
}

struct FinishRow: View {
    let title: String
    let icon: String
    let finish: DesignFinish
    var body: some View {
        if !finish.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: finish.color) ?? Theme.panelRaised).frame(width: 40, height: 40)
                    .overlay(Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(title): \(finish.material)").font(.subheadline.weight(.semibold))
                    if !finish.details.isEmpty { Text(finish.details).font(.caption).foregroundStyle(Theme.muted) }
                }
            }
        }
    }
}

struct PlanStat: View {
    let value: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).panelCard(14)
    }
}

// MARK: - Design request

struct DesignRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Type found by the scan / plan name / previous concept.
    var suggested: RoomKind? = nil
    var reason: String? = nil
    let onSubmit: (String, String, String) -> Void
    @State private var style = "Современный"
    @State private var purpose = ""
    @State private var wishes = ""

    private let styles = ["Современный", "Скандинавский", "Минимализм", "Японди", "Лофт", "Неоклассика", "Средиземноморский", "Эко"]
    private let purposes = ["Санузел", "Кухня", "Кухня‑гостиная", "Гостиная", "Спальня", "Детская", "Кабинет", "Прихожая", "Студия", "Терраса"]
    private var chosen: RoomKind? { RoomKind.keyword(purpose) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "ИИ‑дизайнер", title: "Каким будет\nэто помещение?")
                Text("Назначение").font(.subheadline.weight(.semibold))
                if let suggested {
                    Label("Определено автоматически: \(suggested.russianName)" + (reason.map { " — \($0)" } ?? ""), systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(Theme.orange)
                } else {
                    Text("Выберите назначение — от него зависит, что ИИ поставит в помещение: в санузел только сантехнику, в спальню и гостиную — без сантехники.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                FlowChips(items: purposes, selection: $purpose)
                if let chosen {
                    Text(chosen.allowedShort).font(.caption).foregroundStyle(.white.opacity(0.85))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).panelCard(12)
                    if let suggested, suggested != chosen {
                        Label("По скану это \(suggested.russianName), а выбрано «\(purpose)». Проверьте назначение.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.danger)
                    }
                }
                Text("Стиль").font(.subheadline.weight(.semibold))
                FlowChips(items: styles, selection: $style)
                Text("Пожелания").font(.subheadline.weight(.semibold))
                TextField(chosen == .bathroom ? "Например: душ с трапом вместо ванны, подвесной унитаз, место под стиральную машину" : "Например: рабочее место у окна, много хранения, кровать 180 см, светлый пол", text: $wishes, axis: .vertical)
                    .lineLimit(3...6).padding(14).panelCard(14)
                PrimaryButton(title: purpose.isEmpty ? "Выберите назначение" : "Создать концепцию", icon: "wand.and.stars") {
                    guard !purpose.isEmpty else { Haptics.warning(); return }
                    onSubmit(style, purpose, wishes.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .opacity(purpose.isEmpty ? 0.5 : 1)
                InfoNote(text: "ИИ видит план сверху и размеры, поэтому предметы ставятся с учётом дверей, окон и проходов. Всё, что не подходит для выбранного помещения, приложение убирает автоматически.")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Новый дизайн")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        .onAppear { if purpose.isEmpty, let suggested { purpose = suggested.purposeTitle } }
    }
}

/// Wrapping chips (simple flow layout).
struct FlowChips: View {
    let items: [String]
    @Binding var selection: String
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { Haptics.tap(); selection = item } label: {
                    Text(item).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(selection == item ? Theme.orange : Theme.panel, in: Capsule())
                        .foregroundStyle(selection == item ? .black : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxWidth, widest), height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
