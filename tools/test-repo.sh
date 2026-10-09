#!/usr/bin/env bash
# End-to-end proof that the [colony] trust chain works, without touching this machine.
#
# Builds a signed repository from repo/out, sets up an isolated pacman root with its
# own keyring, and installs a package from it through the [colony] stanza that
# colony-mirrorlist ships. Everything happens inside a temporary directory; the real
# system is never modified.
#
# What a pass proves: the database signature verifies, the package signatures verify,
# and colony-keyring establishes trust from nothing. Then, through the same stanza, a
# database served without its signature and a database signed by a key nobody
# trusts are both refused.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
OUT="$ROOT/repo/out"
KEYRING="$ROOT/packages/colony-keyring"
STANZA="$ROOT/packages/colony-mirrorlist/colony-repo.conf"

: "${COLONY_SIGNING_KEY:?not set - see repo/genkey.sh}"

# Already root, as in a container: no sudo needed, and none may be installed.
SUDO=sudo
(( EUID == 0 )) && SUDO=

shopt -s nullglob
pkgs=("$OUT"/*.pkg.tar.zst)
shopt -u nullglob
(( ${#pkgs[@]} )) || { echo "nothing in repo/out - run repo/build.sh first" >&2; exit 1; }

TEST=$(mktemp -d /tmp/colony-repotest.XXXXXX)
trap 'gpgconf --homedir "$TEST/foreign" --kill gpg-agent 2>/dev/null; $SUDO rm -rf "$TEST"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> sandbox: $TEST"
mkdir -p "$TEST"/{root,cache,repo,gnupg}
cp "$OUT"/*.pkg.tar.zst "$OUT"/*.sig "$TEST/repo/"

echo "==> building the signed database"
( cd "$TEST/repo" && repo-add --sign --key "$COLONY_SIGNING_KEY" --new --quiet \
	colony.db.tar.zst ./*.pkg.tar.zst )

echo "==> isolated keyring, trusting nothing to start with"
$SUDO pacman-key --gpgdir "$TEST/gnupg" --init
$SUDO pacman-key --gpgdir "$TEST/gnupg" --add "$KEYRING/colony.gpg"
$SUDO pacman-key --gpgdir "$TEST/gnupg" --lsign-key "$COLONY_SIGNING_KEY"

# pacman.conf as an installed machine has it: the [options] that `pacman` ships,
# then the stanza colony-mirrorlist ships, verbatim except for where its Include
# points. [options] says DatabaseOptional on purpose, so that whatever refuses an
# unsigned database below can only be the stanza's own SigLevel.
include="Include = $TEST/colony-mirrorlist"
stanza=$(sed "s|^Include = /etc/pacman.d/colony-mirrorlist$|$include|" "$STANZA")
grep -qxF "$include" <<<"$stanza" \
	|| fail "colony-repo.conf no longer includes /etc/pacman.d/colony-mirrorlist"
options='[options]
Architecture = x86_64
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional'
printf '%s\n%s\n' "$options" "$stanza" > "$TEST/pacman.conf"
# The control: what installed machines held before the stanza carried a SigLevel.
printf '%s\n%s\n' "$options" "$(grep -v '^SigLevel' <<<"$stanza")" > "$TEST/pacman-nosiglevel.conf"
printf 'Server = file://%s\n' "$TEST/served" > "$TEST/colony-mirrorlist"

# Each case gets its own database directory, so none can sync from what an
# earlier one left behind.
pac() {
	local conf=$1 db=$2; shift 2
	mkdir -p "$TEST/$db"
	$SUDO pacman --config "$TEST/$conf" --root "$TEST/root" --dbpath "$TEST/$db" \
		--cachedir "$TEST/cache" --gpgdir "$TEST/gnupg" --logfile "$TEST/pacman.log" "$@"
}

# What the server hands out: the repository as built, then whatever a case does to it.
serve() {
	rm -rf "$TEST/served"
	cp -a "$TEST/repo" "$TEST/served"
}

refused() {
	local what=$1; shift
	if pac "$@" -Sy --noconfirm 2>&1 | sed 's/^/    /'; then
		fail "$what was accepted"
	fi
	echo "    -> refused, as it must be"
}

serve

echo "==> syncing"
pac pacman.conf db -Sy --noconfirm

echo "==> installing colony-mirrorlist from the repository"
pac pacman.conf db -S --noconfirm colony-mirrorlist

installed="$TEST/root/etc/pacman.d/colony-mirrorlist"
[[ -f $installed ]] || fail "colony-mirrorlist did not land at $installed"

echo
echo "==> installed file:"
sed 's/^/    /' "$installed"
echo

echo "==> a database served without its signature"
serve
rm -f "$TEST/served/colony.db.sig" "$TEST/served/colony.db.tar.zst.sig"
# Without this, the refusal below could come from anything at all - a typo in a
# path would do. The same served files, through the stanza minus its SigLevel,
# have to sync: that is the hole the SigLevel closes.
echo "    control, without the stanza's SigLevel:"
pac pacman-nosiglevel.conf db-control -Sy --noconfirm 2>&1 | sed 's/^/    /' \
	|| fail "the control did not sync, so the refusal below would prove nothing"
echo "    through the shipped stanza:"
refused "a database without its signature" pacman.conf db-unsigned

echo "==> a database signed by a key colony-keyring does not vouch for"
mkdir -m 700 "$TEST/foreign"
gpg --homedir "$TEST/foreign" --batch --quiet --passphrase '' \
	--quick-gen-key 'test-repo.sh foreign key <foreign@invalid>' ed25519 sign 1d
serve
gpg --homedir "$TEST/foreign" --batch --quiet --yes --detach-sign --no-armor \
	--output "$TEST/served/colony.db.tar.zst.sig" "$TEST/served/colony.db.tar.zst"
# In the keyring but never signed off on: what pacman would hold after fetching
# an attacker's key from a keyserver. It also keeps pacman from going to look.
gpg --homedir "$TEST/foreign" --export > "$TEST/foreign.gpg"
$SUDO pacman-key --gpgdir "$TEST/gnupg" --add "$TEST/foreign.gpg"
refused "a database signed by a foreign key" pacman.conf db-foreign

echo
echo "PASS - signed database verified, signed package verified, trust established"
echo "       from colony-keyring alone; an unsigned database and one signed by a"
echo "       foreign key were both refused by the shipped [colony] stanza."
