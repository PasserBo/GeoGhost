import SwiftData
import SwiftUI
import os

@main
struct GeoGhostApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()

    init() {
        do {
            container = try GeoGhostSchema.makeContainer()
        } catch {
            // A broken store is not recoverable at runtime; fall back to memory so the app still opens,
            // and tell the user (RootView) rather than letting them collect into a store that is never saved.
            Logger(subsystem: "com.passerbo.geoghost", category: "App").error("Store failed to open: \(error.localizedDescription, privacy: .public)")
            container = try! GeoGhostSchema.makeContainer(inMemory: true)
            let services = AppServices()
            services.isRunningWithoutStorage = true
            _services = State(initialValue: services)
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
