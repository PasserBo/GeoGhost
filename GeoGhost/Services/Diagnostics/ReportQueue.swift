import Foundation

/// What a report is about. Feedback is sent because the user pressed Send; everything else is
/// diagnostics and only leaves the device if the user agreed to share reports.
enum ReportKind: String, Sendable {
    case crash, hang, diagnostic, error, feedback
    var isDiagnostic: Bool { self != .feedback }
}

/// One report for the GeoGhost report endpoint (`POST /v1/reports`). Plain JSON, so MetricKit's own
/// JSON passes through untouched. Never contains photos, cutouts, locations or notes.
struct Report: Sendable {
    let id: String
    let kind: ReportKind
    let json: Data

    static func make(_ kind: ReportKind, payload: [String: Any], screenshot: Data? = nil) -> Report? {
        let id = UUID().uuidString
        var body: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "env": environment,
            "app": ["version": Bundle.main.shortVersion, "build": Bundle.main.buildNumber],
            "device": ["model": deviceModel, "os": osVersion, "locale": Locale.current.identifier],
            "payload": payload,
        ]
        if let screenshot { body["screenshot"] = screenshot.base64EncodedString() }
        guard JSONSerialization.isValidJSONObject(body),
              let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return Report(id: id, kind: kind, json: json)
    }

    /// Debug builds are archived separately on the receiving end and never triaged.
    private static let environment: String = {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }()

    /// Hardware identifier such as "iPhone15,4" (the simulator reports the simulated model).
    static let deviceModel: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
}

/// Reports wait on disk until they are uploaded, so nothing is lost offline or across a crash.
/// Diagnostics are only uploaded while sharing is on; feedback always is.
actor ReportQueue {
    static let shared = ReportQueue()
    static let endpoint = URL(string: "https://geoghost-testflight-feedback.passerbo.workers.dev/v1/reports")!
    private static let maxQueued = 50
    /// Errors are capped per launch: one bad loop must not fill the queue.
    private static let maxErrorsPerLaunch = 10

    private let directory: URL
    private let session: URLSession
    private let sharingAllowed: @Sendable () -> Bool
    private var isFlushing = false
    private var errorSignaturesThisLaunch: Set<String> = []

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Reports", directoryHint: .isDirectory),
         session: URLSession = .shared,
         sharingAllowed: @escaping @Sendable () -> Bool = { DiagnosticsConsent.current == .granted }) {
        self.directory = directory
        self.session = session
        self.sharingAllowed = sharingAllowed
    }

    func enqueue(_ report: Report) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Millisecond prefix keeps files in arrival order.
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(report.kind.rawValue)-\(report.id).json"
        try? report.json.write(to: directory.appending(path: name), options: .atomic)
        trim()
    }

    /// Queues an error once per launch per place it was recorded.
    func enqueueError(_ report: Report, signature: String) {
        guard errorSignaturesThisLaunch.count < Self.maxErrorsPerLaunch,
              errorSignaturesThisLaunch.insert(signature).inserted else { return }
        enqueue(report)
    }

    /// Uploads what is allowed, oldest first. Stops at the first failure that may be temporary
    /// (offline, rate limited, server error) and keeps the rest for the next flush.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        let includeDiagnostics = sharingAllowed()
        for file in queuedFiles() where includeDiagnostics || kind(of: file) == .feedback {
            guard let data = try? Data(contentsOf: file) else { continue }
            var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            guard let (_, response) = try? await session.data(for: request) else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 || status >= 500 || status == 0 { return }
            // 2xx: delivered. Other 4xx: the server will never accept it, so don't retry forever.
            try? FileManager.default.removeItem(at: file)
        }
    }

    func isQueued(id: String) -> Bool {
        queuedFiles().contains { $0.lastPathComponent.hasSuffix("-\(id).json") }
    }

    var hasPendingDiagnostics: Bool {
        queuedFiles().contains { kind(of: $0)?.isDiagnostic == true }
    }

    /// Sharing was turned off: diagnostics collected so far never leave the device.
    func purgeDiagnostics() {
        for file in queuedFiles() where kind(of: file)?.isDiagnostic == true {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func queuedFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func kind(of file: URL) -> ReportKind? {
        let parts = file.lastPathComponent.split(separator: "-", maxSplits: 2)
        return parts.count > 1 ? ReportKind(rawValue: String(parts[1])) : nil
    }

    /// Over the cap, drop the oldest diagnostics; feedback someone wrote is kept.
    private func trim() {
        let files = queuedFiles()
        guard files.count > Self.maxQueued else { return }
        for file in files.filter({ kind(of: $0)?.isDiagnostic == true }).prefix(files.count - Self.maxQueued) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}
