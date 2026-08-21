#!/usr/bin/env python3
"""Generate the Calamares netinstall tree for the Arch Colony installer.

Three sections come out of this:

  Bureaux            the desktop profiles, ported from archinstall
  Pilotes graphiques the graphics driver sets, ported from archinstall
  Dépôts             every package in core and extra

The desktop and driver data is derived from archinstall
(https://github.com/archlinux/archinstall), GPL-3.0-or-later, the same licence as
Arch Colony. Deriving it rather than curating a list by hand is deliberate: the
packages that make up a working GNOME or Hyprland session are a fact about Arch,
not an opinion this project should be forming on its own.

The repository listing is a snapshot taken when the ISO is built. archinstall can
regenerate it at install time because it runs pacman itself; Calamares reads a
static file, so a very old ISO will offer packages that have since been renamed.
Those simply fail to install — worth knowing, not worth blocking on.

Usage:
    tools/gen-netinstall.py --archinstall /path/to/archinstall > netinstall.yaml
"""

from __future__ import annotations

import argparse
import ast
import subprocess
import sys
from pathlib import Path

# Driver sets, from archinstall/lib/hardware.py (GfxDriver.gfx_packages).
#
# NVIDIA needs care here in a way it does not for Arch itself. The plain `nvidia`
# and `nvidia-dkms` packages no longer exist; of the two that remain, `nvidia-open`
# depends on `linux` and would drag the stock kernel onto a machine that ships
# linux-hardened (ADR-0004) — the same defect a code review already caught with
# broadcom-wl. So the open kernel module is offered only in its DKMS form, and
# linux-hardened-headers is added, which archinstall does not need because it lets
# the user pick the kernel separately.
DRIVERS = [
    ("Tous les pilotes libres", "Convient à toute machine, matériel inconnu compris", [
        "mesa", "xf86-video-amdgpu", "xf86-video-ati", "xf86-video-nouveau",
        "libva-intel-driver", "intel-media-driver", "vpl-gpu-rt", "libvpl",
        "vulkan-radeon", "vulkan-intel", "vulkan-nouveau",
    ]),
    ("AMD / ATI (libre)", "Cartes AMD et ATI", [
        "mesa", "xf86-video-amdgpu", "xf86-video-ati", "vulkan-radeon",
    ]),
    ("Intel (libre)", "Graphiques intégrés Intel", [
        "mesa", "libva-intel-driver", "intel-media-driver", "vpl-gpu-rt", "libvpl",
        "vulkan-intel",
    ]),
    ("NVIDIA — module noyau ouvert (Turing et plus récent)",
     "Module noyau ouvert, espace utilisateur propriétaire. Variante DKMS obligatoire : "
     "nvidia-open dépend du noyau linux standard, que cette distribution ne livre pas.", [
        "nvidia-open-dkms", "dkms", "linux-hardened-headers", "libva-nvidia-driver",
    ]),
    ("NVIDIA — nouveau (libre)", "Pilote entièrement libre, cartes plus anciennes", [
        "mesa", "xf86-video-nouveau", "vulkan-nouveau",
    ]),
    ("Machine virtuelle", "VirtualBox, QEMU, VMware", [
        "mesa",
    ]),
]


# Greeter packages and the unit to enable, from archinstall's
# ProfileHandler.install_greeter(). This matters more than it looks: archinstall
# does NOT put the greeter in Profile.packages, it installs it separately. Reading
# only `packages` therefore yields a desktop with no login manager, which installs
# cleanly and then boots to a text console.
#
# Keyed by the lowercased GreeterType member name, which is what the parser reads
# out of `return GreeterType.Xxx`. The enum *values* are different strings again
# (GreeterType.Lightdm == 'lightdm-gtk-greeter'), so neither the member name nor
# the value is a package name — the mapping has to be explicit.
GREETERS = {
    "lightdm": (["lightdm", "lightdm-gtk-greeter"], "lightdm"),
    "lightdmslick": (["lightdm", "lightdm-slick-greeter"], "lightdm"),
    "sddm": (["sddm"], "sddm"),
    "gdm": (["gdm"], "gdm"),
    "ly": (["ly"], "ly@tty1"),
    "cosmicsession": (["cosmic-greeter"], "cosmic-greeter"),
    "plasmaloginmanager": (["plasma-login-manager"], "plasmalogin"),
    "greetddms": (["greetd"], "greetd"),
}

