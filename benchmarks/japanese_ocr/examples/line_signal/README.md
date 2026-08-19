# Native line/TextRegion shadow contract example

This directory contains a deliberately synthetic, contract-only signal run.
It exercises the v3.283 input boundary against the repository `test/jap.jpg`
asset, but it is not a human-annotated corpus and is not evidence of general
Japanese OCR or translation quality.

The candidate rows are independent geometry observations. They do not carry
ground-truth region IDs, and the evaluator rejects such leakage. The report is
expected to remain `insufficientCorpus`; it must not enable or alter product
OCR selection, Vision fallback, OCR budgets, translation, layout, or rendering.

Real native TextRegion/line output must be supplied through an authorized
cloud-only job with immutable dataset, app, engine, model, device, and license
metadata before any holdout comparison is considered.
