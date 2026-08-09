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


def convert_encoder(model: VisionEncoderDecoderModel) -> ct.models.MLModel:
    example = torch.rand(1, 3, 224, 224)
    with torch.inference_mode():
        traced = torch.jit.trace(Encoder(model.encoder).eval(), example, strict=False)
    return ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.TensorType(
                name="pixel_values",
                shape=(1, 3, 224, 224),
                dtype=np.float32,
            )
        ],
        outputs=[
            ct.TensorType(name="encoder_hidden_states", dtype=np.float32)
        ],
    )


def convert_decoder(model: VisionEncoderDecoderModel) -> ct.models.MLModel:
    input_ids = torch.tensor([[2, 10, 20, 30]], dtype=torch.int64)
    hidden_states = torch.rand(1, 197, 768)
    with torch.inference_mode():
        traced = torch.jit.trace(
            Decoder(model.decoder).eval(),
            (input_ids, hidden_states),
            strict=False,
        )
    sequence = ct.RangeDim(lower_bound=1, upper_bound=300, default=4)
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
                shape=(1, sequence),
                dtype=np.int32,
            ),
            ct.TensorType(
                name="encoder_hidden_states",
                shape=(1, 197, 768),
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.output.exists():
        if not args.force:
            raise SystemExit(f"output already exists: {args.output}")
        shutil.rmtree(args.output)
    args.output.mkdir(parents=True)

    model = VisionEncoderDecoderModel.from_pretrained(
        args.model,
        revision=args.revision,
    ).eval()
    encoder = quantize(convert_encoder(model))
    decoder = quantize(convert_decoder(model))
    encoder.save(args.output / "MangaOCREncoderINT8.mlpackage")
    decoder.save(args.output / "MangaOCRDecoderINT8.mlpackage")

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
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
