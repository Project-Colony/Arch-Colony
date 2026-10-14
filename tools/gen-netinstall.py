#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate the Calamares netinstall trees for the Arch Colony installer.

The page has five sections: desktops, login screens, graphics drivers, Colony
programs, and every package in core and extra. Their wording, the drivers, the
login screens and the Colony programs are data, in config/netinstall.yaml. This
script checks that file's shape, adds the desktop profiles it parses out of
archinstall and the repository listing, and writes one tree per language,
because Calamares 3.4 reads no per-language keys in a netinstall tree:

  OUT/netinstall-LANG.yaml          the full page
  OUT/netinstall-offline-LANG.yaml  the placeholder for a session without network

The desktop profiles are derived from archinstall
(https://github.com/archlinux/archinstall), at the commit that ARCHINSTALL_COMMIT in
iso/pins.env names. Deriving them rather than curating a list by hand is
deliberate: the packages that make up a working GNOME or Hyprland session are a
fact about Arch, not an opinion this project should be forming on its own.

Licence: archinstall is GPL-3.0-only, not GPL-3.0-or-later like the rest of
Arch Colony. This file parses it, config/netinstall.yaml carries tables ported
from it, and the trees it writes are derived from both, so all of them are
GPL-3.0-only.

The repository listing is a snapshot taken when the ISO is built. archinstall can
regenerate it at install time because it runs pacman itself; Calamares reads a
static file, so a very old ISO will offer packages that have since been renamed.
Those simply fail to install - worth knowing, not worth blocking on.

Usage:
    tools/gen-netinstall.py --archinstall /path/to/archinstall --out DIR
"""

from __future__ import annotations

import argparse
import ast
import subprocess
import sys
from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parent.parent / "config" / "netinstall.yaml"
LANGS = ("en", "fr")


def fail(where: str, msg: str) -> "NoReturn":
    sys.exit(f"{CONFIG}: {where}: {msg}")


def _text(node, where: str) -> dict[str, str]:
    """A string a user reads: exactly one non-empty translation per language."""
    if (not isinstance(node, dict) or set(node) != set(LANGS)
            or not all(isinstance(v, str) and v.strip() for v in node.values())):
        fail(where, f"expected a non-empty {{{', '.join(LANGS)}}} pair, got {node!r}")
    return node


def _name(node, where: str) -> str:
    if not isinstance(node, str) or not node.strip():
        fail(where, f"expected a non-empty string, got {node!r}")
    return node


def _packages(node, where: str) -> list[str]:
    if not isinstance(node, list) or not node:
        fail(where, f"expected a non-empty package list, got {node!r}")
    for i, p in enumerate(node):
        _name(p, f"{where}[{i}]")
    return node


def _list(node, where: str) -> list[dict]:
    if not isinstance(node, list) or not node or not all(isinstance(e, dict) for e in node):
        fail(where, "expected a non-empty list of mappings")
    return node


def load_config(path: Path = CONFIG) -> dict:
    """Read config/netinstall.yaml and refuse anything the generator cannot render.

    A typo here would otherwise surface in the installer, as a group with no
    name or a page missing in one language, on a machine with no way to report it.
    """
    with open(path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict):
        fail("top level", "expected a mapping")

    groups = cfg.get("groups")
    if not isinstance(groups, dict):
        fail("groups", "expected a mapping")
    extra = {"desktops": ("expects_greeter", "expects_no_greeter"),
             "repositories": ("repository",)}
    for key in ("desktops", "greeters", "drivers", "colony", "repositories"):
        g = groups.get(key)
        if not isinstance(g, dict):
            fail(f"groups.{key}", "missing")
        for field in ("name", "description", *extra.get(key, ())):
            _text(g.get(field), f"groups.{key}.{field}")

    offline = cfg.get("offline")
    if not isinstance(offline, dict):
        fail("offline", "missing")
    for field in ("name", "description"):
        _text(offline.get(field), f"offline.{field}")

    for i, d in enumerate(_list(cfg.get("drivers"), "drivers")):
        _text(d.get("name"), f"drivers[{i}].name")
        _text(d.get("description"), f"drivers[{i}].description")
        _packages(d.get("packages"), f"drivers[{i}].packages")

    keys = set()
    for i, g in enumerate(_list(cfg.get("greeters"), "greeters")):
        where = f"greeters[{i}]"
        key = _name(g.get("key"), f"{where}.key")
        if key in keys:
            fail(f"{where}.key", f"'{key}' is listed twice")
        keys.add(key)
        _name(g.get("name"), f"{where}.name")
        _name(g.get("unit"), f"{where}.unit")
        _packages(g.get("packages"), f"{where}.packages")
        _text(g.get("description"), f"{where}.description")
        if not isinstance(g.get("selected", False), bool):
            fail(f"{where}.selected", "expected true or false")
    # One login screen, preselected: two would bring back the alias fight the
    # group exists to end, none would let a desktop install without one.
    if sum(g.get("selected", False) for g in cfg["greeters"]) != 1:
        fail("greeters", "exactly one must be selected")

    overrides = cfg.get("desktop_overrides", {})
    if not isinstance(overrides, dict):
        fail("desktop_overrides", "expected a mapping of profile file names")
    for source, o in overrides.items():
        where = f"desktop_overrides.{source}"
        if not isinstance(o, dict):
            fail(where, "expected a mapping")
        _name(o.get("name"), f"{where}.name")
        _packages(o.get("packages"), f"{where}.packages")
        if o.get("greeter") is not None and o["greeter"] not in keys:
            fail(f"{where}.greeter", f"'{o['greeter']}' is not a key under greeters")

    for i, c in enumerate(_list(cfg.get("colony"), "colony")):
        _name(c.get("name"), f"colony[{i}].name")
        _text(c.get("description"), f"colony[{i}].description")
        _packages(c.get("packages"), f"colony[{i}].packages")

    return cfg


def _strings(node: ast.AST, consts: dict[str, list[str]]) -> list[str] | None:
    """Flatten an expression into the strings it denotes, or None if it doesn't.

    Handles literals, lists and tuples of them, module-level constants, and
    `[...] + something` - the shape several profiles use to append a package the
    user is separately asked about.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [node.value]
    if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        out: list[str] = []
        for element in node.elts:
            got = _strings(element, consts)
            if got is None:
                return None
            out.extend(got)
        return out
    if isinstance(node, ast.Name):
        return list(consts[node.id]) if node.id in consts else None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _strings(node.left, consts)
        right = _strings(node.right, consts)
        if left is None and right is None:
            return None
        # One unresolvable side is fine: `return [ … ] + additional` holds a
        # seat-access package the user is asked about, and Arch Colony always
        # installs a greeter, which already provides a logind seat.
        return (left or []) + (right or [])
    return None


def parse_desktop(path: Path, overrides: dict) -> dict | None:
    """Pull name, packages and greeter out of an archinstall desktop profile.

    Parsed with `ast`, not with regular expressions. Regex parsing of Python
    cost this file twice: an exponential pattern CodeQL flagged as py/redos, and
    a profile silently dropped because one element of its package list was a
    module constant rather than a quoted literal - a list the old pattern could
    only reject wholesale. `ast` removes both classes of mistake, and the module
    constants it can now resolve are why niri_dms is offered at all.
    """
    if path.name in overrides:
        return dict(overrides[path.name], source=path.name)

    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except SyntaxError:
        return None

    # Module-level `NAME = 'x'` and `NAME = ['x', 'y']`, so a list element that
    # is a constant reference resolves instead of poisoning the whole list.
    consts: dict[str, list[str]] = {}
    for stmt in tree.body:
        if not isinstance(stmt, ast.Assign):
            continue
        got = _strings(stmt.value, consts)
        if got is None:
            continue
        for target in stmt.targets:
            if isinstance(target, ast.Name):
                consts[target.id] = got

    name = packages = greeter = None
    for node in ast.walk(tree):
        # `super().__init__('Hyprland', ProfileType.DesktopEnv, …)`
        if (name is None and isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "__init__"
                and isinstance(node.func.value, ast.Call)
                and isinstance(node.func.value.func, ast.Name)
                and node.func.value.func.id == "super"
                and node.args
                and isinstance(node.args[0], ast.Constant)
                and isinstance(node.args[0].value, str)):
            name = node.args[0].value

        if not isinstance(node, ast.FunctionDef):
            continue

        if node.name == "packages" and packages is None:
            for inner in ast.walk(node):
                if isinstance(inner, ast.Return) and inner.value is not None:
                    got = _strings(inner.value, consts)
                    if got:
                        packages = got
                        break

        if node.name == "default_greeter_type" and greeter is None:
            for inner in ast.walk(node):
                if (isinstance(inner, ast.Attribute)
                        and isinstance(inner.value, ast.Name)
                        and inner.value.id == "GreeterType"):
                    greeter = inner.attr.lower()
                    break

    if name is None or not packages:
        return None

    return {
        "name": name,
        "packages": packages,
        "greeter": greeter,
        "source": path.name,
    }


def repo_packages(repos: list[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for repo in repos:
        try:
            listing = subprocess.run(["pacman", "-Sl", repo],
                                     capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError as exc:
            sys.exit(f"cannot list repository '{repo}': {exc.stderr.strip()}")
        names = sorted({line.split()[1] for line in listing.splitlines() if line.strip()})
        if not names:
            sys.exit(f"repository '{repo}' returned no packages")
        out[repo] = names
    return out


def render(cfg: dict, desktops: list[dict], repos: dict[str, list[str]], lang: str) -> list[dict]:
    """The full page in one language, as the list of groups Calamares reads."""
    groups = cfg["groups"]

    def group(key: str, subgroups: list[dict], **fields) -> dict:
        return {"name": groups[key]["name"][lang],
                "description": groups[key]["description"][lang].format(**fields),
                "selected": False, "expanded": True, "subgroups": subgroups}

    def sub(name: str, description: str, packages: list[str], selected: bool = False) -> dict:
        return {"name": name, "description": description,
                "selected": selected, "packages": packages}

    total = sum(len(names) for names in repos.values())
    expects = groups["desktops"]
    return [
        group("desktops", [
            sub(d["name"],
                expects["expects_greeter"][lang].format(unit=d["greeter_unit"])
                if d.get("greeter_unit") else expects["expects_no_greeter"][lang],
                d["packages"])
            for d in desktops
        ]),
        group("greeters", [
            sub(g["name"], g["description"][lang], g["packages"], g.get("selected", False))
            for g in cfg["greeters"]
        ]),
        group("drivers", [
            sub(d["name"][lang], d["description"][lang], d["packages"]) for d in cfg["drivers"]
        ]),
        group("colony", [
            sub(c["name"], c["description"][lang], c["packages"]) for c in cfg["colony"]
        ]),
        # noncheckable, and this is not cosmetic. PackageTreeItem::setSelected walks
        # the source tree, so ticking "extra" would select all 14910 of its packages
        # in one click - and the filter proxy makes that easy to do by accident, since
        # a search leaves the group visible with only its matches shown underneath.
        # noncheckable removes Qt::ItemIsUserCheckable from the group alone; unlike
        # immutable it does not propagate, so individual packages stay selectable.
        dict(group("repositories", [
            dict(sub(repo, groups["repositories"]["repository"][lang].format(count=len(names)),
                     names), noncheckable=True)
            for repo, names in repos.items()
        ], total=total), expanded=False, noncheckable=True),
    ]


def render_offline(cfg: dict, lang: str) -> list[dict]:
    offline = cfg["offline"]
    return [{"name": offline["name"][lang], "description": offline["description"][lang],
             "selected": False, "expanded": False, "noncheckable": True, "packages": []}]


def write(path: Path, groups: list[dict]) -> None:
    header = ("# GENERATED by tools/gen-netinstall.py from config/netinstall.yaml - do not edit.\n"
              "# SPDX-License-Identifier: GPL-3.0-only\n"
              "#\n"
              "# Desktop, greeter and driver data derived from archinstall (GPL-3.0-only).\n"
              "# Repository listings are a snapshot taken when the ISO was built.\n\n")
    path.write_text(header + yaml.safe_dump(groups, allow_unicode=True, sort_keys=False),
                    encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archinstall", required=True, type=Path,
                    help="path to an archinstall checkout")
    ap.add_argument("--out", required=True, type=Path,
                    help="directory to write the trees into")
    # multilib is deliberately absent. It is not enabled in the target's
    # pacman.conf - mkarchiso pacstraps with -G -M and installs pacman's stock
    # config, and the cleanup step only adds [colony] - so every lib32 package
    # offered here would fail to install, silently. Offering something that
    # cannot work is worse than not offering it.
    ap.add_argument("--repos", nargs="+", default=["core", "extra"])
    args = ap.parse_args()

    cfg = load_config()
    greeters = {g["key"]: g for g in cfg["greeters"]}

    desktops_dir = args.archinstall / "archinstall" / "default_profiles" / "desktops"
    if not desktops_dir.is_dir():
        sys.exit(f"no desktop profiles under {desktops_dir}")

    desktops = []
    skipped = []
    for path in sorted(desktops_dir.glob("*.py")):
        if path.name in ("__init__.py", "utils.py"):
            continue
        parsed = parse_desktop(path, cfg.get("desktop_overrides", {}))
        if parsed:
            desktops.append(parsed)
        else:
            skipped.append(path.name)

    if skipped:
        print(f"# profiles that could not be parsed, skipped: {', '.join(skipped)}", file=sys.stderr)
    print(f"# {len(desktops)} desktops", file=sys.stderr)

    # The greeter is not part of archinstall's Profile.packages; it is installed
    # separately by install_greeter(). Without this, every desktop here would
    # install cleanly and then boot to a text console.
    for d in desktops:
        g = d.get("greeter")
        if g is None:
            continue
        if g not in greeters:
            sys.exit(f"{d['source']}: unknown GreeterType '{g}' - add it under greeters in "
                     f"{CONFIG}. Refusing to emit a desktop that would install without a "
                     "login manager.")
        # Kept for the description only. Merging these into d["packages"] is
        # what produced three greeters for three desktops; the login screen is
        # chosen once, in its own group.
        d["greeter_unit"] = greeters[g]["unit"]

    # Strip greeters from the desktop lists outright, because some profiles put
    # theirs in `packages` upstream - i3 lists lightdm and lightdm-gtk-greeter
    # itself - and archinstall does not mind, since install_greeter runs anyway
    # and pacman is idempotent. Here it matters: a desktop that quietly brings a
    # second greeter recreates the alias fight the separate group exists to end.
    greeter_pkgs = {pkg for g in greeters.values() for pkg in g["packages"]}
    for d in desktops:
        d["packages"] = [p for p in d["packages"] if p not in greeter_pkgs]

    repos = repo_packages(args.repos)
    print(f"# {sum(len(v) for v in repos.values())} repository packages", file=sys.stderr)

    args.out.mkdir(parents=True, exist_ok=True)
    for lang in LANGS:
        write(args.out / f"netinstall-{lang}.yaml", render(cfg, desktops, repos, lang))
        write(args.out / f"netinstall-offline-{lang}.yaml", render_offline(cfg, lang))


if __name__ == "__main__":
    main()
