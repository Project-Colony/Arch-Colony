# ADR-0003 — Durcissement LSM par étapes, SELinux en cible

**Statut** : acceptée — 2026-08-19

## Contexte

La demande initiale est d'avoir « toutes les protections de SELinux, Rocky, etc. ».
L'intention est claire : un niveau de durcissement de la famille RHEL, pas un Arch avec
trois `sysctl`.

Le problème est qu'Arch ne prend pas SELinux en charge officiellement. L'activer suppose de
reconstruire et de maintenir en continu une quinzaine de paquets de base — `systemd`,
`coreutils`, `pam`, `shadow`, `util-linux`, `sudo`, `cronie`, `openssh`, `dbus`, plus la
pile `libselinux`/`libsemanage`/`libsepol`/`policycoreutils` — et de porter une politique de
référence. C'est frontalement contraire à [ADR-0002](0002-regle-de-non-recouvrement.md).

Par ailleurs, « les protections de Rocky » ne se réduisent pas à SELinux. L'essentiel de ce
qui rend une machine RHEL défendable — `auditd`, `fapolicyd`, USBGuard, AIDE, le durcissement
PAM, le confinement des unités systemd — ne dépend pas du LSM majeur et fonctionne sur Arch
sans recompiler quoi que ce soit.

## Décision

Le durcissement se fait en deux temps.

**Étape 1 — ce qui ne coûte aucun recouvrement.** AppArmor comme LSM majeur (support natif
Arch, présent dans le noyau), Landlock et lockdown en complément, plus les contrôles issus de
la famille RHEL qui fonctionnent tels quels : `auditd`, USBGuard, AIDE, `fapolicyd`,
durcissement PAM, confinement systemd des services, et CFC pour la couche réseau.

**Étape 2 — SELinux comme profil dédié.** Dans un dépôt `[colony-selinux]` séparé et
désactivé par défaut, une fois que le dépôt `[colony]` et sa CI de reconstruction
fonctionnent. L'utilisateur qui l'active accepte explicitement de quitter la garantie de
non-recouvrement.

## Un seul LSM majeur à la fois

Précision vérifiée le 2026-08-19, qui rend la bascule entre les deux étapes beaucoup moins
coûteuse qu'il n'y paraît.

Le noyau n'autorise qu'**un seul LSM « majeur »** actif — SELinux *ou* AppArmor, jamais les
deux. La documentation du noyau est explicite : aux capabilities, toujours présentes,
s'ajoutent un nombre quelconque de modules mineurs et *au plus un* module majeur. Les
modules mineurs — Landlock, lockdown, Yama, bpf — s'empilent librement avec celui qu'on
retient.

Les deux sont **déjà compilés** dans les noyaux d'Arch, `linux` comme `linux-hardened` : il
n'y a rien à activer côté noyau, seulement à choisir au démarrage. Mesuré sur `linux`
7.1.8-arch1-3 :

```
CONFIG_SECURITY_SELINUX=y   CONFIG_SECURITY_APPARMOR=y
CONFIG_LSM="landlock,lockdown,yama,integrity,bpf"
```

Noter la dernière ligne : par défaut Arch n'active **aucun** des deux. Une machine Arch
n'a aujourd'hui aucun contrôle d'accès obligatoire. L'étape 1 ne remplace donc pas SELinux
par quelque chose de moindre — elle apporte du confinement là où il n'y en a aucun.

**Conséquence sur le plan.** Passer de l'étape 1 à l'étape 2 est un changement de paramètre
d'amorçage plus un changement de dépôt, pas une réécriture. Le travail réel de l'étape 2
reste entièrement dans l'espace utilisateur.

## Conséquences

Le premier ISO amorçable arrive sans attendre la reconstruction de la base. Le durcissement
livré à l'étape 1 est réel, pas symbolique — il couvre la majorité de ce qui est reproché à
un Arch nu.

En contrepartie, la granularité d'une politique SELinux ciblée n'est pas atteinte à l'étape 1,
et AppArmor confine par chemin plutôt que par étiquette, ce qui est plus fragile face aux
liens symboliques et aux montages.

**À vérifier avant l'étape 2** : l'état réel en 2026 du groupe AUR `selinux` et de la
politique de référence pour Arch. S'ils sont abandonnés, l'étape 2 change de nature — il
faudrait porter une politique depuis Fedora, ce qui est un projet à part entière et
justifierait de rouvrir cette ADR.

## Alternatives écartées

- **SELinux dès le départ** — fidèle à la demande initiale, mais repousse indéfiniment le
  premier ISO et impose un rebuild à chaque mise à jour d'Arch touchant la base.
- **AppArmor comme socle définitif** — supprime la dette, mais renonce à la cible demandée.
  Écarté : l'étape 2 reste l'objectif, pas une option abandonnée.
