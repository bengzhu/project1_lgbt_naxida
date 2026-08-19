# Japanese translation benchmark (v3.280)

This is the translation-side companion to the Japanese OCR benchmark. It
separates `cleanSource` from `ocrCorrupted` input so a translation model is
not blamed for an OCR error, and it keeps automatic QA separate from human
judgement. The v3.280 fixture is a contract example only; it is not a claim
about Gemma 270M, Koharu, or any other model's translation quality.

The scorer's automatic gates cover tagged-block completeness, missing/extra/
duplicate/out-of-order tags, source leakage, target-language density, and
length limits. Accuracy, fluency, character voice, terminology, omission,
and bubble-fit quality require a separate blind human review and are never
inferred from BLEU or script density.

Each fixture carries an exact source-input SHA and a split. A clean/corrupted
pair shares `pairedFixtureID`, but the two inputs remain separate evaluation
rows. Predictions must identify the model, prompt template, decoding
parameters, provider, license, and app SHA. The scorer has no access from the
production translation path to these fixtures.

## Local GGUF model profiles (v3.286)

`schema/model-profile-manifest.schema.json` records the identity needed before
comparing a local model: exact GGUF filename and SHA-256, quantization,
license review, template source/template SHA, decoding profile, context and
the existing eight-block/1,800-character image batch ceiling. The committed
`examples/model_profiles/manifest.json` is synthetic and contract-only.

Production rendering starts with message-level system/user/assistant content,
then uses the model's embedded `llama_model_chat_template` through
`llama_chat_apply_template`. Only an explicitly selected known Gemma profile
may render the legacy fallback; missing or unknown Qwen/Sakura templates are
rejected rather than silently converted to ChatML. This protocol does not
replace the default model or claim translation quality.

## Clean-text model comparison (v3.287)

`schema/model-comparison-*.schema.json` and `examples/model_comparison/`
define the next comparison envelope. It requires the same clean-text cases
for Japanese→Simplified Chinese, Japanese→English, and English→Simplified
Chinese across a Gemma 270M floor and disabled candidate profiles. Each model
row records GGUF identity, quantization, license/template metadata, context,
and decoding; each measurement records cold/warm state, latency, first-token
time, peak memory, and context overflow.

The committed envelope is contract-only. Its report must remain blocked until
real model artifacts, authorization, holdout data, human review, and target
device measurements exist. Synthetic output or percentiles never select a
product model.

## Translation context and QA boundary (v3.288)

`schema/translation-context-qa-*.schema.json` and
`examples/translation_context_qa/` define the context contract used by the
image manga batch path. Confirmed terminology, person names, and addressing
entries are distinct from candidate/revoked entries. A completed previous
batch may contribute a read-only summary to the next prompt, but it cannot add
input blocks or output tags.

The block QA envelope rejects extra/duplicate/out-of-order tags and checks
source leakage, numbers, confirmed terms, target-language density, and output
length. A failure retries only the failed block and preserves completed/partial
state; it never reruns OCR or the whole page. The fixture is synthetic and its
report stays blocked/not eligible until real model, authorized corpus, human
review, and target-device evidence exist.

```text
python3 scripts/evaluate-japanese-translation-benchmark.py \
  --manifest benchmarks/japanese_translation/examples/minimal/manifest.json \
  --predictions benchmarks/japanese_translation/examples/minimal/predictions.json \
  --output /tmp/japanese-translation-report.json
```
