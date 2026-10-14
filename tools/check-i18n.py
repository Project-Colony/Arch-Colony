#!/usr/bin/env python3
"""Fail when an English string has no French twin, or the other way round.

    tools/check-i18n.py [ROOT]

English is canonical and French is a complete translation (I18N-1), so a key
exists in both languages or in neither (I18N-3). Checked across every place this
repository keeps user-visible text:

  config/*.yaml       every {en, fr} pair: both present and non-empty, with the
                      same {placeholders}
  **/en.sh + fr.sh    shell string tables (the live session's, colonyctl's):
                      the same keys, with the same printf conversions
  **/show.qml*        the slideshow's `en` and `fr` objects: the same keys

ROOT defaults to the repository this script lives in.
"""

import re
import sys
from pathlib import Path

import yaml

LANGS = ("en", "fr")
SHELL_KEY = re.compile(r'^([a-z][a-z0-9_]*)="', re.M)
PRINTF = re.compile(r"%[-+ #0-9.]*[a-zA-Z%]")
BRACE = re.compile(r"{(\w+)}")
QML_OBJECT = r"property var {}: \(\{{(.*?)\n\s*\}}\)"
QML_KEY = re.compile(r"^\s*([A-Za-z_]\w*)\s*:", re.M)


def check_pairs(node, where: str, errors: list[str]) -> int:
    """Walk a YAML document; every mapping with a language key is a pair."""
    found = 0
    if isinstance(node, dict):
        if set(node) & set(LANGS):
            found = 1
            if set(node) != set(LANGS):
                errors.append(f"{where}: has {sorted(node)}, expected {list(LANGS)}")
            elif not all(isinstance(v, str) and v.strip() for v in node.values()):
                errors.append(f"{where}: an empty or non-text translation")
            elif len({frozenset(BRACE.findall(v)) for v in node.values()}) > 1:
                errors.append(f"{where}: the languages use different {{placeholders}}")
            return found
        for key, value in node.items():
            found += check_pairs(value, f"{where}.{key}", errors)
    elif isinstance(node, list):
        for i, value in enumerate(node):
            found += check_pairs(value, f"{where}[{i}]", errors)
    return found


def shell_table(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    keys = SHELL_KEY.findall(text)
    # A value runs to the next key, which is close enough to count its printf
    # conversions: the comments between two keys carry none.
    starts = [m.start() for m in SHELL_KEY.finditer(text)] + [len(text)]
    return {k: text[a:b] for k, a, b in zip(keys, starts, starts[1:])}


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    errors: list[str] = []
    checked: list[str] = []

    for path in sorted((root / "config").glob("*.yaml")):
        rel = path.relative_to(root)
        n = check_pairs(yaml.safe_load(path.read_text(encoding="utf-8")), str(rel), errors)
        checked.append(f"{rel}: {n} pairs")

    for en in sorted(root.glob("**/en.sh")):
        fr = en.with_name("fr.sh")
        rel = en.parent.relative_to(root)
        if not fr.is_file():
            errors.append(f"{rel}: en.sh has no fr.sh")
            continue
        a, b = shell_table(en), shell_table(fr)
        for key in sorted(a.keys() - b.keys()):
            errors.append(f"{rel}: '{key}' is in en.sh only")
        for key in sorted(b.keys() - a.keys()):
            errors.append(f"{rel}: '{key}' is in fr.sh only")
        for key in sorted(a.keys() & b.keys()):
            if PRINTF.findall(a[key]) != PRINTF.findall(b[key]):
                errors.append(f"{rel}: '{key}' has different printf conversions in en.sh and fr.sh")
        checked.append(f"{rel}: {len(a)} keys")

    for path in sorted(root.glob("**/show.qml*")):
        rel = path.relative_to(root)
        text = path.read_text(encoding="utf-8")
        keys = {}
        for lang in LANGS:
            m = re.search(QML_OBJECT.format(lang), text, re.S)
            if m is None:
                errors.append(f"{rel}: no `property var {lang}` object")
                continue
            keys[lang] = set(QML_KEY.findall(m.group(1)))
        if len(keys) == len(LANGS):
            if keys["en"] != keys["fr"]:
                errors.append(f"{rel}: en and fr keys differ: {sorted(keys['en'] ^ keys['fr'])}")
            checked.append(f"{rel}: {len(keys['en'])} keys")

    for line in checked:
        print(f"    {line}")
    for line in errors:
        print(f"check-i18n: {line}", file=sys.stderr)
    if not checked:
        print("check-i18n: found no translations to check", file=sys.stderr)
        return 1
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
