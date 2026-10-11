#!/usr/bin/env python3
"""Regenerate the Q-A seed, combined setup SQL/copy panel, order CSV, and embedded HTML data.

Edit content/question_bank.json in its existing order, then run:
    python tools/build_daily_qa_assets.py
"""
from __future__ import annotations

import csv
import json
import re
from html import escape as html_escape
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BANK_PATH = ROOT / "content" / "question_bank.json"
SEED_PATH = ROOT / "supabase" / "seed_daily_qa.sql"
SCHEMA_PATH = ROOT / "supabase" / "daily_qa.sql"
SETUP_PATH = ROOT / "supabase" / "setup_shared_project.sql"
COPY_PANEL_PATH = ROOT / "supabase" / "setup_sql_copy.html"
ORDER_PATH = ROOT / "content" / "question_order.csv"
HTML_PATH = ROOT / "index.html"
EXPECTED_COUNTS = {"P4": 160, "P5": 180, "P6": 200, "P7": 120}


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def grade_code(label: str) -> str:
    match = re.fullmatch(r"Primary ([4-7])", label)
    if not match:
        raise ValueError(f"Unsupported grade label: {label!r}")
    return "P" + match.group(1)


def load_and_validate() -> list[dict]:
    items = json.loads(BANK_PATH.read_text(encoding="utf-8"))
    if not isinstance(items, list):
        raise ValueError("The canonical question bank must be a JSON array.")
    counts = Counter(grade_code(item["grade"]) for item in items)
    if dict(counts) != EXPECTED_COUNTS:
        raise ValueError(f"Unexpected per-grade counts: {dict(counts)}")
    ids = [item["id"] for item in items]
    if len(ids) != len(set(ids)):
        raise ValueError("Question IDs must be unique.")
    for code, count in EXPECTED_COUNTS.items():
        grade_items = [item for item in items if grade_code(item["grade"]) == code]
        if [item["number"] for item in grade_items] != list(range(1, count + 1)):
            raise ValueError(f"{code} question numbers must be sequential and source-ordered.")
        for item in grade_items:
            if item.get("subject") != "Science":
                raise ValueError(f"Only Science is supported in the current Q-A app: {item['id']}")
            if not item.get("question", "").strip() or not item.get("answer", "").strip():
                raise ValueError(f"Question and answer are required: {item['id']}")
    return items


def build_seed(items: list[dict]) -> str:
    lines = [
        "-- Existing question/answer wording and source order are preserved for P4-P7 Science.",
        "-- Counts: P4 160, P5 180, P6 200, P7 120 (660 total).",
        "-- Run after supabase/daily_qa.sql. The matching question-only order index is content/question_order.csv.",
        "insert into public.daily_qa_questions",
        "  (id, grade, subject, topic, sort_order, prompt, answer, source_file, is_active)",
        "values",
    ]
    rows = []
    for item in items:
        values = [
            sql_text(item["id"]),
            sql_text(grade_code(item["grade"])),
            sql_text(item["subject"]),
            sql_text(item["topic"]),
            str(int(item["number"])),
            sql_text(item["question"]),
            sql_text(item["answer"]),
            sql_text(item.get("source_file", "")),
            "true",
        ]
        rows.append("  (" + ", ".join(values) + ")")
    lines.append(",\n".join(rows))
    lines.extend([
        "on conflict (id) do update set",
        "  grade = excluded.grade,",
        "  subject = excluded.subject,",
        "  topic = excluded.topic,",
        "  sort_order = excluded.sort_order,",
        "  prompt = excluded.prompt,",
        "  answer = excluded.answer,",
        "  source_file = excluded.source_file,",
        "  is_active = excluded.is_active;",
        "",
    ])
    return "\n".join(lines)


