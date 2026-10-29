import SwiftUI
import CoreLocation

/// Отправление со станции (из расписания GTFS).
struct Departure: Codable, Hashable {
    let t: String        // "HH:MM"
    let line: String
    let to: String
    let type: String     // "metro" | "tram"
    let color: String    // "#RRGGBB"
}

/// Станция.
struct Stop: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let zone: String
    let lines: [String]
    let dep: [Departure]

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Линия (метро или трамвай) с геометрией трассы.
struct Line: Codable, Identifiable, Hashable {
    let line: String
    let type: String
    let color: String
    let text: String
    let name: String
    let shapes: [[[Double]]]   // массив полилиний: [[lat,lon], …]

    var id: String { line }

    var polylines: [[CLLocationCoordinate2D]] {
        shapes.map { pts in pts.map { .init(latitude: $0[0], longitude: $0[1]) } }
    }
    var isMetro: Bool { type == "metro" }
}

extension Color {
    /// Цвет из строки "#RRGGBB".
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
