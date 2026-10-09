# Security Policy

Arch Colony ships the packages in `[colony]`, the ISO images that install it,
and the OpenPGP key every installed machine trusts to sign both. Its packages
install as root, their scriptlets run as root, and `colony-keyring` decides
which signatures `pacman` accepts. A flaw here reaches every machine, so
security reports are handled before anything else.

## Supported versions

| What | Supported |
| --- | --- |
| The latest ISO image (the newest `iso-YYYY.MM.DD` release) | yes |
| The rolling `[colony]` repository (the `repo` release) | yes |
| Older ISO images | no |

`[colony]` is rolling, like Arch: a fix ships as a new package version, and
`pacman -Syu` delivers it. Older images are not rebuilt or re-signed. A system
installed from one is current again after `pacman -Syu`.

## Reporting a vulnerability

Do not open a public issue. Report it privately through GitHub's private
vulnerability reporting:

<https://github.com/Project-Colony/Arch-Colony/security/advisories/new>

Include what you have:

- What an attacker controls and what they gain.
- The ISO date or the package name and version (`pacman -Q <name>`).
- Reproduction steps, or a proof of concept.

What to expect:

- Arch Colony has a single maintainer. Acknowledgement is best effort, usually
  within a week.
- An accepted report is fixed in `[colony]` (and in a new image when the image
  itself is affected) before public disclosure, coordinated with you. You are
  credited in the advisory unless you prefer otherwise.
- A declined report gets a short explanation.

## Scope

In scope:

- **`[colony]` packages**: the PKGBUILDs under `packages/`, their install
  scriptlets, and the files and systemd units they ship. This includes the
  firewall defaults (`colony-firewall-defaults`) and the two downstream
  Calamares patches.
- **The `colony-keyring` trust root**: the key it installs, its
  `colony-trusted` and `colony-revoked` lists, and the build, signing and
  publishing scripts under `repo/` and `iso/`.
- **ISO images**: the archiso profiles under `iso/`, the live session and its
  boot configuration.
- **The Calamares installer configuration** under
  `iso/install/airootfs/etc/calamares/`, including the `shellprocess` steps,
  which run as root.
- **`colonyctl`**.

Out of scope, and better reported upstream:

- Packages from Arch's `[core]`, `[extra]` and `[multilib]`. Arch Colony
  serves them unchanged from Arch's mirrors; report those to
  [Arch Linux](https://security.archlinux.org/).
- The code of Colony Firewall Control, Calamares and paru. Report those to
  [Colony Firewall Control](https://github.com/Project-Colony/Colony-Firewall-Control/security/advisories/new),
  [Calamares](https://github.com/calamares/calamares) and
  [paru](https://github.com/Morganamilo/paru).

A packaging or configuration choice in this repository that makes an upstream
flaw exploitable, or weakens a protection upstream provides, is in scope.

## The signing key

Every package in `[colony]`, its database and every ISO image are signed with
the OpenPGP key that `colony-keyring` installs:

```
5CD2 FCA1 3E69 1C65 A354  780D 80C1 18F7 74E6 C43F
```

An installed machine requires both kinds of signature. The `[colony]` stanza
in `/etc/pacman.conf` sets `SigLevel = Required DatabaseRequired`, so pacman
refuses a package or a database that is unsigned or signed by a key it does
not trust. `colonyctl status` shows this as `database signature`.

The primary key only certifies. Signatures are made by a separate signing
subkey (RSA 4096, expiring 2029-08-18), so that subkey can be replaced without
asking anyone to trust a new key. The reasoning is in
[ADR-0008](docs/decisions/0008-chaine-de-confiance.md).

### If the signing subkey is compromised

1. Revoke the subkey with the primary key and add a new signing subkey.
2. Release a new `colony-keyring` whose `colony.gpg` carries the revocation
   and the new subkey.
3. Re-sign every package and the database with the new subkey and republish
   `[colony]`, then rebuild, sign and republish the current ISO.
4. Publish a security advisory that names the exposure window, the new subkey
   fingerprint, and the commands to import the updated `colony.gpg` with
   `pacman-key --add`. A machine cannot verify packages signed by a subkey it
   has never seen, so this one step is manual.

### If the primary key is compromised

1. Add its fingerprint to `colony-revoked`. `pacman-key --populate` disables
   every key listed there on each machine that installs the update.
2. Generate a new key, put it in `colony.gpg` and `colony-trusted`, and
   release `colony-keyring` with all three files updated.
3. Re-sign and republish `[colony]` and the current ISO, as above.
4. Publish the revocation certificate, which is kept offline and never in this
   repository, and a security advisory with the new fingerprint. Every
   installed machine has to import and trust the new key by hand: that is the
   limit ADR-0008 accepted.
