"""Render the human-readable status report from its single JSON source of truth."""
from pathlib import Path
from collections import Counter
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/audit/remediation-status.json"
DESTINATION = ROOT / "docs/audit/REMEDIATION_STATUS.md"

def render():
    report = json.loads(SOURCE.read_text(encoding="utf-8"))
    findings = report["findings"]
    lines = ["# GS remediation status", "", report["qualification"], "",
             "Finding IDs use P.section.finding; the audit number preserves the original 1–66 mapping.", "",
             "| Section | Status | Fully | Partially | Not yet |", "|---|---|---:|---:|---:|"]
    sections = list(dict.fromkeys(row["section"] for row in findings))
    for index, section in enumerate(sections, 1):
        rows = [row for row in findings if row["section"] == section]
        counts = Counter(row["status"] for row in rows)
        status = "fully implemented" if counts["fully implemented"] == len(rows) else (
            "not yet implemented" if counts["not yet implemented"] == len(rows) else "partially implemented")
        lines.append(f"| P.{index} {section} | **{status}** | {counts['fully implemented']} | {counts['partially implemented']} | {counts['not yet implemented']} |")
    for index, section in enumerate(sections, 1):
        lines += ["", f"## P.{index} — {section}", "",
                  "| Finding | Audit | Priority | Status | Change / verification / remaining boundary |",
                  "|---|---:|---|---|---|"]
        for row in findings:
            if row["section"] != section:
                continue
            details = []
            for key, label in [("changes", "Changed"), ("verification", "Verified"), ("remaining", "Remaining")]:
                if row[key]:
                    details.append(label + ": " + "; ".join(row[key]))
            detail = " · ".join(details).replace("|", r"\|").replace("\n", " ")
            lines.append(f"| {row['id']} {row['title']} | {row['audit_finding']} | {row['priority']} | **{row['status']}** | {detail or 'Pending implementation and qualification.'} |")
    result = "\n".join(lines) + "\n"
    assert len(findings) == 66 and len({row["id"] for row in findings}) == 66
    assert all(row["status"] in {"fully implemented", "partially implemented", "not yet implemented"} for row in findings)
    if "--check" in sys.argv:
        if not DESTINATION.exists() or DESTINATION.read_text(encoding="utf-8") != result:
            raise SystemExit("Status report is stale. Run python tools/audit_status.py")
    else:
        DESTINATION.write_text(result, encoding="utf-8")
    print(json.dumps(Counter(row["status"] for row in findings), sort_keys=True))

if __name__ == "__main__":
    render()
