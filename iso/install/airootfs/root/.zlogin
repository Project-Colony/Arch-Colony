# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Arch Colony: ask before touching the network, then run the installer in a
# Wayland kiosk on the first virtual terminal.
#
# The live image boots with networking off — systemd-networkd, resolved, iwd and
# ModemManager are not enabled in the airootfs. That is deliberate and stronger
# than a checkbox inside the installer: someone who does not want this machine
# reaching the internet does not merely decline a download, the interfaces never
# come up at all. Everything except the optional package selection works offline.
#
# Not exec'd — if cage or calamares fails, the live session must fall back to a
# usable shell rather than to nothing.
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]]; then
    print
    print "Arch Colony — le réseau est désactivé."
    print "Il n'est nécessaire que pour installer des logiciels supplémentaires ;"
    print "l'installation elle-même fonctionne hors ligne."
    print
    print -n "Activer le réseau ? [o/N] "
    read -k 1 _colony_net
    print
    if [[ $_colony_net == [oOyY] ]]; then
        print "Activation du réseau..."
        systemctl start systemd-networkd systemd-resolved systemd-timesyncd 2>/dev/null
        systemctl start iwd ModemManager 2>/dev/null
        systemctl start systemd-networkd-wait-online 2>/dev/null
    else
        print "Réseau laissé désactivé."
    fi
    unset _colony_net
    print

    cage -- calamares
    print "installer exited ($?) — you are at a shell"
fi
