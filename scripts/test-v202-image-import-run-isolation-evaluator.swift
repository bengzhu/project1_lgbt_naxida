import Foundation

private enum ImportKind: String {
    case photo
    case file
}

private enum ImportState: Equatable {
    case idle
    case loading(ImportKind)
    case ready
    case failed(String)
    case cancelled
}

private enum ImportDecision: Equatable {
    case accepted
    case stale
    case failed(String)
}

private struct ImageImportRunIsolationEvaluator {
    private(set) var currentRunID = 0
    private(set) var state: ImportState = .idle
    private(set) var sourceURL: String?

    mutating func begin(_ kind: ImportKind) -> Int {
        currentRunID += 1
        state = .loading(kind)
        sourceURL = nil
        return currentRunID
    }

    mutating func acceptTransfer(runID: Int, data: Data?) -> ImportDecision {
        guard runID == currentRunID else { return .stale }
        guard data?.isEmpty == false else {
            state = .failed("photoTransferReturnedNoData")
            return .failed("photoTransferReturnedNoData")
        }
        return .accepted
    }

    mutating func publishSandboxURL(runID: Int, url: String) -> ImportDecision {
        guard runID == currentRunID else { return .stale }
        sourceURL = url
        return .accepted
    }

    mutating func finish(runID: Int, error: String? = nil) -> ImportDecision {
        guard runID == currentRunID else { return .stale }
        if let error {
            state = .failed(error)
            return .failed(error)
        }
        state = .ready
        return .accepted
    }

    mutating func cancel() {
        currentRunID += 1
        state = .cancelled
    }

    mutating func clear() {
        currentRunID += 1
        state = .idle
        sourceURL = nil
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testLatestSelectionWinsRegardlessOfCompletionOrder() {
    var slowA = ImageImportRunIsolationEvaluator()
    let a = slowA.begin(.photo)
    let b = slowA.begin(.photo)
    require(slowA.acceptTransfer(runID: a, data: Data([1])) == .stale, "late A must be stale")
    require(slowA.acceptTransfer(runID: b, data: Data([2])) == .accepted, "B must remain current")

    var slowB = ImageImportRunIsolationEvaluator()
    let first = slowB.begin(.photo)
    require(slowB.acceptTransfer(runID: first, data: Data([1])) == .accepted, "A may finish transfer first")
    let second = slowB.begin(.photo)
    require(slowB.finish(runID: first) == .stale, "A pipeline completion must not overwrite B")
    require(slowB.acceptTransfer(runID: second, data: Data([2])) == .accepted, "B must remain current")
}

private func testCancelAndClearInvalidateLateCallbacks() {
    var evaluator = ImageImportRunIsolationEvaluator()
    let cancelled = evaluator.begin(.photo)
    evaluator.cancel()
    require(evaluator.acceptTransfer(runID: cancelled, data: Data([1])) == .stale, "cancel must invalidate transfer")
    require(evaluator.state == .cancelled, "late callback must not replace cancelled state")

    let cleared = evaluator.begin(.photo)
    evaluator.clear()
    require(evaluator.finish(runID: cleared, error: "late error") == .stale, "clear must invalidate errors")
    require(evaluator.state == .idle && evaluator.sourceURL == nil, "clear must remain empty")
}

private func testNilTransferFailsExplicitly() {
    var evaluator = ImageImportRunIsolationEvaluator()
    let runID = evaluator.begin(.photo)
    require(
        evaluator.acceptTransfer(runID: runID, data: nil) == .failed("photoTransferReturnedNoData"),
        "nil transfer must be an explicit current-run failure"
    )
    require(evaluator.state == .failed("photoTransferReturnedNoData"), "nil transfer must publish failure state")
}

private func testPhotoAndFileSupersedeEachOther() {
    var evaluator = ImageImportRunIsolationEvaluator()
    let photo = evaluator.begin(.photo)
    let file = evaluator.begin(.file)
    require(evaluator.publishSandboxURL(runID: photo, url: "photo.png") == .stale, "file must supersede photo")
    require(evaluator.publishSandboxURL(runID: file, url: "file.png") == .accepted, "file must publish")

    let nextPhoto = evaluator.begin(.photo)
    require(evaluator.finish(runID: file) == .stale, "photo must supersede file pipeline")
    require(evaluator.publishSandboxURL(runID: nextPhoto, url: "next-photo.png") == .accepted, "new photo must publish")
}

private func testSandboxAndFailureCannotRestoreOldSourceURL() {
    var evaluator = ImageImportRunIsolationEvaluator()
    let oldRun = evaluator.begin(.file)
    require(evaluator.publishSandboxURL(runID: oldRun, url: "old.png") == .accepted, "fixture setup failed")

    let newRun = evaluator.begin(.photo)
    require(evaluator.sourceURL == nil, "new intent must clear retry source before transfer")
    require(evaluator.publishSandboxURL(runID: oldRun, url: "old-late.png") == .stale, "sandbox write needs identity check")
    require(evaluator.finish(runID: oldRun, error: "old failure") == .stale, "old error must be ignored")
    require(evaluator.sourceURL == nil, "stale completion must not restore old retry source")
    require(evaluator.finish(runID: newRun, error: "new failure") == .failed("new failure"), "current failure must publish")
    require(evaluator.sourceURL == nil, "failed new import must not expose old retry source")
}

testLatestSelectionWinsRegardlessOfCompletionOrder()
testCancelAndClearInvalidateLateCallbacks()
testNilTransferFailsExplicitly()
testPhotoAndFileSupersedeEachOther()
testSandboxAndFailureCannotRestoreOldSourceURL()
print("v2.2 image import run isolation evaluator passed")
