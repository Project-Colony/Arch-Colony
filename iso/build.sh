#!/usr/bin/env bash
# Build an Arch Colony ISO from a profile under iso/.
#
#   ./iso/build.sh            build the "base" profile
#   ./iso/build.sh hyprland   build another profile
#
# COLONY_THEME=family/variant picks the palette (default stellar_blade/lily);
# see generated/themes.json in Project-Colony-Resources for the choices.
#
# Downloads archinstall and themes.json at the commits iso/pins.env names.
#
# Requires the packages in repo/out (run repo/build.sh first) and the Colony key
# in this machine's pacman keyring, since the profile verifies [colony] at its
# strictest.
#
# With COLONY_SIGNING_KEY set, it signs a fresh [colony] database over repo/out,
# the installer's offline firewall database (iso/offline-repo.sh, embedded in
# the image), and then the image with its checksum file. Without it, repo/out
# must already hold a signed colony.db and, in repo/out/offline, the signed
# offline repository, and the image is left unsigned: that is how the release
# workflow runs it, since its build jobs never hold a key and separate jobs sign
# the repositories before and the image after.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PROFILE="${1:-base}"
SRC="$ROOT/iso/$PROFILE"
PKGS="$ROOT/repo/out"
WORK="$ROOT/iso/work"
DEST="$ROOT/iso/out"

KEY="${COLONY_SIGNING_KEY:-}"
# Already root, as in a container: no sudo needed, and none may be installed.
SUDO=sudo
(( EUID == 0 )) && SUDO=

[[ -d $SRC ]] || { echo "no profile at $SRC" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "mkarchiso missing: pacman -S archiso" >&2; exit 1; }

