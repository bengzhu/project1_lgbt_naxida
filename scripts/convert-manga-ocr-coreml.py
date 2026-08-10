#!/usr/bin/env python3
"""Convert kha-white Manga OCR into the two INT8 Core ML packages used by AITRANS."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
import numpy as np
import torch
from torch import nn
from transformers import VisionEncoderDecoderModel


MODEL_ID = "kha-white/manga-ocr-base"
MODEL_REVISION = "aa6573bd10b0d446cbf622e29c3e084914df9741"


class Encoder(nn.Module):
    def __init__(self, encoder: nn.Module) -> None:
        super().__init__()
        self.encoder = encoder

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.encoder(pixel_values, return_dict=False)[0]


class BatchSafeViTEmbeddings(nn.Module):
    """Keep CLS-token broadcasting legal for Core ML flexible batch shapes."""

    def __init__(self, source: nn.Module) -> None:
        super().__init__()
        self.cls_token = source.cls_token
        self.mask_token = source.mask_token
        self.patch_embeddings = source.patch_embeddings
        self.position_embeddings = source.position_embeddings
        self.dropout = source.dropout

    def forward(
        self,
        pixel_values: torch.Tensor,
        bool_masked_pos: torch.Tensor | None = None,
        interpolate_pos_encoding: bool = False,
    ) -> torch.Tensor:
        batch_size, _, _, _ = pixel_values.shape
        embeddings = self.patch_embeddings(
            pixel_values,
            interpolate_pos_encoding=interpolate_pos_encoding,
        )
        if bool_masked_pos is not None:
            sequence_length = embeddings.shape[1]
            mask_tokens = self.mask_token * torch.ones(
                (batch_size, sequence_length, 1),
                dtype=self.mask_token.dtype,
                device=self.mask_token.device,
            )
            mask = bool_masked_pos.unsqueeze(-1).type_as(mask_tokens)
            embeddings = embeddings * (1.0 - mask) + mask_tokens * mask

        cls_tokens = self.cls_token * torch.ones(
            (batch_size, 1, 1),
            dtype=self.cls_token.dtype,
            device=self.cls_token.device,
        )
        embeddings = torch.cat((cls_tokens, embeddings), dim=1)
        embeddings = embeddings + self.position_embeddings
        return self.dropout(embeddings)


def make_batch_safe_encoder(encoder: nn.Module) -> nn.Module:
    encoder.embeddings = BatchSafeViTEmbeddings(encoder.embeddings)
    return encoder


class Decoder(nn.Module):
    def __init__(self, decoder: nn.Module) -> None:
        super().__init__()
        self.decoder = decoder

    def forward(
        self,
        input_ids: torch.Tensor,
        encoder_hidden_states: torch.Tensor,
    ) -> torch.Tensor:
        logits = self.decoder(
            input_ids=input_ids,
            encoder_hidden_states=encoder_hidden_states,
            return_dict=False,
        )[0]
        return logits[:, -1, :]


def coreml_batch_dimension(batch_size: int) -> int | ct.RangeDim:
    """Keep the legacy scalar helper for the single-crop conversion path."""
    if batch_size == 1:
        return 1
    return ct.RangeDim(
        lower_bound=1,
        upper_bound=batch_size,
        default=min(batch_size, 4),
    )


def coreml_batch_shape(
    batch_size: int,
    trailing_shape: tuple[int | ct.RangeDim, ...],
    default_trailing_shape: tuple[int, ...] | None = None,
) -> tuple[int | ct.RangeDim, ...] | ct.EnumeratedShapes:
    """Specialize each valid batch to avoid dynamic ViT tile repetition."""
    if batch_size == 1:
        return (1, *trailing_shape)
    default_tail = default_trailing_shape or tuple(
        dimension.default if isinstance(dimension, ct.RangeDim) else dimension
        for dimension in trailing_shape
    )
    shapes = [(batch, *trailing_shape) for batch in range(1, batch_size + 1)]
    return ct.EnumeratedShapes(
        shapes=shapes,
        default=(min(batch_size, 4), *default_tail),
    )


def convert_encoder(
    model: VisionEncoderDecoderModel,
    batch_size: int,
) -> ct.models.MLModel:
    example = torch.rand(batch_size, 3, 224, 224)
    batch_dimension = coreml_batch_dimension(batch_size)
    batch_shape = coreml_batch_shape(batch_size, (3, 224, 224))
    with torch.inference_mode():
        traced = torch.jit.trace(
            Encoder(make_batch_safe_encoder(model.encoder).eval()).eval(),
            example,
            strict=False,
        )
    return ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.TensorType(
                name="pixel_values",
                shape=batch_shape,
                dtype=np.float32,
            )
        ],
        outputs=[
            ct.TensorType(name="encoder_hidden_states", dtype=np.float32)
        ],
    )


def convert_decoder(
    model: VisionEncoderDecoderModel,
    batch_size: int,
) -> ct.models.MLModel:
    input_ids = torch.tensor(
        [[2, 10, 20, 30] for _ in range(batch_size)],
        dtype=torch.int64,
    )
    hidden_states = torch.rand(batch_size, 197, 768)
    sequence = ct.RangeDim(lower_bound=1, upper_bound=300, default=4)
    batch_dimension = coreml_batch_dimension(batch_size)
    with torch.inference_mode():
        traced = torch.jit.trace(
            Decoder(model.decoder).eval(),
            (input_ids, hidden_states),
            strict=False,
        )
    # Decoder math stays FP32 because the BERT causal-mask sentinel overflows
    # FP16. Constants are quantized separately after conversion.
    return ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
        inputs=[
            ct.TensorType(
                name="input_ids",
                shape=(batch_dimension, sequence),
                dtype=np.int32,
            ),
            ct.TensorType(
                name="encoder_hidden_states",
                shape=(batch_dimension, 197, 768),
                dtype=np.float32,
            ),
        ],
        outputs=[ct.TensorType(name="next_token_logits", dtype=np.float32)],
    )


def quantize(model: ct.models.MLModel) -> ct.models.MLModel:
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int8",
        )
    )
    return linear_quantize_weights(model, config=config)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=MODEL_ID)
    parser.add_argument("--revision", default=MODEL_REVISION)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace an existing output directory",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1,
        help="upper bound for the optional flexible batch model (1 keeps legacy shapes)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.output.exists():
        if not args.force:
            raise SystemExit(f"output already exists: {args.output}")
        shutil.rmtree(args.output)
    if not 1 <= args.batch_size <= 16:
        raise SystemExit("--batch-size must be between 1 and 16")
    args.output.mkdir(parents=True)

    model = VisionEncoderDecoderModel.from_pretrained(
        args.model,
        revision=args.revision,
    ).eval()
    encoder = quantize(convert_encoder(model, args.batch_size))
    decoder = quantize(convert_decoder(model, args.batch_size))
    suffix = "" if args.batch_size == 1 else "Batch"
    encoder.save(args.output / f"MangaOCREncoderINT8{suffix}.mlpackage")
    decoder.save(args.output / f"MangaOCRDecoderINT8{suffix}.mlpackage")

    from huggingface_hub import hf_hub_download

    vocabulary = Path(
        hf_hub_download(args.model, "vocab.txt", revision=args.revision)
    )
    shutil.copy2(vocabulary, args.output / "MangaOCRVocab.txt")
    (args.output / "conversion.json").write_text(
        json.dumps(
            {
                "source": args.model,
                "revision": args.revision,
                "encoderComputePrecision": "float16",
                "decoderComputePrecision": "float32",
                "weightQuantization": "linear-symmetric-int8",
                "minimumDeploymentTarget": "iOS17",
                "batchSize": args.batch_size,
                "flexibleBatch": args.batch_size > 1,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
