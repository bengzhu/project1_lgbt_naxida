import Foundation
import Observation
import WebKit

/// A bounded, metadata-only diagnostic recorder for the manga WKWebView.
///
/// The recorder is intentionally independent from `AdBlockStore` and
/// `TranslationSessionStore`. It observes only events emitted by the active
/// browser attachment and never receives request/response bodies.
@MainActor
@Observable
final class BrowserDebugLogStore {
    enum Intent {
        case start(tabID: UUID)
        case stop
        case clearAll
        case delete(UUID)
    }

    enum EntryKind: String, Codable, CaseIterable, Sendable {
        case resource
        case resourceError
        case domInsertion
        case media
        case navigation
        case popup
        case blockedNavigation
    }

    struct Entry: Identifiable, Codable, Equatable, Sendable {
        let id: UUID
        let timestamp: Date
        let kind: EntryKind
        let tabID: UUID
        let isMainFrame: Bool
        let url: String?
        let detail: [String: String]

        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            kind: EntryKind,
            tabID: UUID,
            isMainFrame: Bool,
            url: String?,
            detail: [String: String] = [:]
        ) {
            self.id = id
            self.timestamp = timestamp
            self.kind = kind
            self.tabID = tabID
            self.isMainFrame = isMainFrame
            self.url = url.map(Self.truncated)
            self.detail = detail.reduce(into: [:]) { result, pair in
                result[Self.truncated(pair.key)] = Self.truncated(pair.value)
            }
        }

        private static func truncated(_ value: String) -> String {
            let limit = 2_048
            guard value.count > limit else { return value }
            return String(value.prefix(limit)) + "…"
        }
    }

    struct Session: Identifiable, Codable, Equatable, Sendable {
        let id: UUID
        let tabID: UUID
        let startedAt: Date
        let endedAt: Date
        let entries: [Entry]

        var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    }

    private(set) var sessions: [Session] = []
    private(set) var currentEntries: [Entry] = []
    private(set) var isRecording = false
    private(set) var recordingTabID: UUID?
    private(set) var startedAt: Date?
    private(set) var message = "诊断录制未开始"
    private(set) var lastError: String?

    private let fileManager: FileManager
    private let storageURL: URL
    private var currentSessionID = UUID()

    private static let maximumEntries = 2_000
    private static let maximumSessions = 20
    private static let storageDirectoryName = "BrowserDebugLogs"
    private static let storageFileName = "sessions.json"
#if DEBUG
    private static let diagnosticsBuildEnabled = true
#else
    private static let diagnosticsBuildEnabled = false
