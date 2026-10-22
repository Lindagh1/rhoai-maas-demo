#!/usr/bin/env bash
# Convert Markdown guide(s) to styled PDF via Chrome headless.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

CHROME="${CHROME:-google-chrome}"
if ! command -v "$CHROME" &>/dev/null; then
  CHROME=chromium
fi

md_to_pdf() {
  local src="$1"
  local dst="${2:-${src%.md}.pdf}"
  local title
  title=$(basename "$src" .md | tr '_-' ' ')

  python3 - "$src" "$dst" "$title" <<'PY'
import pathlib, re, subprocess, sys, tempfile
import markdown

src, dst, title = sys.argv[1:4]
text = pathlib.Path(src).read_text(encoding="utf-8")
body = markdown.markdown(
    text,
    extensions=["tables", "fenced_code", "toc", "sane_lists"],
)
html = f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
  @page {{ margin: 18mm 16mm; }}
  body {{
    font-family: "Segoe UI", Helvetica, Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.45;
    color: #1a1a1a;
    max-width: 100%;
  }}
  h1 {{ font-size: 22pt; color: #ee0000; border-bottom: 2px solid #ee0000; padding-bottom: 6px; }}
  h2 {{ font-size: 15pt; color: #333; margin-top: 1.4em; page-break-after: avoid; }}
  h3 {{ font-size: 12.5pt; color: #444; page-break-after: avoid; }}
  table {{ border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 10pt; page-break-inside: avoid; }}
  th, td {{ border: 1px solid #ccc; padding: 6px 8px; vertical-align: top; }}
  th {{ background: #f5f5f5; }}
  code {{ background: #f4f4f4; padding: 1px 4px; border-radius: 3px; font-size: 9.5pt; }}
  pre {{ background: #f8f8f8; border: 1px solid #ddd; padding: 10px; overflow-x: auto; font-size: 9pt; page-break-inside: avoid; }}
  blockquote {{ border-left: 4px solid #ee0000; margin: 1em 0; padding: 0.2em 1em; color: #555; }}
  hr {{ border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }}
  a {{ color: #0066cc; word-break: break-all; }}
</style>
</head>
<body>
{body}
</body>
</html>"""
with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
    f.write(html)
    tmp = f.name
chrome = subprocess.run(["which", "google-chrome"], capture_output=True, text=True)
cmd = (chrome.stdout.strip() or "google-chrome")
user_data = tempfile.mkdtemp(prefix="chrome-pdf-")
subprocess.run([
    cmd, "--headless=new", "--disable-gpu", "--no-sandbox",
    f"--user-data-dir={user_data}",
    f"--print-to-pdf={pathlib.Path(dst).resolve()}",
    f"file://{tmp}",
], check=True)
import shutil
shutil.rmtree(user_data, ignore_errors=True)
pathlib.Path(tmp).unlink(missing_ok=True)
print(f"Wrote {dst}")
PY
}

if [[ $# -eq 0 ]]; then
  md_to_pdf docs/GUIDE-INSTALLATION-DEMO1.md docs/GUIDE-INSTALLATION-DEMO1.pdf
  md_to_pdf docs/GUIDE-DEMO-LIVE.md docs/GUIDE-DEMO-LIVE.pdf
else
  for f in "$@"; do
    md_to_pdf "$f"
  done
fi
