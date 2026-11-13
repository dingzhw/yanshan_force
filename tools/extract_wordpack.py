"""Extract both textbook word-list indexes and require them to agree."""
from collections import Counter
from pathlib import Path
import argparse
import csv
import hashlib
import json
import re
import pymupdf

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PDF = ROOT / "docs/vocabulary-source/grade5a-2026-wordlist.pdf"
PATTERN = re.compile(r"^[ \t]*(\*?)([A-Za-z][A-Za-z’'.,!?…() \-]*?)\s+(?=[（\u3400-\u9fff])([\s\S]*?)\x08\s*\((\d+)\)", re.M)


def extract(page):
    result = []
    text = re.sub(r"(?m)^[ \t]*I{1,3}[ \t]*$", "", page.get_text())
    for star, english, chinese, source_page in PATTERN.findall(text):
        english = re.sub(r"\s+", " ", english).strip()
        chinese = re.sub(r"\s+", "", chinese)
        result.append({"english": english, "chinese": chinese,
                       "textbook_page": int(source_page), "core": not bool(star),
                       "pdf_page": page.number + 1})
    return result


def key(entry):
    return entry["english"], entry["chinese"], entry["textbook_page"], entry["core"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    args = parser.parse_args()
    pdf_path = args.pdf
    doc = pymupdf.open(pdf_path)
    ordered = [row for page in list(doc)[108:111] for row in extract(page)]
    alphabetical = [row for page in list(doc)[111:115] for row in extract(page)]
    counts = Counter(key(row) for row in alphabetical)
    expected = Counter(key(row) for row in ordered)
    missing = expected - counts
    if missing:
        raise ValueError(f"Unit/alphabetical indexes disagree: {missing}")
    extra = counts - expected
    proper = []
    for row in alphabetical:
        if extra[key(row)] > 0:
            proper.append(row)
            extra[key(row)] -= 1
    assert len(proper) == 13, f"Expected 13 proper names, got {len(proper)}"
    all_rows = ordered + proper
    unit_starts = [8, 20, 32, 44, 58, 70, 82, 94]
    for i, row in enumerate(all_rows):
        row["id"] = f"js5a2026-{i+1:03d}"
        row["unit"] = sum(row["textbook_page"] >= start for start in unit_starts)
        row["proper_name"] = i >= len(ordered)
        row["aliases"] = []
        if row["english"] == "favourite (AmE favorite)":
            row["english"] = "favourite"
            row["aliases"] = ["favorite"]
        row["kind"] = ("proper_name" if row["proper_name"] else
                       "sentence" if row["english"].endswith((".", "!", "?")) else
                       "phrase" if " " in row["english"] else "word")
    pack = {"schema_version": 1, "pack_id": "jiangsu-5a-2026", "version": "1.0.0",
            "title": "江苏教材·2026秋五年级上册", "source_pdf": pdf_path.name,
            "source_sha256": hashlib.sha256(pdf_path.read_bytes()).hexdigest(),
            "source_printed_pages": "110–116", "source_pdf_pages": list(range(109,116)),
            "review": "单元表与字母索引逐项交叉核对；词表 I 与专有名词表 III 已查看原页",
            "includes": "书后单词、短语、重要句型及专有名词；保留星号非核心标记；字母索引不重复计数",
            "entries": all_rows}
    output = ROOT / "game/data/wordpacks"
    output.mkdir(parents=True, exist_ok=True)
    target = output / "jiangsu-5a-2026.json"
    if target.exists():
        raise FileExistsError("Preserve the existing word pack before re-extracting.")
    target.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    csv_path = ROOT / "docs/教材词汇核对表.csv"
    with csv_path.open("w", encoding="utf-8-sig", newline="") as stream:
        fields = ["id", "unit", "english", "chinese", "core", "proper_name", "kind", "textbook_page", "pdf_page", "aliases"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(all_rows)
    report = {"unit_index_rows": len(ordered), "proper_names": len(proper),
              "total_entries": len(all_rows), "core_rows": sum(row["core"] and not row["proper_name"] for row in all_rows),
              "unit_counts": dict(sorted(Counter(row["unit"] for row in ordered).items())),
              "cross_check": "all unit-index entries match the alphabetical index including Chinese gloss, page and star marker",
              "missing": [], "source_sha256": pack["source_sha256"]}
    (ROOT / "docs/vocabulary-extraction.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
