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
    # Hardware acceleration first, software rendering if the GPU cannot provide
    # it. Reported from real hardware on 2026-08-22, an NVIDIA card on nouveau:
    #
    #   MESA: error: ZINK: vkCreateInstance failed (VK_ERROR_INCOMPATIBLE_DRIVER)
    #   libEGL warning: egl: failed to create dri2 screen
    #   failed to create the wlroots renderer
    #   installer exited (1)
    #
    # Mesa routes nouveau's OpenGL through zink — OpenGL on top of Vulkan — since
    # the classic driver was dropped, so a card whose Vulkan support is missing or
    # too old takes EGL, wlroots and the whole installer down with it. Nothing was
    # wrong with the machine; it simply could not be installed on.
    #
    # pixman is wlroots' CPU renderer. Calamares is a Qt form: it does not need a
    # GPU, and an installer that starts slowly beats one that does not start.
    # Trying acceleration first costs one failed launch on the machines that need
    # the fallback, and nothing at all on the ones that do not.
    # Calamares is the only window and cage keeps it full-screen, so the
    # client-side title bar Qt draws under Wayland (a grey "Arch Colony
    # Installer" strip with dead minimise/maximise/close buttons) is the one
    # part of the screen the stylesheet cannot reach. Qt drops it on request.
    LIBSEAT_BACKEND=logind QT_WAYLAND_DISABLE_WINDOWDECORATION=1 cage -- calamares
    _colony_rc=$?

    if (( _colony_rc != 0 )); then
        print
        print "L'installateur graphique n'a pas démarré (code $_colony_rc)."
        print "Nouvelle tentative en rendu logiciel — c'est plus lent, pas moins fiable."
        print
        LIBSEAT_BACKEND=logind WLR_RENDERER=pixman LIBGL_ALWAYS_SOFTWARE=1 \
            QT_WAYLAND_DISABLE_WINDOWDECORATION=1 cage -- calamares
        _colony_rc=$?
    fi

    print "installer exited ($_colony_rc) — you are at a shell"
    unset _colony_rc
fi
