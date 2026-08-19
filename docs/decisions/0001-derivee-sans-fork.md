# ADR-0001 — Arch Colony est une dérivée, pas un fork

**Statut** : acceptée — 2026-08-19

## Contexte

Une distribution basée sur Arch peut prendre deux formes. Soit elle reconstruit tout ou
partie des dépôts d'Arch sous son propre nom et sert ses propres paquets de base — c'est un
fork. Soit elle laisse les dépôts d'Arch en place et ajoute une couche par-dessus — c'est une
dérivée.

Le propriétaire du projet a explicitement demandé la seconde forme, en citant la relation
entre SphereCord et Equibop : un dérivé qui suit l'amont plutôt qu'un embranchement qui s'en
détache.

## Décision

`[core]`, `[extra]` et `[multilib]` pointent vers les miroirs officiels d'Arch, déclarés
exactement comme Arch les déclare. `archlinux-keyring` reste la racine de confiance du socle.
Arch Colony ajoute un dépôt `[colony]` et rien d'autre.

## Conséquences

**Positives.** Les correctifs de sécurité d'Arch arrivent sans latence introduite par nous.
La charge de maintenance ne croît pas avec la taille du socle. Un utilisateur peut auditer
que sa base est de l'Arch authentique.

**Négatives.** On ne peut pas modifier le comportement d'un paquet de base. Toute
personnalisation doit passer par de la configuration, un `drop-in` systemd, ou un paquet
distinct — jamais par un correctif amont.

**Contrainte permanente.** Une décision d'Arch peut invalider une des nôtres sans qu'aucun
paquet que nous livrons ne change. Ce flux doit être surveillé activement ; voir
`upstream/`.

## Alternatives écartées

- **Fork complet des dépôts** — donne le contrôle total, coûte une équipe de mainteneurs à
  plein temps. Sans objet pour ce projet.
- **Recouvrement partiel de quelques paquets clés** — la version raisonnable en apparence,
  et le chemin par lequel on devient un fork sans l'avoir décidé. Interdit par
  [ADR-0002](0002-regle-de-non-recouvrement.md).
