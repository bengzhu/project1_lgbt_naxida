import Foundation

private enum RenderFeedbackState: Equatable {
    case idle
    case rendering
    case failed(String)
}

private struct RenderFeedbackLifecycle {
    private(set) var renderID = UUID()
    private(set) var state: RenderFeedbackState = .idle

    mutating func begin() -> UUID? {
        guard state != .rendering else { return nil }
        let nextID = UUID()
        renderID = nextID
        state = .rendering
        return nextID
    }

    mutating func succeed(_ completedID: UUID) {
        guard renderID == completedID else { return }
        state = .idle
    }

    mutating func fail(_ completedID: UUID, message: String) {
        guard renderID == completedID else { return }
        state = .failed(message)
    }

    mutating func invalidate() {
        renderID = UUID()
        state = .idle
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testDuplicateAndCurrentCompletion() {
    var lifecycle = RenderFeedbackLifecycle()
    let current = lifecycle.begin()!
    require(lifecycle.state == .rendering, "begin must publish rendering")
    require(lifecycle.begin() == nil, "rendering must reject duplicate mode changes")
    lifecycle.succeed(current)
    require(lifecycle.state == .idle, "current success must return to idle")
}

private func testFailureCanRetry() {
    var lifecycle = RenderFeedbackLifecycle()
    let failed = lifecycle.begin()!
    lifecycle.fail(failed, message: "publish failed")
    require(lifecycle.state == .failed("publish failed"), "current failure must remain visible")
    let retry = lifecycle.begin()
    require(retry != nil, "failed render must allow retry")
    require(lifecycle.state == .rendering, "retry must return to rendering")
}

private func testStaleResultsCannotOverwriteCurrentRender() {
    var lifecycle = RenderFeedbackLifecycle()
    let stale = lifecycle.begin()!
    lifecycle.invalidate()
    let current = lifecycle.begin()!
    lifecycle.succeed(stale)
    require(lifecycle.state == .rendering, "stale success must not clear current rendering")
    lifecycle.fail(stale, message: "stale failure")
    require(lifecycle.state == .rendering, "stale failure must not replace current rendering")
    lifecycle.fail(current, message: "current failure")
    require(lifecycle.state == .failed("current failure"), "current failure must publish")
    lifecycle.invalidate()
    require(lifecycle.state == .idle, "content invalidation must reset render feedback")
}

testDuplicateAndCurrentCompletion()
testFailureCanRetry()
testStaleResultsCannotOverwriteCurrentRender()
print("v2.9 image render feedback evaluator passed")
