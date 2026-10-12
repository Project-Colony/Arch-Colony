# tools/

Outillage de développement : ce qui aide à construire Arch Colony sans faire partie
d'Arch Colony.

Rien de ce qui vit ici n'est livré à un utilisateur. Ce qui est livré est un paquet, dans
[`../packages/`](../packages/README.md).

## Checks run by CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs these on every pull request
and on every push to `main`, in an `archlinux:base-devel` container.

| Check | Run it locally with |
|---|---|
| shellcheck on every `*.sh`, `colonyctl` and the install scriptlets, `zsh -n` on the live session's `.zlogin`, `py_compile` on `tools/*.py` | the same commands |
| actionlint on every workflow, shellcheck included on each `run:` | `actionlint` |
| Which packages a release builds, and that a version older than the published one is refused | `tools/test-pending-packages.sh` |
| [ADR-0002](../docs/decisions/0002-regle-de-non-recouvrement.md): nothing in `packages/` shadows `[core]`, `[extra]` or `[multilib]` | `tools/check-shadowing.sh` |
| The `colony-mirrorlist` SigLevel migration | `tools/test-mirrorlist-migration.sh` |
| The signed `[colony]` chain end to end, and the installer's offline firewall repository through its own `pacman.conf`, signed in CI with a throwaway key | `tools/test-repo.sh` |
| The installer templates resolve in every palette of the pinned `themes.json`, and the package tree generates from the pinned archinstall | `iso/fetch-inputs.sh DIR`, then `tools/resolve-theme.py` and `tools/gen-netinstall.py` |
| Each package the change touches builds with `makepkg -s`, passes `namcap` without errors, and its `.SRCINFO` equals `makepkg --printsrcinfo` | `makepkg --printsrcinfo > .SRCINFO` |

`tools/test-repo.sh` trusts the key in `packages/colony-keyring/colony.gpg` unless
`COLONY_PUBKEY` names another public key file.

## Checks run by the release workflow

[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds, signs and
publishes a release, and runs these on the signed artefacts before anything is published.
A pull request that changes the workflow or these scripts runs the same chain as a dry
run, signed with a throwaway key.

| Step | Script |
|---|---|
| Build only what is newer than what `[colony]` serves; refuse a downgrade | `tools/pending-packages.sh` |
| The `[colony]` trust chain, on the very database about to be published | `COLONY_PREBUILT_DB=1 tools/test-repo.sh` |
| The image boots under KVM to a working live system, checked on its serial console | `tools/vm-headless.py smoke ISO` |

`tools/vm-headless.py smoke` runs locally too, on any image, with no window and no key.

## Driving an image in a VM

[`vm-headless.py`](vm-headless.py) boots an image in QEMU with no window and drives it
through the QEMU monitor and the guest agent. It needs KVM.

The offline install path, which has to put the firewall in from the medium:

```
tools/vm-headless.py start install --offline    # then install, keyboard only
tools/vm-headless.py installed --offline        # first boot of the installed disk
tools/vm-headless.py check-firewall             # fails unless the firewall runs
```

`check-firewall` asserts that `colony-firewall-nft`, `colony-firewalld` and
`colony-firewall-seed` are active and the eBPF object is installed, and prints
`colonyctl status`. `exec CMD` runs any other command in the guest.

## Prévu

- **Tests en VM.** Démarrage d'un ISO en QEMU, installation sans interaction, assertions sur
  l'état du système obtenu. Porte de sortie de release à partir de
  [J2](../docs/feuille-de-route.md#j2--installable-sur-disque---fait-le-2026-08-21).
