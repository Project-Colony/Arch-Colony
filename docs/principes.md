# Principes

Ce document est la pensée d'Arch Colony. Il ne décrit pas ce qu'on construit — c'est le
rôle de [`modele.md`](modele.md) — mais ce à quoi on refuse de toucher, et pourquoi.

Une distribution ne meurt pas d'un mauvais choix technique. Elle meurt d'une dette de
maintenance contractée un jour où quelqu'un a trouvé qu'une exception était raisonnable.
Les six principes ci-dessous existent pour rendre ces exceptions coûteuses à formuler.

---

## 1. On ne fork pas Arch, on s'y branche

Arch Colony n'est pas un embranchement d'Arch Linux. C'est Arch Linux, plus une couche.
`[core]`, `[extra]` et `[multilib]` continuent de pointer vers les miroirs d'Arch, sans
interposition de notre part. Un utilisateur d'Arch Colony qui fait `pacman -Syu` reçoit
les paquets d'Arch, signés par les clés d'Arch, à la vitesse d'Arch.

C'est exactement la relation que SphereCord entretient avec Equibop : on suit l'amont, on
ajoute par-dessus, on ne réécrit pas en dessous.

**Conséquence pratique.** Toute proposition qui commence par « il suffit de recompiler
`systemd` avec… » est rejetée par défaut. Pas parce qu'elle est fausse, mais parce qu'elle
transfère la maintenance de `systemd` sur nous, définitivement.

## 2. L'overlay ne recouvre jamais un paquet d'Arch

C'est la règle d'or, et c'est la seule qui n'a pas d'exception dans le dépôt principal.
`[colony]` ne contient que des paquets qui **n'existent pas** en amont. Aucun paquet de
`[colony]` ne porte le nom d'un paquet de `[core]` ou `[extra]`.

Le jour où l'overlay recouvre un paquet de base, trois choses arrivent en même temps : on
doit reconstruire à chaque mise à jour d'Arch, on introduit la classe de panne des mises à
jour partielles, et on devient responsable des failles de sécurité de ce paquet dans la
fenêtre entre le correctif d'Arch et notre reconstruction. Ces trois coûts sont permanents
et ne se remarquent qu'au bout de plusieurs mois.

**Conséquence pratique.** C'est ce principe, et non une préférence esthétique, qui rend
SELinux coûteux : SELinux *exige* de recouvrir la base. Voir
[ADR-0003](decisions/0003-lsm-par-etapes.md) — la décision d'y aller par étapes découle de
la règle d'or, elle n'en est pas indépendante.

## 3. Toute configuration est un paquet

Aucun `install.sh`. Aucun fichier déposé dans `/etc` par un script que `pacman` ne connaît
pas. Une configuration livrée par Arch Colony est un paquet, avec un `backup=`, une
désinstallation propre et un chemin de mise à jour.

Un script d'installation produit des fichiers orphelins : le gestionnaire de paquets ne
sait pas qu'ils existent, ne les met pas à jour, ne les retire pas, et les écrase en
silence. Sur une machine personnelle c'est un désagrément ; sur une distribution c'est un
défaut de conception qu'on ne peut plus corriger une fois les utilisateurs installés.

**Conséquence pratique.** `hyprland-colony` livre aujourd'hui un `install.sh`. Il devient
`colony-desktop-hyprland`, un paquet. Le dépôt d'origine reste utilisable tel quel hors
d'Arch Colony ; c'est notre empaquetage qui change, pas son code.

## 4. Une couleur ne s'écrit qu'une fois

`Project-Colony-Resources` a établi la règle pour les applications : la couleur vit dans
`tokens/`, et chaque programme lit un artefact **généré**. Arch Colony étend la règle au
système : Plymouth, le greeter, GTK, Qt, la palette de console et la configuration Hyprland
sont des cibles du générateur, pas des fichiers écrits à la main.

Écrire un hexadécimal en dur dans un thème Plymouth, c'est recréer exactement le problème
que `Project-Colony-Resources` a été créé pour résoudre — SphereCord qui téléchargeait le
`theme.rs` de Colony pour le parser à la regex.

**Conséquence pratique.** Ajouter une cible au générateur `colony-tokens` est du travail
en amont, dans `Project-Colony-Resources`. C'est voulu.

## 5. Un durcissement invisible est un durcissement qui sera désactivé

Toute protection livrée par défaut doit être observable et réversible : l'utilisateur doit
pouvoir savoir qu'elle est active, voir ce qu'elle a bloqué, et la lever sans réinstaller.
Une protection qui casse quelque chose en silence n'apprend rien à personne — elle apprend
seulement à désactiver la sécurité en bloc, ce qui est pire que de ne rien avoir livré.

C'est la même logique que la doc de durcissement de CFC, qui recommande de repasser en
`balanced` pour diagnostiquer plutôt que de deviner en `strict`.

**Conséquence pratique.** Pas de politique par défaut sans commande de diagnostic
correspondante, et pas de posture fail-closed sans garde-fou anti-verrouillage.

## 6. Chaque jalon boote

Un jalon d'Arch Colony est une chose qui démarre ou qui tourne. Pas un document, pas un
schéma, pas une politique écrite mais jamais chargée. La feuille de route ne contient que
des artefacts vérifiables sur une machine ou dans une VM.

**Conséquence pratique.** Le jalon 1 n'est pas « l'architecture du dépôt » — c'est le plus
petit ISO qui démarre et se reconnaît comme Arch Colony.

---

## Ce qu'Arch Colony n'est pas

- **Pas une distribution « sécurisée » au sens marketing.** On livre des mécanismes précis,
  documentés, et on dit ce qu'ils ne couvrent pas.
- **Pas un Arch préconfiguré avec un fond d'écran.** L'intérêt est dans la couche système :
  pare-feu applicatif bidirectionnel, politique LSM, chaîne de démarrage.
- **Pas un projet qui vise l'exhaustivité des bureaux.** Deux éditions, tenues correctement.
