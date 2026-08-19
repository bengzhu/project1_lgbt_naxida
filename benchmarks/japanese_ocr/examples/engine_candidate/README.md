# Distributable OCR candidate shadow contract example

This is a synthetic v3.284 envelope. It demonstrates how a future OCR
candidate must declare model/artifact identity, source/runtime revision,
license, distribution policy, quantization, artifact size, same-crop output,
and target-device resource measurements.

The candidate artifact is deliberately missing. Its rows remain explicit
failures, and the evaluator must report `blocked`. The baseline resource row
also leaves energy unavailable with an explicit reason, so this fixture cannot
pretend to contain a complete resource matrix. `contractExampleOnly` remains
true and no product selector may consume this report.

Real candidate runs must use an authorized corpus and an immutable artifact
envelope. A model is not eligible for bundling merely because its OCR text is
better on an oracle crop; detected-crop/full-page evidence, license, package
size, peak memory, latency, energy, and a target-device run must all be
reported before the route can proceed to v3.285.
