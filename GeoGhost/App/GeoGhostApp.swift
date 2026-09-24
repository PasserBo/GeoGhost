import SwiftData
import SwiftUI

@main
struct GeoGhostApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()

    init() {
        do {
            container = try GeoGhostSchema.makeContainer()
        } catch {
            // A broken store is not recoverable at runtime; fall back to memory so the app still opens.
            container = try! GeoGhostSchema.makeContainer(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .tint(Theme.accent)
                .task { await services.pro.load() }
        }
        .modelContainer(container)
    }
}
