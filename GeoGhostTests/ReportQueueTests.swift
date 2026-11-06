import XCTest
@testable import GeoGhost

final class ReportQueueTests: XCTestCase {
    /// Answers every request with `status` and records the JSON bodies it was sent.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 204
        nonisolated(unsafe) static var received: [[String: Any]] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            // URLSession hands the body to protocols as a stream.
            let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { Self.received.append(json) }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            return data
        }
    }

    private var directory: URL!

    override func setUp() {
        StubProtocol.status = 204
        StubProtocol.received = []
        directory = FileManager.default.temporaryDirectory.appending(path: "ReportQueueTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeQueue(sharing: Bool) -> ReportQueue {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ReportQueue(directory: directory, session: URLSession(configuration: config), sharingAllowed: { sharing })
    }

    private func queuedCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).count
    }

    /// Mirrors the endpoint's validation (worker/src/index.js `validate`).
    func testReportMatchesEndpointSchema() throws {
        let report = try XCTUnwrap(Report.make(.feedback, payload: ["message": "hi"], screenshot: Data([0xFF, 0xD8, 0xFF])))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: report.json) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "feedback")
        XCTAssertEqual(json["env"] as? String, "debug")
        XCTAssertNotNil((json["id"] as? String)?.range(of: "^[A-Za-z0-9-]{8,64}$", options: .regularExpression))
        let app = try XCTUnwrap(json["app"] as? [String: String])
        XCTAssertFalse(try XCTUnwrap(app["version"]).isEmpty)
        XCTAssertFalse(try XCTUnwrap(app["build"]).isEmpty)
        let device = try XCTUnwrap(json["device"] as? [String: String])
        XCTAssertFalse(try XCTUnwrap(device["model"]).isEmpty)
        XCTAssertTrue(try XCTUnwrap(device["os"]).hasPrefix("iOS "))
        XCTAssertFalse(try XCTUnwrap(device["locale"]).isEmpty)
        XCTAssertEqual((json["payload"] as? [String: String])?["message"], "hi")
        XCTAssertTrue(try XCTUnwrap(json["screenshot"] as? String).hasPrefix("/9j/"))
    }

    func testWithoutSharingOnlyFeedbackLeavesTheDevice() async throws {
        let queue = makeQueue(sharing: false)
        let error = try XCTUnwrap(Report.make(.error, payload: ["context": "test"]))
        let feedback = try XCTUnwrap(Report.make(.feedback, payload: ["message": "hi"]))
        await queue.enqueue(error)
        await queue.enqueue(feedback)
        await queue.flush()

        XCTAssertEqual(StubProtocol.received.compactMap { $0["kind"] as? String }, ["feedback"])
        let errorQueued = await queue.isQueued(id: error.id)
        XCTAssertTrue(errorQueued)
        await queue.purgeDiagnostics()
        let pending = await queue.hasPendingDiagnostics
        XCTAssertFalse(pending)
        XCTAssertEqual(queuedCount(), 0)
    }

    func testTemporaryFailureKeepsTheReportAndRejectionDropsIt() async throws {
        let queue = makeQueue(sharing: true)
        let report = try XCTUnwrap(Report.make(.crash, payload: ["type": "crash"]))
        await queue.enqueue(report)

        StubProtocol.status = 503
        await queue.flush()
        var queued = await queue.isQueued(id: report.id)
        XCTAssertTrue(queued)

        StubProtocol.status = 400
        await queue.flush()
        queued = await queue.isQueued(id: report.id)
        XCTAssertFalse(queued)
        XCTAssertEqual(StubProtocol.received.count, 2)
    }

    func testTheSameErrorIsQueuedOncePerLaunch() async throws {
        let queue = makeQueue(sharing: false)
        for _ in 0..<3 {
            await queue.enqueueError(try XCTUnwrap(Report.make(.error, payload: [:])), signature: "save|X|1")
        }
        await queue.enqueueError(try XCTUnwrap(Report.make(.error, payload: [:])), signature: "save|X|2")
        XCTAssertEqual(queuedCount(), 2)
    }
}
