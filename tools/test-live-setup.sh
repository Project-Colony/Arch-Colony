#!/usr/bin/env bash
# What colony-live-setup writes into the live session for each boot entry's
# kernel parameters, checked against a scratch root instead of a booted image.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
AIROOTFS="$ROOT/iso/install/airootfs"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
failed=0

# boot CMDLINE: run the script as that boot would, into a fresh root.
boot() {
	local root="$SCRATCH/$((++n))"
	mkdir -p "$root/etc" "$root/usr/share/colony"
	cp -r "$AIROOTFS/usr/share/colony/strings" "$root/usr/share/colony/"
	: > "$root/etc/environment"
	printf '%s\n' "$1" > "$root/cmdline"
	COLONY_ROOT=$root COLONY_CMDLINE=$root/cmdline "$AIROOTFS/usr/local/bin/colony-live-setup"
	R=$root
}

# expect FILE LINE: FILE under the last root holds LINE.
expect() {
	if ! grep -qxF -- "$2" "$R/$1" 2>/dev/null; then
		echo "FAIL [$cmdline] $1 lacks: $2" >&2
		failed=1
	fi
}

# refuse FILE PATTERN: FILE under the last root has no line matching PATTERN.
refuse() {
	if grep -qE -- "$2" "$R/$1" 2>/dev/null; then
		echo "FAIL [$cmdline] $1 has: $(grep -E -- "$2" "$R/$1")" >&2
		failed=1
	fi
}

n=0
archiso='archisobasedir=colony archisosearchuuid=2026-10-14-00-00-00-00'

cmdline=$archiso
boot "$cmdline"
expect etc/locale.conf 'LANG=en_US.UTF-8'
expect etc/motd 'Arch Colony - installation medium'
refuse etc/environment 'XKB_DEFAULT_LAYOUT'
[[ ! -e $R/run/colony/espeakup.env ]] || { echo "FAIL [$cmdline] an English boot sets a voice" >&2; failed=1; }

cmdline="$archiso colony.lang=fr vconsole.keymap=fr accessibility=on"
boot "$cmdline"
expect etc/locale.conf 'LANG=fr_FR.UTF-8'
expect etc/motd "Arch Colony - support d'installation"
expect etc/environment 'XKB_DEFAULT_LAYOUT=fr'
expect run/colony/espeakup.env 'default_voice=fr'

cmdline="$archiso colony.lang=de"
boot "$cmdline"
expect etc/locale.conf 'LANG=en_US.UTF-8'

(( ! failed )) && echo "colony-live-setup: $n boots checked"
exit "$failed"
