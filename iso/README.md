# iso/

Profils `archiso`, un par édition, plus une base commune.

```
base/        ce que les deux éditions partagent
hyprland/    édition d'identité
plasma/      édition complète
```

## Règle

Un profil ISO **choisit des paquets**, il n'en fabrique pas. Aucun fichier livré par un ISO
qui ne vienne d'un paquet de `[colony]` ou du socle - voir
[ADR-0007](../docs/decisions/0007-configuration-en-paquets.md). L'`airootfs` d'un profil se
limite à ce qui est propre à l'environnement live et n'a aucun sens sur un système installé.

Conséquence utile : ce qui marche sur l'ISO marche après installation, parce que c'est le
même paquet.

## À traiter au moment de J1

- L'environnement live a besoin de réseau pour installer. Décider si CFC y est actif -
  probablement non, et le documenter comme un choix plutôt que le laisser par défaut.
- Les deux éditions doivent partager `base/` autant que possible. La qualité de cette
  séparation détermine le coût de J5.

## Pinned inputs

`build.sh` downloads two inputs that do not live in this repository: archinstall, for
the installer's desktop and driver lists, and `generated/themes.json` from
Project-Colony-Resources, for the installer's palette. [`pins.env`](pins.env) pins both
to a commit, and `themes.json` to a sha256 as well. [`fetch-inputs.sh`](fetch-inputs.sh)
fetches them, for the build and for CI alike, so CI checks exactly the inputs the next
image is built from.

To move a pin, edit `pins.env` in a pull request. CI resolves the templates and
generates the package trees from the new inputs before it merges. `pins.env` also lists
the nerd-fonts and OpenDyslexic releases `colony-fonts` is built from, and CI checks that
its PKGBUILD agrees.

## Language, font and text size

The boot menu offers the install medium in English (the default) and in French, each
also with speech, and with large text and OpenDyslexic. An entry is a set of kernel
parameters, which the boot menu can edit (press `e`):

| Parameter | Effect |
|---|---|
| `colony.lang=en\|fr` | Language of the live console, the message of the day, Calamares, its package page and its slideshow, and of the screen reader's voice |
| `colony.font=dyslexic` | OpenDyslexic instead of JetBrainsMono Nerd Font, in the whole installer |
| `colony.textscale=N` | The installer's text scale: 0.85, 1, 1.2 or 1.4, or any value from 0.7225 to 1.68 |
| `vconsole.keymap=fr`, `vconsole.font=ter-v22b` | systemd's own: the console keymap, and a larger console font |

[`colony-live-setup`](install/airootfs/usr/local/bin/colony-live-setup) applies the
`colony.*` ones at boot, to the live session only: the installed system takes the
language and keyboard chosen on the installer's pages. The font is chosen through the
one fontconfig file the installer reads, in
[`/usr/share/colony/fontconfig`](install/airootfs/usr/share/colony/fontconfig), and the
text scale reaches Qt as `QT_SCALE_FACTOR`. The text itself lives in en/fr tables:
[`config/netinstall.yaml`](../config/netinstall.yaml) for the package page, the
[live session's](install/airootfs/usr/share/colony/strings) and
[colonyctl's](../packages/colonyctl/en.sh) `en.sh`/`fr.sh`, and the slideshow's `en`/`fr`
objects. `tools/check-i18n.py` fails CI when a key is missing from one language.

To see the installer's theme at a text scale, in either font, without building an
image: `tools/preview-calamares-theme.py --scale 1.68 --font dyslexic`.

## The firewall on installed systems

Every installed system gets Colony Firewall Control, online or offline. The installer's
cleanup step installs `colony-firewall-defaults`, `colony-firewall-control` and
`colony-firewall-control-ebpf` into the target from a small signed repository the
medium carries at `/usr/share/colony/offline-repo`, before it enables networking, and
stops the install if they do not install or their units are not enabled.

`build.sh` assembles that repository with [`offline-repo.sh`](offline-repo.sh): it
copies the three packages and the signatures `repo/build.sh` made from `repo/out`, then
signs a `colony-offline` database over them with `COLONY_SIGNING_KEY`. The
[`pacman.conf`](install/airootfs/usr/share/colony/offline-repo/pacman.conf) next to it
requires a Colony signature on the database and on every package.

The live session never installs from it. A live medium that enabled the firewall
would hand the installer a fail-closed table and no network to finish with.

