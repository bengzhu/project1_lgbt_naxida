import Foundation

/// Stable identifiers used inside one image-recognition session. These are
/// detector/TextRegion and line identities only; the ephemeral Koharu
/// `verticalTextRegionOwner` remains a separate field and is never serialized
/// as a persisted block identity.
struct ImageOCRRegionID: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct ImageOCRLineID: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

enum ImageOCREngineID: String, Codable, Sendable {
    case vision
    case bundledMangaOCR
    case fusion
}

enum ImageOCRCandidateRole: String, Codable, Sendable {
    case page
    case crop
    case verticalLine
    case detectorTextRegion
    case geometryOnly
    case tileFallback
    case blockFallback
    case layoutBlock
}

enum ImageOCRCropVariant: String, Codable, Sendable {
    case page
    case detectorBBox
    case blockBBox
    case lineBBox
    case lineQuad
    case tile
    case none
}

enum ImageOCRGeometrySource: String, Codable, Sendable {
    case none
    case bbox
    case lineQuad
}

enum ImageOCRSelectionReason: String, Codable, Sendable {
    case shadowOnly
    case selectedByExistingFusion
    case existingLayoutFusion
    case scopedRerecognition
}

/// Per-candidate information that is safe to compare in a later shadow
/// benchmark. Confidence is intentionally kept engine-local; v3.281 does not
/// compare raw confidence values across engines.
struct ImageOCRCandidateProvenance: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var engine: ImageOCREngineID
    var role: ImageOCRCandidateRole
    var cropVariant: ImageOCRCropVariant
    var geometrySource: ImageOCRGeometrySource
    var regionID: ImageOCRRegionID?
    var lineID: ImageOCRLineID?
    var rawConfidence: Float
    var detectorConfidence: Float?
    var rotationApplied: Int
    var verticalTextRegionOwner: Int?

    init(
        engine: ImageOCREngineID,
        role: ImageOCRCandidateRole,
        cropVariant: ImageOCRCropVariant,
        geometrySource: ImageOCRGeometrySource,
        regionID: ImageOCRRegionID? = nil,
        lineID: ImageOCRLineID? = nil,
        rawConfidence: Float,
        detectorConfidence: Float? = nil,
        rotationApplied: Int = 0,
        verticalTextRegionOwner: Int? = nil,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.engine = engine
        self.role = role
        self.cropVariant = cropVariant
        self.geometrySource = geometrySource
        self.regionID = regionID
        self.lineID = lineID
        self.rawConfidence = rawConfidence
        self.detectorConfidence = detectorConfidence
        self.rotationApplied = rotationApplied
        self.verticalTextRegionOwner = verticalTextRegionOwner
    }
}

/// A transient shadow row. It contains OCR text and geometry for later
/// comparison, but is not read by the production candidate selector.
struct ImageOCRCandidate: Equatable, Codable, Sendable {
    var candidateID: String
    var text: String
    var confidence: Float
    var rect: ImageOCRLayoutRect
    var provenance: ImageOCRCandidateProvenance
    var selectionReason: ImageOCRSelectionReason
}

/// Small, optional provenance persisted with a final image block. It records
/// the candidates already consumed by existing fusion/layout, without storing
/// the complete transient ledger or any benchmark ground truth.
struct ImageOCRBlockProvenance: Equatable, Codable, Sendable {
    var schemaVersion: Int
    var candidates: [ImageOCRCandidateProvenance]
    var selectionReason: ImageOCRSelectionReason

    init(
        candidates: [ImageOCRCandidateProvenance],
        selectionReason: ImageOCRSelectionReason = .existingLayoutFusion,
        schemaVersion: Int = ImageOCRCandidateProvenance.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        var unique: [ImageOCRCandidateProvenance] = []
        for candidate in candidates where !unique.contains(candidate) {
            unique.append(candidate)
        }
        self.candidates = unique
        self.selectionReason = selectionReason
    }

    static func make(
        from candidates: [ImageOCRCandidateProvenance],
        selectionReason: ImageOCRSelectionReason = .existingLayoutFusion
    ) -> Self? {
        guard !candidates.isEmpty else { return nil }
        return Self(candidates: candidates, selectionReason: selectionReason)
    }
}

