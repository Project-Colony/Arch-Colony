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

## Alternatives écartées

- **Installateur Colony maison en Rust/iced** — cohérence visuelle totale, mais réimplémenter
  partitionnement, chiffrement et installation du chargeur d'amorçage est un projet entier,
  systématiquement sous-estimé, et dont les défaillances se manifestent chez l'utilisateur
  sur du matériel inconnu. À reconsidérer une fois la distribution stable, jamais avant.
- **`archinstall` avec un profil Colony** — le plus rapide à livrer, mais une expérience en
  TUI pour une distribution qui se définit en partie par son soin visuel.
