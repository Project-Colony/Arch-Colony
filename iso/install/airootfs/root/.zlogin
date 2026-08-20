# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Arch Colony: run the installer in a Wayland kiosk on the first virtual terminal.
# Deliberately not exec'd — if cage or calamares fails, the live session must fall
# back to a usable shell rather than to nothing.
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]]; then
    cage -- calamares
    print "installer exited ($?) — you are at a shell"
fi
