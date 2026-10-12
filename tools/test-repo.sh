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
# trusts are both refused. Only the first refusal depends on the stanza's SigLevel.
#
# Then the installer's offline repository: iso/offline-repo.sh assembles it as
# iso/build.sh does, with colony-mirrorlist standing in for the firewall packages
# CI does not build here, and the pacman.conf the installer uses must install from
# it and refuse it once its database signature is gone.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
OUT="$ROOT/repo/out"
KEYRING="$ROOT/packages/colony-keyring"
STANZA="$ROOT/packages/colony-mirrorlist/colony-repo.conf"

# The key the sandbox trusts, and the one that signs the database it builds.
: "${COLONY_SIGNING_KEY:?not set - see repo/genkey.sh}"
# The public key the sandbox is told to trust. CI holds no Colony key, so it
# signs with a throwaway one and points this at its export.
PUBKEY="${COLONY_PUBKEY:-$KEYRING/colony.gpg}"
# COLONY_PREBUILT_DB=1 tests the signed database repo/out already holds instead
# of building one, which needs no secret key: the release workflow uses it on
# the database it is about to publish.
PREBUILT="${COLONY_PREBUILT_DB:-}"

# Already root, as in a container: no sudo needed, and none may be installed.
SUDO=sudo
(( EUID == 0 )) && SUDO=

shopt -s nullglob
pkgs=("$OUT"/*.pkg.tar.zst)
shopt -u nullglob
(( ${#pkgs[@]} )) || { echo "nothing in repo/out - run repo/build.sh first" >&2; exit 1; }

TEST=$(mktemp -d /tmp/colony-repotest.XXXXXX)
# pacman-key starts a gpg-agent for $TEST/gnupg, gpg one for $TEST/foreign.
# Stop both rather than count on them noticing their home directory is gone.
# errexit holds inside the trap too, so a failed kill must not skip the rm.
trap 'gpgconf --homedir "$TEST/foreign" --kill all 2>/dev/null || :
	$SUDO gpgconf --homedir "$TEST/gnupg" --kill all 2>/dev/null || :
	$SUDO rm -rf "$TEST"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> sandbox: $TEST"
mkdir -p "$TEST"/{root,cache,repo,gnupg}
cp "$OUT"/*.pkg.tar.zst "$OUT"/*.pkg.tar.zst.sig "$TEST/repo/"

if [[ -n $PREBUILT ]]; then
	echo "==> the signed database from repo/out"
	for f in colony.db.tar.zst colony.files.tar.zst; do
		cp "$OUT/$f" "$OUT/$f.sig" "$TEST/repo/" || fail "repo/out has no signed $f"
		# The names pacman fetches, as links the way repo-add leaves them: a
		# case below replaces colony.db.tar.zst.sig and pacman must see that.
		ln -s "$f" "$TEST/repo/${f%.tar.zst}"
		ln -s "$f.sig" "$TEST/repo/${f%.tar.zst}.sig"
	done
else
	echo "==> building the signed database"
	( cd "$TEST/repo" && repo-add --sign --key "$COLONY_SIGNING_KEY" --new --quiet \
		colony.db.tar.zst ./*.pkg.tar.zst )
fi

echo "==> isolated keyring, trusting nothing to start with"
$SUDO pacman-key --gpgdir "$TEST/gnupg" --init
$SUDO pacman-key --gpgdir "$TEST/gnupg" --add "$PUBKEY"
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
# The sandbox root has no shell for colony-mirrorlist.install to run in, and
# pacman would only print an error for it: tools/test-mirrorlist-migration.sh
# tests that scriptlet.
pac pacman.conf db -S --noconfirm --noscriptlet colony-mirrorlist

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
# This refusal is the keyring's, not the stanza's: pacman checks a signature
# that is present under DatabaseOptional too, and wants a trusted key for it.
gpg --homedir "$TEST/foreign" --export > "$TEST/foreign.gpg"
$SUDO pacman-key --gpgdir "$TEST/gnupg" --add "$TEST/foreign.gpg"
refused "a database signed by a foreign key" pacman.conf db-foreign

echo "==> the installer's offline repository"
"$ROOT/iso/offline-repo.sh" "$TEST/offline" colony-mirrorlist
# The installer's own pacman.conf, verbatim except for where its Server points.
server="Server = file://$TEST/offline"
sed "s|^Server = file:///usr/share/colony/offline-repo$|$server|" \
	"$ROOT/iso/install/airootfs/usr/share/colony/offline-repo/pacman.conf" > "$TEST/offline.conf"
grep -qxF "$server" "$TEST/offline.conf" \
	|| fail "the offline pacman.conf no longer serves /usr/share/colony/offline-repo"
# Into the root the first case installed, with its database, as on a target
# that already has packages: the stand-in is reinstalled over itself.
pac offline.conf db -Sy --noconfirm
pac offline.conf db -S --noconfirm --noscriptlet colony-mirrorlist

echo "==> the offline database without its signature"
rm -f "$TEST/offline/colony-offline.db.sig" "$TEST/offline/colony-offline.db.tar.zst.sig"
refused "an unsigned offline database" offline.conf db-offline-unsigned

echo
echo "PASS - signed database verified, signed package verified, trust established"
echo "       from colony-keyring alone; an unsigned database was refused by the"
echo "       SigLevel of the shipped [colony] stanza, and one signed by a foreign"
echo "       key was refused because colony-keyring does not vouch for that key."
echo "       The installer's offline repository installed through its own"
echo "       pacman.conf, and was refused once its database was unsigned."
