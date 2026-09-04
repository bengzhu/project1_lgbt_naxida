import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

private final class AdBlockStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responsePhase = 0
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func useNotModifiedResponse() {
        lock.lock()
        responsePhase = 1
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let phase = Self.responsePhase
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response: HTTPURLResponse
        let data: Data
        let hasConditionalETag = request.value(forHTTPHeaderField: "If-None-Match") != nil
        if phase == 0 || !hasConditionalETag {
            response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain; charset=utf-8",
                    "ETag": "\"rules-v1\"",
                    "Last-Modified": "Fri, 04 Sep 2026 00:00:00 GMT"
                ]
            )!
            data = Data("||ads.example^$third-party".utf8)
        } else {
            response = HTTPURLResponse(
                url: url,
                statusCode: 304,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            data = Data()
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
private struct AdBlockRuleRepositorySmoke {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aitrans-adblock-repository-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdBlockStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let source = AdBlockRuleSource(
            id: "test-source",
            name: "Test Source",
            urlString: "https://rules.example/filter.txt",
            format: .adGuard,
            license: "test fixture",
            isRequired: false,
            maximumResponseBytes: 1_024,
            maximumNetworkRules: 10,
            maximumCosmeticRules: 10
        )
        let repository = AdBlockRuleRepository(
            sources: [source],
            directory: directory,
            session: session,
            refreshInterval: 12 * 60 * 60
        )

        let first = try await repository.refresh(force: true)
        require(first.snapshots.count == 1, "initial 200 response was not cached")
        require(first.snapshots[0].cameFromCache == false, "fresh response mislabeled as cache")
        require(first.statuses[0].etag == "\"rules-v1\"", "ETag was not persisted")

        AdBlockStubURLProtocol.useNotModifiedResponse()
        let second = try await repository.refresh(force: true)
        require(second.snapshots.count == 1, "304 response did not reuse cached rules")
        require(second.snapshots[0].cameFromCache, "304 snapshot was not marked cached")
        require(second.statuses[0].cameFromCache, "304 status was not marked cached")
        let requests = AdBlockStubURLProtocol.recordedRequests()
        require(requests.count == 2, "expected exactly two requests")
        require(requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"rules-v1\"", "conditional ETag header missing")
        require(requests[1].value(forHTTPHeaderField: "If-Modified-Since") != nil, "conditional date header missing")

        try Data("corrupt".utf8).write(to: directory.appending(path: "test-source.txt"), options: .atomic)
        let repaired = try await repository.refresh(force: false)
        require(repaired.snapshots.count == 1, "corrupt cache did not trigger a repair fetch")
        require(!repaired.snapshots[0].cameFromCache, "repair fetch was mislabeled as cache")
        let repairedRequests = AdBlockStubURLProtocol.recordedRequests()
        require(repairedRequests.count == 3, "corrupt cache should bypass the refresh interval")
        require(repairedRequests[2].value(forHTTPHeaderField: "If-None-Match") == nil, "corrupt cache must not send a stale ETag")

        try await repository.clearCache()
        let cleared = try await repository.loadCached()
        require(cleared.snapshots.isEmpty, "cache clear left a readable snapshot")
        print("AdBlock rule repository smoke passed: 200 cache, ETag 304 reuse, corruption repair, clear")
    }
}
