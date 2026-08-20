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
        cp /usr/share/colony/netinstall.yaml /etc/calamares/modules/netinstall.yaml
    else
        print "Réseau laissé désactivé."
        # The package page only offers downloads. Replacing the tree with a
        # placeholder is what makes the refusal mean something: without it the
        # page still renders in full, since a file:// groups list loads happily
        # with no interface up, and a selection would be silently discarded.
        cp /usr/share/colony/netinstall-offline.yaml /etc/calamares/modules/netinstall.yaml
    fi
    unset _colony_net
    print

    # libseat tries seatd before logind and prints two red lines when it does not
    # find it. There is no seatd in this image and there is no reason for one —
    # logind provides the seat. Naming the backend skips the failed attempt
    # instead of hiding its message, which is the difference between silencing a
    # warning and not producing it.
    LIBSEAT_BACKEND=logind cage -- calamares
    print "installer exited ($?) — you are at a shell"
fi
