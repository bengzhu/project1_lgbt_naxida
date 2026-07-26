import Foundation

private struct ImageShareLifecycle {
    let root: URL
    private(set) var requestID = UUID()
    private(set) var ownedDirectories: Set<URL> = []
    private(set) var publicShareURL: URL?
    var deletionFailures: Set<URL> = []

    mutating func begin(sourceFilename: String) -> (requestID: UUID, directory: URL, shareURL: URL) {
        discard()
        let nextID = UUID()
        requestID = nextID
        let directory = root.appendingPathComponent(nextID.uuidString, isDirectory: true)
        let base = (sourceFilename as NSString).deletingPathExtension
        return (nextID, directory, directory.appendingPathComponent("\(base)-translated.png"))
    }

    mutating func complete(
        _ request: (requestID: UUID, directory: URL, shareURL: URL),
        sourceURL: URL
    ) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: false)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: request.shareURL)
        } catch {
            try? FileManager.default.copyItem(at: sourceURL, to: request.shareURL)
        }
        guard requestID == request.requestID else {
            if !remove(request.directory) { ownedDirectories.insert(request.directory.standardizedFileURL) }
            return
        }
        ownedDirectories.insert(request.directory.standardizedFileURL)
        publicShareURL = request.shareURL
    }

    mutating func reconcile() {
        let managedRoot = root.standardizedFileURL
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: managedRoot,
            includingPropertiesForKeys: nil
        ) else { return }
        for candidate in candidates {
            let directory = candidate.standardizedFileURL
            guard directory.deletingLastPathComponent() == managedRoot,
                  UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            ownedDirectories.insert(directory)
        }
        discard()
    }

    mutating func discard() {
        requestID = UUID()
        publicShareURL = nil
        for directory in Array(ownedDirectories) where remove(directory) {
            ownedDirectories.remove(directory)
        }
    }

    mutating func remove(_ directory: URL) -> Bool {
        let managedRoot = root.standardizedFileURL
        let managedDirectory = directory.standardizedFileURL
        guard managedDirectory.deletingLastPathComponent() == managedRoot,
              UUID(uuidString: managedDirectory.lastPathComponent) != nil else { return false }
        let fileManager = FileManager.default
        guard (try? fileManager.destinationOfSymbolicLink(atPath: managedDirectory.path)) == nil else {
            return false
        }
        guard fileManager.fileExists(atPath: managedDirectory.path) else { return true }
        guard let values = try? managedDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              !deletionFailures.contains(managedDirectory) else { return false }
        do {
            try fileManager.removeItem(at: managedDirectory)
            return !fileManager.fileExists(atPath: managedDirectory.path)
        } catch {
            return false
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func makeFile(_ url: URL, contents: String = "fixture") {
    _ = FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8))
}

private let sandbox = FileManager.default.temporaryDirectory
    .appendingPathComponent("aitrans-v206-\(UUID().uuidString)", isDirectory: true)
private let shareRoot = sandbox.appendingPathComponent("ImageTranslationShares", isDirectory: true)
private let outside = sandbox.appendingPathComponent("Outside", isDirectory: true)
try FileManager.default.createDirectory(at: shareRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: sandbox) }

private func testReadableShareAndDismissCleanup() {
    let source = sandbox.appendingPathComponent("aitrans-export-\(UUID().uuidString)-receipt-translated.png")
    makeFile(source, contents: "translated")
    var lifecycle = ImageShareLifecycle(root: shareRoot)
    let request = lifecycle.begin(sourceFilename: "receipt.png")
    lifecycle.complete(request, sourceURL: source)
    require(request.shareURL.lastPathComponent == "receipt-translated.png", "share leaf must be readable")
    require(!request.shareURL.lastPathComponent.contains(request.requestID.uuidString), "share leaf must hide UUID")
    require((try? Data(contentsOf: request.shareURL)) == Data("translated".utf8), "share content must match export")
    lifecycle.discard()
    require(lifecycle.publicShareURL == nil, "dismiss must revoke public share URL")
    require(!FileManager.default.fileExists(atPath: request.directory.path), "dismiss must remove share directory")
}

private func testStaleRequestCannotPublish() {
    let source = sandbox.appendingPathComponent("stale-source.png")
    makeFile(source)
    var lifecycle = ImageShareLifecycle(root: shareRoot)
    let requestA = lifecycle.begin(sourceFilename: "A.png")
    let requestB = lifecycle.begin(sourceFilename: "B.png")
    lifecycle.complete(requestA, sourceURL: source)
    require(lifecycle.publicShareURL == nil, "stale A must not publish after B starts")
    require(!FileManager.default.fileExists(atPath: requestA.directory.path), "stale A directory must be removed")
    lifecycle.complete(requestB, sourceURL: source)
    require(lifecycle.publicShareURL == requestB.shareURL, "current B must publish")
}

private func testStartupCleanupAndGuardRejections() {
    let orphan = shareRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let arbitrary = shareRoot.appendingPathComponent("user-files", isDirectory: true)
    let outsideDirectory = outside.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nestedParent = shareRoot.appendingPathComponent("Nested", isDirectory: true)
    let nested = nestedParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let symlink = shareRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let dangling = shareRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    for directory in [orphan, arbitrary, outsideDirectory, nested] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    makeFile(orphan.appendingPathComponent("page-translated.png"))
    try? FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideDirectory)
    try? FileManager.default.createSymbolicLink(
        at: dangling,
        withDestinationURL: outside.appendingPathComponent("missing", isDirectory: true)
    )
    var lifecycle = ImageShareLifecycle(root: shareRoot)
    lifecycle.reconcile()
    require(!FileManager.default.fileExists(atPath: orphan.path), "startup must remove owned UUID directory")
    require(FileManager.default.fileExists(atPath: arbitrary.path), "startup must retain arbitrary directory")
    require(FileManager.default.fileExists(atPath: outsideDirectory.path), "startup must retain outside directory")
    require(FileManager.default.fileExists(atPath: nested.path), "startup must retain nested UUID directory")
    require((try? FileManager.default.destinationOfSymbolicLink(atPath: symlink.path)) != nil, "symlink must survive")
    require((try? FileManager.default.destinationOfSymbolicLink(atPath: dangling.path)) != nil, "dangling symlink must survive")
}

private func testDeletionFailureRetries() {
    let source = sandbox.appendingPathComponent("retry-source.png")
    makeFile(source)
    var lifecycle = ImageShareLifecycle(root: shareRoot)
    let request = lifecycle.begin(sourceFilename: "retry.png")
    lifecycle.complete(request, sourceURL: source)
    lifecycle.deletionFailures.insert(request.directory.standardizedFileURL)
    lifecycle.discard()
    require(lifecycle.ownedDirectories.contains(request.directory.standardizedFileURL), "failure must retain ownership")
    lifecycle.deletionFailures.removeAll()
    lifecycle.discard()
    require(lifecycle.ownedDirectories.isEmpty, "later lifecycle must release ownership")
    require(!FileManager.default.fileExists(atPath: request.directory.path), "later lifecycle must remove share")
}

testReadableShareAndDismissCleanup()
testStaleRequestCannotPublish()
testStartupCleanupAndGuardRejections()
testDeletionFailureRetries()
print("v2.6 image share lifecycle evaluator passed")
