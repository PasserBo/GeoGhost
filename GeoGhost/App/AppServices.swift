import Foundation
import Observation

/// Long-lived services shared through the environment.
@Observable
@MainActor
final class AppServices {
    let location = LocationService()
    let camera = CameraService()
    let pro = ProStore()
}
