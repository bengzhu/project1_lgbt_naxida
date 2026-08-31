#!/usr/bin/env python3
"""Static contract for v3.385 llama sampler state progression."""

from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class LlamaSamplerStateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.runtime = read("AITRANS/Services/LlamaRuntime.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.test2_workflow = read(".github/workflows/test2-image-translation-ui.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = "".join(
            read(path)
            for path in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )

    def test_generated_tokens_advance_sampler_state_before_next_decode(self) -> None:
        start = self.runtime.find("for _ in 0..<maxTokens {")
        end = self.runtime.find("\n        batch = currentBatch", start)
        self.assertGreaterEqual(start, 0)
        self.assertGreater(end, start)
        generation = self.runtime[start:end]
        sample = generation.find("llama_sampler_sample(sampler")
        decode = generation.find("generatedText += decode(token: token)")
        accept = generation.find("llama_sampler_accept(sampler, token)")
        clear = generation.find("clear(&currentBatch)")
        self.assertGreaterEqual(sample, 0)
        self.assertGreaterEqual(decode, 0)
        self.assertGreaterEqual(accept, 0)
        self.assertGreaterEqual(clear, 0)
        self.assertLess(sample, decode)
        self.assertLess(decode, accept)
        self.assertLess(accept, clear)

    def test_prompt_tokens_keep_the_existing_sampler_seed_state(self) -> None:
        self.assertIn(
            "llama_sampler_accept(sampler, token)",
            self.runtime[self.runtime.find("for (index, token) in promptTokens.enumerated()") :],
        )

    def test_test2_capture_records_the_real_local_generation_trace(self) -> None:
        for marker in (
            "AITRANS_RUN_LLM_SMOKE",
            "SIMCTL_CHILD_AITRANS_RUN_LLM_SMOKE=1",
            "-AITRANS_RUN_LLM_SMOKE 1",
            "llm-smoke-result.log",
            "test2-llm-probe.log",
        ):
            self.assertIn(marker, self.capture)

    def test_test2_route_stays_on_ordinary_image_translation(self) -> None:
        self.assertIn("runLaunchBundledImageTranslationTestIfNeeded()", self.store)
        for marker in (
            'let filename = "2.png"',
            "self.translateImage(from: url)",
        ):
            self.assertIn(marker, self.store)
        for marker in (
            "scripts/capture-bundled-image-translation-ui.sh",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
        ):
            self.assertIn(marker, self.capture + self.test2_workflow)

    def test_version_and_ci_registration_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.385", "3.385"],
        )
        for marker in (
            "scripts/test-v3381-llama-sampler-state-contract.py",
            "japanese-benchmark-v3.385-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.385",
            "test/2.png",
            "llama sampler",
            "ordinary image OCR",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3381-llama-sampler-state-contract.py")
        for forbidden in (
            "subprocess" + ".run(",
            "subprocess" + ".Popen(",
            "xcodebuild" + " ",
            "swiftc" + " ",
            "cargo" + " ",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
