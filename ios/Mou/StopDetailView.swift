import SwiftUI
import MapKit
import CoreLocation

/// Карточка станции в стиле Яндекс.Карт: заголовок → линии → дистанция →
/// вкладки «Обзор / Расписание». В «Обзоре» — ближайший поезд по направлениям
/// (можно развернуть встречное), адрес и контакт. «Расписание» разворачивает лист на весь экран.
struct StopDetailView: View {
    @EnvironmentObject var store: TransitStore
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    var userLoc: CLLocationCoordinate2D? = nil

    enum Tab { case overview, schedule }
    @State private var tab: Tab = .overview
    @State private var detent: PresentationDetent = .medium
    @State private var address: String? = nil
    @State private var expanded: Set<String> = []

    private let accent = Color(hex: "#007AFF")
    private let ink = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.12, opacity: 1)
    private let routeBlue = Color(hex: "#0B1A4D")   // тёмно-тёмно-синий для «Ruta»
    private let phone = "900461046"

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    lineIdentity
                    if let d = distanceText {
                        Text(d).font(.system(size: 15)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20).padding(.top, 10)
                    }
                    tabsBar.padding(.top, 18)
                    if tab == .overview { overview } else { schedule }
                }
                .padding(.bottom, 16)
            }
            bottomBar
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.white)
        .task { await geocode() }
    }

    // MARK: заголовок

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name).font(.system(size: 27, weight: .bold)).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stationKind).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5), in: Circle())
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
    }

    private var stationKind: String {
        let types = Set(stop.lines.compactMap { store.lineByID[$0]?.type })
        if types == ["tram"] { return "Parada de tramvia" }
        if types.contains("tram") && types.contains("metro") { return "Estació de metro i tramvia" }
        return "Estació de metro"
    }

    // MARK: линии (иконка метро + бейдж + название ветки)

    private var lineIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(stop.lines, id: \.self) { l in
                if let line = store.lineByID[l] {
                    HStack(spacing: 10) {
                        metroGlyph
                        lineBadge(l, size: 24, font: 13, radius: 6)
                        Text(branchName(line)).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ink).lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 2)
    }

    private var metroGlyph: some View {
        ZStack {
            Circle().fill(.white).frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 0.5))
            if let i = UIImage(named: "metro") {
                Image(uiImage: i).resizable().scaledToFit().frame(width: 20, height: 20)
            }
        }
    }

    private func lineBadge(_ l: String, size: CGFloat, font: CGFloat, radius: CGFloat) -> some View {
        Text(l).font(.system(size: font, weight: .heavy))
            .foregroundStyle(store.textColor(for: l))
            .frame(width: size, height: size)
            .background(store.color(for: l), in: RoundedRectangle(cornerRadius: radius))
    }

    /// «1 - Bétera - Castelló» → «Bétera – Castelló»
    private func branchName(_ line: Line) -> String {
        let parts = line.name.components(separatedBy: " - ")
        let tail = parts.count > 1 ? Array(parts.dropFirst()) : parts
        return tail.joined(separator: " – ")
    }

    private var distanceText: String? {
        guard let u = userLoc else { return nil }
        let d = CLLocation(latitude: u.latitude, longitude: u.longitude)
            .distance(from: CLLocation(latitude: stop.lat, longitude: stop.lon))
        if d < 950 { return "\(Int((d / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", d / 1000).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: вкладки

    private var tabsBar: some View {
        HStack(spacing: 26) {
            tabButton("Resum", .overview)
            tabButton("Horari", .schedule)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .overlay(Divider(), alignment: .bottom)
    }

    private func tabButton(_ title: String, _ t: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                tab = t
                detent = (t == .schedule ? .large : .medium)
            }
        } label: {
            VStack(spacing: 7) {
                Text(title).font(.system(size: 16, weight: tab == t ? .semibold : .regular))
                    .foregroundStyle(tab == t ? accent : Color.secondary)
                Rectangle().fill(tab == t ? accent : .clear).frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: обзор

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stop.lines, id: \.self) { l in
                let gs = directionGroups(for: l)
                if !gs.isEmpty {
                    let shown = expanded.contains(l) ? gs : Array(gs.prefix(1))
                    ForEach(shown, id: \.to) { g in directionRow(line: l, group: g) }
                    if gs.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expanded.contains(l) { expanded.remove(l) } else { expanded.insert(l) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(expanded.contains(l) ? "Replegar"
                                     : "\(gs.count - 1) \(plural(gs.count - 1)) més")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .rotationEffect(.degrees(expanded.contains(l) ? 180 : 0))
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if directionsEmpty {
                Text("No queden més eixides per a hui")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            }
            infoSection
        }
    }

    private var directionsEmpty: Bool {
        stop.lines.allSatisfy { directionGroups(for: $0).isEmpty }
    }

    private func directionRow(line: String, group: (to: String, deps: [Departure])) -> some View {
        let next = group.deps[0]
        let mins = Sched.minutes(until: next.t) ?? 0
        let iv = interval(group.deps)
        return HStack(spacing: 12) {
            Image(systemName: isTram(line) ? "tram.fill" : "tram.tunnel.fill")
                .font(.system(size: 16)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(white: 0.5), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.to).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ink).lineLimit(1)
                Text(iv != nil ? "interval ~\(iv!) min" : "a les \(next.t)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(mins <= 0 ? "ara" : "d'ací a \(mins) min")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mins <= 2 ? accent : ink)
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
    }

    private func directionGroups(for line: String) -> [(to: String, deps: [Departure])] {
        let up = stop.dep.filter { $0.line == line && (Sched.minutes(until: $0.t) ?? -1) >= 0 }
        var byTo: [String: [Departure]] = [:]
        for d in up { byTo[d.to, default: []].append(d) }
        return byTo.map { (to: $0.key, deps: $0.value.sorted { $0.t < $1.t }) }
            .sorted { (Sched.minutes(until: $0.deps[0].t) ?? 9999) < (Sched.minutes(until: $1.deps[0].t) ?? 9999) }
    }

    private func interval(_ deps: [Departure]) -> Int? {
        let ms = deps.prefix(6).compactMap { Sched.minutes(until: $0.t) }
        guard ms.count >= 2 else { return nil }
        var gaps: [Int] = []
        for i in 1..<ms.count { gaps.append(ms[i] - ms[i - 1]) }
        let g = gaps.sorted()[gaps.count / 2]
        return g > 0 ? g : nil
    }

    private func isTram(_ line: String) -> Bool { store.lineByID[line]?.type == "tram" }

    private func plural(_ n: Int) -> String {
        n == 1 ? "opció" : "opcions"
    }

    // MARK: адрес + контакт

    private var infoSection: some View {
        VStack(spacing: 0) {
            if let a = address {
                infoRow(icon: "mappin.and.ellipse", title: a, sub: "Adreça")
            }
            infoRow(icon: "phone", title: "900 46 10 46", sub: "Metrovalencia · informació")
        }
        .padding(.top, 8)
    }

    private func infoRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sub).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
    }

    // MARK: расписание (весь день, по времени)

    private var schedule: some View {
        let up = stop.dep
            .filter { (Sched.minutes(until: $0.t) ?? -1) >= 0 }
            .sorted { $0.t < $1.t }
        return LazyVStack(spacing: 0) {
            if up.isEmpty {
                Text(stop.dep.isEmpty ? "No hi ha horari per a hui" : "No queden més eixides per a hui")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            } else {
                ForEach(Array(up.enumerated()), id: \.offset) { _, d in
                    scheduleRow(d)
                }
            }
        }
    }

    private func scheduleRow(_ d: Departure) -> some View {
        let mins = Sched.minutes(until: d.t) ?? 0
        return HStack(spacing: 12) {
            Text(d.t).font(.system(.body, design: .monospaced).weight(.bold))
                .monospacedDigit().foregroundStyle(ink)
                .frame(width: 54, alignment: .leading)
            lineBadge(d.line, size: 22, font: 12, radius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.to.isEmpty ? "—" : d.to).font(.system(size: 15)).foregroundStyle(ink).lineLimit(1)
                Text(mins <= 0 ? "ara" : "d'ací a \(mins) min")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: isTram(d.line) ? "tram.fill" : "tram.tunnel.fill")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .overlay(Divider().padding(.leading, 20), alignment: .bottom)
    }

    // MARK: нижняя панель

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { openDirections() } label: {
                Text("Ruta").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30).frame(height: 46)
                    .background(routeBlue, in: RoundedRectangle(cornerRadius: 20))
            }
            Button { call() } label: {
                Image(systemName: "phone.fill").font(.system(size: 17)).foregroundStyle(routeBlue)
                    .frame(width: 48, height: 46)
                    .background(routeBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
        .background(Color.white)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: действия

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }

    private func call() {
        if let url = URL(string: "tel://\(phone)") { UIApplication.shared.open(url) }
    }

    private func geocode() async {
        let g = CLGeocoder()
        let loc = CLLocation(latitude: stop.lat, longitude: stop.lon)
        if let pm = try? await g.reverseGeocodeLocation(loc).first {
            let parts = [pm.thoroughfare, pm.subThoroughfare, pm.locality].compactMap { $0 }
            if !parts.isEmpty { address = parts.joined(separator: ", ") }
        }
    }
}

/// Бейдж линии для списков (используется в оверлее поиска).
struct LineBadge: View {
    @EnvironmentObject var store: TransitStore
    let line: String
    var body: some View {
        Text(line)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(store.textColor(for: line))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(store.color(for: line), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Color {
    /// Белый или чёрный текст для контраста на этом фоне.
    var contrastingText: Color {
        let ui = UIColor(self); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
    }
}
