import SwiftUI

// MARK: - Furniture by hand

/// Moving the furniture of a concept with a finger: drag, turn, remove, add. Items stand flush to the walls they come
/// close to; the layout check marks what is wrong. Nothing is saved until «Сохранить».
struct FurnitureEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let planID: FloorPlan.ID
    let proposalID: UUID

    @State private var furniture: [DesignFurniture] = []
    @State private var history: [[DesignFurniture]] = []
    @State private var selected: Int?
    @State private var snap = true
    @State private var issues: [LayoutIssue] = []
    @State private var dragging: (index: Int, offset: PlanPoint)?
    @State private var showCatalog = false
    @State private var loaded = false
    @State private var confirmDiscard = false

    private var plan: FloorPlan? { store.floorPlans.first { $0.id == planID } }
    private var proposal: DesignProposal? { plan?.proposals.first { $0.id == proposalID } }
    private var changed: Bool { loaded && proposal.map { $0.furniture != furniture } ?? false }
    private var flagged: Set<Int> { Set(issues.flatMap(\.items)) }

    var body: some View {
        Group {
            if let plan, let proposal { editor(plan, proposal) }
            else { ContentUnavailableView("Концепция удалена", systemImage: "trash") }
        }
        .background(Theme.background)
        .navigationTitle("Мебель").helperScreen("Мебель")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { if changed { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }.disabled(!changed)
            }
        }
        .confirmationDialog("Выйти без сохранения?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Не сохранять", role: .destructive) { dismiss() }
        }
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                List(catalog) { entry in
                    Button { add(entry) } label: {
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text(size(entry.width, entry.depth)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .navigationTitle("Добавить предмет").helperScreen("Добавить предмет")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showCatalog = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear(perform: load)
    }

    private var catalog: [FurnitureCatalog.Entry] {
        guard let plan else { return FurnitureCatalog.all }
        return FurnitureCatalog.entries(for: RoomKind.detect(plan: plan, proposal: proposal))
    }

    private func editor(_ plan: FloorPlan, _ proposal: DesignProposal) -> some View {
        let walls = PlanWalls.numbered(plan)
        var shown = proposal
        shown.furniture = furniture
        return VStack(spacing: 12) {
            GeometryReader { geo in
                let viewport = PlanViewport(plan: plan, width: Double(geo.size.width), height: Double(geo.size.height), margin: FloorPlanCanvas.margin(compact: false))
                ZStack {
                    FloorPlanCanvas(plan: plan, proposal: shown)
                    marks(viewport)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drag(viewport, walls: walls, plan: plan))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            controls(plan, walls: walls)
        }
        .padding(.vertical, 12)
    }

    /// The selected item in orange, items with a problem dashed in red.
    private func marks(_ viewport: PlanViewport) -> some View {
        let flagged = self.flagged
        return Canvas { context, _ in
            func outline(_ item: DesignFurniture) -> Path {
                var path = Path()
                path.addLines(item.footprint.corners.map { point in
                    let s = viewport.screen(point)
                    return CGPoint(x: s.x, y: s.y)
                })
                path.closeSubpath()
                return path
            }
            for index in flagged where furniture.indices.contains(index) {
                context.stroke(outline(furniture[index]), with: .color(Theme.danger), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
            }
            if let selected, furniture.indices.contains(selected) {
                context.stroke(outline(furniture[selected]), with: .color(Theme.orange), lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
    }

    /// A finger on an item picks it and drags it; on an empty spot it clears the choice.
    private func drag(_ viewport: PlanViewport, walls: [WallSide], plan: FloorPlan) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    let start = viewport.plan(x: Double(value.startLocation.x), y: Double(value.startLocation.y))
                    guard let index = FurnitureEditor.item(at: start, in: furniture, margin: 12 / viewport.scale) else {
                        selected = nil
                        return
                    }
                    selected = index
                    history.append(furniture)
                    dragging = (index, PlanPoint(x: furniture[index].x - start.x, y: furniture[index].y - start.y))
                }
                // A tap only picks the item: it must not jump to a wall.
                guard let current = dragging, furniture.indices.contains(current.index),
                      hypot(value.translation.width, value.translation.height) >= 3 else { return }
                let point = viewport.plan(x: Double(value.location.x), y: Double(value.location.y))
                furniture[current.index] = FurnitureEditor.move(furniture[current.index], to: point + current.offset, walls: walls, snap: snap)
            }
            .onEnded { _ in
                if dragging != nil {
                    if let last = history.last, last == furniture { history.removeLast() }
                    recheck(plan)
                }
                dragging = nil
            }
    }

    private func controls(_ plan: FloorPlan, walls: [WallSide]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Names as chips: also the way to pick a mirror that hangs above a sink.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(furniture.enumerated()), id: \.offset) { index, item in
                        Button { Haptics.tap(); selected = index } label: {
                            Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(selected == index ? Theme.orange : (flagged.contains(index) ? Theme.danger.opacity(0.35) : Theme.panel), in: Capsule())
                                .foregroundStyle(selected == index ? Color.black : Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let selected, furniture.indices.contains(selected) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(furniture[selected].name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(size(furniture[selected].width, furniture[selected].depth)).font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    iconButton("rotate.right", "Повернуть на 90°") {
                        change { furniture[selected] = FurnitureEditor.rotated(furniture[selected], by: 90, walls: walls, snap: snap) }
                    }
                    iconButton("goforward.15", "Повернуть на 15°") {
                        change { furniture[selected] = FurnitureEditor.rotated(furniture[selected], by: 15, walls: walls, snap: snap) }
                    }
                    iconButton("trash", "Удалить", destructive: true) {
                        change {
                            furniture.remove(at: selected)
                            self.selected = nil
                        }
                    }
                }
            } else {
                Text("Нажмите на предмет и перетащите его. У стены он встанет вплотную и ровно.").font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Button { showCatalog = true } label: { SecondaryActionLabel(title: "Добавить", icon: "plus") }
                    .buttonStyle(PremiumPressStyle())
                Button { undo() } label: { SecondaryActionLabel(title: "Отменить", icon: "arrow.uturn.backward") }
                    .buttonStyle(PremiumPressStyle())
                    .disabled(history.isEmpty)
                    .opacity(history.isEmpty ? 0.5 : 1)
            }
            Toggle("Прилипать к стенам", isOn: $snap).font(.subheadline).tint(Theme.orange)
            if issues.isEmpty {
                Label("Проходы, двери и окна свободны", systemImage: "checkmark.seal.fill").font(.footnote).foregroundStyle(Theme.success)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(issues.prefix(3).enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.danger)
                    }
                    if issues.count > 3 { Text("И ещё \(issues.count - 3)").font(.caption).foregroundStyle(Theme.muted) }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func iconButton(_ icon: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(destructive ? Theme.danger : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func size(_ width: Double, _ depth: Double) -> String {
        String(format: "%.2f × %.2f м", width, depth).replacingOccurrences(of: ".", with: ",")
    }

    private func load() {
        guard !loaded, let plan, let proposal else { return }
        furniture = proposal.furniture
        loaded = true
        recheck(plan)
    }

    private func recheck(_ plan: FloorPlan) {
        issues = LayoutCheck.issues(plan: plan, furniture: furniture)
    }

    /// One step that «Отменить» can take back.
    private func change(_ body: () -> Void) {
        guard let plan else { return }
        history.append(furniture)
        body()
        recheck(plan)
    }

    private func add(_ entry: FurnitureCatalog.Entry) {
        guard let plan else { return }
        change {
            furniture.append(FurnitureEditor.placeNew(entry.item, plan: plan, furniture: furniture))
            selected = furniture.count - 1
        }
        showCatalog = false
        store.track("furniture_added")
    }

    private func undo() {
        guard let previous = history.popLast(), let plan else { return }
        furniture = previous
        if let selected, !furniture.indices.contains(selected) { self.selected = nil }
        recheck(plan)
    }

    private func save() {
        guard var plan, let index = plan.proposals.firstIndex(where: { $0.id == proposalID }) else { return }
        plan.proposals[index].furniture = furniture
        plan.proposals[index].editedAt = Date()
        if plan.proposals[index].layoutVersion == nil { plan.proposals[index].layoutVersion = 2 }
        store.savePlan(plan)
        store.track("furniture_edited")
        Haptics.success()
        dismiss()
    }
}

// MARK: - The plan by hand

/// Corrections of the plan: wall lengths, the ceiling, doors and windows, square corners. The furniture of every
/// concept moves with the walls. Nothing is saved until «Сохранить».
struct PlanEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let planID: FloorPlan.ID

    @State private var draft: FloorPlan?
    @State private var history: [FloorPlan] = []
    @State private var error: String?
    @State private var notice: String?
    @State private var wallNumber = 1
    @State private var showWallLength = false
    @State private var showCeiling = false
    @State private var valueText = ""
    @State private var opening: OpeningDraft?
    @State private var confirmDiscard = false

    struct OpeningDraft: Identifiable {
        let id = UUID()
        /// nil — a new opening.
        let segmentID: UUID?
        let spec: PlanEditor.OpeningSpec
    }

    struct OpeningRow: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let icon: String
        let spec: PlanEditor.OpeningSpec
    }

    var body: some View {
        Group {
            if let draft { content(draft) }
            else { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.background)
        .navigationTitle("Правка плана").helperScreen("Правка плана")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { if history.isEmpty { dismiss() } else { confirmDiscard = true } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }.disabled(history.isEmpty)
            }
        }
        .confirmationDialog("Выйти без сохранения?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Не сохранять", role: .destructive) { dismiss() }
        }
        .alert("Длина стены \(wallNumber)", isPresented: $showWallLength) {
            TextField("Метры, например 3,42", text: $valueText).keyboardType(.decimalPad)
            Button("Сохранить") { applyWallLength() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Дальняя часть комнаты сдвинется вдоль стены, мебель и проёмы — вместе с ней.")
        }
        .alert("Высота потолка", isPresented: $showCeiling) {
            TextField("Метры, например 2,7", text: $valueText).keyboardType(.decimalPad)
            Button("Сохранить") { applyCeiling() }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(item: $opening) { item in
            NavigationStack {
                OpeningFormView(walls: draft.map { PlanWalls.numbered($0) } ?? [], initial: item.spec, isNew: item.segmentID == nil,
                                onSave: { spec in try saveOpening(item.segmentID, spec) },
                                onDelete: { if let id = item.segmentID { removeOpening(id) } })
            }
        }
        .onAppear { if draft == nil { draft = store.floorPlans.first { $0.id == planID } } }
    }

    private func content(_ plan: FloorPlan) -> some View {
        let walls = PlanWalls.numbered(plan)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FloorPlanCanvas(plan: plan, proposal: nil, wallNumbers: true)
                    .aspectRatio(max(0.7, min(1.6, plan.width / max(0.5, plan.depth))), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
                } else if let notice {
                    Label(notice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.success)
                }

                Text("СТЕНЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange)
                ForEach(walls, id: \.number) { wall in
                    row(title: "Стена \(wall.number)", value: "\(PlanEditor.meters(wall.length)) м", icon: "ruler") {
                        wallNumber = wall.number
                        valueText = PlanEditor.meters(wall.length)
                        showWallLength = true
                    }
                }
                row(title: "Высота потолка", value: "\(PlanEditor.meters(plan.ceilingHeight)) м", icon: "arrow.up.and.down") {
                    valueText = PlanEditor.meters(plan.ceilingHeight)
                    showCeiling = true
                }
                Button { straighten() } label: { SecondaryActionLabel(title: "Выпрямить углы", icon: "square.dashed") }
                    .buttonStyle(PremiumPressStyle())

                Text("ДВЕРИ И ОКНА").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.orange).padding(.top, 6)
                let rows = openingRows(plan)
                if rows.isEmpty {
                    Text("На плане нет дверей и окон. Добавьте их, чтобы мебель не закрывала проходы и окна.").font(.caption).foregroundStyle(Theme.muted)
                }
                ForEach(rows) { item in
                    row(title: item.title, value: item.detail, icon: item.icon) {
                        opening = OpeningDraft(segmentID: item.id, spec: item.spec)
                    }
                }
                HStack(spacing: 10) {
                    Button { newOpening(.door, walls: walls) } label: { SecondaryActionLabel(title: "Дверь", icon: "plus") }
                    Button { newOpening(.window, walls: walls) } label: { SecondaryActionLabel(title: "Окно", icon: "plus") }
                }
                .buttonStyle(PremiumPressStyle())
                if !history.isEmpty {
                    Button { undo() } label: { SecondaryActionLabel(title: "Отменить последнюю правку", icon: "arrow.uturn.backward") }
                        .buttonStyle(PremiumPressStyle())
                }
                InfoNote(text: "Стены нумеруются по часовой стрелке от входа. Мебель всех концепций двигается вместе со стенами; 3D‑модель скана (USDZ) остаётся исходной.")
            }
            .padding(20)
        }
    }

    private func row(title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.orange).frame(width: 24)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(value).font(.subheadline).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard(14)
        }
        .buttonStyle(PremiumCardPressStyle())
    }

    private func openingRows(_ plan: FloorPlan) -> [OpeningRow] {
        plan.segments.filter { $0.kind != .wall }.compactMap { segment in
            guard let spec = PlanEditor.spec(of: segment.id, in: plan) else { return nil }
            let title = segment.kind == .window ? "Окно" : (segment.kind == .door ? "Дверь" : "Проём")
            var detail = "стена \(spec.wall) · \(PlanEditor.meters(spec.width)) × \(PlanEditor.meters(spec.height)) м"
            if segment.kind == .window { detail += " · от пола \(PlanEditor.meters(spec.sill))" }
            return OpeningRow(id: segment.id, title: title, detail: detail, icon: segment.kind == .window ? "window.vertical.closed" : "door.left.hand.open", spec: spec)
        }
    }

    /// Applies one edit to the draft; a refused edit leaves the draft as it was and says why.
    private func apply(_ edit: (FloorPlan) throws -> FloorPlan, notice text: String) {
        guard let current = draft else { return }
        do {
            let edited = try edit(current)
            history.append(current)
            draft = edited
            error = nil
            notice = text
            Haptics.success()
        } catch {
            self.error = error.localizedDescription; HelperCenter.shared.failed(error)
            notice = nil
            Haptics.warning()
        }
    }

    private func applyWallLength() {
        guard let length = PlanEditor.parseMeters(valueText) else { error = "Введите длину числом, например 3,42."; return }
        let number = wallNumber
        apply({ try PlanEditor.setWallLength($0, wall: number, to: length) }, notice: "Стена \(number): \(PlanEditor.meters(length)) м.")
    }

    private func applyCeiling() {
        guard let height = PlanEditor.parseMeters(valueText) else { error = "Введите высоту числом, например 2,7."; return }
        apply({ try PlanEditor.setCeilingHeight($0, to: height) }, notice: "Потолок: \(PlanEditor.meters(height)) м.")
    }

    private func straighten() {
        guard let current = draft else { return }
        do {
            let result = try PlanEditor.straightened(current)
            error = nil
            guard result.corners > 0 else { notice = "Углы уже прямые."; return }
            history.append(current)
            draft = result.plan
            notice = "Выпрямлено углов: \(result.corners)."
            Haptics.success()
        } catch {
            self.error = error.localizedDescription; HelperCenter.shared.failed(error)
            notice = nil
            Haptics.warning()
        }
    }

    private func newOpening(_ kind: PlanSegment.Kind, walls: [WallSide]) {
        let free = walls.filter { $0.doors.isEmpty && $0.windows.isEmpty }
        guard let wall = (free.isEmpty ? walls : free).max(by: { $0.length < $1.length }) else { return }
        var spec: PlanEditor.OpeningSpec = kind == .window ? .window(wall: wall.number, from: 0) : .door(wall: wall.number, from: 0)
        spec.from = max(0, (wall.length - spec.width) / 2)
        opening = OpeningDraft(segmentID: nil, spec: spec)
    }

    private func saveOpening(_ id: UUID?, _ spec: PlanEditor.OpeningSpec) throws {
        guard let current = draft else { return }
        let edited: FloorPlan
        if let id {
            edited = try PlanEditor.updateOpening(current, id: id, to: spec)
        } else {
            edited = try PlanEditor.addOpening(current, spec).plan
        }
        history.append(current)
        draft = edited
        error = nil
        let name = spec.kind == .window ? "Окно" : (spec.kind == .door ? "Дверь" : "Проём")
        notice = id == nil ? "\(name) добавлено на стену \(spec.wall)." : "\(name): изменения внесены."
    }

    private func removeOpening(_ id: UUID) {
        guard let current = draft else { return }
        history.append(current)
        draft = PlanEditor.removeOpening(current, id: id)
        error = nil
        notice = "Проём удалён."
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        draft = previous
        error = nil
        notice = nil
    }

    private func save() {
        guard let draft else { return }
        store.savePlan(draft)
        store.track("plan_edited")
        Haptics.success()
        dismiss()
    }
}

/// A door, an opening without a door or a window: on which wall, where, how big.
struct OpeningFormView: View {
    @Environment(\.dismiss) private var dismiss
    let walls: [WallSide]
    let initial: PlanEditor.OpeningSpec
    let isNew: Bool
    let onSave: (PlanEditor.OpeningSpec) throws -> Void
    let onDelete: () -> Void

    @State private var kind: PlanSegment.Kind = .door
    @State private var wall = 1
    @State private var from = ""
    @State private var width = ""
    @State private var height = ""
    @State private var sill = ""
    @State private var hingeAtEnd = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Что это", selection: $kind) {
                    Text("Дверь").tag(PlanSegment.Kind.door)
                    Text("Проём").tag(PlanSegment.Kind.opening)
                    Text("Окно").tag(PlanSegment.Kind.window)
                }
                .pickerStyle(.segmented)
                Picker("Стена", selection: $wall) {
                    ForEach(walls, id: \.number) { side in
                        Text("Стена \(side.number) · \(PlanEditor.meters(side.length)) м").tag(side.number)
                    }
                }
            }
            Section {
                field("От начала стены", text: $from)
                field("Ширина", text: $width)
                field("Высота", text: $height)
                if kind == .window { field("Подоконник от пола", text: $sill) }
                if kind == .door { Toggle("Петли с другой стороны", isOn: $hingeAtEnd) }
            } header: {
                Text("Размеры, м")
            } footer: {
                Text("«От начала» — по ходу нумерации стен, как на плане. Можно вводить в сантиметрах: 80 — это 0,8 м.")
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
            }
            if !isNew {
                Section { Button("Удалить", role: .destructive) { onDelete(); dismiss() } }
            }
        }
        .navigationTitle(isNew ? (initial.kind == .window ? "Новое окно" : "Новая дверь") : "Проём")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, newKind in
            // Typical sizes when a door becomes a window and back.
            let current = PlanEditor.parseMeters(height) ?? 0
            if newKind == .window && current > 1.9 { height = PlanEditor.meters(1.5); sill = PlanEditor.meters(0.85) }
            if newKind != .window && current < 1.8 { height = PlanEditor.meters(2.1) }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0,00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        kind = initial.kind
        wall = initial.wall
        from = PlanEditor.meters(initial.from)
        width = PlanEditor.meters(initial.width)
        height = PlanEditor.meters(initial.height)
        sill = PlanEditor.meters(initial.sill)
        hingeAtEnd = initial.hingeAtEnd
    }

    private func save() {
        guard let start = PlanEditor.parseMeters(from), let size = PlanEditor.parseMeters(width), let tall = PlanEditor.parseMeters(height) else {
            error = "Заполните размеры числами."
            return
        }
        let bottom = kind == .window ? (PlanEditor.parseMeters(sill) ?? 0.85) : 0
        do {
            try onSave(PlanEditor.OpeningSpec(kind: kind, wall: wall, from: start, width: size, height: tall, sill: bottom, hingeAtEnd: kind == .door && hingeAtEnd))
            dismiss()
        } catch {
            self.error = error.localizedDescription; HelperCenter.shared.failed(error)
        }
    }
}
