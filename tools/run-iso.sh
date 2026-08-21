#!/usr/bin/env bash
# Boot an Arch Colony ISO in QEMU, in a window, with a fresh target disk.
#
#   ./tools/run-iso.sh              the installer ISO (archcolony-*)
#   ./tools/run-iso.sh base         the minimal ISO
#   ./tools/run-iso.sh install bios boot in BIOS mode instead of UEFI
#
# UEFI is the default and it matters: under BIOS, Calamares installs GRUB, which
# is not what we ship — modules/bootloader.conf specifies systemd-boot, and that
# is UEFI-only. Testing under BIOS validates a path no user will take.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PROFILE="${1:-install}"
FIRMWARE="${2:-uefi}"
# Not /tmp. On Arch /tmp is tmpfs, so a completed installation — the artefact
# that took an hour of clicking through Calamares and answering firewall prompts
# — is gone the next time the host reboots. That is exactly what happened on
# 2026-08-21, and the disk was already an hour old.
#
# ~/.cache is the right shelf for it: persistent, per-user, outside the
# repository, and something a person can delete on purpose without being told to.
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-colony"
mkdir -p "$STATE"
DISK="${COLONY_TEST_DISK:-$STATE/colony-target.qcow2}"
DISK_SIZE="${COLONY_TEST_DISK_SIZE:-20G}"

case "$PROFILE" in
	base)    pattern="archcolony-base-*.iso" ;;
	install) pattern="archcolony-2*.iso" ;;
	*)       pattern="archcolony-$PROFILE-*.iso" ;;
esac

shopt -s nullglob
isos=("$ROOT/iso/out/"$pattern)
shopt -u nullglob
(( ${#isos[@]} )) || { echo "no ISO matching $pattern in iso/out — run iso/build.sh first" >&2; exit 1; }
ISO="${isos[-1]}"

command -v qemu-system-x86_64 >/dev/null || { echo "qemu missing: pacman -S qemu-desktop" >&2; exit 1; }
[[ -r /dev/kvm ]] || echo "WARNING: /dev/kvm unavailable — this will be extremely slow. Enable SVM/VT-x in firmware." >&2

echo "==> fresh target disk: $DISK ($DISK_SIZE)"
rm -f "$DISK"
qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null

args=(
	-enable-kvm -cpu host -m 4G -smp 4
	-cdrom "$ISO"
	-drive "file=$DISK,format=qcow2,if=virtio"
	-nic user,model=virtio-net-pci
	-device usb-ehci -device usb-tablet
	-vga virtio -display gtk
	-boot d
)

if [[ $FIRMWARE == uefi ]]; then
	CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
	VARS="$STATE/colony-OVMF_VARS.fd"
	[[ -f $CODE ]] || { echo "OVMF missing: pacman -S edk2-ovmf" >&2; exit 1; }
	cp -f /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
	args+=(-drive "if=pflash,format=raw,readonly=on,file=$CODE"
	       -drive "if=pflash,format=raw,file=$VARS")
	echo "==> firmware: UEFI"
else
	echo "==> firmware: BIOS — note that this installs GRUB, not systemd-boot"
fi

echo "==> $(basename "$ISO")"
exec qemu-system-x86_64 "${args[@]}"
