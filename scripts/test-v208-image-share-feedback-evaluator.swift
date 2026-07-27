import Foundation

private enum ShareFeedbackState: Equatable {
    case idle
    case preparing
    case failed(String)
}

private struct ShareFeedbackLifecycle {
    private(set) var requestID = UUID()
    private(set) var state: ShareFeedbackState = .idle

    mutating func begin() -> UUID? {
        guard state != .preparing else { return nil }
        let nextID = UUID()
        requestID = nextID
        state = .preparing
        return nextID
    }

    mutating func succeed(_ completedID: UUID) {
        guard requestID == completedID else { return }
        state = .idle
    }

    mutating func fail(_ completedID: UUID, message: String) {
        guard requestID == completedID else { return }
        state = .failed(message)
    }

    mutating func discard() {
        requestID = UUID()
        state = .idle
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testPreparingRejectsDuplicate() {
    var lifecycle = ShareFeedbackLifecycle()
    let request = lifecycle.begin()
    require(request != nil, "idle share must start")
    require(lifecycle.state == .preparing, "share must publish preparing before async work")
    require(lifecycle.begin() == nil, "preparing share must reject duplicate request")
    require(lifecycle.requestID == request, "duplicate request must not replace current identity")
}

private func testCurrentCompletionAndFailure() {
    var lifecycle = ShareFeedbackLifecycle()
    let success = lifecycle.begin()!
    lifecycle.succeed(success)
    require(lifecycle.state == .idle, "current success must return to idle")
    let failure = lifecycle.begin()!
    lifecycle.fail(failure, message: "copy failed")
    require(lifecycle.state == .failed("copy failed"), "current failure must remain visible")
    require(lifecycle.begin() != nil, "failure must allow a new attempt")
}

private func testStaleResultsAndDiscardCannotOverwrite() {
    var lifecycle = ShareFeedbackLifecycle()
    let stale = lifecycle.begin()!
    lifecycle.discard()
    let current = lifecycle.begin()!
    lifecycle.succeed(stale)
    require(lifecycle.state == .preparing, "stale success must not clear current preparing state")
    lifecycle.fail(stale, message: "stale failure")
    require(lifecycle.state == .preparing, "stale failure must not replace current state")
    lifecycle.fail(current, message: "current failure")
    require(lifecycle.state == .failed("current failure"), "current failure must publish")
    lifecycle.discard()
    require(lifecycle.state == .idle, "dismiss or content invalidation must reset feedback")
}

testPreparingRejectsDuplicate()
testCurrentCompletionAndFailure()
testStaleResultsAndDiscardCannotOverwrite()
print("v2.8 image share feedback evaluator passed")
