import Foundation

private struct ImageExportLifecycle {
    let directory: URL
    private(set) var sourceURL: URL?
    private(set) var publicExportURL: URL?
    private(set) var ownedExportURLs: Set<URL> = []
    var deletionFailures: Set<URL> = []

    mutating func publish(source: URL? = nil, export: URL) {
        if let source {
            sourceURL = source
        }
        let standardizedExport = export.standardizedFileURL
        ownedExportURLs.insert(standardizedExport)
        publicExportURL = standardizedExport
    }

    mutating func beginReplacement(preservingSource: Bool = false) {
        discardExport()
        if !preservingSource {
            sourceURL = nil
        }
    }

    mutating func beginRerender() {
        discardExport()
    }

    mutating func cancel() {
        // Cancellation intentionally retains the published source for Retry.
    }

    mutating func clear() {
        if let sourceURL {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        discardExport()
        sourceURL = nil
    }

    mutating func discardExport() {
        publicExportURL = nil
        for url in Array(ownedExportURLs) where removeManagedExport(url) {
            ownedExportURLs.remove(url)
        }
    }

    mutating func discardOrphanedExportsAtStartup() {
        let managedDirectory = directory.standardizedFileURL
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: managedDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for candidate in candidates {
            let managedFile = candidate.standardizedFileURL
            let filename = managedFile.lastPathComponent
            guard managedFile.deletingLastPathComponent() == managedDirectory,
                  !filename.hasPrefix("."),
                  filename.hasSuffix("-translated.png") else {
                continue
            }
            ownedExportURLs.insert(managedFile)
        }
        discardExport()
    }

    private func removeManagedExport(_ url: URL) -> Bool {
        let managedDirectory = directory.standardizedFileURL
        let managedFile = url.standardizedFileURL
        let filename = managedFile.lastPathComponent
        guard managedFile.deletingLastPathComponent() == managedDirectory,
              !filename.hasPrefix("."),
              filename.hasSuffix("-translated.png") else {
            return false
        }
        let fileManager = FileManager.default
        guard (try? fileManager.destinationOfSymbolicLink(atPath: managedFile.path)) == nil else {
            return false
        }
        guard fileManager.fileExists(atPath: managedFile.path) else { return true }
        guard let values = try? managedFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              !deletionFailures.contains(managedFile) else {
            return false
        }
        do {
            try fileManager.removeItem(at: managedFile)
            return !fileManager.fileExists(atPath: managedFile.path)
        } catch {
            return false
        }
    }
}

private struct RenderLifecycle {
    private(set) var currentRenderID: UUID?
    private(set) var stagingURLs: Set<URL> = []
    private(set) var publishedExportURL: URL?

    mutating func begin() -> UUID {
        let renderID = UUID()
        currentRenderID = renderID
        publishedExportURL = nil
        return renderID
    }

    mutating func stage(renderID: UUID, url: URL) {
        stagingURLs.insert(url)
    }

    mutating func complete(renderID: UUID, stagingURL: URL, outputURL: URL, succeeded: Bool) {
        stagingURLs.remove(stagingURL)
        guard currentRenderID == renderID, succeeded else { return }
        publishedExportURL = outputURL
    }

