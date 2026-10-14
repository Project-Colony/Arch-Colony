# repo/

Construction, signature et publication du dépôt `[colony]`.

## Chaîne

```
packages/<nom>/PKGBUILD
   ↓  construction en chroot propre (devtools)
   ↓  signature du paquet
   ↓  repo-add dans la base de données
   ↓  signature de la base de données
   ↓  publication
[colony] servi aux utilisateurs
```

## Points qui se paient cher s'ils sont bâclés

**La clé de signature.** Elle est la racine de confiance de toute machine Arch Colony. Où
vit la clé privée, qui y a accès, et comment on révoque en cas de compromission sont des
questions à trancher **avant** le premier paquet publié - après, chaque utilisateur installé
est un coût de migration.

**La construction en chroot propre.** Construire sur la machine de développement produit des
paquets qui dépendent de ce qui s'y trouvait par hasard. `devtools` existe pour ça.

**L'amorçage de la confiance.** `colony-keyring` doit être installable avant que le dépôt ne
soit vérifiable, ce qui est circulaire. Le mécanisme employé par `archlinux-keyring` est la
référence à suivre.

## Publishing

Nothing here publishes. Releases are built, signed and published by
[`.github/workflows/release.yml`](../.github/workflows/release.yml): the signing subkey
lives only in that workflow's `release` environment, and the certification key never
leaves its owner. See [ADR-0010](../docs/decisions/0010-signing-in-ci.md).

`build.sh` builds and signs packages locally, for testing an image with
`iso/build.sh`. `genkey.sh` is the offline tool that created the key, kept for the
record and for a key rotation; it never runs in CI.

## Jalon

C'est [J0](../docs/feuille-de-route.md#j0--le-dépôt-existe---fait-le-2026-08-19), le premier, précisément parce
qu'une erreur ici se paie par une réinstallation chez tout le monde.
