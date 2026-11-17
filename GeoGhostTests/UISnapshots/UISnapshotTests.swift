import SnapshotTesting
import SwiftUI
import XCTest
@testable import GeoGhost

/// Renders every state that ui/screen.yaml snapshots and compares it with ui/snapshots/.
/// Record and verify through scripts/ui-snapshots.sh, which runs each language in turn; see ui/README.md.
@MainActor
final class UISnapshotTests: XCTestCase {
    private var spec: UISpec!
    private var previousTimeZone: TimeZone!

    override func setUp() async throws {
        spec = try UISpec.load()
        // Dates are formatted in the process time zone; pin it so they read the same anywhere.
        previousTimeZone = NSTimeZone.default
        NSTimeZone.default = UIFixtures.timeZone
        UIOnlineFixture.install()
    }

    override func tearDown() async throws {
        NSTimeZone.default = previousTimeZone
        UIOnlineFixture.uninstall()
        ScreenCatalog.reset()
    }

    // MARK: - screen.yaml, event.yaml and the catalog agree

    func testEverySnapshottedStateHasACatalogEntry() {
        let declared = spec.snapshottedKeys
        let built = Set(ScreenCatalog.entries.keys)
        XCTAssertEqual(declared.subtracting(built).sorted(), [], "In ui/screen.yaml but not in ScreenCatalog")
        XCTAssertEqual(built.subtracting(declared).sorted(), [], "In ScreenCatalog but not snapshotted in ui/screen.yaml")
    }

    func testScreenSpecIsWellFormed() {
        let kinds: Set = ["screen", "sheet", "component"]
        for (id, screen) in spec.screens {
            XCTAssertTrue(isSnakeCase(id), "Screen name \(id) is not snake_case")
            XCTAssertTrue(kinds.contains(screen.kind), "\(id): unknown kind \(screen.kind)")
            XCTAssertNotNil(screen.states[screen.default], "\(id): default state \(screen.default) is not one of its states")
            for region in screen.unstable ?? [] { XCTAssertFalse(region.reason.isEmpty, "\(id): unstable region without a reason") }
            for (name, state) in screen.states {
                XCTAssertTrue(isSnakeCase(name), "State name \(id).\(name) is not snake_case")
                if state.isSnapshotted {
                    XCTAssertTrue(UIFixtures.names.contains(state.fixture ?? ""), "\(id).\(name): unknown fixture \(state.fixture ?? "(none)")")
                } else {
                    XCTAssertFalse((state.reason ?? "").isEmpty, "\(id).\(name): snapshot is off without a reason")
                }
            }
        }
        XCTAssertTrue(spec.matrix.locales.contains(spec.matrix.primaryLocale))
        for locale in spec.matrix.locales { XCTAssertNotNil(spec.matrix.regions[locale], "No region for \(locale)") }
    }

    func testEventsReferToKnownScreens() throws {
        let events = try UISpec.loadEvents()
        let types: Set = ["string", "int", "bool"]
        for (name, event) in events.events {
            XCTAssertTrue(isSnakeCase(name), "Event name \(name) is not snake_case")
            if let screen = event.screen { XCTAssertNotNil(spec.screens[screen], "\(name): unknown screen \(screen)") }
            for (property, type) in event.properties ?? [:] {
                XCTAssertTrue(isSnakeCase(property), "\(name).\(property) is not snake_case")
                XCTAssertTrue(types.contains(type), "\(name).\(property): unknown type \(type)")
            }
        }
    }

    /// ui/snapshots/ holds exactly the images screen.yaml asks for: none missing, none left over
    /// from a state that was renamed or removed.
    func testSnapshotFolderMatchesTheSpec() throws {
        let expected = Set(spec.allCases.map(\.fileName))
        let found = Set(try FileManager.default.contentsOfDirectory(atPath: UISpec.snapshotDirectory.path).filter { $0.hasSuffix(".png") })
        XCTAssertEqual(found.subtracting(expected).sorted(), [], "Left over in ui/snapshots; delete them")
        XCTAssertEqual(expected.subtracting(found).sorted(), [], "Not recorded yet; run scripts/ui-snapshots.sh record")
    }

    // MARK: - The images

