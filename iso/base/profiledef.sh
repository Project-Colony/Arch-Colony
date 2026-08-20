#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archcolony-base"
iso_label="COLONY_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Project Colony <https://github.com/Project-Colony>"
iso_application="Arch Colony base"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="colony"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
# squashfs+xz, the settings of Arch's own releng profile. The baseline profile we
# started from uses erofs with LZMA and tail-packing; linux-hardened boots from it
# but then fails to read compressed inode metadata:
#
#   erofs (device loop0): failed to read inode meta block (nid: 9275766): -4
#
# The image itself is sound — the host kernel mounts it and reads files from it
# without complaint. The difference is on the kernel side, and since we do not
# control linux-hardened's configuration (ADR-0004), the answer is to use the
# format Arch's own installer ISO uses and that every Arch kernel is tested with.
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=(xz -9e)
file_permissions=(
  ["/etc/shadow"]="0:0:400"
)
