# Décisions d'architecture

Un fichier par choix structurant. Une ADR n'est jamais réécrite : quand une décision change,
on en écrit une nouvelle qui remplace l'ancienne, et l'ancienne passe en *remplacée* avec un
lien. L'historique des choix vaut autant que les choix eux-mêmes.

| № | Décision | Statut |
|---|---|---|
| [0001](0001-derivee-sans-fork.md) | Arch Colony est une dérivée, pas un fork | acceptée |
| [0002](0002-regle-de-non-recouvrement.md) | L'overlay ne recouvre jamais un paquet d'Arch | acceptée |
| [0003](0003-lsm-par-etapes.md) | Durcissement LSM par étapes, SELinux en cible | acceptée |
| [0004](0004-noyau-linux-hardened.md) | Noyau `linux-hardened`, sans paquet maison | acceptée, **non validée** |
| [0005](0005-deux-editions.md) | Deux éditions : Hyprland et KDE Plasma | acceptée |
| [0006](0006-installateur-calamares.md) | Installateur Calamares brandé Colony | acceptée |
| [0007](0007-configuration-en-paquets.md) | Toute configuration est livrée comme paquet | acceptée |
| [0008](0008-chaine-de-confiance.md) | Chaîne de confiance et hébergement du dépôt | acceptée |
| [0009](0009-pile-du-bureau.md) | Pile du bureau : ce qu'on réutilise, ce qu'on écrit | acceptée |

**0002 contraint tout le reste.** Une proposition qui la viole ne se discute pas au cas par
cas : soit elle est reformulée, soit elle va dans un dépôt opt-in séparé.

**0004 est acceptée mais non validée** : elle repose sur une hypothèse de configuration
noyau qui n'a pas encore été vérifiée sur machine. Voir la section « À vérifier » de l'ADR.

## Statuts

- **proposée** — écrite, pas encore tranchée
- **acceptée** — en vigueur
- **acceptée, non validée** — tranchée, mais reposant sur une hypothèse non vérifiée
- **remplacée par XXXX** — plus en vigueur, conservée pour l'historique
