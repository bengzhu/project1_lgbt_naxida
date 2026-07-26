import Foundation

private enum ManagedKind {
    case input
    case staging
    case stableExport
}

private struct ImageWorkspaceRecovery {
    let directory: URL
    private(set) var ownedExports: Set<URL> = []
    private(set) var ownedOrphans: Set<URL> = []
    var deletionFailures: Set<URL> = []

    mutating func reconcile() {
        let managedDirectory = directory.standardizedFileURL
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: managedDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for candidate in candidates {
            let file = candidate.standardizedFileURL
            let filename = file.lastPathComponent
            guard file.deletingLastPathComponent() == managedDirectory else { continue }
            if isStableExport(filename) {
                ownedExports.insert(file)
            } else if isInput(filename) || isStaging(filename) {
                ownedOrphans.insert(file)
            }
        }
        discard()
    }

    mutating func discard() {
        for url in Array(ownedExports) where remove(url, kind: .stableExport) {
            ownedExports.remove(url)
        }
        for url in Array(ownedOrphans) {
            let kind: ManagedKind = isInput(url.lastPathComponent) ? .input : .staging
            if remove(url, kind: kind) {
                ownedOrphans.remove(url)
            }
        }
    }

    mutating func removeRuntime(_ url: URL, kind: ManagedKind) -> Bool {
        let managedDirectory = directory.standardizedFileURL
        let file = url.standardizedFileURL
        let removed = remove(file, kind: kind)
        if removed {
            ownedOrphans.remove(file)
        } else if file.deletingLastPathComponent() == managedDirectory,
                  isManaged(file.lastPathComponent, kind: kind) {
            ownedOrphans.insert(file)
        }
        return removed
    }

    mutating func remove(_ url: URL, kind: ManagedKind) -> Bool {
        let managedDirectory = directory.standardizedFileURL
        let file = url.standardizedFileURL
        guard file.deletingLastPathComponent() == managedDirectory,
              isManaged(file.lastPathComponent, kind: kind) else {
            return false
        }
        let fileManager = FileManager.default
        guard (try? fileManager.destinationOfSymbolicLink(atPath: file.path)) == nil else {
            return false
        }
        guard fileManager.fileExists(atPath: file.path) else { return true }
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              !deletionFailures.contains(file) else {
            return false
        }
        do {
            try fileManager.removeItem(at: file)
            return !fileManager.fileExists(atPath: file.path)
        } catch {
            return false
        }
    }

    func isManaged(_ filename: String, kind: ManagedKind) -> Bool {
        switch kind {
        case .input: isInput(filename)
        case .staging: isStaging(filename)
        case .stableExport: isStableExport(filename)
        }
    }

    func isInput(_ filename: String) -> Bool {
        guard !filename.hasPrefix("."), filename.count > 37 else { return false }
        let uuidEnd = filename.index(filename.startIndex, offsetBy: 36)
        let uuid = String(filename[..<uuidEnd])
        let remainder = filename[filename.index(after: uuidEnd)...]
        return filename[uuidEnd] == "-" && UUID(uuidString: uuid) != nil && !remainder.isEmpty
    }

    func isStaging(_ filename: String) -> Bool {
        let suffix = ".staging.png"
        guard filename.hasPrefix("."), filename.hasSuffix(suffix) else { return false }
        let stem = String(filename.dropLast(suffix.count))
        guard stem.count > 48 else { return false }
        return UUID(uuidString: String(stem.suffix(36))) != nil &&
            String(stem.dropLast(36)).hasSuffix("-translated-")
    }

    func isStableExport(_ filename: String) -> Bool {
        let prefix = "aitrans-export-"
        let suffix = "-translated.png"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return false }
        let remainder = String(filename.dropFirst(prefix.count))
        guard remainder.count > 36 + 1 + suffix.count else { return false }
        let uuidEnd = remainder.index(remainder.startIndex, offsetBy: 36)
        let uuid = String(remainder[..<uuidEnd])
        let baseAndSuffix = remainder[remainder.index(after: uuidEnd)...]
        return remainder[uuidEnd] == "-" &&
            UUID(uuidString: uuid) != nil &&
            baseAndSuffix.count > suffix.count &&
            baseAndSuffix.hasSuffix(suffix)
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func makeFile(_ url: URL) {
    _ = FileManager.default.createFile(atPath: url.path, contents: Data("fixture".utf8))
}

private func stableExport(_ base: String = "page") -> String {
    "aitrans-export-\(UUID().uuidString)-\(base)-translated.png"
}

private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("aitrans-v205-\(UUID().uuidString)", isDirectory: true)
private let managed = root.appendingPathComponent("ImageTranslations", isDirectory: true)
private let outside = root.appendingPathComponent("Outside", isDirectory: true)
try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

private func testFilenameClassification() {
    let taskID = UUID()
    let renderID = UUID()
    let recovery = ImageWorkspaceRecovery(directory: managed)
    require(recovery.isInput("\(taskID.uuidString)-page.png"), "task UUID input must be recognized")
    require(!recovery.isInput("not-a-uuid-page.png"), "malformed input must be rejected")
    require(!recovery.isInput("\(taskID.uuidString)-"), "empty input name must be rejected")
    require(recovery.isStaging(".page-translated-\(renderID.uuidString).staging.png"), "render staging must be recognized")
    require(!recovery.isStaging(".page-\(renderID.uuidString).staging.png"), "staging without translated marker must be rejected")
    require(!recovery.isStaging(".page-translated-bad.staging.png"), "staging without UUID must be rejected")
    require(recovery.isStableExport(stableExport()), "marked stable export must be recognized")
    require(!recovery.isStableExport("page-translated.png"), "unmarked translated suffix must be rejected")
}

private func testStartupRemovesPriorInputStagingAndExport() {
    let input = managed.appendingPathComponent("\(UUID().uuidString)-page.png")
    let staging = managed.appendingPathComponent(".page-translated-\(UUID().uuidString).staging.png")
    let output = managed.appendingPathComponent(stableExport())
    for url in [input, staging, output] { makeFile(url) }
    var recovery = ImageWorkspaceRecovery(directory: managed)
    recovery.reconcile()
    for url in [input, staging, output] {
        require(!FileManager.default.fileExists(atPath: url.path), "startup must remove \(url.lastPathComponent)")
    }
    require(recovery.ownedExports.isEmpty && recovery.ownedOrphans.isEmpty, "successful cleanup must release ownership")
}

private func testArbitraryNestedOutsideAndSymlinkFilesSurvive() {
    let arbitrary = managed.appendingPathComponent("user-note-translated.png")
    let overlappingInput = managed.appendingPathComponent("\(UUID().uuidString)-page-translated.png")
    let nestedDirectory = managed.appendingPathComponent("Nested", isDirectory: true)
    let nested = nestedDirectory.appendingPathComponent("\(UUID().uuidString)-nested.png")
    let outsideInput = outside.appendingPathComponent("\(UUID().uuidString)-outside.png")
    let symlink = managed.appendingPathComponent("\(UUID().uuidString)-link.png")
    let dangling = managed.appendingPathComponent("\(UUID().uuidString)-dangling.png")
    try? FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    for url in [arbitrary, overlappingInput, nested, outsideInput] { makeFile(url) }
    try? FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideInput)
    try? FileManager.default.createSymbolicLink(
        at: dangling,
        withDestinationURL: outside.appendingPathComponent("missing.png")
    )

