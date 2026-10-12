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
generates the package tree from the new inputs before it merges.

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

