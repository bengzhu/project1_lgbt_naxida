import CryptoKit
import Foundation

struct AdBlockRepositoryResult: Sendable {
    let snapshots: [AdBlockRuleSnapshot]
    let statuses: [AdBlockSourceStatus]
    let checkedAt: Date
}

actor AdBlockRuleRepository {
    private struct CacheEntry: Codable, Sendable {
        var sourceID: String
        var filename: String
        var etag: String?
        var lastModified: String?
        var fetchedAt: Date
        var lastCheckedAt: Date
        var contentSHA256: String
    }

    private struct CacheManifest: Codable, Sendable {
        static let schemaVersion = 1

        var schemaVersion: Int
        var entries: [String: CacheEntry]

        static let empty = Self(schemaVersion: schemaVersion, entries: [:])
    }

    private struct FetchResult: Sendable {
        let source: AdBlockRuleSource
        let statusCode: Int?
        let data: Data?
        let etag: String?
        let lastModified: String?
        let errorMessage: String?
    }

    private let sources: [AdBlockRuleSource]
    private let directory: URL
    private let session: URLSession
    private let refreshInterval: TimeInterval
    private let fileManager: FileManager

    init(
        sources: [AdBlockRuleSource] = AdBlockRuleSource.recommended,
        directory: URL = URL.applicationSupportDirectory
            .appending(path: "AITRANS")
            .appending(path: "AdBlockRules"),
        session: URLSession = .shared,
        refreshInterval: TimeInterval = 12 * 60 * 60,
        fileManager: FileManager = .default
    ) {
        self.sources = sources
        self.directory = directory
        self.session = session
        self.refreshInterval = refreshInterval
        self.fileManager = fileManager
    }

    func loadCached() throws -> AdBlockRepositoryResult {
        try ensureDirectory()
        let manifest = try loadManifest()
        let loaded = loadSnapshots(
            from: manifest,
            cachedSourceIDs: Set(manifest.entries.keys)
        )
        return AdBlockRepositoryResult(
            snapshots: loaded.snapshots,
            statuses: loaded.statuses,
            checkedAt: manifest.entries.values.map(\.lastCheckedAt).max() ?? .distantPast
        )
    }

    func refresh(force: Bool) async throws -> AdBlockRepositoryResult {
        try ensureDirectory()
        var manifest = try loadManifest()
        let now = Date.now
        if !force,
           !manifest.entries.isEmpty,
           manifest.entries.values.allSatisfy({ now.timeIntervalSince($0.lastCheckedAt) < refreshInterval }) {
            let loaded = loadSnapshots(
                from: manifest,
                cachedSourceIDs: Set(manifest.entries.keys)
            )
            if loaded.snapshots.count == manifest.entries.count {
                return AdBlockRepositoryResult(
                    snapshots: loaded.snapshots,
                    statuses: loaded.statuses,
                    checkedAt: now
                )
            }
        }

        let validCacheIDs = Set(
            loadSnapshots(
                from: manifest,
                cachedSourceIDs: Set(manifest.entries.keys)
            ).snapshots.map(\.source.id)
        )
        manifest.entries = manifest.entries.filter { validCacheIDs.contains($0.key) }
        let cachedEntries = manifest.entries
        let session = session
        let results = await withTaskGroup(of: FetchResult.self) { group in
            for source in sources {
                let cachedEntry = cachedEntries[source.id]
                group.addTask {
                    guard let url = source.url else {
                        return FetchResult(
                            source: source,
                            statusCode: nil,
                            data: nil,
                            etag: nil,
                            lastModified: nil,
                            errorMessage: AdBlockError.invalidSource(source.name).localizedDescription
                        )
                    }
                    var request = URLRequest(
                        url: url,
                        cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                        timeoutInterval: 18
                    )
                    request.setValue("text/plain, */*;q=0.1", forHTTPHeaderField: "Accept")
                    request.setValue("AITRANS-iOS/AdBlockRules", forHTTPHeaderField: "User-Agent")
                    if let etag = cachedEntry?.etag {
                        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
                    }
                    if let lastModified = cachedEntry?.lastModified {
                        request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                    }
                    do {
                        let (data, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            return FetchResult(
                                source: source,
                                statusCode: nil,
                                data: nil,
                                etag: nil,
                                lastModified: nil,
                                errorMessage: AdBlockError.invalidResponse(source.name).localizedDescription
                            )
                        }
                        return FetchResult(
                            source: source,
                            statusCode: http.statusCode,
                            data: data,
                            etag: http.value(forHTTPHeaderField: "ETag"),
                            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                            errorMessage: nil
                        )
                    } catch is CancellationError {
                        return FetchResult(
                            source: source,
                            statusCode: nil,
                            data: nil,
                            etag: nil,
                            lastModified: nil,
                            errorMessage: "更新已取消"
                        )
                    } catch {
                        return FetchResult(
                            source: source,
                            statusCode: nil,
                            data: nil,
                            etag: nil,
                            lastModified: nil,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            var collected: [FetchResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        try Task.checkCancellation()

        var statusesByID: [String: AdBlockSourceStatus] = [:]
        for result in results {
            try Task.checkCancellation()
            let source = result.source
            let cachedEntry = manifest.entries[source.id]
            switch result.statusCode {
            case 304:
                if var entry = cachedEntry {
                    entry.lastCheckedAt = now
                    manifest.entries[source.id] = entry
                    statusesByID[source.id] = status(
                        for: source,
                        entry: entry,
                        cameFromCache: true,
                        message: "ETag 未变化，复用本地规则"
                    )
                } else {
                    statusesByID[source.id] = failedStatus(
                        for: source,
                        checkedAt: now,
                        message: "服务器返回未修改，但本地缓存不存在"
                    )
                }
            case 200:
                guard let data = result.data,
                      !data.isEmpty,
                      data.count <= source.maximumResponseBytes,
                      String(data: data, encoding: .utf8) != nil else {
                    statusesByID[source.id] = fallbackStatus(
                        for: source,
                        entry: cachedEntry,
                        checkedAt: now,
                        message: result.data.map { $0.count > source.maximumResponseBytes
                            ? AdBlockError.responseTooLarge(source.name).localizedDescription
                            : AdBlockError.invalidResponse(source.name).localizedDescription
                        } ?? AdBlockError.invalidResponse(source.name).localizedDescription
                    )
                    continue
                }
                let filename = "\(source.id).txt"
                let fileURL = directory.appending(path: filename)
                do {
                    try data.write(to: fileURL, options: .atomic)
                    let entry = CacheEntry(
                        sourceID: source.id,
                        filename: filename,
                        etag: result.etag,
                        lastModified: result.lastModified,
                        fetchedAt: now,
                        lastCheckedAt: now,
                        contentSHA256: Self.sha256Hex(data)
                    )
                    manifest.entries[source.id] = entry
                    statusesByID[source.id] = status(
                        for: source,
                        entry: entry,
                        cameFromCache: false,
                        message: "已下载新版本"
                    )
                } catch {
                    statusesByID[source.id] = fallbackStatus(
                        for: source,
                        entry: cachedEntry,
                        checkedAt: now,
                        message: AdBlockError.cacheFailure(error.localizedDescription).localizedDescription
                    )
                }
            default:
                let responseDescription = result.statusCode.map { "HTTP \($0)" }
                    ?? result.errorMessage
                    ?? "未知网络错误"
                statusesByID[source.id] = fallbackStatus(
                    for: source,
                    entry: cachedEntry,
                    checkedAt: now,
                    message: responseDescription
                )
            }
        }

        try saveManifest(manifest)
        let loaded = loadSnapshots(
            from: manifest,
            cachedSourceIDs: Set(
                statusesByID.values
                    .filter(\.cameFromCache)
                    .map(\.id)
            )
        )
        let statuses = sources.map { source in
            statusesByID[source.id]
                ?? loaded.statuses.first(where: { $0.id == source.id })
                ?? failedStatus(for: source, checkedAt: now, message: "规则源未返回结果")
        }
        return AdBlockRepositoryResult(
            snapshots: loaded.snapshots,
            statuses: statuses,
            checkedAt: now
        )
    }

    func clearCache() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for url in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            try fileManager.removeItem(at: url)
        }
    }

    private func loadSnapshots(
        from manifest: CacheManifest,
        cachedSourceIDs: Set<String>
    ) -> (snapshots: [AdBlockRuleSnapshot], statuses: [AdBlockSourceStatus]) {
        var snapshots: [AdBlockRuleSnapshot] = []
        var statuses: [AdBlockSourceStatus] = []
        for source in sources {
            guard let entry = manifest.entries[source.id] else { continue }
            let fileURL = directory.appending(path: entry.filename)
            guard let data = try? Data(contentsOf: fileURL),
                  data.count <= source.maximumResponseBytes,
                  Self.sha256Hex(data) == entry.contentSHA256,
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            snapshots.append(
                AdBlockRuleSnapshot(
                    source: source,
                    text: text,
                    etag: entry.etag,
                    lastModified: entry.lastModified,
                    fetchedAt: entry.fetchedAt,
                    contentSHA256: entry.contentSHA256,
                    cameFromCache: cachedSourceIDs.contains(source.id)
                )
            )
            statuses.append(
                status(
                    for: source,
                    entry: entry,
                    cameFromCache: cachedSourceIDs.contains(source.id),
                    message: "已载入本地缓存"
                )
            )
        }
        return (snapshots, statuses)
    }

    private func fallbackStatus(
        for source: AdBlockRuleSource,
        entry: CacheEntry?,
        checkedAt: Date,
        message: String
    ) -> AdBlockSourceStatus {
        if let entry {
            var cached = status(
                for: source,
                entry: entry,
                cameFromCache: true,
                message: "更新失败，继续使用缓存：\(message)"
            )
            cached.lastCheckedAt = checkedAt
            return cached
        }
        return failedStatus(for: source, checkedAt: checkedAt, message: message)
    }

    private func status(
        for source: AdBlockRuleSource,
        entry: CacheEntry,
        cameFromCache: Bool,
        message: String
    ) -> AdBlockSourceStatus {
        AdBlockSourceStatus(
            id: source.id,
            name: source.name,
            etag: entry.etag,
            contentSHA256: entry.contentSHA256,
            fetchedAt: entry.fetchedAt,
            lastCheckedAt: entry.lastCheckedAt,
            ruleCount: 0,
            cameFromCache: cameFromCache,
            message: message
        )
    }

    private func failedStatus(
        for source: AdBlockRuleSource,
        checkedAt: Date,
        message: String
    ) -> AdBlockSourceStatus {
        AdBlockSourceStatus(
            id: source.id,
            name: source.name,
            etag: nil,
            contentSHA256: nil,
            fetchedAt: nil,
            lastCheckedAt: checkedAt,
            ruleCount: 0,
            cameFromCache: false,
            message: message
        )
    }

    private func ensureDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            throw AdBlockError.cacheFailure(error.localizedDescription)
        }
    }

    private var manifestURL: URL { directory.appending(path: "manifest.json") }

    private func loadManifest() throws -> CacheManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(CacheManifest.self, from: data) else {
                // A cache index is disposable. Recover to a fresh manifest so
                // a malformed or older file cannot permanently block refresh.
                return .empty
            }
            guard manifest.schemaVersion == CacheManifest.schemaVersion else { return .empty }
            return manifest
        } catch {
            throw AdBlockError.cacheFailure(error.localizedDescription)
        }
    }

    private func saveManifest(_ manifest: CacheManifest) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            throw AdBlockError.cacheFailure(error.localizedDescription)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
