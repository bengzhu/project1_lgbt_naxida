# v3.284 distributable OCR candidate shadow evaluation

The v3.284 evaluator compares a declared baseline and candidate on the exact
same crop keys used by the v3.282 multi-engine boundary. It imports the
existing deterministic CER/exact-match scorer, then adds an explicit resource
and license matrix:

- model and artifact SHA, size, quantization, source, license, and distribution
  policy;
- cold/warm latency samples with deterministic p50/p95 calculation;
- peak memory and energy, or an explicit partial/missing reason;
- platform, hardware, OS, runtime, target-device flag, and reference-only
  status;
- default-enabled/product-selection invariants.

Unavailable artifacts or incomplete measurements block the report; they are
never replaced by synthetic timings or inferred license claims. The wrapper is
cloud-only and only aggregates caller-provided envelopes. This stage does not
change AITRANS's bundled Manga OCR, default selection, translation model,
request budgets, UI, or renderer.
