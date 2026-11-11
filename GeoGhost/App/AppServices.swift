import Foundation
import Observation

/// Long-lived services shared through the environment.
@Observable
@MainActor
final class AppServices {
    let location = LocationService()
    let camera = CameraService()
    let pro = ProStore()
    let diagnostics = DiagnosticsReporter()
    /// The online backend and the state its screens share, when this build has one configured;
    /// nil hides every online feature.
    let onlineState = OnlineConfig.current.map { OnlineState(services: OnlineServices(config: $0)) }
    var online: OnlineServices? { onlineState?.services }
    /// The on-disk store failed to open and the app is running on an in-memory store: nothing will persist.
    var isRunningWithoutStorage = false
}
