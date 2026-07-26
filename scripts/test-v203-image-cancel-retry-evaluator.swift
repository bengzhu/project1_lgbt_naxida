import Foundation

private enum ImageState: Equatable {
    case idle
    case running
    case failed
    case translated
}

private struct ImageRetryEvaluator {
    private(set) var state: ImageState = .idle
    private(set) var sourceExists = false

    var canRetry: Bool {
        (state == .idle || state == .failed) && sourceExists
    }

    mutating func begin() {
        state = .running
        sourceExists = false
    }

    mutating func publishSource() {
        sourceExists = true
    }

    mutating func cancel() {
        state = .idle
    }

    mutating func fail() {
        state = .failed
    }

    mutating func finish() {
        state = .translated
    }

    mutating func clear() {
        state = .idle
        sourceExists = false
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testCancelAfterSourcePublicationCanRetry() {
    var evaluator = ImageRetryEvaluator()
    evaluator.begin()
    evaluator.publishSource()
    evaluator.cancel()
    require(evaluator.canRetry, "cancelled task with a retained source must be retryable")
}

private func testCancelBeforeSourcePublicationCannotRetry() {
    var evaluator = ImageRetryEvaluator()
    evaluator.begin()
    evaluator.cancel()
    require(!evaluator.canRetry, "cancelled transfer without a source must not offer retry")
}

private func testFailureRequiresARealSource() {
    var missingSource = ImageRetryEvaluator()
    missingSource.begin()
    missingSource.fail()
    require(!missingSource.canRetry, "transfer failure without a source must not offer retry")

    var retainedSource = ImageRetryEvaluator()
    retainedSource.begin()
    retainedSource.publishSource()
    retainedSource.fail()
    require(retainedSource.canRetry, "pipeline failure with a retained source must be retryable")
}

private func testClearAndSuccessNeverOfferRetry() {
    var cleared = ImageRetryEvaluator()
    cleared.begin()
    cleared.publishSource()
    cleared.clear()
    require(!cleared.canRetry, "clear must remove retry availability")

    var translated = ImageRetryEvaluator()
    translated.begin()
    translated.publishSource()
    translated.finish()
    require(!translated.canRetry, "completed translation uses retranslation controls, not retry")
}

testCancelAfterSourcePublicationCanRetry()
testCancelBeforeSourcePublicationCannotRetry()
testFailureRequiresARealSource()
testClearAndSuccessNeverOfferRetry()
print("v2.3 image cancel retry evaluator passed")
