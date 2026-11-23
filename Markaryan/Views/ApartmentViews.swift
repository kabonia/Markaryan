import SwiftUI
import QuickLook

/// The whole apartment from above: every room where the scan saw it, partitions and doors once, room numbers.
struct ApartmentCanvas: View {
    let layout: ApartmentLayout
    var compact = false

    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let ink = Color(red: 0.13, green: 0.15, blue: 0.14)
    private let floorTint = Color(red: 0.93, green: 0.90, blue: 0.84)

    static func margin(compact: Bool) -> Double { compact ? 8 : 30 }

    var body: some View {
        let bodies = layout.wallBodies()
        let doorIDs = Set(layout.doors.map(\.door.id))
        return Canvas { context, size in
            let viewport = PlanViewport(bounds: layout.bounds, width: Double(size.width), height: Double(size.height), margin: Self.margin(compact: compact))
            func p(_ point: PlanPoint) -> CGPoint { let s = viewport.screen(point); return CGPoint(x: s.x, y: s.y) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            for room in layout.rooms {
                var floor = Path()
                floor.addLines(room.plan.outline.map(p)); floor.closeSubpath()
                context.fill(floor, with: .color(floorTint))
            }
            var walls = Path()
            for piece in bodies.flatMap(\.pieces) { walls.addLines(piece.polygon.map(p)); walls.closeSubpath() }
            context.fill(walls, with: .color(ink))
            for gap in bodies.flatMap(\.gaps) {
                if gap.opening.kind == .window {
                    var glass = Path()
                    glass.move(to: p(gap.innerStart + gap.outward * (gap.thickness / 2)))
                    glass.addLine(to: p(gap.innerEnd + gap.outward * (gap.thickness / 2)))
                    context.stroke(glass, with: .color(Color(red: 0.25, green: 0.55, blue: 0.85)), lineWidth: compact ? 1 : 2)
                } else if gap.opening.kind == .door && !compact && doorIDs.contains(gap.opening.id) {
                    let hinge = gap.innerStart.distance(to: gap.opening.start) <= gap.innerEnd.distance(to: gap.opening.start) ? gap.innerStart : gap.innerEnd
                    let latch = hinge == gap.innerStart ? gap.innerEnd : gap.innerStart
                    var leaf = Path()
                    leaf.move(to: p(hinge)); leaf.addLine(to: p(hinge + gap.outward * -hinge.distance(to: latch)))
                    context.stroke(leaf, with: .color(Theme.orange), lineWidth: 1.2)
                }
            }
            guard !compact else { return }
            for room in layout.rooms {
                let center = p(room.labelPoint)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 11, y: center.y - 22, width: 22, height: 22)), with: .color(ink))
                context.draw(Text("\(room.number)").font(.system(size: 11, weight: .bold)).foregroundColor(paper), at: CGPoint(x: center.x, y: center.y - 11))
                context.draw(Text(room.name).font(.system(size: 10, weight: .semibold)).foregroundColor(ink), at: CGPoint(x: center.x, y: center.y + 7))
                context.draw(Text(String(format: "%.1f м²", room.area).replacingOccurrences(of: ".", with: ",")).font(.system(size: 9).monospacedDigit()).foregroundColor(ink.opacity(0.75)), at: CGPoint(x: center.x, y: center.y + 20))
            }
        }
        .accessibilityLabel("План квартиры: \(layout.rooms.count) комнат, \(CalculationEngine.format((layout.area * 10).rounded() / 10)) квадратных метров")
    }
}

/// An apartment in the list of plans.
struct ApartmentRow: View {
    let apartment: Apartment

    var body: some View {
        HStack(spacing: 14) {
            ApartmentCanvas(layout: apartment.layout, compact: true)
                .frame(width: 92, height: 72).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(apartment.name).font(.headline).foregroundStyle(Theme.ink)
                Text("\(apartment.rooms.count) \(ApartmentView.roomsWord(apartment.rooms.count)) · \(CalculationEngine.format((apartment.area * 10).rounded() / 10)) м²")
                    .font(.caption).foregroundStyle(Theme.muted)
                Text("Квартира целиком").font(.caption.weight(.semibold)).foregroundStyle(Theme.orange)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .panelCard(18)
    }
}

/// The apartment: the plan of all rooms, the room schedule, drawings and DXF; a room opens its own plan screen.
struct ApartmentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let apartmentID: UUID

    @State private var openRoom: UUID?
    @State private var modelURL: URL?
    @State private var shareFile: SharedFile?
    @State private var error: String?
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var confirmUngroup = false

    private var apartment: Apartment? { store.apartments.first { $0.id == apartmentID } }

