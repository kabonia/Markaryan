import SwiftUI
import MapKit
import CoreLocation

/// «Дом снаружи» → «Участок по кадастру»: граница из НСПД на карте, данные ЕГРН и проверки по нормам.
/// Найденный участок сохраняется и уходит в пакет скана — макет дома встанет на свой участок.
struct ParcelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var parcel: CadastralParcel? = ParcelStore.load()
    @State private var loading = false
    @State private var error: String?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    search
                    if let parcel { details(parcel) }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger) }
                    InfoNote(text: "Данные — из публичной кадастровой карты Росреестра (НСПД). Граница участка там с точностью межевания (обычно 0,1–0,3 м); на месте макет привязывается к ней по двум углам участка.")
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Участок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Кадастровый номер, напр. 50:20:0010101:123", text: $number)
                .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 10) {
                Button { Task { await find(byNumber: true) } } label: { SecondaryActionLabel(title: "Найти по номеру", icon: "magnifyingglass") }
                    .disabled(!NSPDClient.isCadastralNumber(number.trimmingCharacters(in: .whitespaces)))
                Button { Task { await find(byNumber: false) } } label: { SecondaryActionLabel(title: "Я на участке", icon: "location") }
            }
            .buttonStyle(PremiumPressStyle())
            if loading { HStack { ProgressView(); Text("Запрашиваем кадастровую карту…").font(.footnote) } }
        }
    }

    private func details(_ parcel: CadastralParcel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Map(position: $camera) {
                MapPolygon(coordinates: parcel.outline.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) })
                    .foregroundStyle(Theme.gold.opacity(0.18))
                    .stroke(Theme.gold, lineWidth: 2)
            }
            .mapStyle(.hybrid)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear { focus(parcel) }

            VStack(alignment: .leading, spacing: 8) {
                Text(parcel.cadNumber).font(.system(.title3, design: .serif, weight: .bold))
                if let address = parcel.address { Text(address).font(.footnote).foregroundStyle(Theme.muted) }
                row("Площадь по ЕГРН", parcel.areaDocument.map { "\(ParcelRules.format($0)) м²" })
                row("Площадь по границе", "\(ParcelRules.format(parcel.areaOutline)) м²")
                row("Категория", parcel.category)
                row("Разрешённое использование", parcel.permittedUse)
                row("Кадастровая стоимость", parcel.cadastralValue.map { "\(ParcelRules.format($0)) ₽" })
            }
            .padding(16).panelCard(16)

            VStack(alignment: .leading, spacing: 10) {
                Text("ПРОВЕРКИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach(ParcelRules.check(parcel: parcel, buildings: [])) { finding in FindingRow(finding: finding) }
                Text("Отступы дома и построек от границ, процент застройки и разрывы проверятся, когда появится макет дома после скана.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.footnote).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value ?? "—").font(.footnote.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private func focus(_ parcel: CadastralParcel) {
        let c = parcel.centroid
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon), latitudinalMeters: 160, longitudinalMeters: 160))
    }

    private func find(byNumber: Bool) async {
        error = nil
        loading = true
        defer { loading = false }
        do {
            let found: CadastralParcel
            if byNumber {
                found = try await NSPDClient.shared.parcel(number: number.trimmingCharacters(in: .whitespaces))
            } else {
                guard let location = await PreciseLocation.current() else {
                    error = "Не удалось определить местоположение. Разрешите доступ к геопозиции или введите кадастровый номер."
                    return
                }
                found = try await NSPDClient.shared.parcel(at: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
            }
            parcel = found
            number = found.cadNumber
            ParcelStore.save(found)
            focus(found)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FindingRow: View {
    let finding: ParcelFinding

    private var icon: (String, Color) {
        switch finding.level {
        case .ok: return ("checkmark.circle.fill", Theme.success)
        case .warning: return ("exclamationmark.triangle.fill", Theme.gold)
        case .problem: return ("xmark.octagon.fill", Theme.danger)
        case .info: return ("info.circle.fill", Theme.sky)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon.0).foregroundStyle(icon.1)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.title).font(.subheadline.weight(.semibold))
                if !finding.detail.isEmpty { Text(finding.detail).font(.caption).foregroundStyle(Theme.muted) }
                if let norm = finding.norm { Text(norm).font(.caption2).foregroundStyle(Theme.gold) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).panelCard(14)
    }
}

/// Последний найденный участок (один файл в «HouseScans»).
enum ParcelStore {
    private static var url: URL { HouseScanStore.root.appendingPathComponent("parcel.json") }
    static func load() -> CadastralParcel? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CadastralParcel.self, from: data)
    }
    static func save(_ parcel: CadastralParcel) {
        try? FileManager.default.createDirectory(at: HouseScanStore.root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(parcel).write(to: url)
    }
}

/// Точная геопозиция (до 10–20 м) — для поиска участка и привязки скана к карте и солнцу.
@MainActor final class PreciseLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var best: CLLocation?
    private var timeout: Task<Void, Never>?

    static func current() async -> CLLocation? { await PreciseLocation().locate() }

    private func locate() async -> CLLocation? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.startUpdatingLocation() }
            // До 8 секунд ждём точку точнее 15 м, иначе берём лучшую из полученных.
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.finish(self?.best)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        manager.stopUpdatingLocation()
        timeout?.cancel()
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations where location.horizontalAccuracy >= 0 {
                if self.best == nil || location.horizontalAccuracy < self.best!.horizontalAccuracy { self.best = location }
            }
            if let best = self.best, best.horizontalAccuracy <= 15 { self.finish(best) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.best == nil { self.finish(nil) } }
    }
}
