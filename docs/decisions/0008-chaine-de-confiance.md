# ADR-0008 — Chaîne de confiance et hébergement du dépôt

**Statut** : acceptée — 2026-08-19

## Contexte

Le dépôt `[colony]` doit être signé. La clé qui le signe engage toutes les machines qui
installeront Arch Colony : quiconque la détient peut faire installer n'importe quel paquet
sur ces machines sans qu'aucun avertissement n'apparaisse. Et changer de clé après coup
impose une manœuvre manuelle à chaque personne déjà installée.

Aucune clé n'existait au moment de cette décision (`gpg --list-secret-keys` : 0).

Ces choix se font donc **avant** le premier paquet publié, pas après.

## Décision

**Clé.** Une clé RSA 4096 dédiée au projet, générée sur la machine de développement,
protégée par phrase de passe, avec une sauvegarde chiffrée sur un support débranché. RSA
plutôt qu'une courbe elliptique pour la compatibilité maximale avec les versions de `pacman`
et de GnuPG en circulation.

**Hébergement.** Le dépôt est publié comme actifs d'une *release* GitHub sur
`Project-Colony/Arch-Colony`, sous un tag dédié `repo`. Pas de serveur à administrer, la
bande passante est prise en charge, et la CI publie directement.

## Conséquences

**Ce que ça simplifie.** Aucune infrastructure à maintenir pour J0. La publication est une
commande `gh release upload`. La chaîne complète — construire, signer, publier — tient dans
deux scripts.

**Ce que ça contraint.** Les actifs d'une release GitHub sont un espace plat : pas de
hiérarchie par architecture. Sans conséquence tant qu'on ne cible que `x86_64`, à revoir
sinon. GitHub impose aussi une taille maximale par actif, ce qui deviendra un sujet pour les
ISO à partir de J1 — l'hébergement des images est une question distincte de celle du dépôt de
paquets, et sera tranchée séparément.

**Ce qui reste à concevoir.** La récupération après compromission. Aujourd'hui, si la clé
fuite, il faut publier une clé neuve et demander à chaque utilisateur de l'importer à la
main. C'est acceptable tant que la base d'utilisateurs est proche de zéro ; ça ne l'est plus
ensuite.

**Chemin de sortie prévu.** Migrer vers le modèle d'Arch — clé maîtresse hors ligne servant
uniquement à certifier, sous-clé de signature au quotidien — permet de révoquer la sous-clé
sans que personne n'ait à changer de clé de confiance. La migration est indolore *si* la clé
créée aujourd'hui porte déjà une sous-clé de signature distincte de la clé maîtresse. C'est
pour cette raison que la génération en crée une, et non pour un besoin immédiat.

## Alternatives écartées

- **Clé matérielle (YubiKey)** — la partie privée ne quitte jamais le jeton, donc une machine
  compromise ne la livre pas. Plus solide, écarté pour l'instant faute de matériel ; reste le
  meilleur choix quand le projet aura des utilisateurs.
- **Stockage objet + CDN** — nécessaire le jour où les ISO s'ajoutent, inutile pour J0.
- **VPS** — contrôle total contre une machine à tenir à jour et à sécuriser en permanence,
  c'est-à-dire du travail système récurrent sans rapport avec le projet.
