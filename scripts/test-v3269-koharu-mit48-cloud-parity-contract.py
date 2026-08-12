#!/usr/bin/env python3
"""Static contract for the cloud-only Koharu MIT48 reference parity gate."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuMit48CloudParityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = read("scripts/validate-koharu-mit48px-artifact.py")
        cls.smoke = read("scripts/run-koharu-mit48px-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/koharu-mit48-parity.yml")
        cls.ci_workflow = read(".github/workflows/ci-results.yml")
        cls.reference = read("reference/koharu-main/koharu-ml/src/mit48px_ocr/mod.rs")
        cls.license = read("reference/koharu-main/LICENSE")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_artifact_identity_is_pinned_and_not_the_bundled_manga_model(self) -> None:
        for marker in [
            'HF_REPO = "mayocream/mit48px-ocr"',
            'HF_REVISION = "205395b155a041b068fd754a6e417cd71b4cb1de"',
            '"config.json"',
            '"alphabet-all-v7.txt"',
            '"model.safetensors"',
            '"README.md"',
            '"model.safetensors": 263375432',
            '"alphabet-all-v7.txt": 186651',
            '"config.json": 334',
            'hf_hub_download(',
            '"bundledInAITRANS": False',
        ]:
            self.assertIn(marker, self.validator)
        self.assertNotIn("MangaOCRDecoderINT8", self.validator)

    def test_reference_config_and_license_boundary_are_recorded(self) -> None:
        for marker in [
            '"text_height": 48',
            '"max_width": 8100',
            '"embd_dim": 320',
            '"encoder_layers": 4',
            '"decoder_layers": 5',
            '"beam_size_default": 5',
            '"max_seq_length_default": 255',
            '"pad_token_id": 0',
            '"bos_token_id": 1',
            '"eos_token_id": 2',
            '"space_token": "<SP>"',
            '"dictionary_file": "alphabet-all-v7.txt"',
        ]:
            self.assertIn(marker, self.validator)
        for marker in [
            "const OCR_CHUNK_SIZE: usize = 16",
            "pub fn load_from_dir",
            "pub fn inference_regions",
            "FilterType::Triangle",
            "127.5",
        ]:
            self.assertIn(marker, self.reference)
        self.assertTrue(
            "GNU GENERAL PUBLIC LICENSE" in self.license
            or "GPL-3.0-only" in self.license
        )
        self.assertIn('"modelLicense": "GPL-3.0"', self.validator)

    def test_cloud_smoke_uses_fixed_japanese_line_crops_and_cpu_reference_binary(self) -> None:
        for marker in [
            'GITHUB_ACTIONS:-',
            'test/jap.jpg',
            'rotate(270, expand=True)',
            'cargo build',
            'mit48px-ocr',
            '--model-dir',
            '--json-output',
            '--cpu',
            'japanese_density',
            'density >= 0.5',
            'no nonempty Japanese crop output',
        ]:
            self.assertIn(marker, self.smoke)
        self.assertNotIn("xcodebuild", self.smoke)

    def test_workflow_is_manual_cloud_only_and_never_uploads_weights(self) -> None:
        for marker in [
            "workflow_dispatch:",
            "runs-on: ubuntu-24.04",
            "actions/checkout@v4",
            "actions/setup-python@v5",
            "dtolnay/rust-toolchain@stable",
            '"huggingface_hub<1"',
            '"Pillow>=10,<12"',
            "bash scripts/run-koharu-mit48px-cloud-smoke.sh",
            "actions/upload-artifact@v4",
            "${{ runner.temp }}/koharu-mit48-output",
        ]:
            self.assertIn(marker, self.workflow)
        self.assertNotIn("model.safetensors", self.workflow)
        self.assertNotIn("koharu-mit48-model", self.workflow.split("Upload parity evidence", 1)[-1])

    def test_ci_contract_route_and_version(self) -> None:
        current = "python3 -B scripts/test-v3269-koharu-mit48-cloud-parity-contract.py"
        self.assertIn(current, self.ci_workflow)
        self.assertIn(
            "if grep -Fx 'scripts/test-v3269-koharu-mit48-cloud-parity-contract.py'",
            self.ci_workflow,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.269", "3.269"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
