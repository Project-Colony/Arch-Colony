# ADR-0006 — Installateur : Calamares brandé Colony

**Statut** : acceptée — 2026-08-19

## Contexte

Un installateur doit gérer le partitionnement, LUKS2, l'installation du chargeur d'amorçage,
les utilisateurs, les locales, le fuseau, le clavier, et la génération de l'initramfs — puis
survivre à toutes les configurations matérielles qu'on n'a pas testées.

L'écosystème Colony est écrit en Rust avec `iced`, et un installateur maison utilisant
`colony-ui` serait visuellement parfaitement cohérent.

## Décision

Calamares, avec branding et modules de configuration Colony. C'est le modèle d'EndeavourOS
et de Garuda.

## Conséquences

On écrit du QML et de la configuration, pas un installateur. Le partitionnement et le
chiffrement sont des problèmes déjà résolus et éprouvés sur du matériel réel que nous n'avons
pas. Un premier ISO installable devient atteignable rapidement, ce qui satisfait le
[principe 6](../principes.md#6-chaque-jalon-boote).

En contrepartie, l'installateur ne ressemblera jamais tout à fait au reste de l'écosystème :
Calamares est en Qt, `colony-ui` est en `iced`. Le thème Qt de l'édition Plasma limite l'écart
côté Plasma ; côté Hyprland l'installateur restera visuellement étranger. C'est accepté.

Calamares devra aussi porter la logique d'amorçage propre à Arch Colony : semer le jeu de
règles initial du pare-feu, activer les unités système, et — si l'étape 2 de
[ADR-0003](0003-lsm-par-etapes.md) se concrétise — déclencher un réétiquetage SELinux.

## Amendement du 2026-08-20 — le coût réel, vérifié

La rédaction initiale disait « on écrit du QML et de la configuration, pas un
installateur ». C'était incomplet.

**Calamares n'est pas dans les dépôts d'Arch.** Vérifié : absent de `core`, `extra` et
`multilib`, absent aussi de `chaotic-aur`. Il n'existe que dans l'AUR (3.4.2, dernière
mise à jour 2026-03-23, 6 votes — signe que les dérivées maintiennent chacune la leur).

Choisir Calamares implique donc d'en devenir **packageur**. La bonne nouvelle est que le
coût est borné : ses onze dépendances de construction et d'exécution sont **toutes** dans
les dépôts officiels —

```
kcoreaddons  kpmcore  libpwquality  qt6-declarative  qt6-svg  yaml-cpp
extra-cmake-modules  libglvnd  ninja  qt6-tools  qt6-translations
```

— donc c'est un seul `PKGBUILD` dans `[colony]`, sans chaîne AUR derrière. Et comme
`calamares` n'existe pas en amont, il ne viole pas
[ADR-0002](0002-regle-de-non-recouvrement.md).

**L'obligation récurrente**, en revanche, est réelle : Calamares est une application
Qt6/KF6, et les montées de version de Qt ou des KDE Frameworks dans Arch la casseront
périodiquement. Chaque rupture est une reconstruction chez nous, entre le moment où Arch
publie et celui où notre ISO redevient constructible. C'est le prix, et il se paie à
chaque cycle Qt, pas une fois.

La décision est maintenue : ce coût reste inférieur à celui d'écrire un installateur, et
c'est exactement ce que font EndeavourOS et Garuda.

## Alternatives écartées

- **Installateur Colony maison en Rust/iced** — cohérence visuelle totale, mais réimplémenter
  partitionnement, chiffrement et installation du chargeur d'amorçage est un projet entier,
  systématiquement sous-estimé, et dont les défaillances se manifestent chez l'utilisateur
  sur du matériel inconnu. À reconsidérer une fois la distribution stable, jamais avant.
- **`archinstall` avec un profil Colony** — le plus rapide à livrer, mais une expérience en
  TUI pour une distribution qui se définit en partie par son soin visuel.
