#!/usr/bin/env python3
"""Static contract for v3.286 GGUF chat-template and model-profile routing."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_json(relative: str) -> dict:
    payload = json.loads(read(relative))
    if not isinstance(payload, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return payload


class LocalGGUFChatTemplateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile_source = read("AITRANS/Models/LocalModelPromptProfile.swift")
        cls.runtime = read("AITRANS/Services/LlamaRuntime.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.schema = load_json("benchmarks/japanese_translation/schema/model-profile-manifest.schema.json")
        cls.manifest = load_json("benchmarks/japanese_translation/examples/model_profiles/manifest.json")
        cls.fixture = read("scripts/fixtures/v3286-local-gguf-chat-template-evaluator.swift")
        cls.runtime_shell = read("scripts/test-v3286-local-gguf-chat-template-runtime.sh")

    def test_model_profile_manifest_is_strict_and_records_artifact_identity(self) -> None:
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertFalse(self.schema["additionalProperties"])
        self.assertEqual(self.manifest["benchmark"], "japanese-translation-model-profiles")
        self.assertTrue(self.manifest["contractExampleOnly"])
        profiles = self.manifest["profiles"]
        self.assertEqual({profile["modelFamily"] for profile in profiles}, {"Gemma", "Qwen", "Sakura"})
        for profile in profiles:
            self.assertRegex(profile["appSha"], r"^[0-9a-f]{40}$")
            model = profile["model"]
            self.assertRegex(model["filename"], r"\.gguf$")
            self.assertRegex(model["sha256"], r"^[0-9a-f]{64}$")
            self.assertTrue(model["quantization"])
            self.assertIn("licenseReviewed", model)
            template = profile["template"]
            self.assertEqual(template["applyAPI"], "llama_chat_apply_template")
            self.assertIn(template["source"], {"embedded", "missingRejected"})
            self.assertEqual(profile["capability"]["maxBatchBlocks"], 8)
            self.assertEqual(profile["capability"]["maxBatchCharacters"], 1800)
            self.assertIn("profileID", profile["decoding"])

    def test_profile_separates_messages_from_wrappers_and_only_gemma_can_fallback(self) -> None:
        for marker in (
            "struct LocalModelChatMessage",
            "enum LocalModelPromptProfileID",
            "static let gemma",
            "static let qwen",
            "static let sakura",
            "knownFallbackTemplate: .gemma",
            "knownFallbackTemplate: nil",
            "fallbackUnavailable",
            "never turns a missing template into ChatML",
            "<start_of_turn>",
            "<end_of_turn>",
        ):
            self.assertIn(marker, self.profile_source)
        self.assertNotIn('output += "<|im_start|>"', self.profile_source)
        self.assertIn("LocalModelChatMessage(role: .user", self.gemma)
        self.assertIn("translationMessages(for: request)", self.gemma)
        self.assertIn("fallbackProfile: promptProfile", self.gemma)
        self.assertIn("promptForLogging(for: messages)", self.gemma)
        self.assertIn("return rendered.prompt", self.gemma)
        self.assertIn("translationPrompts(for request:", self.gemma)
        self.assertIn("promptProfile: LocalModelPromptProfile? = nil", self.gemma)
        self.assertIn("isBundledGemmaDirectory", self.gemma)
        self.assertIn(".experimental", self.gemma)

    def test_runtime_reads_embedded_template_and_handles_c_buffer_sizing(self) -> None:
        for marker in (
            "llama_model_chat_template(model, nil)",
            "llama_chat_apply_template",
            "withCChatMessages",
            "withCString",
            "let required =",
            "buffer.baseAddress",
            "Int(written) + 1",
            "case missingChatTemplate",
            "case unsupportedChatTemplate",
            "case chatTemplateBufferSizingFailed",
            "case invalidRenderedPrompt",
            "throw LlamaRuntimeError.unsupportedChatTemplate",
            "throw LlamaRuntimeError.missingChatTemplate",
        ):
            self.assertIn(marker, self.runtime)
        self.assertNotIn("llama_chat_apply_template(nil", self.runtime)
        self.assertNotIn('tmpl == nil ? "chatml"', self.runtime)
        self.assertIn("source: .embedded", self.runtime)
        self.assertIn("source: .explicitKnownFallback", self.runtime)
        self.assertIn("String(data: Data(bytes), encoding: .utf8)", self.runtime)

    def test_gemma_instruction_and_tagged_batch_regressions_remain_in_place(self) -> None:
        for marker in (
            "你是专业的漫画翻译器",
            "原样保留每个 [N] 标签",
            "不要合并、拆分、遗漏或重排",
            "<start_of_turn>user",
            "<end_of_turn>",
            "<start_of_turn>model",
            "cleanMangaBlockOutput",
            "let expectedPartsByID = Dictionary(",
            "ordering and completeness are",
        ):
            self.assertTrue(marker in self.gemma or marker in self.store, marker)
        for marker in (
            "let maximumBlocks = 8",
            "let maximumCharacters = 1_800",
            "parseMangaTaggedTranslations",
            "missingOffsets",
            "if error is CancellationError",
        ):
            self.assertIn(marker, self.store)
        self.assertNotIn("Qwen", self.gemma)
        self.assertNotIn("Sakura", self.gemma)
        self.assertNotIn("maxBatchBlocks = 16", self.gemma + self.store)
        self.assertNotIn("maximumCharacters = 3_600", self.store)

    def test_cloud_fixture_covers_embedded_fixtures_fallback_rejection_unicode_resize_and_raw_tags(self) -> None:
        for marker in (
            "profileID: .gemma",
            "profileID: .qwen",
            "profileID: .sakura",
            "embeddedTemplate",
            "fallbackUnavailable",
            "今度こそ😀",
            "renderWithBufferResize",
            "String(repeating: \"长文本😀\"",
            "[2] 二\\n[1] 一",
            "let decoded = try JSONDecoder().decode(LocalModelPromptProfile.self, from: encoded)",
            "precondition(decoded == .gemma)",
            "v3.286 local GGUF chat-template evaluator passed",
        ):
            self.assertIn(marker, self.fixture)
        self.assertNotIn("precondition(try ", self.fixture)
        self.assertIn("GITHUB_ACTIONS", self.runtime_shell)
        self.assertIn("xcrun swiftc", self.runtime_shell)
        self.assertIn("LocalModelPromptProfile.swift", self.runtime_shell)
        self.assertNotIn("xcodebuild", self.runtime_shell)
        self.assertNotIn("cargo", self.runtime_shell)

    def test_ci_and_version_route_are_explicit_without_product_model_replacement(self) -> None:
        for marker in (
            "scripts/test-v3286-local-gguf-chat-template-contract.py",
            "scripts/test-v3286-local-gguf-chat-template-runtime.sh",
            "japanese-translation-model-profile-manifest.json",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.319", "3.319"])
        self.assertIn("v3.286", self.route)
        self.assertIn("v3.286", self.update_log)
        for marker in (
            "不立即更换默认模型",
            "Gemma 回归",
            "Qwen",
            "Sakura",
            "template source",
            "decoding profile",
        ):
            self.assertIn(marker, self.route + self.update_log)
        self.assertIn("ModelDecodingProfile.deterministic", self.gemma)
        self.assertIn("decodingProfile: .sampled", self.gemma)
        self.assertNotIn("contextParameters.n_ctx = 2_048", self.runtime)

    def test_project_contains_model_profile_in_models_group_and_sources_phase(self) -> None:
        self.assertIn("LocalModelPromptProfile.swift in Sources", self.project)
        self.assertIn("LocalModelPromptProfile.swift */", self.project)
        self.assertIn("0A00000100000000000000E6", self.project)
        self.assertIn("0A00000100000000000000E7", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
