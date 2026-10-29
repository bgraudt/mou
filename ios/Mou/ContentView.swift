import SwiftUI
import MapKit

extension View {
    /// Белая подложка с лёгкой прозрачностью и мягкой тенью.
    func cardBG<S: Shape>(_ shape: S) -> some View {
        self.background(Color.white.opacity(0.9), in: shape)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

/// Нажатие с лёгким «пружинным» уменьшением.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Контент, плавно проявляющийся при появлении (zoom или подгрузка при листании карты).
struct FadeIn<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var shown = false
    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.35)) { shown = true } }
            .onDisappear { shown = false }
    }
}

/// Треугольник-хвостик (остриём вниз) для «баллона» выбранной станции.
struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

enum MapKind: CaseIterable {
    case scheme, satellite, hybrid
    var style: MapStyle {
        switch self {
        case .scheme:    return .standard(pointsOfInterest: .excludingAll)
        case .satellite: return .imagery
        case .hybrid:    return .hybrid(pointsOfInterest: .excludingAll)
        }
    }
    var next: MapKind { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}

struct ContentView: View {
    @EnvironmentObject var store: TransitStore
    @StateObject private var loc = LocationManager()

    @State private var camera: MapCameraPosition = .region(Self.valencia)
    @State private var region: MKCoordinateRegion = Self.valencia
    @State private var kind: MapKind = .scheme
    @State private var searchActive = false
    @State private var didLocate = false          // синей станет только после тапа
    @FocusState private var searchFocused: Bool

