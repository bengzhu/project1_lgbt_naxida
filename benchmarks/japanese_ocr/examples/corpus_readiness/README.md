# Shared corpus readiness envelope

This directory contains only a contract example. It is not an authorized
dataset, a ground-truth source, a prediction artifact, or a holdout result.

The v3.292 evaluator keeps the gate `blocked` until all of the following are
provided outside the repository and frozen before any holdout is opened:

- an authorized dataset with a stable SHA-256 and permitted uses;
- at least 20 complete pages and 150 annotated TextRegions with polygon/line,
  direction, exact source text, reading order, bubble association, and text
  type fields;
- disjoint train/dev/holdout asset IDs;
- the same oracle-crop, detected-crop, and full-page matrix for AITRANS,
  Vision, Koharu MIT48, and Koharu PaddleOCR-VL reference rows;
- a protocol SHA frozen before holdout, with no post-hoc holdout tuning.

The report can become `readyForHoldout`, but it never enables product OCR or
translation selection and never consumes ground truth for runtime decisions.
