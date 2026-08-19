import Foundation

@main
struct ImageOCRSelectorPolicyEvaluator {
    static func main() throws {
        let policy = ImageOCRSelectorPolicy()
        precondition(policy.featureFlagEnabled == false)
        precondition(policy.isFailClosed)
        let encodedPolicy = try JSONEncoder().encode(policy)
        let decodedPolicy = try JSONDecoder().decode(
            ImageOCRSelectorPolicy.self,
            from: encodedPolicy
        )
        precondition(decodedPolicy == policy)

        let baseline = ImageOCRSelectorEngineSignal(
            engineID: "bundled-manga-ocr",
            candidateRole: .baseline,
            artifactStatus: .available,
            licenseReviewed: true,
            supportedCropVariants: [.detectorBBox, .lineQuad, .blockBBox],
            outputStatus: .success,
            hasNonEmptyText: true,
            warmLatencyMilliseconds: 9.4,
            peakMemoryBytes: 104_857_600
        )
        let missingCandidate = ImageOCRSelectorEngineSignal(
            engineID: "candidate-ocr-vl",
            candidateRole: .candidate,
            artifactStatus: .missing,
            licenseReviewed: false,
            supportedCropVariants: [],
            outputStatus: .failure,
            hasNonEmptyText: false
        )
        let goodCandidate = ImageOCRSelectorEngineSignal(
            engineID: "candidate-ocr-vl",
            candidateRole: .candidate,
            artifactStatus: .available,
            licenseReviewed: true,
            supportedCropVariants: [.detectorBBox],
            outputStatus: .success,
            hasNonEmptyText: true,
            calibratedQuality: 0.91,
            calibrationProfileID: "ocr-calibration-v1",
            warmLatencyMilliseconds: 32.0,
            peakMemoryBytes: 134_217_728
        )
        let context = ImageOCRSelectorContext(
            cropVariant: .detectorBBox,
            geometryValid: true,
            duplicateRisk: false,
            requestBudgetRemaining: 1,
            pixelBudgetRemaining: 16_000_000,
            cancellationState: .active,
            generationMatches: true,
            candidateFailureCount: 0
        )

        let defaultDecision = ImageOCREngineSelector.select(
            policy: policy,
            context: context,
            baseline: baseline,
            candidate: missingCandidate
        )
        precondition(defaultDecision.selectedEngineID == "bundled-manga-ocr")
        precondition(defaultDecision.candidateAccepted == false)
        precondition(defaultDecision.fallbackReasons.contains("featureFlagDisabled"))
        precondition(defaultDecision.requestBudgetDelta == 0)
        precondition(defaultDecision.pixelBudgetDelta == 0)
        precondition(defaultDecision.storeProvenance)
        precondition(defaultDecision.reviewStatePreserved)

        var controlledPolicy = policy
        controlledPolicy.featureFlagEnabled = true
        let candidateDecision = ImageOCREngineSelector.select(
            policy: controlledPolicy,
            context: context,
            baseline: baseline,
            candidate: goodCandidate
        )
        precondition(candidateDecision.selectedEngineID == "candidate-ocr-vl")
        precondition(candidateDecision.selectionReason == .candidateShadowEligible)
        precondition(candidateDecision.candidateAccepted)

        var cancelledContext = context
        cancelledContext.cancellationState = .cancelled
        let cancelledDecision = ImageOCREngineSelector.select(
            policy: controlledPolicy,
            context: cancelledContext,
            baseline: baseline,
            candidate: goodCandidate
        )
        precondition(cancelledDecision.selectedEngineID == "bundled-manga-ocr")
        precondition(cancelledDecision.selectionReason == .rollbackToBaseline)
        precondition(cancelledDecision.rollbackApplied)
        precondition(cancelledDecision.reviewStatePreserved)

        var noBaseline = baseline
        noBaseline.artifactStatus = .missing
        let noEngineDecision = ImageOCREngineSelector.select(
            policy: controlledPolicy,
            context: context,
            baseline: noBaseline,
            candidate: goodCandidate
        )
        precondition(noEngineDecision.selectedEngineID == nil)
        precondition(noEngineDecision.selectionReason == .noEngineAvailable)

        let decisionData = try JSONEncoder().encode(candidateDecision)
        let decodedDecision = try JSONDecoder().decode(
            ImageOCRSelectorDecision.self,
            from: decisionData
        )
        precondition(decodedDecision == candidateDecision)

        print("v3.285 image OCR selector policy evaluator passed")
    }
}
