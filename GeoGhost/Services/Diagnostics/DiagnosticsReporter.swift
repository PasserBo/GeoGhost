import Foundation
import MetricKit
import Observation
import SwiftData
import os

/// Whether the user agreed to share crash and error reports. Asked once (RootView), changeable in Settings.
enum DiagnosticsConsent: String, Sendable {
    case undecided, granted, declined

    static let key = "diagnosticsConsent"
    /// Readable from any thread (UserDefaults is thread-safe), for the reporters below.
    static var current: DiagnosticsConsent {
        UserDefaults.standard.string(forKey: key).flatMap(DiagnosticsConsent.init) ?? .undecided
    }
}

/// Collects crashes, hangs and other diagnostics from MetricKit and errors the app handled on its own.
/// Until the user decides they are only queued; if the user declines they are deleted.
@Observable
@MainActor
final class DiagnosticsReporter {
    private static let launchesKey = "launchCount"

    var consent: DiagnosticsConsent = DiagnosticsConsent.current {
        didSet {
            guard consent != oldValue else { return }
            UserDefaults.standard.set(consent.rawValue, forKey: DiagnosticsConsent.key)
            Task {
                if consent == .declined { await ReportQueue.shared.purgeDiagnostics() }
                await ReportQueue.shared.flush()
            }
        }
    }
    private(set) var hasPendingDiagnostics = false
    private var launches = UserDefaults.standard.integer(forKey: launchesKey)
    private let subscriber = MetricKitSubscriber()

    /// Not on the very first launch, which is for trying the app; but right away if a report is
    /// already waiting (something crashed), since that is when sharing it helps most.
    var shouldAskForConsent: Bool { consent == .undecided && (launches >= 2 || hasPendingDiagnostics) }

    func start() async {
        launches += 1
        UserDefaults.standard.set(launches, forKey: Self.launchesKey)
        MXMetricManager.shared.add(subscriber)
        hasPendingDiagnostics = await ReportQueue.shared.hasPendingDiagnostics
        await ReportQueue.shared.flush()
    }
}

enum Diagnostics {
    private static let log = Logger(subsystem: "com.passerbo.geoghost", category: "Diagnostics")

    /// Records an error the app handled without bothering the user, for the developer to fix.
    /// Sends no message text: SwiftData validation errors can quote the user's own notes.
    static func record(_ error: any Error, context: String, file: String = #fileID, line: Int = #line) {
        let ns = error as NSError
        log.error("\(context, privacy: .public): \(ns.domain, privacy: .public) \(ns.code) at \(file, privacy: .public):\(line)")
        guard DiagnosticsConsent.current != .declined else { return }
        let payload: [String: Any] = [
            "context": context, "domain": ns.domain, "code": ns.code,
            "type": String(reflecting: type(of: error)), "file": file, "line": line,
        ]
        guard let report = Report.make(.error, payload: payload) else { return }
        let signature = "\(context)|\(ns.domain)|\(ns.code)|\(file)|\(line)"
        Task {
            await ReportQueue.shared.enqueueError(report, signature: signature)
            await ReportQueue.shared.flush()
        }
    }
}

extension ModelContext {
    /// Saves, recording a failure instead of silently dropping it.
    func saveReportingErrors(_ context: String, file: String = #fileID, line: Int = #line) {
        do { try save() } catch { Diagnostics.record(error, context: context, file: file, line: line) }
    }
}

/// MetricKit delivers diagnostics (with call stacks) on the next launch after a crash or hang.
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard DiagnosticsConsent.current != .declined else { return }
        var reports: [Report] = []
        for payload in payloads {
            let groups: [(ReportKind, String, [MXDiagnostic])] = [
                (.crash, "crash", payload.crashDiagnostics ?? []),
                (.hang, "hang", payload.hangDiagnostics ?? []),
                (.diagnostic, "cpuException", payload.cpuExceptionDiagnostics ?? []),
                (.diagnostic, "diskWriteException", payload.diskWriteExceptionDiagnostics ?? []),
                (.diagnostic, "appLaunch", payload.appLaunchDiagnostics ?? []),
            ]
            for (kind, type, diagnostics) in groups {
                for diagnostic in diagnostics {
                    guard let json = try? JSONSerialization.jsonObject(with: diagnostic.jsonRepresentation()),
                          let report = Report.make(kind, payload: ["type": type, "diagnostic": json]) else { continue }
                    reports.append(report)
                }
            }
        }
        guard !reports.isEmpty else { return }
        Task {
            for report in reports { await ReportQueue.shared.enqueue(report) }
            await ReportQueue.shared.flush()
        }
    }
}
