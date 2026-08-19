# v3.285 GT-isolated OCR selector protocol

This protocol describes the smallest safe boundary for a future distributable
OCR candidate. It is shadow-only until v3.284 artifact/resource evidence and
the v3.285 holdout gates are complete.

The selector may read only runtime facts:

- engine artifact availability and reviewed distribution capability;
- crop role support, geometry validity and duplicate-risk signals;
- the candidate's calibrated, engine-local quality signal and calibration profile;
- warm latency, peak memory, request/pixel budget remaining, cancellation and
  request-generation state.

It does not receive ground truth text, ground-truth labels, benchmark filenames, expected region
counts, CER, holdout labels or raw confidence values from another engine.
Raw confidence is never compared across engines. A candidate must pass a frozen
calibration profile and resource limits, while the bundled Manga OCR engine
remains the immediate fallback.

Every decision emits selection provenance. Candidate rejection, cancellation,
stale generation, duplicate risk, geometry failure and budget exhaustion retain
the baseline result and review state; selector deltas for request and pixel
budgets are always zero.

The `evidenceGate` is report-only and cannot change a per-block decision. A
controlled rollout requires a policy frozen on train/dev before one holdout
evaluation, no post-hoc holdout tuning, complete output/duplicate/omission/order,
cancellation, memory and rollback evidence, and an authorized corpus. The
contract fixture intentionally remains blocked and keeps the feature flag off.
