# v3.287 clean-text model comparison (contract-only)

This directory defines the comparison envelope for the next translation
stage. Every model must consume the same clean-text case IDs, including
Japanese→Simplified Chinese, Japanese→English, and English→Simplified
Chinese. OCR-corrupted inputs are intentionally excluded from this stage.

The committed corpus, model identities, outputs, and measurements are
synthetic contract data. They exercise identity, coverage, nearest-rank
percentiles, cold/warm separation, context-overflow reporting, and the
fail-closed promotion gate. They are not downloadable model artifacts,
license approval, device measurements, translation quality, or a reason to
replace the current product model.

The Gemma 270M row is explicitly a floor. Candidate rows remain disabled and
the comparison report must keep `productSelectionChanged=false`.
