# iso/

Profils `archiso`, un par édition, plus une base commune.

```
base/        ce que les deux éditions partagent
hyprland/    édition d'identité
plasma/      édition complète
```

## Règle

Un profil ISO **choisit des paquets**, il n'en fabrique pas. Aucun fichier livré par un ISO
qui ne vienne d'un paquet de `[colony]` ou du socle — voir
[ADR-0007](../docs/decisions/0007-configuration-en-paquets.md). L'`airootfs` d'un profil se
limite à ce qui est propre à l'environnement live et n'a aucun sens sur un système installé.

Conséquence utile : ce qui marche sur l'ISO marche après installation, parce que c'est le
même paquet.

## À traiter au moment de J1

- L'environnement live a besoin de réseau pour installer. Décider si CFC y est actif —
  probablement non, et le documenter comme un choix plutôt que le laisser par défaut.
- Les deux éditions doivent partager `base/` autant que possible. La qualité de cette
  séparation détermine le coût de J5.
