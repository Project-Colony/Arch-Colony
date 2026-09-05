#!/usr/bin/env python3
"""Fill @token@ placeholders in *.in files from the generated Colony palette.

    resolve-theme.py THEMES_JSON FAMILY/VARIANT FILE.in [FILE.in ...]

Every FILE.in is written next to itself without the suffix, with each @name@
replaced by the palette field of that name from Project-Colony-Resources'
generated/themes.json. A template names palette fields directly — @bg_primary@,
@accent_blue@ — so there is no second vocabulary to keep in step with the
artifact, and no colour is ever written down in this repository (principe 4).

Nothing is written until every template has resolved. A token that names no
palette field aborts the run: Qt drops a stylesheet rule it cannot parse without
a word, so a typo would otherwise ship as a silently unstyled widget.
"""

import json
import re
import sys
from pathlib import Path

TOKEN = re.compile(r"@([a-z][a-z0-9_]*)@")


def fail(msg: str) -> "NoReturn":
    print(f"resolve-theme: {msg}", file=sys.stderr)
    sys.exit(1)


def palette(themes_path: str, spec: str) -> tuple[dict, str]:
    with open(themes_path) as f:
        themes = json.load(f)
    family, _, variant = spec.partition("/")
    fam = next((f for f in themes["families"] if f.get("key") == family), None)
    if fam is None:
        names = ", ".join(sorted(f.get("key", "?") for f in themes["families"]))
        fail(f"no theme family '{family}' in {themes_path}\n  families: {names}")
    var = next((v for v in fam["variants"] if v.get("key") == variant), None)
    if var is None:
        names = ", ".join(sorted(v.get("key", "?") for v in fam["variants"]))
        fail(f"no variant '{variant}' in family '{family}'\n  variants: {names}")
    return var["palette"], f"{family}/{variant}"


def main(argv: list[str]) -> None:
    if len(argv) < 4:
        fail("usage: resolve-theme.py THEMES_JSON FAMILY/VARIANT FILE.in [FILE.in ...]")
    pal, name = palette(argv[1], argv[2])

    resolved: list[tuple[Path, Path, str]] = []
    for src in map(Path, argv[3:]):
        if src.suffix != ".in":
            fail(f"{src}: not a template (expected a .in suffix)")
        text = src.read_text()
        unknown = sorted({m for m in TOKEN.findall(text) if m not in pal})
        if unknown:
            fail(f"{src}: unknown palette field(s): {', '.join(unknown)}")
        resolved.append((src, src.with_suffix(""), TOKEN.sub(lambda m: pal[m.group(1)], text)))

    for src, dst, text in resolved:
        dst.write_text(text)
        src.unlink()
        print(f"    {src} -> {dst}")
    print(f"    {len(resolved)} template(s) resolved from {name} ({len(pal)} palette fields)")


if __name__ == "__main__":
    main(sys.argv)
