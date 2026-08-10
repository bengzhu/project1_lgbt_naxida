# Manga OCR model notice

The bundled Core ML encoder and decoder, including the flexible-batch pair,
are converted from
`kha-white/manga-ocr-base` at revision
`aa6573bd10b0d446cbf622e29c3e084914df9741`.

Source: https://huggingface.co/kha-white/manga-ocr-base

The original model is licensed under Apache License 2.0. See
`LICENSE-APACHE` in this directory. AITRANS converts the encoder to FP16,
keeps decoder operations in FP32, and linearly quantizes constant weights to
INT8 for on-device Core ML inference. No original model weights are modified
during application runtime.
