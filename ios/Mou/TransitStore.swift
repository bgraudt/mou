import SwiftUI
import Combine

/// Хранилище данных сети: грузит GTFS-JSON из бандла, держит фильтр линий и выбранную станцию.
@MainActor
final class TransitStore: ObservableObject {
    @Published private(set) var stops: [Stop] = []
    @Published private(set) var lines: [Line] = []
    @Published var activeLines: Set<String> = []
    @Published var selectedStop: Stop?
    @Published var query: String = ""

    private(set) var lineByID: [String: Line] = [:]

    init() { load() }

    func load() {
        stops = Self.decode("stops", [Stop].self) ?? []
        lines = Self.decode("lines", [Line].self) ?? []
        lineByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.line, $0) })
        activeLines = Set(lines.map(\.line))
    }

    private static func decode<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Станции, видимые при текущем фильтре линий.
    var visibleStops: [Stop] {
        stops.filter { stop in stop.lines.contains { activeLines.contains($0) } }
    }

    /// Результаты поиска по названию.
    var searchResults: [Stop] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return stops.filter { $0.name.lowercased().contains(q) }.prefix(8).map { $0 }
    }

    func color(for line: String) -> Color { Color(hex: lineByID[line]?.color ?? "#888888") }
    func textColor(for line: String) -> Color { Color(hex: lineByID[line]?.text ?? "#FFFFFF") }

    func toggle(_ line: String) {
        if activeLines.contains(line) { activeLines.remove(line) } else { activeLines.insert(line) }
    }
}

enum Sched {
    /// Минуты от текущего момента до времени "HH:MM" (в пределах сегодняшнего дня).
    static func minutes(until hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let cur = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        return parts[0] * 60 + parts[1] - cur
    }
}