def build_order_csv(items: list[dict]) -> str:
    from io import StringIO

    output = StringIO(newline="")
    fields = ["grade", "grade_code", "sort_order", "topic_order", "topic_id", "topic", "question_id", "question"]
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    topic_orders: dict[str, dict[str, int]] = {}
    for item in items:
        code = grade_code(item["grade"])
        mapping = topic_orders.setdefault(code, {})
        topic_key = item.get("topic_id") or item["topic"]
        if topic_key not in mapping:
            mapping[topic_key] = len(mapping) + 1
        writer.writerow({
            "grade": item["grade"],
            "grade_code": code,
            "sort_order": item["number"],
            "topic_order": mapping[topic_key],
            "topic_id": item.get("topic_id") or "",
            "topic": item["topic"],
            "question_id": item["id"],
            "question": item["question"],
        })
    return output.getvalue()


def build_sql_copy_panel(setup_sql: str) -> str:
    """Create a browser-viewable copy/download panel for the complete setup SQL."""
    template = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Q-A Supabase setup SQL</title>
<style>
:root{color-scheme:light;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#18241d;background:#f4f7f4}
*{box-sizing:border-box}body{margin:0;padding:20px}main{max-width:1100px;margin:0 auto;background:#fff;border:1px solid #dbe4dc;border-radius:16px;overflow:hidden;box-shadow:0 8px 28px #1a392414}
header{padding:22px 24px;border-bottom:1px solid #e4ebe4}h1{margin:0 0 8px;font-size:22px}p{margin:6px 0;color:#526157;font-size:14px;line-height:1.5}.note{padding:13px 24px;background:#fff7df;border-bottom:1px solid #f0e3bd;color:#654d1a;font-size:13px;line-height:1.5}
.toolbar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;padding:14px 24px;border-bottom:1px solid #e4ebe4}button{display:inline-flex;align-items:center;gap:8px;border:1px solid #cfdacf;border-radius:9px;background:#fff;color:#1c3525;font:700 14px system-ui,sans-serif;padding:10px 14px;cursor:pointer}button.primary{background:#176b42;border-color:#176b42;color:#fff}button:hover{filter:brightness(.96)}svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}#status{font-size:13px;color:#24633f;min-height:1.4em}
textarea{display:block;width:100%;height:min(70vh,900px);min-height:460px;resize:vertical;border:0;background:#111a17;color:#e3f2e9;padding:20px 22px;font:12px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace;white-space:pre;tab-size:2;outline:none}footer{padding:12px 24px;color:#647166;font-size:12px}
@media(max-width:600px){body{padding:8px}header{padding:18px}.note,.toolbar,footer{padding-left:18px;padding-right:18px}textarea{font-size:11px;height:68vh}}
</style>
</head>
<body>
<main>
<header>
<h1>Q-A — Supabase setup SQL</h1>
<p>This is the full, additive schema-plus-seed script for the existing SmartPle student-app project: <strong>__LINE_COUNT__ lines, 660 questions</strong>.</p>
<p>Run this file first. After it succeeds, run <code>authorize_qa_admin.sql</code>, then <code>secure_smartple_profiles.sql</code>, and finally <code>verify_daily_qa.sql</code>.</p>
</header>
<div class="note"><strong>Before running:</strong> make sure Supabase is open to project <code>ftykmafgfyqvniacguyi</code>. The script checks for the expected <code>smartple_profiles</code> table/columns and stops if they are missing. This panel does not run SQL or contact Supabase.</div>
<div class="toolbar">
<button class="primary" id="copy" type="button" aria-label="Copy the complete SQL"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2"></rect><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"></path></svg>Copy SQL</button>
<button id="download" type="button" aria-label="Download the SQL file"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12"></path><path d="m7 10 5 5 5-5"></path><path d="M5 21h14"></path></svg>Download .sql</button>
<span id="status" role="status" aria-live="polite"></span>
</div>
<textarea id="sql" readonly spellcheck="false" aria-label="Complete copy-paste-ready Supabase setup SQL">__ESCAPED_SQL__</textarea>
<footer>Tip: if clipboard access is blocked, click inside the SQL box, press Ctrl+A (or ⌘A), then Ctrl+C (or ⌘C).</footer>
</main>
<script>
const box=document.getElementById('sql');
const status=document.getElementById('status');
function say(text){status.textContent=text;}
document.getElementById('copy').addEventListener('click',async()=>{
  try{await navigator.clipboard.writeText(box.value);say('Copied the full setup SQL. Paste it into Supabase SQL Editor.');}
  catch(_){box.focus();box.select();box.setSelectionRange(0,box.value.length);try{if(document.execCommand('copy'))say('Copied the full setup SQL. Paste it into Supabase SQL Editor.');else say('SQL selected; press Ctrl+C or ⌘C to copy.');}catch(__){say('SQL selected; press Ctrl+C or ⌘C to copy.');}}
});
document.getElementById('download').addEventListener('click',()=>{
  const blob=new Blob([box.value],{type:'text/sql;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='setup_shared_project.sql';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);say('Download started.');
});
</script>
</body>
</html>'''
    return (template
            .replace("__LINE_COUNT__", f"{len(setup_sql.splitlines()):,}")
            .replace("__ESCAPED_SQL__", html_escape(setup_sql, quote=False)))


def embed_json(html: str, script_id: str, value: str | list[dict]) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    # Prevent question text from ever closing the surrounding script element.
    encoded = encoded.replace("</", "<\\/")
    pattern = rf'(<script id="{re.escape(script_id)}" type="application/json">)(.*?)(</script>)'
    updated, count = re.subn(pattern, lambda m: m.group(1) + encoded + m.group(3), html, count=1, flags=re.S)
    if count != 1:
        raise ValueError(f"Could not find embedded JSON script #{script_id} in index.html")
    return updated


def main() -> None:
    items = load_and_validate()
    seed_sql = build_seed(items)
    SEED_PATH.write_text(seed_sql, encoding="utf-8")
    schema_sql = SCHEMA_PATH.read_text(encoding="utf-8")
    setup_sql = (
        "-- COPY/PASTE THIS ENTIRE FILE into the SQL Editor of the existing SmartPle project.\n"
        "-- It installs the additive Q-A schema and all 660 questions.\n"
        "-- After it succeeds, run authorize_qa_admin.sql (it requires exactly one linked admin),\n"
        "-- then secure_smartple_profiles.sql, and finally verify_daily_qa.sql.\n"
        "-- Never put a service-role key in the client.\n\n"
        + schema_sql.rstrip()
        + "\n\n-- Ordered P4-P7 Science Q&A seed (660 items).\n"
        + seed_sql.rstrip()
        + "\n"
    )
    SETUP_PATH.write_text(setup_sql, encoding="utf-8")
    COPY_PANEL_PATH.write_text(build_sql_copy_panel(setup_sql), encoding="utf-8")
    ORDER_PATH.write_text(build_order_csv(items), encoding="utf-8")
    html = HTML_PATH.read_text(encoding="utf-8")
    html = embed_json(html, "question-bank", items)
    html = embed_json(html, "schema-sql", schema_sql)
    html = embed_json(html, "seed-sql", seed_sql)
    HTML_PATH.write_text(html, encoding="utf-8")
    print("Generated 660 ordered Q&A items:", dict(Counter(grade_code(item["grade"]) for item in items)))
    print(f"Wrote {SEED_PATH.relative_to(ROOT)}")
    print(f"Wrote {SETUP_PATH.relative_to(ROOT)} (schema + seed, ready to copy/paste)")
    print(f"Wrote {COPY_PANEL_PATH.relative_to(ROOT)} (visible SQL with Copy and Download controls)")
    print(f"Wrote {ORDER_PATH.relative_to(ROOT)} (questions only; no answers)")
    print("Synchronized embedded question bank and SQL in index.html")


if __name__ == "__main__":
    main()
