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
| [ADR-0002](../docs/decisions/0002-regle-de-non-recouvrement.md): nothing in `packages/` shadows `[core]`, `[extra]` or `[multilib]` | `tools/check-shadowing.sh` |
| The `colony-mirrorlist` SigLevel migration | `tools/test-mirrorlist-migration.sh` |
| The signed `[colony]` chain end to end, signed in CI with a throwaway key | `tools/test-repo.sh` |
| The installer templates resolve in every palette of the pinned `themes.json`, and the package tree generates from the pinned archinstall | `iso/fetch-inputs.sh DIR`, then `tools/resolve-theme.py` and `tools/gen-netinstall.py` |
| Each package the change touches builds with `makepkg -s`, passes `namcap` without errors, and its `.SRCINFO` equals `makepkg --printsrcinfo` | `makepkg --printsrcinfo > .SRCINFO` |

`tools/test-repo.sh` trusts the key in `packages/colony-keyring/colony.gpg` unless
`COLONY_PUBKEY` names another public key file.

## Prévu

- **Tests en VM.** Démarrage d'un ISO en QEMU, installation sans interaction, assertions sur
  l'état du système obtenu. Porte de sortie de release à partir de
  [J2](../docs/feuille-de-route.md#j2--installable-sur-disque---fait-le-2026-08-21).
