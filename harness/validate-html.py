#!/usr/bin/env python3
"""Validate the project's HTML docs without a browser.

Checks every <dir>/index.html in the repo:
  - tag balance (well-formedness)
  - local href/src targets resolve relative to each page's own directory
  - CSS custom properties used are defined in assets/crt.css
  - @font-face woff2 sources referenced by crt.css exist
  - no stray CDN font references (we self-host the font)

Run:  python3 harness/validate-html.py     (or: make validate)
Exits non-zero if any problem is found, so it doubles as a CI gate.
"""
import glob
import html.parser
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}
# assets/status.js is a gitignored, generated overlay — absent on a fresh clone.
OPTIONAL = {"assets/status.js"}


def tag_errors(src):
    stack, errs = [], []

    class Parser(html.parser.HTMLParser):
        def handle_starttag(self, tag, attrs):
            if tag not in VOID:
                stack.append(tag)

        def handle_endtag(self, tag):
            if stack and stack[-1] == tag:
                stack.pop()
            else:
                errs.append(f"stray </{tag}>")

    Parser().feed(src)
    if stack:
        errs.append("unclosed: " + ", ".join(stack))
    return errs


def link_errors(src, page_dir):
    errs = []
    for ref in sorted(set(re.findall(r'(?:href|src)="([^"#:]+)(?:#[^"]*)?"', src))):
        if ref.startswith("http"):
            continue
        target = os.path.join(page_dir, ref)
        if os.path.relpath(target, REPO) in OPTIONAL:
            continue
        if not os.path.exists(target):
            errs.append(f"missing ref: {ref}")
    return errs


def main():
    css_path = os.path.join(REPO, "assets", "crt.css")
    css = open(css_path, encoding="utf-8").read() if os.path.exists(css_path) else ""
    defined = set(re.findall(r"(--[a-z0-9-]+)\s*:", css))

    pages = sorted(set(
        glob.glob(os.path.join(REPO, "index.html"))
        + glob.glob(os.path.join(REPO, "*/index.html"))
        + glob.glob(os.path.join(REPO, "*/*/index.html"))
    ))

    problems = 0
    for page in pages:
        src = open(page, encoding="utf-8").read()
        errs = tag_errors(src) + link_errors(src, os.path.dirname(page))
        undef = set(re.findall(r"var\((--[a-z0-9-]+)\)", src)) - defined
        if undef:
            errs.append(f"undefined css vars: {sorted(undef)}")
        if "fonts.googleapis" in src or "cdn.jsdelivr" in src:
            errs.append("stray CDN reference (fonts are self-hosted)")
        print(f"[{'OK' if not errs else 'FAIL'}] {os.path.relpath(page, REPO)}")
        for e in errs:
            print(f"      - {e}")
        problems += len(errs)

    print("\n@font-face sources:")
    for u in re.findall(r"url\('([^']+\.woff2)'\)", css):
        ok = os.path.exists(os.path.join(REPO, "assets", u))
        print(f"  {'OK  ' if ok else 'MISS'} assets/{u}")
        problems += 0 if ok else 1

    print("\n" + ("ALL OK" if not problems else f"{problems} problem(s) found"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
