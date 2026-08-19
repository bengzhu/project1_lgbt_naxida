# Local GGUF model profile fixtures (v3.286)

`manifest.json` is a contract-only record of the fields required before a
local GGUF profile can be compared: exact filename, SHA-256, quantization,
license review, embedded-template source, decoding profile, context and the
existing eight-block/1,800-character image batch ceiling.

The three rows are synthetic fixtures. They do not identify a downloadable
model, prove a license, or claim Qwen/Sakura quality. A missing template may
use only an explicitly approved known fallback; an unknown profile is recorded
as rejected and never silently converted to ChatML.
