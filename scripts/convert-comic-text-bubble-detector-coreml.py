#!/usr/bin/env python3
"""Convert Koharu's comic text/bubble RT-DETR-v2 model to INT8 Core ML."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
import numpy as np
import torch
from torch import nn
from transformers import RTDetrV2ForObjectDetection
from transformers.models.rt_detr_v2.modeling_rt_detr_v2 import RTDetrV2Model


MODEL_ID = "ogkalu/comic-text-and-bubble-detector"
MODEL_REVISION = "16e8a622f91fabc6b5b65c96d32d1183f8843546"
IMAGE_SIZE = 640


def functional_generate_anchors(
    self: RTDetrV2Model,
    spatial_shapes=None,
    grid_size=0.05,
    device="cpu",
    dtype=torch.float32,
):
    """Equivalent anchor math without trace-hostile in-place view writes."""
    if spatial_shapes is None:
        spatial_shapes = [
            [
                int(self.config.anchor_image_size[0] / stride),
                int(self.config.anchor_image_size[1] / stride),
            ]
            for stride in self.config.feat_strides
        ]
    anchors = []
    for level, (height, width) in enumerate(spatial_shapes):
        grid_y, grid_x = torch.meshgrid(
            torch.arange(end=height, device=device).to(dtype),
            torch.arange(end=width, device=device).to(dtype),
            indexing="ij",
        )
        # Transformers 4.56.2 mutates two grid_xy views in place here. The
        # functional stack is numerically identical and survives TorchScript.
        grid_xy = torch.stack(
            (
                (grid_x + 0.5) / width,
                (grid_y + 0.5) / height,
            ),
            -1,
        ).unsqueeze(0)
        wh = torch.ones_like(grid_xy) * grid_size * (2.0**level)
        anchors.append(
            torch.concat([grid_xy, wh], -1).reshape(-1, height * width, 4)
        )
    anchors = torch.concat(anchors, 1)
    epsilon = 1e-2
    valid_mask = ((anchors > epsilon) * (anchors < 1 - epsilon)).all(
        -1,
        keepdim=True,
    )
    anchors = torch.log(anchors / (1 - anchors))
    anchors = torch.where(
        valid_mask,
        anchors,
        torch.tensor(torch.finfo(dtype).max, dtype=dtype, device=device),
    )
    return anchors, valid_mask


class Detector(nn.Module):
    def __init__(self, model: RTDetrV2ForObjectDetection) -> None:
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        output = self.model(pixel_values=image)
        return output.logits, output.pred_boxes


def convert(model: RTDetrV2ForObjectDetection) -> ct.models.MLModel:
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    with torch.inference_mode():
        traced = torch.jit.trace(Detector(model).eval(), example, strict=False)
    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, IMAGE_SIZE, IMAGE_SIZE),
                scale=1 / 255,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[
            ct.TensorType(name="logits", dtype=np.float32),
            ct.TensorType(name="pred_boxes", dtype=np.float32),
        ],
    )
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int8",
        )
    )
    return linear_quantize_weights(converted, config=config)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=MODEL_ID)
    parser.add_argument("--revision", default=MODEL_REVISION)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.output.exists():
        raise SystemExit(f"output already exists: {args.output}")
    args.output.mkdir(parents=True)

    # Apply before from_pretrained(), because fixed-size anchors are generated
    # during RTDetrV2Model initialization.
    RTDetrV2Model.generate_anchors = functional_generate_anchors
    model = RTDetrV2ForObjectDetection.from_pretrained(
        args.model,
        revision=args.revision,
    ).eval()
    converted = convert(model)
    converted.save(args.output / "ComicTextBubbleDetectorINT8.mlpackage")
    (args.output / "conversion.json").write_text(
        json.dumps(
            {
                "source": args.model,
                "revision": args.revision,
                "architecture": "RT-DETR-v2 R50",
                "input": "RGB 640x640, scale=1/255",
                "outputs": ["logits[1,300,3]", "pred_boxes[1,300,4]"],
                "labels": ["bubble", "text_bubble", "text_free"],
                "textConfidenceThreshold": 0.30,
                "computePrecision": "float16",
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
