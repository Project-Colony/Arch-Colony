#!/usr/bin/env bash
# End-to-end proof that the PUBLISHED [colony] repository works over HTTPS.
#
# tools/test-repo.sh proves the trust chain against a file:// repository built
# from repo/out. That is the right test for the signing chain and the wrong one
# for hosting: it never touches the network, so it passes just as happily when
# the release does not exist, when an asset failed to upload, or when GitHub
# serves a redirect pacman cannot follow.
#
# This one points at the real URL a user's machine will use. Everything happens
# in a temporary root with its own keyring; this machine is never modified.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
KEYRING="$ROOT/packages/colony-keyring"
SERVER="${COLONY_SERVER:-https://github.com/Project-Colony/Arch-Colony/releases/download/repo}"
# What to install as the proof. The eBPF object is the interesting one: it is
# the package whose whole reason for existing is that it reaches the machine.
WANT="${1:-colony-firewall-control-ebpf}"

: "${COLONY_SIGNING_KEY:?not set — see repo/genkey.sh}"

echo "==> server: $SERVER"

# Fail early and legibly rather than inside pacman's sync.
for asset in colony.db colony.db.sig; do
	code=$(curl -sL -o /dev/null -w '%{http_code}' "$SERVER/$asset")
	printf '    %-16s HTTP %s\n' "$asset" "$code"
	[[ $code == 200 ]] || { echo "FAIL: $asset is not being served" >&2; exit 1; }
done

TEST=$(mktemp -d /tmp/colony-published.XXXXXX)
trap 'sudo rm -rf "$TEST"' EXIT
mkdir -p "$TEST"/{root,db,cache,gnupg}

echo "==> isolated keyring, trusting nothing to start with"
sudo pacman-key --gpgdir "$TEST/gnupg" --init
sudo pacman-key --gpgdir "$TEST/gnupg" --add "$KEYRING/colony.gpg"
sudo pacman-key --gpgdir "$TEST/gnupg" --lsign-key "$COLONY_SIGNING_KEY"

cat > "$TEST/pacman.conf" <<EOF
[options]
Architecture = x86_64
SigLevel    = Required DatabaseRequired

[colony]
Server = $SERVER
EOF

pac() {
	sudo pacman --config "$TEST/pacman.conf" --root "$TEST/root" --dbpath "$TEST/db" \
		--cachedir "$TEST/cache" --gpgdir "$TEST/gnupg" --logfile "$TEST/pacman.log" "$@"
}

echo "==> syncing over the network"
pac -Sy --noconfirm

echo "==> what the published database offers"
pac -Sl colony | sed 's/^/    /'

echo "==> installing $WANT"
pac -S --noconfirm "$WANT"

# The point of the whole exercise: the object has to arrive intact, with the
# BTF a stripped or mis-linked one would be missing.
obj="$TEST/root/usr/lib/colony-firewall/cfc-ebpf.o"
if [[ $WANT == colony-firewall-control-ebpf ]]; then
	[[ -f $obj ]] || { echo "FAIL: $obj did not land" >&2; exit 1; }
	echo "==> the object as a user's machine receives it"
	file "$obj" | sed 's/^.*: /    /'
	readelf -S --wide "$obj" | grep -E '\.BTF' | sed 's/^/    /'
	readelf -S --wide "$obj" | grep -q '\.BTF' || {
		echo "FAIL: the delivered object has no .BTF — CO-RE would misresolve" >&2
		exit 1
	}
fi

echo
echo "PASS — published database verified over HTTPS, package signature verified,"
echo "       trust established from colony-keyring alone."