    private let accent = Color(hex: "#007AFF")           // синий, как у Apple
    private let ink = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.12, opacity: 1)
    private let margin: CGFloat = 22             // для строки поиска
    private let ctrlMargin: CGFloat = 12         // для кнопок на карте (ближе к краю)
    private let bottomMargin: CGFloat = 36       // чуть выше, аккуратно над home indicator
    static let valencia = MKCoordinateRegion(center: .init(latitude: 39.47, longitude: -0.38),
                                             span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22))

    var body: some View {
        ZStack {
            mapLayer

            if searchActive { searchOverlay.zIndex(1) }

            if !searchActive {
                // верх-справа: слои (смена схема ↔ спутник)
                layersButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.horizontal, ctrlMargin).padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)

                // середина-слева: линейка масштаба (на другом краю, параллельно зуму)
                scaleBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, ctrlMargin)
                    .transition(.opacity)
                    .zIndex(2)

                // середина-справа: зум +/−
                zoomGroup
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.horizontal, ctrlMargin)
                    .transition(.opacity)
                    .zIndex(2)
            }

            VStack(spacing: 10) {
                Spacer()
                if store.selectedStop == nil {          // при выбранной станции поиск убираем (его накрывает карточка)
                    if !searchActive {
                        HStack(alignment: .bottom) {
                            leftButton
                            Spacer()
                            locateButton
                        }
                        .padding(.horizontal, ctrlMargin)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    searchPanel
                }
            }
            .zIndex(2)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: searchActive)
        .onChange(of: searchFocused) { _, focused in
            if focused != searchActive {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { searchActive = focused }
            }
        }
        .sheet(item: $store.selectedStop) { stop in
            StopDetailView(stop: stop, userLoc: loc.coordinate).environmentObject(store)
        }
        .preferredColorScheme(.light)   // дизайн светлый (как в референсах), без тёмной темы
        .onAppear {   // тестовые хуки для скриншотов
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-openStop"), i + 1 < a.count,
               let s = store.stops.first(where: { $0.name == a[i + 1] }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.selectedStop = s }
            }
            if a.contains("-zoomCity") {
                camera = .region(MKCoordinateRegion(
                    center: .init(latitude: 39.468, longitude: -0.372),
                    span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)))
            }
        }
    }

    // аэропорт Валенсии (Manises)
    private let airport = CLLocationCoordinate2D(latitude: 39.4893, longitude: -0.4816)
    // вокзалы (Renfe / Cercanías); th — порог зума, при котором виден
    private let trainStations: [(name: String, coord: CLLocationCoordinate2D, th: Double)] = [
        ("Estació del Nord", .init(latitude: 39.4660, longitude: -0.3770), 0.12),
        ("Cabanyal",         .init(latitude: 39.4736, longitude: -0.3306), 0.12),
        ("J. Sorolla",       .init(latitude: 39.4591, longitude: -0.3808), 0.035),
    ]
    // станции видны только при приближении (иначе — обычная карта); подписи ближе, номера линий — ещё ближе
    private var showAirport: Bool { region.span.latitudeDelta < 0.5 }   // виден раньше (уровень Сагунто)
    private var showLabels: Bool { region.span.latitudeDelta < 0.06 }
    private var showLineNumbers: Bool { region.span.latitudeDelta < 0.025 }
    private var isSatellite: Bool { kind != .scheme }
    private static let metroIcon = UIImage(named: "metro")

    // прогрессивная загрузка: важные станции (пересадки) видны раньше, мелкие — ближе
    private func stationThreshold(_ stop: Stop) -> Double {
        switch stop.lines.count {
        case 0, 1: return 0.05
        case 2:    return 0.10
        case 3:    return 0.18
        default:   return 0.40
        }
    }
    private func stationVisible(_ stop: Stop) -> Bool {
        region.span.latitudeDelta < stationThreshold(stop)
    }

    // для карты рисуем только нужные аннотации: видимые по зуму и попавшие в кадр (+выбранную).
    // это резко снижает нагрузку (иначе MapKit держит все 144 станции сразу).
    private var annotationStops: [Stop] {
        let r = region
        let latPad = r.span.latitudeDelta * 0.6, lonPad = r.span.longitudeDelta * 0.6
        let minLat = r.center.latitude - r.span.latitudeDelta / 2 - latPad
        let maxLat = r.center.latitude + r.span.latitudeDelta / 2 + latPad
        let minLon = r.center.longitude - r.span.longitudeDelta / 2 - lonPad
        let maxLon = r.center.longitude + r.span.longitudeDelta / 2 + lonPad
        return store.visibleStops.filter { s in
            if store.selectedStop?.id == s.id { return true }
            guard stationVisible(s) else { return false }
            return s.lat >= minLat && s.lat <= maxLat && s.lon >= minLon && s.lon <= maxLon
        }
    }

    // MARK: карта — метростанции при приближении + аэропорт

    private let markerAnim: Animation = .easeInOut(duration: 0.3)   // плавное затухание

    private var mapLayer: some View {
        Map(position: $camera) {
            ForEach(annotationStops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate,
                           anchor: store.selectedStop?.id == stop.id ? .bottom : .center) {
                    stationView(stop)
                }
                .annotationTitles(.hidden)
            }
            Annotation("Aeroport de València", coordinate: airport) {
                airportView
            }
            .annotationTitles(.hidden)
            ForEach(trainStations, id: \.name) { st in
                Annotation(st.name, coordinate: st.coord) {
                    trainView(name: st.name, show: region.span.latitudeDelta < st.th)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(kind.style)
        .onMapCameraChange(frequency: .continuous) { ctx in region = ctx.region }
        .ignoresSafeArea()
    }

    // станция: иконка ВСЕГДА отрисована на точке (фикс. размер 22×22) — не сдвигается;
    // видимость — только через opacity (затухание), без вставки/удаления, поэтому не «съезжает».
    // FadeIn даёт то же затухание при подгрузке во время листания карты.
    @ViewBuilder private func stationView(_ stop: Stop) -> some View {
        if store.selectedStop?.id == stop.id {
            selectedMarker(stop)
        } else {
            FadeIn {
                metroMarker
                    .overlay(alignment: .leading) {            // номера линий справа
                        lineBadges(stop.lines).fixedSize().offset(x: 25)
                            .opacity(showLineNumbers ? 1 : 0)
                    }
                    .overlay(alignment: .top) {                // подпись снизу
                        mapLabel(stop.name).fixedSize().offset(y: 25)
                            .opacity(showLabels ? 1 : 0)
                    }
            }
            .animation(markerAnim, value: showLabels)
            .animation(markerAnim, value: showLineNumbers)
            .onTapGesture { selectStop(stop) }
        }
    }

    // выбранная станция: белый «баллон» с лого метро, хвостик вниз, красная точка и подпись
    private func selectedMarker(_ stop: Stop) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(.white)
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                if let icon = Self.metroIcon {
                    Image(uiImage: icon).resizable().scaledToFit().frame(width: 32, height: 32)
                } else {
                    Circle().fill(Color(hex: "#E2231A")).frame(width: 30, height: 30)
                }
            }
            Triangle().fill(.white).frame(width: 15, height: 8)
            Circle().fill(Color(hex: "#E2231A")).frame(width: 7, height: 7)
        }
        .overlay(alignment: .bottom) {
            mapLabel(stop.name).fixedSize().offset(y: 16)
        }
        .onTapGesture { store.selectedStop = nil }
    }

    // открыть станцию: сместить камеру так, чтобы точка была в верхней половине (над картой станции)
    private func selectStop(_ stop: Stop) {
        store.selectedStop = stop
        let d = max(region.span.latitudeDelta, 0.012)
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(
                center: .init(latitude: stop.lat - d * 0.22, longitude: stop.lon),
                span: region.span))
        }
    }

    // аэропорт: синий квадрат с белым самолётом + «VLC» слева; фикс. размер, затухание без сдвига
    @ViewBuilder private var airportView: some View {
        FadeIn {
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                .overlay(alignment: .trailing) {           // VLC слева от иконки
                    vlcLabel.offset(x: -27)
                }
        }
        .opacity(showAirport ? 1 : 0)
        .allowsHitTesting(showAirport)
        .animation(markerAnim, value: showAirport)
    }

    // вокзал: фиолетовый квадрат с поездом + подпись снизу; затухание без сдвига
    @ViewBuilder private func trainView(name: String, show: Bool) -> some View {
        FadeIn {
            Image(systemName: "train.side.front.car")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: "#6E368C"), in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                .overlay(alignment: .top) {
                    mapLabel(name).fixedSize().offset(y: 24)
                }
        }
        .opacity(show ? 1 : 0)
        .allowsHitTesting(false)
        .animation(markerAnim, value: show)
    }

    // «VLC»: всегда синий, крупнее и жирнее, с тонким белым контуром (читается на спутнике)
    private var vlcLabel: some View {
        let base = Text("VLC").font(.system(size: 12, weight: .black))
        return ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                base.foregroundStyle(.white).offset(x: cos(a), y: sin(a))
            }
            base.foregroundStyle(accent)
        }
        .fixedSize()
    }

    // лого Metrovalencia на белой круглой подложке
    @ViewBuilder private var metroMarker: some View {
        ZStack {
            Circle().fill(.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
            if let icon = Self.metroIcon {
                Image(uiImage: icon).resizable().scaledToFit().frame(width: 17, height: 17)
            } else {
                Circle().fill(Color(hex: "#E2231A")).frame(width: 17, height: 17)
            }
        }
    }

    // номера линий станции справа (скруглённые квадраты, как у Metrovalencia)
    private func lineBadges(_ lines: [String]) -> some View {
        HStack(spacing: 2) {
            ForEach(lines, id: \.self) { l in
                Text(l)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: store.lineByID[l]?.text ?? "#FFFFFF"))
                    .frame(width: 15, height: 15)
                    .background(store.color(for: l), in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
        }
    }

    // подпись без плашки: схема — тёмно-серый; спутник — белый с синим контуром
    @ViewBuilder private func mapLabel(_ text: String) -> some View {
        let base = Text(text).font(.system(size: 10, weight: .semibold))
        if isSatellite {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) / 8 * 2 * .pi
                    base.foregroundStyle(accent)
                        .offset(x: cos(a) * 0.9, y: sin(a) * 0.9)
                }
                base.foregroundStyle(.white)
            }
            .fixedSize()
        } else {
            base.foregroundStyle(Color(white: 0.22)).fixedSize()
        }
    }

    // MARK: низ-слева — кнопка «маршрут» (белый скруглённый квадрат)

    private var leftButton: some View {
        Button { } label: {
            Image(systemName: "point.bottomleft.forward.to.arrow.triangle.scurvepath.fill")
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(ink)
                .frame(width: 52, height: 52)
                .cardBG(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: белые кнопки справа — слои (сверху), зум (посередине), геопозиция (снизу)

    private var layersButton: some View {
        squareButton("square.2.stack.3d", color: ink) {
            withAnimation(.easeInOut(duration: 0.25)) { kind = kind.next }
        }
    }

    private var zoomGroup: some View {
        VStack(spacing: 10) {                              // + и − — отдельными кнопками, крупнее
            squareButton("plus", color: ink, size: 27) { zoom(0.5) }
            squareButton("minus", color: ink, size: 27) { zoom(2) }
        }
    }

    // линейка масштаба: вертикальная линия фиксированной длины (= две кнопки зума) + подпись
    private var scaleBar: some View {
        let barLen: CGFloat = 96             // чуть короче блока зума
        let screenH = max(1, UIScreen.main.bounds.height)
        let metersPerPt = region.span.latitudeDelta * 111_000 / Double(screenH)
        let nice = niceNumber(Double(barLen) * metersPerPt)
        return HStack(spacing: 6) {
            Rectangle().fill(ink).frame(width: 2, height: barLen)
                .shadow(color: .white.opacity(0.9), radius: 1.5)
            Text(scaleLabel(nice))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .shadow(color: .white.opacity(0.9), radius: 1.5)
        }
    }

    private func niceNumber(_ x: Double) -> Double {
        guard x > 0 else { return 1 }
        let base = pow(10, floor(log10(x)))
        let f = x / base
        let nice: Double = f < 1.5 ? 1 : (f < 3.5 ? 2 : (f < 7.5 ? 5 : 10))
        return nice * base
    }

    private func scaleLabel(_ m: Double) -> String {
        m >= 1000 ? "\(Int((m / 1000).rounded())) km" : "\(Int(m)) m"
    }

    private var locateButton: some View {
        Button { loc.requestAndLocate(); recenterOnUser(); didLocate = true } label: {
            Image(systemName: "location.north.fill")
                .font(.system(size: 23, weight: .medium))
                .rotationEffect(.degrees(45))            // повёрнута вправо на 45°
                .foregroundStyle(didLocate ? accent : ink)   // серая, пока не нажал
                .frame(width: 58, height: 58)
                .cardBG(Circle())             // круглая подложка, чуть крупнее
        }
        .buttonStyle(PressStyle())
    }

    private func squareButton(_ systemName: String, color: Color, size: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium)).symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .cardBG(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressStyle())
    }

    private func zoom(_ factor: Double) {
        let s = region.span
        let lat = min(2, max(0.0025, s.latitudeDelta * factor))
        let lon = min(2, max(0.0025, s.longitudeDelta * factor))
        withAnimation(.easeInOut(duration: 0.25)) {
            camera = .region(MKCoordinateRegion(center: region.center,
                span: MKCoordinateSpan(latitudeDelta: lat, longitudeDelta: lon)))
        }
    }

    // MARK: нижняя строка поиска

    // нижняя шторка: хваталка + поле; докнута к низу без отступа, тянется вверх → поиск
    private var searchPanel: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color(.systemGray3)).frame(width: 40, height: 5)
            searchField
        }
        .padding(.top, 8)
        .padding(.horizontal, margin)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.white)
                .ignoresSafeArea(.container, edges: .bottom)   // белое уходит за home indicator
                .shadow(color: .black.opacity(0.12), radius: 10, y: -1)
        )
        .gesture(DragGesture(minimumDistance: 12).onEnded { v in
            if v.translation.height < -20 { searchFocused = true }   // потянул вверх → поиск
        })
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
            TextField("Cerca ací", text: $store.query)
                .font(.system(size: 17)).foregroundStyle(ink).tint(accent)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if searchActive {
                Button { store.query = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                }
                .buttonStyle(PressStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: оверлей поиска (фильтр линий + результаты)

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.lines) { line in
                            let on = store.activeLines.contains(line.line)
                            Button { store.toggle(line.line) } label: {
                                Text(line.line)
                                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                                    .foregroundStyle(Color(hex: line.text))
                                    .frame(width: 30, height: 30)
                                    .background(Color(hex: line.color), in: Circle())
                                    .opacity(on ? 1 : 0.3)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                Divider()
                if store.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    hint("Comença a escriure el nom de l'estació")
                } else if store.searchResults.isEmpty {
                    hint("No s'ha trobat res")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.searchResults) { s in
                                Button { select(s) } label: {
                                    HStack {
                                        Image(systemName: "mappin.circle.fill").foregroundStyle(accent)
                                        Text(s.name).foregroundStyle(ink)
                                        Spacer()
                                        ForEach(s.lines.prefix(4), id: \.self) { LineBadge(line: $0) }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                }
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .padding(.bottom, 100)
        }
        .padding(.horizontal, margin)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: действия

    private func recenterOnUser() {
        guard let c = loc.coordinate else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }
    private func select(_ s: Stop) {
        store.query = ""; searchFocused = false
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(
                center: .init(latitude: s.lat - 0.03 * 0.22, longitude: s.lon),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.selectedStop = s }
    }
}
