#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archcolony"
iso_label="COLONY_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Project Colony <https://github.com/Project-Colony>"
iso_application="Arch Colony Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="colony"
buildmodes=('iso')
# UEFI only, deliberately. bootloader.conf asks for systemd-boot, which is
# UEFI-only — but Calamares routes every non-EFI install to GRUB regardless
# (bootloader/main.py: `elif efi_boot_loader == "grub" or fw_type != "efi"`), and
# then reads configuration["grubInstall"] with a bare subscript. That key is not
# in our override, so a BIOS install dies on an unhandled KeyError *after*
# partitioning, formatting and unpacking have already run: a wiped disk with no
# bootloader. Refusing to boot on BIOS is far better than installing onto it and
# failing at the last step.
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
)
