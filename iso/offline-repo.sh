#!/usr/bin/env bash
# Assemble the signed repository the installer installs the firewall from.
#
#   iso/offline-repo.sh DEST [PKGNAME ...]
#
# Copies the build of each package in repo/out, with its signature, into DEST
# and signs a colony-offline database over them with COLONY_SIGNING_KEY. With no
# PKGNAME it takes what colony-firewall-defaults needs: that package, and the
# two colony-firewall-control builds it depends on. iso/build.sh runs it on the
# staged install profile; tools/test-repo.sh runs it on a stand-in package.
#
# Signed here: colony-offline.db.tar.zst.sig (and the colony-offline.db.sig link
# repo-add makes to it). Not signed here: the packages. Their .sig files are the
# ones repo/build.sh made, checked before they are copied.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PKGS="$ROOT/repo/out"

: "${COLONY_SIGNING_KEY:?not set - see repo/genkey.sh}"
DEST=${1:?usage: iso/offline-repo.sh DEST [PKGNAME ...]}
shift
(( $# )) || set -- colony-firewall-defaults colony-firewall-control colony-firewall-control-ebpf

# gpg --verify accepts a signature from any key in this keyring. The installer
# accepts only the Colony key, so check the signer against the one named here.
fpr=$(gpg --batch --with-colons --fingerprint "$COLONY_SIGNING_KEY" 2>/dev/null |
	awk -F: '/^fpr:/ {print $10; exit}')
[[ -n $fpr ]] || { echo "COLONY_SIGNING_KEY $COLONY_SIGNING_KEY is not in this keyring" >&2; exit 1; }

mkdir -p "$DEST"
for name in "$@"; do
	# name-pkgver-pkgrel-arch: a pkgver starts with a digit and holds no dash,
	# so colony-firewall-control cannot match colony-firewall-control-ebpf.
	shopt -s nullglob
	found=("$PKGS/$name"-[0-9]*-*-*.pkg.tar.zst)
	shopt -u nullglob
	(( ${#found[@]} == 1 )) ||
		{ echo "expected one build of $name in $PKGS, found ${#found[@]} - run repo/build.sh" >&2; exit 1; }
	pkg=${found[0]}
	# The installer would refuse it anyway, but only on someone's machine, after
	# partitioning. Here it stops the build.
	# VALIDSIG ends with the primary key's fingerprint, also for a subkey signature.
	gpg --batch --status-fd 1 --verify "$pkg.sig" "$pkg" 2>/dev/null |
		awk -v fpr="$fpr" '$2 == "VALIDSIG" && $NF == fpr {ok = 1} END {exit !ok}' ||
		{ echo "${pkg##*/}: signature missing, bad or not made by $COLONY_SIGNING_KEY - run repo/build.sh" >&2; exit 1; }
	cp "$pkg" "$pkg.sig" "$DEST/"
done

( cd "$DEST" && repo-add --sign --key "$COLONY_SIGNING_KEY" --new --quiet \
	colony-offline.db.tar.zst ./*.pkg.tar.zst )
