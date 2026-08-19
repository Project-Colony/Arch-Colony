# upstream/

Surveillance des décisions d'Arch Linux.

## Pourquoi ce répertoire existe

Le [modèle](../docs/modele.md#le-suivi-de-lamont) distingue deux flux venant de l'amont.

Le **flux descendant** — les paquets — est automatique : les miroirs d'Arch servent
directement les utilisateurs, et c'est tout le bénéfice de la règle de non-recouvrement.
Rien à surveiller.

Le **flux montant** — les décisions — ne l'est pas. Arch change parfois quelque chose qui
nous concerne sans toucher un seul paquet que nous livrons : un défaut de `mkinitcpio`, une
bascule d'outillage, un changement dans la chaîne d'amorçage, une dépréciation. Aucune alerte
ne se déclenche de notre côté, et la dérive ne se remarque qu'au moment où un ISO ne démarre
plus.

C'est ce flux-là qui casse les distributions dérivées, et c'est celui qu'on oublie de
surveiller.

## Contenu

- Ce qu'on surveille : annonces Arch, `arch-dev-public`, changements de `devtools` et
  d'`archiso`, et les paquets dont nos décisions dépendent sans que nous les livrions —
  `linux-hardened` en premier lieu.
- L'automatisation qui ouvre un ticket quand une décision amont invalide une des nôtres.

Rien n'est encore écrit ici. À traiter au plus tard à [J2](../docs/feuille-de-route.md),
quand la chaîne d'amorçage commence à dépendre de choix d'Arch.
