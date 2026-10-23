# Arch Colony

Une distribution Linux dérivée d'Arch, pour l'écosystème [Project Colony](https://github.com/Project-Colony).

Arch Colony est de l'Arch Linux - mêmes dépôts, mêmes miroirs, même `pacman`, mêmes clés -
plus une couche : les programmes Colony, une identité visuelle dérivée du système de tokens
partagé, et un durcissement système assumé dont Colony Firewall Control est la couche réseau.

Ce n'est pas un fork. `[core]`, `[extra]` et `[multilib]` pointent vers les miroirs d'Arch
et ne sont jamais reconstruits. Un `pacman -Syu` sur Arch Colony reçoit les paquets d'Arch,
signés par Arch, à la vitesse d'Arch.

---

## Télécharger

[**archcolony-2026.10.24-x86_64.iso**](https://github.com/Project-Colony/Arch-Colony/releases/tag/iso-2026.10.24) - 1,7 Go

Vérifier avant de l'écrire sur quoi que ce soit. La somme de contrôle attrape un
téléchargement corrompu ; c'est la signature qui dit que l'image vient bien de nous.

```sh
gpg --verify archcolony-2026.10.24-x86_64.iso.sig archcolony-2026.10.24-x86_64.iso
sha256sum -c archcolony-2026.10.24-x86_64.iso.sha256
```

La clé est celle du paquet `colony-keyring`, empreinte
`5CD2 FCA1 3E69 1C65 A354  780D 80C1 18F7 74E6 C43F`.

---

## État

**Trois jalons sur sept sont faits, et se vérifient sur machine.**

| | | |
|---|---|---|
| **J0** | ✅ | le dépôt `[colony]` existe, signé, et sert ses paquets par HTTPS |
| **J1** | ✅ | une image démarre sous `linux-hardened` et se déclare Arch Colony |
| **J2** | ✅ | Calamares installe sur disque, la machine redémarre et ouvre une session |
| **J3** | ⏳ | le bureau et l'identité visuelle |

Ce que le dépôt sert aujourd'hui : `calamares`, `colonyctl`, `colony-firewall-control`
et sa couche noyau eBPF, `colony-firewall-defaults`, `colony-keyring`, `colony-mirrorlist`,
`colony-mkinitcpio`, `colony-release`, `paru`.

Le pare-feu s'installe et s'active tout seul : le démon, puis les douze règles système -
DNS, DHCP, NTP, pacman, ssh - puis seulement la table de filtrage. L'ordre est imposé par
systemd, parce que l'inverse donne une machine qui ressemble à une panne réseau.

Sur une machine installée, `[colony]` est déjà configuré - les paquets Colony arrivent par
`pacman -Syu` comme ceux d'Arch. `colonyctl status` dit ce qui tourne et ce qui protège.

| Document | Contenu |
|---|---|
| [Principes](docs/principes.md) | Ce à quoi on ne touche pas, et pourquoi |
| [Modèle](docs/modele.md) | Les quatre couches, le suivi de l'amont, l'échappatoire SELinux |
| [Décisions](docs/decisions/README.md) | Neuf ADR, dont une contraint toutes les autres |
| [Feuille de route](docs/feuille-de-route.md) | Sept jalons, chacun amorçable ou exécutable |

---

## La règle qui tient tout

> Aucun paquet de `[colony]` ne porte le nom d'un paquet de `[core]`, `[extra]` ou
> `[multilib]`.

C'est la [règle de non-recouvrement](docs/decisions/0002-regle-de-non-recouvrement.md).
Elle évite la classe de panne des mises à jour partielles, elle évite la fenêtre de
vulnérabilité entre un correctif d'Arch et notre reconstruction, et elle est la raison pour
laquelle SELinux n'arrive qu'en opt-in dans un dépôt séparé plutôt qu'au premier jour.

Test de la règle, pour toute proposition : *après cette modification, une mise à jour d'Arch
peut-elle casser une machine Arch Colony alors qu'elle n'aurait pas cassé une machine Arch ?*
Si oui, la proposition ne va pas dans `[colony]`.

---

## Arborescence

```
docs/          principes, modèle, décisions, feuille de route
  decisions/   un ADR par choix structurant
packages/      un répertoire par paquet de [colony]
iso/           profils archiso, un par édition
repo/          local package builds, and the offline key generator
tools/         outillage de développement
```

## Écosystème

Arch Colony empaquette les programmes Colony, il ne les modifie pas. Un correctif dans un
programme se fait dans son dépôt.

| Dépôt | Rôle ici |
|---|---|
| [Project-Colony-Resources](https://github.com/Project-Colony/Project-Colony-Resources) | Source des couleurs et des conventions - le thème système en dérive |
| [Colony](https://github.com/Project-Colony/Colony) | Le hub, livré sur les deux éditions |
| [Colony-Firewall-Control](https://github.com/Project-Colony/Colony-Firewall-Control) | La couche réseau du durcissement |
| [SphereCord](https://github.com/Project-Colony/SphereCord) | Client Discord, et le modèle de suivi de l'amont |
| hyprland-colony | Devient `colony-desktop-hyprland` |

## Code signing policy

Arch Colony signs what pacman and a bootloader consume, with the OpenPGP key
that the `colony-keyring` package installs:

| Signed | Signature |
|---|---|
| The installation image `archcolony-YYYY.MM.DD-x86_64.iso` | `<image>.sig` |
| Its checksum file `<image>.sha256` | `<image>.sha256.sig` |
| Every package in `[colony]` | `<package>.pkg.tar.zst.sig` |
| The repository databases `colony.db` and `colony.files` | `colony.db.sig`, `colony.files.sig` |
| The `colony-offline` database the image carries, from which the installer puts the firewall on every disk | `colony-offline.db.sig`, inside the image |

| Key | Fingerprint |
|---|---|
| Primary, certification only (RSA 4096) | `5CD2 FCA1 3E69 1C65 A354  780D 80C1 18F7 74E6 C43F` |
| Signing subkey (RSA 4096, expires 2029-08-18) | `088E 5521 9623 2B44 36B4  213C E32A 4FF5 7FFB 0D19` |

**Who signs, and where.** Releases are signed in CI only, by
[`.github/workflows/release.yml`](.github/workflows/release.yml), when a
release pull request opened by release-please is merged into `main`. The jobs
that build packages and images never see a key. Two separate jobs sign: they
check out nothing and build nothing, and they run in the repository's
`release` environment, whose secret holds the signing subkey alone. The
primary key never enters CI or this repository: it stays with the maintainer,
and is only needed to certify a new subkey or revoke one. A last job checks
every signature against `colony.gpg` before anything is published. Images
published before 2026-10 (the `iso-YYYY.MM.DD` releases) were signed by hand
with the same subkey. The reasoning is in
[ADR-0010](docs/decisions/0010-signing-in-ci.md).

**Verify an image.** Every release carries `colony.gpg`, also in this
repository at
[`packages/colony-keyring/colony.gpg`](packages/colony-keyring/colony.gpg). The
key is on no keyserver. Check its fingerprint against the table above first:

```sh
gpg --show-keys colony.gpg
gpg --import colony.gpg
gpg --verify archcolony-YYYY.MM.DD-x86_64.iso.sig archcolony-YYYY.MM.DD-x86_64.iso
gpg --verify archcolony-YYYY.MM.DD-x86_64.iso.sha256.sig archcolony-YYYY.MM.DD-x86_64.iso.sha256
sha256sum -c archcolony-YYYY.MM.DD-x86_64.iso.sha256
```

**Packages.** An installed Arch Colony verifies every package and database
itself: `colony-keyring` puts the key in pacman's keyring, and the `[colony]`
stanza says `SigLevel = Required DatabaseRequired`. To add `[colony]` to an
existing Arch Linux by hand, trust the key first:

```sh
pacman-key --add colony.gpg
pacman-key --lsign-key 5CD2FCA13E691C65A354780D80C118F774E6C43F
```

**Revocation.** What happens if a key is compromised, and how to report a
vulnerability, is in [SECURITY.md](SECURITY.md).

**Source code.** Every release carries `arch-colony-<version>-source.tar`,
with this repository at that version, the source of every `[colony]` package
and the pinned installer inputs, and `<image>.pkglist.txt`, which names every
package in the image with its exact version.

## Privacy

Arch Colony sends no telemetry, no analytics and no crash reports. It
contacts no server of its own: `[colony]` is served by GitHub.

| When | What is contacted | Why |
|---|---|---|
| Live image, by default | nothing | network interfaces stay down until you answer yes to the question at boot |
| Live image, network on | the NTP pool `[0-3].arch.pool.ntp.org` | systemd-timesyncd sets the clock |
| Installer, network on | `https://archlinux.org` | Calamares' internet check. Its GeoIP lookup is turned off |
| Installer, network on | `geo.mirror.pkgbuild.com`, `fastly.mirror.pkgbuild.com`, GitHub | the software you pick, and `[colony]` |
| Installed system | the NTP pool `[0-3].arch.pool.ntp.org` | systemd-timesyncd sets the clock |
| Installed system | the DNS servers your network provides, or else Quad9, Cloudflare and Google | systemd-resolved; those three are systemd's fallback |
| Installed system, weekly | `archlinux.org` | `reflector.timer` reads Arch's mirror status and rewrites `/etc/pacman.d/mirrorlist` |
| Installed system, weekly | `archlinux.org` | `archlinux-keyring-wkd-sync.timer` refreshes the Arch packager keys |
| `pacman -Syu` | the Arch mirrors in `/etc/pacman.d/mirrorlist` | Arch's packages |
| `pacman -Syu` | `github.com` and GitHub's download servers | `[colony]`. GitHub sees the IP address of every download |
| `paru`, when you run it | `aur.archlinux.org` | the AUR |

The Colony programs in `[colony]`, such as Colony Firewall Control, have their
own privacy policy in their repositories.

## Licence

GPL-3.0-or-later, comme le reste de l'écosystème.

One exception: [`tools/gen-netinstall.py`](tools/gen-netinstall.py) is GPL-3.0-only.
Its desktop, greeter and graphics driver tables are ported from
[archinstall](https://github.com/archlinux/archinstall), which is GPL-3.0-only, and so
is the installer package tree it generates into the install image.
