import SwiftData
import SwiftUI
import XCTest
@testable import GeoGhost

/// A screen that reads `AppServices` must survive being built before the environment reaches it.
/// On iOS 26.5 SwiftUI sizes a pushed screen's toolbar buttons while the screen is still being
/// attached, and builds the screen for that with an environment that has no `AppServices` yet;
/// `@Environment(AppServices.self)` trapped there (TestFlight crashes on builds 22 and 64).
@MainActor
final class ServicesEnvironmentTests: XCTestCase {
    /// The crash site: the detail screen pushed on a navigation stack, with nothing injected.
    func testArtworkDetailBuildsWithoutInjectedServices() throws {
        let fixture = try UIFixtures.make("typical")
        show(NavigationStack { ArtworkDetailView(artwork: fixture.artwork("ghost-1")) }.modelContainer(fixture.container))
    }

    func testServicesFallBackToTheAppsInstance() {
        let seen = Seen()
        show(Probe(seen: seen))
        XCTAssertTrue(seen.services === AppServices.live)
    }

    func testInjectedServicesAreUsedWhenPresent() {
        let seen = Seen(), injected = AppServices(onlineState: nil)
        show(Probe(seen: seen).environment(injected))
        XCTAssertTrue(seen.services === injected)
    }

    private final class Seen { var services: AppServices? }

    private struct Probe: View {
        @Services private var services
        let seen: Seen
        var body: some View {
            let _ = (seen.services = services)
            Color.clear
        }
    }

    /// Puts the view in a window and lays it out, as the app does. A missing `AppServices` trapped here.
    private func show(_ view: some View) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.isHidden = true
    }
}
