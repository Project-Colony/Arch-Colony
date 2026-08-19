# ADR-0007 — Toute configuration est livrée comme paquet

**Statut** : acceptée — 2026-08-19

## Contexte

L'écosystème Colony distribue aujourd'hui de la configuration par script : `hyprland-colony`
livre un `install.sh` qui copie des fichiers dans le répertoire de l'utilisateur. C'est un
modèle adapté à un dépôt qu'on clone soi-même. Il ne l'est pas pour une distribution.

Un fichier déposé par un script est invisible pour `pacman` : jamais mis à jour, jamais
retiré à la désinstallation, et écrasé sans avertissement à la prochaine exécution du script.
Multiplié par le nombre d'utilisateurs et de mises à jour, c'est une dette impossible à
rattraper une fois les machines déployées.

## Décision

Tout fichier livré par Arch Colony appartient à un paquet. Aucun script d'installation dans
l'ISO ou dans les paquets, en dehors des `.install` de `pacman` pour les actions qui ne
peuvent pas être des fichiers (`systemctl daemon-reload`, `vconsole`, mise à jour de cache).

Les fichiers de `/etc` destinés à être modifiés par l'utilisateur sont déclarés dans
`backup=`, pour que `pacman` produise des `.pacnew` au lieu d'écraser.

## Conséquences

Chaque configuration devient un paquet avec un cycle de vie : version, dépendances,
désinstallation propre, et un chemin de mise à jour qui respecte les modifications locales.

Le coût est de l'écriture de `PKGBUILD` en amont de tout le reste, y compris pour des paquets
qui ne contiennent que des fichiers texte. C'est le prix d'un système désinstallable.

Cas particulier des fichiers utilisateur : un paquet ne peut pas écrire dans `/home`. La
configuration de session est livrée dans `/etc/skel` pour les nouveaux comptes, et dans
`/usr/share/colony/` comme référence pour les comptes existants. Le mécanisme qui propose à
un utilisateur existant d'adopter une nouvelle version de la configuration reste à concevoir —
il ne doit en aucun cas écraser silencieusement.
