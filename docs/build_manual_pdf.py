#!/usr/bin/env python3
"""Build docs/EE_Calc_User_Manual.pdf from docs/USER_MANUAL.md.

The PDF follows the owner's document standard: Visby (installed as
Visby CF), 12 pt body, Dracula Pro Alucard colours, US Letter portrait, no
background fills, and a footer with the document line and "Page x of y".
Screenshots come from screenshots/light/ (the Alucard theme), so the
printed manual stays light; the GitHub page keeps the dark ones.

The PDF is not committed: it embeds Visby CF, whose licence only allows
embedded fonts that cannot be extracted, so it stays local for printing
(see .gitignore). The Markdown manual is the published version.

Needs: pandoc, and Playwright's Chromium headless shell
(~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell).

    python3 docs/build_manual_pdf.py
"""

import datetime
import glob
import os
import pathlib
import re
import subprocess
import sys
import tempfile

DOCS = pathlib.Path(__file__).resolve().parent
SOURCE = DOCS / "USER_MANUAL.md"
OUTPUT = DOCS / "EE_Calc_User_Manual.pdf"
VERSION = "0.2.0"

# Dark GitHub images -> light print images.
IMAGE_MAP = {
    "../preview.png": "screenshots/light/overview.png",
    "screenshots/e-series.png": "screenshots/light/e-series.png",
    "screenshots/divider-analyse.png": "screenshots/light/divider-analyse.png",
    "screenshots/divider-loaded.png": "screenshots/light/divider-loaded.png",
    "screenshots/divider-find-values.png": "screenshots/light/divider-find-values.png",
}

CSS = """
@font-face { font-family: DocVisby; src: local("VisbyCF-Regular"); font-weight: 400; }
@font-face { font-family: DocVisby; src: local("VisbyCF-Medium"); font-weight: 500; }
@font-face { font-family: DocVisby; src: local("VisbyCF-DemiBold"); font-weight: 600; }
@font-face { font-family: DocVisby; src: local("VisbyCF-Bold"); font-weight: 700; }

@page {
  size: letter portrait;
  margin: 0.6in 0.6in 0.75in 0.6in;
  @bottom-left {
    content: "EE Calc user manual  \\2014  v%(version)s  \\2014  %(date)s";
    font-family: DocVisby; font-size: 9pt; color: #4b4b56;
  }
  @bottom-right {
    content: "Page " counter(page) " of " counter(pages);
    font-family: DocVisby; font-size: 9pt; color: #4b4b56;
  }
}

/* No background fill anywhere: white paper, only text, borders and rules. */
*, *::before, *::after { background: transparent !important; box-shadow: none !important; }
html, body { background: #fff !important; print-color-adjust: economy; -webkit-print-color-adjust: economy; }

body { margin: 0; color: #1f1f1f; font-family: DocVisby; font-size: 12pt; font-weight: 400; line-height: 1.5; }
h1 { font-size: 20pt; font-weight: 600; margin: 0 0 6pt; border-bottom: 3px solid #644ac9; padding-bottom: 6pt; }
h1 + p { color: #4b4b56; font-size: 11pt; margin-top: 4pt; }
h2 { font-size: 14.5pt; font-weight: 600; margin: 18pt 0 6pt; padding-bottom: 3pt; border-bottom: 1px solid #cfcfde; break-after: avoid; }
h3 { font-size: 12.75pt; font-weight: 500; color: #644ac9; margin: 12pt 0 4pt; break-after: avoid; }
p { margin: 0 0 8pt; }
ul, ol { margin: 4pt 0 8pt 18pt; padding: 0; }
li { margin: 2pt 0; }
strong { font-weight: 600; }
em { font-style: normal; color: #4b4b56; }
a { color: #1f1f1f; text-decoration: none; }
code { font-family: DocVisby; font-weight: 500; color: #036a96; font-size: 11pt; }
pre { border: 1px solid #cfcfde; border-left: 3px solid #644ac9; padding: 6pt 10pt; margin: 4pt 0 10pt;
      white-space: pre-wrap; overflow-wrap: break-word; break-inside: avoid; }
pre code { color: #1f1f1f; font-weight: 500; font-size: 10.5pt; }
table { width: 100%%; border-collapse: collapse; font-size: 10.5pt; margin: 4pt 0 12pt; }
th, td { border: 1px solid #cfcfde; padding: 4pt 7pt; text-align: left; vertical-align: top; overflow-wrap: break-word; }
th { font-weight: 600; font-size: 10.5pt; border-bottom: 2px solid #b9b9c8; }
tr { break-inside: avoid; }
td code, th code { font-size: 10.5pt; }
hr { border: 0; border-top: 1px solid #cfcfde; margin: 16pt 0 8pt; }
hr + p { color: #4b4b56; font-size: 10pt; }
img { display: block; margin: 6pt auto 12pt; max-width: 100%%; break-inside: avoid; }
img.panel { width: 3.4in; }
img.overview { width: 100%%; }
"""


def find_chromium():
    hits = sorted(glob.glob(os.path.expanduser(
        "~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell")))
    if not hits:
        sys.exit("Playwright's Chromium headless shell was not found.")
    return hits[-1]


def main():
    html_body = subprocess.run(
        ["pandoc", "--from=gfm", "--to=html", str(SOURCE)],
        check=True, capture_output=True, text=True).stdout

    def swap(match):
        src = match.group(1)
        light = IMAGE_MAP.get(src, src)
        css_class = "overview" if light.endswith("overview.png") else "panel"
        return f'<img src="{light}" class="{css_class}"'

    html_body = re.sub(r'<img src="([^"]+)"', swap, html_body)
    missing = [p for p in re.findall(r'<img src="([^"]+)"', html_body) if not (DOCS / p).exists()]
    if missing:
        sys.exit(f"Missing images: {missing}")

    date = datetime.date.today().isoformat()
    page = ("<!doctype html><html><head><meta charset='utf-8'><title>EE Calc user manual</title>"
            f"<style>{CSS % {'version': VERSION, 'date': date}}</style></head>"
            f"<body>{html_body}</body></html>")

    # The HTML sits in docs/ so relative image paths resolve.
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=DOCS, delete=False, encoding="utf-8") as f:
        f.write(page)
        html_path = f.name
    try:
        subprocess.run([find_chromium(), "--headless", "--disable-gpu", "--no-sandbox",
                        "--no-pdf-header-footer", f"--print-to-pdf={OUTPUT}",
                        pathlib.Path(html_path).as_uri()],
                       check=True, capture_output=True, timeout=120)
    finally:
        os.unlink(html_path)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
