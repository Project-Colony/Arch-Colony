# Le modèle

Comment Arch Colony est assemblé. Les principes qui justifient ces choix sont dans
[`principes.md`](principes.md).

---

## Quatre couches

```
┌──────────────────────────────────────────────────────────────────┐
│  4. IMAGES        iso/hyprland     iso/plasma                     │
│                   profils archiso → un ISO amorçable              │
├──────────────────────────────────────────────────────────────────┤
│  3. PROFILS       colony-base  colony-desktop-*  colony-hardened  │
│                   méta-paquets : ce qui s'installe ensemble       │
├──────────────────────────────────────────────────────────────────┤
│  2. OVERLAY       dépôt [colony]                                  │
│                   uniquement ce qui n'existe pas en amont         │
├──────────────────────────────────────────────────────────────────┤
│  1. SOCLE         [core] [extra] [multilib] — miroirs d'Arch      │
│                   consommé tel quel, jamais reconstruit           │
└──────────────────────────────────────────────────────────────────┘
```

Chaque couche ne dépend que de celles en dessous. Une image est une composition de profils,
un profil est une composition de paquets, un paquet vient de l'overlay ou du socle.

### Couche 1 — le socle

Les miroirs d'Arch, non modifiés. Notre `pacman.conf` les déclare exactement comme Arch les
déclare, avec `archlinux-keyring` comme racine de confiance. Aucune priorité, aucun
`IgnorePkg`, aucun épinglage.

### Couche 2 — l'overlay `[colony]`

Un seul dépôt, déclaré **avant** `[core]` dans `pacman.conf`. Cette position ne sert pas à
recouvrir quoi que ce soit — la [règle d'or](principes.md#2-loverlay-ne-recouvre-jamais-un-paquet-darch)
l'interdit — elle sert à ce que nos méta-paquets résolvent leurs dépendances chez nous en
priorité lorsqu'un nom existe des deux côtés par accident.

Le contenu se répartit en cinq familles :

| Famille | Exemples | Nature |
|---|---|---|
| Programmes Colony | `colony`, `colony-firewall-control`, `spherecord` | Nos logiciels |
| Configuration | `colony-desktop-hyprland`, `colony-plymouth-theme` | Des fichiers, aucun code |
| Méta-paquets | `colony-base`, `colony-hardened` | Uniquement des `depends=` |
| Amorçage | `colony-keyring`, `colony-mirrorlist` | La racine de confiance |
| Système | `colony-hardening-sysctl`, `colony-nftables` | Politique système |

### Couche 3 — les profils

Un profil est un méta-paquet sans contenu propre. Installer Arch Colony revient à installer
`colony-base` plus une édition de bureau, éventuellement plus `colony-hardened`.

```
colony-base
├── colony-keyring, colony-mirrorlist
├── linux-hardened, linux-hardened-headers
├── colony-hardening-sysctl
└── colony-firewall-control

colony-desktop-hyprland          colony-desktop-plasma
├── colony-base                  ├── colony-base
├── hyprland, waybar, …          ├── plasma-meta, …
├── colony-theme-hyprland        ├── colony-theme-plasma
└── colony                       └── colony

colony-hardened   (optionnel, opt-in)
├── auditd, usbguard, aide, fapolicyd
└── colony-hardening-profiles
```

### Couche 4 — les images

Deux profils `archiso`, partageant tout ce qui peut l'être. Un ISO n'ajoute rien qui ne
soit pas empaqueté : il choisit des paquets et un `airootfs` minimal.

---

## Le suivi de l'amont

C'est la mécanique qui donne son nom à la relation avec Arch. Deux flux distincts, à ne pas
confondre :

**Flux descendant — les paquets.** Automatique et permanent : les miroirs d'Arch servent
directement les utilisateurs. Rien à faire de notre côté, c'est le bénéfice de la règle d'or.

**Flux montant — les décisions.** Arch change parfois des choses qui nous concernent sans
changer un paquet que nous livrons : un défaut de `mkinitcpio`, une bascule vers `dracut`,
un changement dans la chaîne d'amorçage, un remplacement de `netctl`. Ce flux-là est
surveillé, pas automatique. Un travail périodique lit les annonces d'Arch et ouvre un ticket
quand une décision amont invalide une des nôtres.

Le second flux est celui qu'on oublie, et c'est celui qui casse les dérivées.

---

## L'échappatoire SELinux

La règle d'or interdit de recouvrir la base. SELinux l'exige. La contradiction se résout
par la séparation, pas par l'exception :

```
[colony]           ← garantie de non-recouvrement, tout le monde
[colony-selinux]   ← recouvre la base, opt-in explicite
```

Un utilisateur qui active `[colony-selinux]` accepte explicitement de sortir de la garantie :
il reçoit des `systemd`, `coreutils`, `pam`, `shadow`, `util-linux` reconstruits par nous, et
donc notre latence de correctif plutôt que celle d'Arch. Le dépôt est désactivé par défaut,
et son activation est une action délibérée, documentée pour ce qu'elle coûte.

Cette structure permet de commencer SELinux sans mettre en jeu la stabilité de la
distribution principale, et de l'abandonner sans rien casser si le coût se révèle
insoutenable. Voir [ADR-0003](decisions/0003-lsm-par-etapes.md).

---

## La frontière avec les autres dépôts Colony

Arch Colony **empaquette** les programmes Colony, il ne les modifie pas. Un correctif dans
CFC se fait dans CFC ; ici on n'écrit que le `PKGBUILD`, les unités systemd d'intégration et
la configuration par défaut.

Le contrat avec chaque programme tient en trois points : un artefact installable, une
interface stable (chemins, unités, sockets), et un manifeste `colony.json` conforme au schéma
de `Project-Colony-Resources`. Ce qu'il y a derrière ne nous regarde pas.

Cette frontière a une conséquence directe sur le travail en cours : **CFC est une boîte
noire.** On conçoit l'intégration contre son interface — un paquet, des unités, un socket —
et non contre son code source, qui bouge.

---

## Arborescence du dépôt

```
docs/          principes, modèle, décisions, feuille de route
decisions/     un ADR par choix structurant, jamais réécrit, seulement remplacé
packages/      un répertoire par paquet de [colony] — PKGBUILD et fichiers
iso/           profils archiso, un par édition
repo/          construction, signature et publication du dépôt [colony]
upstream/      surveillance des décisions d'Arch (le flux montant)
tools/         outillage de développement
```