/// The v3.281 shadow output is available to cloud-only evaluators and future
/// same-crop comparisons. Existing callers still receive only `blocks`, so the
/// ledger cannot alter production selection, request budgets, or UI output.
struct ImageOCRShadowLedger: Equatable, Codable, Sendable {
    var schemaVersion: Int
    var candidates: [ImageOCRCandidate]
    var selectedCandidateIDs: [String]

    init(
        candidates: [ImageOCRCandidate],
        selectedCandidateIDs: [String] = [],
        schemaVersion: Int = ImageOCRCandidateProvenance.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.candidates = candidates
        self.selectedCandidateIDs = selectedCandidateIDs
    }
}

/// Runtime-only candidate selector policy. This is deliberately separate from
/// `ImageOCREngineID`: a future distributable engine may be supplied by a
/// download or user bundle, while the existing production engine IDs and
/// fusion semantics remain unchanged until a real artifact is approved.
struct ImageOCRSelectorPolicy: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var policyID: String
    var policyVersion: String
    var featureFlagEnabled: Bool
    var baselineEngineID: String
    var candidateEngineID: String
    var candidateMinCalibratedQuality: Double
    var candidateCalibrationProfileID: String
    var candidateMaxWarmLatencyMilliseconds: Double
    var candidateMaxPeakMemoryBytes: Int
    var rollbackFailureThreshold: Int
    var thresholdsFrozen: Bool
    var requestBudgetDelta: Int
    var pixelBudgetDelta: Int
    var storeProvenance: Bool
    var preserveReviewStateOnRollback: Bool

    init(
        policyID: String = "aitrans-image-ocr-candidate-selector",
        policyVersion: String = "v3.285-shadow-1",
        featureFlagEnabled: Bool = false,
        baselineEngineID: String = "bundled-manga-ocr",
        candidateEngineID: String = "candidate-ocr-vl",
        candidateMinCalibratedQuality: Double = 0.78,
        candidateCalibrationProfileID: String = "ocr-calibration-v1",
        candidateMaxWarmLatencyMilliseconds: Double = 250.0,
        candidateMaxPeakMemoryBytes: Int = 268_435_456,
        rollbackFailureThreshold: Int = 1,
        thresholdsFrozen: Bool = true,
        requestBudgetDelta: Int = 0,
        pixelBudgetDelta: Int = 0,
        storeProvenance: Bool = true,
        preserveReviewStateOnRollback: Bool = true,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.featureFlagEnabled = featureFlagEnabled
        self.baselineEngineID = baselineEngineID
        self.candidateEngineID = candidateEngineID
        self.candidateMinCalibratedQuality = candidateMinCalibratedQuality
        self.candidateCalibrationProfileID = candidateCalibrationProfileID
        self.candidateMaxWarmLatencyMilliseconds = candidateMaxWarmLatencyMilliseconds
        self.candidateMaxPeakMemoryBytes = candidateMaxPeakMemoryBytes
        self.rollbackFailureThreshold = rollbackFailureThreshold
        self.thresholdsFrozen = thresholdsFrozen
        self.requestBudgetDelta = requestBudgetDelta
        self.pixelBudgetDelta = pixelBudgetDelta
        self.storeProvenance = storeProvenance
        self.preserveReviewStateOnRollback = preserveReviewStateOnRollback
    }

    var isFailClosed: Bool {
        thresholdsFrozen
            && requestBudgetDelta == 0
            && pixelBudgetDelta == 0
            && storeProvenance
            && preserveReviewStateOnRollback
            && candidateMinCalibratedQuality >= 0
            && candidateMinCalibratedQuality <= 1
            && candidateMaxWarmLatencyMilliseconds > 0
            && candidateMaxPeakMemoryBytes > 0
            && rollbackFailureThreshold >= 1
    }
}

enum ImageOCRSelectorCandidateRole: String, Codable, Sendable {
    case baseline
    case candidate
}

enum ImageOCRSelectorArtifactStatus: String, Codable, Sendable {
    case available
    case missing
    case failed
}

enum ImageOCRSelectorOutputStatus: String, Codable, Sendable {
    case success
    case empty
    case failure
}

enum ImageOCRSelectorCancellationState: String, Codable, Sendable {
    case active
    case cancelRequested
    case cancelled
}