    static func roomsWord(_ count: Int) -> String {
        let tens = count % 100, units = count % 10
        if (11...14).contains(tens) { return "комнат" }
        if units == 1 { return "комната" }
        if (2...4).contains(units) { return "комнаты" }
        return "комнат"
    }

    var body: some View {
        Group {
            if let apartment { content(apartment) }
            else { ContentUnavailableView("Квартира удалена", systemImage: "trash") }
        }
        .background(Theme.background)
        .navigationTitle(apartment?.name ?? "Квартира").helperScreen(apartment?.name ?? "Квартира")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newName = apartment?.name ?? ""; showRename = true } label: { Label("Переименовать", systemImage: "pencil") }
                    Button { confirmUngroup = true } label: { Label("Разделить на отдельные комнаты", systemImage: "square.split.2x2") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить квартиру", systemImage: "trash") }
                } label: { Label("Ещё", systemImage: "ellipsis.circle") }
            }
        }
        .navigationDestination(item: $openRoom) { id in FloorPlanDetailView(planID: id) }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .quickLookPreview($modelURL)
        .alert("Название квартиры", isPresented: $showRename) {
            TextField("Например, квартира на Ленина", text: $newName)
            Button("Сохранить") { store.renameApartment(apartmentID, to: newName) }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Разделить квартиру? Комнаты останутся отдельными планами.", isPresented: $confirmUngroup, titleVisibility: .visible) {
            Button("Разделить") { store.ungroupApartment(apartmentID); dismiss() }
        }
        .confirmationDialog("Удалить квартиру со всеми комнатами и концепциями?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { store.deleteApartment(apartmentID); dismiss() }
        }
    }

    private func content(_ apartment: Apartment) -> some View {
        let layout = apartment.layout
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GeometryReader { geo in
                    ApartmentCanvas(layout: layout)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let viewport = PlanViewport(bounds: layout.bounds, width: Double(geo.size.width), height: Double(geo.size.height), margin: ApartmentCanvas.margin(compact: false))
                            if let room = layout.room(at: viewport.plan(x: Double(location.x), y: Double(location.y))) {
                                Haptics.tap()
                                openRoom = room.id
                            }
                        }
                }
                .aspectRatio(max(0.7, min(1.8, layout.width / max(0.5, layout.depth))), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Нажмите на комнату, чтобы открыть её план, дизайн и чертежи.").font(.caption).foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    PlanStat(value: "\(CalculationEngine.format((layout.area * 10).rounded() / 10)) м²", title: "Площадь комнат")
                    PlanStat(value: "\(layout.rooms.count)", title: Self.roomsWord(layout.rooms.count).capitalized)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }

                Text("ЭКСПЛИКАЦИЯ ПОМЕЩЕНИЙ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(layout.rooms) { room in
                    Button { Haptics.tap(); openRoom = room.id } label: {
                        HStack(spacing: 12) {
                            Text("\(room.number)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 28, height: 28).background(Theme.orange, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                let concepts = room.plan.proposals.count
                                Text(concepts == 0 ? "Дизайн ещё не создан" : "Концепций: \(concepts)").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text("\(CalculationEngine.format((room.area * 10).rounded() / 10)) м²").font(.subheadline).foregroundStyle(Theme.muted).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelCard(14)
                    }
                    .buttonStyle(PremiumCardPressStyle())
                }

                Text("ЧЕРТЕЖИ КВАРТИРЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold).padding(.top, 6)
                Text("Общий план с перегородками, номерами и площадями комнат и экспликацией — лист А3 со штампом. Листы каждой комнаты — в её разделе.")
                    .font(.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button { openDrawings(layout, name: apartment.name) } label: { SecondaryActionLabel(title: "План PDF", icon: "doc.text.magnifyingglass") }
                    Button { shareDXF(layout, name: apartment.name) } label: { SecondaryActionLabel(title: "DXF", icon: "square.and.arrow.up") }
                }
                .buttonStyle(PremiumPressStyle())
                InfoNote(text: "Комнаты сняты одним сканом и стоят на своих местах. Перегородки показаны по фактическому зазору между комнатами, наружные стены — условной толщины 150 мм.")
            }
            .padding(20)
        }
    }

    private func openDrawings(_ layout: ApartmentLayout, name: String) {
        do {
            modelURL = try DrawingsPDF.render(apartment: layout, name: name, projectName: store.projectDisplayName)
            store.track("apartment_drawings")
        } catch { self.error = "Не удалось сделать чертёж: \(error.localizedDescription)" }
    }

    private func shareDXF(_ layout: ApartmentLayout, name: String) {
        do {
            shareFile = SharedFile(url: try PlanDXF.file(apartment: layout, name: name))
            store.track("apartment_dxf")
        } catch { self.error = "Не удалось сделать DXF: \(error.localizedDescription)" }
    }
}
