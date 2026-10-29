import SwiftUI

@main
struct MouApp: App {
    @StateObject private var store = TransitStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
