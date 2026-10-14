# shellcheck shell=bash disable=SC2034
# The live session's text, in English: the boot prompt in /root/.zlogin, the
# message of the day and the installer's own checks. English is canonical; fr.sh
# holds the same keys, and tools/check-i18n.py fails CI when they differ.
#
# Sourced by bash and by zsh, so plain double-quoted assignments only: no $,
# no backquotes. A value used as a printf format says so in its comment.

# /root/.zlogin, before the installer starts.
net_intro="Arch Colony - the network is disabled.
It is only needed to install additional software;
the installation itself works offline."
net_prompt="Enable the network? [y/N] "
net_enabling="Enabling the network..."
net_left_off="Network left disabled."
# printf format: the installer's exit code.
installer_failed="The graphical installer did not start (code %s)."
installer_retry="Trying again with software rendering - slower, not less reliable."
# printf format: the installer's exit code.
installer_exited="The installer exited (%s) - you are at a shell."

# /etc/motd, written at boot by colony-live-setup.
motd="Arch Colony - installation medium

The graphical installer starts on its own. If you are reading this, it has
stopped or you have opened another console.

  Start the installer again    cage -- calamares
  If rendering fails           WLR_RENDERER=pixman cage -- calamares
  See why it failed            grep -iE 'error|warning' ~/.cache/calamares/session.log | tail -30

Network: it stays DISABLED unless you allowed it at boot. No interface is up,
wired or wireless. That is deliberate: declining means this machine reaches
nothing, not merely that it downloads nothing. The installation works entirely
offline; the network is only needed for additional software.

  Enable it now                systemctl start systemd-networkd systemd-resolved
  Wireless, then               systemctl start iwd && iwctl
  Mobile modem, then           systemctl start ModemManager && mmcli

Report a problem: https://github.com/Project-Colony/Arch-Colony/issues"

# colony-preflight, shown by the installer when it refuses to start.
preflight_unusable="This installation medium is unusable: airootfs.sfs is missing from it.
The disk has NOT been touched.

This is what a USB stick written in ISO or extraction mode looks like - Rufus in
ISO mode, Ventoy, or the image unpacked onto a formatted stick. An Arch image has
to be copied byte for byte:
    dd if=archcolony-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
or Rufus in DD mode."

# colony-verify-session, shown by the installer when it stops. printf format:
# the number of graphical sessions installed. "Login screen" is the name of the
# group in config/netinstall.yaml.
verify_no_greeter="This installation would boot to a text console.

%d graphical session(s) are installed and no login screen is. That happens
when the \"Login screen\" group was unticked on the software page: a desktop
without one leaves you at a login: prompt that looks like a failure.

Nothing here can be repaired without a login screen on the disk, so the
installation is stopped rather than finished into something unusable.

Start the installer again and tick one under \"Login screen\" - SDDM suits
every desktop offered."
