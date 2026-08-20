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
import re
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


def parse_desktop(path: Path) -> dict | None:
    """Pull name, packages and greeter out of an archinstall desktop profile.

    Several profiles build the list as `return [ … ] + additional`, where
    `additional` holds a seat-access package the user is asked about. Arch Colony
    always installs a greeter, which provides a logind seat, so the extra package
    is not needed and only the literal list is taken.
    """
    if path.name in OVERRIDES:
        return dict(OVERRIDES[path.name], source=path.name)

    src = path.read_text(encoding="utf-8")

    name = re.search(r"super\(\)\.__init__\(\s*\n?\s*'([^']+)'", src)
    if not name:
        return None

    # The body of the packages property, up to the next decorator or class.
    body = re.search(
        r"def packages\(\s*self\s*\)\s*->\s*list\[str\]:(.*?)(?=\n\t@|\nclass |\Z)",
        src, re.S)
    if not body:
        return None

    # The first bracketed list of string literals inside it.
    listing = re.search(r"\[\s*((?:\s*'[^']+'\s*,?)+)\s*\]", body.group(1), re.S)
    if not listing:
        return None
    packages = re.findall(r"'([^']+)'", listing.group(1))
    if not packages:
        return None

    greeter = re.search(r"def default_greeter_type.*?GreeterType\.(\w+)", src, re.S)
    return {
        "name": name.group(1),
        "packages": packages,
        "greeter": greeter.group(1).lower() if greeter else None,
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
