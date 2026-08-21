#!/usr/bin/env bash
# Publish a built ISO as a GitHub release.
#
# This PUBLISHES. Everything it uploads becomes publicly downloadable, and an
# ISO is the artefact people write to a USB stick before any package manager
# exists to check anything for them. Read what is in iso/out/ before running.
#
# Separate from repo/publish.sh, and on a separate tag, because the two have
# opposite lifecycles: [colony] is one rolling release whose assets are replaced
# in place, while an image is a dated thing people cite, link to and come back
# for. Overwriting last month's ISO under the same name would break every link
# to it and silently change what a checksum someone wrote down refers to.

set -euo pipefail

ROOT="$(dirname "$(realpath "$0")")/.."
OUT="$ROOT/iso/out"
GH_REPO="${COLONY_GH_REPO:-Project-Colony/Arch-Colony}"

: "${COLONY_SIGNING_KEY:?not set — see repo/genkey.sh}"
command -v gh >/dev/null || { echo "gh missing: pacman -S github-cli" >&2; exit 1; }

ISO="${1:-}"
if [[ -z $ISO ]]; then
	shopt -s nullglob
	candidates=("$OUT"/*.iso)
	shopt -u nullglob
	(( ${#candidates[@]} )) || { echo "no image in $OUT — run iso/build.sh first" >&2; exit 1; }
	if (( ${#candidates[@]} > 1 )); then
		echo "several images in $OUT; name the one to publish:" >&2
		printf '  %s\n' "${candidates[@]##*/}" >&2
		exit 1
	fi
	ISO="${candidates[0]}"
fi
[[ -f $ISO ]] || ISO="$OUT/$ISO"
[[ -f $ISO ]] || { echo "no such image: $ISO" >&2; exit 1; }

NAME=$(basename "$ISO")
# Matched, not sliced. `${NAME#*-}` then `%%-*` reads the date out of
# archcolony-2026.08.21-x86_64.iso and reads "base" out of
# archcolony-base-2026.08.20-x86_64.iso — one edition name is all it takes.
[[ $NAME =~ ([0-9]{4}\.[0-9]{2}\.[0-9]{2}) ]] || {
	echo "cannot read a release date out of '$NAME'" >&2; exit 1; }
DATE="${BASH_REMATCH[1]}"
# One tag per date, editions share it as separate assets.
TAG="iso-$DATE"

assets=("$ISO")
for extra in "$ISO.sig" "$ISO.sha256" "$ISO.sha256.sig"; do
	[[ -f $extra ]] || { echo "missing $extra — rebuild with iso/build.sh, which signs" >&2; exit 1; }
	assets+=("$extra")
done

# The signature is verified here rather than trusted, because the failure this
# catches — publishing an image signed by a key nobody has, or not signed at all
# because gpg-agent quietly declined — is invisible until a user reports it.
echo "==> verifying before upload"
gpg --verify "$ISO.sig" "$ISO" 2>&1 | sed 's/^/    /'
( cd "$OUT" && sha256sum -c "$NAME.sha256" ) | sed 's/^/    /'

# GitHub refuses an asset over 2 GiB. Say so here rather than after a long
# upload: the image has been at 84% of that ceiling and a second edition is
# planned, so this will matter before it is expected to.
size=$(stat -c %s "$ISO")
limit=$((2 * 1024 * 1024 * 1024))
printf '    %s is %.2f GiB, %d%% of the 2 GiB asset ceiling\n' \
	"$NAME" "$(awk -v b="$size" 'BEGIN{printf "%.2f", b/1073741824}')" \
	"$(( size * 100 / limit ))"
(( size < limit )) || {
	echo "too large for a GitHub release asset — object storage is the next step" >&2
	exit 1; }

echo
echo "==> the following will be published to $GH_REPO (tag: $TAG)"
ls -1sh -- "${assets[@]}"
read -rp "publish? [y/N] " answer
[[ $answer == [yY] ]] || { echo "aborted"; exit 1; }

if ! gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
	gh release create "$TAG" --repo "$GH_REPO" \
		--title "Arch Colony $DATE" \
		--notes "Installation image for Arch Colony, $DATE.

Verify before writing it to anything:

    gpg --verify $NAME.sig $NAME
    sha256sum -c $NAME.sha256

The signing key is the one in \`colony-keyring\`; \`sha256sum -c\` catches a
corrupted download, the signature is what says the image is ours."
fi

gh release upload "$TAG" --repo "$GH_REPO" --clobber -- "${assets[@]}"

echo
echo "Published: https://github.com/$GH_REPO/releases/tag/$TAG"
