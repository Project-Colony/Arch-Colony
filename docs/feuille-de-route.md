# Feuille de route

Chaque jalon est une chose qui démarre ou qui tourne, conformément au
[principe 6](principes.md#6-chaque-jalon-boote). Aucun jalon n'est un document.

Les fourchettes d'effort supposent une personne travaillant par intermittence, avec
l'assistance d'un agent. Elles sont indicatives et seront révisées après J1, qui est le seul
jalon dont on connaîtra vraiment le coût une fois fait.

---

## J0 — Le dépôt existe

**Artefact vérifiable** : depuis une VM Arch vierge, ajouter `[colony]` à `pacman.conf`,
importer la clé, et installer `colony-mirrorlist` avec `pacman -S`.

- `colony-keyring` : la clé de signature du projet et sa chaîne de confiance
- `colony-mirrorlist` : la liste des miroirs, paquet minimal servant de test de bout en bout
- `repo/` : construction en chroot propre, signature, publication
- Un hébergement qui sert le dépôt

**Pourquoi en premier.** Tout le reste en dépend, et c'est le seul jalon qui valide la chaîne
de confiance — la partie où une erreur se paie par une réinstallation chez tous les
utilisateurs.

**Effort** : quelques jours. **Risque** : faible, mécanique bien documentée.

---

## J1 — Le plus petit ISO qui démarre

**Artefact vérifiable** : un ISO qui démarre en VM jusqu'à un shell root, où
`cat /etc/os-release` affiche Arch Colony.

- Un profil `archiso` minimal dans `iso/base/`
- `colony-base` réduit à son strict minimum
- `colony-release` : `/etc/os-release`, `/etc/issue`, le nom du système
- Pas de bureau, pas d'installateur, pas de durcissement

**Pourquoi.** C'est le jalon qui transforme le projet d'idée en système. Il révèle le coût
réel de la construction d'image, qui conditionne toutes les estimations suivantes.

**Effort** : quelques jours à une semaine. **Risque** : faible.

---

## J2 — Installable sur disque

**Artefact vérifiable** : depuis l'ISO, installer sur un disque virtuel, redémarrer, et
ouvrir une session sur le système installé.

- Calamares avec configuration et branding Colony
- Chaîne d'amorçage : `systemd-boot`, LUKS2 optionnel
- `linux-hardened` installé et démarré ([ADR-0004](decisions/0004-noyau-linux-hardened.md))
- Test automatisé en QEMU : installation sans interaction, redémarrage, assertion sur l'état

**Effort** : deux à quatre semaines. **Risque** : moyen — Calamares est éprouvé, sa
configuration l'est moins.

**Bloquant à lever avant J2** : la vérification `CONFIG_DEBUG_INFO_BTF` de
[ADR-0004](decisions/0004-noyau-linux-hardened.md). Si elle échoue, le choix du noyau change
et J2 est retardé.

---

## J3 — Le bureau et l'identité

**Artefact vérifiable** : le système installé démarre sur une session Hyprland thémée
Colony, avec le hub `colony` lancé.

- `colony-desktop-hyprland`, issu de `hyprland-colony` empaqueté
  ([ADR-0007](decisions/0007-configuration-en-paquets.md))
- Nouvelles cibles du générateur `colony-tokens`, en amont dans `Project-Colony-Resources` :
  Plymouth, greeter, palette de console, fragments Hyprland, GTK, Qt
- Les programmes Colony empaquetés dans `[colony]`

**Effort** : trois à six semaines, dont une part significative en amont dans
`Project-Colony-Resources`. **Risque** : moyen.

---

## J4 — Le durcissement

**Artefact vérifiable** : après installation, `aa-status` montre les profils chargés, CFC
tourne et filtre dans les deux sens, et la machine a toujours du réseau.

- AppArmor comme LSM majeur, profils pour les programmes Colony
- `colony-hardening-sysctl` : `sysctl` et paramètres d'amorçage
- `colony-hardened` : `auditd`, USBGuard, AIDE, `fapolicyd`, durcissement PAM
- CFC intégré au système : activé au démarrage, jeu de règles initial semé à l'installation,
  **garde-fou anti-verrouillage** pour la politique entrante

**Le point délicat.** Une politique entrante fail-closed activée au démarrage est le moyen le
plus sûr de livrer un ISO qui ressemble à une panne réseau — et, sur une machine distante,
d'enfermer l'utilisateur dehors. Le garde-fou n'est pas une finition, c'est une condition de
livraison. Voir le [principe 5](principes.md#5-un-durcissement-invisible-est-un-durcissement-qui-sera-désactivé).

**Effort** : quatre à huit semaines. **Risque** : élevé — c'est le jalon où l'on casse des
choses en silence.

---

## J5 — L'édition Plasma

**Artefact vérifiable** : un second ISO, même base, session Plasma thémée Colony.

**Effort** : deux à trois semaines si J3 a correctement séparé ce qui est générique de ce qui
est propre à Hyprland. Beaucoup plus sinon — c'est le test de la qualité de J3.

---

## J6 — SELinux en opt-in

**Artefact vérifiable** : après activation de `[colony-selinux]` et un réétiquetage, `sestatus`
indique le mode *enforcing* et la machine démarre encore.

- Dépôt séparé, désactivé par défaut
  ([ADR-0003](decisions/0003-lsm-par-etapes.md), [ADR-0002](decisions/0002-regle-de-non-recouvrement.md))
- Reconstruction de la base, CI de reconstruction automatique sur bump amont
- Politique de référence, et son portage si l'existant Arch est abandonné

**Effort** : inconnu, et c'est le point. Ne pas estimer avant d'avoir vérifié l'état réel du
support SELinux sur Arch en 2026. Fourchette basse : deux mois. Fourchette haute : le projet
change de nature.

---

## Ce qui n'est pas planifié

Le paquet noyau maison, l'installateur Rust/iced, les architectures autres que x86_64, et
toute édition de bureau supplémentaire. Chacun est une ADR à rouvrir, pas une tâche à
ajouter.
