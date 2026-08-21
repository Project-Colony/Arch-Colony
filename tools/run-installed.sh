#!/usr/bin/env bash
# Boot the disk that tools/run-iso.sh installed onto, with no ISO attached.
#
#   ./tools/run-installed.sh
#
# This is the half of the test that matters: an installation that completes proves
# nothing until the machine boots from its own disk without the installer medium.

set -euo pipefail

# Matches tools/run-iso.sh: not /tmp, which is tmpfs here and takes a completed
# installation with it at the next reboot of the host.
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-colony"
DISK="${COLONY_TEST_DISK:-$STATE/colony-target.qcow2}"
VARS="$STATE/colony-OVMF_VARS.fd"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd

[[ -f $DISK ]] || { echo "no target disk at $DISK — run tools/run-iso.sh and install first" >&2; exit 1; }
[[ -f $CODE ]] || { echo "OVMF missing: pacman -S edk2-ovmf" >&2; exit 1; }

# Reuse the firmware variables the installation wrote: they hold the systemd-boot
# entry. Starting from a pristine VARS would fall back to \EFI\BOOT\BOOTX64.EFI,
# which works but would not tell us whether the boot entry was registered properly.
if [[ ! -f $VARS ]]; then
	echo "note: no firmware variables from the install run; starting from a fresh copy" >&2
	cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
fi

echo "==> booting $DISK from disk only, no installer medium"
exec qemu-system-x86_64 \
	-enable-kvm -cpu host -m 4G -smp 4 \
	-drive "if=pflash,format=raw,readonly=on,file=$CODE" \
	-drive "if=pflash,format=raw,file=$VARS" \
	-drive "file=$DISK,format=qcow2,if=virtio" \
	-nic user,model=virtio-net-pci \
	-device usb-ehci -device usb-tablet \
	-vga virtio -display gtk
