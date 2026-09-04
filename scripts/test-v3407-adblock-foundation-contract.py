#!/usr/bin/env python3
"""Static contract for the native AdBlock rule/cache foundation."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AdBlockFoundationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = read("AITRANS/Models/AdBlockModels.swift")
        cls.repository = read("AITRANS/Services/AdBlockRuleRepository.swift")
        cls.compiler = read("AITRANS/Services/AdBlockRuleCompiler.swift")
        cls.store = read("AITRANS/Services/AdBlockStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_store_is_main_actor_observable_and_intent_driven(self):
        for needle in (
            "@MainActor\n@Observable\nfinal class AdBlockStore",
            "enum Intent",
            "func send(_ intent: Intent)",
            "private(set) var state: AdBlockState",
            "private var operationID = UUID()",
            "try Task.checkCancellation()",
            "guard self.operationID == operationID",
        ):
            self.assertIn(needle, self.store)

    def test_repository_has_etag_versioned_bounded_cache(self):
        for needle in (
            '"If-None-Match"',
            '"If-Modified-Since"',
            "case 304:",
            "maximumResponseBytes",
            "data.count <= source.maximumResponseBytes",
            "contentSHA256",
            "schemaVersion",
            "dateEncodingStrategy = .iso8601",
            "dateDecodingStrategy = .iso8601",
            "options: .atomic",
            "FileProtectionType.completeUntilFirstUserAuthentication",
            "func clearCache()",
        ):
            self.assertIn(needle, self.models + self.repository)

    def test_sources_are_remote_data_not_linked_code(self):
        for source_id in (
            "filter_224_Chinese/filter.txt",
            "filter_11_Mobile/filter.txt",
            "filter_19_Annoyances_Popups/filter.txt",
            "filter_2_Base/filter.txt",
            "https://small.oisd.nl",
        ):
            self.assertIn(source_id, self.models)
        self.assertIn('license: "GPL-3.0 rules data"', self.models)
        self.assertNotIn("XCRemoteSwiftPackageReference", self.project)

    def test_converter_is_conservative_and_outputs_two_native_lists(self):
        for needle in (
            'actionType = isException ? "ignore-previous-rules" : "block"',
            "let networkRules = networkBlocks + networkExceptions",
            'type: "css-display-none"',
            '"[class*="',
            '"[id*="',
            "!ifDomains.isEmpty",
            "let networkID = \"aitrans-adblock-network-",
            "let cosmeticID = \"aitrans-adblock-cosmetic-",
            "compileContentRuleList",
            "removeObsoleteCompiledLists",
        ):
            self.assertIn(needle, self.compiler + self.store)

    def test_new_files_are_target_members_and_ci_runs_behavior_smoke(self):
        for filename in (
            "AdBlockModels.swift",
            "AdBlockRuleRepository.swift",
            "AdBlockRuleCompiler.swift",
            "AdBlockStore.swift",
        ):
            self.assertIn(f"/* {filename} in Sources */", self.project)
        self.assertIn("test-v3407-adblock-foundation-contract.py", self.workflow)
        self.assertIn("test-adblock-rule-compiler.swift", self.workflow)
        self.assertIn("test-adblock-rule-repository.swift", self.workflow)


if __name__ == "__main__":
    unittest.main()