#endif

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.storageURL = base
                .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
                .appendingPathComponent(Self.storageFileName)
        }
        load()
    }

    func send(_ intent: Intent) {
        switch intent {
        case let .start(tabID): start(tabID: tabID)
        case .stop: stop()
        case .clearAll: clearAll()
        case let .delete(id): delete(id: id)
        }
    }

    func recordScriptMessage(
        _ body: Any,
        tabID: UUID,
        isMainFrame: Bool
    ) {
        guard Self.diagnosticsBuildEnabled,
              isRecording, recordingTabID == tabID,
              let payload = body as? [String: Any],
              let rawKind = payload["kind"] as? String,
              let kind = EntryKind(rawValue: rawKind) else { return }

        let url = payload["url"] as? String ?? payload["src"] as? String
        let allowedDetailKeys: Set<String> = [
            "initiatorType", "duration", "transferSize", "encodedBodySize",
            "decodedBodySize", "tag", "width", "height", "reason", "event",
            "source", "frame", "isTrackingPixel"
        ]
        var detail: [String: String] = [:]
        for (key, value) in payload where allowedDetailKeys.contains(key) {
            if let value = value as? String {
                detail[key] = value
            } else if let value = value as? NSNumber {
                detail[key] = value.stringValue
            }
        }
        append(
            Entry(
                kind: kind,
                tabID: tabID,
                isMainFrame: isMainFrame,
                url: url,
                detail: detail
            )
        )
    }

    func recordNavigation(
        _ kind: EntryKind = .navigation,
        tabID: UUID,
        url: URL?,
        isMainFrame: Bool = true,
        detail: [String: String] = [:]
    ) {
        guard Self.diagnosticsBuildEnabled,
              kind == .navigation || kind == .popup || kind == .blockedNavigation else { return }
        append(
            Entry(
                kind: kind,
                tabID: tabID,
                isMainFrame: isMainFrame,
                url: url?.absoluteString,
                detail: detail
            )
        )
    }

    func exportData(for sessionID: UUID) -> Data? {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(session)
        } catch {
            lastError = "无法导出诊断日志：\(error.localizedDescription)"
            return nil
        }
    }

    private func start(tabID: UUID) {
        if isRecording { stop() }
        currentSessionID = UUID()
        currentEntries = []
        recordingTabID = tabID
        startedAt = Date()
        isRecording = true
        lastError = nil
        message = "正在录制当前漫画页的请求与 DOM 元数据"
    }

    private func stop() {
        guard isRecording, let tabID = recordingTabID, let startedAt else { return }
        let session = Session(
            id: currentSessionID,
            tabID: tabID,
            startedAt: startedAt,
            endedAt: Date(),
            entries: currentEntries
        )
        sessions.insert(session, at: 0)
        sessions = Array(sessions.prefix(Self.maximumSessions))
        currentEntries = []
        recordingTabID = nil
        self.startedAt = nil
        isRecording = false
        message = "已停止，日志可导出或删除（\(session.entries.count) 条）"
        persist()
    }

    private func append(_ entry: Entry) {
        guard isRecording, recordingTabID == entry.tabID else { return }
        currentEntries.append(entry)
        if currentEntries.count > Self.maximumEntries {
            currentEntries.removeFirst(currentEntries.count - Self.maximumEntries)
        }
    }

    private func clearAll() {
        guard !isRecording else {
            message = "请先停止录制，再清空已保存日志"
            return
        }
        sessions.removeAll()
        message = "已清空诊断日志"
        persist()
    }

    private func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        message = "已删除诊断日志"
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([Session].self, from: data)
            sessions = Array(sessions.prefix(Self.maximumSessions))
        } catch {
            lastError = "诊断日志缓存损坏，已忽略旧记录"
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(sessions)
            let temporaryURL = storageURL.appendingPathExtension("tmp")
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: storageURL.path) {
                _ = try fileManager.replaceItemAt(storageURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storageURL)
            }
        } catch {
            lastError = "无法保存诊断日志：\(error.localizedDescription)"
        }
    }

    static let contentWorld = WKContentWorld.world(name: "com.aitrans.browser.debug")
    static let messageName = "aitransBrowserDebug"

    /// Resource Timing + DOM/media metadata only. No body, page text, cookie,
    /// form value, or response header is read or sent to the app.
    static let userScriptSource = #"""
    (() => {
      const channel = "aitransBrowserDebug";
      const send = (payload) => {
        try {
          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[channel];
          if (handler) handler.postMessage(payload);
        } catch (_) {}
      };
      const seenResources = new Set();
      const relevantTags = new Set(["SCRIPT", "IFRAME", "VIDEO", "AUDIO", "SOURCE", "IMG"]);
      const value = (node, key) => {
        try { return node && node.getAttribute ? node.getAttribute(key) || "" : ""; } catch (_) { return ""; }
      };
      const inspect = (node) => {
        if (!node || node.nodeType !== 1 || !relevantTags.has(node.tagName)) return;
        const src = value(node, "src") || value(node, "data-src") || value(node, "href");
        const width = Number(node.width || value(node, "width") || 0);
        const height = Number(node.height || value(node, "height") || 0);
        send({ kind: "domInsertion", url: src, src, tag: node.tagName.toLowerCase(), width, height,
          isTrackingPixel: node.tagName === "IMG" && width <= 2 && height <= 2 });
      };
      const scanResources = () => {
        try {
          performance.getEntriesByType("resource").forEach((entry) => {
            const key = [entry.name, entry.startTime, entry.initiatorType].join("|");
            if (seenResources.has(key)) return;
            seenResources.add(key);
            send({ kind: "resource", url: entry.name, initiatorType: entry.initiatorType || "unknown",
              duration: Math.round(entry.duration || 0), transferSize: Number(entry.transferSize || 0),
              encodedBodySize: Number(entry.encodedBodySize || 0), decodedBodySize: Number(entry.decodedBodySize || 0) });
          });
        } catch (_) {}
      };
      const install = () => {
        try {
          const root = document.documentElement || document;
          new MutationObserver((records) => records.forEach((record) => record.addedNodes.forEach(inspect))).observe(root, { childList: true, subtree: true });
          document.addEventListener("error", (event) => {
            const target = event.target;
            if (target && relevantTags.has(target.tagName)) send({ kind: "resourceError", url: value(target, "src") || value(target, "href"), tag: target.tagName.toLowerCase(), reason: "load-error" });
          }, true);
          document.addEventListener("play", (event) => {
            const target = event.target;
            if (target && (target.tagName === "VIDEO" || target.tagName === "AUDIO")) send({ kind: "media", url: value(target, "src"), tag: target.tagName.toLowerCase(), event: "play" });
          }, true);
          document.addEventListener("fullscreenchange", () => send({ kind: "media", event: "fullscreenchange" }), true);
          scanResources();
          window.setInterval(scanResources, 2500);
        } catch (_) {}
      };
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", install, { once: true }); else install();
    })();
    """#
}