    var recovery = ImageWorkspaceRecovery(directory: managed)
    recovery.reconcile()
    for url in [arbitrary, nested, outsideInput, symlink] {
        require(FileManager.default.fileExists(atPath: url.path), "guard must retain \(url.lastPathComponent)")
    }
    require(
        !FileManager.default.fileExists(atPath: overlappingInput.path),
        "task UUID input must be classified as an input orphan, not a stable export"
    )
    require((try? FileManager.default.destinationOfSymbolicLink(atPath: dangling.path)) != nil, "dangling symlink must survive")
}

private func testWrongKindCannotDeleteAnotherManagedFile() {
    let input = managed.appendingPathComponent("\(UUID().uuidString)-page.png")
    let staging = managed.appendingPathComponent(".page-translated-\(UUID().uuidString).staging.png")
    makeFile(input)
    makeFile(staging)
    var recovery = ImageWorkspaceRecovery(directory: managed)
    require(!recovery.remove(input, kind: .staging), "staging cleanup must reject input")
    require(!recovery.remove(staging, kind: .input), "input cleanup must reject staging")
    require(FileManager.default.fileExists(atPath: input.path), "wrong-kind input must remain")
    require(FileManager.default.fileExists(atPath: staging.path), "wrong-kind staging must remain")
    require(recovery.remove(input, kind: .input), "input cleanup must accept input")
    require(recovery.remove(staging, kind: .staging), "staging cleanup must accept staging")
}

private func testFailedOrphanDeletionRetries() {
    let input = managed.appendingPathComponent("\(UUID().uuidString)-retry.png").standardizedFileURL
    makeFile(input)
    var recovery = ImageWorkspaceRecovery(directory: managed)
    recovery.deletionFailures.insert(input)
    recovery.reconcile()
    require(recovery.ownedOrphans.contains(input), "failed cleanup must retain orphan ownership")
    require(FileManager.default.fileExists(atPath: input.path), "failed cleanup must retain input")
    recovery.deletionFailures.remove(input)
    recovery.discard()
    require(!recovery.ownedOrphans.contains(input), "later lifecycle must release cleaned orphan")
    require(!FileManager.default.fileExists(atPath: input.path), "later lifecycle must remove retained orphan")
}

private func testRuntimeDeletionFailureRegistersForLifecycleRetry() {
    let input = managed.appendingPathComponent("\(UUID().uuidString)-runtime.png").standardizedFileURL
    let staging = managed.appendingPathComponent(
        ".runtime-translated-\(UUID().uuidString).staging.png"
    ).standardizedFileURL
    makeFile(input)
    makeFile(staging)
    var recovery = ImageWorkspaceRecovery(directory: managed)
    recovery.deletionFailures.formUnion([input, staging])
    require(!recovery.removeRuntime(input, kind: .input), "runtime input failure must be reported")
    require(!recovery.removeRuntime(staging, kind: .staging), "runtime staging failure must be reported")
    require(recovery.ownedOrphans == Set([input, staging]), "runtime failures must retain orphan ownership")
    recovery.deletionFailures.removeAll()
    recovery.discard()
    require(recovery.ownedOrphans.isEmpty, "next lifecycle must release runtime orphan ownership")
    require(!FileManager.default.fileExists(atPath: input.path), "next lifecycle must remove runtime input")
    require(!FileManager.default.fileExists(atPath: staging.path), "next lifecycle must remove runtime staging")
}

testFilenameClassification()
testStartupRemovesPriorInputStagingAndExport()
testArbitraryNestedOutsideAndSymlinkFilesSurvive()
testWrongKindCannotDeleteAnotherManagedFile()
testFailedOrphanDeletionRetries()
testRuntimeDeletionFailureRegistersForLifecycleRetry()
print("v2.5 image workspace recovery evaluator passed")
