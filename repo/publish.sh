#!/usr/bin/env bash
# Assemble the signed [colony] database and publish it as a GitHub release.
#
# This PUBLISHES. Everything it uploads becomes publicly downloadable and will be
# installed by every Arch Colony machine. Read what is in repo/out/ before running.

set -euo pipefail

ROOT="$(dirname "$(realpath "$0")")/.."
OUT="$ROOT/repo/out"
REPO_NAME=colony
TAG=repo
GH_REPO="${COLONY_GH_REPO:-Project-Colony/Arch-Colony}"

: "${COLONY_SIGNING_KEY:?not set — run repo/genkey.sh first, then export it}"
command -v gh >/dev/null || { echo "gh missing: pacman -S github-cli" >&2; exit 1; }

cd "$OUT"

shopt -s nullglob
pkgs=(*.pkg.tar.zst)
shopt -u nullglob
(( ${#pkgs[@]} )) || { echo "nothing in $OUT — run repo/build.sh first" >&2; exit 1; }

echo "==> building the signed database"
rm -f "$REPO_NAME".db* "$REPO_NAME".files*
repo-add --sign --key "$COLONY_SIGNING_KEY" --new --prevent-downgrade \
	"$REPO_NAME.db.tar.zst" "${pkgs[@]}"

# repo-add leaves colony.db and colony.files as symlinks. Release assets cannot be
# symlinks, and pacman fetches exactly those names, so materialise them.
for link in "$REPO_NAME.db" "$REPO_NAME.files"; do
	[[ -L "$link" ]] || continue
	target=$(readlink "$link")
	rm -f "$link"
	cp -f "$target" "$link"
	[[ -f "$target.sig" ]] && cp -f "$target.sig" "$link.sig"
done

echo "==> the following will be published to $GH_REPO (tag: $TAG)"
ls -1sh -- *.pkg.tar.zst *.sig "$REPO_NAME".db* "$REPO_NAME".files* 2>/dev/null
read -rp "publish? [y/N] " answer
[[ $answer == [yY] ]] || { echo "aborted"; exit 1; }

if ! gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
	gh release create "$TAG" --repo "$GH_REPO" \
		--title "[colony] repository" \
		--notes "Rolling pacman repository for Arch Colony. Assets are replaced in place; there is no per-release history here."
fi

gh release upload "$TAG" --repo "$GH_REPO" --clobber -- \
	*.pkg.tar.zst *.sig "$REPO_NAME".db* "$REPO_NAME".files*

echo
echo "Published. On a test machine:"
echo "  pacman-key --recv-keys $COLONY_SIGNING_KEY && pacman-key --lsign-key $COLONY_SIGNING_KEY"
echo "  add [colony] to pacman.conf, then: pacman -Sy colony-mirrorlist"
