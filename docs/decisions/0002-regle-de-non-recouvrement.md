# ADR-0002 — Règle de non-recouvrement

**Statut** : acceptée — 2026-08-19
**Portée** : contraint toutes les décisions suivantes

## Contexte

[ADR-0001](0001-derivee-sans-fork.md) pose qu'Arch Colony est une dérivée. Cette position
n'est pas stable en soi : une dérivée devient un fork paquet par paquet, chaque fois qu'une
exception paraît justifiée localement. Il faut une règle qui rende l'exception visible.

## Décision

**Aucun paquet du dépôt `[colony]` ne porte le nom d'un paquet de `[core]`, `[extra]` ou
`[multilib]`.**

Pas de `provides`/`replaces` visant un paquet du socle. Pas de `IgnorePkg`. Pas d'épinglage
de version. Si une fonctionnalité exige de remplacer un paquet de base, elle ne va pas dans
`[colony]` — elle va dans un dépôt séparé, désactivé par défaut, dont l'activation est un
acte délibéré de l'utilisateur.

## Conséquences

**Ce que la règle achète.** Pas de mises à jour partielles causées par nous : la classe de
panne où `[colony]` livre un `systemd` reconstruit pendant qu'Arch en publie un plus récent,
et où l'utilisateur se retrouve avec une base incohérente, disparaît par construction. Pas de
fenêtre de vulnérabilité entre le correctif d'Arch et notre reconstruction. Pas de rebuild
en cascade à chaque `soname` bump.

**Ce que la règle coûte.** SELinux devient impossible dans le dépôt principal, puisqu'il
exige `systemd-selinux`, `coreutils-selinux`, `pam-selinux`, `shadow-selinux`,
`util-linux-selinux` et une dizaine d'autres. C'est le coût réel de la règle, et il est
assumé : voir [ADR-0003](0003-lsm-par-etapes.md).

**Ce que la règle rend possible.** Le dépôt `[colony-selinux]`, séparé, opt-in, où le
recouvrement est autorisé parce que l'utilisateur a explicitement accepté d'en sortir. La
garantie reste intacte pour tous les autres.

## Test de la règle

Une proposition viole cette ADR si sa mise en œuvre implique de répondre « oui » à :
*« est-ce qu'après cette modification, une mise à jour d'Arch peut casser une machine Arch
Colony alors qu'elle n'aurait pas cassé une machine Arch ? »*