/// Runtime signal accepted by the selector. It intentionally has no
/// ground-truth text or cross-engine raw confidence field.
struct ImageOCRSelectorEngineSignal: Equatable, Codable, Sendable {
    var engineID: String
    var candidateRole: ImageOCRSelectorCandidateRole
    var artifactStatus: ImageOCRSelectorArtifactStatus
    var licenseReviewed: Bool
    var supportedCropVariants: [ImageOCRCropVariant]
    var outputStatus: ImageOCRSelectorOutputStatus
    var hasNonEmptyText: Bool
    var calibratedQuality: Double?
    var calibrationProfileID: String?
    var warmLatencyMilliseconds: Double?
    var peakMemoryBytes: Int?

    init(
        engineID: String,
        candidateRole: ImageOCRSelectorCandidateRole,
        artifactStatus: ImageOCRSelectorArtifactStatus,
        licenseReviewed: Bool,
        supportedCropVariants: [ImageOCRCropVariant],
        outputStatus: ImageOCRSelectorOutputStatus,
        hasNonEmptyText: Bool,
        calibratedQuality: Double? = nil,
        calibrationProfileID: String? = nil,
        warmLatencyMilliseconds: Double? = nil,
        peakMemoryBytes: Int? = nil
    ) {
        self.engineID = engineID
        self.candidateRole = candidateRole
        self.artifactStatus = artifactStatus
        self.licenseReviewed = licenseReviewed
        self.supportedCropVariants = supportedCropVariants
        self.outputStatus = outputStatus
        self.hasNonEmptyText = hasNonEmptyText
        self.calibratedQuality = calibratedQuality
        self.calibrationProfileID = calibrationProfileID
        self.warmLatencyMilliseconds = warmLatencyMilliseconds
        self.peakMemoryBytes = peakMemoryBytes
    }
}

struct ImageOCRSelectorContext: Equatable, Codable, Sendable {
    var cropVariant: ImageOCRCropVariant
    var geometryValid: Bool
    var duplicateRisk: Bool
    var requestBudgetRemaining: Int
    var pixelBudgetRemaining: Int
    var cancellationState: ImageOCRSelectorCancellationState
    var generationMatches: Bool
    var candidateFailureCount: Int

    init(
        cropVariant: ImageOCRCropVariant,
        geometryValid: Bool,
        duplicateRisk: Bool,
        requestBudgetRemaining: Int,
        pixelBudgetRemaining: Int,
        cancellationState: ImageOCRSelectorCancellationState,
        generationMatches: Bool,
        candidateFailureCount: Int
    ) {
        self.cropVariant = cropVariant
        self.geometryValid = geometryValid
        self.duplicateRisk = duplicateRisk
        self.requestBudgetRemaining = requestBudgetRemaining
        self.pixelBudgetRemaining = pixelBudgetRemaining
        self.cancellationState = cancellationState
        self.generationMatches = generationMatches
        self.candidateFailureCount = candidateFailureCount
    }
}

enum ImageOCRSelectorSelectionReason: String, Codable, Sendable {
    case baselineDefault
    case candidateShadowEligible
    case rollbackToBaseline
    case noEngineAvailable
}

struct ImageOCRSelectorDecision: Equatable, Codable, Sendable {
    var selectedEngineID: String?
    var selectionReason: ImageOCRSelectorSelectionReason
    var candidateConsidered: Bool
    var candidateAccepted: Bool
    var fallbackReasons: [String]
    var rollbackApplied: Bool
    var storeProvenance: Bool
    var reviewStatePreserved: Bool
    var requestBudgetDelta: Int
    var pixelBudgetDelta: Int
}

