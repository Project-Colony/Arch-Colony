# Arch Colony

Une distribution Linux dérivée d'Arch, pour l'écosystème [Project Colony](https://github.com/Project-Colony).

Arch Colony est de l'Arch Linux — mêmes dépôts, mêmes miroirs, même `pacman`, mêmes clés —
plus une couche : les programmes Colony, une identité visuelle dérivée du système de tokens
partagé, et un durcissement système assumé dont Colony Firewall Control est la couche réseau.

Ce n'est pas un fork. `[core]`, `[extra]` et `[multilib]` pointent vers les miroirs d'Arch
et ne sont jamais reconstruits. Un `pacman -Syu` sur Arch Colony reçoit les paquets d'Arch,
signés par Arch, à la vitesse d'Arch.

---

## État

**Conception.** Rien n'est encore construit. Les fondations — ce qu'on fait, ce qu'on refuse
de faire, et dans quel ordre — sont écrites :

| Document | Contenu |
|---|---|
| [Principes](docs/principes.md) | Ce à quoi on ne touche pas, et pourquoi |
| [Modèle](docs/modele.md) | Les quatre couches, le suivi de l'amont, l'échappatoire SELinux |
| [Décisions](docs/decisions/README.md) | Sept ADR, dont une contraint toutes les autres |
| [Feuille de route](docs/feuille-de-route.md) | Sept jalons, chacun amorçable ou exécutable |

Prochain jalon : **J0 — le dépôt `[colony]` existe et sert un paquet.**

---

## La règle qui tient tout

> Aucun paquet de `[colony]` ne porte le nom d'un paquet de `[core]`, `[extra]` ou
> `[multilib]`.

C'est la [règle de non-recouvrement](docs/decisions/0002-regle-de-non-recouvrement.md).
Elle évite la classe de panne des mises à jour partielles, elle évite la fenêtre de
vulnérabilité entre un correctif d'Arch et notre reconstruction, et elle est la raison pour
laquelle SELinux n'arrive qu'en opt-in dans un dépôt séparé plutôt qu'au premier jour.

Test de la règle, pour toute proposition : *après cette modification, une mise à jour d'Arch
peut-elle casser une machine Arch Colony alors qu'elle n'aurait pas cassé une machine Arch ?*
Si oui, la proposition ne va pas dans `[colony]`.

---

## Arborescence

```
docs/          principes, modèle, décisions, feuille de route
  decisions/   un ADR par choix structurant
packages/      un répertoire par paquet de [colony]
iso/           profils archiso, un par édition
repo/          construction, signature et publication du dépôt
upstream/      surveillance des décisions d'Arch
tools/         outillage de développement
```

## Écosystème

Arch Colony empaquette les programmes Colony, il ne les modifie pas. Un correctif dans un
programme se fait dans son dépôt.

| Dépôt | Rôle ici |
|---|---|
| [Project-Colony-Resources](https://github.com/Project-Colony/Project-Colony-Resources) | Source des couleurs et des conventions — le thème système en dérive |
| [Colony](https://github.com/Project-Colony/Colony) | Le hub, livré sur les deux éditions |
| [Colony-Firewall-Control](https://github.com/Project-Colony/Colony-Firewall-Control) | La couche réseau du durcissement |
| [SphereCord](https://github.com/Project-Colony/SphereCord) | Client Discord, et le modèle de suivi de l'amont |
| hyprland-colony | Devient `colony-desktop-hyprland` |

## Licence

GPL-3.0-or-later, comme le reste de l'écosystème.
