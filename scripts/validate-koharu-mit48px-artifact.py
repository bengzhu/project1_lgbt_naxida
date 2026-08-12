#!/usr/bin/env python3
"""Validate the pinned Koharu MIT48px model package.

This validator is intentionally usable only by the cloud parity workflow.  It
does not add the GPL model to the iOS target and it never treats the existing
Apache Manga OCR package as an MIT48 substitute.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
from typing import Any


HF_REPO = "mayocream/mit48px-ocr"
HF_REVISION = "205395b155a041b068fd754a6e417cd71b4cb1de"
REQUIRED_FILES = (
    "config.json",
    "alphabet-all-v7.txt",
    "model.safetensors",
    "README.md",
)
EXACT_SIZES = {
    "config.json": 334,
    "alphabet-all-v7.txt": 186651,
    "model.safetensors": 263375432,
}
EXPECTED_CONFIG = {
    "text_height": 48,
    "max_width": 8100,
    "embd_dim": 320,
    "num_heads": 4,
    "encoder_layers": 4,
    "decoder_layers": 5,
    "beam_size_default": 5,
    "max_seq_length_default": 255,
    "pad_token_id": 0,
    "bos_token_id": 1,
    "eos_token_id": 2,
    "space_token": "<SP>",
    "dictionary_file": "alphabet-all-v7.txt",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_files(root: Path) -> None:
    try:
        from huggingface_hub import hf_hub_download
    except ImportError as error:  # pragma: no cover - exercised in CI setup
        raise SystemExit("huggingface_hub is required for --download") from error

    root.mkdir(parents=True, exist_ok=True)
    for filename in REQUIRED_FILES:
        downloaded = Path(
            hf_hub_download(
                repo_id=HF_REPO,
                filename=filename,
                revision=HF_REVISION,
                local_dir=str(root),
            )
        )
        destination = root / filename
        if downloaded.resolve() != destination.resolve():
            shutil.copyfile(downloaded, destination)


def validate(root: Path) -> dict[str, Any]:
    files: dict[str, dict[str, Any]] = {}
    for filename in REQUIRED_FILES:
        path = root / filename
        if not path.is_file():
            raise AssertionError(f"missing MIT48 artifact: {path}")
        entry: dict[str, Any] = {
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        }
        expected_size = EXACT_SIZES.get(filename)
        if expected_size is not None and entry["bytes"] != expected_size:
            raise AssertionError(
                f"unexpected {filename} size: {entry['bytes']} != {expected_size}"
            )
        files[filename] = entry

    config = json.loads((root / "config.json").read_text(encoding="utf-8"))
    for key, expected in EXPECTED_CONFIG.items():
        actual = config.get(key)
        if actual != expected:
            raise AssertionError(f"config.{key}: {actual!r} != {expected!r}")

    dictionary = (root / "alphabet-all-v7.txt").read_text(encoding="utf-8")
    tokens = dictionary.splitlines()
    if len(tokens) <= 1000:
        raise AssertionError(f"dictionary is unexpectedly small: {len(tokens)}")
    for token in ("<S>", "</S>", "<SP>"):
        if token not in tokens:
            raise AssertionError(f"dictionary is missing required token {token}")

    model_readme = (root / "README.md").read_text(encoding="utf-8").lower()
    if "gpl-3.0" not in model_readme and "gnu general public license" not in model_readme:
        raise AssertionError("MIT48 model README does not declare GPL-3.0")

    reference_license = Path(__file__).resolve().parents[1] / "reference/koharu-main/LICENSE"
    license_text = reference_license.read_text(encoding="utf-8").lower()
    if "gpl-3.0-only" not in license_text and "gnu general public license" not in license_text:
        raise AssertionError("Koharu reference GPL license marker is missing")

    return {
        "status": "success",
        "repo": HF_REPO,
        "revision": HF_REVISION,
        "files": files,
        "config": config,
        "dictionaryTokenCount": len(tokens),
        "modelLicense": "GPL-3.0",
        "referenceLicense": "GPL-3.0-only",
        "bundledInAITRANS": False,
        "runtime": "reference/koharu-main/koharu-ml/bin/mit48px-ocr.rs",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--json-output", type=Path, required=True)
    args = parser.parse_args()

    if args.download:
        download_files(args.root)
    report = validate(args.root)
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, json.JSONDecodeError) as error:
        print(f"MIT48 artifact validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
