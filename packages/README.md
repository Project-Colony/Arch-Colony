# packages/

Un répertoire par paquet du dépôt `[colony]`, contenant un `PKGBUILD` et les fichiers qu'il
installe.

## Règle d'admission

Un paquet n'entre ici que s'il **n'existe pas** dans `[core]`, `[extra]` ou `[multilib]`.
Voir [ADR-0002](../docs/decisions/0002-regle-de-non-recouvrement.md). Les paquets qui
recouvrent la base — la pile SELinux le jour venu — vont dans un dépôt séparé, pas ici.

## Familles

| Famille | Nature | Exemples prévus |
|---|---|---|
| Programmes | Nos logiciels | `colony`, `colony-firewall-control`, `spherecord` |
| Configuration | Des fichiers, aucun code | `colony-desktop-hyprland`, `colony-plymouth-theme` |
| Méta-paquets | Uniquement des `depends=` | `colony-base`, `colony-hardened` |
| Amorçage | La racine de confiance | `colony-keyring`, `colony-mirrorlist` |
| Système | Politique système | `colony-hardening-sysctl`, `colony-release` |

## Conventions

- Préfixe `colony-`, sauf pour les programmes portant déjà leur propre nom.
- Tout fichier de `/etc` modifiable par l'utilisateur est déclaré dans `backup=`.
- Les `.install` sont réservés à ce qui ne peut pas être un fichier : `daemon-reload`, mise à
  jour de cache, `vconsole`. Jamais de copie de fichiers.
- Configuration de session : dans `/etc/skel` pour les nouveaux comptes, et
  `/usr/share/colony/` comme référence. Un paquet n'écrit pas dans `/home`.
