#!/usr/bin/env python3
"""Contract for parsing batch Manga OCR runtime records separately from metadata."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseBatchRuntimeParserContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runtime = read("scripts/test-v3214-image-japanese-manga-ocr-runtime.sh")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_parser_only_consumes_direction_records(self) -> None:
        for marker in [
            "block_lines = [",
            'if re.match(r"^(horizontal|vertical|unknown)\\t", line)',
            'if len(block_lines) != 5:',
            'line.startswith("vertical\\t") for line in block_lines',
        ]:
            self.assertIn(marker, self.runtime)
        self.assertNotIn("text.splitlines()[1:]", self.runtime)

    def test_batch_metadata_cannot_be_counted_as_provenance(self) -> None:
        records = [
            line
            for line in "batchInference=true\nblocks=5\nvertical\t甲\nvertical\t乙\n".splitlines()
            if re.match(r"^(horizontal|vertical|unknown)\t", line)
        ]
        self.assertEqual(records, ["vertical\t甲", "vertical\t乙"])

    def test_ci_routes_parser_fix_after_v3229(self) -> None:
        previous = "python3 -B scripts/test-v3229-image-japanese-batch-model-shape-contract.py"
        current = "python3 -B scripts/test-v3230-image-japanese-batch-runtime-parser-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3230-image-japanese-batch-runtime-parser-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 230) for version in versions)
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
