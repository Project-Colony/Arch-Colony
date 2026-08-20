#!/usr/bin/env bash
# Build an Arch Colony ISO from a profile under iso/.
#
#   ./iso/build.sh            build the "base" profile
#   ./iso/build.sh hyprland   build another profile
#
# Requires the packages in repo/out (run repo/build.sh first) and the Colony key
# in this machine's pacman keyring, since the profile verifies [colony] at its
# strictest.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PROFILE="${1:-base}"
SRC="$ROOT/iso/$PROFILE"
PKGS="$ROOT/repo/out"
WORK="$ROOT/iso/work"
DEST="$ROOT/iso/out"

: "${COLONY_SIGNING_KEY:?not set — see repo/genkey.sh}"
[[ -d $SRC ]] || { echo "no profile at $SRC" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "mkarchiso missing: pacman -S archiso" >&2; exit 1; }

shopt -s nullglob
built=("$PKGS"/*.pkg.tar.zst)
shopt -u nullglob
(( ${#built[@]} )) || { echo "nothing in repo/out — run repo/build.sh first" >&2; exit 1; }

echo "==> refreshing the local [colony] database"
( cd "$PKGS" && rm -f colony.db* colony.files* &&
  repo-add --sign --key "$COLONY_SIGNING_KEY" --new --quiet colony.db.tar.zst ./*.pkg.tar.zst )

if ! sudo pacman-key --list-keys "$COLONY_SIGNING_KEY" &>/dev/null; then
	cat >&2 <<EOF
The Colony signing key is not in this machine's pacman keyring, so the build
cannot verify [colony]. Add it once:

    sudo pacman-key --add packages/colony-keyring/colony.gpg
    sudo pacman-key --lsign-key $COLONY_SIGNING_KEY
EOF
	exit 1
fi

echo "==> staging the profile"
# mkarchiso runs as root and leaves a root-owned work tree, which a user-level
# rm cannot remove. Left in place, mkarchiso reuses it and silently reproduces
# the previous image — a rebuild that changes nothing while reporting success.
sudo rm -rf "$WORK"
[[ -e $WORK ]] && { echo "could not clear $WORK — refusing to build against a stale work tree" >&2; exit 1; }
mkdir -p "$WORK" "$DEST"
STAGE="$WORK/profile"
cp -r "$SRC" "$STAGE"

# A file:// URL cannot contain a raw space, and this repository lives under a
# path that has one.
REPO_URL=${PKGS// /%20}
sed -i "s|@COLONY_REPO@|$REPO_URL|g" "$STAGE/pacman.conf"

echo "==> mkarchiso ($PROFILE)"
sudo mkarchiso -v -w "$WORK/work" -o "$DEST" "$STAGE"

echo
echo "Built:"
for f in "$DEST"/*.iso; do
	[[ -e $f ]] && printf '    %s  (%s)\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done
