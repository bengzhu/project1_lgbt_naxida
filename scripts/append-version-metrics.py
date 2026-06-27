#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import subprocess
from pathlib import Path


HEADER = [
    "version",
    "date",
    "gitCommit",
    "decodingMode",
    "totalBlocksDetected",
    "groundTruthMatchedBlocks",
    "groundTruthUnmatchedBlocks",
    "averageCoreDialogueOCRSimilarity",
    "averageDecorativeOCRSimilarity",
    "wholePageAccuracyVsGroundTruth",
    "bubbleFirstAccuracyVsGroundTruth",
    "frameworkComparisonConsistencyPassed",
    "cleanTextDiagnosticPassRate",
    "passedBlocks",
    "failedBlocks",
    "translationFailureBreakdownJson",
    "glyphMaskBlocksCount",
    "backgroundFillAppliedCount",
    "renderCollisionUnresolvedCount",
    "renderTextTruncatedCount",
    "notes",
]


def git_commit(project_root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=project_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        return ""


def fmt(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def compact_json(value):
    if value in (None, ""):
        return ""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser(description="Append manga probe metrics to metrics/version_history.csv")
    parser.add_argument("--version", required=True, help="conversation version label, e.g. v6")
    parser.add_argument("--report", default="output/probe_report.json")
    parser.add_argument("--csv", default="metrics/version_history.csv")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    report_path = (project_root / args.report).resolve()
    csv_path = (project_root / args.csv).resolve()

    report = json.loads(report_path.read_text(encoding="utf-8"))
    diagnostics = report.get("diagnostics") or {}
    framework = report.get("frameworkComparison") or {}
    clean = report.get("cleanTextDiagnostic") or {}

    row = {
        "version": args.version,
        "date": args.date,
        "gitCommit": git_commit(project_root),
        "decodingMode": fmt(report.get("decodingMode") or clean.get("decodingMode")),
        "totalBlocksDetected": fmt(report.get("totalBlocksDetected")),
        "groundTruthMatchedBlocks": fmt(diagnostics.get("groundTruthMatchedBlocks")),
        "groundTruthUnmatchedBlocks": fmt(diagnostics.get("groundTruthUnmatchedBlocks")),
        "averageCoreDialogueOCRSimilarity": fmt(diagnostics.get("averageCoreDialogueOCRSimilarity")),
        "averageDecorativeOCRSimilarity": fmt(diagnostics.get("averageDecorativeOCRSimilarity")),
        "wholePageAccuracyVsGroundTruth": fmt((framework.get("wholePage") or {}).get("accuracyVsGroundTruth")),
        "bubbleFirstAccuracyVsGroundTruth": fmt((framework.get("bubbleFirst") or {}).get("accuracyVsGroundTruth")),
        "frameworkComparisonConsistencyPassed": fmt(framework.get("consistencyPassed")),
        "cleanTextDiagnosticPassRate": fmt(clean.get("passRate")),
        "passedBlocks": fmt(diagnostics.get("passedBlocks")),
        "failedBlocks": fmt(diagnostics.get("failedBlocks")),
        "translationFailureBreakdownJson": compact_json(diagnostics.get("translationFailureBreakdown")),
        "glyphMaskBlocksCount": fmt(diagnostics.get("glyphMaskBlocks")),
        "backgroundFillAppliedCount": fmt(len(diagnostics.get("backgroundFillAppliedBlocks") or [])),
        "renderCollisionUnresolvedCount": fmt(len(diagnostics.get("renderCollisionUnresolvedBlocks") or [])),
        "renderTextTruncatedCount": fmt(len(diagnostics.get("renderTextTruncatedBlocks") or [])),
        "notes": args.notes,
    }

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    write_header = not csv_path.exists() or csv_path.stat().st_size == 0
    with csv_path.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=HEADER, lineterminator="\n")
        if write_header:
            writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    main()
