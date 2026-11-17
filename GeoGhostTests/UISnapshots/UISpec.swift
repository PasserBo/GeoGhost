import Foundation
import Yams

/// ui/screen.yaml and ui/event.yaml, as the tests read them.
struct UISpec: Decodable {
    struct Matrix: Decodable {
        struct Device: Decodable { let name: String; let width: Double; let height: Double; let scale: Double }
        let device: Device
        let primaryLocale: String
        let locales: [String]
        /// The region each language is recorded in; it decides how dates and numbers are written.
        let regions: [String: String]
        let appearances: [String]

        enum CodingKeys: String, CodingKey { case device, locales, regions, appearances, primaryLocale = "primary_locale" }
    }

    struct Screen: Decodable {
        let title: String
        let kind: String
        let spec: String?
        let `default`: String
        let unstable: [Region]?
        let states: [String: State]
    }

    /// A part of the screen left out of the comparison, in points.
    struct Region: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let reason: String

        func pixels(scale: Double) -> CGRect {
            CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
        }
    }

    struct State: Decodable {
        let title: String
        let fixture: String?
        let snapshot: Bool?
        let reason: String?

        var isSnapshotted: Bool { snapshot ?? true }
    }

    let matrix: Matrix
    let screens: [String: Screen]
}

struct UIEventSpec: Decodable {
    struct Event: Decodable {
        let title: String
        let screen: String?
        let properties: [String: String]?
    }

    let status: String
    let events: [String: Event]
}

/// ui/translations.yaml: the gallery's words in one other language.
struct UITranslation: Decodable {
    struct Screen: Decodable {
        let title: String
        let states: [String: String]
    }

    let screens: [String: Screen]
    let events: [String: String]
    /// Keyed by the original Chinese text.
    let reasons: [String: String]
}

/// One image: a state of a screen in one appearance and language.
struct UISnapshotCase: Hashable {
    let screen: String
    let state: String
    let appearance: String
    let locale: String

    /// `<screen>.<state>-<appearance>-<locale>.png`; scripts/build-ui-gallery.rb builds the same name.
    var fileName: String { "\(screen).\(variant).png" }
    var variant: String { "\(state)-\(appearance)-\(locale)" }
    var key: String { "\(screen).\(state)" }
}

extension UISpec {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "ui", directoryHint: .isDirectory)
    static let snapshotDirectory = directory.appending(path: "snapshots", directoryHint: .isDirectory)

    static func load() throws -> UISpec {
        try YAMLDecoder().decode(UISpec.self, from: Data(contentsOf: directory.appending(path: "screen.yaml")))
    }

    static func loadTranslations() throws -> [String: UITranslation] {
        try YAMLDecoder().decode([String: UITranslation].self, from: Data(contentsOf: directory.appending(path: "translations.yaml")))
    }

    static func loadEvents() throws -> UIEventSpec {
        try YAMLDecoder().decode(UIEventSpec.self, from: Data(contentsOf: directory.appending(path: "event.yaml")))
    }

    /// `screen.state` of every state that gets a snapshot.
    var snapshottedKeys: Set<String> {
        var keys = Set<String>()
        for (id, screen) in screens {
            for (name, state) in screen.states where state.isSnapshotted { keys.insert("\(id).\(name)") }
        }
        return keys
    }

    /// The primary language gets every state in every appearance; the others get the default state
    /// in the first appearance, which is enough to catch text that doesn't fit.
    func cases(locale: String) -> [UISnapshotCase] {
        var result: [UISnapshotCase] = []
        for (id, screen) in screens.sorted(by: { $0.key < $1.key }) {
            for (name, state) in screen.states.sorted(by: { $0.key < $1.key }) where state.isSnapshotted {
                if locale == matrix.primaryLocale {
                    for appearance in matrix.appearances {
                        result.append(UISnapshotCase(screen: id, state: name, appearance: appearance, locale: locale))
                    }
                } else if name == screen.default, let appearance = matrix.appearances.first {
                    result.append(UISnapshotCase(screen: id, state: name, appearance: appearance, locale: locale))
                }
            }
        }
        return result
    }

    var allCases: [UISnapshotCase] { matrix.locales.flatMap { cases(locale: $0) } }
}