# Profiles whose package list cannot be read statically, because it depends on a
# choice archinstall makes interactively. Arch Colony takes the default that
# archinstall itself marks as recommended.
OVERRIDES = {
    # PlasmaProfile.packages reads a flavour the user picks: plasma-meta,
    # plasma or plasma-desktop. Meta is the one archinstall labels "Recommended".
    # Its greeter is PlasmaLoginManager, not sddm.
    "plasma.py": {"name": "KDE Plasma", "packages": ["plasma-meta"],
                  "greeter": "plasmaloginmanager"},
}


# Offered from [colony], which — unlike multilib — the target's pacman.conf does
# get, because the cleanup step appends colony-repo.conf to it. So these install.
#
# A short, chosen list rather than the repository's contents. calamares is the
# installer and packages.conf removes it from the target on purpose;
# colony-keyring, colony-mirrorlist, colony-mkinitcpio, colony-release and
# colonyctl are already on the machine through the filesystem copy. Offering a
# package that is installed, or one that is about to be removed, teaches people
# not to trust the page.
# Colony Firewall Control is deliberately NOT here any more. It is installed
# into the target by packages.conf's try_install of colony-firewall-defaults,
# so offering it as a tick box would offer something already on its way — and a
# page that offers what you are getting anyway teaches people not to read it.
COLONY = [
    ("paru",
     "Assistant AUR, pour installer depuis les dépôts communautaires",
     ["paru"]),
]


