# ADR-0004 — Noyau : `linux-hardened` d'Arch, sans paquet maison

**Statut** : acceptée — 2026-08-19
**Point de vigilance** : dépendance eBPF de CFC, voir « À vérifier »

## Contexte

Le projet demande un noyau « super puissant », et surtout un noyau sur lequel Colony Firewall
Control fonctionne à 100 %. Ces deux exigences ne pointent pas dans la même direction : un
noyau orienté performance et un noyau durci font des arbitrages opposés.

CFC impose des contraintes concrètes : NFQUEUE et nftables pour l'interception, la lecture de
`/proc/net/*` et `/proc/*/fd` pour l'attribution des processus, et — c'est le point qui a
changé — un sous-système eBPF désormais en cours d'intégration en amont, ce qui déplace des
exigences comme BTF/CO-RE du statut « plus tard » au statut « maintenant ».

## Décision

Arch Colony livre le paquet **`linux-hardened`** officiel d'Arch, accompagné de nos propres
`sysctl` et paramètres d'amorçage empaquetés séparément (`colony-hardening-sysctl`). Aucun
paquet noyau maison.

## Conséquences

**Positives.** Aucun coût de rebase : le noyau suit Arch. Aucune casse DKMS spécifique à
nous. Et une synergie directe avec CFC : `linux-hardened` restreint les *user namespaces* non
privilégiés, ce qui ferme le contournement `unshare -rn` que la documentation de durcissement
de CFC reconnaît explicitement comme une limite de son modèle NFQUEUE.

**Négatives.** On ne contrôle pas la configuration du noyau. Si `linux-hardened` désactive une
option dont CFC a besoin, on n'a aucun recours en dehors de rouvrir cette ADR.

**Sur la « puissance ».** Le mot est ambigu et la décision le tranche dans le sens de la
robustesse, pas du débit. Un noyau de la famille performance reste installable par
l'utilisateur depuis les dépôts d'Arch ; simplement, ce n'est pas ce qui est livré ni testé
par défaut.

## À vérifier — bloquant pour la validation de cette ADR

Ces points décident si la décision tient. Ils demandent une vérification sur machine et sur
les sources de configuration d'Arch, pas un raisonnement :

1. `CONFIG_DEBUG_INFO_BTF` est-il activé dans `linux-hardened` ? Si le chargeur eBPF de CFC
   fait du CO-RE et que BTF est absent, le chargement échoue et cette ADR tombe.
2. `CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF`, `CONFIG_BPF_JIT`,
   `CONFIG_NETFILTER_NETLINK_QUEUE`, `CONFIG_NF_TABLES` — présents ?

   **Mesure partielle du 2026-08-19**, relevée dans `/proc/config.gz` sur une machine Arch
   à jour, noyau `linux` **7.1.8-arch1-3** :

   ```
   CONFIG_DEBUG_INFO_BTF=y          CONFIG_BPF_SYSCALL=y
   CONFIG_BPF_JIT=y                 CONFIG_CGROUP_BPF=y
   CONFIG_NETFILTER_NETLINK_QUEUE=m CONFIG_NF_TABLES=m
   ```

   Les six options sont présentes, BTF compris. **Cela ne valide pas l'ADR** : la mesure
   porte sur le paquet `linux`, pas sur `linux-hardened`, qui a sa propre configuration. Le
   résultat rend l'hypothèse vraisemblable, il ne la démontre pas. La vérification doit être
   refaite sur un système démarré sous `linux-hardened`.

   **Première divergence observée, 2026-08-20.** `linux-hardened` ne lit pas la même chose
   que `linux`. Le profil `baseline` d'archiso compresse son `airootfs` en erofs+LZMA avec
   *tail-packing* ; l'image démarre sous `linux-hardened` mais échoue ensuite à lire ses
   métadonnées :

   ```
   erofs (device loop0): failed to read inode meta block (nid: 9275766): -4
   ```

   L'image n'est pas en cause : le noyau `linux` de la machine hôte la monte et en lit les
   fichiers sans erreur. C'est bien une différence de configuration côté noyau. Le profil
   d'Arch Colony utilise donc squashfs+xz, comme le profil `releng` d'Arch. Cette
   observation ne dit rien de BTF, mais elle confirme que l'hypothèse du point 1 doit être
   vérifiée et non supposée.

3. Distinguer trois choses souvent confondues : la restriction eBPF *non privilégié*
   (sans effet sur un démon root doté de `CAP_BPF`), la configuration de compilation, et le
   *lockdown* à l'exécution. Sous Secure Boot, le lockdown s'active automatiquement et peut
   bloquer des opérations BPF pour root lui-même. C'est le scénario qui passe sur la machine
   de développement et casse chez l'utilisateur.

Tant que le point 1 n'est pas vérifié, cette ADR est acceptée mais non validée.

## Alternatives écartées

- **`linux-colony` maison** — contrôle total, mais rebase à chaque version et responsabilité
  de la signature Secure Boot. À reprendre uniquement si le point 1 échoue.
- **Base performance durcie** — les deux objectifs tirent en sens inverse.
- **Deux noyaux au choix** — double la surface de test pour un bénéfice qui n'existe pas
  tant qu'on n'a pas un seul noyau qui marche.
