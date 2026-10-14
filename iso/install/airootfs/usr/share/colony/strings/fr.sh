# shellcheck shell=bash disable=SC2034
# The live session's text, in French: the same keys as en.sh, which is
# canonical. tools/check-i18n.py fails CI when the two differ.

# /root/.zlogin, before the installer starts.
net_intro="Arch Colony - le réseau est désactivé.
Il n'est nécessaire que pour installer des logiciels supplémentaires ;
l'installation elle-même fonctionne hors ligne."
net_prompt="Activer le réseau ? [o/N] "
net_enabling="Activation du réseau..."
net_left_off="Réseau laissé désactivé."
installer_failed="L'installateur graphique n'a pas démarré (code %s)."
installer_retry="Nouvelle tentative en rendu logiciel - c'est plus lent, pas moins fiable."
installer_exited="L'installateur s'est arrêté (%s) - vous êtes dans un shell."

# /etc/motd, written at boot by colony-live-setup.
motd="Arch Colony - support d'installation

L'installateur graphique démarre automatiquement. Si vous lisez ceci, c'est
qu'il s'est arrêté ou que vous avez ouvert une autre console.

  Relancer l'installateur      cage -- calamares
  Si le rendu échoue           WLR_RENDERER=pixman cage -- calamares
  Voir pourquoi il a échoué    grep -iE 'error|warning' ~/.cache/calamares/session.log | tail -30

Réseau : il reste DÉSACTIVÉ tant que vous ne l'avez pas autorisé au démarrage.
Aucune interface n'est montée, ni filaire ni sans fil. C'est voulu : refuser
signifie que cette machine ne joint rien, pas seulement qu'elle ne télécharge
rien. L'installation fonctionne entièrement hors ligne ; le réseau ne sert qu'à
installer des logiciels supplémentaires.

  L'activer maintenant         systemctl start systemd-networkd systemd-resolved
  Sans fil, ensuite            systemctl start iwd && iwctl
  Modem mobile, ensuite        systemctl start ModemManager && mmcli

Signaler un problème : https://github.com/Project-Colony/Arch-Colony/issues"

# colony-preflight.
preflight_unusable="Ce support d'installation est inutilisable : airootfs.sfs n'y figure pas.
Le disque n'a PAS été touché.

C'est ce que donne une clé USB écrite en mode ISO ou par extraction - Rufus en
mode ISO, Ventoy, ou l'image décompressée sur une clé formatée. Une image Arch
doit être copiée octet par octet :
    dd if=archcolony-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
ou Rufus en mode DD."

# colony-verify-session. "Écran de connexion" is the name of the group in
# config/netinstall.yaml.
verify_no_greeter="Cette installation démarrerait sur une console texte.

%d session(s) graphique(s) installée(s), et aucun écran de connexion. Cela
arrive quand le groupe « Écran de connexion » a été décoché sur la page des
logiciels : un bureau sans écran de connexion laisse devant une invite login:
qui ressemble à une panne.

Rien ne peut être réparé ici sans écran de connexion sur le disque, donc
l'installation s'arrête plutôt que de se terminer sur un système inutilisable.

Relancez l'installateur et cochez-en un sous « Écran de connexion » - SDDM
convient à tous les bureaux proposés."
