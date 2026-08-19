# Native line/TextRegion shadow evaluation

v3.283 defines a shadow-only protocol for measuring a future native
TextRegion/line geometry signal against the same annotated corpus used by the
Japanese OCR benchmark. The evaluator reports region and line IoU recall,
precision, duplicate/omission, cross-region merge, cut-candidate, direction,
reading-order, orphan-line, and candidate-budget evidence.

The protocol is intentionally fail-closed:

- candidates cannot identify ground-truth regions;
- every manifest page needs an explicit success, empty, or failure status;
- region and line budgets are declared and checked;
- contract-only and legacy fixtures produce `insufficientCorpus` and never a
  promotion-quality claim;
- no shadow geometry is imported by `AITRANS/` or used for product selection.

The cloud wrapper only aggregates a caller-provided signal JSON. It does not
download or build an OCR model. The first real run must use an authorized
corpus and remain a reference/shadow artifact until frozen holdout evidence
meets the later route requirements.