    func testSnapshots() async throws {
        let device = spec.matrix.device
        let simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(simulator == device.name, "UI snapshots are recorded on \(device.name); this is \(simulator)")
        let locale = Bundle.main.preferredLocalizations.first ?? ""
        try XCTSkipUnless(spec.matrix.locales.contains(locale), "UI snapshots are not recorded in \(locale)")
        // A plain test run uses the simulator's own region; scripts/ui-snapshots.sh sets the recorded one.
        let region = Locale.current.region?.identifier ?? ""
        try XCTSkipUnless(region == spec.matrix.regions[locale], "UI snapshots in \(locale) are recorded in region \(spec.matrix.regions[locale] ?? "?"); this is \(region). Use scripts/ui-snapshots.sh")

        var fixtures: [UIFixture] = []
        defer { withExtendedLifetime(fixtures) {} }
        // UI_SNAPSHOT_FILTER=map. limits a run to the screens whose `screen.state` starts with it.
        let filter = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FILTER"] ?? ""
        for snapshot in spec.cases(locale: locale) where snapshot.key.hasPrefix(filter) {
            guard let state = spec.screens[snapshot.screen]?.states[snapshot.state], let fixtureName = state.fixture else { continue }
            let fixture = try UIFixtures.make(fixtureName)
            // A screen's tasks can outlive its window; their data has to as well.
            fixtures.append(fixture)
            guard let view = await ScreenCatalog.host(snapshot.key, fixture: fixture) else {
                XCTFail("\(snapshot.key) has no entry in ScreenCatalog")
                continue
            }
            let image = await render(view, dark: snapshot.appearance == "dark",
                                     size: CGSize(width: device.width, height: device.height), scale: device.scale)
            let reference = UISpec.snapshotDirectory.appending(path: snapshot.fileName)
            let ignored = (spec.screens[snapshot.screen]?.unstable ?? []).map { $0.pixels(scale: device.scale) }
            if !isRecording, let expected = UIImage(contentsOfFile: reference.path),
               PixelComparison.looksTheSame(image, expected, ignoring: ignored) { continue }
            // Differs, missing or recording: the library writes the image, or reports the difference.
            let failure = verifySnapshot(of: image, as: .image, named: snapshot.variant,
                                         snapshotDirectory: UISpec.snapshotDirectory.path, testName: snapshot.screen)
            if let failure { XCTFail("\(snapshot.fileName): \(failure)") }
        }
    }

    /// Puts the screen in a window of its own, as the root, the way the app shows it; rendering
    /// off screen leaves out system bars and materials.
    private func render(_ view: AnyView, dark: Bool, size: CGSize, scale: Double) async -> UIImage {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("The test host has no window scene")
            return UIImage()
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = UIHostingController(rootView: view)
        // Key, like the app's window: system bars draw themselves differently in a window that isn't.
        window.makeKeyAndVisible()
        // Images are kept at the scale ui/screen.yaml asks for, not the simulator's, to keep them small.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        // Plain sRGB, 8 bits a channel: the default follows the display and writes files several times the size.
        format.preferredRange = .standard
        func draw() -> UIImage {
            // No blinking text cursor in the image.
            window.endEditing(true)
            return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        try? await Task.sleep(for: .milliseconds(400))
        var image = draw()
        // System materials keep adjusting for a moment after a screen appears (the search bar's
        // placeholder, for one); take the image once two renders in a row agree.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(250))
            let next = draw()
            let settled = PixelComparison.looksTheSame(image, next)
            image = next
            if settled { break }
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    private var isRecording: Bool { ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil }

    private func isSnakeCase(_ text: String) -> Bool {
        text.range(of: "^[a-z][a-z0-9]*(_[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}

/// Two renders of the same screen are not identical to the last bit: translucent system materials
/// (the search bar, navigation bar buttons) come out a level or two different each time. So a
/// pixel counts as changed only when a channel moved by more than `channelTolerance`, and the image
/// as changed when more than `pixelAllowance` pixels did — small enough that a recoloured icon fails.
enum PixelComparison {
    static let channelTolerance = 6
    static let pixelAllowance = 20

    /// `ignoring`: rectangles in pixels that are left out (ui/screen.yaml `unstable`).
    static func looksTheSame(_ a: UIImage, _ b: UIImage, ignoring: [CGRect] = []) -> Bool {
        guard let a = a.cgImage, let b = b.cgImage, a.width == b.width, a.height == b.height,
              let pixelsA = pixels(a, blanking: ignoring), let pixelsB = pixels(b, blanking: ignoring) else { return false }
        if pixelsA == pixelsB { return true }
        var changed = 0
        return pixelsA.withUnsafeBufferPointer { pa in
            pixelsB.withUnsafeBufferPointer { pb in
                for i in 0..<pa.count where abs(Int(pa[i]) - Int(pb[i])) > channelTolerance {
                    changed += 1
                    // Up to four channels per pixel.
                    if changed > pixelAllowance * 4 { return false }
                }
                return true
            }
        }
    }

    private static func pixels(_ image: CGImage, blanking: [CGRect]) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // The context's origin is bottom-left; the regions are measured from the top.
            context.setFillColor(gray: 0, alpha: 1)
            for rect in blanking {
                context.fill(CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height))
            }
            return true
        }
        return drawn ? buffer : nil
    }
}
