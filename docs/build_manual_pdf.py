#!/usr/bin/env python3
"""Build a private low-ink manual using Visby and the Alucard Documents Standard.

The manifest supplies the version. Screenshots are omitted from the print
edition; their captions refer to the illustrated Markdown manual. No dark
or stale light-mode screenshot is silently substituted.

    python3 docs/build_manual_pdf.py
    python3 docs/build_manual_pdf.py --html-only

Requires pandoc and a Chromium-family browser (or EE_CALC_CHROMIUM).
The generated PDF/HTML are private local artifacts, not release assets.
"""

import argparse
import datetime
import html
import json
import shutil
import os
import pathlib
import re
import subprocess
import sys

DOCS = pathlib.Path(__file__).resolve().parent
SOURCE = DOCS / "USER_MANUAL.md"
OUTPUT = DOCS / "EE_Calc_User_Manual.pdf"
MANIFEST = DOCS.parent / "manifest.json"

CSS = """
@font-face { font-family: Visby; src: local("VisbyCF-Regular"); font-weight: 400; }
@font-face { font-family: Visby; src: local("VisbyCF-Medium"); font-weight: 500; }
@font-face { font-family: Visby; src: local("VisbyCF-DemiBold"); font-weight: 600; }
@font-face { font-family: Visby; src: local("VisbyCF-Bold"); font-weight: 700; }

@page {
  size: letter portrait;
  margin: 0.6in 0.6in 0.75in 0.6in;
  @bottom-left {
    content: "EE Calc user manual  \\2014  v%(version)s  \\2014  %(date)s";
    font-family: Visby; font-size: 9pt; color: #4b4b56; font-feature-settings: "ss01";
  }
  @bottom-right {
    content: "Page " counter(page) " of " counter(pages);
    font-family: Visby; font-size: 9pt; color: #4b4b56; font-feature-settings: "ss01";
  }
}

/* No background fill anywhere: white paper, only text, borders and rules. */
*, *::before, *::after { background: transparent !important; box-shadow: none !important; }
html, body { background: #fff !important; print-color-adjust: economy; -webkit-print-color-adjust: economy; }

body { margin: 0; color: #1f1f1f; font-family: Visby; font-size: 12pt; font-weight: 400; line-height: 1.5; }
@media screen { body { max-width: 1050px; margin: 24px auto; padding: 0 24px; } }
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
code { font-family: Visby; font-weight: 500; color: #036a96; font-size: 11pt; }
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
/* Visby's default zero is round, like a capital O. Its stylistic set 1
   has an oval zero; it is switched on for each 0 alone (wrapped by
   oval_zeros below), so M, i and j keep their default shapes. The footer
   cannot hold markup, so ss01 applies to its whole line; it has no M, i
   or j in it. */
.z { font-feature-settings: "ss01"; }
img.overview { width: 100%%; }
"""


def oval_zeros(html):
    """Wrap each 0 in text in <span class="z">, leaving tags, attributes
    (image paths, links) and character references such as &#160; alone."""
    def text(segment):
        return re.sub(r"&#?\w+;|0",
                      lambda m: '<span class="z">0</span>' if m.group(0) == "0" else m.group(0),
                      segment)
    parts = re.split(r"(<[^>]*>)", html)
    return "".join(part if part.startswith("<") else text(part) for part in parts)


def find_chromium():
    override = os.environ.get("EE_CALC_CHROMIUM")
    if override:
        path = shutil.which(override)
        if path:
            return path
        sys.exit("EE_CALC_CHROMIUM is not an executable browser path.")
    base = pathlib.Path.home() / ".cache/ms-playwright"
    hits = list(base.glob("chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell"))
    hits += list(base.glob("chromium_headless_shell-*/chrome-linux/headless_shell"))
    hits = [p for p in hits if p.is_file() and os.access(p, os.X_OK)]
    if hits:
        return str(max(hits, key=lambda p: int(re.search(r"shell-(\d+)", str(p)).group(1))))
    for name in ("chromium", "chromium-browser", "google-chrome", "brave"):
        if path := shutil.which(name):
            return path
    sys.exit("No Chromium browser found; use --html-only or set EE_CALC_CHROMIUM.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--html-only", action="store_true")
    args = parser.parse_args()
    version = json.loads(MANIFEST.read_text())["version"]
    source = SOURCE.read_text()
    declared = re.search(r"^Version\s+(\S+)", source, re.M)
    if not source.startswith("# EE Calc") or not declared or declared.group(1).removesuffix(".") != version:
        sys.exit("Manual version must match manifest.json before printing.")
    html_body = subprocess.run(
        ["pandoc", "--from=gfm", "--to=html", str(SOURCE)],
        check=True, capture_output=True, text=True).stdout
    # The print edition is complete text/tables. Existing captures remain in
    # the illustrated manual with their capture-version qualification.
    def screen_reference(match):
        alt = re.search(r'alt="([^"]*)"', match.group(0))
        label = html.unescape(alt.group(1)) if alt else "screen example"
        return "<em>Illustration in the electronic manual: " + html.escape(label) + ".</em>"
    html_body = re.sub(r"<img\b[^>]*>", screen_reference, html_body, flags=re.S)
    html_body = oval_zeros(html_body)
    date = datetime.date.today().isoformat()
    page = ("<!doctype html><html><head><meta charset='utf-8'><title>EE Calc user manual</title>"
            f"<style>{CSS % {'version': version, 'date': date}}</style></head>"
            f"<body>{html_body}</body></html>")
    html_path = OUTPUT.with_suffix(".html")
    html_path.write_text(page, encoding="utf-8")
    if args.html_only:
        print(f"wrote {html_path}")
        return
    subprocess.run([find_chromium(), "--headless", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", f"--print-to-pdf={OUTPUT}",
                    html_path.as_uri()], check=True, capture_output=True, timeout=60)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