    mutating func cancel() {
        currentRenderID = UUID()
        publishedExportURL = nil
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func makeFile(_ url: URL) {
    _ = FileManager.default.createFile(atPath: url.path, contents: Data("fixture".utf8))
}

private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("aitrans-v204-\(UUID().uuidString)", isDirectory: true)
private let managedDirectory = root.appendingPathComponent("ImageTranslations", isDirectory: true)
private let outsideDirectory = root.appendingPathComponent("Outside", isDirectory: true)
try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

private func testReplacementAndClearRemoveOwnedFiles() {
    let firstSource = managedDirectory.appendingPathComponent("first-source.png")
    let firstOutput = managedDirectory.appendingPathComponent("first-translated.png")
    makeFile(firstSource)
    makeFile(firstOutput)
    var lifecycle = ImageExportLifecycle(directory: managedDirectory)
    lifecycle.publish(source: firstSource, export: firstOutput)
    lifecycle.beginReplacement()
    require(!FileManager.default.fileExists(atPath: firstOutput.path), "replacement must remove the old stable export")

    let secondSource = managedDirectory.appendingPathComponent("second-source.png")
    let secondOutput = managedDirectory.appendingPathComponent("second-translated.png")
    makeFile(secondSource)
    makeFile(secondOutput)
    lifecycle.publish(source: secondSource, export: secondOutput)
    lifecycle.clear()
    require(!FileManager.default.fileExists(atPath: secondSource.path), "clear must remove the current source")
    require(!FileManager.default.fileExists(atPath: secondOutput.path), "clear must remove the stable export")
}

private func testCancelAndRetryPreserveSource() {
    let source = managedDirectory.appendingPathComponent("retry-source.png")
    let output = managedDirectory.appendingPathComponent("retry-translated.png")
    makeFile(source)
    makeFile(output)
    var lifecycle = ImageExportLifecycle(directory: managedDirectory)
    lifecycle.publish(source: source, export: output)
    lifecycle.cancel()
    require(FileManager.default.fileExists(atPath: source.path), "cancel must preserve the retry source")
    lifecycle.beginReplacement(preservingSource: true)
    require(FileManager.default.fileExists(atPath: source.path), "retry must preserve its source")
    require(!FileManager.default.fileExists(atPath: output.path), "retry must discard the prior export")
}

private func testRerenderRevokesPublicExportAndRemovesStableFile() {
    let source = managedDirectory.appendingPathComponent("rerender-source.png")
    let output = managedDirectory.appendingPathComponent("rerender-translated.png")
    makeFile(source)
    makeFile(output)
    var lifecycle = ImageExportLifecycle(directory: managedDirectory)
    lifecycle.publish(source: source, export: output)
    lifecycle.beginRerender()
    require(lifecycle.publicExportURL == nil, "rerender must revoke the public export URL")
    require(!FileManager.default.fileExists(atPath: output.path), "rerender must remove its superseded stable export")
    require(FileManager.default.fileExists(atPath: source.path), "rerender must preserve the source")
}

private func testDeletionFailureRetainsOwnershipForRetry() {
    let output = managedDirectory.appendingPathComponent("failure-translated.png").standardizedFileURL
    makeFile(output)
    var lifecycle = ImageExportLifecycle(directory: managedDirectory)
    lifecycle.publish(export: output)
    lifecycle.deletionFailures.insert(output)
    lifecycle.discardExport()
    require(lifecycle.publicExportURL == nil, "failed deletion must still revoke public sharing")
    require(lifecycle.ownedExportURLs.contains(output), "failed deletion must retain private ownership")
    require(FileManager.default.fileExists(atPath: output.path), "injected deletion failure must retain the file")
    lifecycle.deletionFailures.remove(output)
    lifecycle.discardExport()
    require(lifecycle.ownedExportURLs.isEmpty, "a later lifecycle event must retry retained cleanup")
    require(!FileManager.default.fileExists(atPath: output.path), "retried cleanup must remove the file")
}

private func testNewLifecycleCleansPriorStableExport() {
    let output = managedDirectory.appendingPathComponent("prior-launch-translated.png")
    makeFile(output)
    var newLifecycle = ImageExportLifecycle(directory: managedDirectory)
    newLifecycle.discardOrphanedExportsAtStartup()
    require(!FileManager.default.fileExists(atPath: output.path), "a new lifecycle must clean prior stable exports")
    require(newLifecycle.ownedExportURLs.isEmpty, "successful startup cleanup must release ownership")
}

private func testGuardRejectsOutsideNestedEscapeSourceStagingAndSymlink() {
    let outside = outsideDirectory.appendingPathComponent("outside-translated.png")
    let nestedDirectory = managedDirectory.appendingPathComponent("Nested", isDirectory: true)
    let nested = nestedDirectory.appendingPathComponent("nested-translated.png")
    let escaped = managedDirectory.appendingPathComponent("../Outside/escape-translated.png")
    let source = managedDirectory.appendingPathComponent("source.png")
    let staging = managedDirectory.appendingPathComponent(".page-translated-ID.staging.png")
    let symlink = managedDirectory.appendingPathComponent("link-translated.png")
    let danglingSymlink = managedDirectory.appendingPathComponent("dangling-translated.png")
    try? FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    for url in [outside, nested, escaped.standardizedFileURL, source, staging] {
        makeFile(url)
    }
    try? FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
    try? FileManager.default.createSymbolicLink(
        at: danglingSymlink,
        withDestinationURL: outsideDirectory.appendingPathComponent("missing.png")
    )

    var lifecycle = ImageExportLifecycle(directory: managedDirectory)
    for url in [outside, nested, escaped, source, staging, symlink, danglingSymlink] {
        lifecycle.publish(export: url)
    }
    lifecycle.discardExport()
    for url in [outside, nested, escaped.standardizedFileURL, source, staging, symlink] {
        require(FileManager.default.fileExists(atPath: url.path), "guard must retain \(url.lastPathComponent)")
    }
    let danglingDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: danglingSymlink.path)
    require(danglingDestination != nil, "guard must retain dangling symlinks")
    require(lifecycle.ownedExportURLs.contains(danglingSymlink), "dangling symlink ownership must not be released")
}

private func testStaleAndFailedRendersOnlyCleanTheirOwnStaging() {
    var lifecycle = RenderLifecycle()
    let renderA = lifecycle.begin()
    let stagingA = managedDirectory.appendingPathComponent(".A.staging.png")
    lifecycle.stage(renderID: renderA, url: stagingA)
    let renderB = lifecycle.begin()
    let stagingB = managedDirectory.appendingPathComponent(".B.staging.png")
    let outputA = managedDirectory.appendingPathComponent("A-translated.png")
    let outputB = managedDirectory.appendingPathComponent("B-translated.png")
    lifecycle.stage(renderID: renderB, url: stagingB)
    lifecycle.complete(renderID: renderA, stagingURL: stagingA, outputURL: outputA, succeeded: true)
    require(lifecycle.publishedExportURL == nil, "stale A must not publish over B")
    require(!lifecycle.stagingURLs.contains(stagingA), "stale A must clean its staging")
    lifecycle.complete(renderID: renderB, stagingURL: stagingB, outputURL: outputB, succeeded: false)
    require(lifecycle.publishedExportURL == nil, "failed B must not publish")
    require(lifecycle.stagingURLs.isEmpty, "failed B must clean its staging")
}

testReplacementAndClearRemoveOwnedFiles()
testCancelAndRetryPreserveSource()
testRerenderRevokesPublicExportAndRemovesStableFile()
testDeletionFailureRetainsOwnershipForRetry()
testNewLifecycleCleansPriorStableExport()
testGuardRejectsOutsideNestedEscapeSourceStagingAndSymlink()
testStaleAndFailedRendersOnlyCleanTheirOwnStaging()
print("v2.4 image export lifecycle evaluator passed")