shopt -s nullglob
built=("$PKGS"/*.pkg.tar.zst)
shopt -u nullglob
(( ${#built[@]} )) || { echo "nothing in repo/out - run repo/build.sh first" >&2; exit 1; }

if [[ -n $KEY ]]; then
	echo "==> refreshing the local [colony] database"
	( cd "$PKGS" && rm -f colony.db* colony.files* &&
	  repo-add --sign --key "$KEY" --new --quiet colony.db.tar.zst ./*.pkg.tar.zst )
else
	[[ -f $PKGS/colony.db.tar.zst.sig ]] || {
		echo "COLONY_SIGNING_KEY is not set and repo/out holds no signed colony.db to build from" >&2
		exit 1; }
	echo "==> using the signed [colony] database already in repo/out"
fi

# pacman-key --verify wants a trusted key, not merely a known one: the test
# mkarchiso's pacman applies too, but with a message that says what to do.
if ! $SUDO pacman-key --verify "$PKGS/colony.db.tar.zst.sig" "$PKGS/colony.db.tar.zst" &>/dev/null; then
	cat >&2 <<EOF
The key that signed repo/out/colony.db is not trusted in this machine's pacman
keyring, so the build cannot verify [colony]. Add the Colony key once:

    sudo pacman-key --add packages/colony-keyring/colony.gpg
    sudo pacman-key --lsign-key $(cut -d: -f1 "$ROOT/packages/colony-keyring/colony-trusted")
EOF
	exit 1
fi

echo "==> staging the profile"
# mkarchiso runs as root and leaves a root-owned work tree, which a user-level
# rm cannot remove. Left in place, mkarchiso reuses it and silently reproduces
# the previous image - a rebuild that changes nothing while reporting success.
$SUDO rm -rf "$WORK"
[[ -e $WORK ]] && { echo "could not clear $WORK - refusing to build against a stale work tree" >&2; exit 1; }
mkdir -p "$WORK" "$DEST"
STAGE="$WORK/profile"
cp -r "$SRC" "$STAGE"

# The inputs that do not live in this repository, at the commits iso/pins.env
# pins, so that the same commit of Arch Colony builds the same installer.
INPUTS="$WORK/inputs"
"$ROOT/iso/fetch-inputs.sh" "$INPUTS"

# A file:// URL cannot contain a raw space, and this repository lives under a
# path that has one.
REPO_URL=${PKGS// /%20}
sed -i "s|@COLONY_REPO@|$REPO_URL|g" "$STAGE/pacman.conf"

# Colours come from the token system, never from a file in this repository
# (principe 4). The staged profile's templates are filled in here from
# Project-Colony-Resources' generated artifact - the same artifact every other
# Colony program consumes, rather than a second copy of the palette, fetched at
# the commit iso/pins.env names. A template names palette fields directly
# (@bg_primary@, @accent_blue@, ...), and an unknown name fails the build rather
# than shipping unstyled; see tools/resolve-theme.py. COLONY_THEME=family/variant
# picks another palette.
#
# Only the installer's branding under etc/calamares and the boot menu under
# syslinux. The profile carries archiso's own
# usr/local/share/livecd-sound/asound.conf.in, which the livecd-sound script
# fills in itself at boot; an earlier `**/*.in` here renamed it away, and the
# live medium has had no ALSA configuration since - quietly, since the script
# tolerates the missing file.
shopt -s nullglob globstar
templates=("$STAGE"/airootfs/etc/calamares/**/*.in "$STAGE"/syslinux/*.in)
shopt -u nullglob globstar
if (( ${#templates[@]} )); then
	echo "==> resolving theme tokens"
	python3 "$ROOT/tools/resolve-theme.py" "$INPUTS/themes.json" "${COLONY_THEME:-stellar_blade/lily}" \
		"${templates[@]}" | sed "s|$STAGE/||g"
fi

# The installer's package tree is generated, not committed: it carries every
# package in core and extra, which is a fact about the repositories on the
# day the ISO is built rather than something to keep in git. Desktop and driver
# definitions are derived from archinstall, which is GPL-3.0-only: see the
# licence note in tools/gen-netinstall.py.
if [[ -f "$STAGE/airootfs/etc/calamares/modules/netinstall.conf" ]]; then
	echo "==> generating the installer package tree"
	# Written to /usr/share, not to the path Calamares reads. .zlogin copies it
	# into place only if the user allowed network access at boot; otherwise it
	# installs the offline placeholder instead. Everything on that page is a
	# download, so offering it to someone who declined the network would let them
	# select twenty desktops and reach a green "Finished" with none of them.
	mkdir -p "$STAGE/airootfs/usr/share/colony"
	"$ROOT/tools/gen-netinstall.py" --archinstall "$INPUTS/archinstall" \
		> "$STAGE/airootfs/usr/share/colony/netinstall.yaml"
fi

# The firewall the installer puts on the target, carried on the medium so that an
# offline install gets it too. Files only: nothing installs it on the live
# session, whose network would otherwise sit behind a fail-closed table. See the
# pacman.conf in that directory for how the installer uses it.
OFFLINE="$STAGE/airootfs/usr/share/colony/offline-repo"
if [[ -f $OFFLINE/pacman.conf ]]; then
	if [[ -n $KEY ]]; then
		echo "==> assembling the installer's offline firewall repository"
		"$ROOT/iso/offline-repo.sh" "$OFFLINE"
	else
		echo "==> using the signed offline firewall repository in repo/out/offline"
		db=$PKGS/offline/colony-offline.db
		# The same test as for colony.db above: the installer would refuse it,
		# but only on someone's machine, after partitioning.
		$SUDO pacman-key --verify "$db.sig" "$db" &>/dev/null || {
			echo "repo/out/offline holds no colony-offline.db signed by a trusted key" >&2
			exit 1; }
		cp "$PKGS"/offline/* "$OFFLINE/"
	fi
	printf '    %s on the medium\n' "$(du -sh "$OFFLINE" | cut -f1)"
fi

echo "==> mkarchiso ($PROFILE)"
# A marker to tell this run's image from any older one left in iso/out. Globbing
# *.iso and signing whatever matches would re-sign, and re-publish, images built
# from a tree nobody remembers.
MARKER="$WORK/.build-started"
: > "$MARKER"
$SUDO mkarchiso -v -w "$WORK/work" -o "$DEST" "$STAGE"

shopt -s nullglob
fresh=()
for f in "$DEST"/*.iso; do
	[[ $f -nt $MARKER ]] && fresh+=("$f")
done
shopt -u nullglob
(( ${#fresh[@]} )) || { echo "mkarchiso reported success but produced no image" >&2; exit 1; }

# Next to each image: its checksum, and the package list mkarchiso wrote into
# it, exact versions included, so that what an image carries can be read
# without mounting it and the source of each package traced from it.
shopt -s nullglob
pkglists=("$WORK"/work/iso/*/pkglist.x86_64.txt)
shopt -u nullglob
(( ${#pkglists[@]} == 1 )) || { echo "expected one pkglist.x86_64.txt under $WORK/work/iso" >&2; exit 1; }
for f in "${fresh[@]}"; do
	name=$(basename "$f")
	cp "${pkglists[0]}" "$f.pkglist.txt"
	( cd "$DEST" && sha256sum "$name" > "$name.sha256" )
done

if [[ -z $KEY ]]; then
	echo
	echo "Built, not signed:"
	for f in "${fresh[@]}"; do
		printf '    %-46s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
	done
	exit 0
fi

# Sign the image, and say so in a checksum file signed alongside it.
#
# Every package in [colony] is signed and pacman refuses unsigned ones, which
# makes it odd to hand someone an unsigned ISO - the first artefact they touch,
# the one they write to a USB stick, and the one with no package manager behind
# it to check anything. `sha256sum -c` catches a corrupted download; only the
# signature says the image is ours.
echo
echo "==> signing"
for f in "${fresh[@]}"; do
	name=$(basename "$f")
	gpg --detach-sign --no-armor --local-user "$KEY" --yes "$f"
	gpg --detach-sign --no-armor --local-user "$KEY" --yes "$f.sha256"
	printf '    %-46s %s\n' "$name" "$(du -h "$f" | cut -f1)"
	printf '    %-46s %s\n' "$name.sig" "signature"
	printf '    %-46s %s\n' "$name.sha256" "checksum, signed"
done

echo
echo "Verify, on any machine that trusts the Colony key:"
echo "    gpg --verify $(basename "${fresh[0]}").sig"
echo "    sha256sum -c $(basename "${fresh[0]}").sha256"
