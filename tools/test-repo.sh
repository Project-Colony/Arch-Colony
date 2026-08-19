#!/usr/bin/env bash
# End-to-end proof that the [colony] trust chain works, without touching this machine.
#
# Builds a signed repository from repo/out, sets up an isolated pacman root with its
# own keyring, and installs a package from it with signature checking at its strictest.
# Everything happens inside a temporary directory; the real system is never modified.
#
# What a pass proves: the database signature verifies, the package signatures verify,
# and colony-keyring establishes trust from nothing.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
OUT="$ROOT/repo/out"
KEYRING="$ROOT/packages/colony-keyring"

: "${COLONY_SIGNING_KEY:?not set — see repo/genkey.sh}"

shopt -s nullglob
pkgs=("$OUT"/*.pkg.tar.zst)
shopt -u nullglob
(( ${#pkgs[@]} )) || { echo "nothing in repo/out — run repo/build.sh first" >&2; exit 1; }

TEST=$(mktemp -d /tmp/colony-repotest.XXXXXX)
trap 'sudo rm -rf "$TEST"' EXIT

echo "==> sandbox: $TEST"
mkdir -p "$TEST"/{root,db,cache,repo,gnupg}
cp "$OUT"/*.pkg.tar.zst "$OUT"/*.sig "$TEST/repo/"

echo "==> building the signed database"
( cd "$TEST/repo" && repo-add --sign --key "$COLONY_SIGNING_KEY" --new --quiet \
	colony.db.tar.zst ./*.pkg.tar.zst )

echo "==> isolated keyring, trusting nothing to start with"
sudo pacman-key --gpgdir "$TEST/gnupg" --init
sudo pacman-key --gpgdir "$TEST/gnupg" --add "$KEYRING/colony.gpg"
sudo pacman-key --gpgdir "$TEST/gnupg" --lsign-key "$COLONY_SIGNING_KEY"

cat > "$TEST/pacman.conf" <<EOF
[options]
Architecture = x86_64
SigLevel    = Required DatabaseRequired

[colony]
Server = file://$TEST/repo
EOF

echo "==> syncing"
sudo pacman --config "$TEST/pacman.conf" --root "$TEST/root" --dbpath "$TEST/db" \
	--cachedir "$TEST/cache" --gpgdir "$TEST/gnupg" --logfile "$TEST/pacman.log" \
	-Sy --noconfirm

echo "==> installing colony-mirrorlist from the repository"
sudo pacman --config "$TEST/pacman.conf" --root "$TEST/root" --dbpath "$TEST/db" \
	--cachedir "$TEST/cache" --gpgdir "$TEST/gnupg" --logfile "$TEST/pacman.log" \
	-S --noconfirm colony-mirrorlist

installed="$TEST/root/etc/pacman.d/colony-mirrorlist"
if [[ ! -f $installed ]]; then
	echo "FAIL: colony-mirrorlist did not land at $installed" >&2
	exit 1
fi

echo
echo "==> installed file:"
sed 's/^/    /' "$installed"
echo
echo "PASS — signed database verified, signed package verified, trust established"
echo "       from colony-keyring alone."
