#!/usr/bin/env bash
# Build an Arch Colony ISO from a profile under iso/.
#
#   ./iso/build.sh            build the "base" profile
#   ./iso/build.sh hyprland   build another profile
#
# COLONY_THEME=family/variant picks the palette (default stellar_blade/lily);
# see Project-Colony-Resources/generated/themes.json for the choices.
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

# Colours come from the token system, never from a file in this repository
# (principe 4). Any *.in under the staged profile is filled in here from
# Project-Colony-Resources' generated artifact — the same artifact every other
# Colony program consumes, rather than a second copy of the palette. A template
# names palette fields directly (@bg_primary@, @accent_blue@, ...), and an
# unknown name fails the build rather than shipping unstyled; see
# tools/resolve-theme.py. COLONY_THEME=family/variant picks another palette.
#
# Only under etc/calamares. The profile carries archiso's own
# usr/local/share/livecd-sound/asound.conf.in, which the livecd-sound script
# fills in itself at boot; an earlier `**/*.in` here renamed it away, and the
# live medium has had no ALSA configuration since — quietly, since the script
# tolerates the missing file.
shopt -s nullglob globstar
templates=("$STAGE"/airootfs/etc/calamares/**/*.in)
shopt -u nullglob globstar
if (( ${#templates[@]} )); then
	RESOURCES="${COLONY_RESOURCES:-$ROOT/../Project-Colony-Resources}"
	THEMES="$RESOURCES/generated/themes.json"
	[[ -f $THEMES ]] || {
		echo "cannot resolve theme tokens: $THEMES not found." >&2
		echo "Set COLONY_RESOURCES to the Project-Colony-Resources checkout." >&2
		exit 1
	}
	echo "==> resolving theme tokens from $THEMES"
	python3 "$ROOT/tools/resolve-theme.py" "$THEMES" "${COLONY_THEME:-stellar_blade/lily}" \
		"${templates[@]}" | sed "s|$STAGE/||g"
fi

# The installer's package tree is generated, not committed: it carries every
# package in core and extra, which is a fact about the repositories on the
# day the ISO is built rather than something to keep in git. Desktop and driver
# definitions are derived from archinstall (GPL-3.0-or-later, same as us).
if [[ -f "$STAGE/airootfs/etc/calamares/modules/netinstall.conf" ]]; then
	ARCHINSTALL="${COLONY_ARCHINSTALL:-$WORK/archinstall}"
	if [[ ! -d $ARCHINSTALL ]]; then
		echo "==> fetching archinstall (desktop and driver definitions)"
		git clone -q --depth 1 https://github.com/archlinux/archinstall.git "$ARCHINSTALL" \
			|| { echo "cannot fetch archinstall; set COLONY_ARCHINSTALL to a checkout" >&2; exit 1; }
	fi
	echo "==> generating the installer package tree"
	# Written to /usr/share, not to the path Calamares reads. .zlogin copies it
	# into place only if the user allowed network access at boot; otherwise it
	# installs the offline placeholder instead. Everything on that page is a
	# download, so offering it to someone who declined the network would let them
	# select twenty desktops and reach a green "Finished" with none of them.
	mkdir -p "$STAGE/airootfs/usr/share/colony"
	"$ROOT/tools/gen-netinstall.py" --archinstall "$ARCHINSTALL" \
		> "$STAGE/airootfs/usr/share/colony/netinstall.yaml"
fi

echo "==> mkarchiso ($PROFILE)"
# A marker to tell this run's image from any older one left in iso/out. Globbing
# *.iso and signing whatever matches would re-sign, and re-publish, images built
# from a tree nobody remembers.
MARKER="$WORK/.build-started"
: > "$MARKER"
sudo mkarchiso -v -w "$WORK/work" -o "$DEST" "$STAGE"

shopt -s nullglob
fresh=()
for f in "$DEST"/*.iso; do
	[[ $f -nt $MARKER ]] && fresh+=("$f")
done
shopt -u nullglob
(( ${#fresh[@]} )) || { echo "mkarchiso reported success but produced no image" >&2; exit 1; }

# Sign the image, and say so in a checksum file signed alongside it.
#
# Every package in [colony] is signed and pacman refuses unsigned ones, which
# makes it odd to hand someone an unsigned ISO — the first artefact they touch,
# the one they write to a USB stick, and the one with no package manager behind
# it to check anything. `sha256sum -c` catches a corrupted download; only the
# signature says the image is ours.
echo
echo "==> signing"
for f in "${fresh[@]}"; do
	name=$(basename "$f")
	( cd "$DEST" && sha256sum "$name" > "$name.sha256" )
	gpg --detach-sign --no-armor --local-user "$COLONY_SIGNING_KEY" --yes "$f"
	gpg --detach-sign --no-armor --local-user "$COLONY_SIGNING_KEY" --yes "$f.sha256"
	printf '    %-46s %s\n' "$name" "$(du -h "$f" | cut -f1)"
	printf '    %-46s %s\n' "$name.sig" "signature"
	printf '    %-46s %s\n' "$name.sha256" "checksum, signed"
done

echo
echo "Verify, on any machine that trusts the Colony key:"
echo "    gpg --verify $(basename "${fresh[0]}").sig"
echo "    sha256sum -c $(basename "${fresh[0]}").sha256"