def _strings(node: ast.AST, consts: dict[str, list[str]]) -> list[str] | None:
    """Flatten an expression into the strings it denotes, or None if it doesn't.

    Handles literals, lists and tuples of them, module-level constants, and
    `[...] + something` — the shape several profiles use to append a package the
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


def parse_desktop(path: Path) -> dict | None:
    """Pull name, packages and greeter out of an archinstall desktop profile.

    Parsed with `ast`, not with regular expressions. Regex parsing of Python
    cost this file twice: an exponential pattern CodeQL flagged as py/redos, and
    a profile silently dropped because one element of its package list was a
    module constant rather than a quoted literal — a list the old pattern could
    only reject wholesale. `ast` removes both classes of mistake, and the module
    constants it can now resolve are why niri_dms is offered at all.
    """
    if path.name in OVERRIDES:
        return dict(OVERRIDES[path.name], source=path.name)

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


def emit(groups: list[dict]) -> str:
    lines = ["# GENERATED by tools/gen-netinstall.py — do not edit.",
             "#",
             "# Desktop and driver data derived from archinstall (GPL-3.0-or-later).",
             "# Repository listings are a snapshot taken when the ISO was built.",
             ""]
    for g in groups:
        lines.append(f'- name: "{g["name"]}"')
        if g.get("description"):
            lines.append(f'  description: "{g["description"]}"')
        lines.append("  selected: false")
        lines.append(f'  expanded: {"true" if g.get("expanded") else "false"}')
        if g.get("noncheckable"):
            lines.append("  noncheckable: true")
        if g.get("packages"):
            lines.append("  packages:")
            lines.extend(f'    - "{p}"' for p in g["packages"])
        if g.get("subgroups"):
            lines.append("  subgroups:")
            for sub in g["subgroups"]:
                lines.append(f'    - name: "{sub["name"]}"')
                if sub.get("description"):
                    lines.append(f'      description: "{sub["description"]}"')
                lines.append("      selected: false")
                if sub.get("noncheckable"):
                    lines.append("      noncheckable: true")
                lines.append("      packages:")
                lines.extend(f'        - "{p}"' for p in sub["packages"])
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archinstall", required=True, type=Path,
                    help="path to an archinstall checkout")
    # multilib is deliberately absent. It is not enabled in the target's
    # pacman.conf — mkarchiso pacstraps with -G -M and installs pacman's stock
    # config, and the cleanup step only adds [colony] — so every lib32 package
    # offered here would fail to install, silently. Offering something that
    # cannot work is worse than not offering it.
    ap.add_argument("--repos", nargs="+", default=["core", "extra"])
    args = ap.parse_args()

    desktops_dir = args.archinstall / "archinstall" / "default_profiles" / "desktops"
    if not desktops_dir.is_dir():
        sys.exit(f"no desktop profiles under {desktops_dir}")

    desktops = []
    skipped = []
    for path in sorted(desktops_dir.glob("*.py")):
        if path.name in ("__init__.py", "utils.py"):
            continue
        parsed = parse_desktop(path)
        if parsed:
            desktops.append(parsed)
        else:
            skipped.append(path.name)

    if skipped:
        print(f"# profils non analysables, ignorés : {', '.join(skipped)}", file=sys.stderr)
    print(f"# {len(desktops)} bureaux extraits", file=sys.stderr)

    # The greeter is not part of archinstall's Profile.packages; it is installed
    # separately by install_greeter(). Without this, every desktop here would
    # install cleanly and then boot to a text console.
    for d in desktops:
        g = d.get("greeter")
        if g is None:
            continue
        if g not in GREETERS:
            sys.exit(f"{d['source']}: unknown GreeterType '{g}' — add it to GREETERS. "
                     "Refusing to emit a desktop that would install without a login manager.")
        pkgs, unit = GREETERS[g]
        d["packages"] = d["packages"] + [p for p in pkgs if p not in d["packages"]]
        d["greeter_unit"] = unit

    groups = [
        {
            "name": "Bureaux",
            "description": "Environnements de bureau et gestionnaires de fenêtres",
            "expanded": True,
            "subgroups": [
                {
                    "name": d["name"],
                    "description": (f"greeter : {d['greeter_unit']}" if d.get("greeter_unit")
                                    else "sans greeter par défaut"),
                    "packages": d["packages"],
                }
                for d in desktops
            ],
        },
        {
            "name": "Pilotes graphiques",
            "description": "Choisir celui qui correspond à la carte de la machine",
            "expanded": True,
            "subgroups": [
                {"name": n, "description": d, "packages": p} for n, d, p in DRIVERS
            ],
        },
        {
            "name": "Colony",
            "description": "Les programmes de l'écosystème, depuis le dépôt [colony]",
            "expanded": True,
            "subgroups": [
                {"name": n, "description": d, "packages": p} for n, d, p in COLONY
            ],
        },
    ]

    repos = repo_packages(args.repos)
    total = sum(len(v) for v in repos.values())
    print(f"# {total} paquets de dépôt", file=sys.stderr)
    # noncheckable, and this is not cosmetic. PackageTreeItem::setSelected walks
    # the source tree, so ticking "extra" would select all 14910 of its packages
    # in one click — and the filter proxy makes that easy to do by accident, since
    # a search leaves the group visible with only its matches shown underneath.
    # noncheckable removes Qt::ItemIsUserCheckable from the group alone; unlike
    # immutable it does not propagate, so individual packages stay selectable.
    groups.append({
        "name": "Dépôts",
        "description": f"Tous les paquets d'Arch ({total}). Utiliser la recherche.",
        "expanded": False,
        "noncheckable": True,
        "subgroups": [
            {"name": repo, "description": f"{len(names)} paquets",
             "noncheckable": True, "packages": names}
            for repo, names in repos.items()
        ],
    })

    print(emit(groups))


if __name__ == "__main__":
    main()
