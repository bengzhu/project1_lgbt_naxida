#!/usr/bin/env python3
"""Evaluate the v3.288 translation context and block-level QA boundary.

The evaluator is intentionally cloud-only when invoked by the wrapper.  It is
also pure stdlib so contracts can validate the fail-closed policy without
loading a model, OCR runtime, or product state.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-translation-context-qa"
ROOT = Path(__file__).resolve().parents[1]
TAG_RE = re.compile(r"(?m)^\s*\[(\d+)\]\s*")
NUMBER_RE = re.compile(r"\d+(?:[.,:/-]\d+)*")
LANGUAGE_PAIRS = {("ja", "zh-CN"), ("ja", "en")}


class ContextQAError(ValueError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContextQAError(f"cannot read JSON {path}: {error}") from error


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContextQAError(message)


def reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    require(not unknown, f"{label} has unknown fields: {unknown}")


def string(value: Any, label: str) -> str:
    require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value


def normalize_text(value: str) -> str:
    return "".join(
        character
        for character in unicodedata.normalize("NFKC", value).casefold()
        if not character.isspace() and not unicodedata.category(character).startswith("P")
    )


def number_tokens(value: str) -> list[str]:
    return NUMBER_RE.findall(unicodedata.normalize("NFKC", value))


def target_density(value: str, target: str) -> float:
    relevant = [character for character in value if not character.isspace() and not unicodedata.category(character).startswith("P")]
    if not relevant:
        return 0.0
    if target == "zh-CN":
        signal = sum("\u4e00" <= character <= "\u9fff" for character in relevant)
    else:
        signal = sum(("a" <= character.casefold() <= "z") for character in relevant)
    return signal / len(relevant)


def is_placeholder_response(value: str) -> bool:
    normalized = " ".join(unicodedata.normalize("NFKC", value).casefold().split())
    compact = "".join(character for character in normalized if not character.isspace() and not unicodedata.category(character).startswith("P"))
    if not compact:
        return False

    exact_meta_responses = {
        "na",
        "待翻译",
        "以下是翻译",
        "这是翻译",
        "翻译如下",
        "翻译成中文",
        "translationunavailable",
        "notranslationavailable",
        "cannottranslate",
        "unabletotranslate",
        "pleaseprovide",
        "providethetext",
        "translatethefollowing",
        "翻译是",
        "意思是",
        "这句话的意思",
        "最合适的翻译",
        "最通用的翻译",
        "最常用的翻译",
    }
    if compact in exact_meta_responses:
        return True

    refusal_markers = (
        "无法翻译",
        "无法完成翻译",
        "无法提供译文",
        "翻译失败",
        "需要更多上下文",
        "需要更多信息",
        "请提供更多上下文",
        "请提供更多信息",
        "cannottranslate",
        "unabletotranslate",
        "translationunavailable",
        "notranslationavailable",
        "pleaseprovidemorecontext",
        "pleaseprovidemoreinformation",
        "needmorecontext",
        "needmoreinformation",
        "pleaseprovidethetext",
        "providethetexttotranslate",
        "请将以下翻译成中文",
        "请将以上翻译成中文",
        "请将以下翻译转换成中文",
        "请将以上翻译转换成中文",
        "把以下翻译成中文",
        "翻译转换成中文",
    )
    if len(compact) <= 96 and any(marker in compact for marker in refusal_markers):
        return True

    request_markers = (
        "请提供",
        "请您提供",
        "请你提供",
        "请输入",
        "请给出",
        "pleaseprovide",
        "pleaseenter",
        "pleasesend",
        "kindlyprovide",
    )
    translation_input_markers = (
        "需要翻译的文本",
        "想要翻译的文本",
        "待翻译文本",
        "翻译文本",
        "原文",
        "译文",
        "文本",
        "内容",
        "句子",
        "文字",
        "text",
        "sourcetext",
        "translation",
        "sentence",
        "content",
    )
    return (
        len(compact) <= 96
        and any(marker in compact for marker in request_markers)
        and any(marker in compact for marker in translation_input_markers)
    )


def parse_records(output: str) -> list[tuple[int, str]]:
    text = output.replace("```text", "").replace("```", "").strip()
    for marker in ("<end_of_turn>", "<start_of_turn>"):
        if marker in text:
            text = text.split(marker, 1)[0].strip()
    matches = list(TAG_RE.finditer(text))
    records: list[tuple[int, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        records.append((int(match.group(1)), text[start:end].strip()))
    return records


def validate_input(payload: Any) -> dict[str, Any]:
    require(isinstance(payload, dict), "input must be an object")
    reject_unknown(payload, {"schemaVersion", "benchmark", "run", "contractExampleOnly", "context", "batches", "boundary"}, "input")
    require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported schemaVersion")
    require(payload.get("benchmark") == BENCHMARK, "invalid benchmark")
    require(isinstance(payload.get("contractExampleOnly"), bool), "contractExampleOnly must be boolean")

    run = payload.get("run")
    require(isinstance(run, dict), "run must be an object")
    reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    require(re.fullmatch(r"[0-9a-f]{40}", str(run.get("appSha", ""))) is not None, "run.appSha is invalid")
    string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode is invalid")

    context = payload.get("context")
    require(isinstance(context, dict), "context must be an object")
    reject_unknown(context, {"sourceLanguage", "targetLanguage", "textKind", "confirmedTerms", "previousBatchSummary"}, "context")
    require(context.get("sourceLanguage") == "ja", "context sourceLanguage must be ja")
    require(("ja", context.get("targetLanguage")) in LANGUAGE_PAIRS, "unsupported context language pair")
    require(context.get("textKind") in {"dialogue", "narration", "sfx", "title", "other"}, "context textKind is invalid")
    terms = context.get("confirmedTerms")
    require(isinstance(terms, list), "context.confirmedTerms must be an array")
    seen_sources: set[str] = set()
    for index, term in enumerate(terms):
        label = f"context.confirmedTerms[{index}]"
        require(isinstance(term, dict), f"{label} must be an object")
        reject_unknown(term, {"id", "source", "target", "kind", "status", "note"}, label)
        for key in ("id", "source", "target", "kind", "status"):
            string(term.get(key), f"{label}.{key}")
        require(term["kind"] in {"terminology", "personName", "addressing", "sfx", "narration"}, f"{label}.kind is invalid")
        require(term["status"] in {"confirmed", "candidate", "revoked"}, f"{label}.status is invalid")
        source_key = normalize_text(term["source"])
        require(source_key not in seen_sources, f"duplicate term source: {term['source']}")
        seen_sources.add(source_key)

    summary = context.get("previousBatchSummary")
    if summary is not None:
        require(isinstance(summary, dict), "previousBatchSummary must be an object or null")
        reject_unknown(summary, {"batchID", "items", "isReadOnly", "containsPendingInputBlocks", "generatedFromCompletedBlocks"}, "previousBatchSummary")
        string(summary.get("batchID"), "previousBatchSummary.batchID")
        require(summary.get("isReadOnly") is True, "previous batch context must be read-only")
        require(summary.get("containsPendingInputBlocks") is False, "previous batch context contains pending input blocks")
        require(summary.get("generatedFromCompletedBlocks") is True, "previous batch context is not from completed blocks")
        require(isinstance(summary.get("items"), list), "previousBatchSummary.items must be an array")
        for item_index, item in enumerate(summary["items"]):
            label = f"previousBatchSummary.items[{item_index}]"
            require(isinstance(item, dict), f"{label} must be an object")
            reject_unknown(item, {"ordinal", "sourceExcerpt", "targetExcerpt", "kind"}, label)
            require(isinstance(item.get("ordinal"), int) and item["ordinal"] > 0, f"{label}.ordinal is invalid")
            string(item.get("sourceExcerpt"), f"{label}.sourceExcerpt")
            string(item.get("targetExcerpt"), f"{label}.targetExcerpt")
            require(item.get("kind") in {"dialogue", "narration", "sfx", "title", "other"}, f"{label}.kind is invalid")

    boundary = payload.get("boundary")
    require(isinstance(boundary, dict), "boundary must be an object")
    reject_unknown(boundary, {"ocrRerunOnQAFailure", "pageRerunOnQAFailure", "extraTagsRejected", "duplicateTagsRejected", "outOfOrderTagsRejected", "defaultProductSelectionChanged"}, "boundary")
    require(boundary.get("ocrRerunOnQAFailure") is False, "QA may not rerun OCR")
    require(boundary.get("pageRerunOnQAFailure") is False, "QA may not rerun the whole page")
    require(boundary.get("extraTagsRejected") is True, "extra tags must be rejected")
    require(boundary.get("duplicateTagsRejected") is True, "duplicate tags must be rejected")
    require(boundary.get("outOfOrderTagsRejected") is True, "out-of-order tags must be rejected")
    require(boundary.get("defaultProductSelectionChanged") is False, "product selection changed")

    batches = payload.get("batches")
    require(isinstance(batches, list) and batches, "batches must be a non-empty array")
    batch_ids: list[str] = []
    for batch_index, batch in enumerate(batches):
        label = f"batches[{batch_index}]"
        require(isinstance(batch, dict), f"{label} must be an object")
        reject_unknown(batch, {"batchID", "sourceBlocks", "rawOutput", "expectedFailedBlockIDs", "expectedAction", "cancelScenario"}, label)
        string(batch.get("batchID"), f"{label}.batchID")
        require(batch["batchID"] not in batch_ids, f"duplicate batch ID: {batch['batchID']}")
        batch_ids.append(batch["batchID"])
        blocks = batch.get("sourceBlocks")
        require(isinstance(blocks, list) and blocks, f"{label}.sourceBlocks must be non-empty")
        block_ids: set[int] = set()
        for block_index, block in enumerate(blocks):
            block_label = f"{label}.sourceBlocks[{block_index}]"
            require(isinstance(block, dict), f"{block_label} must be an object")
            reject_unknown(block, {"id", "sourceText", "kind", "maxOutputCharacters"}, block_label)
            require(isinstance(block.get("id"), int) and block["id"] > 0, f"{block_label}.id is invalid")
            require(block["id"] not in block_ids, f"{label} has duplicate block ID")
            block_ids.add(block["id"])
            string(block.get("sourceText"), f"{block_label}.sourceText")
            require(block.get("kind") in {"dialogue", "narration", "sfx", "title", "other"}, f"{block_label}.kind is invalid")
            require(isinstance(block.get("maxOutputCharacters"), int) and block["maxOutputCharacters"] > 0, f"{block_label}.maxOutputCharacters is invalid")
        require(isinstance(batch.get("rawOutput"), str), f"{label}.rawOutput must be a string")
        failed_ids = batch.get("expectedFailedBlockIDs")
        require(isinstance(failed_ids, list) and all(isinstance(value, int) for value in failed_ids), f"{label}.expectedFailedBlockIDs is invalid")
        require(set(failed_ids).issubset(block_ids), f"{label}.expectedFailedBlockIDs escapes source blocks")
        require(batch.get("expectedAction") in {"accept", "retryFailedBlocksOnly", "persistPartialAndStop"}, f"{label}.expectedAction is invalid")
        cancel = batch.get("cancelScenario")
        require(isinstance(cancel, dict), f"{label}.cancelScenario must be an object")
        reject_unknown(cancel, {"requested", "scope", "preservesCompletedBlocks", "persistsPartialState", "rerunsOCR", "rerunsWholePage"}, f"{label}.cancelScenario")
        require(isinstance(cancel.get("requested"), bool), f"{label}.cancelScenario.requested is invalid")
        require(cancel.get("scope") in {"none", "block", "batch"}, f"{label}.cancelScenario.scope is invalid")
        for key in ("preservesCompletedBlocks", "persistsPartialState", "rerunsOCR", "rerunsWholePage"):
            require(isinstance(cancel.get(key), bool), f"{label}.cancelScenario.{key} is invalid")
    if summary is not None:
        summary_index = batch_ids.index(summary["batchID"]) if summary["batchID"] in batch_ids else -1
        require(summary_index >= 0, "previousBatchSummary.batchID must identify a source batch")
        require(summary_index < len(batch_ids) - 1, "previousBatchSummary must have a following target batch")
    return payload


def text_failures(
    source: str,
    output: str,
    target: str,
    max_chars: int,
    terms: list[dict[str, Any]],
    previous_summary: dict[str, Any] | None,
) -> list[str]:
    failures: list[str] = []
    source_normalized = normalize_text(source)
    output_normalized = normalize_text(output)
    if is_placeholder_response(output):
        failures.append("placeholderOutput")
    if len(source_normalized) > 1 and not source_normalized.isdigit() and source_normalized in output_normalized:
        failures.append("sourceLeakage")
    if number_tokens(source) != number_tokens(output):
        failures.append("numberMismatch")
    if previous_summary is not None:
        if any(
            len(normalize_text(item["targetExcerpt"])) >= 4
            and normalize_text(item["targetExcerpt"]) in output_normalized
            for item in previous_summary["items"]
        ):
            failures.append("previousContextLeakage")
    for term in terms:
        if term["status"] != "confirmed" or term["source"] not in source:
            continue
        if term["target"] not in output:
            failures.append("confirmedTermMismatch")
    for term in terms:
        if term["status"] == "revoked" and term["target"] in output:
            failures.append("revokedTermUse")
    if len(output) > max_chars:
        failures.append("outputTooLong")
    if target_density(output, target) < 0.35:
        failures.append("targetLanguageDensity")
    return failures


def evaluate_batch(batch: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    blocks = batch["sourceBlocks"]
    expected_ids = [block["id"] for block in blocks]
    records = parse_records(batch["rawOutput"])
    failure_reasons: dict[str, list[str]] = {}
    failed: set[int] = set()

    def fail(block_id: int, reason: str) -> None:
        failed.add(block_id)
        key = str(block_id)
        failure_reasons.setdefault(key, [])
        if reason not in failure_reasons[key]:
            failure_reasons[key].append(reason)

    if not records:
        for block_id in expected_ids:
            fail(block_id, "missingTags")
    record_ids = [record_id for record_id, _ in records]
    known_records = [(record_id, value) for record_id, value in records if record_id in expected_ids]
    if len(known_records) != len(records):
        for block_id in expected_ids:
            fail(block_id, "extraTag")
    for block_id in expected_ids:
        occurrences = [value for record_id, value in known_records if record_id == block_id]
        if not occurrences:
            fail(block_id, "missingTags")
        elif len(occurrences) > 1:
            fail(block_id, "duplicateTags")
    expected_recognized = [block_id for block_id in expected_ids if block_id in record_ids]
    if [record_id for record_id in record_ids if record_id in expected_ids] != expected_recognized:
        for index, record_id in enumerate([record_id for record_id in record_ids if record_id in expected_ids]):
            if index >= len(expected_recognized) or record_id != expected_recognized[index]:
                fail(record_id, "outOfOrderTags")
                if index < len(expected_recognized):
                    fail(expected_recognized[index], "outOfOrderTags")

    confirmed_terms = context["confirmedTerms"]
    previous_summary = context["previousBatchSummary"]
    if previous_summary is not None and previous_summary["batchID"] == batch["batchID"]:
        previous_summary = None
    for block in blocks:
        if block["id"] in failed:
            continue
        values = [value for record_id, value in known_records if record_id == block["id"]]
        if not values:
            continue
        for reason in text_failures(
            block["sourceText"],
            values[0],
            context["targetLanguage"],
            block["maxOutputCharacters"],
            confirmed_terms,
            previous_summary,
        ):
            fail(block["id"], reason)

    accepted = [block_id for block_id in expected_ids if block_id not in failed]
    cancel = batch["cancelScenario"]
    cancel_boundary_passed = (
        (not cancel["requested"] or cancel["scope"] in {"block", "batch"})
        and cancel["preservesCompletedBlocks"]
        and cancel["persistsPartialState"]
        and not cancel["rerunsOCR"]
        and not cancel["rerunsWholePage"]
    )
    require(cancel_boundary_passed, f"{batch['batchID']} violates cancellation/partial persistence boundary")

    action = "accept" if not failed else "retryFailedBlocksOnly"
    if failed and not accepted:
        action = "persistPartialAndStop"
    return {
        "batchID": batch["batchID"],
        "acceptedBlockIDs": accepted,
        "failedBlockIDs": sorted(failed),
        "failureReasons": failure_reasons,
        "action": action,
        "cancelBoundaryPassed": cancel_boundary_passed,
    }


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    validate_input(payload)
    context = payload["context"]
    summary = context["previousBatchSummary"]
    summary_index = next(
        (index for index, batch in enumerate(payload["batches"]) if summary is not None and batch["batchID"] == summary["batchID"]),
        None,
    )
    reports: list[dict[str, Any]] = []
    for index, batch in enumerate(payload["batches"]):
        batch_context = context
        if summary is not None and summary_index is not None and index != summary_index + 1:
            batch_context = dict(context)
            batch_context["previousBatchSummary"] = None
        reports.append(evaluate_batch(batch, batch_context))
    for batch, report in zip(payload["batches"], reports):
        require(report["failedBlockIDs"] == sorted(batch["expectedFailedBlockIDs"]), f"{batch['batchID']} failed block set differs from contract")
        require(report["action"] == batch["expectedAction"], f"{batch['batchID']} action differs from contract")

    gate_ledger = [
        {"gateID": "G-context-read-only", "status": "passed", "detail": "previous batch summary is read-only and contains no pending input blocks"},
        {"gateID": "G-tag-boundary", "status": "passed", "detail": "extra, duplicate, and out-of-order tags are rejected"},
        {"gateID": "G-translation-QA", "status": "passed", "detail": "source leakage, numbers, terms, placeholder outputs, target density, and length are checked per block"},
        {"gateID": "G-real-artifact", "status": "blocked", "detail": "contract fixture is synthetic; real GGUF, authorized clean corpus, and target-device evidence are absent"},
    ]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": "blocked" if payload["contractExampleOnly"] else "passed",
        "promotionStatus": "notEligible",
        "contractExampleOnly": payload["contractExampleOnly"],
        "productSelectionChanged": False,
        "batchReports": reports,
        "gateLedger": gate_ledger,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = evaluate(load_json(args.input))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except ContextQAError as error:
        print(f"v3.288 translation context QA failed: {error}", file=sys.stderr)
        return 2
    print(f"v3.288 translation context QA {report['status']}; batches={len(report['batchReports'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