/// Pure policy core for a later controlled rollout. No current OCR caller
/// invokes this helper; keeping it isolated makes the v3.285 boundary
/// testable without changing the existing recognition/fusion path.
enum ImageOCREngineSelector {
    static func select(
        policy: ImageOCRSelectorPolicy,
        context: ImageOCRSelectorContext,
        baseline: ImageOCRSelectorEngineSignal,
        candidate: ImageOCRSelectorEngineSignal
    ) -> ImageOCRSelectorDecision {
        var rejectionReasons: [String] = []
        if !policy.isFailClosed { rejectionReasons.append("unsafePolicy") }
        if baseline.engineID != policy.baselineEngineID || baseline.candidateRole != .baseline {
            rejectionReasons.append("baselineIdentityMismatch")
        }
        if candidate.engineID != policy.candidateEngineID || candidate.candidateRole != .candidate {
            rejectionReasons.append("candidateIdentityMismatch")
        }
        if !policy.featureFlagEnabled { rejectionReasons.append("featureFlagDisabled") }
        if candidate.artifactStatus != .available { rejectionReasons.append("candidateArtifactUnavailable") }
        if !candidate.licenseReviewed { rejectionReasons.append("candidateLicenseNotReviewed") }
        if !candidate.supportedCropVariants.contains(context.cropVariant) { rejectionReasons.append("cropRoleUnsupported") }
        if !context.geometryValid { rejectionReasons.append("geometryInvalid") }
        if context.duplicateRisk { rejectionReasons.append("duplicateRisk") }
        if context.requestBudgetRemaining <= 0 { rejectionReasons.append("requestBudgetExhausted") }
        if context.pixelBudgetRemaining <= 0 { rejectionReasons.append("pixelBudgetExhausted") }
        if context.cancellationState != .active { rejectionReasons.append("cancelledOrCancelRequested") }
        if !context.generationMatches { rejectionReasons.append("staleGeneration") }
        if context.candidateFailureCount >= policy.rollbackFailureThreshold {
            rejectionReasons.append("rollbackFailureThresholdReached")
        }
        if candidate.outputStatus != .success || !candidate.hasNonEmptyText {
            rejectionReasons.append("candidateOutputUnavailable")
        }
        if let quality = candidate.calibratedQuality {
            if !quality.isFinite || quality < 0 || quality > 1 {
                rejectionReasons.append("calibratedQualityInvalid")
            } else if quality < policy.candidateMinCalibratedQuality {
                rejectionReasons.append("candidateQualityBelowThreshold")
            } else if candidate.calibrationProfileID != policy.candidateCalibrationProfileID {
                rejectionReasons.append("calibrationProfileMismatch")
            }
        } else {
            rejectionReasons.append("calibratedQualityUnavailable")
        }
        if let warmLatency = candidate.warmLatencyMilliseconds {
            if warmLatency > policy.candidateMaxWarmLatencyMilliseconds {
                rejectionReasons.append("candidateWarmLatencyExceeded")
            }
        } else {
            rejectionReasons.append("candidateWarmLatencyUnavailable")
        }
        if let peakMemory = candidate.peakMemoryBytes {
            if peakMemory > policy.candidateMaxPeakMemoryBytes {
                rejectionReasons.append("candidatePeakMemoryExceeded")
            }
        } else {
            rejectionReasons.append("candidatePeakMemoryUnavailable")
        }

        let baselineAvailable = baseline.engineID == policy.baselineEngineID
            && baseline.candidateRole == .baseline
            && baseline.artifactStatus == .available
            && baseline.licenseReviewed
            && baseline.supportedCropVariants.contains(context.cropVariant)
        let candidateAccepted = rejectionReasons.isEmpty && baselineAvailable
        let rollbackApplied = context.candidateFailureCount >= policy.rollbackFailureThreshold
            || context.cancellationState != .active
            || !context.generationMatches

        if candidateAccepted {
            return ImageOCRSelectorDecision(
                selectedEngineID: policy.candidateEngineID,
                selectionReason: .candidateShadowEligible,
                candidateConsidered: true,
                candidateAccepted: true,
                fallbackReasons: [],
                rollbackApplied: false,
                storeProvenance: policy.storeProvenance,
                reviewStatePreserved: policy.preserveReviewStateOnRollback,
                requestBudgetDelta: 0,
                pixelBudgetDelta: 0
            )
        }

        if baselineAvailable {
            return ImageOCRSelectorDecision(
                selectedEngineID: policy.baselineEngineID,
                selectionReason: rollbackApplied ? .rollbackToBaseline : .baselineDefault,
                candidateConsidered: true,
                candidateAccepted: false,
                fallbackReasons: rejectionReasons,
                rollbackApplied: rollbackApplied,
                storeProvenance: policy.storeProvenance,
                reviewStatePreserved: policy.preserveReviewStateOnRollback,
                requestBudgetDelta: 0,
                pixelBudgetDelta: 0
            )
        }

        rejectionReasons.append("baselineUnavailable")
        return ImageOCRSelectorDecision(
            selectedEngineID: nil,
            selectionReason: .noEngineAvailable,
            candidateConsidered: true,
            candidateAccepted: false,
            fallbackReasons: rejectionReasons,
            rollbackApplied: rollbackApplied,
            storeProvenance: policy.storeProvenance,
            reviewStatePreserved: policy.preserveReviewStateOnRollback,
            requestBudgetDelta: 0,
            pixelBudgetDelta: 0
        )
    }
}
