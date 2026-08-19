# Notes pour Claude

## Avant toute proposition

Lire [`docs/decisions/README.md`](docs/decisions/README.md). Sept décisions sont déjà prises
et ne se rediscutent pas au fil de l'eau — si l'une doit changer, on écrit une nouvelle ADR
qui remplace l'ancienne.

**ADR-0002 contraint tout.** Avant de proposer un paquet, appliquer son test : *après cette
modification, une mise à jour d'Arch peut-elle casser une machine Arch Colony alors qu'elle
n'aurait pas cassé une machine Arch ?* Si oui, ça ne va pas dans `[colony]`.

## Frontières avec les autres dépôts

Les dépôts de l'écosystème sont côte à côte dans `~/Documents/Repositories/`, non vendorés.
On les lit souvent ; on n'y écrit jamais depuis ici.

**Colony-Firewall-Control est en cours de réécriture par une autre session** (branche
`claude/colony-firewall-improvements-cf91d7`, worktree sous son `.claude/worktrees/`). Ne
rien y écrire, ne pas y lancer `cargo build` — ça entrerait en conflit sur `target/`.
Concevoir l'intégration contre l'interface de CFC (un paquet, des unités, un socket), pas
contre son code source.

Une modification nécessaire dans un programme Colony se fait dans son dépôt, pas ici. Ici on
écrit le `PKGBUILD`, les unités d'intégration et la configuration par défaut.

## Conventions

- **Documentation en français.** Le code, les noms de paquets et les commentaires de
  `PKGBUILD` restent en anglais.
- **Pas de couleur en dur.** Tout ce qui est visuel dérive des tokens de
  `Project-Colony-Resources` via une cible de générateur. Ajouter une cible est du travail en
  amont, dans ce dépôt-là.
- **Pas de script d'installation.** Tout fichier livré appartient à un paquet
  ([ADR-0007](docs/decisions/0007-configuration-en-paquets.md)).
- **Un jalon boote.** Ne pas proposer de livrable qui ne se vérifie pas sur machine ou en VM.

## Vérifier plutôt qu'affirmer

L'état des paquets, des options noyau et des outils change. Toute affirmation sur ce qu'Arch
livre en 2026 se vérifie contre les sources amont ou la machine, jamais de mémoire.

Point ouvert et bloquant : `CONFIG_DEBUG_INFO_BTF` dans `linux-hardened`. Voir la section
« À vérifier » de [ADR-0004](docs/decisions/0004-noyau-linux-hardened.md). Tant qu'il n'est
pas tranché, le choix du noyau est une hypothèse.
