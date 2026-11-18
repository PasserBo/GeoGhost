import SwiftUI

extension AppServices {
    /// The one instance the running app uses: `GeoGhostApp` puts it in the environment, and
    /// `@Services` falls back to it.
    static let live = AppServices()
}

/// Reads `AppServices` from the environment — use this instead of `@Environment(AppServices.self)`,
/// which traps when the object is not there.
///
/// It is not always there. On iOS 26.5 SwiftUI sizes a pushed screen's toolbar buttons while the
/// screen is still being attached to the window, and builds the screen for that with an environment
/// that has not received `AppServices` yet (TestFlight crashes on builds 22 and 64, when opening a
/// piece). The screen is built again once the environment arrives, so for that moment this hands
/// out the app's own instance — the same object the environment is about to deliver.
@propertyWrapper
struct Services: DynamicProperty {
    @Environment(AppServices.self) private var injected: AppServices?

    @MainActor var wrappedValue: AppServices { injected ?? .live }
}
